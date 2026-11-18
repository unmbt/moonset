///|
fn strip_toml_comment(line : String) -> String {
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
fn cargo_value(source : String, section : String, key : String) -> String? {
  let mut active = ""
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = strip_toml_comment(raw.to_owned()).trim().to_owned()
    if line.has_prefix("[") && line.has_suffix("]") {
      active = line[1:line.length() - 1].trim().to_owned()
      continue
    }
    if active == section && line.has_prefix(key) {
      let after_key = line[key.length():].trim().to_owned()
      if after_key.has_prefix("=") {
        let value = after_key[1:].trim().to_owned()
        if (value.has_prefix("\"") && value.has_suffix("\"")) ||
          (value.has_prefix("'") && value.has_suffix("'")) {
          if value.length() >= 2 {
            return Some(value[1:value.length() - 1].to_owned())
          }
        }
      }
    }
  }
  None
}

///|
fn cargo_raw_value(source : String, section : String, key : String) -> String? {
  let mut active = ""
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = strip_toml_comment(raw.to_owned()).trim().to_owned()
    if line.has_prefix("[") && line.has_suffix("]") {
      active = line[1:line.length() - 1].trim().to_owned()
    } else if active == section && line.has_prefix(key) {
      let after_key = line[key.length():].trim().to_owned()
      if after_key.has_prefix("=") {
        return Some(after_key[1:].trim().to_owned())
      }
    }
  }
  None
}

///|
fn cargo_array(source : String, key : String) -> Array[String] {
  let result : Array[String] = []
  let mut active = false
  let mut collecting = false
  let mut values = ""
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line == "[workspace]" {
      active = true
      continue
    }
    if active && line.has_prefix(key + " =") {
      collecting = true
      values = line.split("=").last().unwrap_or("").to_owned()
    } else if collecting {
      values = values + " " + line
    }
    if collecting && values.contains("]") {
      for
        item in values
        .split("[")
        .last()
        .unwrap_or("")
        .replace_all(old="]", new="")
        .split(",") {
        let value = item.trim().replace_all(old="\"", new="")
        if value != "" {
          result.push(value.to_owned())
        }
      }
      return result
    }
    if active && line.has_prefix("[") {
      active = false
    }
  }
  result
}

///|
fn cargo_members(source : String) -> Array[String] {
  cargo_array(source, "members")
}

///|
async fn expand_cargo_glob(
  reader : Reader,
  workspace_root : String,
  current : String,
  parts : Array[String],
  index : Int32,
  result : Array[String],
) -> Unit {
  if index >= parts.length() {
    let manifest_rel = if workspace_root == "" {
      if current == "" {
        "Cargo.toml"
      } else {
        current + "/Cargo.toml"
      }
    } else if current == "" {
      workspace_root + "/Cargo.toml"
    } else {
      workspace_root + "/" + current + "/Cargo.toml"
    }
    if !result.contains(current) && reader.read(manifest_rel) is Some(_) {
      result.push(current)
    }
    return
  }
  let part = parts[index]
  if part == "" || part == "." {
    expand_cargo_glob(reader, workspace_root, current, parts, index + 1, result)
    return
  }
  let dir_rel = if workspace_root == "" {
    current
  } else if current == "" {
    workspace_root
  } else {
    workspace_root + "/" + current
  }
  if part == "**" {
    expand_cargo_glob(reader, workspace_root, current, parts, index + 1, result)
    for child in reader.dirs(dir_rel) {
      if [".git", "target", "_build", "node_modules", ".mooncakes"].contains(
          child,
        ) {
        continue
      }
      let next = if current == "" { child } else { current + "/" + child }
      expand_cargo_glob(reader, workspace_root, next, parts, index, result)
    }
    return
  }
  if !part.contains("*") && !part.contains("?") {
    let next = if current == "" { part } else { current + "/" + part }
    expand_cargo_glob(reader, workspace_root, next, parts, index + 1, result)
    return
  }
  for child in reader.dirs(dir_rel) {
    if [".git", "target", "_build", "node_modules", ".mooncakes"].contains(
        child,
      ) {
      continue
    }
    if @engine.matches_pattern(child, part) {
      let next = if current == "" { child } else { current + "/" + child }
      expand_cargo_glob(reader, workspace_root, next, parts, index + 1, result)
    }
  }
}

