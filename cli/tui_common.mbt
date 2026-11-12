///|
/// Terminal lifecycle helpers shared by init/add. Callers must defer cleanup
/// immediately after entering raw mode so cancellation and errors restore tty state.
pub fn tui_begin() -> Unit {
  @tui.enable_raw_mode()
  @tui.print_raw(@render.ansi_hide_cursor())
}

///|
pub fn tui_cleanup() -> Unit {
  @tui.cleanup_stdin()
  @tui.print_raw(@tui.ansi_full_reset() + @render.ansi_show_cursor())
}

///|
/// Parse the key strings returned by mizchi/tui into the pure reducer model.
pub fn tui_key(raw : String) -> TuiKey {
  match raw {
    "up" | "\u001b[A" => Up
    "down" | "\u001b[B" => Down
    "left" | "\u001b[D" => Left
    "right" | "\u001b[C" => Right
    "enter" | "\r" | "\n" => Enter
    "backspace" | "\u007f" => Backspace
    "delete" => Delete
    "space" | " " => Space
    "\u0003" => Cancel
    _ => Char(raw)
  }
}
