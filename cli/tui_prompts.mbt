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
  let out = @process.Cmd(program, args).run(
    stdin=Empty,
    stdout=Collect,
    stderr=Collect,
  ) catch {
    _ => return false
  }
  out.exit_code == 0
}

///|
priv enum EditorOutcome {
  EditorResult(String)
  EditorEmpty
  EditorError
}

///|
/// Open an external editor to author a multi-line changeset summary.
async fn edit_summary_in_editor(
  initial : String,
  render_state : TuiRenderState,
) -> EditorOutcome {
  guard parse_editor_command() is Some(_) else { return EditorError }
  let tmp = @fs.tmpdir(prefix="moonset-summary-") catch {
    _ => return EditorError
  }
  defer (@fs.remove(tmp, recursive=true) catch { _ => () })
  let draft_path = @path.Path(tmp).join(@path.Path("SUMMARY.md")).to_string()
  let header = if initial.trim() != "" {
    initial + "\n"
  } else {
    "\n\n# Please enter a summary for your changes.\n# An empty message aborts the editor.\n"
  }
  @fs.write_text(draft_path, header) catch {
    _ => return EditorError
  }
  tui_clear_frame(render_state)
  tui_cleanup(render_state)
  let ok = open_in_external_editor(draft_path)
  tui_begin(render_state)
  if !ok {
    return EditorError
  }
  let raw = @fs.read_text(draft_path) catch { _ => return EditorError }
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
    EditorEmpty
  } else {
    EditorResult(kept)
  }
}

///|
fn stage_visible_limit() -> Int32 {
  let rows = tty_rows() - 6
  if rows < 4 {
    4
  } else if rows > 16 {
    16
  } else {
    rows
  }
}

///|
fn tui_ask_confirm(
  render_state : TuiRenderState,
  message : String,
  initial_value~ : Bool = false,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> Bool? {
  let mut state = ConfirmState::new(initial=initial_value)
  while !state.confirmed && !state.cancelled {
    let prompt = render_confirm_prompt(message, state, with_guide~, color~)
    tui_render_screen(render_state, prompt)
    state = reduce_confirm(state, tui_read_key())
  }
  if state.cancelled {
    tui_commit_line(
      render_state,
      render_clack_cancel(message, with_guide~, color~),
    )
    return None
  }
  tui_commit_line(
    render_state,
    render_confirm_prompt(message, state, submitted=true, with_guide~, color~),
  )
  Some(state.value)
}

///|
fn tui_ask_select(
  render_state : TuiRenderState,
  message : String,
  labels : Array[String],
  submitted_labels~ : Array[String] = [],
  initial_cursor~ : Int32 = 0,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> Int32? {
  if labels.is_empty() {
    return None
  }
  let mut cursor = if initial_cursor >= 0 && initial_cursor < labels.length() {
    initial_cursor
  } else {
    0
  }
  for ;; {
    let prompt = render_select_prompt(
      message,
      labels,
      cursor,
      with_guide~,
      color~,
    )
    tui_render_screen(render_state, prompt)
    let (next_cursor, accepted, cancelled) = reduce_choice(
      cursor,
      labels.length(),
      tui_read_key(),
    )
    cursor = next_cursor
    if cancelled {
      tui_commit_line(
        render_state,
        render_clack_cancel(message, with_guide~, color~),
      )
      return None
    }
    if accepted {
      let chosen = submitted_labels.get(cursor).unwrap_or(labels[cursor])
      tui_commit_line(
        render_state,
        render_select_prompt(
          message,
          labels,
          cursor,
          submitted=true,
          submitted_text=chosen,
          with_guide~,
          color~,
        ),
      )
      return Some(cursor)
    }
  }
}

///|
fn tui_ask_group_multiselect(
  render_state : TuiRenderState,
  message : String,
  groups : Array[(String, Array[Int32])],
  item_labels : Array[String],
  submitted_names~ : Array[String] = [],
  required~ : Bool = false,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> Array[Int32]? {
  if groups.is_empty() || item_labels.is_empty() {
    return Some([])
  }
  let rows : Array[GroupRow] = []
  for entry in groups {
    let (group_name, members) = entry
    if !members.is_empty() {
      rows.push(GroupHeader(group_name, members))
      for idx in members {
        rows.push(GroupItem(idx))
      }
    }
  }
  if rows.is_empty() {
    return Some([])
  }
  let mut state = GroupMultiselectState::new(item_labels.length())
  while !state.cancelled && !state.confirmed {
    let prompt = render_group_multiselect_prompt(
      message,
      rows,
      item_labels,
      state,
      max_visible=stage_visible_limit(),
      with_guide~,
      color~,
    )
    tui_render_screen(render_state, prompt)
    state = reduce_group_multiselect(state, rows, tui_read_key(), required~)
  }
  if state.cancelled {
    tui_commit_line(
      render_state,
      render_clack_cancel(message, with_guide~, color~),
    )
    return None
  }
  let selected : Array[Int32] = []
  let summary_parts : Array[String] = []
  for i, is_on in state.selected {
    if is_on {
      selected.push(i)
      summary_parts.push(submitted_names.get(i).unwrap_or(item_labels[i]))
    }
  }
  let submitted_text = summary_parts.join(", ")
  tui_commit_line(
    render_state,
    render_group_multiselect_prompt(
      message,
      rows,
      item_labels,
      state,
      submitted=true,
      submitted_text~,
      with_guide~,
      color~,
    ),
  )
  Some(selected)
}

///|
priv enum TextPromptResult {
  TextSubmitted(String)
  TextOpenEditor(String)
  TextCancelled
}

///|
fn tui_ask_text(
  render_state : TuiRenderState,
  message : String,
  placeholder~ : String = "",
  default_value~ : String = "",
  not_empty~ : Bool = false,
  allow_ctrl_e~ : Bool = false,
  allow_empty_submit~ : Bool = false,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> TextPromptResult {
  let mut state = SummaryState::new()
  let mut error = ""
  for ;; {
    let prompt = render_text_prompt(
      message,
      state,
      placeholder~,
      error~,
      with_guide~,
      color~,
    )
    tui_render_screen(render_state, prompt)
    let key = tui_read_key()
    let next = reduce_summary(state, key)
    if next.cancelled {
      tui_commit_line(
        render_state,
        render_clack_cancel(message, with_guide~, color~),
      )
      return TextCancelled
    }
    if allow_ctrl_e && next.open_editor {
      tui_clear_frame(render_state)
      return TextOpenEditor(state.text())
    }
    if next.confirmed {
      let raw = next.text()
      let resolved = if raw == "" && default_value != "" {
        default_value
      } else {
        raw
      }
      if not_empty && resolved.trim() == "" {
        state = { ..next, confirmed: false, open_editor: false, }
        error = "Can't be empty."
        continue
      }
      if resolved == "" && !allow_empty_submit && default_value == "" {
        state = { ..next, confirmed: false, open_editor: false, }
        error = "Can't be empty."
        continue
      }
      let shown = if resolved == "" { "" } else { summary_preview(resolved) }
      tui_commit_line(
        render_state,
        render_text_prompt(
          message,
          state,
          submitted=true,
          submitted_text=shown,
          with_guide~,
          color~,
        ),
      )
      return TextSubmitted(resolved)
    }
    state = { ..next, confirmed: false, open_editor: false, }
    if key != Unknown {
      error = ""
    }
  }
}
