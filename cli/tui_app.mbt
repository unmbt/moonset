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
async fn edit_summary_in_editor(initial : String) -> String? {
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
  tui_cleanup()
  let ok = open_in_external_editor(draft_path)
  tui_begin()
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
fn unit_is_changed(
  unit : @model.ReleaseUnit,
  changed_files : Array[String],
) -> Bool {
  if changed_files.is_empty() {
    return false
  }
  let prefix = if unit.root == "" || unit.root == "." {
    ""
  } else {
    unit.root + "/"
  }
  for file in changed_files {
    if prefix == "" || file == unit.root || file.has_prefix(prefix) {
      return true
    }
  }
  false
}

///|
fn is_pre_one_zero_version(version : String) -> Bool {
  version.has_prefix("0.")
}

///|
/// Interactive TUI for `moonset add` powered by our built-in UTF-8 native TTY stub.
async fn interactive_add(
  options : Options,
  loaded : @workspace.LoadedWorkspace,
) -> Int32 {
  let _no_color = options.no_color
  let _cols = tty_cols()
  let eligible_units = loaded.snapshot.units.filter(u => {
    !loaded.snapshot.config.ignore.any(pat => {
      !pat.has_prefix("!") &&
      (
        @engine.matches_unit_pattern(pat, u.id) ||
        @engine.matches_unit_pattern(pat, u.native_name)
      )
    })
  })
  if eligible_units.is_empty() {
    raise @model.Invalid(
      @model.diagnostic(
        "empty-workspace", "No selectable packages in workspace",
      ),
    )
  }
  // Group changed packages first for rapid monorepo selection
  let ordered_units : Array[@model.ReleaseUnit] = []
  let changed_flags : Array[Bool] = []
  for u in eligible_units {
    if unit_is_changed(u, loaded.snapshot.changed_files) {
      ordered_units.push(u)
      changed_flags.push(true)
    }
  }
  for u in eligible_units {
    if !unit_is_changed(u, loaded.snapshot.changed_files) {
      ordered_units.push(u)
      changed_flags.push(false)
    }
  }
  let labels = ordered_units.map(x => x.id)
  let versions = ordered_units.map(x => x.version.unwrap_or("unversioned"))
  let max_visible = {
    let rows = tty_rows() - 7
    if rows > 4 {
      rows
    } else {
      8
    }
  }
  let has_editor = parse_editor_command() is Some(_)

  tui_begin()
  defer tui_cleanup()

  // Single-package workspace fast path: auto-select the sole package!
  let chosen_indices : Array[Int32] = if ordered_units.length() == 1 {
    [0]
  } else {
    let mut state = SelectState::new(labels.length())
    let mut done = false
    while !done && !state.cancelled {
      tui_render_screen(
        render_package_page(
          labels,
          versions,
          state,
          changed_flags~,
          max_visible~,
        ),
      )
      let key = tui_read_key()
      state = reduce_select(state, key)
      done = state.confirmed
    }
    if state.cancelled || !state.confirmed {
      return 130
    }
    let indices : Array[Int32] = []
    for i, chosen in state.selected {
      if chosen {
        indices.push(i)
      }
    }
    indices
  }
  if chosen_indices.is_empty() {
    return 2
  }

  let bumps = Array::make(chosen_indices.length(), 2)
  let choices = [@model.Major, @model.Minor, @model.Patch, @model.None]
  let mut pkg_step = 0
  while pkg_step < chosen_indices.length() {
    let unit_idx = chosen_indices[pkg_step]
    tui_render_screen(
      render_bump_page(
        labels[unit_idx],
        versions[unit_idx],
        bumps[pkg_step],
        step_index=pkg_step,
        step_total=chosen_indices.length(),
      ),
    )
    let key = tui_read_key()
    let (next_cursor, confirmed, back) = reduce_choice(bumps[pkg_step], 4, key)
    bumps[pkg_step] = next_cursor
    if back {
      if key == Cancel {
        return 130
      }
      if pkg_step > 0 {
        pkg_step -= 1
      }
    } else if confirmed {
      // Confirm 0.x -> 1.0.0 major bump explicitly (matching Changesets UX)
      if bumps[pkg_step] == 0 && is_pre_one_zero_version(versions[unit_idx]) {
        let mut confirm_cursor : Int32 = 0
        let mut proceed = false
        let mut decided = false
        while !decided {
          tui_render_screen(
            render_zero_major_confirm(
              labels[unit_idx],
              versions[unit_idx],
              confirm_cursor,
            ),
          )
          let ckey = tui_read_key()
          let (nc, ok, cancel_back) = reduce_choice(confirm_cursor, 2, ckey)
          confirm_cursor = nc
          if cancel_back {
            if ckey == Cancel {
              return 130
            }
            decided = true
            proceed = false
          } else if ok {
            decided = true
            proceed = confirm_cursor == 1
          }
        }
        if proceed {
          pkg_step += 1
        }
      } else {
        pkg_step += 1
      }
    }
  }

  let selected : Array[@model.Change] = []
  for i, unit_idx in chosen_indices {
    selected.push({ unit_id: labels[unit_idx], bump: choices[bumps[i]], })
  }

  let mut summary_state = SummaryState::new()
  let mut finalized = false
  while !finalized {
    let mut submitted = false
    while !submitted {
      tui_render_screen(render_summary_page(summary_state, has_editor))
      let key = tui_read_key()
      let next = reduce_summary(summary_state, key)
      if next.cancelled {
        return 130
      }
      if next.open_editor {
        match edit_summary_in_editor(summary_state.text()) {
          Some(edited) => {
            summary_state = SummaryState::new(initial=edited)
            submitted = true
          }
          None => summary_state = { ..summary_state, open_editor: false, }
        }
        continue
      }
      summary_state = { ..next, confirmed: false, }
      if next.confirmed && summary_state.text().trim() != "" {
        submitted = true
      }
    }
    let clean_summary = summary_state.text().trim().to_owned()
    tui_render_screen(render_confirmation(clean_summary, selected))
    let mut decided = false
    while !decided {
      let key = tui_read_key()
      match key {
        Enter => {
          decided = true
          finalized = true
        }
        Left | Escape => decided = true
        Cancel => return 130
        _ => ()
      }
    }
  }

  let final_summary = summary_state.text().trim().to_owned()
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
    tui_cleanup()
    ignore(open_in_external_editor(written))
  }
  if !options.quiet {
    tui_render_screen("Created " + written)
  }
  0
}
