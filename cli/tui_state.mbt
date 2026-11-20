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
fn reduce_choice(
  cursor : Int32,
  length : Int32,
  key : TuiKey,
) -> (Int32, Bool, Bool) {
  if key == Cancel || key == Escape {
    return (cursor, false, true)
  }
  if length <= 0 {
    return (0, false, false)
  }
  match key {
    Up | Char("k") =>
      (if cursor == 0 { length - 1 } else { cursor - 1 }, false, false)
    Down | Char("j") =>
      (if cursor + 1 == length { 0 } else { cursor + 1 }, false, false)
    Home => (0, false, false)
    End => (length - 1, false, false)
    Enter => (cursor, true, false)
    Left => (cursor, false, false)
    _ => (cursor, false, false)
  }
}

///|
fn assign_bump_stages(
  labels : Array[String],
  chosen : Array[Int32],
  major : Array[Int32],
  minor : Array[Int32],
) -> Array[@model.Change] {
  let changes : Array[@model.Change] = []
  for index in chosen {
    let bump = if major.contains(index) {
      @model.Major
    } else if minor.contains(index) {
      @model.Minor
    } else {
      @model.Patch
    }
    changes.push({ unit_id: labels[index], bump, })
  }
  changes
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

///|
/// Pure state machine for `@clack/prompts`-style Yes/No confirmation prompts.
priv struct ConfirmState {
  value : Bool
  confirmed : Bool
  cancelled : Bool
}

///|
fn ConfirmState::new(initial~ : Bool = false) -> ConfirmState {
  { value: initial, confirmed: false, cancelled: false, }
}

///|
fn reduce_confirm(state : ConfirmState, key : TuiKey) -> ConfirmState {
  match key {
    Left
    | Right
    | Up
    | Down
    | Tab
    | Space
    | Char("h")
    | Char("l")
    | Char("j")
    | Char("k") => { ..state, value: !state.value, }
    Char("y") | Char("Y") => { ..state, value: true, }
    Char("n") | Char("N") => { ..state, value: false, }
    Enter => { ..state, confirmed: true, }
    Cancel | Escape => { ..state, cancelled: true, }
    _ => state
  }
}

///|
/// Row entry for `@clack/prompts` `groupMultiselect` (selectable group headers + items).
priv enum GroupRow {
  GroupHeader(String, Array[Int32])
  GroupItem(Int32)
}

///|
priv struct GroupMultiselectState {
  cursor : Int32
  selected : Array[Bool]
  error : String
  confirmed : Bool
  cancelled : Bool
}

///|
fn GroupMultiselectState::new(item_count : Int32) -> GroupMultiselectState {
  {
    cursor: 0,
    selected: Array::make(item_count, false),
    error: "",
    confirmed: false,
    cancelled: false,
  }
}

///|
fn reduce_group_multiselect(
  state : GroupMultiselectState,
  rows : Array[GroupRow],
  key : TuiKey,
  required~ : Bool = false,
) -> GroupMultiselectState {
  let row_count = rows.length()
  if row_count == 0 {
    match key {
      Cancel | Escape => return { ..state, cancelled: true, }
      Enter =>
        if !required {
          return { ..state, confirmed: true, error: "", }
        } else {
          return { ..state, error: "Please select at least one option", }
        }
      _ => return state
    }
  }
  match key {
    Up | Char("k") => {
      let next_cursor = if state.cursor <= 0 {
        row_count - 1
      } else {
        state.cursor - 1
      }
      { ..state, cursor: next_cursor, error: "", }
    }
    Down | Char("j") => {
      let next_cursor = if state.cursor + 1 >= row_count {
        0
      } else {
        state.cursor + 1
      }
      { ..state, cursor: next_cursor, error: "", }
    }
    Home => { ..state, cursor: 0, error: "", }
    End => { ..state, cursor: row_count - 1, error: "", }
    Space => {
      let values = state.selected.copy()
      match rows[state.cursor] {
        GroupHeader(_, members) => {
          let all_on = !members.is_empty() && members.all(idx => values[idx])
          for idx in members {
            values[idx] = !all_on
          }
        }
        GroupItem(idx) => values[idx] = !values[idx]
      }
      { ..state, selected: values, error: "", }
    }
    Char("a") | Char("A") => {
      let all_on = !state.selected.is_empty() && state.selected.all(x => x)
      let values = Array::make(state.selected.length(), !all_on)
      { ..state, selected: values, error: "", }
    }
    Backspace | Delete => {
      let values = state.selected.copy()
      match rows[state.cursor] {
        GroupHeader(_, members) =>
          for idx in members {
            values[idx] = false
          }
        GroupItem(idx) => values[idx] = false
      }
      { ..state, selected: values, error: "", }
    }
    Enter =>
      if !required || state.selected.any(x => x) {
        { ..state, confirmed: true, error: "", }
      } else {
        {
          ..state,
          confirmed: false,
          error: "Please select at least one option",
        }
      }
    Cancel | Escape => { ..state, cancelled: true, }
    Unknown => state
    _ => { ..state, error: "", }
  }
}
