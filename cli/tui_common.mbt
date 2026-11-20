///|
const ANSI_HIDE_CURSOR : String = "\u{001b}[?25l"

///|
const ANSI_SHOW_CURSOR : String = "\u{001b}[?25h"

///|
const ANSI_RESET : String = "\u{001b}[0m"

///|
const ANSI_CLEAR_TO_END : String = "\u{001b}[J"

///|
priv struct TuiRenderState {
  mut prev_lines : Int32
  mut active : Bool
}

///|
fn TuiRenderState::new() -> TuiRenderState {
  { prev_lines: 0, active: false, }
}

///|
/// Enter raw mode and hide cursor. Callers MUST immediately `defer tui_cleanup(state)`.
fn tui_begin(state : TuiRenderState) -> Unit {
  if state.active {
    return
  }
  ignore(tty_enter_raw())
  tty_write(ANSI_HIDE_CURSOR)
  state.active = true
}

///|
/// Idempotently show cursor and restore terminal mode.
fn tui_cleanup(state : TuiRenderState) -> Unit {
  if !state.active {
    return
  }
  tty_write(ANSI_RESET + ANSI_SHOW_CURSOR)
  tty_leave_raw()
  state.active = false
}

///|
fn tui_clear_frame(state : TuiRenderState) -> Unit {
  if state.prev_lines > 0 {
    tty_write(tui_redraw_sequence(state.prev_lines))
    state.prev_lines = 0
  }
}

///|
fn tui_redraw_sequence(prev_lines : Int32) -> String {
  if prev_lines <= 0 {
    ""
  } else {
    "\u{001b}[\{prev_lines}A\r" + ANSI_CLEAR_TO_END
  }
}

///|
fn tui_frame_output(prev_lines : Int32, content : String) -> String {
  tui_redraw_sequence(prev_lines) + content + "\n"
}

///|
fn tui_render_screen(state : TuiRenderState, content : String) -> Unit {
  tty_write(tui_frame_output(state.prev_lines, content))
  state.prev_lines = visual_line_count(content, tty_cols())
}

///|
/// Clear the active prompt and permanently commit a collapsed summary line.
fn tui_commit_line(state : TuiRenderState, line : String) -> Unit {
  tty_write(tui_frame_output(state.prev_lines, line))
  state.prev_lines = 0
}

///|
fn tui_read_key() -> TuiKey {
  tui_key(tty_read_raw_event())
}

///|
/// Parse raw terminal sequences returned by `tty_read_raw_event` into `TuiKey`.
fn tui_key(raw : String) -> TuiKey {
  match raw {
    "up" | "\u{001b}[A" | "\u{001b}OA" => Up
    "down" | "\u{001b}[B" | "\u{001b}OB" => Down
    "right" | "\u{001b}[C" | "\u{001b}OC" => Right
    "left" | "\u{001b}[D" | "\u{001b}OD" => Left
    "home" | "\u{001b}[H" | "\u{001b}OH" | "\u{001b}[1~" | "\u{0001}" => Home
    "end" | "\u{001b}[F" | "\u{001b}OF" | "\u{001b}[4~" => End
    "enter" | "\r" | "\n" => Enter
    "backspace" | "\u{007f}" | "\u{0008}" => Backspace
    "delete" | "\u{001b}[3~" => Delete
    "space" | " " => Space
    "escape" | "\u{001b}" => Escape
    "ctrl+e" | "\u{0005}" => CtrlE
    "\u{0003}" => Cancel
    "\t" => Tab
    _ =>
      if raw.has_prefix("\u{001b}") {
        // Ignore unrecognized ANSI escape sequences rather than injecting garbage.
        Unknown
      } else {
        Char(raw)
      }
  }
}
