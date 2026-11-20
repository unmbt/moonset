///|
const ANSI_HIDE_CURSOR : String = "\u{001b}[?25l"

///|
const ANSI_SHOW_CURSOR : String = "\u{001b}[?25h"

///|
const ANSI_RESET : String = "\u{001b}[0m"

///|
const ANSI_CLEAR_HOME : String = "\u{001b}[2J\u{001b}[H"

///|
/// Enter raw mode and hide cursor. Callers MUST immediately `defer tui_cleanup()`.
fn tui_begin() -> Unit {
  ignore(tty_enter_raw())
  tty_write(ANSI_HIDE_CURSOR)
}

///|
fn tui_cleanup() -> Unit {
  tty_write(ANSI_RESET + ANSI_SHOW_CURSOR)
  tty_leave_raw()
}

///|
fn tui_render_screen(content : String) -> Unit {
  tty_write(ANSI_CLEAR_HOME + content + "\n")
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
