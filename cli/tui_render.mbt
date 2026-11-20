///|
/// Deterministic, terminal-width independent views used by the interactive TUI
/// and headless unit tests.
fn render_package_page(
  labels : Array[String],
  versions : Array[String],
  state : SelectState,
  changed_flags~ : Array[Bool] = [],
  publish_flags~ : Array[Bool] = [],
  max_visible~ : Int32 = 16,
  color~ : Bool = false,
  title~ : String = "? Select affected packages",
  allow_empty~ : Bool = false,
  hint~ : String = "",
) -> String {
  let confirm_hint = if allow_empty {
    "Enter confirm (empty skips)"
  } else {
    "Enter confirm"
  }
  let lines = [
    style_title(title, color),
    style_dim(
      "↑/↓ move  Space toggle  a all/none  " +
      confirm_hint +
      "  Esc/Ctrl+C cancel",
      color,
    ),
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
    lines.push(style_dim("  ... (" + start.to_string() + " more above)", color))
  }
  let show_groups = changed_flags.length() == labels.length() &&
    changed_flags.any(x => x)
  let mut previous_group = -1
  for i in start..<end {
    let changed = changed_flags.get(i).unwrap_or(false)
    let group = if changed { 0 } else { 1 }
    if show_groups && group != previous_group {
      lines.push(
        style_dim(
          if changed {
            "  changed packages"
          } else {
            "  unchanged packages"
          },
          color,
        ),
      )
      previous_group = group
    }
    let label = labels[i]
    let is_selected = state.selected.get(i).unwrap_or(false)
    let marker = if is_selected { style_success("x", color) } else { " " }
    let prefix = if i == state.cursor { style_title(">", color) } else { " " }
    let version = versions.get(i).unwrap_or("")
    let changed_badge = if changed {
      style_warn_soft(" [changed]", color)
    } else {
      ""
    }
    let publish_badge = match publish_flags.get(i) {
      Some(false) => style_dim(" [no-publish]", color)
      _ => ""
    }
    lines.push(
      prefix +
      " [" +
      marker +
      "] " +
      style_pkg(label, color) +
      "  " +
      style_dim(version, color) +
      changed_badge +
      publish_badge,
    )
  }
  if end < total {
    lines.push(
      style_dim("  ... (" + (total - end).to_string() + " more below)", color),
    )
  }
  if hint != "" {
    lines.push(style_warn("! " + hint, color))
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
  choices~ : Array[String] = ["major", "minor", "patch"],
  color~ : Bool = false,
) -> String {
  let progress = if step_total > 1 {
    " (" + (step_index + 1).to_string() + "/" + step_total.to_string() + ")"
  } else {
    ""
  }
  let lines = [
    style_title("? Bump for ", color) +
    style_pkg(unit_id, color) +
    "  " +
    style_dim(version, color) +
    progress,
    style_dim("↑/↓ move  Enter select  Esc/Ctrl+C cancel", color),
    "",
  ]
  for i, choice in choices {
    lines.push(
      (if i == cursor { style_title("> ", color) } else { "  " }) +
      style_bump(choice, color),
    )
  }
  lines.join("\n")
}

///|
fn render_zero_major_confirm(
  unit_id : String,
  version : String,
  cursor : Int32,
  color~ : Bool = false,
) -> String {
  let choices = [
    "No, do not make a first major release", "Yes, graduate to 1.0.0 (major)",
  ]
  let lines = [
    style_error("! ", color) +
    style_pkg(unit_id, color) +
    " is currently on pre-1.0 version " +
    style_dim(version, color),
    "  Selecting major will graduate this package to 1.0.0. Continue?",
    style_dim("↑/↓ move  y/n or Enter confirm  Esc/Ctrl+C cancel", color),
    "",
  ]
  for i, choice in choices {
    lines.push(
      (if i == cursor { style_title("> ", color) } else { "  " }) + choice,
    )
  }
  lines.join("\n")
}

///|
fn render_summary_page(
  state : SummaryState,
  has_editor : Bool,
  color~ : Bool = false,
  hint~ : String = "",
) -> String {
  let before = String::from_array(state.chars[:state.cursor].to_owned())
  let after = String::from_array(state.chars[state.cursor:].to_owned())
  let editor_hint = if has_editor { "  Ctrl+E external editor" } else { "" }
  let lines = [
    style_title("? Enter a summary for this changeset", color),
    style_dim(
      "Type summary (UTF-8 / 中文 supported)  ←/→ move  Enter confirm" +
      editor_hint +
      "  Esc/Ctrl+C cancel",
      color,
    ),
    "",
    style_title("> ", color) + before + style_accent("|", color) + after,
  ]
  if hint != "" {
    lines.push(style_warn("! " + hint, color))
  }
  lines.join("\n")
}

///|
fn format_completed_step(item : String, color~ : Bool = false) -> String {
  style_success("✓ ", color) + item
}

///|
fn format_cancelled_step(color~ : Bool = false) -> String {
  style_warn("✗ ", color) + style_dim("Cancelled", color)
}

///|
fn char_is_combining(ch : Char) -> Bool {
  (ch >= '\u{0300}' && ch <= '\u{036f}') ||
  (ch >= '\u{0483}' && ch <= '\u{0489}') ||
  (ch >= '\u{0591}' && ch <= '\u{05bd}') ||
  ch == '\u{05bf}' ||
  (ch >= '\u{05c1}' && ch <= '\u{05c2}') ||
  (ch >= '\u{0610}' && ch <= '\u{061a}') ||
  (ch >= '\u{064b}' && ch <= '\u{065f}') ||
  (ch >= '\u{06d6}' && ch <= '\u{06ed}') ||
  (ch >= '\u{1ab0}' && ch <= '\u{1aff}') ||
  (ch >= '\u{1dc0}' && ch <= '\u{1dff}') ||
  (ch >= '\u{20d0}' && ch <= '\u{20ff}') ||
  (ch >= '\u{1f3fb}' && ch <= '\u{1f3ff}') ||
  (ch >= '\u{fe00}' && ch <= '\u{fe0f}') ||
  (ch >= '\u{fe20}' && ch <= '\u{fe2f}') ||
  ch == '\u{200d}'
}

///|
/// Unicode Emoji_Presentation symbols in U+2300..U+27BF (excludes narrow
/// symbols like `✓` U+2713, `✗` U+2717, arrows, and box-drawing glyphs).
fn char_is_emoji_presentation_bmp(ch : Char) -> Bool {
  (ch >= '\u{231a}' && ch <= '\u{231b}') ||
  (ch >= '\u{23e9}' && ch <= '\u{23ec}') ||
  ch == '\u{23f0}' ||
  ch == '\u{23f3}' ||
  (ch >= '\u{25fd}' && ch <= '\u{25fe}') ||
  (ch >= '\u{2614}' && ch <= '\u{2615}') ||
  (ch >= '\u{2648}' && ch <= '\u{2653}') ||
  ch == '\u{267f}' ||
  ch == '\u{2693}' ||
  ch == '\u{26a1}' ||
  (ch >= '\u{26aa}' && ch <= '\u{26ab}') ||
  (ch >= '\u{26bd}' && ch <= '\u{26be}') ||
  (ch >= '\u{26c4}' && ch <= '\u{26c5}') ||
  ch == '\u{26ce}' ||
  ch == '\u{26d4}' ||
  ch == '\u{26ea}' ||
  (ch >= '\u{26f2}' && ch <= '\u{26f3}') ||
  ch == '\u{26f5}' ||
  ch == '\u{26fa}' ||
  ch == '\u{26fd}' ||
  ch == '\u{2705}' ||
  (ch >= '\u{270a}' && ch <= '\u{270b}') ||
  ch == '\u{2728}' ||
  ch == '\u{274c}' ||
  ch == '\u{274e}' ||
  (ch >= '\u{2753}' && ch <= '\u{2755}') ||
  ch == '\u{2757}' ||
  (ch >= '\u{2795}' && ch <= '\u{2797}') ||
  ch == '\u{27b0}' ||
  ch == '\u{27bf}'
}

///|
fn char_is_wide(ch : Char) -> Bool {
  (ch >= '\u{1100}' && ch <= '\u{115f}') ||
  ch == '\u{2329}' ||
  ch == '\u{232a}' ||
  (ch >= '\u{2e80}' && ch <= '\u{a4cf}') ||
  (ch >= '\u{ac00}' && ch <= '\u{d7a3}') ||
  (ch >= '\u{f900}' && ch <= '\u{faff}') ||
  (ch >= '\u{fe10}' && ch <= '\u{fe19}') ||
  (ch >= '\u{fe30}' && ch <= '\u{fe6f}') ||
  (ch >= '\u{ff01}' && ch <= '\u{ff60}') ||
  (ch >= '\u{ffe0}' && ch <= '\u{ffe6}') ||
  char_is_emoji_presentation_bmp(ch) ||
  (ch >= '\u{1f000}' && ch <= '\u{1faff}') ||
  (ch >= '\u{20000}' && ch <= '\u{3fffd}')
}

///|
fn char_is_regional_indicator(ch : Char) -> Bool {
  ch >= '\u{1f1e6}' && ch <= '\u{1f1ff}'
}

///|
fn has_emoji_variation_selector(chars : Array[Char], index : Int32) -> Bool {
  index + 1 < chars.length() && chars[index + 1] == '\u{fe0f}'
}

///|
fn is_keycap_emoji(chars : Array[Char], index : Int32) -> Bool {
  let base = chars[index]
  let is_keycap_base = base == '#' ||
    base == '*' ||
    (base >= '0' && base <= '9')
  if !is_keycap_base {
    return false
  }
  let suffix = if has_emoji_variation_selector(chars, index) {
    index + 2
  } else {
    index + 1
  }
  suffix < chars.length() && chars[suffix] == '\u{20e3}'
}

///|
/// Skip an ANSI escape sequence starting at `chars[index] == '\u{001b}'`,
/// returning the index immediately after the sequence.
fn skip_ansi_escape(chars : Array[Char], index : Int32) -> Int32 {
  let mut i = index + 1
  if i < chars.length() && chars[i] == '[' {
    i += 1
    while i < chars.length() && !(chars[i] >= '@' && chars[i] <= '~') {
      i += 1
    }
    if i < chars.length() {
      i += 1
    }
  } else if i < chars.length() {
    i += 1
  }
  i
}

///|
/// Compute the terminal cell width of `chars[index]` and update grapheme state.
fn step_cell_width(
  chars : Array[Char],
  index : Int32,
  column : Int32,
  join_next : Bool,
  previous_was_regional : Bool,
) -> (Int32, Bool, Bool) {
  let ch = chars[index]
  if ch == '\t' {
    return (8 - column % 8, false, false)
  }
  if ch <= '\u{001f}' || (ch >= '\u{007f}' && ch <= '\u{009f}') {
    return (0, false, false)
  }
  if ch == '\u{200d}' {
    return (0, true, previous_was_regional)
  }
  if char_is_combining(ch) {
    return (0, join_next, previous_was_regional)
  }
  if char_is_regional_indicator(ch) {
    if previous_was_regional {
      return (0, false, false)
    }
    return (if join_next { 0 } else { 2 }, false, true)
  }
  let cell_width : Int32 = if join_next {
    0
  } else if char_is_wide(ch) ||
    is_keycap_emoji(chars, index) ||
    has_emoji_variation_selector(chars, index) {
    2
  } else {
    1
  }
  (cell_width, false, false)
}

///|
fn visual_width(text : String) -> Int32 {
  let chars = text.to_array()
  let mut width : Int32 = 0
  let mut i : Int32 = 0
  let mut join_next = false
  let mut previous_was_regional = false
  while i < chars.length() {
    if chars[i] == '\u{001b}' {
      i = skip_ansi_escape(chars, i)
      previous_was_regional = false
      continue
    }
    let (cell, next_join, next_regional) = step_cell_width(
      chars, i, width, join_next, previous_was_regional,
    )
    width += cell
    join_next = next_join
    previous_was_regional = next_regional
    i += 1
  }
  width
}

///|
fn truncate_visual(text : String, max_cols : Int32) -> String {
  if max_cols <= 0 || visual_width(text) <= max_cols {
    return text
  }
  let target = if max_cols > 3 { max_cols - 3 } else { max_cols }
  let chars = text.to_array()
  let out = StringBuilder()
  let mut col : Int32 = 0
  let mut i : Int32 = 0
  let mut join_next = false
  let mut previous_was_regional = false
  while i < chars.length() {
    if chars[i] == '\u{001b}' {
      let next_i = skip_ansi_escape(chars, i)
      for k in i..<next_i {
        out.write_char(chars[k])
      }
      i = next_i
      previous_was_regional = false
      continue
    }
    let (cell, next_join, next_regional) = step_cell_width(
      chars, i, col, join_next, previous_was_regional,
    )
    if cell > 0 && col + cell > target {
      break
    }
    out.write_char(chars[i])
    col += cell
    join_next = next_join
    previous_was_regional = next_regional
    i += 1
  }
  if max_cols > 3 {
    out.write_string("...")
  }
  out.to_string()
}

///|
fn visual_line_count(text : String, columns : Int32) -> Int32 {
  let width_limit = if columns > 0 { columns } else { 80 }
  let chars = text.to_array()
  let mut lines : Int32 = 1
  let mut column : Int32 = 0
  let mut i : Int32 = 0
  let mut join_next = false
  let mut previous_was_regional = false
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\n' {
      lines += 1
      column = 0
      join_next = false
      previous_was_regional = false
      i += 1
      continue
    }
    if ch == '\u{001b}' {
      i = skip_ansi_escape(chars, i)
      continue
    }
    let (cell_width, next_join, next_regional) = step_cell_width(
      chars, i, column, join_next, previous_was_regional,
    )
    join_next = next_join
    previous_was_regional = next_regional
    if cell_width > 0 {
      if column > 0 && column + cell_width > width_limit {
        lines += 1
        column = 0
      }
      column += cell_width
    }
    i += 1
  }
  lines
}
