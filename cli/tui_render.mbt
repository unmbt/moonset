///|
/// Split a single line on whitespace while wrapping to `max_cols` visual columns
/// and preserving ANSI SGR sequences inside tokens.
fn wrap_visual_line(line : String, max_cols : Int32) -> Array[String] {
  let limit = if max_cols > 4 { max_cols } else { 4 }
  if line == "" {
    return [""]
  }
  if visual_width(line) <= limit {
    return [line]
  }
  // Preserve leading spaces on the first wrapped segment (e.g., "  WHAT ...")
  let chars = line.to_array()
  let mut lead_count : Int32 = 0
  while lead_count < chars.length() && chars[lead_count] == ' ' {
    lead_count += 1
  }
  let indent = if lead_count > 0 && lead_count < limit {
    String::from_array(chars[:lead_count].to_owned())
  } else {
    ""
  }
  let rest = String::from_array(chars[lead_count:].to_owned())
  let words = rest
    .split(" ")
    .map(w => w.to_owned())
    .filter(w => w != "")
    .collect()
  if words.is_empty() {
    return [indent]
  }
  let out : Array[String] = []
  let mut current = indent
  let mut cur_width = visual_width(indent)
  let mut has_word = false
  for word in words {
    let word_w = visual_width(word)
    let space_w : Int32 = if has_word { 1 } else { 0 }
    if cur_width + space_w + word_w <= limit {
      if has_word {
        current = current + " " + word
      } else {
        current = current + word
      }
      cur_width += space_w + word_w
      has_word = true
    } else if word_w <= limit {
      if has_word {
        out.push(current)
      }
      current = word
      cur_width = word_w
      has_word = true
    } else {
      // Single long token (e.g., CJK text without spaces or long URL): break by char width
      if has_word {
        out.push(current)
        current = ""
        cur_width = 0
        has_word = false
      }
      let wchars = word.to_array()
      let buf = StringBuilder()
      let mut bw : Int32 = 0
      let mut wi : Int32 = 0
      let mut join_next = false
      let mut prev_reg = false
      while wi < wchars.length() {
        if wchars[wi] == '\u{001b}' {
          let next_i = skip_ansi_escape(wchars, wi)
          for k in wi..<next_i {
            buf.write_char(wchars[k])
          }
          wi = next_i
          prev_reg = false
          continue
        }
        let (cw, nj, pr) = step_cell_width(wchars, wi, bw, join_next, prev_reg)
        if cw > 0 && bw > 0 && bw + cw > limit {
          out.push(buf.to_string())
          buf.reset()
          bw = 0
        }
        buf.write_char(wchars[wi])
        bw += cw
        join_next = nj
        prev_reg = pr
        wi += 1
      }
      let tail = buf.to_string()
      if tail != "" {
        current = tail
        cur_width = visual_width(tail)
        has_word = true
      }
    }
  }
  if has_word {
    out.push(current)
  }
  out
}

///|
fn repeat_str(s : String, count : Int32) -> String {
  if count <= 0 {
    return ""
  }
  let buf = StringBuilder()
  for _ in 0..<count {
    buf.write_string(s)
  }
  buf.to_string()
}

///|
fn render_clack_intro(
  title : String,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if with_guide {
    style_gray("┌  ", color) + title + "\n" + style_gray("│", color)
  } else {
    title + "\n"
  }
}

///|
/// Render `@clack/prompts` log block (`kind`: "plain" | "info" | "success" | "warn" | "error").
fn render_clack_log(
  kind : String,
  lines : Array[String],
  with_guide~ : Bool = true,
  trailing_bar~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if lines.is_empty() {
    return ""
  }
  if !with_guide {
    let out = lines.join("\n")
    return if trailing_bar { out + "\n" } else { out }
  }
  let head_sym = match kind {
    "info" => style_blue("●  ", color)
    "success" => style_green("◆  ", color)
    "warn" => style_yellow("▲  ", color)
    "error" => style_red("■  ", color)
    _ => style_gray("│  ", color)
  }
  let out : Array[String] = [head_sym + lines[0]]
  for i in 1..<lines.length() {
    if lines[i] == "" {
      out.push(style_gray("│", color))
    } else {
      out.push(style_gray("│  ", color) + lines[i])
    }
  }
  if trailing_bar {
    out.push(style_gray("│", color))
  }
  out.join("\n")
}

///|
fn render_clack_cancel(
  message : String,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if with_guide {
    style_red("■  ", color) +
    message +
    "\n" +
    style_gray("│", color) +
    "\n" +
    style_gray("└  ", color) +
    style_red("Canceled... 👋", color)
  } else {
    style_red("■  ", color) +
    message +
    "\n" +
    style_red("Canceled... 👋", color)
  }
}

