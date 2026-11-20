///|
/// Return true when a pattern contains glob metacharacters.
pub fn has_glob_meta(pattern : String) -> Bool {
  pattern.contains("*") ||
  pattern.contains("?") ||
  pattern.contains("[") ||
  pattern.contains("{") ||
  pattern.contains("@(") ||
  pattern.contains("?(") ||
  pattern.contains("+(") ||
  pattern.contains("*(") ||
  pattern.contains("!(")
}

///|
/// Validate glob syntax for config patterns (`fixed`/`linked`/`ignore` and `changedFilePatterns`).
pub fn validate_glob_pattern(
  pattern : String,
  allow_negation~ : Bool = false,
  path~ : String = ".changeset/config.json",
) -> Unit raise @model.MoonsetError {
  if pattern == "" {
    invalid("Glob pattern cannot be empty", path~, code="invalid-config")
  }
  let raw = if pattern.has_prefix("!") && !pattern.has_prefix("!(") {
    if !allow_negation {
      invalid(
        "Negated glob patterns are not supported here: " + pattern,
        path~,
        code="invalid-config",
      )
    }
    let rest = pattern[1:].to_owned()
    if rest == "" {
      invalid(
        "Negated glob pattern cannot be empty: " + pattern,
        path~,
        code="invalid-config",
      )
    }
    rest
  } else {
    pattern
  }
  let chars = raw.to_array()
  let mut i = 0
  let mut brace_depth = 0
  let mut extglob_depth = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '[' {
      let mut j = i + 1
      if j < chars.length() && (chars[j] == '!' || chars[j] == '^') {
        j += 1
      }
      if j >= chars.length() || chars[j] == ']' {
        invalid(
          "Empty or unclosed character class in glob: " + pattern,
          path~,
          code="invalid-config",
        )
      }
      let mut closed = false
      while j < chars.length() {
        if chars[j] == '\\' && j + 1 < chars.length() {
          j += 2
          continue
        }
        if chars[j] == ']' {
          closed = true
          break
        }
        if j + 2 < chars.length() && chars[j + 1] == '-' && chars[j + 2] != ']' {
          if chars[j] > chars[j + 2] {
            invalid(
              "Invalid character range in glob: " + pattern,
              path~,
              code="invalid-config",
            )
          }
          j += 3
        } else {
          j += 1
        }
      }
      if !closed {
        invalid(
          "Unclosed character class in glob: " + pattern,
          path~,
          code="invalid-config",
        )
      }
      i = j + 1
      continue
    }
    if ch == '{' {
      brace_depth += 1
    } else if ch == '}' {
      brace_depth -= 1
      if brace_depth < 0 {
        invalid(
          "Unmatched '}' in glob: " + pattern,
          path~,
          code="invalid-config",
        )
      }
    } else if is_extglob_prefix(ch) &&
      i + 1 < chars.length() &&
      chars[i + 1] == '(' {
      extglob_depth += 1
      i += 2
      continue
    } else if ch == '(' && extglob_depth > 0 {
      extglob_depth += 1
    } else if ch == ')' && extglob_depth > 0 {
      extglob_depth -= 1
    }
    i += 1
  }
  if brace_depth != 0 {
    invalid("Unclosed '{' in glob: " + pattern, path~, code="invalid-config")
  }
  if extglob_depth != 0 {
    invalid("Unclosed '(' in glob: " + pattern, path~, code="invalid-config")
  }
}

///|
fn find_matching_delim(
  chars : Array[Char],
  open_idx : Int32,
  open_ch : Char,
  close_ch : Char,
) -> Int32? {
  let mut depth = 0
  let mut i = open_idx
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '[' && open_ch != '[' {
      let mut j = i + 1
      if j < chars.length() && (chars[j] == '!' || chars[j] == '^') {
        j += 1
      }
      while j < chars.length() {
        if chars[j] == '\\' && j + 1 < chars.length() {
          j += 2
          continue
        }
        if chars[j] == ']' {
          break
        }
        j += 1
      }
      i = if j < chars.length() { j + 1 } else { chars.length() }
      continue
    }
    if ch == open_ch {
      depth += 1
    } else if ch == close_ch {
      depth -= 1
      if depth == 0 {
        return Some(i)
      }
    }
    i += 1
  }
  None
}

