///|
pub(all) struct LoadedWorkspace {
  snapshot : @model.WorkspaceSnapshot
  changesets : Array[@model.Changeset]
  pre : @model.PreState?
  changeset_directory : String
}

///|
async fn locate(
  cwd : String,
  config_path : String?,
  since : String?,
) -> (String, String) {
  let start = @fs.realpath(cwd)
  let head_files = if since is Some(_) {
    let repo = git(start, ["rev-parse", "--show-toplevel"]).trim().to_owned()
    let paths = git(repo, ["ls-tree", "-r", "--name-only", "-z", "HEAD"])
      .split("\u0000")
      .map(x => join(repo, x.to_owned()))
      .collect()
    Some(paths)
  } else {
    None
  }
  if config_path is Some(path) {
    let absolute = if @path.Path(path).is_absolute() {
      path
    } else {
      join(start, path)
    }
    if head_files is None && !@fs.exists(absolute) {
      fail_input("Explicit config does not exist", path=absolute)
    }
    let root = @fs.realpath(parent(parent(absolute)))
    return (root, relative(root, absolute))
  }
  let mut cursor = start
  let mut single : String? = None
  for ;; {
    let has_config = match head_files {
      Some(paths) => paths.contains(join(cursor, ".changeset/config.json"))
      None => @fs.exists(join(cursor, ".changeset/config.json"))
    }
    let has_work = match head_files {
      Some(paths) => paths.contains(join(cursor, "moon.work"))
      None => @fs.exists(join(cursor, "moon.work"))
    }
    let has_mod = match head_files {
      Some(paths) => paths.contains(join(cursor, "moon.mod"))
      None => @fs.exists(join(cursor, "moon.mod"))
    }
    if has_config || has_work {
      return (cursor, ".changeset/config.json")
    }
    if single is None && has_mod {
      single = Some(cursor)
    }
    if @fs.exists(join(cursor, ".git")) || parent(cursor) == cursor {
      break
    }
    cursor = parent(cursor)
  }
  match single {
    Some(root) => (root, ".changeset/config.json")
    None => {
      fail_input(
        "No MoonBit module, workspace or release config found",
        path=start,
      )
      (start, ".changeset/config.json")
    }
  }
}

///|
fn manifest_document(
  kind : @manifest.Kind,
  source : String,
  path : String,
) -> @manifest.Document raise @model.MoonsetError {
  let document = @manifest.parse(kind, source, path~)
  if document.diagnostics.get(0) is Some(error) {
    let prefix = @utf8.decode_lossy(document.source[:error.start])
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-manifest",
        error.message,
        path~,
        line=prefix.split("\n").count(),
        column=prefix.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
      ),
    )
  }
  document
}

///|
async fn nested_checkout(reader : Reader, path : String) -> Bool {
  let mut cursor = path
  while cursor != "" && cursor != "." {
    match reader.git_root {
      Some(root) => {
        let key = relative(root, join(reader.root, cursor))
        if reader.tree.get(key) == Some("160000") {
          return true
        }
      }
      None =>
        if @fs.exists(join(reader.root, join(cursor, ".git"))) {
          return true
        }
    }
    cursor = slash(parent(cursor))
  }
  false
}

