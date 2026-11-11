///|
/// Pure keyboard state used by both the native TUI and headless tests.
#derive(Eq, Debug)
pub(all) enum TuiKey {
  Up
  Down
  Left
  Right
  Enter
  Space
  Backspace
  Delete
  Cancel
  Char(String)
}

///|
pub(all) struct SelectState {
  cursor : Int32
  selected : Array[Bool]
  cancelled : Bool
  confirmed : Bool
}

///|
pub fn SelectState::new(length : Int32) -> SelectState {
  {
    cursor: 0,
    selected: Array::make(length, false),
    cancelled: false,
    confirmed: false,
  }
}

///|
pub fn reduce_select(state : SelectState, key : TuiKey) -> SelectState {
  let next = { ..state, }
  let length = state.selected.length()
  if length == 0 {
    match key {
      Cancel => return { ..next, cancelled: true, }
      _ => return next
    }
  }
  match key {
    Up =>
      {
        ..next,
        cursor: if state.cursor == 0 {
          length - 1
        } else {
          state.cursor - 1
        },
      }
    Down =>
      {
        ..next,
        cursor: if state.cursor + 1 == length {
          0
        } else {
          state.cursor + 1
        },
      }
    Space => {
      let values = state.selected.copy()
      values[state.cursor] = !values[state.cursor]
      { ..next, selected: values, }
    }
    Backspace | Delete => {
      let values = state.selected.copy()
      values[state.cursor] = false
      { ..next, selected: values, }
    }
    Enter => { ..next, confirmed: state.selected.any(x => x), }
    Cancel => { ..next, cancelled: true, }
    _ => next
  }
}

///|
pub fn reduce_choice(
  cursor : Int32,
  length : Int32,
  key : TuiKey,
) -> (Int32, Bool, Bool) {
  if length <= 0 {
    match key {
      Cancel => return (0, false, true)
      _ => return (0, false, false)
    }
  }
  match key {
    Up => (if cursor == 0 { length - 1 } else { cursor - 1 }, false, false)
    Down => (if cursor + 1 == length { 0 } else { cursor + 1 }, false, false)
    Enter => (cursor, true, false)
    Cancel | Left => (cursor, false, true)
    _ => (cursor, false, false)
  }
}

///|
pub fn edit_summary(value : String, key : TuiKey) -> (String, Bool, Bool) {
  match key {
    Backspace | Delete => {
      let chars = value.to_array()
      if chars.is_empty() {
        (value, false, false)
      } else {
        let _ = chars.pop()
        (String::from_array(chars), false, false)
      }
    }
    Enter => (value, true, false)
    Cancel => (value, false, true)
    Char(text) => (value + text, false, false)
    _ => (value, false, false)
  }
}
