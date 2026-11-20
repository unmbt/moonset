///|
/// Lightweight SemVer 2.0.0 representation supporting arbitrarily long numeric
/// prerelease identifiers (e.g. 14-digit YYYYMMDDHHmmss snapshot timestamps)
/// without 32-bit Int overflow.
priv struct SemVerParts {
  major : Int32
  minor : Int32
  patch : Int32
  pre : Array[String]
}

///|
fn is_all_ascii_digits(text : String) -> Bool {
  if text == "" {
    return false
  }
  for ch in text.to_array() {
    if ch < '0' || ch > '9' {
      return false
    }
  }
  true
}

///|
fn parse_uint32_checked(text : String) -> Int32? {
  if text == "" {
    return None
  }
  if text.length() > 1 && text[0] == '0' {
    return None
  }
  let mut acc : Int32 = 0
  for ch in text.to_array() {
    if ch < '0' || ch > '9' {
      return None
    }
    let digit = ch.to_int() - '0'.to_int()
    if acc > 214748364 || (acc == 214748364 && digit > 7) {
      return None
    }
    acc = acc * 10 + digit
  }
  Some(acc)
}

///|
fn parse_semver_parts(value : String) -> SemVerParts raise @model.MoonsetError {
  let trimmed = value.trim().to_owned()
  if trimmed == "" || trimmed != value {
    raise @model.Invalid(
      @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
    )
  }
  // Strip optional build metadata (+...) after validating build chars
  let without_build = match trimmed.find("+") {
    Some(idx) => {
      let build = trimmed[idx + 1:].to_owned()
      if build == "" {
        raise @model.Invalid(
          @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
        )
      }
      for seg_view in build.split(".") {
        let seg = seg_view.to_owned()
        if seg == "" {
          raise @model.Invalid(
            @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
          )
        }
        for ch in seg.to_array() {
          let ok = (ch >= '0' && ch <= '9') ||
            (ch >= 'a' && ch <= 'z') ||
            (ch >= 'A' && ch <= 'Z') ||
            ch == '-'
          if !ok {
            raise @model.Invalid(
              @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
            )
          }
        }
      }
      trimmed[:idx].to_owned()
    }
    None => trimmed
  }
  let (core, pre) : (String, Array[String]) = match without_build.find("-") {
    Some(idx) => {
      let pre_str = without_build[idx + 1:].to_owned()
      if pre_str == "" {
        raise @model.Invalid(
          @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
        )
      }
      let ids : Array[String] = []
      for seg_view in pre_str.split(".") {
        let seg = seg_view.to_owned()
        if seg == "" {
          raise @model.Invalid(
            @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
          )
        }
        let mut all_digits = true
        for ch in seg.to_array() {
          let is_digit = ch >= '0' && ch <= '9'
          let is_alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
          if !is_digit && !is_alpha && ch != '-' {
            raise @model.Invalid(
              @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
            )
          }
          if !is_digit {
            all_digits = false
          }
        }
        if all_digits && seg.length() > 1 && seg[0] == '0' {
          raise @model.Invalid(
            @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
          )
        }
        ids.push(seg)
      }
      (without_build[:idx].to_owned(), ids)
    }
    None => (without_build, [])
  }
  let parts : Array[String] = core.split(".").map(x => x.to_owned()).collect()
  if parts.length() != 3 {
    raise @model.Invalid(
      @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
    )
  }
  guard (
      parse_uint32_checked(parts[0]),
      parse_uint32_checked(parts[1]),
      parse_uint32_checked(parts[2]),
    )
    is (Some(major), Some(minor), Some(patch)) else {
    raise @model.Invalid(
      @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
    )
  }
  { major, minor, patch, pre, }
}

///|
fn SemVerParts::is_prerelease(self : SemVerParts) -> Bool {
  !self.pre.is_empty()
}

///|
fn compare_numeric_strings(a : String, b : String) -> Int32 {
  if a.length() != b.length() {
    a.length().compare(b.length())
  } else {
    a.compare(b)
  }
}