///|
fn render_confirm_prompt(
  message : String,
  state : ConfirmState,
  submitted~ : Bool = false,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if submitted {
    let val = if state.value { "Yes" } else { "No" }
    if with_guide {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_gray("│  ", color) +
        style_dim(val, color) +
        "\n" +
        style_gray("│", color)
    } else {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_dim(val, color)
    }
  }
  let yes_label = if state.value {
    style_green("● ", color) + "Yes"
  } else {
    style_dim("○ Yes", color)
  }
  let no_label = if !state.value {
    style_green("● ", color) + "No"
  } else {
    style_dim("○ No", color)
  }
  let row = yes_label + " " + style_dim("/", color) + " " + no_label
  if with_guide {
    style_cyan("◆  ", color) +
    message +
    "\n" +
    style_cyan("│  ", color) +
    row +
    "\n" +
    style_cyan("└", color)
  } else {
    style_cyan("◆  ", color) + message + "\n" + row
  }
}

///|
fn render_select_prompt(
  message : String,
  labels : Array[String],
  cursor : Int32,
  submitted~ : Bool = false,
  submitted_text~ : String = "",
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if submitted {
    let chosen = if submitted_text != "" {
      submitted_text
    } else {
      labels.get(cursor).unwrap_or("")
    }
    if with_guide {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_gray("│  ", color) +
        style_dim(chosen, color) +
        "\n" +
        style_gray("│", color)
    } else {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_dim(chosen, color)
    }
  }
  let bar = if with_guide { style_cyan("│  ", color) } else { "" }
  let lines = [style_cyan("◆  ", color) + message]
  for i, label in labels {
    if i == cursor {
      lines.push(bar + style_green("● ", color) + label)
    } else {
      lines.push(bar + style_dim("○ ", color) + style_dim(label, color))
    }
  }
  if with_guide {
    lines.push(style_cyan("└", color))
  }
  lines.join("\n")
}

///|
fn render_group_multiselect_prompt(
  message : String,
  rows : Array[GroupRow],
  item_labels : Array[String],
  state : GroupMultiselectState,
  submitted~ : Bool = false,
  submitted_text~ : String = "",
  max_visible~ : Int32 = 16,
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if submitted {
    let head = style_green("◇  ", color) + message
    if with_guide {
      let val_line = if submitted_text != "" {
        style_gray("│  ", color) + style_dim(submitted_text, color)
      } else {
        style_gray("│  ", color)
      }
      return head + "\n" + val_line + "\n" + style_gray("│", color)
    } else {
      return head + "\n" + style_dim(submitted_text, color)
    }
  }
  let has_err = state.error != ""
  let head_sym = if has_err {
    style_yellow("▲  ", color)
  } else {
    style_cyan("◆  ", color)
  }
  let bar = if with_guide {
    if has_err {
      style_yellow("│  ", color)
    } else {
      style_cyan("│  ", color)
    }
  } else {
    ""
  }
  let lines = [head_sym + message]
  let total = rows.length()
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
    lines.push(bar + style_dim("...", color))
  }
  for r in start..<end {
    let is_cur = r == state.cursor
    let cur_marker = if !color { if is_cur { "> " } else { "  " } } else { "" }
    match rows[r] {
      GroupHeader(group_name, members) => {
        let all_on = !members.is_empty() &&
          members.all(idx => state.selected.get(idx).unwrap_or(false))
        let box = if all_on {
          style_green("◼", color)
        } else if is_cur {
          style_cyan("◻", color)
        } else {
          style_dim("◻", color)
        }
        let text = if is_cur {
          style_bold(group_name, color)
        } else {
          style_dim(group_name, color)
        }
        lines.push(bar + cur_marker + box + " " + text)
      }
      GroupItem(idx) => {
        let is_sel = state.selected.get(idx).unwrap_or(false)
        let label = item_labels.get(idx).unwrap_or("")
        let box = if is_sel {
          style_green("◼", color)
        } else if is_cur {
          style_cyan("◻", color)
        } else {
          style_dim("◻", color)
        }
        let text = if is_cur || is_sel {
          label
        } else {
          style_dim(label, color)
        }
        lines.push(bar + "  " + cur_marker + box + " " + text)
      }
    }
  }
  if end < total {
    lines.push(bar + style_dim("...", color))
  }
  if has_err {
    let err_prefix = if with_guide {
      style_yellow("└  ", color)
    } else {
      style_yellow("▲  ", color)
    }
    lines.push(err_prefix + style_yellow(state.error, color))
  } else if with_guide {
    lines.push(style_cyan("└", color))
  }
  lines.join("\n")
}

