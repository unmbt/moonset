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
fn pnpm_members(source : String) -> Array[String] {
  let result : Array[String] = []
  let mut active = false
  for line in source.replace_all(old="\r\n", new="\n").split("\n") {
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
async fn package_candidates(root : String, pattern : String) -> Array[String] {
  let clean = pattern.trim().replace_all(old="./", new="")
  if !clean.contains("*") && !clean.contains("?") {
    return [clean.to_owned()]
  }
  let parts = clean.split("/").map(x => x.to_owned()).collect()
  let result : Array[String] = []
  let wildcard = parts.search_by(x => x.contains("*") || x.contains("?"))
  guard wildcard is Some(index) else { return result }
  let parent = parts[:index].join("/")
  let directory = @path.Path(root).join(@path.Path(parent)).to_string()
  if !@fs.exists(directory) {
    return result
  }
  for child in @fs.readdir(directory) {
    if @engine.matches_pattern(child, parts[index]) {
      let child_path = if parent == "" { child } else { parent + "/" + child }
      if index + 1 == parts.length() {
        result.push(child_path)
      } else {
        let suffix = parts[index + 1:].join("/")
        let candidate = child_path + "/" + suffix
        if !candidate.contains("*") &&
          @fs.exists(
            @path.Path(root)
            .join(@path.Path(candidate))
            .join(@path.Path("package.json"))
            .to_string(),
          ) {
          result.push(candidate)
        }
      }
    }
  }
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
  for pattern in patterns {
    for
      candidate in package_candidates(
        root,
        if workspace_root == "" {
          pattern
        } else if pattern == "" {
          workspace_root
        } else {
          workspace_root + "/" + pattern
        },
      ) {
      let path = slash(candidate + "/package.json")
      if !members.contains(candidate) && reader.read(path) is Some(_) {
        members.push(candidate)
      }
    }
  }
  for member_path in members {
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
    let manifest = slash(member_path + "/package.json")
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
              dependencies.push({
                producer: "npm:" + dependency,
                requirement: value,
                kind: @model.Runtime,
                path: manifest,
                start: 0,
                end: 0,
              })
            }
          }
        _ => ()
      }
    }
    let publish = match overrides.get(id) {
      Some({ publish: Some(value), .. }) => value
      _ => !private
    }
    units.push({
      id,
      native_name: name,
      ecosystem: "npm",
      workspace_id: spec.id,
      root: member_path,
      manifest,
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