///|
pub async fn discover(
  cwd : String,
  config_path? : String,
  since? : String,
) -> LoadedWorkspace {
  let (root, config_file) = locate(cwd, config_path, since)
  let (reader, changed_files, warnings) = make_reader(root, since)
  let config = match reader.read(config_file) {
    Some(source) => @engine.parse_config(source, path=config_file)
    None => {
      if config_path is Some(_) {
        fail_input(
          "Explicit config is absent from the selected snapshot",
          path=config_file,
        )
      }
      @model.Config::default()
    }
  }
  let changeset_directory = slash(parent(config_file))
  let workspaces : Array[@model.EcosystemWorkspace] = []
  let units : Array[@model.ReleaseUnit] = []
  let ownership : Array[@model.Ownership] = []
  let unmanaged : Array[String] = []
  let roots : Array[(String, String, Bool)] = []
  match config.raw {
    {
      "experimental": {
        "mixedWorkspaces": { "workspaces": Array(items), .. },
        ..
      },
      ..
    } =>
      for item in items {
        if item
          is {
            "id": String(id),
            "root": String(path),
            "ecosystem": String(ecosystem),
            "includeRoot": include_root,
            ..
          } {
          if ecosystem == "moonbit" {
            roots.push(
              (
                id,
                relative(root, join(root, path)),
                include_root == Json::boolean(true),
              ),
            )
          }
        }
      }
    _ => roots.push(("main", "", reader.read("moon.work") is None))
  }
  let seen : Map[String, Bool] = Map([])
  for (workspace_id, ws_root, include_root) in roots {
    let members : Array[String] = []
    let work_path = slash(join(ws_root, "moon.work"))
    match reader.read(work_path) {
      Some(source) => {
        let document = manifest_document(@manifest.Work, source, work_path)
        for entry in document.member_entries() {
          let path = relative(root, join(root, join(ws_root, entry.value)))
          if path.contains("*") || path.contains("?") {
            fail_input("Workspace member globs are unsupported", path=work_path)
          }
          members.push(path)
        }
        if include_root &&
          !members.contains(ws_root) &&
          reader.read(slash(join(ws_root, "moon.mod"))) is Some(_) {
          members.push(ws_root)
        }
      }
      None => if include_root { members.push(ws_root) }
    }
    workspaces.push({
      id: workspace_id,
      root: ws_root,
      ecosystem: "moonbit",
      manager: "moon",
    })
    for member_path in members {
      if member_path
        .split("/")
        .any(x => {
          ["node_modules", "_build", "target", ".mooncakes", ".git"].contains(
            x.to_owned(),
          )
        }) {
        fail_input(
          "Workspace member points into an excluded directory",
          path=member_path,
        )
      }
      if nested_checkout(reader, member_path) {
        warnings.push(
          @model.diagnostic(
            "nested-checkout-excluded",
            "Nested Git checkout is not owned by this release domain",
            path=member_path,
          ),
        )
        continue
      }
      let manifest = slash(join(member_path, "moon.mod"))
      guard reader.read(manifest) is Some(source) else {
        fail_input("Workspace member has no moon.mod", path=manifest)
        continue
      }
      let canonical = if reader.head is None {
        @fs.realpath(join(root, manifest))
      } else {
        manifest
      }
      if seen.contains(canonical) {
        fail_input("Manifest has multiple workspace owners", path=manifest)
      }
      seen[canonical] = true
      let document = manifest_document(@manifest.Mod, source, manifest)
      guard document.module_name() is Some(name) else {
        fail_input("Module name is required", path=manifest)
        continue
      }
      if name == "" ||
        name.contains(":") ||
        !name.contains("/") ||
        name.contains(" ") {
        fail_input("Invalid MoonBit module name", path=manifest)
      }
      let id = "moonbit:" + name
      if units.any(unit => unit.id == id) {
        fail_input("Duplicate module identity: " + id, path=manifest)
      }
      let dependencies = document
        .dependencies()
        .map(dep => @model.DependencyEdge::{
          producer: "moonbit:" + dep.name,
          requirement: dep.version,
          kind: @model.Runtime,
          path: manifest,
          start: dep.span.start,
          end: dep.span.end,
        })
      let publish = match config.raw {
        {
          "experimental": {
            "mixedWorkspaces": { "units": Object(overrides), .. },
            ..
          },
          ..
        } =>
          match overrides.get(id) {
            Some({ "publish": False, .. }) => false
            _ => true
          }
        _ => true
      }
      units.push({
        id,
        native_name: name,
        ecosystem: "moonbit",
        workspace_id,
        root: member_path,
        manifest,
        version: document.version(),
        visibility: if document.is_private() {
          "restricted"
        } else {
          "public"
        },
        publish,
        dependencies,
      })
      ownership.push({ path: manifest, field: "version", owner: id, })
    }
  }
  for spec in config.mixed_workspaces {
    if spec.ecosystem == "npm" {
      discover_npm_workspace(
        reader,
        root,
        spec,
        units,
        workspaces,
        ownership,
        unmanaged,
        seen,
        config.unit_overrides,
      )
    }
  }
  if units.is_empty() {
    fail_input("No managed MoonBit modules were discovered", path=root)
  }
  match config.raw {
    {
      "experimental": {
        "mixedWorkspaces": { "units": Object(overrides), .. },
        ..
      },
      ..
    } =>
      for id, value in overrides {
        if !units.any(unit => unit.id == id) {
          fail_input(
            "Unit override references an unknown UnitId: " + id,
            path=config_file,
          )
        }
        if value is { "publisher": String(publisher), .. } &&
          publisher != "moon" {
          fail_input(
            "Unsupported MoonBit publisher override",
            path=config_file,
            code="unsupported-capability",
          )
        }
      }
    _ => ()
  }
  let inspection_roots = [""] + units.map(x => x.root)
  for dir in inspection_roots {
    for file in ["package.json", "pnpm-workspace.yaml", "Cargo.toml"] {
      let path = slash(join(dir, file))
      let managed = units.any(unit => unit.manifest == path)
      if !managed && !unmanaged.contains(path) && reader.read(path) is Some(_) {
        unmanaged.push(path)
      }
    }
  }
  units.sort_by((a, b) => a.id.compare(b.id))
  ownership.sort_by((a, b) => a.path.compare(b.path))
  unmanaged.sort()
  // Version planning needs the current changelog and persisted release state
  // in its immutable source snapshot so stale hashes can be checked before
  // any write occurs.
  for unit in units {
    let changelog = if unit.root == "" {
      "CHANGELOG.md"
    } else {
      slash(join(unit.root, "CHANGELOG.md"))
    }
    ignore(reader.read(changelog))
  }
  ignore(reader.read(".moonset/release-state.json"))
  let changesets = []
  for file in reader.files(changeset_directory) {
    let path = slash(join(changeset_directory, file))
    if !file.has_suffix(".md") || file == "README.md" || file.has_prefix(".") {
      continue
    }
    if since is Some(_) && !changed_files.contains(path) {
      continue
    }
    if reader.read(path) is Some(source) {
      changesets.push(
        @engine.parse_changeset(
          source,
          id=file[:file.length() - 3].to_owned(),
          path~,
          mixed=config.mixed,
        ),
      )
    }
  }
  let pre_file = match config.raw {
    { "pre": { "file": String(path), .. }, .. } => path
    _ => slash(join(changeset_directory, "pre.json"))
  }
  let pre = match reader.read(pre_file) {
    Some(source) => Some(@engine.parse_pre_state(source, path=pre_file))
    None => None
  }
  {
    snapshot: {
      root,
      workspaces,
      units,
      ownership,
      unmanaged,
      config,
      sources: reader.sources,
      changed_files,
      warnings,
      git_head: reader.head,
    },
    changesets,
    pre,
    changeset_directory,
  }
}
