///|
fn cargo_publish_allowed(val : TomlVal?) -> Bool {
  match val {
    None => true
    Some(Bool(flag)) => flag
    Some(Arr(items)) =>
      items.any(item => {
        match item {
          Str(reg, _) => reg == "crates-io"
          _ => false
        }
      })
    _ => true
  }
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
  if !@engine.has_glob_meta(part) {
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
  expand_cargo_glob(reader, workspace_root, "", parts, 0, result)
  result
}

///|
fn extract_cargo_dep_from_val(
  dep_key : String,
  val : TomlVal,
  ws_deps : Map[String, TomlVal]?,
  member_manifest : String,
  ws_manifest : String,
  base_kind : @model.DependencyKind,
  target_condition : String?,
) -> @model.DependencyEdge? {
  match val {
    Str(req, span) =>
      Some({
        producer: "cargo:" + dep_key,
        requirement: req,
        kind: base_kind,
        path: member_manifest,
        start: span.start,
        end: span.end,
        target_condition,
      })
    Tbl(tbl) => {
      let is_optional = toml_bool(tbl, "optional") == Some(true)
      let kind = if is_optional { @model.Optional } else { base_kind }
      let uses_ws = toml_bool(tbl, "workspace") == Some(true)
      let effective_val : TomlVal? = if uses_ws {
        ws_deps.bind(m => m.get(dep_key))
      } else {
        Some(val)
      }
      let dep_path = if uses_ws { ws_manifest } else { member_manifest }
      match effective_val {
        Some(Str(req, span)) =>
          Some({
            producer: "cargo:" + dep_key,
            requirement: req,
            kind,
            path: dep_path,
            start: span.start,
            end: span.end,
            target_condition,
          })
        Some(Tbl(eff_tbl)) => {
          let pkg_name = match toml_string(eff_tbl, "package") {
            Some((renamed, _)) => renamed
            None => dep_key
          }
          match toml_string(eff_tbl, "version") {
            Some((req, span)) =>
              Some({
                producer: "cargo:" + pkg_name,
                requirement: req,
                kind,
                path: dep_path,
                start: span.start,
                end: span.end,
                target_condition,
              })
            None => None
          }
        }
        _ => None
      }
    }
    _ => None
  }
}

///|
fn collect_cargo_dep_section(
  section_tbl : Map[String, TomlVal],
  ws_deps : Map[String, TomlVal]?,
  member_manifest : String,
  ws_manifest : String,
  base_kind : @model.DependencyKind,
  target_condition : String?,
  out : Array[@model.DependencyEdge],
) -> Unit {
  for dep_key, val in section_tbl {
    if extract_cargo_dep_from_val(
        dep_key, val, ws_deps, member_manifest, ws_manifest, base_kind, target_condition,
      )
      is Some(edge) {
      if !out.any(x => {
          x.producer == edge.producer &&
          x.path == edge.path &&
          x.start == edge.start
        }) {
        out.push(edge)
      }
    }
  }
}

///|
fn collect_cargo_dependencies(
  doc : TomlDoc,
  ws_doc : TomlDoc,
  member_manifest : String,
  ws_manifest : String,
) -> Array[@model.DependencyEdge] {
  let ws_deps = ws_doc.get_table(["workspace", "dependencies"])
  let out : Array[@model.DependencyEdge] = []
  let pairs : Array[(String, @model.DependencyKind)] = [
    ("dependencies", @model.Runtime),
    ("dev-dependencies", @model.Development),
    ("build-dependencies", @model.Build),
  ]
  for pair in pairs {
    if doc.get_table([pair.0]) is Some(sec) {
      collect_cargo_dep_section(
        sec,
        ws_deps,
        member_manifest,
        ws_manifest,
        pair.1,
        None,
        out,
      )
    }
  }
  if doc.get_table(["target"]) is Some(targets_tbl) {
    for cond, target_val in targets_tbl {
      if target_val is Tbl(t_sub) {
        for pair in pairs {
          if t_sub.get(pair.0) is Some(Tbl(sec)) {
            collect_cargo_dep_section(
              sec,
              ws_deps,
              member_manifest,
              ws_manifest,
              pair.1,
              Some(cond),
              out,
            )
          }
        }
      }
    }
  }
  out
}

///|
/// Discover an explicit Cargo workspace (or single-crate Cargo root) using a
/// proper span-preserving TOML parser.
async fn discover_cargo_workspace(
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
  let ws_root = normalize_ws_root(spec.root)
  let manifest = if ws_root == "" {
    "Cargo.toml"
  } else {
    ws_root + "/Cargo.toml"
  }
  guard reader.read(manifest) is Some(workspace_source) else {
    fail_input("Cargo workspace has no Cargo.toml", path=manifest)
    return
  }
  if !managed_root_manifests.contains(manifest) {
    managed_root_manifests.push(manifest)
  }
  let ws_doc = parse_toml(workspace_source)
  let ws_pkg_tbl = ws_doc.get_table(["workspace", "package"])
  let inherited_version = ws_pkg_tbl.bind(t => toml_string(t, "version"))
  let inherited_publish_val = ws_pkg_tbl.bind(t => t.get("publish"))
  let ws_tbl = ws_doc.get_table(["workspace"])
  let member_patterns = match ws_tbl {
    Some(t) => toml_string_array(t, "members")
    None => []
  }
  let excluded_patterns = match ws_tbl {
    Some(t) => toml_string_array(t, "exclude")
    None => []
  }
  let norm_excludes = excluded_patterns.map(ex => {
    let mut clean = slash(ex).trim().to_owned()
    while clean.has_prefix("./") {
      clean = clean[2:].to_owned()
    }
    while clean.has_suffix("/") {
      clean = clean[:clean.length() - 1].to_owned()
    }
    clean
  })
  let members : Array[String] = []
  for pattern in member_patterns {
    for candidate in cargo_candidates(reader, ws_root, pattern) {
      if !members.contains(candidate) &&
        !norm_excludes.any(ex => @engine.matches_pattern(candidate, ex)) {
        members.push(candidate)
      }
    }
  }
  let root_pkg_name = ws_doc
    .get_table(["package"])
    .bind(t => toml_string(t, "name"))
  if spec.include_root && root_pkg_name is Some(_) && !members.contains("") {
    members.push("")
  }
  if members.is_empty() {
    fail_input("Cargo workspace members must not be empty", path=manifest)
  }
  workspaces.push({
    id: spec.id,
    root: ws_root,
    ecosystem: @model.Cargo,
    manager: @model.Cargo,
  })
  for package_member in members {
    let member_path = if package_member == "" {
      ws_root
    } else if ws_root == "" {
      package_member
    } else {
      ws_root + "/" + package_member
    }
    if member_path
      .split("/")
      .any(x => {
        ["node_modules", "_build", "target", ".mooncakes", ".git"].contains(
          x.to_owned(),
        )
      }) {
      continue
    }
    if nested_checkout(reader, member_path) {
      continue
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
    let canonical = if !reader.use_git_tree {
      @fs.realpath(join(root, member_manifest))
    } else {
      member_manifest
    }
    let doc = parse_toml(source)
    guard doc.get_table(["package"]) is Some(pkg_tbl) else {
      fail_input(
        "Cargo member is missing [package] table",
        path=member_manifest,
      )
      continue
    }
    guard toml_string(pkg_tbl, "name") is Some((name, _)) else {
      fail_input("Cargo package requires name", path=member_manifest)
      continue
    }
    let direct_version = toml_string(pkg_tbl, "version")
    let inherits_version = toml_is_workspace_inherited(pkg_tbl.get("version"))
    let (version, version_span, version_path, version_field) : (
      String?,
      @model.TextSpan?,
      String,
      String,
    ) = match direct_version {
      Some((v, sp)) => (Some(v), Some(sp), member_manifest, "package")
      None =>
        if inherits_version {
          match inherited_version {
            Some((v, sp)) => (Some(v), Some(sp), manifest, "workspace.package")
            None => {
              fail_input(
                "Cargo package inherits version.workspace = true, but [workspace.package].version is missing",
                path=member_manifest,
              )
              (None, None, manifest, "workspace.package")
            }
          }
        } else {
          (None, None, member_manifest, "package")
        }
    }
    let id = "cargo:" + name
    if seen.contains(canonical) || units.any(x => x.id == id) {
      fail_input("Duplicate Cargo package: " + id, path=member_manifest)
    }
    seen[canonical] = true
    let publish_val = pkg_tbl.get("publish")
    let effective_publish_val = if toml_is_workspace_inherited(publish_val) {
      inherited_publish_val
    } else {
      publish_val
    }
    let cargo_allows_publish = cargo_publish_allowed(effective_publish_val)
    let publish = cargo_allows_publish &&
      overrides.get(id).map(x => x.publish).unwrap_or(None) != Some(false)
    let dependencies = collect_cargo_dependencies(
      doc, ws_doc, member_manifest, manifest,
    )
    units.push({
      id,
      native_name: name,
      ecosystem: @model.Cargo,
      workspace_id: spec.id,
      root: member_path,
      manifest: member_manifest,
      version_path,
      version_field,
      version,
      version_span,
      visibility: if cargo_allows_publish {
        @model.Public
      } else {
        @model.Private
      },
      publish,
      publish_config: None,
      dependencies,
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
}
