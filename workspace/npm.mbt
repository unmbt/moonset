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
fn normalize_ws_root(raw : String) -> String {
  let mut clean = slash(raw).trim().to_owned()
  while clean.has_prefix("./") {
    clean = clean[2:].to_owned()
  }
  while clean.has_suffix("/") {
    clean = clean[:clean.length() - 1].to_owned()
  }
  if clean == "." {
    ""
  } else {
    clean
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
fn unquote_yaml_scalar(raw : String) -> String {
  let value = raw.trim().to_owned()
  if value.length() >= 2 &&
    (
      (value.has_prefix("\"") && value.has_suffix("\"")) ||
      (value.has_prefix("'") && value.has_suffix("'"))
    ) {
    value[1:value.length() - 1].to_owned()
  } else {
    value
  }
}

///|
fn pnpm_members(source : String) -> Array[String] {
  let result : Array[String] = []
  let mut active = false
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = strip_yaml_comment(raw.to_owned())
    let trimmed = line.trim().to_owned()
    if trimmed == "" {
      continue
    }
    let is_top_level = !line.has_prefix(" ") && !line.has_prefix("\t")
    if is_top_level && trimmed.has_prefix("packages") {
      let rest = trimmed[8:].trim().to_owned()
      if rest == ":" {
        active = true
        continue
      }
      if rest.has_prefix(":") {
        let after = rest[1:].trim().to_owned()
        if after.has_prefix("[") && after.has_suffix("]") && after.length() >= 2 {
          let inner = after[1:after.length() - 1].to_owned()
          for item in inner.split(",") {
            let v = unquote_yaml_scalar(item.to_owned())
            if v != "" {
              result.push(v)
            }
          }
          active = false
          continue
        }
        if after == "" {
          active = true
          continue
        }
      }
    }
    if active && trimmed.has_prefix("-") {
      let value = unquote_yaml_scalar(trimmed[1:].to_owned())
      if value != "" {
        result.push(value)
      }
    } else if active && is_top_level {
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
fn find_json_string_span(
  source : String,
  section : String?,
  key : String,
) -> @model.TextSpan? {
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
      guard scan_json_string_end(bytes, i) is Some(str_end) else { return None }
      let raw_lit = @utf8.decode_lossy(bytes[i:str_end])
      let parsed_key = @json.parse(raw_lit) catch { _ => Json::null() }
      let after_ws = skip_json_ws(bytes, str_end)
      if after_ws < bytes.length() && bytes[after_ws].to_int() == 0x3A {
        let val_start = skip_json_ws(bytes, after_ws + 1)
        if parsed_key is String(field_name) {
          if section is None && depth == 1 && field_name == key {
            if val_start < bytes.length() && bytes[val_start].to_int() == 0x22 {
              guard scan_json_string_end(bytes, val_start) is Some(val_end) else {
                return None
              }
              return Some({ start: val_start, end: val_end, })
            }
          } else if section is Some(sec) {
            if depth == 1 &&
              val_start < bytes.length() &&
              bytes[val_start].to_int() == 0x7B {
              active_section = field_name
            } else if depth == 2 &&
              active_section == sec &&
              field_name == key &&
              val_start < bytes.length() &&
              bytes[val_start].to_int() == 0x22 {
              guard scan_json_string_end(bytes, val_start) is Some(val_end) else {
                return None
              }
              return Some({ start: val_start, end: val_end, })
            }
          }
        }
      }
      i = str_end
      continue
    }
    i += 1
  }
  None
}

///|
fn parse_npm_publish_config(json : Json) -> @model.PublishConfig? {
  let pc = property(json, "publishConfig")
  guard pc is Object(_) else { return None }
  let access = json_string(pc, "access").bind(@model.Access::parse)
  let registry = json_string(pc, "registry")
  let directory = json_string(pc, "directory")
  if access is None && registry is None && directory is None {
    None
  } else {
    Some({ access, registry, directory, })
  }
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
  if !@engine.has_glob_meta(part) {
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
  let mut clean = slash(pattern).trim().to_owned()
  while clean.has_prefix("./") {
    clean = clean[2:].to_owned()
  }
  while clean.has_suffix("/") {
    clean = clean[:clean.length() - 1].to_owned()
  }
  if clean == "" || clean == "." {
    return [""]
  }
  if !@engine.has_glob_meta(clean) {
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
  seen : Map[String, Bool],
  overrides : Map[String, @model.UnitOverride],
  managed_root_manifests : Array[String],
) -> Unit {
  let workspace_root = normalize_ws_root(spec.root)
  let package_path = if workspace_root == "" {
    "package.json"
  } else {
    workspace_root + "/package.json"
  }
  let pnpm_ws_path = if workspace_root == "" {
    "pnpm-workspace.yaml"
  } else {
    workspace_root + "/pnpm-workspace.yaml"
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
  if !managed_root_manifests.contains(package_path) {
    managed_root_manifests.push(package_path)
  }
  let root_json = @engine.parse_json(source, package_path)
  // Real pnpm gives `pnpm-workspace.yaml` precedence over `package.json#workspaces`.
  let patterns : Array[String] = if spec.manager == @model.Pnpm {
    match reader.read(pnpm_ws_path) {
      Some(pnpm) => {
        if !managed_root_manifests.contains(pnpm_ws_path) {
          managed_root_manifests.push(pnpm_ws_path)
        }
        pnpm_members(pnpm)
      }
      None => npm_members_from_json(root_json)
    }
  } else {
    npm_members_from_json(root_json)
  }
  if spec.include_root && !patterns.contains(".") && !patterns.contains("") {
    patterns.push("")
  }
  workspaces.push({
    id: spec.id,
    root: workspace_root,
    ecosystem: @model.Npm,
    manager: spec.manager,
  })
  let members : Array[String] = []
  let excludes : Array[String] = []
  for raw_pattern in patterns {
    let mut trimmed = slash(raw_pattern).trim().to_owned()
    if trimmed.has_prefix("!") {
      let mut ex = trimmed[1:].trim().to_owned()
      while ex.has_prefix("./") {
        ex = ex[2:].to_owned()
      }
      while ex.has_suffix("/") {
        ex = ex[:ex.length() - 1].to_owned()
      }
      let full_ex = if workspace_root == "" {
        ex
      } else if ex == "" || ex == "." {
        workspace_root
      } else {
        workspace_root + "/" + ex
      }
      excludes.push(full_ex)
      continue
    }
    while trimmed.has_prefix("./") {
      trimmed = trimmed[2:].to_owned()
    }
    while trimmed.has_suffix("/") {
      trimmed = trimmed[:trimmed.length() - 1].to_owned()
    }
    let full_pat = if workspace_root == "" {
      if trimmed == "." {
        ""
      } else {
        trimmed
      }
    } else if trimmed == "" || trimmed == "." {
      workspace_root
    } else {
      workspace_root + "/" + trimmed
    }
    for candidate in package_candidates(reader, full_pat) {
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
        ["node_modules", ".git", ".mooncakes", "_build", "target"].contains(
          x.to_owned(),
        )
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
    let version = json_string(json, "version")
    let version_span = if version is Some(_) {
      find_json_string_span(source, None, "version")
    } else {
      None
    }
    let canonical = if !reader.use_git_tree {
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
    let is_private = property(json, "private") == Json::boolean(true)
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
              let (start, end) = match
                find_json_string_span(source, Some(field), dependency) {
                Some(sp) => (sp.start, sp.end)
                None => (0, 0)
              }
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
    let publish = if is_private || version is None {
      false
    } else {
      match overrides.get(id) {
        Some({ publish: Some(value), .. }) => value
        _ => true
      }
    }
    let publish_config = parse_npm_publish_config(json)
    units.push({
      id,
      native_name: name,
      ecosystem: @model.Npm,
      workspace_id: spec.id,
      root: member_path,
      manifest,
      version_path: manifest,
      version_field: "version",
      version,
      version_span,
      visibility: if is_private {
        @model.Private
      } else {
        @model.Public
      },
      publish,
      publish_config,
      dependencies,
    })
    if version is Some(_) {
      ownership.push({ path: manifest, field: "version", owner: id, })
    }
  }
}
