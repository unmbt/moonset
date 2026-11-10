///|
pub fn parse_pre_state(
  source : String,
  path~ : String = ".changeset/pre.json",
) -> @model.PreState raise @model.MoonsetError {
  let json = parse_json(source, path)
  guard json is Object(fields) else {
    invalid("Expected pre state object", path~)
    return {
      mode: "",
      tag: "",
      initial_versions: Map([]),
      next_numbers: Map([]),
      consumed: [],
    }
  }
  for key in fields.keys() {
    if !["mode", "tag", "initialVersions", "nextNumbers", "consumed"].contains(
        key,
      ) {
      invalid("Unknown pre state key: " + key, path~)
    }
  }
  let mode = match property(json, "mode") {
    String("active" | "exit" as s) => s
    _ => {
      invalid("Invalid pre mode", path~)
      ""
    }
  }
  let tag = match property(json, "tag") {
    String(s) => s
    _ => {
      invalid("Missing pre tag", path~)
      ""
    }
  }
  if tag == "" || tag.contains(".") || tag.contains("+") {
    invalid("Pre tag must be one nonnumeric SemVer identifier", path~)
  }
  let tag_version = parse_version("0.0.0-" + tag + ".0")
  if !(tag_version.pre[0] is @semver.Str(_)) {
    invalid("Pre tag must be nonnumeric", path~)
  }
  let initial_versions : Map[String, String] = Map([])
  let next_numbers : Map[String, Int32] = Map([])
  match property(json, "initialVersions") {
    Object(entries) =>
      for id, value in entries {
        guard value is String(version) else {
          invalid("Invalid initialVersions value", path~)
          continue
        }
        ignore(parse_version(version))
        if canonical_id(id) != id {
          invalid("Pre state requires canonical UnitId", path~)
        }
        initial_versions[id] = version
      }
    _ => invalid("Missing initialVersions", path~)
  }
  match property(json, "nextNumbers") {
    Object(entries) =>
      for id, value in entries {
        guard value is Number(number, ..) &&
          number >= 0 &&
          number <= 2147483646.0 &&
          number == number.to_int().to_double() else {
          invalid("Invalid nextNumbers counter", path~)
          continue
        }
        next_numbers[id] = number.to_int()
      }
    _ => invalid("Missing nextNumbers", path~)
  }
  guard property(json, "consumed") is Array(items) &&
    items.all(x => x is String(_)) else {
    invalid("Missing consumed changeset IDs", path~)
    return { mode, tag, initial_versions, next_numbers, consumed: [], }
  }
  {
    mode,
    tag,
    initial_versions,
    next_numbers,
    consumed: strings(property(json, "consumed")),
  }
}

///|
fn target_version(
  unit : @model.ReleaseUnit,
  level : @model.Bump,
  pre : @model.PreState?,
) -> String raise @model.MoonsetError {
  guard unit.version is Some(old) else {
    invalid("Release unit has no version: " + unit.id, path=unit.manifest)
    return ""
  }
  let base = increment(old, level)
  match pre {
    Some(state) if state.mode == "active" && level != @model.None => {
      let current = parse_version(old)
      let counter = state.next_numbers.get(unit.id).unwrap_or(0)
      if current.is_prerelease() &&
        (
          current.pre.length() != 2 ||
          !(current.pre[0] is @semver.Str(tag) && tag == state.tag)
        ) {
        invalid(
          "Existing prerelease does not match pre state: " + unit.id,
          path=unit.manifest,
        )
      }
      base + "-" + state.tag + ".\{counter}"
    }
    _ => base
  }
}