///|
fn split_top_level(chars : Array[Char], sep : Char) -> Array[String] {
  let parts : Array[String] = []
  let current : Array[Char] = []
  let mut brace_depth = 0
  let mut paren_depth = 0
  let mut in_class = false
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\\' && i + 1 < chars.length() {
      current.push(ch)
      current.push(chars[i + 1])
      i += 2
      continue
    }
    if in_class {
      current.push(ch)
      if ch == ']' {
        in_class = false
      }
      i += 1
      continue
    }
    if ch == '[' {
      in_class = true
      current.push(ch)
    } else if ch == '{' {
      brace_depth += 1
      current.push(ch)
    } else if ch == '}' {
      brace_depth -= 1
      current.push(ch)
    } else if ch == '(' {
      paren_depth += 1
      current.push(ch)
    } else if ch == ')' {
      paren_depth -= 1
      current.push(ch)
    } else if ch == sep && brace_depth == 0 && paren_depth == 0 {
      parts.push(String::from_array(current))
      current.clear()
    } else {
      current.push(ch)
    }
    i += 1
  }
  parts.push(String::from_array(current))
  parts
}

///|
fn expand_braces_into(
  pattern : String,
  limit : Int32,
  out : Array[String],
) -> Unit {
  if out.length() >= limit {
    return
  }
  let chars = pattern.to_array()
  let mut open_idx : Int32? = None
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '\\' {
      i += 2
      continue
    }
    if ch == '[' {
      let mut j = i + 1
      if j < chars.length() && (chars[j] == '!' || chars[j] == '^') {
        j += 1
      }
      while j < chars.length() {
        if chars[j] == '\\' && j + 1 < chars.length() {
          j += 2
          continue
        }
        if chars[j] == ']' {
          break
        }
        j += 1
      }
      i = if j < chars.length() { j + 1 } else { chars.length() }
      continue
    }
    if ch == '{' {
      open_idx = Some(i)
      break
    }
    i += 1
  }
  guard open_idx is Some(start) else {
    out.push(pattern)
    return
  }
  guard find_matching_delim(chars, start, '{', '}') is Some(end) else {
    out.push(pattern)
    return
  }
  let prefix = String::from_array(chars[:start].to_owned())
  let inner = chars[start + 1:end].to_owned()
  let suffix = String::from_array(chars[end + 1:].to_owned())
  let alts = split_top_level(inner, ',')
  if alts.length() <= 1 {
    // Preserve single-item `{foo}` as literal per bash/picomatch semantics.
    let escaped = prefix + "\\{" + String::from_array(inner) + "\\}" + suffix
    expand_braces_into(escaped, limit, out)
    return
  }
  for alt in alts {
    if out.length() >= limit {
      break
    }
    expand_braces_into(prefix + alt + suffix, limit, out)
  }
}

///|
fn expand_braces_bounded(pattern : String, limit : Int32) -> Array[String] {
  let out : Array[String] = []
  expand_braces_into(pattern, limit, out)
  out
}

///|
fn match_char_class(
  ch : Char,
  pat : Array[Char],
  start : Int32,
  slash_special : Bool,
) -> (Bool, Int32)? {
  let mut j = start + 1
  let mut negate = false
  if j < pat.length() && (pat[j] == '!' || pat[j] == '^') {
    negate = true
    j += 1
  }
  let mut matched = false
  while j < pat.length() && pat[j] != ']' {
    let cur = if pat[j] == '\\' && j + 1 < pat.length() {
      j += 1
      pat[j]
    } else {
      pat[j]
    }
    if j + 2 < pat.length() && pat[j + 1] == '-' && pat[j + 2] != ']' {
      let hi = if pat[j + 2] == '\\' && j + 3 < pat.length() {
        j += 1
        pat[j + 2]
      } else {
        pat[j + 2]
      }
      if ch >= cur && ch <= hi {
        matched = true
      }
      j += 3
    } else {
      if ch == cur {
        matched = true
      }
      j += 1
    }
  }
  if j >= pat.length() {
    return None
  }
  if slash_special && ch == '/' {
    return Some((false, j + 1))
  }
  Some((if negate { !matched } else { matched }, j + 1))
}

///|
fn is_extglob_prefix(ch : Char) -> Bool {
  ch == '@' || ch == '?' || ch == '+' || ch == '*' || ch == '!'
}

