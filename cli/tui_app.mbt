///|
fn normalize_rel_path(path : String) -> String {
  let slash = path.replace_all(old="\\", new="/").trim().to_owned()
  let trimmed = if slash.has_prefix("./") {
    slash[2:].to_owned()
  } else {
    slash
  }
  if trimmed == "." {
    ""
  } else if trimmed.has_suffix("/") {
    trimmed[:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
}

///|
/// Determine which units have changed files by matching each changed path to
/// the most specific (longest root prefix) unit, ignoring changeset metadata.
fn compute_changed_flags(
  units : Array[@model.ReleaseUnit],
  changed_files : Array[String],
  changeset_directory~ : String = ".changeset",
) -> Array[Bool] {
  let flags = Array::make(units.length(), false)
  if changed_files.is_empty() || units.is_empty() {
    return flags
  }
  let cs_dir = normalize_rel_path(changeset_directory)
  let unit_roots = units.map(u => normalize_rel_path(u.root))
  for raw_file in changed_files {
    let file = normalize_rel_path(raw_file)
    if file == "" ||
      file == ".moonset" ||
      file.has_prefix(".moonset/") ||
      (cs_dir != "" && (file == cs_dir || file.has_prefix(cs_dir + "/"))) {
      continue
    }
    let mut best_len : Int32 = -1
    let mut matched : Array[Int32] = []
    for i, uroot in unit_roots {
      let hits = if uroot == "" {
        true
      } else {
        file == uroot || file.has_prefix(uroot + "/")
      }
      if hits {
        let root_len = uroot.length()
        if root_len > best_len {
          best_len = root_len
          matched = [i]
        } else if root_len == best_len {
          matched.push(i)
        }
      }
    }
    for idx in matched {
      flags[idx] = true
    }
  }
  flags
}

///|
fn sorted_units(
  units : Array[@model.ReleaseUnit],
  changed_files : Array[String],
  changeset_directory~ : String = ".changeset",
  is_mixed~ : Bool = false,
) -> (Array[@model.ReleaseUnit], Array[Bool]) {
  let raw_flags = compute_changed_flags(
    units,
    changed_files,
    changeset_directory~,
  )
  let changed_group : Array[@model.ReleaseUnit] = []
  let unchanged_group : Array[@model.ReleaseUnit] = []
  for i, unit in units {
    if raw_flags[i] {
      changed_group.push(unit)
    } else {
      unchanged_group.push(unit)
    }
  }
  let key_fn = (u : @model.ReleaseUnit) => {
    if is_mixed {
      u.id
    } else {
      u.native_name
    }
  }
  changed_group.sort_by((a, b) => key_fn(a).compare(key_fn(b)))
  unchanged_group.sort_by((a, b) => key_fn(a).compare(key_fn(b)))
  let ordered : Array[@model.ReleaseUnit] = []
  let flags : Array[Bool] = []
  for unit in changed_group {
    ordered.push(unit)
    flags.push(true)
  }
  for unit in unchanged_group {
    ordered.push(unit)
    flags.push(false)
  }
  (ordered, flags)
}

///|
async fn git_best_effort(cwd : String, args : Array[String]) -> String? {
  let out = @process.Cmd("git", args, cwd~).run(
    stdin=Empty,
    stdout=Collect,
    stderr=Collect,
  ) catch {
    _ => return None
  }
  if out.exit_code != 0 {
    None
  } else {
    Some(@utf8.decode_lossy(out.stdout_binary()))
  }
}

///|
/// Best-effort changed-file detection for interactive `moonset add` (combining
/// branch commits against `--since` or `baseBranch` with working-tree edits and
/// untracked files, matching `@changesets/cli` behavior). Never fails.
async fn detect_add_changed_files(
  root : String,
  base_branch : String,
  explicit_since : String?,
) -> Array[String] {
  guard git_best_effort(root, ["rev-parse", "--show-toplevel"]) is Some(raw_top) else {
    return []
  }
  let top = raw_top.trim().to_owned()
  if top == "" {
    return []
  }
  let git_root = @fs.realpath(top) catch { _ => top }
  let norm_root = @fs.realpath(root) catch { _ => root }
  let domain_prefix = normalize_rel_path(
    @path.Path(norm_root).relative(base=@path.Path(git_root)).to_string(),
  )
  let candidates : Array[String] = match explicit_since {
    Some(r) if r.trim() != "" => [r.trim().to_owned()]
    _ =>
      if base_branch.trim() != "" {
        [
          base_branch.trim().to_owned(),
          "origin/" + base_branch.trim().to_owned(),
        ]
      } else {
        []
      }
  }
  let mut diff_base : String? = None
  for candidate in candidates {
    match
      git_best_effort(git_root, [
        "rev-parse",
        "--verify",
        "--end-of-options",
        candidate + "^{commit}",
      ]) {
      Some(ref_sha) if ref_sha.trim() != "" =>
        match
          git_best_effort(git_root, [
            "merge-base",
            ref_sha.trim().to_owned(),
            "HEAD",
          ]) {
          Some(mb) if mb.trim() != "" => {
            diff_base = Some(mb.trim().to_owned())
            break
          }
          _ => ()
        }
      _ => ()
    }
  }
  let raw_paths : Array[String] = []
  let diff_out = match diff_base {
    Some(base) =>
      git_best_effort(git_root, ["diff", "--name-only", "-z", base, "--"])
    None =>
      git_best_effort(git_root, ["diff", "--name-only", "-z", "HEAD", "--"])
  }
  if diff_out is Some(text) {
    for entry in text.split("\u{0000}") {
      let item = entry.to_owned()
      if item != "" {
        raw_paths.push(item)
      }
    }
  }
  if git_best_effort(git_root, [
      "ls-files", "--others", "--exclude-standard", "-z",
    ])
    is Some(untracked) {
    for entry in untracked.split("\u{0000}") {
      let item = entry.to_owned()
      if item != "" {
        raw_paths.push(item)
      }
    }
  }
  let changed : Array[String] = []
  for raw in raw_paths {
    let path = normalize_rel_path(raw)
    if path == "" {
      continue
    }
    let rel = if domain_prefix == "" {
      Some(path)
    } else if path.has_prefix(domain_prefix + "/") {
      Some(path[domain_prefix.length() + 1:].to_owned())
    } else {
      None
    }
    if rel is Some(domain_path) && !changed.contains(domain_path) {
      changed.push(domain_path)
    }
  }
  changed
}

///|
fn is_pre_one_zero_version(version : String) -> Bool {
  let v = version.trim().to_owned()
  let clean = if v.has_prefix("v") { v[1:].to_owned() } else { v }
  clean.has_prefix("0.")
}

///|
fn summary_preview(summary : String) -> String {
  let first_line = summary
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .next()
    .map(x => x.trim().to_owned())
    .unwrap_or("")
  let clipped = truncate_visual(first_line, 72)
  if summary.contains("\n") && !clipped.has_suffix("...") {
    clipped + " ..."
  } else {
    clipped
  }
}

///|
fn confirm_first_major_release(
  render_state : TuiRenderState,
  display_name : String,
  color : Bool,
) -> Bool? {
  let warn_lines = [
    "The " +
    style_red("major", color) +
    " version of " +
    style_blue(display_name, color) +
    " will be its " +
    style_red("first major release", color) +
    " (1.0.0).",
    "If you are unsure if this is correct, contact the package's maintainers " +
    style_red("before committing this changeset", color) +
    ".",
  ]
  tui_print_static(
    render_state,
    render_note_box(
      "IMPORTANT",
      warn_lines,
      title_yellow=true,
      body_white=true,
      with_guide=true,
      columns=tty_cols(),
      color~,
    ),
  )
  tui_ask_confirm(
    render_state,
    "Are you sure you want to release the " +
    style_red("first major version", color) +
    " of " +
    style_blue(display_name, color) +
    "?",
    initial_value=true,
    with_guide=true,
    color~,
  )
}

///|
/// Interactive TUI for `moonset add` replicating `@changesets/cli` v3.0.3 (`@clack/prompts`).
async fn interactive_add(
  options : Options,
  loaded : @workspace.LoadedWorkspace,
) -> Int32 {
  let color = terminal_color_enabled(options.no_color, false)
  let ignored_ids = @engine.resolve_ignored_units(
    loaded.snapshot.config,
    loaded.snapshot.units,
  )
  let eligible_units = loaded.snapshot.units.filter(unit => {
    !ignored_ids.contains(unit.id) &&
    unit.version is Some(_) &&
    (
      unit.visibility != @model.Private ||
      loaded.snapshot.config.private_packages.version
    )
  })
  if eligible_units.is_empty() {
    raise @model.Invalid(
      @model.diagnostic("empty-workspace", "No versionable packages found"),
    )
  }
  let is_mixed = loaded.snapshot.config.is_mixed()
  let detected_changed = if loaded.snapshot.changed_files.is_empty() {
    detect_add_changed_files(
      loaded.snapshot.root,
      loaded.snapshot.config.base_branch,
      options.since,
    )
  } else {
    loaded.snapshot.changed_files
  }
  let (ordered_units, changed_flags) = sorted_units(
    eligible_units,
    detected_changed,
    changeset_directory=loaded.changeset_directory,
    is_mixed~,
  )
  let unit_ids = ordered_units.map(u => u.id)
  let display_names = ordered_units.map(u => {
    if is_mixed {
      u.id
    } else {
      u.native_name
    }
  })
  let versions = ordered_units.map(u => u.version.unwrap_or("0.0.0"))
  let pkg_select_labels = ordered_units.mapi((i, u) => {
    let mut label = display_names[i]
    if u.visibility == @model.Private {
      label = label + " (private)"
    }
    if is_mixed && !u.publish {
      label = label + " [no-publish]"
    }
    label
  })
  let pkg_ver_labels = ordered_units.mapi((i, _) => {
    style_bold(display_names[i], color) + "@" + style_bold(versions[i], color)
  })
  let pkg_ver_plain = ordered_units.mapi((i, _) => {
    display_names[i] + "@" + versions[i]
  })
  let has_editor = parse_editor_command() is Some(_)
  let render_state = TuiRenderState::new()

  tui_print_static(
    render_state,
    render_clack_intro(
      "🌙 moonset v" + cli_version(),
      with_guide=true,
      color~,
    ),
  )

  tui_begin(render_state)
  defer tui_cleanup(render_state)

  let chosen_indices : Array[Int32] = if ordered_units.length() == 1 {
    [0]
  } else {
    let changed_indices : Array[Int32] = []
    let unchanged_indices : Array[Int32] = []
    for i, changed in changed_flags {
      if changed {
        changed_indices.push(i)
      } else {
        unchanged_indices.push(i)
      }
    }
    let groups : Array[(String, Array[Int32])] = []
    if !changed_indices.is_empty() {
      groups.push(("changed packages", changed_indices))
    }
    if !unchanged_indices.is_empty() {
      groups.push(("unchanged packages", unchanged_indices))
    }
    match
      tui_ask_group_multiselect(
        render_state,
        "Which packages were affected by the changes you made?",
        groups,
        pkg_select_labels,
        submitted_names=display_names,
        required=true,
        with_guide=true,
        color~,
      ) {
      Some(indices) => {
        let sorted = indices.copy()
        sorted.sort_by((a, b) => display_names[a].compare(display_names[b]))
        sorted
      }
      None => return 130
    }
  }
  if chosen_indices.is_empty() {
    tui_clear_frame(render_state)
    return 2
  }

  let selected : Array[@model.Change] = []
  let selected_display : Array[(String, @model.Bump)] = []

  if ordered_units.length() == 1 {
    let bump_choices = [
      "patch " + style_semver_hint("patch", color),
      "minor " + style_semver_hint("minor", color),
      "major " + style_semver_hint("major", color),
    ]
    let bump_submitted = ["patch", "minor", "major"]
    let mut cursor : Int32 = 0
    let mut chosen_bump : @model.Bump? = None
    while chosen_bump is None {
      match
        tui_ask_select(
          render_state,
          "What kind of change is this for " +
          style_blue(display_names[0], color) +
          "? " +
          style_gray("(current version is " + versions[0] + ")", color),
          bump_choices,
          submitted_labels=bump_submitted,
          initial_cursor=cursor,
          with_guide=true,
          color~,
        ) {
        None => return 130
        Some(picked) => {
          cursor = picked
          let candidate = match picked {
            0 => @model.Patch
            1 => @model.Minor
            _ => @model.Major
          }
          if candidate == @model.Major && is_pre_one_zero_version(versions[0]) {
            match
              confirm_first_major_release(render_state, display_names[0], color) {
              None => return 130
              Some(true) => chosen_bump = Some(@model.Major)
              Some(false) => cursor = 0
            }
          } else {
            chosen_bump = Some(candidate)
          }
        }
      }
    }
    let bump = chosen_bump.unwrap()
    selected.push({ unit_id: unit_ids[0], bump, })
    selected_display.push((display_names[0], bump))
  } else {
    let mut remaining = chosen_indices.copy()
    let major_indices : Array[Int32] = []
    let minor_indices : Array[Int32] = []

    match
      tui_ask_group_multiselect(
        render_state,
        style_bold(
          "Which packages should have a " +
          style_red("major", color) +
          " " +
          style_semver_hint("major", color) +
          " bump?",
          color,
        ),
        [("all packages", remaining)],
        pkg_ver_labels,
        submitted_names=pkg_ver_plain,
        required=false,
        with_guide=true,
        color~,
      ) {
      None => return 130
      Some(major_selected) =>
        for index in major_selected {
          let approved = if is_pre_one_zero_version(versions[index]) {
            match
              confirm_first_major_release(
                render_state,
                display_names[index],
                color,
              ) {
              None => return 130
              Some(ok) => ok
            }
          } else {
            true
          }
          if approved {
            major_indices.push(index)
          }
        }
    }
    remaining = remaining.filter(index => !major_indices.contains(index))

    if !remaining.is_empty() {
      match
        tui_ask_group_multiselect(
          render_state,
          style_bold(
            "Which packages should have a " +
            style_green("minor", color) +
            " " +
            style_semver_hint("minor", color) +
            " bump?",
            color,
          ),
          [("all packages", remaining)],
          pkg_ver_labels,
          submitted_names=pkg_ver_plain,
          required=false,
          with_guide=true,
          color~,
        ) {
        None => return 130
        Some(minor_selected) =>
          for index in minor_selected {
            minor_indices.push(index)
          }
      }
      remaining = remaining.filter(index => !minor_indices.contains(index))
    }

    if !remaining.is_empty() {
      let patch_list = remaining.map(i => pkg_ver_labels[i]).join(", ")
      tui_print_static(
        render_state,
        render_clack_log(
          "info",
          [
            "The following packages will be " +
            style_blue("patch", color) +
            " " +
            style_semver_hint("patch", color) +
            " bumped:",
            style_gray(patch_list, color),
          ],
          with_guide=true,
          color~,
        ),
      )
    }

    let staged_changes = assign_bump_stages(
      unit_ids, chosen_indices, major_indices, minor_indices,
    )
    for i, change in staged_changes {
      selected.push(change)
      let idx = chosen_indices[i]
      selected_display.push((display_names[idx], change.bump))
    }
  }

  let final_summary = match options.summary {
    Some(pre_summary) if pre_summary.trim() != "" =>
      pre_summary.trim().to_owned()
    _ => {
      let mut summary_text = ""
      let placeholder = if has_editor {
        "  (submit nothing to open an external editor)"
      } else {
        ""
      }
      match
        tui_ask_text(
          render_state,
          "Please enter a summary for this change (this will be in the changelogs).",
          placeholder~,
          not_empty=!has_editor,
          allow_ctrl_e=has_editor,
          allow_empty_submit=has_editor,
          with_guide=true,
          color~,
        ) {
        TextCancelled => return 130
        TextOpenEditor(draft) =>
          match edit_summary_in_editor(draft, render_state) {
            EditorResult(edited) => summary_text = edited
            EditorEmpty =>
              match
                tui_ask_text(
                  render_state,
                  "Did not find a summary in the edited file. Please enter one:",
                  not_empty=true,
                  with_guide=true,
                  color~,
                ) {
                TextSubmitted(s) => summary_text = s.trim().to_owned()
                _ => return 130
              }
            EditorError =>
              match
                tui_ask_text(
                  render_state,
                  style_red(
                    "An error happened using external editor. Please type your summary here:",
                    color,
                  ),
                  not_empty=true,
                  with_guide=true,
                  color~,
                ) {
                TextSubmitted(s) => summary_text = s.trim().to_owned()
                _ => return 130
              }
          }
        TextSubmitted(entered) =>
          if entered.trim() != "" {
            summary_text = entered.trim().to_owned()
          } else {
            match edit_summary_in_editor("", render_state) {
              EditorResult(edited) => summary_text = edited
              EditorEmpty =>
                match
                  tui_ask_text(
                    render_state,
                    "Did not find a summary in the edited file. Please enter one:",
                    not_empty=true,
                    with_guide=true,
                    color~,
                  ) {
                  TextSubmitted(s) => summary_text = s.trim().to_owned()
                  _ => return 130
                }
              EditorError =>
                match
                  tui_ask_text(
                    render_state,
                    style_red(
                      "An error happened using external editor. Please type your summary here:",
                      color,
                    ),
                    not_empty=true,
                    with_guide=true,
                    color~,
                  ) {
                  TextSubmitted(s) => summary_text = s.trim().to_owned()
                  _ => return 130
                }
            }
          }
      }
      summary_text
    }
  }

  let major_names : Array[String] = []
  let minor_names : Array[String] = []
  let patch_names : Array[String] = []
  for item in selected_display {
    let (name, bump) = item
    match bump {
      @model.Major => major_names.push(name)
      @model.Minor => minor_names.push(name)
      @model.Patch => patch_names.push(name)
      @model.None => ()
    }
  }
  tui_print_static(
    render_state,
    render_changeset_summary(
      major=major_names,
      minor=minor_names,
      patch=patch_names,
      with_guide=true,
      color~,
    ),
  )
  if ordered_units.length() > 1 {
    tui_print_static(
      render_state,
      render_note_box(
        "NOTE",
        [
          "All packages that depend on these whose required versions will be incompatible will also be " +
          style_blue("patch", color) +
          " bumped when this changeset is applied.",
        ],
        with_guide=true,
        columns=tty_cols(),
        color~,
      ),
    )
  }

  // Restore cooked terminal mode & cursor BEFORE file I/O, external formatters,
  // or git commit hooks run.
  tui_cleanup(render_state)

  let text = @engine.format_changeset(@model.ChangesetDraft::{
    releases: selected,
    summary: final_summary,
  })
  let (_, written) = write_unique_changeset(
    loaded.snapshot.root,
    loaded.changeset_directory,
    options.id,
    text,
  )
  let rel_written = @path.Path(written)
    .relative(base=@path.Path(loaded.snapshot.root))
    .to_string()
    .replace_all(old="\\", new="/")
  ignore(
    @executor.format_files(
      loaded.snapshot.root,
      loaded.snapshot.config,
      [rel_written],
      no_format=options.no_format,
    ),
  )
  let mut committed = false
  if !options.no_commit &&
    (
      loaded.snapshot.config.commit.mode == @model.CommitMode::Add ||
      loaded.snapshot.config.commit.mode == @model.CommitMode::Both
    ) {
    committed = @executor.commit_changes(
      loaded.snapshot.root,
      [rel_written],
      loaded.snapshot.config.commit.add_message,
    )
  }
  if options.open_editor {
    ignore(open_in_external_editor(written))
  }
  if !options.quiet {
    let has_major = !major_names.is_empty()
    if has_major {
      tui_print_static(
        render_state,
        render_note_box(
          "IMPORTANT",
          [
            "This Changeset includes a major change and we STRONGLY recommend adding more information to the changeset:",
            "  WHAT the breaking change is", "  WHY the change was made", "  HOW a consumer should update their code",
          ],
          title_yellow=true,
          body_white=true,
          with_guide=true,
          columns=tty_cols(),
          color~,
        ),
      )
    }
    let rel_from_cwd = @path.Path(written)
      .relative(base=@path.Path(options.cwd))
      .to_string()
    let final_lines : Array[String] = [
      style_green(
        if committed {
          "Changeset added and committed!"
        } else {
          "Changeset added - you can now commit it!"
        },
        color,
      ),
    ]
    if !has_major {
      final_lines.push(
        style_green(
          "If you want to modify or expand on the changeset summary, you can find it here:",
          color,
        ),
      )
    }
    final_lines.push(style_blue(rel_from_cwd, color))
    tui_print_static(
      render_state,
      render_clack_log(
        "success",
        final_lines,
        with_guide=true,
        trailing_bar=false,
        color~,
      ),
    )
  }
  0
}
