///|
fn property(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap_or(Json::null())
    _ => Json::null()
  }
}

///|
fn json_string(value : Json, key : String) -> String? {
  match property(value, key) {
    String(text) => Some(text)
    _ => None
  }
}

///|
fn npm_members_from_json(value : Json) -> Array[String] {
  match property(value, "workspaces") {
    Array(items) =>
      items.filter_map(x => {
        match x {
          String(pattern) => Some(pattern)
          _ => None
        }
      })
    { "packages": Array(items), .. } =>
      items.filter_map(x => {
        match x {
          String(pattern) => Some(pattern)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn strip_yaml_comment(line : String) -> String {
  let mut in_double = false
  let mut in_single = false
  let mut escaped = false
  let out : Array[Char] = []
  for ch in line.to_array() {
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
    if !in_double && !in_single && ch == '#' {
      break
    }
    out.push(ch)
  }
  String::from_array(out)
}

///|
fn pnpm_members(source : String) -> Array[String] {
  let result : Array[String] = []
  let mut active = false
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = strip_yaml_comment(raw.to_owned())
    let trimmed = line.trim().to_owned()
    if trimmed == "packages:" {
      active = true
      continue
    }
    if active && trimmed.has_prefix("-") {
      let value = trimmed[1:].trim().to_owned()
      if value.has_prefix("\"") && value.has_suffix("\"") {
        result.push(value[1:value.length() - 1].to_owned())
      } else if value.has_prefix("'") && value.has_suffix("'") {
        result.push(value[1:value.length() - 1].to_owned())
      } else if value != "" {
        result.push(value)
      }
    } else if active &&
      trimmed != "" &&
      !line.has_prefix(" ") &&
      !line.has_prefix("\t") {
      active = false
    }
  }
  result
}

///|
fn skip_json_ws(bytes : Bytes, index : Int32) -> Int32 {
  let mut i = index
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
      i += 1
    } else {
      break
    }
  }
  i
}

///|
fn scan_json_string_end(bytes : Bytes, start_quote : Int32) -> Int32? {
  let mut i = start_quote + 1
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x5C {
      i += 2
      continue
    }
    if b == 0x22 {
      return Some(i + 1)
    }
    i += 1
  }
  None
}

///|
fn find_npm_dep_span(
  source : String,
  section : String,
  key : String,
) -> (Int32, Int32) {
  let bytes = @utf8.encode(source)
  let mut depth = 0
  let mut active_section = ""
  let mut i : Int32 = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
      i += 1
      continue
    }
    if b == 0x7B || b == 0x5B {
      depth += 1
      i += 1
      continue
    }
    if b == 0x7D || b == 0x5D {
      if depth == 2 {
        active_section = ""
      }
      depth -= 1
      i += 1
      continue
    }
    if b == 0x22 {
      guard scan_json_string_end(bytes, i) is Some(str_end) else {
        return (0, 0)
      }
      let raw_lit = @utf8.decode_lossy(bytes[i:str_end])
      let parsed_key = @json.parse(raw_lit) catch { _ => Json::null() }
      let after_ws = skip_json_ws(bytes, str_end)
      if after_ws < bytes.length() && bytes[after_ws].to_int() == 0x3A {
        let val_start = skip_json_ws(bytes, after_ws + 1)
        if parsed_key is String(field_name) {
          if depth == 1 &&
            val_start < bytes.length() &&
            bytes[val_start].to_int() == 0x7B {
            active_section = field_name
          } else if depth == 2 &&
            active_section == section &&
            field_name == key &&
            val_start < bytes.length() &&
            bytes[val_start].to_int() == 0x22 {
            guard scan_json_string_end(bytes, val_start) is Some(val_end) else {
              return (0, 0)
            }
            return (val_start, val_end)
          }
        }
      }
      i = str_end
      continue
    }
    i += 1
  }
  (0, 0)
}

///|
async fn expand_glob_parts(
  reader : Reader,
  current : String,
  parts : Array[String],
  index : Int32,
  result : Array[String],
) -> Unit {
  if index >= parts.length() {
    let manifest = if current == "" {
      "package.json"
    } else {
      current + "/package.json"
    }
    if !result.contains(current) && reader.read(manifest) is Some(_) {
      result.push(current)
    }
    return
  }
  let part = parts[index]
  if part == "" || part == "." {
    expand_glob_parts(reader, current, parts, index + 1, result)
    return
  }
  if part == "**" {
    expand_glob_parts(reader, current, parts, index + 1, result)
    for child in reader.dirs(current) {
      if ["node_modules", ".git", ".mooncakes", "_build", "target"].contains(
          child,
        ) {
        continue
      }
      let next = if current == "" { child } else { current + "/" + child }
      expand_glob_parts(reader, next, parts, index, result)
    }
    return
  }
  if !part.contains("*") && !part.contains("?") {
    let next = if current == "" { part } else { current + "/" + part }
    expand_glob_parts(reader, next, parts, index + 1, result)
    return
  }
  for child in reader.dirs(current) {
    if ["node_modules", ".git", ".mooncakes", "_build", "target"].contains(
        child,
      ) {
      continue
    }
    if @engine.matches_pattern(child, part) {
      let next = if current == "" { child } else { current + "/" + child }
      expand_glob_parts(reader, next, parts, index + 1, result)
    }
  }
}

///|
async fn package_candidates(reader : Reader, pattern : String) -> Array[String] {
  let mut clean = pattern.trim().to_owned()
  while clean.has_prefix("./") {
    clean = clean[2:].to_owned()
  }
  if clean == "" || clean == "." {
    return [""]
  }
  if !clean.contains("*") && !clean.contains("?") {
    return [clean]
  }
  let parts = clean
    .split("/")
    .map(x => x.to_owned())
    .filter(x => x != "")
    .collect()
  let result : Array[String] = []
  expand_glob_parts(reader, "", parts, 0, result)
  result
}

