///|
fn parse_version(value : String) -> @semver.SemVer raise @model.MoonsetError {
  @semver.parse(value) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic("invalid-version", "Invalid SemVer: " + value),
      )
  }
}

///|
pub fn version_matches(
  required : String,
  candidate : String,
) -> Bool raise @model.MoonsetError {
  let r = parse_version(required)
  let c = parse_version(candidate)
  c.compare(r) >= 0 &&
  (if r.major < 2 { c.major < 2 } else { c.major == r.major })
}

///|
fn increment(
  value : String,
  level : @model.Bump,
) -> String raise @model.MoonsetError {
  ignore(parse_version(value))
  if level == @model.None {
    return value
  }
  match @semver.inc(value, level.text()) {
    Some(value) => value
    None =>
      raise @model.Invalid(
        @model.diagnostic("invalid-version", "Cannot increment " + value),
      )
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
