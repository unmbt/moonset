///|
/// Parsed configuration for `snapshot` releases from `.changeset/config.json`.
pub(all) struct SnapshotConfig {
  enabled : Bool
  use_calculated_version : Bool
  prerelease_template : String
}

///|
/// Parse `snapshot` settings from `Config.raw` with specification defaults.
pub fn parse_snapshot_config(config : @model.Config) -> SnapshotConfig {
  let snap = property(config.raw, "snapshot")
  let enabled = property(snap, "enabled") == Json::boolean(true)
  let use_calculated_version = property(snap, "useCalculatedVersion") ==
    Json::boolean(true)
  let prerelease_template = match property(snap, "prereleaseTemplate") {
    String(s) if s.trim() != "" => s
    _ => "{tag}-{datetime}"
  }
  { enabled, use_calculated_version, prerelease_template, }
}

///|
/// Validate `snapshot.prereleaseTemplate` placeholders and balanced braces.
pub fn validate_snapshot_template(
  template : String,
  path~ : String = ".changeset/config.json",
) -> Unit raise @model.MoonsetError {
  if template.trim() == "" {
    invalid(
      "snapshot.prereleaseTemplate cannot be empty",
      path~,
      code="invalid-config",
    )
  }
  let chars = template.to_array()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        if chars[j] == '{' {
          invalid(
            "Nested '{' in snapshot.prereleaseTemplate: " + template,
            path~,
            code="invalid-config",
          )
        }
        j += 1
      }
      if j >= chars.length() {
        invalid(
          "Unclosed '{' in snapshot.prereleaseTemplate: " + template,
          path~,
          code="invalid-config",
        )
      }
      let name = String::from_array(chars[i + 1:j].to_owned())
      if !["tag", "datetime", "commit", "version"].contains(name) {
        invalid(
          "Unsupported placeholder '{" +
          name +
          "}' in snapshot.prereleaseTemplate",
          path~,
          code="invalid-config",
        )
      }
      i = j + 1
    } else if chars[i] == '}' {
      invalid(
        "Unmatched '}' in snapshot.prereleaseTemplate: " + template,
        path~,
        code="invalid-config",
      )
    } else {
      i += 1
    }
  }
}

///|
fn extract_datetime_digits(generated_at : String) -> String {
  let out : Array[Char] = []
  for ch in generated_at.to_array() {
    if ch >= '0' && ch <= '9' {
      out.push(ch)
    }
  }
  if out.is_empty() {
    "0"
  } else {
    String::from_array(out)
  }
}

///|
fn short_commit_sha(git_head : String?) -> String {
  match git_head {
    Some(sha) => {
      let clean = sha.trim().to_owned()
      if clean == "" {
        "0000000"
      } else if clean.length() > 7 {
        clean[:7].to_owned()
      } else {
        clean
      }
    }
    None => "0000000"
  }
}

