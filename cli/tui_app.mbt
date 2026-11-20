///|
/// Split `$VISUAL` / `$EDITOR` into executable + args without invoking a shell (`SEC-001`).
fn parse_editor_command() -> (String, Array[String])? {
  let raw = match @env.get_env_var("VISUAL") {
    Some(v) if v.trim() != "" => v.trim().to_owned()
    _ =>
      match @env.get_env_var("EDITOR") {
        Some(v) if v.trim() != "" => v.trim().to_owned()
        _ => return None
      }
  }
  let parts : Array[String] = []
  let current = StringBuilder()
  let mut in_single = false
  let mut in_double = false
  for ch in raw.to_array() {
    if ch == '\'' && !in_double {
      in_single = !in_single
    } else if ch == '"' && !in_single {
      in_double = !in_double
    } else if (ch == ' ' || ch == '\t') && !in_single && !in_double {
      let token = current.to_string()
      if token != "" {
        parts.push(token)
        current.reset()
      }
    } else {
      current.write_char(ch)
    }
  }
  let tail = current.to_string()
  if tail != "" {
    parts.push(tail)
  }
  if parts.is_empty() {
    None
  } else {
    Some((parts[0], parts[1:].to_owned()))
  }
}

///|
/// Launch `$VISUAL`/`$EDITOR` on `file_path` via parameterized argv (never a shell).
async fn open_in_external_editor(file_path : String) -> Bool {
  guard parse_editor_command() is Some((program, base_args)) else {
    return false
  }
  let args = base_args + [file_path]
  let out = @shell.Cmd(program, args).output() catch { _ => return false }
  out.exit_code() == 0
}

///|
/// Open an external editor to author a multi-line changeset summary.
async fn edit_summary_in_editor(
  initial : String,
  render_state : TuiRenderState,
) -> String? {
  guard parse_editor_command() is Some(_) else { return None }
  let tmp = @fs.tmpdir(prefix="moonset-summary-") catch { _ => return None }
  defer (@fs.rmdir(tmp, recursive=true) catch { _ => () })
  let draft_path = @path.Path(tmp).join(@path.Path("SUMMARY.md")).to_string()
  let header = if initial.trim() != "" {
    initial + "\n"
  } else {
    "\n# Write your changeset summary above. Lines starting with '#' are ignored.\n"
  }
  @fs.write_text(draft_path, header) catch {
    _ => return None
  }
  tui_clear_frame(render_state)
  tui_cleanup(render_state)
  let ok = open_in_external_editor(draft_path)
  tui_begin(render_state)
  if !ok {
    return None
  }
  let raw = @fs.read_text(draft_path) catch { _ => return None }
  let kept = raw
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .filter(line => !line.trim().has_prefix("#"))
    .map(line => line.to_owned())
    .collect()
    .join("\n")
    .trim()
    .to_owned()
  if kept == "" {
    None
  } else {
    Some(kept)
  }
}

///|
fn stage_visible_limit() -> Int32 {
  let rows = tty_rows() - 9
  if rows < 2 {
    2
  } else if rows > 16 {
    16
  } else {
    rows
  }
}

///|
fn tui_choose_indices(
  render_state : TuiRenderState,
  title : String,
  candidates : Array[Int32],
  all_labels : Array[String],
  all_versions : Array[String],
  all_changed_flags : Array[Bool],
  all_publish_flags : Array[Bool],
  color : Bool,
  allow_empty~ : Bool = false,
) -> Array[Int32]? {
  if candidates.is_empty() {
    return Some([])
  }
  let labels : Array[String] = []
  let versions : Array[String] = []
  let changed_flags : Array[Bool] = []
  let publish_flags : Array[Bool] = []
  for index in candidates {
    labels.push(all_labels[index])
    versions.push(all_versions[index])
    if !all_changed_flags.is_empty() {
      changed_flags.push(all_changed_flags.get(index).unwrap_or(false))
    }
    if !all_publish_flags.is_empty() {
      publish_flags.push(all_publish_flags.get(index).unwrap_or(true))
    }
  }
  let mut state = SelectState::new(candidates.length())
  let mut hint = ""
  while !state.cancelled && !state.confirmed {
    let prompt = render_package_page(
      labels,
      versions,
      state,
      changed_flags~,
      publish_flags~,
      max_visible=stage_visible_limit(),
      color~,
      title~,
      allow_empty~,
      hint~,
    )
    tui_render_screen(render_state, prompt)
    let key = tui_read_key()
    let next = reduce_select_stage(state, key, allow_empty~)
    if key == Enter && !next.confirmed && !allow_empty {
      hint = "Select at least one package with Space"
    } else if key != Unknown {
      hint = ""
    }
    state = next
  }
  if state.cancelled {
    return None
  }
  let selected : Array[Int32] = []
  for i, value in state.selected {
    if value {
      selected.push(candidates[i])
    }
  }
  Some(selected)
}