///|
fn render_text_prompt(
  message : String,
  state : SummaryState,
  placeholder~ : String = "",
  error~ : String = "",
  submitted~ : Bool = false,
  submitted_text~ : String = "",
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  if submitted {
    let shown = if submitted_text != "" { submitted_text } else { state.text() }
    if with_guide {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_gray("│  ", color) +
        style_dim(shown, color) +
        "\n" +
        style_gray("│", color)
    } else {
      return style_green("◇  ", color) +
        message +
        "\n" +
        style_dim(shown, color)
    }
  }
  let has_err = error != ""
  let head_sym = if has_err {
    style_yellow("▲  ", color)
  } else {
    style_cyan("◆  ", color)
  }
  let bar = if with_guide {
    if has_err {
      style_yellow("│  ", color)
    } else {
      style_cyan("│  ", color)
    }
  } else {
    ""
  }
  let input_display = if state.chars.is_empty() && placeholder != "" {
    if color {
      let pchars = placeholder.to_array()
      let first = pchars[0].to_string()
      let rest = String::from_array(pchars[1:].to_owned())
      style_inverse(first, true) + style_gray(rest, true)
    } else {
      placeholder
    }
  } else {
    let before = String::from_array(state.chars[:state.cursor].to_owned())
    if state.cursor < state.chars.length() {
      let at = state.chars[state.cursor].to_string()
      let after = String::from_array(state.chars[state.cursor + 1:].to_owned())
      if color {
        before + style_inverse(at, true) + after
      } else {
        before + "|" + at + after
      }
    } else if color {
      before + style_inverse(" ", true)
    } else {
      before + "|"
    }
  }
  let lines = [head_sym + message, bar + input_display]
  if has_err {
    let err_prefix = if with_guide {
      style_yellow("└  ", color)
    } else {
      style_yellow("▲  ", color)
    }
    lines.push(err_prefix + style_yellow(error, color))
  } else if with_guide {
    lines.push(style_cyan("└", color))
  }
  lines.join("\n")
}

///|
/// Render `@clack/prompts` rounded `note(message, title)` box with exact right-border alignment.
fn render_note_box(
  title : String,
  body_lines : Array[String],
  title_yellow~ : Bool = false,
  body_white~ : Bool = false,
  with_guide~ : Bool = true,
  columns~ : Int32 = 80,
  color~ : Bool = false,
) -> String {
  let cols = if columns > 16 { columns } else { 80 }
  let max_wrap = cols - 8
  let wrapped : Array[String] = []
  for raw in body_lines {
    for seg in wrap_visual_line(raw, max_wrap) {
      wrapped.push(seg)
    }
  }
  let mut max_line_w : Int32 = 0
  for w in wrapped {
    let lw = visual_width(w)
    if lw > max_line_w {
      max_line_w = lw
    }
  }
  let title_w = visual_width(title)
  let min_for_title = title_w + 5
  let desired_inner = max_line_w + 4
  let inner_span = if desired_inner > min_for_title {
    desired_inner
  } else {
    min_for_title
  }
  let top_dashes = inner_span - title_w - 3
  let styled_title = if title_yellow {
    style_yellow(title, color)
  } else {
    title
  }
  let out = [
    style_green("◇  ", color) +
    styled_title +
    " " +
    style_gray(repeat_str("─", top_dashes) + "╮", color),
    style_gray("│" + repeat_str(" ", inner_span) + "│", color),
  ]
  for w in wrapped {
    let lw = visual_width(w)
    let pad_right = inner_span - 2 - lw
    let body_text = if body_white { style_white(w, color) } else { w }
    out.push(
      style_gray("│  ", color) +
      body_text +
      repeat_str(" ", pad_right) +
      style_gray("│", color),
    )
  }
  out.push(style_gray("│" + repeat_str(" ", inner_span) + "│", color))
  out.push(style_gray("├" + repeat_str("─", inner_span) + "╯", color))
  if with_guide {
    out.push(style_gray("│", color))
  }
  out.join("\n")
}

///|
fn render_changeset_summary(
  major~ : Array[String] = [],
  minor~ : Array[String] = [],
  patch~ : Array[String] = [],
  with_guide~ : Bool = true,
  color~ : Bool = false,
) -> String {
  let lines = [style_bold("Summary of changesets:", color)]
  if !major.is_empty() {
    lines.push(style_bump("major", color) + ":  " + major.join(", "))
  }
  if !minor.is_empty() {
    lines.push(style_bump("minor", color) + ":  " + minor.join(", "))
  }
  if !patch.is_empty() {
    lines.push(style_bump("patch", color) + ":  " + patch.join(", "))
  }
  render_clack_log("success", lines, with_guide~, color~)
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