///|
/// Discover one explicitly configured npm/pnpm workspace.
async fn discover_npm_workspace(
  reader : Reader,
  root : String,
  spec : @model.MixedWorkspaceSpec,
  units : Array[@model.ReleaseUnit],
  workspaces : Array[@model.EcosystemWorkspace],
  ownership : Array[@model.Ownership],
  _unmanaged : Array[String],
  seen : Map[String, Bool],
  overrides : Map[String, @model.UnitOverride],
) -> Unit {
  let workspace_root = slash(spec.root)
  let package_path = if workspace_root == "" {
    "package.json"
  } else {
    workspace_root + "/package.json"
  }
  let root_source = reader.read(package_path)
  guard root_source is Some(source) else {
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-workspace",
        "npm workspace has no package.json",
        path=package_path,
      ),
    )
  }
  let root_json = @engine.parse_json(source, package_path)
  let mut patterns = npm_members_from_json(root_json)
  if spec.manager == "pnpm" && patterns.is_empty() {
    if reader.read(
        if workspace_root == "" {
          "pnpm-workspace.yaml"
        } else {
          workspace_root + "/pnpm-workspace.yaml"
        },
      )
      is Some(pnpm) {
      patterns = pnpm_members(pnpm)
    }
  }
  if spec.include_root && reader.read(package_path) is Some(_) {
    patterns.push(if workspace_root == "" { "" } else { workspace_root })
  }
  workspaces.push({
    id: spec.id,
    root: workspace_root,
    ecosystem: "npm",
    manager: spec.manager,
  })
  let members : Array[String] = []
  let excludes : Array[String] = []
  for raw_pattern in patterns {
    let trimmed = raw_pattern.trim().to_owned()
    if trimmed.has_prefix("!") {
      let mut ex = trimmed[1:].trim().to_owned()
      while ex.has_prefix("./") {
        ex = ex[2:].to_owned()
      }
      let full_ex = if workspace_root == "" {
        ex
      } else if ex == "" {
        workspace_root
      } else {
        workspace_root + "/" + ex
      }
      excludes.push(full_ex)
      continue
    }
    for
      candidate in package_candidates(
        reader,
        if workspace_root == "" {
          trimmed
        } else if trimmed == "" {
          workspace_root
        } else {
          workspace_root + "/" + trimmed
        },
      ) {
      let path = if candidate == "" {
        "package.json"
      } else {
        slash(candidate + "/package.json")
      }
      if !members.contains(candidate) && reader.read(path) is Some(_) {
        members.push(candidate)
      }
    }
  }
  let filtered_members = members.filter(m => {
    !excludes.any(ex => @engine.matches_pattern(m, ex))
  })
  for member_path in filtered_members {
    if member_path
      .split("/")
      .any(x => {
        ["node_modules", "dist", "build", "target"].contains(x.to_owned())
      }) {
      continue
    }
    if nested_checkout(reader, member_path) {
      continue
    }
    let manifest = if member_path == "" {
      "package.json"
    } else {
      slash(member_path + "/package.json")
    }
    let source = reader.read(manifest).unwrap()
    let json = @engine.parse_json(source, manifest)
    guard json_string(json, "name") is Some(name) else {
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-package",
          "package.json requires name",
          path=manifest,
        ),
      )
    }
    guard json_string(json, "version") is Some(version) else {
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-package",
          "package.json requires version",
          path=manifest,
        ),
      )
    }
    let canonical = if reader.head is None {
      @fs.realpath(@path.Path(root).join(@path.Path(manifest)).to_string())
    } else {
      manifest
    }
    if seen.contains(canonical) {
      raise @model.Invalid(
        @model.diagnostic(
          "ambiguous-owner",
          "Package has multiple workspace owners",
          path=manifest,
        ),
      )
    }
    seen[canonical] = true
    let private = property(json, "private") == Json::boolean(true)
    let id = "npm:" + name
    if units.any(unit => unit.id == id) {
      raise @model.Invalid(
        @model.diagnostic(
          "duplicate-unit",
          "Duplicate npm package: " + id,
          path=manifest,
        ),
      )
    }
    let dependencies : Array[@model.DependencyEdge] = []
    for
      field in [
        "dependencies", "devDependencies", "optionalDependencies", "peerDependencies",
      ] {
      match property(json, field) {
        Object(items) =>
          for dependency, requirement in items {
            if requirement is String(value) {
              let kind = match field {
                "devDependencies" => @model.Development
                "optionalDependencies" => @model.Optional
                "peerDependencies" => @model.Peer
                _ => @model.Runtime
              }
              let (start, end) = find_npm_dep_span(source, field, dependency)
              dependencies.push({
                producer: "npm:" + dependency,
                requirement: value,
                kind,
                path: manifest,
                start,
                end,
                target_condition: None,
              })
            }
          }
        _ => ()
      }
    }
    // npm's native private=true prohibition cannot be overridden by moonset policy.
    let publish = if private {
      false
    } else {
      match overrides.get(id) {
        Some({ publish: Some(value), .. }) => value
        _ => true
      }
    }
    units.push({
      id,
      native_name: name,
      ecosystem: "npm",
      workspace_id: spec.id,
      root: member_path,
      manifest,
      version_path: manifest,
      version_field: "version",
      version: Some(version),
      visibility: if private {
        "private"
      } else {
        "public"
      },
      publish,
      dependencies,
    })
    ownership.push({ path: manifest, field: "version", owner: id, })
  }
}