///|
async fn cargo_candidates(
  reader : Reader,
  workspace_root : String,
  pattern : String,
) -> Array[String] {
  let mut clean = pattern.trim().to_owned()
  while clean.has_prefix("./") {
    clean = clean[2:].to_owned()
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
  expand_cargo_glob(reader, workspace_root, "", parts, 0, result)
  result
}

///|
priv struct CargoEntry {
  section : String
  key : String
  raw : String
  offset : Int32
}

///|
fn cargo_entries(source : String) -> Array[CargoEntry] {
  let result : Array[CargoEntry] = []
  let bytes = @utf8.encode(source)
  let mut section = ""
  let mut pos : Int32 = 0
  while pos <= bytes.length() {
    let mut nl = pos
    while nl < bytes.length() && bytes[nl].to_int() != 0x0A {
      nl += 1
    }
    let line_end = if nl > pos && bytes[nl - 1].to_int() == 0x0D {
      nl - 1
    } else {
      nl
    }
    let line = @utf8.decode_lossy(bytes[pos:line_end])
    let clean = strip_toml_comment(line)
    let trimmed = clean.trim().to_owned()
    if trimmed.has_prefix("[") && trimmed.has_suffix("]") {
      section = trimmed[1:trimmed.length() - 1].trim().to_owned()
    } else if trimmed != "" && clean.contains("=") {
      match clean.find("=") {
        Some(eq_char_idx) => {
          let key = clean[:eq_char_idx].trim().to_owned()
          let value_part = clean[eq_char_idx + 1:]
          let raw_value = value_part.trim().to_owned()
          let prefix_bytes = @utf8.encode(clean[:eq_char_idx + 1].to_owned()).length()
          let mut val_offset = pos + prefix_bytes
          while val_offset < line_end &&
                (
                  bytes[val_offset].to_int() == 0x20 ||
                  bytes[val_offset].to_int() == 0x09
                ) {
            val_offset += 1
          }
          result.push({ section, key, raw: raw_value, offset: val_offset, })
        }
        None => ()
      }
    }
    if nl >= bytes.length() {
      break
    }
    pos = nl + 1
  }
  result
}

///|
fn cargo_attr(raw : String, key : String) -> String? {
  let needle = key + " ="
  match raw.find(needle) {
    Some(index) => {
      let tail = raw[index + needle.length():].trim().to_owned()
      let value = tail.split(",").next().unwrap_or("").trim().to_owned()
      match value.find("\"") {
        Some(first) =>
          match value[first + 1:].find("\"") {
            Some(length) => Some(value[first + 1:first + 1 + length].to_owned())
            None => Some(value)
          }
        None => Some(value)
      }
    }
    None => None
  }
}

///|
fn cargo_req(entry : CargoEntry) -> String? {
  if entry.raw.has_prefix("\"") && entry.raw.has_suffix("\"") {
    Some(entry.raw[1:entry.raw.length() - 1].to_owned())
  } else {
    cargo_attr(entry.raw, "version")
  }
}

///|
fn find_toml_inline_key_offset(raw : String, target_key : String) -> Int32? {
  let bytes = @utf8.encode(raw)
  let key_bytes = @utf8.encode(target_key)
  let mut in_double = false
  let mut in_single = false
  let mut escaped = false
  let mut i : Int32 = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if escaped {
      escaped = false
      i += 1
      continue
    }
    if in_double {
      if b == 0x5C {
        escaped = true
      } else if b == 0x22 {
        in_double = false
      }
      i += 1
      continue
    }
    if in_single {
      if b == 0x27 {
        in_single = false
      }
      i += 1
      continue
    }
    if b == 0x22 {
      in_double = true
      i += 1
      continue
    }
    if b == 0x27 {
      in_single = true
      i += 1
      continue
    }
    if i + key_bytes.length() <= bytes.length() {
      let prev_ok = i == 0 ||
        bytes[i - 1].to_int() == 0x20 ||
        bytes[i - 1].to_int() == 0x09 ||
        bytes[i - 1].to_int() == 0x7B ||
        bytes[i - 1].to_int() == 0x2C
      if prev_ok {
        let mut matched = true
        for k in 0..<key_bytes.length() {
          if bytes[i + k] != key_bytes[k] {
            matched = false
            break
          }
        }
        if matched {
          let mut after = i + key_bytes.length()
          while after < bytes.length() &&
                (bytes[after].to_int() == 0x20 || bytes[after].to_int() == 0x09) {
            after += 1
          }
          if after < bytes.length() && bytes[after].to_int() == 0x3D {
            return Some(after + 1)
          }
        }
      }
    }
    i += 1
  }
  None
}

