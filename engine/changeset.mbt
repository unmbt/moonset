///|
fn strip_yaml_comment(line : String) -> String {
  let chars = line.to_array()
  let out : Array[Char] = []
  let mut in_double = false
  let mut in_single = false
  let mut escaped = false
  for i, ch in chars {
    if escaped {
      out.push(ch)
      escaped = false
      continue
    }
    if in_double && ch == '\\' {
      out.push(ch)
      escaped = true
      continue
    }
    if !in_single && ch == '"' {
      in_double = !in_double
      out.push(ch)
      continue
    }
    if !in_double && ch == '\'' {
      in_single = !in_single
      out.push(ch)
      continue
    }
    if !in_double &&
      !in_single &&
      ch == '#' &&
      (i == 0 || chars[i - 1] == ' ' || chars[i - 1] == '\t') {
      break
    }
    out.push(ch)
  }
  String::from_array(out)
}

///|
fn scalar(
  value : String,
  path : String,
  line : Int32,
) -> String raise @model.MoonsetError {
  let text = value.trim().to_owned()
  if text.has_prefix("\"") {
    let parsed = parse_json(text, path) catch {
      @model.Invalid(diagnostic) =>
        raise @model.Invalid({ ..diagnostic, line: line + diagnostic.line - 1, })
      error => raise error
    }
    return match parsed {
      String(s) if s != "" => s
      _ => {
        invalid("Expected a non-empty string", path~, line~)
        ""
      }
    }
  }
  if text.has_prefix("'") && text.has_suffix("'") && text.length() >= 2 {
    let inner = text[1:text.length() - 1].to_owned()
    // Reject unescaped interior single quotes
    let chars = inner.to_array()
    let mut i = 0
    while i < chars.length() {
      if chars[i] == '\'' {
        if i + 1 < chars.length() && chars[i + 1] == '\'' {
          i += 2
          continue
        }
        invalid("Unescaped single quote in scalar", path~, line~)
      }
      i += 1
    }
    let decoded = inner.replace_all(old="''", new="'")
    if decoded == "" {
      invalid("Expected a non-empty string", path~, line~)
    }
    return decoded
  }
  if text == "" ||
    text.contains(" ") ||
    text.contains("\t") ||
    text.contains("&") ||
    text.contains("*") ||
    text.contains("[") ||
    text.contains("{") ||
    text.contains("#") ||
    text.contains("'") ||
    text.contains("\"") {
    invalid("Expected a plain scalar or quoted string", path~, line~)
  }
  text
}

///|
fn find_frontmatter_colon(content : String) -> Int32? {
  let chars = content.to_array()
  let mut in_double = false
  let mut in_single = false
  let mut escaped = false
  let mut last_colon : Int32? = None
  for i, ch in chars {
    if escaped {
      escaped = false
      continue
    }
    if in_double && ch == '\\' {
      escaped = true
      continue
    }
    if !in_single && ch == '"' {
      in_double = !in_double
      continue
    }
    if !in_double && ch == '\'' {
      in_single = !in_single
      continue
    }
    if !in_double && !in_single && ch == ':' {
      last_colon = Some(i)
    }
  }
  last_colon
}

