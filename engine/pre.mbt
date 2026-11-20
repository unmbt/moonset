///|
/// Parse Changesets v3 minimal `pre.json` (`{ "mode": "pre" | "exit", "tag": "..." }`),
/// transparently accepting legacy v2 fields (`"mode": "active"`, `initialVersions`,
/// `nextNumbers`, `consumed`) for smooth migration.
pub fn parse_pre_state(
  source : String,
  path~ : String = ".changeset/pre.json",
) -> @model.PreState raise @model.MoonsetError {
  let json = parse_json(source, path)
  guard json is Object(fields) else {
    invalid("Expected pre state object", path~)
    return @model.PreState::new(@model.Pre, "")
  }
  for key in fields.keys() {
    if ![
        "mode", "tag", "initialVersions", "nextNumbers", "consumed", "changesets",
      ].contains(key) {
      invalid("Unknown pre state key: " + key, path~)
    }
  }
  let mode = match property(json, "mode") {
    String(s) =>
      match @model.PreMode::parse(s) {
        Some(m) => m
        None => {
          invalid("Invalid pre mode: " + s, path~)
          @model.Pre
        }
      }
    _ => {
      invalid("Invalid pre mode", path~)
      @model.Pre
    }
  }
  let tag = match property(json, "tag") {
    String(s) => s
    _ => {
      invalid("Missing pre tag", path~)
      ""
    }
  }
  validate_pre_tag(tag, path~)
  let legacy_consumed : Array[String] = []
  match property(json, "consumed") {
    Array(items) =>
      for item in items {
        guard item is String(cs_id) else {
          invalid("Invalid consumed changeset ID", path~)
          continue
        }
        if !legacy_consumed.contains(cs_id) {
          legacy_consumed.push(cs_id)
        }
      }
    Null => ()
    _ => invalid("Invalid consumed changeset IDs", path~)
  }
  match property(json, "changesets") {
    Array(items) =>
      for item in items {
        if item is String(cs_id) && !legacy_consumed.contains(cs_id) {
          legacy_consumed.push(cs_id)
        }
      }
    _ => ()
  }
  { mode, tag, legacy_consumed, }
}

///|
pub fn validate_pre_tag(
  tag : String,
  path~ : String = ".changeset/pre.json",
) -> Unit raise @model.MoonsetError {
  if tag == "" || tag.contains(".") || tag.contains("+") {
    invalid("Pre tag must be one nonnumeric SemVer identifier", path~)
  }
  let tag_version = parse_version("0.0.0-" + tag + ".0")
  if tag_version.pre.is_empty() || is_all_ascii_digits(tag_version.pre[0]) {
    invalid("Pre tag must be nonnumeric", path~)
  }
}

///|
fn strip_prerelease(version : SemVerParts) -> String {
  "\{version.major}.\{version.minor}.\{version.patch}"
}

///|
/// Changesets v3 pre-release counter derivation:
/// - Stable version (`1.0.0`) -> next pre counter is `0` (`-tag.0`)
/// - Matching prerelease (`1.0.1-next.2`) -> next pre counter is `3` (`-next.3`)
/// - Prerelease with another tag (`1.0.1-alpha.2` entering `beta`) -> counter resets to `0` (`-beta.0`)
fn next_pre_number(
  current : SemVerParts,
  tag : String,
) -> Int32 raise @model.MoonsetError {
  if !current.is_prerelease() {
    return 0
  }
  if current.pre.length() >= 2 && current.pre[0] == tag {
    match parse_uint32_checked(current.pre[1]) {
      Some(n) => return safe_inc_int(n)
      None =>
        invalid(
          "Prerelease numeric counter is invalid for tag '" + tag + "'",
          code="invalid-version",
        )
    }
  }
  0
}

///|
/// Return true when `version` is a prerelease carrying `tag` (or any prerelease if `tag == ""`).
fn has_prerelease_tag(version : SemVerParts, tag : String) -> Bool {
  if !version.is_prerelease() {
    return false
  }
  if tag == "" {
    true
  } else {
    version.pre.length() >= 1 && version.pre[0] == tag
  }
}

///|
/// Compute the next version from current manifest version(s) using Changesets v3
/// prerelease rules (no `initialVersions` / `nextNumbers` needed; no `"0.0.0"` sentinel bug).
fn compute_group_target_version(
  units : Array[@model.ReleaseUnit],
  level : @model.Bump,
  pre : @model.PreState?,
) -> String raise @model.MoonsetError {
  if units.is_empty() {
    invalid("Version group cannot be empty")
  }
  let mut highest_current_opt : (String, SemVerParts)? = None
  let mut max_counter : Int32 = 0
  for unit in units {
    guard unit.version is Some(old) else {
      invalid("Release unit has no version: " + unit.id, path=unit.manifest)
      return ""
    }
    let parsed = parse_version(old)
    match highest_current_opt {
      None => highest_current_opt = Some((old, parsed))
      Some((_, cur_best)) =>
        if parsed.compare(cur_best) > 0 {
          highest_current_opt = Some((old, parsed))
        }
    }
    if pre is Some(state) && state.mode == @model.Pre {
      let c = next_pre_number(parsed, state.tag)
      if c > max_counter {
        max_counter = c
      }
    }
  }
  let (highest_current, _) = highest_current_opt.unwrap()
  if level == @model.None {
    return highest_current
  }
  let bumped = increment(highest_current, level)
  match pre {
    Some(state) if state.mode == @model.Pre =>
      bumped + "-" + state.tag + ".\{max_counter}"
    _ => bumped
  }
}

///|
fn target_version(
  unit : @model.ReleaseUnit,
  level : @model.Bump,
  pre : @model.PreState?,
) -> String raise @model.MoonsetError {
  compute_group_target_version([unit], level, pre)
}