///|
fn match_glob_chars(
  text : Array[Char],
  pat : Array[Char],
  i : Int32,
  j : Int32,
  slash_special : Bool,
  memo : Map[String, Bool],
) -> Bool {
  let key = "\{i}:\{j}"
  if memo.get(key) is Some(found) {
    return found
  }
  let matched = if j == pat.length() {
    i == text.length()
  } else if pat[j] == '\\' && j + 1 < pat.length() {
    i < text.length() &&
    text[i] == pat[j + 1] &&
    match_glob_chars(text, pat, i + 1, j + 2, slash_special, memo)
  } else if is_extglob_prefix(pat[j]) &&
    j + 1 < pat.length() &&
    pat[j + 1] == '(' &&
    find_matching_delim(pat, j + 1, '(', ')') is Some(close_idx) {
    let kind = pat[j]
    let open_idx = j + 1
    let inner = pat[open_idx + 1:close_idx].to_owned()
    let alts = split_top_level(inner, '|')
    let next_j = close_idx + 1
    match_extglob(text, pat, i, next_j, kind, alts, slash_special, memo)
  } else if pat[j] == '*' {
    let is_double_star = slash_special &&
      j + 1 < pat.length() &&
      pat[j + 1] == '*'
    // Globstar `**` only crosses '/' when bounded by start/end or '/' in the pattern.
    let globstar_valid = is_double_star &&
      (j == 0 || pat[j - 1] == '/') &&
      (j + 2 == pat.length() || pat[j + 2] == '/')
    let next = j + (if is_double_star { 2 } else { 1 })
    if globstar_valid {
      let at_seg_boundary = i == 0 || text[i - 1] == '/'
      (
        at_seg_boundary &&
        next < pat.length() &&
        pat[next] == '/' &&
        match_glob_chars(text, pat, i, next + 1, slash_special, memo)
      ) ||
      match_glob_chars(text, pat, i, next, slash_special, memo) ||
      (
        i < text.length() &&
        match_glob_chars(text, pat, i + 1, j, slash_special, memo)
      )
    } else {
      match_glob_chars(text, pat, i, next, slash_special, memo) ||
      (
        i < text.length() &&
        (!slash_special || text[i] != '/') &&
        match_glob_chars(text, pat, i + 1, j, slash_special, memo)
      )
    }
  } else if pat[j] == '[' {
    if i < text.length() {
      match match_char_class(text[i], pat, j, slash_special) {
        Some((ok, next_j)) =>
          ok && match_glob_chars(text, pat, i + 1, next_j, slash_special, memo)
        None => false
      }
    } else {
      false
    }
  } else if pat[j] == '?' {
    i < text.length() &&
    (!slash_special || text[i] != '/') &&
    match_glob_chars(text, pat, i + 1, j + 1, slash_special, memo)
  } else if i < text.length() && pat[j] == text[i] {
    match_glob_chars(text, pat, i + 1, j + 1, slash_special, memo)
  } else {
    false
  }
  memo[key] = matched
  matched
}

///|
fn match_subpattern(
  slice : Array[Char],
  pattern : String,
  slash_special : Bool,
) -> Bool {
  for expanded in expand_braces_bounded(pattern, 256) {
    if match_glob_chars(
        slice,
        expanded.to_array(),
        0,
        0,
        slash_special,
        Map([]),
      ) {
      return true
    }
  }
  false
}

///|
fn match_extglob(
  text : Array[Char],
  pat : Array[Char],
  i : Int32,
  next_j : Int32,
  kind : Char,
  alts : Array[String],
  slash_special : Bool,
  memo : Map[String, Bool],
) -> Bool {
  let allow_slash = !slash_special ||
    alts.any(a => a.contains("/") || a.contains("**"))
  let mut max_end = i
  while max_end < text.length() && (allow_slash || text[max_end] != '/') {
    max_end += 1
  }
  if kind == '@' {
    for end in i..<=max_end {
      let slice = text[i:end].to_owned()
      if alts.any(alt => match_subpattern(slice, alt, slash_special)) &&
        match_glob_chars(text, pat, end, next_j, slash_special, memo) {
        return true
      }
    }
    false
  } else if kind == '?' {
    if match_glob_chars(text, pat, i, next_j, slash_special, memo) {
      return true
    }
    for end in (i + 1)..<=max_end {
      let slice = text[i:end].to_owned()
      if alts.any(alt => match_subpattern(slice, alt, slash_special)) &&
        match_glob_chars(text, pat, end, next_j, slash_special, memo) {
        return true
      }
    }
    false
  } else if kind == '!' {
    for end in i..<=max_end {
      let slice = text[i:end].to_owned()
      if !alts.any(alt => match_subpattern(slice, alt, slash_special)) &&
        match_glob_chars(text, pat, end, next_j, slash_special, memo) {
        return true
      }
    }
    false
  } else if kind == '*' || kind == '+' {
    let reachable : Array[Bool] = Array::make(max_end - i + 1, false)
    reachable[0] = true
    let mut step = 0
    while step <= max_end - i {
      if reachable[step] {
        let start = i + step
        for end in (start + 1)..<=max_end {
          if !reachable[end - i] {
            let slice = text[start:end].to_owned()
            if alts.any(alt => match_subpattern(slice, alt, slash_special)) {
              reachable[end - i] = true
            }
          }
        }
      }
      step += 1
    }
    let min_offset = if kind == '+' {
      if alts.any(alt => match_subpattern([], alt, slash_special)) {
        0
      } else {
        1
      }
    } else {
      0
    }
    for offset in min_offset..<=(max_end - i) {
      if reachable[offset] &&
        match_glob_chars(text, pat, i + offset, next_j, slash_special, memo) {
        return true
      }
    }
    false
  } else {
    false
  }
}

