///|
pub fn parse_json(
  source : String,
  path : String,
) -> Json raise @model.MoonsetError {
  @json.parse(source, reject_duplicate_keys=true) catch {
    error => {
      let (line, column) = match error {
        @json.DuplicateKey(pos, _)
        | @json.InvalidChar(pos, _)
        | @json.InvalidIdentEscape(pos)
        | @json.InvalidNumber(pos, _) => (pos.line, pos.column + 1)
        _ =>
          (
            source.split("\n").count(),
            source.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
          )
      }
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-json",
          error.to_string(),
          path~,
          line~,
          column~,
        ),
      )
    }
  }
}

///|
fn strings(value : Json) -> Array[String] {
  match value {
    Array(items) =>
      items.filter_map(x => {
        match x {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn groups(value : Json) -> Array[Array[String]] {
  match value {
    Array(items) => items.map(x => strings(x).map(canonical_id))
    _ => []
  }
}

///|
pub fn parse_config(
  source : String,
  path~ : String = ".changeset/config.json",
) -> @model.Config raise @model.MoonsetError {
  let raw = parse_json(source, path)
  let schema = parse_json(config_schema_text, "builtin-config-schema")
  if schema_issue(raw, schema, schema, "$") is Some(issue) {
    let json_path = issue.split(":").next().unwrap_or("$").to_owned()
    let key = json_path.split(".").last().unwrap_or("").to_owned()
    let offset = source.find(Json::string(key).stringify()).unwrap_or(0)
    let prefix = source[:offset].to_owned()
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-config",
        issue,
        path~,
        line=prefix.split("\n").count(),
        column=prefix.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
        json_path~,
      ),
    )
  }
  let defaults = @model.Config::default()
  let fixed = groups(property(raw, "fixed"))
  let linked = groups(property(raw, "linked"))
  let ignore = strings(property(raw, "ignore")).map(canonical_id)
  let occupied : Map[String, Bool] = Map([])
  for group in fixed + linked {
    for id in group {
      if occupied.contains(id) {
        invalid("Overlapping or repeated version group member: " + id, path~)
      }
      occupied[id] = true
    }
  }
  for id in occupied.keys().collect() + ignore {
    if id.contains("*") || id.contains("?") || id.contains("[") {
      invalid(
        "Version group globs are not supported in Phase 1",
        path~,
        code="unsupported-capability",
      )
    }
  }
  let mixed = property(property(raw, "experimental"), "mixedWorkspaces")
  if mixed != Json::null() {
    if property(mixed, "mode") != Json::string("coexist") {
      invalid(
        "Unified mixed-workspace planning is not implemented",
        path~,
        code="unsupported-capability",
      )
    }
    if property(mixed, "bridges") is Array(bridges) && !bridges.is_empty() {
      invalid(
        "Build bridges require a later adapter phase",
        path~,
        code="unsupported-capability",
      )
    }
    if property(mixed, "workspaces") is Array(workspaces) {
      let ids : Map[String, Bool] = Map([])
      for ws in workspaces {
        if property(ws, "ecosystem") != Json::string("moonbit") {
          invalid(
            "Configured ecosystem adapter is unavailable: " +
            property(ws, "ecosystem").stringify(),
            path~,
            code="unsupported-capability",
          )
        }
        if property(ws, "id") is String(id) {
          if ids.contains(id) {
            invalid("Duplicate workspace ID: " + id, path~)
          }
          ids[id] = true
        }
      }
    }
  }
  let changed_patterns = match property(raw, "changedFilePatterns") {
    Array(_) as xs => strings(xs)
    _ => defaults.changed_patterns
  }
  for pattern in changed_patterns {
    if pattern.contains("[") ||
      pattern.contains("{") ||
      pattern.contains("(") ||
      pattern.has_prefix("!") {
      invalid(
        "changedFilePatterns supports *, ** and ? only",
        path~,
        code="unsupported-capability",
      )
    }
  }
  {
    fixed,
    linked,
    ignore,
    update_dependencies: if property(raw, "updateInternalDependencies") ==
      Json::string("minor") {
      @model.Minor
    } else {
      @model.Patch
    },
    update_dependents: match property(raw, "updateInternalDependents") {
      String(s) => s
      _ => defaults.update_dependents
    },
    changed_patterns,
    pre_file: match property(property(raw, "pre"), "file") {
      String(s) => s
      _ => defaults.pre_file
    },
    mixed: mixed != Json::null(),
    raw,
  }
}