///|
pub fn parse_changeset(
  source : String,
  id~ : String,
  path~ : String,
  mixed~ : Bool = false,
  in_pre_dir~ : Bool = false,
) -> @model.Changeset raise @model.MoonsetError {
  let input = if source.has_prefix("\uFEFF") {
    source[1:].to_owned()
  } else {
    source
  }
  let lines = input
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let mut open_idx = 0
  while open_idx < lines.length() && lines[open_idx].trim() == "" {
    open_idx += 1
  }
  if open_idx >= lines.length() || lines[open_idx].trim_end() != "---" {
    invalid("Missing opening front matter delimiter", path~)
  }
  let releases : Array[@model.Change] = []
  let seen : Map[String, Bool] = Map([])
  let mut seen_empty_object = false
  let mut closing = -1
  for i in (open_idx + 1)..<lines.length() {
    let line = lines[i]
    if line.trim_end() == "---" &&
      !line.has_prefix(" ") &&
      !line.has_prefix("\t") {
      closing = i
      break
    }
    let content = strip_yaml_comment(line).trim().to_owned()
    if content == "" {
      continue
    }
    if content == "{}" {
      if !releases.is_empty() || seen_empty_object {
        invalid("Cannot mix '{}' with release mappings", path~, line=i + 1)
      }
      seen_empty_object = true
      continue
    }
    if seen_empty_object {
      invalid("Cannot mix '{}' with release mappings", path~, line=i + 1)
    }
    if line.has_prefix(" ") || line.has_prefix("\t") {
      invalid("Nested front matter is not supported", path~, line=i + 1)
    }
    guard find_frontmatter_colon(content) is Some(separator) else {
      invalid("Expected name: bump", path~, line=i + 1)
      continue
    }
    let name = scalar(content[:separator].to_owned(), path, i + 1)
    if mixed && !name.contains(":") {
      invalid(
        "Mixed changesets require ecosystem-prefixed UnitId",
        path~,
        line=i + 1,
      )
    }
    let unit_id = canonical_id(name)
    if unit_id.has_suffix(":") {
      invalid("Empty package name in UnitId: " + unit_id, path~, line=i + 1)
    }
    if seen.contains(unit_id) {
      invalid("Duplicate changeset unit: " + unit_id, path~, line=i + 1)
    }
    seen[unit_id] = true
    let value = scalar(content[separator + 1:].to_owned(), path, i + 1)
    let bump = match value {
      "major" => @model.Major
      "minor" => @model.Minor
      "patch" => @model.Patch
      "none" => @model.None
      _ => {
        invalid("Unknown bump: " + value, path~, line=i + 1)
        @model.None
      }
    }
    releases.push({ unit_id, bump, })
  }
  if closing < 0 {
    invalid(
      "Missing closing front matter delimiter",
      path~,
      line=lines.length(),
    )
  }
  releases.sort_by((a, b) => a.unit_id.compare(b.unit_id))
  {
    id,
    path,
    releases,
    summary: lines[closing + 1:].to_owned().join("\n").trim().to_owned(),
    in_pre_dir,
  }
}

///|
/// Validate and format a draft using Moonset's stable YAML front matter format.
/// Keys are always double-quoted so scoped npm packages (`npm:@acme/ui`) and colons
/// remain valid YAML across Prettier and other formatters.
pub fn format_changeset(
  draft : @model.ChangesetDraft,
  allow_empty~ : Bool = false,
) -> String raise @model.MoonsetError {
  let summary = draft.summary.trim().to_owned()
  if !allow_empty && summary == "" {
    invalid("Changeset summary cannot be empty")
  }
  if summary.contains("\u0000") {
    invalid("Changeset summary contains NUL")
  }
  let seen : Map[String, Bool] = Map([])
  let lines = draft.releases.map(change => {
    let raw = change.unit_id.trim().to_owned()
    if raw == "" || raw.has_prefix(":") || raw.has_suffix(":") {
      invalid("Invalid UnitId: " + change.unit_id)
    }
    let id = canonical_id(raw)
    if id.contains("\n") || id.contains("\r") || id.has_suffix(":") {
      invalid("Invalid UnitId: " + id)
    }
    if seen.contains(id) {
      invalid("Duplicate changeset unit: " + id)
    }
    seen[id] = true
    Json::string(id).stringify() + ": " + change.bump.text()
  })
  if !allow_empty && lines.is_empty() {
    invalid("At least one release is required")
  }
  let header = if lines.is_empty() {
    "---\n---\n"
  } else {
    "---\n" + lines.join("\n") + "\n---\n"
  }
  if summary == "" {
    header
  } else {
    header + "\n" + summary + "\n"
  }
}

///|
pub fn validate_changeset_draft(
  draft : @model.ChangesetDraft,
  allow_empty~ : Bool = false,
) -> Unit raise @model.MoonsetError {
  ignore(format_changeset(draft, allow_empty~))
}