///|
/// Match a relative file path against a glob pattern (`*`, `**`, `?`, `[...]`, `{...}`, extglob).
pub fn matches_pattern(path : String, pattern : String) -> Bool {
  let text = path.to_array()
  for expanded in expand_braces_bounded(pattern, 256) {
    if match_glob_chars(text, expanded.to_array(), 0, 0, true, Map([])) {
      return true
    }
  }
  false
}

///|
/// Evaluate an ordered list of `changedFilePatterns` (including `!pattern` negations).
pub fn matches_changed_patterns(
  path : String,
  patterns : Array[String],
) -> Bool {
  if patterns.is_empty() {
    return false
  }
  let has_positive = patterns.any(p => {
    !(p.has_prefix("!") && !p.has_prefix("!("))
  })
  let mut matched = !has_positive
  for pattern in patterns {
    if pattern.has_prefix("!") && !pattern.has_prefix("!(") {
      let inner = pattern[1:].to_owned()
      if inner != "" && matches_pattern(path, inner) {
        matched = false
      }
    } else if matches_pattern(path, pattern) {
      matched = true
    }
  }
  matched
}

///|
fn unit_pattern_key(pattern : String) -> String {
  if pattern.contains(":") ||
    pattern.has_prefix("*") ||
    pattern.has_prefix("{") ||
    pattern.has_prefix("?") ||
    pattern.has_prefix("[") ||
    pattern.has_prefix("@(") ||
    pattern.has_prefix("!(") {
    pattern
  } else {
    canonical_id(pattern)
  }
}

///|
/// Match a canonical UnitId against an exact UnitId or glob pattern.
pub fn matches_unit_pattern(unit_id : String, pattern : String) -> Bool {
  let canonical_pat = unit_pattern_key(pattern)
  if !has_glob_meta(canonical_pat) {
    return unit_id == canonical_pat
  }
  let text = unit_id.to_array()
  for expanded in expand_braces_bounded(canonical_pat, 256) {
    if match_glob_chars(text, expanded.to_array(), 0, 0, false, Map([])) {
      return true
    }
  }
  false
}

///|
/// Return true when a unit matches `config.ignore` (supporting ordered `!negation`).
pub fn is_unit_ignored(config : @model.Config, unit_id : String) -> Bool {
  let mut ignored = false
  for entry in config.ignore {
    if entry.has_prefix("!") && !entry.has_prefix("!(") {
      let inner = entry[1:].to_owned()
      if inner != "" && matches_unit_pattern(unit_id, inner) {
        ignored = false
      }
    } else if matches_unit_pattern(unit_id, entry) {
      ignored = true
    }
  }
  ignored
}

///|
/// Resolve configured `ignore` entries (exact UnitIds + globs + `!negations`) against discovered units.
pub fn resolve_ignored_units(
  config : @model.Config,
  units : Array[@model.ReleaseUnit],
) -> Array[String] raise @model.MoonsetError {
  let ids = units.map(u => u.id)
  ids.sort()
  for entry in config.ignore {
    let raw = if entry.has_prefix("!") && !entry.has_prefix("!(") {
      entry[1:].to_owned()
    } else {
      entry
    }
    let pattern = unit_pattern_key(raw)
    if !has_glob_meta(pattern) && !ids.contains(pattern) {
      invalid("Unknown configured unit: " + pattern)
    }
  }
  let resolved = ids.filter(id => is_unit_ignored(config, id))
  resolved.sort()
  resolved
}

///|
/// Resolve configured `fixed` or `linked` groups (exact UnitIds + globs + `!negations`) against discovered units.
pub fn resolve_unit_groups(
  groups : Array[Array[String]],
  units : Array[@model.ReleaseUnit],
) -> Array[Array[String]] raise @model.MoonsetError {
  let ids = units.map(u => u.id)
  ids.sort()
  let resolved : Array[Array[String]] = []
  for group in groups {
    let members : Array[String] = []
    for entry in group {
      if entry.has_prefix("!") && !entry.has_prefix("!(") {
        let inner = entry[1:].to_owned()
        if inner != "" {
          let keep : Array[String] = []
          for m in members {
            if !matches_unit_pattern(m, inner) {
              keep.push(m)
            }
          }
          members.clear()
          for m in keep {
            members.push(m)
          }
        }
        continue
      }
      let pattern = unit_pattern_key(entry)
      if !has_glob_meta(pattern) {
        if !ids.contains(pattern) {
          invalid("Unknown configured unit: " + pattern)
        }
        if !members.contains(pattern) {
          members.push(pattern)
        }
      } else {
        for id in ids {
          if matches_unit_pattern(id, pattern) && !members.contains(id) {
            members.push(id)
          }
        }
      }
    }
    if !members.is_empty() {
      members.sort()
      resolved.push(members)
    }
  }
  resolved
}