///|
fn cargo_req_span(entry : CargoEntry) -> (Int32, Int32) {
  let raw = entry.raw
  let bytes = @utf8.encode(raw)
  let base_offset : Int32 = if raw.has_prefix("\"") || raw.has_prefix("'") {
    0
  } else {
    match find_toml_inline_key_offset(raw, "version") {
      Some(idx) => idx
      None => return (0, 0)
    }
  }
  let mut i = base_offset
  while i < bytes.length() &&
        bytes[i].to_int() != 0x22 &&
        bytes[i].to_int() != 0x27 {
    i += 1
  }
  if i >= bytes.length() {
    return (0, 0)
  }
  let quote = bytes[i].to_int()
  let val_start = i + 1
  let mut val_end = val_start
  while val_end < bytes.length() && bytes[val_end].to_int() != quote {
    val_end += 1
  }
  if val_end >= bytes.length() {
    return (0, 0)
  }
  (entry.offset + val_start, entry.offset + val_end)
}

///|
fn cargo_dependency_kind(
  section : String,
  raw : String,
) -> @model.DependencyKind {
  if raw.contains("optional = true") {
    @model.Optional
  } else if section.has_suffix("dev-dependencies") {
    @model.Development
  } else if section.has_suffix("build-dependencies") {
    @model.Build
  } else {
    @model.Runtime
  }
}

///|
fn cargo_target_condition(section : String) -> String? {
  if section.has_prefix("target.") {
    match section.find(".dependencies") {
      Some(index) =>
        Some(
          section[7:index]
          .to_owned()
          .replace_all(old="'", new="")
          .replace_all(old="\"", new=""),
        )
      None => None
    }
  } else {
    None
  }
}