///|
fn compare_lex(a : String, b : String) -> Int32 {
  let ac = a.to_array()
  let bc = b.to_array()
  let min_len = if ac.length() < bc.length() {
    ac.length()
  } else {
    bc.length()
  }
  for i in 0..<min_len {
    if ac[i] != bc[i] {
      return ac[i].to_int().compare(bc[i].to_int())
    }
  }
  ac.length().compare(bc.length())
}

///|
fn SemVerParts::compare(self : SemVerParts, other : SemVerParts) -> Int32 {
  if self.major != other.major {
    return self.major.compare(other.major)
  }
  if self.minor != other.minor {
    return self.minor.compare(other.minor)
  }
  if self.patch != other.patch {
    return self.patch.compare(other.patch)
  }
  match (self.pre.is_empty(), other.pre.is_empty()) {
    (true, true) => 0
    (true, false) => 1
    (false, true) => -1
    (false, false) => {
      let min_len = if self.pre.length() < other.pre.length() {
        self.pre.length()
      } else {
        other.pre.length()
      }
      for i in 0..<min_len {
        let a = self.pre[i]
        let b = other.pre[i]
        if a == b {
          continue
        }
        let a_num = is_all_ascii_digits(a)
        let b_num = is_all_ascii_digits(b)
        if a_num && b_num {
          let cmp = compare_numeric_strings(a, b)
          if cmp != 0 {
            return cmp
          }
        } else if a_num {
          return -1
        } else if b_num {
          return 1
        } else {
          let cmp = compare_lex(a, b)
          if cmp != 0 {
            return cmp
          }
        }
      }
      self.pre.length().compare(other.pre.length())
    }
  }
}

///|
fn parse_version(value : String) -> SemVerParts raise @model.MoonsetError {
  parse_semver_parts(value)
}

///|
/// MoonBit MVS SemVer compatibility matching:
/// - `0.x` and `1.x` share the `< 2` compatibility line (`c.major < 2`)
/// - `>= 2.x`: same major (`c.major == r.major`)
/// - Prerelease candidates only match when `required` is also a prerelease with the same `major.minor.patch`.
pub fn version_matches(
  required : String,
  candidate : String,
) -> Bool raise @model.MoonsetError {
  let r = parse_version(required)
  let c = parse_version(candidate)
  if c.is_prerelease() {
    if !r.is_prerelease() ||
      r.major != c.major ||
      r.minor != c.minor ||
      r.patch != c.patch {
      return false
    }
  }
  c.compare(r) >= 0 &&
  (if r.major < 2 { c.major < 2 } else { c.major == r.major })
}

///|
fn increment(
  value : String,
  level : @model.Bump,
) -> String raise @model.MoonsetError {
  let v = parse_version(value)
  if level == @model.None {
    return value
  }
  // Delegate to @semver.inc when standard 32-bit pre ids, with pure fallback for >32-bit prereleases.
  match @semver.inc(value, level.text()) {
    Some(next) => next
    None =>
      match level {
        @model.Major => {
          let next_major = if v.minor != 0 || v.patch != 0 || !v.is_prerelease() {
            v.major + 1
          } else {
            v.major
          }
          "\{next_major}.0.0"
        }
        @model.Minor => {
          let next_minor = if v.patch != 0 || !v.is_prerelease() {
            v.minor + 1
          } else {
            v.minor
          }
          "\{v.major}.\{next_minor}.0"
        }
        @model.Patch => {
          let next_patch = if !v.is_prerelease() {
            v.patch + 1
          } else {
            v.patch
          }
          "\{v.major}.\{v.minor}.\{next_patch}"
        }
        @model.None => value
      }
  }
}

///|
fn invalid(
  message : String,
  path~ : String = "",
  line~ : Int32 = 1,
  column~ : Int32 = 1,
  code~ : String = "invalid-input",
) -> Unit raise @model.MoonsetError {
  raise @model.Invalid(@model.diagnostic(code, message, path~, line~, column~))
}

///|
pub fn canonical_id(name : String) -> String {
  if name.contains(":") {
    name
  } else {
    "moonbit:" + name
  }
}
