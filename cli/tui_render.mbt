///|
/// Deterministic, terminal-width independent views used by the interactive TUI
/// and headless unit tests.
fn render_package_page(
  labels : Array[String],
  versions : Array[String],
  state : SelectState,
  changed_flags~ : Array[Bool] = [],
  max_visible~ : Int32 = 16,
) -> String {
  let lines = [
    "? Select affected packages", "↑/↓ move  Space toggle  a all/none  Enter confirm  Esc/Ctrl+C cancel",
    "",
  ]
  let total = labels.length()
  let window = if max_visible > 0 { max_visible } else { 16 }
  let start = if total <= window || state.cursor < window / 2 {
    0
  } else if state.cursor + (window - window / 2) >= total {
    total - window
  } else {
    state.cursor - window / 2
  }
  let end = if start + window < total { start + window } else { total }
  if start > 0 {
    lines.push("  ... (" + start.to_string() + " more above)")
  }
  for i in start..<end {
    let label = labels[i]
    let marker = if state.selected.get(i).unwrap_or(false) { "x" } else { " " }
    let prefix = if i == state.cursor { ">" } else { " " }
    let version = versions.get(i).unwrap_or("")
    let badge = if changed_flags.get(i).unwrap_or(false) {
      " [changed]"
    } else {
      ""
    }
    lines.push(prefix + " [" + marker + "] " + label + "  " + version + badge)
  }
  if end < total {
    lines.push("  ... (" + (total - end).to_string() + " more below)")
  }
  lines.join("\n")
}

///|
fn render_bump_page(
  unit_id : String,
  version : String,
  cursor : Int32,
  step_index~ : Int32 = 0,
  step_total~ : Int32 = 1,
) -> String {
  let choices = ["major", "minor", "patch", "none"]
  let progress = if step_total > 1 {
    " (" + (step_index + 1).to_string() + "/" + step_total.to_string() + ")"
  } else {
    ""
  }
  let lines = [
    "? Bump for " + unit_id + "  " + version + progress,
    "↑/↓ move  Enter select  ← back  Ctrl+C cancel",
    "",
  ]
  for i, choice in choices {
    lines.push((if i == cursor { "> " } else { "  " }) + choice)
  }
  lines.join("\n")
}

///|
fn render_zero_major_confirm(
  unit_id : String,
  version : String,
  cursor : Int32,
) -> String {
  let choices = [
    "No, go back and choose another bump", "Yes, graduate to 1.0.0 (major)",
  ]
  let lines = [
    "! " + unit_id + " is currently on pre-1.0 version " + version,
    "  Selecting `major` will graduate this package to 1.0.0. Continue?",
    "",
  ]
  for i, choice in choices {
    lines.push((if i == cursor { "> " } else { "  " }) + choice)
  }
  lines.join("\n")
}

///|
fn render_summary_page(state : SummaryState, has_editor : Bool) -> String {
  let before = String::from_array(state.chars[:state.cursor].to_owned())
  let after = String::from_array(state.chars[state.cursor:].to_owned())
  let editor_hint = if has_editor { "  Ctrl+E external editor" } else { "" }
  let lines = [
    "? Enter a summary for this changeset",
    "Type summary (UTF-8 / 中文 supported)  ←/→ move  Enter confirm" +
    editor_hint +
    "  Esc/Ctrl+C cancel",
    "",
    "> " + before + "|" + after,
  ]
  lines.join("\n")
}

///|
fn render_confirmation(
  summary : String,
  changes : Array[@model.Change],
) -> String {
  let lines = ["Summary of changesets:", ""]
  for level in [@model.Major, @model.Minor, @model.Patch, @model.None] {
    let names = changes.filter(x => x.bump == level).map(x => x.unit_id)
    if !names.is_empty() {
      lines.push(level.text() + ": " + names.join(", "))
    }
  }
  lines.push("")
  lines.push(summary)
  lines.push("")
  lines.push("Enter write  ← back  Ctrl+C cancel")
  lines.join("\n")
}
