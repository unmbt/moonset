///|
fn cargo_value(source : String, section : String, key : String) -> String? {
  let mut active = ""
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("[") && line.has_suffix("]") {
      active = line[1:line.length() - 1].to_owned()
      continue
    }
    if active == section && line.has_prefix(key + " =") {
      let value = line.split("=").last().unwrap_or("").trim().to_owned()
      if value.has_prefix("\"") && value.has_suffix("\"") {
        return Some(value[1:value.length() - 1].to_owned())
      }
    }
  }
  None
}

///|
fn cargo_raw_value(source : String, section : String, key : String) -> String? {
  let mut active = ""
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw.trim().to_owned()
    if line.has_prefix("[") && line.has_suffix("]") {
      active = line[1:line.length() - 1].to_owned()
    } else if active == section && line.has_prefix(key + " =") {
      return Some(line.split("=").last().unwrap_or("").trim().to_owned())
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
async fn cargo_candidates(
  reader : Reader,
  workspace_root : String,
  pattern : String,
) -> Array[String] {
  let clean = pattern.trim().replace_all(old="./", new="")
  if !clean.contains("*") && !clean.contains("?") {
    return [clean.to_owned()]
  }
  let parts = clean.split("/").map(x => x.to_owned()).collect()
  let wildcard = parts.search_by(x => x.contains("*") || x.contains("?"))
  guard wildcard is Some(index) else { return [] }
  let parent = parts[:index].join("/")
  let directory_rel = if workspace_root == "" {
    parent
  } else if parent == "" {
    workspace_root
  } else {
    workspace_root + "/" + parent
  }
  let directory = join(reader.root, directory_rel)
  if !@fs.exists(directory) {
    return []
  }
  let result : Array[String] = []
  for child in @fs.readdir(directory) {
    if !@engine.matches_pattern(child, parts[index]) {
      continue
    }
    let prefix = if parent == "" { child } else { parent + "/" + child }
    let suffix = if index + 1 == parts.length() {
      ""
    } else {
      "/" + parts[index + 1:].join("/")
    }
    let candidate = prefix + suffix
    let full = if workspace_root == "" {
      candidate
    } else {
      workspace_root + "/" + candidate
    }
    if reader.read(full + "/Cargo.toml") is Some(_) {
      result.push(candidate)
    }
  }
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
  let mut section = ""
  let mut offset = 0
  for raw_line in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.to_owned()
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("[") && trimmed.has_suffix("]") {
      section = trimmed[1:trimmed.length() - 1].to_owned()
    } else if trimmed != "" && !trimmed.has_prefix("#") && line.contains("=") {
      match line.find("=") {
        Some(index) => {
          let value_source = line[index + 1:]
          let raw_value = value_source.trim().to_owned()
          let leading = value_source.length() - value_source.trim().length()
          result.push({
            section,
            key: line[:index].trim().to_owned(),
            raw: raw_value,
            offset: offset + index + 1 + leading,
          })
        }
        None => ()
      }
    }
    offset += line.length() + 1
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
fn cargo_req_span(entry : CargoEntry) -> (Int32, Int32) {
  let raw = entry.raw
  let search = if raw.has_prefix("\"") {
    raw
  } else {
    let version_index = raw.find("version").unwrap_or(0)
    raw[version_index:].to_owned()
  }
  match search.find("\"") {
    Some(first) =>
      match search[first + 1:].find("\"") {
        Some(length) => {
          let prefix = if raw.has_prefix("\"") {
            0
          } else {
            raw.find("version").unwrap_or(0)
          }
          let start = entry.offset + prefix + first + 1
          (start, start + length)
        }
        None => (0, 0)
      }
    None => (0, 0)
  }
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
    let publish = cargo_raw_value(source, "package", "publish") != Some("false") &&
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
