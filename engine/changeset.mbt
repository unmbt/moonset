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
      String(s) => s
      _ => {
        invalid("Expected a string", path~, line~)
        ""
      }
    }
  }
  if text.has_prefix("'") && text.has_suffix("'") && text.length() >= 2 {
    return text[1:text.length() - 1].to_owned().replace_all(old="''", new="'")
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
pub fn parse_changeset(
  source : String,
  id~ : String,
  path~ : String,
  mixed~ : Bool = false,
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
  if lines.is_empty() || lines[0] != "---" {
    invalid("Missing opening front matter delimiter", path~)
  }
  let releases : Array[@model.Change] = []
  let seen : Map[String, Bool] = Map([])
  let mut closing = -1
  for i in 1..<lines.length() {
    let line = lines[i]
    if line == "---" {
      closing = i
      break
    }
    let content = line.trim().to_owned()
    if content == "" || content.has_prefix("#") {
      continue
    }
    if content == "{}" && releases.is_empty() {
      continue
    }
    if line.has_prefix(" ") || line.has_prefix("\t") {
      invalid("Nested front matter is not supported", path~, line=i + 1)
    }
    guard content.rev_find(":") is Some(separator) else {
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
  }
}
