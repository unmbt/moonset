///|
/// Pure keyboard state used by both the native TUI and headless unit tests.
#derive(Eq)
priv enum TuiKey {
  Up
  Down
  Left
  Right
  Home
  End
  Enter
  Space
  Backspace
  Delete
  Escape
  Tab
  CtrlE
  Cancel
  Char(String)
  Unknown
}

///|
priv struct SelectState {
  cursor : Int32
  selected : Array[Bool]
  cancelled : Bool
  confirmed : Bool
}

///|
fn SelectState::new(length : Int32) -> SelectState {
  {
    cursor: 0,
    selected: Array::make(length, false),
    cancelled: false,
    confirmed: false,
  }
}

///|
fn reduce_select(state : SelectState, key : TuiKey) -> SelectState {
  let next = { ..state, }
  let length = state.selected.length()
  if length == 0 {
    match key {
      Cancel | Escape => return { ..next, cancelled: true, }
      _ => return next
    }
  }
  match key {
    Up | Char("k") =>
      {
        ..next,
        cursor: if state.cursor == 0 {
          length - 1
        } else {
          state.cursor - 1
        },
      }
    Down | Char("j") =>
      {
        ..next,
        cursor: if state.cursor + 1 == length {
          0
        } else {
          state.cursor + 1
        },
      }
    Home => { ..next, cursor: 0, }
    End => { ..next, cursor: length - 1, }
    Space => {
      let values = state.selected.copy()
      values[state.cursor] = !values[state.cursor]
      { ..next, selected: values, }
    }
    Char("a") | Char("A") => {
      let all_selected = state.selected.all(x => x)
      let values = Array::make(length, !all_selected)
      { ..next, selected: values, }
    }
    Backspace | Delete => {
      let values = state.selected.copy()
      values[state.cursor] = false
      { ..next, selected: values, }
    }
    Enter => { ..next, confirmed: state.selected.any(x => x), }
    Cancel | Escape => { ..next, cancelled: true, }
    _ => next
  }
}

///|
fn reduce_choice(
  cursor : Int32,
  length : Int32,
  key : TuiKey,
) -> (Int32, Bool, Bool) {
  if length <= 0 {
    match key {
      Cancel | Escape => return (0, false, true)
      _ => return (0, false, false)
    }
  }
  match key {
    Up | Char("k") =>
      (if cursor == 0 { length - 1 } else { cursor - 1 }, false, false)
    Down | Char("j") =>
      (if cursor + 1 == length { 0 } else { cursor + 1 }, false, false)
    Enter => (cursor, true, false)
    Cancel | Escape | Left => (cursor, false, true)
    _ => (cursor, false, false)
  }
}

///|
/// Character-indexed line editor supporting ASCII, Space, and full UTF-8 / CJK IME input.
priv struct SummaryState {
  chars : Array[Char]
  cursor : Int32
  confirmed : Bool
  cancelled : Bool
  open_editor : Bool
}

///|
fn SummaryState::new(initial~ : String = "") -> SummaryState {
  let chars = initial.to_array()
  {
    chars,
    cursor: chars.length(),
    confirmed: false,
    cancelled: false,
    open_editor: false,
  }
}

///|
fn SummaryState::text(self : SummaryState) -> String {
  String::from_array(self.chars)
}

///|
fn reduce_summary(state : SummaryState, key : TuiKey) -> SummaryState {
  match key {
    Left =>
      { ..state, cursor: if state.cursor > 0 { state.cursor - 1 } else { 0 }, }
    Right =>
      {
        ..state,
        cursor: if state.cursor < state.chars.length() {
          state.cursor + 1
        } else {
          state.chars.length()
        },
      }
    Home => { ..state, cursor: 0, }
    End => { ..state, cursor: state.chars.length(), }
    Backspace =>
      if state.cursor <= 0 {
        state
      } else {
        let next_chars : Array[Char] = []
        for i in 0..<state.chars.length() {
          if i != state.cursor - 1 {
            next_chars.push(state.chars[i])
          }
        }
        { ..state, chars: next_chars, cursor: state.cursor - 1, }
      }
    Delete =>
      if state.cursor >= state.chars.length() {
        state
      } else {
        let next_chars : Array[Char] = []
        for i in 0..<state.chars.length() {
          if i != state.cursor {
            next_chars.push(state.chars[i])
          }
        }
        { ..state, chars: next_chars, }
      }
    Space => {
      let next_chars : Array[Char] = []
      for i in 0..<state.cursor {
        next_chars.push(state.chars[i])
      }
      next_chars.push(' ')
      for i in state.cursor..<state.chars.length() {
        next_chars.push(state.chars[i])
      }
      { ..state, chars: next_chars, cursor: state.cursor + 1, }
    }
    Char(text) => {
      let inserted = text.to_array()
      if inserted.is_empty() {
        return state
      }
      let next_chars : Array[Char] = []
      for i in 0..<state.cursor {
        next_chars.push(state.chars[i])
      }
      for ch in inserted {
        next_chars.push(ch)
      }
      for i in state.cursor..<state.chars.length() {
        next_chars.push(state.chars[i])
      }
      { ..state, chars: next_chars, cursor: state.cursor + inserted.length(), }
    }
    Enter => { ..state, confirmed: true, }
    CtrlE => { ..state, open_editor: true, }
    Cancel | Escape => { ..state, cancelled: true, }
    _ => state
  }
}
