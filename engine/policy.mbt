///|
/// Return the structured `SnapshotConfig` from `Config`.
pub fn parse_snapshot_config(config : @model.Config) -> @model.SnapshotConfig {
  config.snapshot
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
      if !["tag", "datetime", "timestamp", "commit", "commit-short", "version"].contains(
          name,
        ) {
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
  // Normalize ISO-8601 `YYYY-MM-DDTHH:MM:SS[.sss][Z]` to 14-digit `YYYYMMDDHHmmss`.
  let base = match generated_at.find(".") {
    Some(idx) => generated_at[:idx].to_owned()
    None =>
      match generated_at.find("Z") {
        Some(idx) => generated_at[:idx].to_owned()
        None => generated_at
      }
  }
  let out : Array[Char] = []
  for ch in base.to_array() {
    if ch >= '0' && ch <= '9' {
      out.push(ch)
      if out.length() == 14 {
        break
      }
    }
  }
  if out.is_empty() {
    "0"
  } else {
    String::from_array(out)
  }
}

///|
fn full_commit_sha(git_head : String?) -> String? {
  match git_head {
    Some(sha) => {
      let clean = sha.trim().to_owned()
      if clean == "" {
        None
      } else {
        Some(clean)
      }
    }
    None => None
  }
}

///|
fn short_commit_sha(git_head : String?) -> String? {
  match full_commit_sha(git_head) {
    Some(clean) =>
      Some(if clean.length() > 7 { clean[:7].to_owned() } else { clean })
    None => None
  }
}

///|
fn sanitize_numeric_prerelease_id(id : String) -> String {
  if is_all_ascii_digits(id) && id.length() > 1 && id[0] == '0' {
    "g" + id
  } else {
    id
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
/// Supports tagless snapshots (`snapshot_tag = ""`) and single-pass placeholder
/// expansion for `{tag}`, `{datetime}`, `{timestamp}`, `{commit}`, `{commit-short}`, `{version}`.
pub fn render_snapshot_version(
  calculated_version : String,
  snapshot_tag : String,
  snapshot_config : @model.SnapshotConfig,
  generated_at~ : String = "",
  timestamp_ms~ : String = "",
  git_head? : String,
) -> String raise @model.MoonsetError {
  if !snapshot_config.enabled {
    invalid(
      "Snapshot releases are disabled by configuration; set snapshot.enabled to true",
      code="snapshot-disabled",
    )
  }
  let clean_tag = snapshot_tag.trim().to_owned()
  let base = if snapshot_config.use_calculated_version {
    strip_prerelease(parse_version(calculated_version))
  } else {
    "0.0.0"
  }
  let datetime = extract_datetime_digits(generated_at)
  let timestamp = if timestamp_ms.trim() != "" {
    timestamp_ms.trim().to_owned()
  } else {
    datetime
  }
  let commit_full = full_commit_sha(git_head).unwrap_or("0000000")
  let commit_short = short_commit_sha(git_head).unwrap_or("0000000")
  let template = snapshot_config.prerelease_template
  validate_snapshot_template(template)
  // Default template `{tag}-{datetime}` gracefully supports tagless `--snapshot` -> `{datetime}`.
  if clean_tag == "" && template == "{tag}-{datetime}" {
    validate_semver_prerelease(datetime)
    return base + "-" + datetime
  }
  if clean_tag != "" && !template.contains("{tag}") {
    invalid(
      "snapshot.prereleaseTemplate is missing '{tag}' placeholder while a snapshot tag was provided: " +
      clean_tag,
      code="invalid-input",
    )
  }
  if clean_tag == "" && template.contains("{tag}") {
    invalid(
      "snapshot.prereleaseTemplate requires a snapshot tag for '{tag}'",
      code="invalid-input",
    )
  }
  // Single-pass substitution prevents double-interpolation when tag contains `{...}`.
  let chars = template.to_array()
  let out = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    if chars[i] == '{' {
      let mut j = i + 1
      while j < chars.length() && chars[j] != '}' {
        j += 1
      }
      let key = String::from_array(chars[i + 1:j].to_owned())
      match key {
        "tag" => out.write_string(clean_tag)
        "datetime" => out.write_string(datetime)
        "timestamp" => out.write_string(timestamp)
        "commit" =>
          out.write_string(sanitize_numeric_prerelease_id(commit_full))
        "commit-short" =>
          out.write_string(sanitize_numeric_prerelease_id(commit_short))
        "version" => out.write_string(calculated_version)
        _ => ()
      }
      i = j + 1
    } else {
      out.write_char(chars[i])
      i += 1
    }
  }
  let rendered_suffix = out.to_string()
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
    "prettier" => Some(("prettier", ["--write", "--"] + paths))
    "oxfmt" => Some(("oxfmt", ["--write", "--"] + paths))
    "biome" => Some(("biome", ["format", "--write", "--"] + paths))
    "dprint" => Some(("dprint", ["fmt", "--"] + paths))
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
          None =>
            // Allow URLs with query strings (`https://reg.example?a=b`) as global,
            // but reject obvious unknown scope prefixes like `npn=https://...`.
            if !lhs.contains("://") && !lhs.contains("?") {
              invalid(
                "Unknown publish override scope '" +
                lhs +
                "' (expected moonbit, npm, cargo, or UnitId)",
                code="invalid-input",
              )
            } else {
              any_unscoped = true
            }
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
  if !any_scoped && entries.length() > 1 {
    invalid(
      "Comma-separated publish overrides must use scoped 'ecosystem=value' or 'unitId=value' syntax: " +
      trimmed,
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
  ecosystem : @model.Ecosystem,
) -> String? {
  match mapping.by_unit.get(unit_id) {
    Some(value) => Some(value)
    None =>
      match mapping.by_ecosystem.get(ecosystem.text()) {
        Some(value) => Some(value)
        None => mapping.global
      }
  }
}