///|
/// Discover an explicit Cargo workspace with native workspace package versions.
async fn discover_cargo_workspace(
  reader : Reader,
  spec : @model.MixedWorkspaceSpec,
  units : Array[@model.ReleaseUnit],
  workspaces : Array[@model.EcosystemWorkspace],
  ownership : Array[@model.Ownership],
  seen : Map[String, Bool],
  overrides : Map[String, @model.UnitOverride],
) -> Unit {
  let ws_root = if spec.root == "." || spec.root == "" {
    ""
  } else {
    slash(spec.root)
  }
  let manifest = if ws_root == "" {
    "Cargo.toml"
  } else {
    ws_root + "/Cargo.toml"
  }
  guard reader.read(manifest) is Some(workspace_source) else {
    fail_input("Cargo workspace has no Cargo.toml", path=manifest)
    return
  }
  let inherited = cargo_value(workspace_source, "workspace.package", "version")
  let member_patterns = cargo_members(workspace_source)
  let excluded_patterns = cargo_array(workspace_source, "exclude")
  let members : Array[String] = []
  for pattern in member_patterns {
    for candidate in cargo_candidates(reader, ws_root, pattern) {
      if !members.contains(candidate) &&
        !excluded_patterns.any(exclude => {
          candidate == exclude ||
          (
            exclude.has_suffix("/*") &&
            candidate.has_prefix(exclude[:exclude.length() - 1])
          )
        }) {
        members.push(candidate)
      }
    }
  }
  if members.is_empty() {
    fail_input("Cargo workspace members must not be empty", path=manifest)
  }
  if spec.include_root &&
    cargo_value(workspace_source, "package", "name") is Some(_) {
    members.push("")
  }
  workspaces.push({
    id: spec.id,
    root: ws_root,
    ecosystem: "cargo",
    manager: "cargo",
  })
  for package_member in members {
    let member_path = if package_member == "" {
      ws_root
    } else if ws_root == "" {
      package_member
    } else {
      ws_root + "/" + package_member
    }
    let member_manifest = if member_path == "" {
      "Cargo.toml"
    } else {
      member_path + "/Cargo.toml"
    }
    guard reader.read(member_manifest) is Some(source) else {
      fail_input(
        "Cargo workspace member is missing Cargo.toml",
        path=member_manifest,
      )
      continue
    }
    guard cargo_value(source, "package", "name") is Some(name) else {
      fail_input("Cargo package requires name", path=member_manifest)
      continue
    }
    let direct_version = cargo_value(source, "package", "version")
    let inherited_version = if source.contains("version.workspace = true") {
      inherited
    } else {
      direct_version
    }
    let version = match inherited_version {
      Some(value) => Some(value)
      None => inherited
    }
    let version_path = if direct_version is Some(_) {
      member_manifest
    } else {
      manifest
    }
    let version_field = if direct_version is Some(_) {
      "package"
    } else {
      "workspace.package"
    }
    let id = "cargo:" + name
    if seen.contains(member_manifest) || units.any(x => x.id == id) {
      fail_input("Duplicate Cargo package: " + id, path=member_manifest)
    }
    seen[member_manifest] = true
    let raw_publish = cargo_raw_value(source, "package", "publish")
    let cargo_allows_publish = match raw_publish {
      None => true
      Some(raw) => {
        let clean = raw.trim().to_owned()
        if clean == "false" {
          false
        } else if clean.has_prefix("[") {
          clean.contains("\"crates-io\"") || clean.contains("'crates-io'")
        } else {
          true
        }
      }
    }
    let publish = cargo_allows_publish &&
      overrides.get(id).map(x => x.publish).unwrap_or(None) != Some(false)
    units.push({
      id,
      native_name: name,
      ecosystem: "cargo",
      workspace_id: spec.id,
      root: member_path,
      manifest: member_manifest,
      version_path,
      version_field,
      version,
      visibility: if publish {
        "public"
      } else {
        "private"
      },
      publish,
      dependencies: [],
    })
    if version is Some(_) &&
      !ownership.any(x => x.path == version_path && x.field == "package.version") {
      ownership.push({
        path: version_path,
        field: "package.version",
        owner: id,
      })
    }
  }
  let unit_ids = units.filter(x => x.workspace_id == spec.id).map(x => x.id)
  for id in unit_ids {
    let mut current : @model.ReleaseUnit? = None
    for unit in units {
      if unit.id == id {
        current = Some(unit)
      }
    }
    match current {
      Some(unit) => {
        let source = reader.read(unit.manifest).unwrap()
        let dependencies : Array[@model.DependencyEdge] = []
        for entry in cargo_entries(source) {
          let is_dependency_section = entry.section == "dependencies" ||
            entry.section == "dev-dependencies" ||
            entry.section == "build-dependencies" ||
            entry.section.has_suffix(".dependencies") ||
            entry.section.has_suffix(".dev-dependencies") ||
            entry.section.has_suffix(".build-dependencies")
          if !is_dependency_section {
            continue
          }
          let mut ws_entry : CargoEntry? = None
          if entry.raw.contains("workspace = true") {
            for candidate in cargo_entries(workspace_source) {
              if candidate.section == "workspace.dependencies" &&
                candidate.key == entry.key {
                ws_entry = Some(candidate)
              }
            }
          }
          let effective = ws_entry.unwrap_or(entry)
          let package_name = cargo_attr(effective.raw, "package").unwrap_or(
            entry.key,
          )
          let producer = "cargo:" + package_name
          let range = cargo_req(effective).unwrap_or("*")
          let (start, end) = cargo_req_span(effective)
          let dependency_path = if ws_entry is Some(_) {
            manifest
          } else {
            unit.manifest
          }
          if start > 0 &&
            !dependencies.any(x => {
              x.producer == producer &&
              x.path == dependency_path &&
              x.start == start
            }) {
            dependencies.push({
              producer,
              requirement: range,
              kind: cargo_dependency_kind(entry.section, entry.raw),
              path: dependency_path,
              start,
              end,
              target_condition: cargo_target_condition(entry.section),
            })
          }
        }
        let index = units.search_by(x => x.id == id).unwrap_or(-1)
        if index >= 0 {
          units[index] = { ..unit, dependencies, }
        }
      }
      None => ()
    }
  }
}