///|
/// Confirm a `0.x -> 1.0.0` major release. Returns `None` on cancel (`Esc`/`Ctrl+C`),
/// `Some(true)` on yes, `Some(false)` on no.
fn tui_confirm_zero_major(
  render_state : TuiRenderState,
  unit_id : String,
  version : String,
  color : Bool,
) -> Bool? {
  let mut cursor : Int32 = 0
  for ;; {
    let prompt = render_zero_major_confirm(unit_id, version, cursor, color~)
    tui_render_screen(render_state, prompt)
    let key = tui_read_key()
    match key {
      Char("y") | Char("Y") => return Some(true)
      Char("n") | Char("N") => return Some(false)
      _ => {
        let (next_cursor, accepted, cancelled) = reduce_choice(cursor, 2, key)
        cursor = next_cursor
        if cancelled {
          return None
        }
        if accepted {
          return Some(cursor == 1)
        }
      }
    }
  }
}

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
  changed_group.sort_by((a, b) => a.id.compare(b.id))
  unchanged_group.sort_by((a, b) => a.id.compare(b.id))
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
  let out = @shell.Cmd("git", args, cwd~).output() catch { _ => return None }
  if out.exit_code() != 0 {
    None
  } else {
    Some(out.stdout())
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
  version.has_prefix("0.")
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
/// Interactive TUI for `moonset add` powered by our built-in UTF-8 native TTY stub.
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
    !ignored_ids.contains(unit.id)
  })
  if eligible_units.is_empty() {
    raise @model.Invalid(
      @model.diagnostic(
        "empty-workspace", "No selectable packages in workspace",
      ),
    )
  }
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
  )
  let labels = ordered_units.map(unit => unit.id)
  let versions = ordered_units.map(unit => unit.version.unwrap_or("unversioned"))
  let publish_flags = ordered_units.map(unit => unit.publish)
  let candidates : Array[Int32] = []
  for i in 0..<ordered_units.length() {
    candidates.push(i)
  }
  let has_editor = parse_editor_command() is Some(_)
  let render_state = TuiRenderState::new()

  tui_begin(render_state)
  defer tui_cleanup(render_state)

  let chosen_indices : Array[Int32] = if ordered_units.length() == 1 {
    [0]
  } else {
    match
      tui_choose_indices(
        render_state, "? Which packages would you like to include?", candidates,
        labels, versions, changed_flags, publish_flags, color,
      ) {
      Some(indices) => indices
      None => {
        tui_commit_line(render_state, format_cancelled_step(color~))
        return 130
      }
    }
  }
  if chosen_indices.is_empty() {
    tui_clear_frame(render_state)
    return 2
  }
  tui_commit_line(
    render_state,
    format_completed_step(
      "Affected packages: " +
      chosen_indices.map(i => style_pkg(labels[i], color)).join(", "),
      color~,
    ),
  )

  let selected : Array[@model.Change] = []
  if ordered_units.length() == 1 {
    let choices = ["patch", "minor", "major"]
    let mut cursor : Int32 = 0
    let mut chosen_bump : @model.Bump? = None
    while chosen_bump is None {
      let prompt = render_bump_page(
        labels[0],
        versions[0],
        cursor,
        choices~,
        color~,
      )
      tui_render_screen(render_state, prompt)
      let (next_cursor, accepted, cancelled) = reduce_choice(
        cursor,
        choices.length(),
        tui_read_key(),
      )
      cursor = next_cursor
      if cancelled {
        tui_commit_line(render_state, format_cancelled_step(color~))
        return 130
      }
      if accepted {
        let candidate = match cursor {
          0 => @model.Patch
          1 => @model.Minor
          _ => @model.Major
        }
        if candidate == @model.Major && is_pre_one_zero_version(versions[0]) {
          match
            tui_confirm_zero_major(render_state, labels[0], versions[0], color) {
            None => {
              tui_commit_line(render_state, format_cancelled_step(color~))
              return 130
            }
            Some(true) => chosen_bump = Some(@model.Major)
            Some(false) => cursor = 1 // Let user pick minor or patch instead
          }
        } else {
          chosen_bump = Some(candidate)
        }
      }
    }
    let bump = chosen_bump.unwrap()
    selected.push({ unit_id: labels[0], bump, })
    tui_commit_line(
      render_state,
      format_completed_step(
        style_bump(bump.text(), color) +
        ": " +
        style_pkg(labels[0], color) +
        style_dim("@" + versions[0], color),
        color~,
      ),
    )
  } else {
    let mut remaining = chosen_indices.copy()
    let major_indices : Array[Int32] = []
    let minor_indices : Array[Int32] = []
    match
      tui_choose_indices(
        render_state,
        "? Which packages should have a major bump?",
        remaining,
        labels,
        versions,
        [],
        [],
        color,
        allow_empty=true,
      ) {
      Some(major_selected) => {
        let major_packages : Array[String] = []
        for index in major_selected {
          let approved = if is_pre_one_zero_version(versions[index]) {
            match
              tui_confirm_zero_major(
                render_state,
                labels[index],
                versions[index],
                color,
              ) {
              None => {
                tui_commit_line(render_state, format_cancelled_step(color~))
                return 130
              }
              Some(ok) => ok
            }
          } else {
            true
          }
          if approved {
            major_indices.push(index)
            major_packages.push(labels[index])
          }
        }
        remaining = remaining.filter(index => !major_indices.contains(index))
        let major_summary = if major_packages.is_empty() {
          style_dim("none", color)
        } else {
          major_packages.map(p => style_pkg(p, color)).join(", ")
        }
        tui_commit_line(
          render_state,
          format_completed_step(
            style_bump("major", color) + ": " + major_summary,
            color~,
          ),
        )
      }
      None => {
        tui_commit_line(render_state, format_cancelled_step(color~))
        return 130
      }
    }

    if !remaining.is_empty() {
      match
        tui_choose_indices(
          render_state,
          "? Which packages should have a minor bump?",
          remaining,
          labels,
          versions,
          [],
          [],
          color,
          allow_empty=true,
        ) {
        Some(minor_selected) => {
          let minor_packages : Array[String] = []
          for index in minor_selected {
            minor_indices.push(index)
            minor_packages.push(labels[index])
          }
          let minor_summary = if minor_packages.is_empty() {
            style_dim("none", color)
          } else {
            minor_packages.map(p => style_pkg(p, color)).join(", ")
          }
          tui_commit_line(
            render_state,
            format_completed_step(
              style_bump("minor", color) + ": " + minor_summary,
              color~,
            ),
          )
          remaining = remaining.filter(index => !minor_indices.contains(index))
        }
        None => {
          tui_commit_line(render_state, format_cancelled_step(color~))
          return 130
        }
      }
    }

    let patch_packages = remaining.map(index => labels[index])
    let staged_changes = assign_bump_stages(
      labels, chosen_indices, major_indices, minor_indices,
    )
    for change in staged_changes {
      selected.push(change)
    }
    if !patch_packages.is_empty() {
      tui_commit_line(
        render_state,
        format_completed_step(
          style_bump("patch", color) +
          ": " +
          patch_packages.map(p => style_pkg(p, color)).join(", "),
          color~,
        ),
      )
    }
  }

  let mut summary_state = SummaryState::new()
  let mut submitted = false
  let mut summary_hint = ""
  while !submitted {
    let prompt = render_summary_page(
      summary_state,
      has_editor,
      color~,
      hint=summary_hint,
    )
    tui_render_screen(render_state, prompt)
    let key = tui_read_key()
    let next = reduce_summary(summary_state, key)
    if next.cancelled {
      tui_commit_line(render_state, format_cancelled_step(color~))
      return 130
    }
    if next.open_editor ||
      (next.confirmed && next.text().trim() == "" && has_editor) {
      summary_hint = ""
      match edit_summary_in_editor(summary_state.text(), render_state) {
        Some(edited) => summary_state = SummaryState::new(initial=edited)
        None =>
          summary_state = {
            ..summary_state,
            open_editor: false,
            confirmed: false,
          }
      }
      continue
    }
    summary_state = { ..next, open_editor: false, confirmed: false, }
    if next.confirmed {
      if summary_state.text().trim() != "" {
        submitted = true
      } else {
        summary_hint = "Summary cannot be empty"
      }
    } else if key != Unknown {
      summary_hint = ""
    }
  }

  let final_summary = summary_state.text().trim().to_owned()
  tui_commit_line(
    render_state,
    format_completed_step(
      "Summary: " + style_dim(summary_preview(final_summary), color),
      color~,
    ),
  )
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
  if !options.no_commit &&
    (
      loaded.snapshot.config.commit.mode == @model.CommitMode::Add ||
      loaded.snapshot.config.commit.mode == @model.CommitMode::Both
    ) {
    ignore(
      @executor.commit_changes(
        loaded.snapshot.root,
        [rel_written],
        loaded.snapshot.config.commit.add_message,
      ),
    )
  }
  if options.open_editor {
    ignore(open_in_external_editor(written))
  }
  if !options.quiet {
    println(style_success("Created ", color) + style_pkg(written, color))
  }
  0
}
