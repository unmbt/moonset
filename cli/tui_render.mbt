///|
/// Deterministic, terminal-width independent views used by the interactive adapter
/// and golden tests. ANSI is deliberately added by the terminal adapter only.
pub fn render_package_page(
  labels : Array[String],
  versions : Array[String],
  state : SelectState,
) -> String {
  let lines = [
    "? Select affected packages", "↑/↓ move  Space select  Enter confirm  Ctrl+C cancel",
    "",
  ]
  for i, label in labels {
    let marker = if state.selected.get(i).unwrap_or(false) { "x" } else { " " }
    let prefix = if i == state.cursor { ">" } else { " " }
    let version = versions.get(i).unwrap_or("")
    lines.push(prefix + " [" + marker + "] " + label + "  " + version)
  }
  lines.join("\n")
}

///|
pub fn render_bump_page(
  unit_id : String,
  version : String,
  cursor : Int32,
) -> String {
  let choices = ["major", "minor", "patch", "none"]
  let lines = [
    "? " + unit_id + "  " + version,
    "↑/↓ move  Enter select  ← back",
    "",
  ]
  for i, choice in choices {
    lines.push((if i == cursor { "> " } else { "  " }) + choice)
  }
  lines.join("\n")
}

///|
pub fn render_confirmation(
  summary : String,
  changes : Array[@model.Change],
) -> String {
  let lines = ["Summary of changesets:", ""]
  for level in [@model.Major, @model.Minor, @model.Patch] {
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