///|
fn validate_semver_prerelease(
  prerelease : String,
) -> Unit raise @model.MoonsetError {
  if prerelease == "" {
    invalid("Prerelease suffix cannot be empty", code="invalid-version")
  }
  for part_view in prerelease.split(".") {
    let part = part_view.to_owned()
    if part == "" {
      invalid(
        "Empty identifier in SemVer prerelease: " + prerelease,
        code="invalid-version",
      )
    }
    let mut all_digits = true
    for ch in part.to_array() {
      let is_digit = ch >= '0' && ch <= '9'
      let is_alpha = (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z')
      if !is_digit && !is_alpha && ch != '-' {
        invalid(
          "Illegal character in SemVer prerelease: " + prerelease,
          code="invalid-version",
        )
      }
      if !is_digit {
        all_digits = false
      }
    }
    if all_digits && part.length() > 1 && part[0] == '0' {
      invalid(
        "Numeric prerelease identifier cannot have leading zero: " + prerelease,
        code="invalid-version",
      )
    }
  }
}

///|
/// Render and SemVer-validate a snapshot version according to `SnapshotConfig`.
pub fn render_snapshot_version(
  calculated_version : String,
  snapshot_tag : String,
  snapshot_config : SnapshotConfig,
  generated_at~ : String = "",
  git_head? : String,
) -> String raise @model.MoonsetError {
  if !snapshot_config.enabled {
    invalid(
      "Snapshot releases are disabled by configuration; set snapshot.enabled to true",
      code="snapshot-disabled",
    )
  }
  let clean_tag = snapshot_tag.trim().to_owned()
  if clean_tag == "" {
    invalid("Snapshot tag cannot be empty", code="invalid-input")
  }
  validate_snapshot_template(snapshot_config.prerelease_template)
  let base = if snapshot_config.use_calculated_version {
    strip_prerelease(parse_version(calculated_version))
  } else {
    "0.0.0"
  }
  let datetime = extract_datetime_digits(generated_at)
  let commit = short_commit_sha(git_head)
  let rendered_suffix = snapshot_config.prerelease_template
    .replace_all(old="{tag}", new=clean_tag)
    .replace_all(old="{datetime}", new=datetime)
    .replace_all(old="{commit}", new=commit)
    .replace_all(old="{version}", new=calculated_version)
  validate_semver_prerelease(rendered_suffix)
  base + "-" + rendered_suffix
}

///|
/// Resolve the effective formatter name (`"none"`, `"builtin"`, `"prettier"`, `"oxfmt"`, `"biome"`, `"dprint"`).
pub fn resolve_formatter(
  config : @model.Config,
  no_format~ : Bool = false,
) -> String {
  if no_format || config.format_mode == "false" {
    return "none"
  }
  if ["prettier", "oxfmt", "biome", "dprint"].contains(config.format_mode) {
    return config.format_mode
  }
  if ["prettier", "oxfmt", "biome", "dprint"].contains(config.formatter) {
    return config.formatter
  }
  "builtin"
}

///|
/// Return true when the given formatter supports formatting `path`.
pub fn formatter_supports_path(formatter : String, path : String) -> Bool {
  let normalized = path.replace_all(old="\\", new="/")
  if normalized == "" ||
    normalized.has_prefix(".moonset/") ||
    normalized.contains("/.moonset/") {
    return false
  }
  let lower = normalized.to_lower()
  match formatter {
    "prettier" | "oxfmt" =>
      lower.has_suffix(".md") ||
      lower.has_suffix(".json") ||
      lower.has_suffix(".yaml") ||
      lower.has_suffix(".yml")
    "biome" => lower.has_suffix(".json") || lower.has_suffix(".jsonc")
    "dprint" =>
      lower.has_suffix(".md") ||
      lower.has_suffix(".json") ||
      lower.has_suffix(".toml")
    _ => false
  }
}

///|
/// Construct the parameterized command `(program, args)` for an external formatter.
/// Returns `None` for `"builtin"`, `"none"`, or empty path lists.
pub fn formatter_command(
  formatter : String,
  paths : Array[String],
) -> (String, Array[String])? {
  if paths.is_empty() {
    return None
  }
  match formatter {
    "prettier" => Some(("prettier", ["--write"] + paths))
    "oxfmt" => Some(("oxfmt", ["--write"] + paths))
    "biome" => Some(("biome", ["format", "--write"] + paths))
    "dprint" => Some(("dprint", ["fmt"] + paths))
    _ => None
  }
}

///|
/// Parsed scoped or global publish override (for `--registry`, `--tag`, or `publisher.registry`).
pub(all) struct PublishTargetOverride {
  global : String?
  by_ecosystem : Map[String, String]
  by_unit : Map[String, String]
}

///|
fn parse_scope_key(lhs : String) -> (String, String)? {
  if lhs == "moonbit" || lhs == "npm" || lhs == "cargo" {
    return Some(("ecosystem", lhs))
  }
  if (
      lhs.has_prefix("moonbit:") ||
      lhs.has_prefix("npm:") ||
      lhs.has_prefix("cargo:")
    ) &&
    !lhs.contains(" ") {
    match lhs.find(":") {
      Some(idx) if idx + 1 < lhs.length() => return Some(("unit", lhs))
      _ => return None
    }
  }
  None
}

///|
/// Parse a global value or comma-separated scoped mapping
/// (`npm=https://...,cargo=my-reg` or `npm:@acme/ui=canary`).
pub fn parse_target_mapping(
  raw : String?,
) -> PublishTargetOverride raise @model.MoonsetError {
  let by_ecosystem : Map[String, String] = Map([])
  let by_unit : Map[String, String] = Map([])
  guard raw is Some(text) else {
    return { global: None, by_ecosystem, by_unit, }
  }
  let trimmed = text.trim().to_owned()
  if trimmed == "" {
    return { global: None, by_ecosystem, by_unit, }
  }
  let entries = trimmed.split(",").map(x => x.trim().to_owned()).collect()
  let mut any_scoped = false
  let mut any_unscoped = false
  for entry in entries {
    if entry == "" {
      invalid(
        "Empty entry in scoped publish override: " + trimmed,
        code="invalid-input",
      )
    }
    match entry.find("=") {
      Some(eq) => {
        let lhs = entry[:eq].trim().to_owned()
        let rhs = entry[eq + 1:].trim().to_owned()
        match parse_scope_key(lhs) {
          Some((kind, key)) => {
            any_scoped = true
            if rhs == "" {
              invalid(
                "Missing value for scoped publish override '" + key + "'",
                code="invalid-input",
              )
            }
            if kind == "ecosystem" {
              if by_ecosystem.contains(key) {
                invalid(
                  "Duplicate ecosystem publish override: " + key,
                  code="invalid-input",
                )
              }
              by_ecosystem[key] = rhs
            } else {
              if by_unit.contains(key) {
                invalid(
                  "Duplicate unit publish override: " + key,
                  code="invalid-input",
                )
              }
              by_unit[key] = rhs
            }
          }
          None => any_unscoped = true
        }
      }
      None => any_unscoped = true
    }
  }
  if any_scoped && any_unscoped {
    invalid(
      "Cannot mix global and scoped entries in publish override: " + trimmed,
      code="invalid-input",
    )
  }
  if any_scoped {
    { global: None, by_ecosystem, by_unit, }
  } else {
    { global: Some(trimmed), by_ecosystem, by_unit, }
  }
}

///|
/// Resolve a publish override for a specific unit with precedence `unitId > ecosystem > global`.
pub fn resolve_target_override(
  mapping : PublishTargetOverride,
  unit_id : String,
  ecosystem : String,
) -> String? {
  match mapping.by_unit.get(unit_id) {
    Some(value) => Some(value)
    None =>
      match mapping.by_ecosystem.get(ecosystem) {
        Some(value) => Some(value)
        None => mapping.global
      }
  }
}
