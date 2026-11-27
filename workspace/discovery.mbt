///|
pub(all) struct LoadedWorkspace {
  snapshot : @model.WorkspaceSnapshot
  changesets : Array[@model.Changeset]
  pre : @model.PreState?
  changeset_directory : String
  changeset_commits : Map[String, String]
}

///|
async fn locate(
  cwd : String,
  config_path : String?,
  since : String?,
) -> (String, String) {
  let start = @fs.realpath(cwd)
  let head_files : Map[String, Bool]? = if since is Some(_) {
    let repo_raw = git(start, ["rev-parse", "--show-toplevel"])
      .trim()
      .to_owned()
    let repo = @fs.realpath(repo_raw) catch { _ => repo_raw }
    let map : Map[String, Bool] = Map([])
    for
      x in git(repo, ["ls-tree", "-r", "--name-only", "-z", "HEAD"]).split(
        "\u0000",
      ) {
      if x != "" {
        map[norm_cmp_path(join(repo, x.to_owned()))] = true
      }
    }
    Some(map)
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
    let config_dir = parent(absolute)
    let dir_name = @path.Path(config_dir).basename().to_owned()
    // Standard `.changeset/config.json` or `.moonset/config.json` lives one level under the domain root;
    // a standalone `--config ./moonset.json` lives directly in the domain root.
    let config_root_dir = if dir_name == ".changeset" || dir_name == ".moonset" {
      parent(config_dir)
    } else {
      config_dir
    }
    let root = if @fs.exists(config_root_dir) {
      @fs.realpath(config_root_dir)
    } else {
      @path.Path(config_root_dir).normalize().to_string()
    }
    return (root, relative(root, absolute))
  }
  let mut cursor = start
  let mut single : String? = None
  let mut legacy_json_root : String? = None
  for ;; {
    let has_config = match head_files {
      Some(paths) =>
        paths.contains(norm_cmp_path(join(cursor, ".changeset/config.json")))
      None => @fs.exists(join(cursor, ".changeset/config.json"))
    }
    let has_work = match head_files {
      Some(paths) => paths.contains(norm_cmp_path(join(cursor, "moon.work")))
      None => @fs.exists(join(cursor, "moon.work"))
    }
    let has_mod = match head_files {
      Some(paths) => paths.contains(norm_cmp_path(join(cursor, "moon.mod")))
      None => @fs.exists(join(cursor, "moon.mod"))
    }
    let has_legacy_mod_json = match head_files {
      Some(paths) =>
        paths.contains(norm_cmp_path(join(cursor, "moon.mod.json")))
      None => @fs.exists(join(cursor, "moon.mod.json"))
    }
    if has_config || has_work {
      return (cursor, ".changeset/config.json")
    }
    if single is None && has_mod {
      single = Some(cursor)
    }
    if legacy_json_root is None && has_legacy_mod_json {
      legacy_json_root = Some(cursor)
    }
    if @fs.exists(join(cursor, ".git")) || parent(cursor) == cursor {
      break
    }
    cursor = parent(cursor)
  }
  match single {
    Some(root) => (root, ".changeset/config.json")
    None => {
      if legacy_json_root is Some(legacy_dir) {
        fail_input(
          "Legacy moon.mod.json is unsupported; migrate to modern moon.mod (MoonBit toolchain)",
          path=join(legacy_dir, "moon.mod.json"),
          code="unsupported-capability",
        )
      }
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
    if reader.use_git_tree {
      if reader.git_root is Some(root) {
        let key = relative(root, join(reader.root, cursor))
        if reader.tree.get(key) == Some("160000") {
          return true
        }
      }
    } else if @fs.exists(join(reader.root, join(cursor, ".git"))) {
      return true
    }
    cursor = slash(parent(cursor))
  }
  false
}

///|
fn is_ignored_changeset_filename(file : String) -> Bool {
  let lower = file.to_lower()
  !lower.has_suffix(".md") ||
  file.has_prefix(".") ||
  lower == "readme.md" ||
  lower == "agents.md" ||
  lower == "claude.md" ||
  lower == "gemini.md"
}

///|
pub async fn discover(
  cwd : String,
  config_path? : String,
  since? : String,
  include_commits~ : Bool = true,
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
  let managed_root_manifests : Array[String] = []
  let roots : Array[(String, String, Bool)] = []
  match config.mixed {
    Some(mixed_cfg) =>
      for spec in mixed_cfg.workspaces {
        if spec.ecosystem == @model.MoonBit {
          roots.push(
            (spec.id, relative(root, join(root, spec.root)), spec.include_root),
          )
        }
      }
    None => roots.push(("main", "", reader.read("moon.work") is None))
  }
  let overrides = config.unit_overrides()
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
      None =>
        if include_root {
          members.push(ws_root)
        } else if reader.read(slash(join(ws_root, "moon.mod"))) is Some(_) {
          fail_input(
            "MoonBit workspace has no moon.work; set includeRoot: true for single-module root",
            path=work_path,
          )
        }
    }
    workspaces.push({
      id: workspace_id,
      root: ws_root,
      ecosystem: @model.MoonBit,
      manager: @model.Moon,
    })
    let member_manifests = members.map(m => slash(join(m, "moon.mod")))
    reader.prefetch(member_manifests)
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
      let canonical = if !reader.use_git_tree {
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
          target_condition: None,
        })
      let is_private = document.is_private()
      let publish = match overrides.get(id) {
        Some({ publish: Some(flag), .. }) => flag
        _ => !is_private
      }
      let version_span : @model.TextSpan? = match
        document.string_field("version") {
        Some(field) => Some({ start: field.span.start, end: field.span.end, })
        None => None
      }
      units.push({
        id,
        native_name: name,
        ecosystem: @model.MoonBit,
        workspace_id,
        root: member_path,
        manifest,
        version_path: manifest,
        version_field: "version",
        version: document.version(),
        version_span,
        visibility: if is_private {
          @model.Private
        } else {
          @model.Public
        },
        publish,
        publish_config: None,
        dependencies,
      })
      ownership.push({ path: manifest, field: "version", owner: id, })
    }
  }
  for spec in config.mixed_workspaces() {
    if spec.ecosystem == @model.Npm {
      discover_npm_workspace(
        reader, root, spec, units, workspaces, ownership, seen, overrides, managed_root_manifests,
      )
    } else if spec.ecosystem == @model.Cargo {
      discover_cargo_workspace(
        reader, root, spec, units, workspaces, ownership, seen, overrides, managed_root_manifests,
      )
    }
  }
  if units.is_empty() {
    fail_input("No managed release units were discovered", path=root)
  }
  for id, unit_override in overrides {
    let mut found : @model.ReleaseUnit? = None
    for unit in units {
      if unit.id == id {
        found = Some(unit)
      }
    }
    guard found is Some(unit) else {
      fail_input(
        "Unit override references an unknown UnitId: " + id,
        path=config_file,
      )
      continue
    }
    if unit_override.publisher is Some(publisher) {
      let allowed = if config.publisher.kind == "api" ||
        config.publisher.kind == "command" {
        publisher.trim() != ""
      } else {
        match unit.ecosystem {
          @model.MoonBit => publisher == "moon"
          @model.Npm =>
            publisher == "npm" || publisher == "pnpm" || publisher == "yarn"
          @model.Cargo => publisher == "cargo"
        }
      }
      if !allowed {
        fail_input(
          "Unsupported publisher override for " +
          unit.ecosystem.text() +
          ": " +
          publisher,
          path=config_file,
          code="unsupported-capability",
        )
      }
    }
  }
  let inspection_roots = [""] + units.map(x => x.root)
  let inspection_paths : Array[String] = []
  for dir in inspection_roots {
    for file in ["package.json", "pnpm-workspace.yaml", "Cargo.toml"] {
      inspection_paths.push(slash(join(dir, file)))
    }
    inspection_paths.push(slash(join(dir, ".changeset/config.json")))
  }
  reader.prefetch(inspection_paths)
  for dir in inspection_roots {
    for file in ["package.json", "pnpm-workspace.yaml", "Cargo.toml"] {
      let path = slash(join(dir, file))
      let managed = units.any(unit => unit.manifest == path) ||
        managed_root_manifests.contains(path)
      if !managed && !unmanaged.contains(path) && reader.read(path) is Some(_) {
        unmanaged.push(path)
      }
    }
    let foreign_cs_cfg = slash(join(dir, ".changeset/config.json"))
    let marker = "changeset-config:" + foreign_cs_cfg
    if foreign_cs_cfg != config_file &&
      !unmanaged.contains(marker) &&
      reader.read(foreign_cs_cfg) is Some(_) {
      unmanaged.push(marker)
    }
  }
  units.sort_by((a, b) => a.id.compare(b.id))
  ownership.sort_by((a, b) => a.path.compare(b.path))
  unmanaged.sort()
  let preload_paths : Array[String] = [".moonset/release-state.json"]
  for unit in units {
    let changelog = if unit.root == "" {
      config.changelog.file
    } else {
      slash(join(unit.root, config.changelog.file))
    }
    preload_paths.push(changelog)
  }
  reader.prefetch(preload_paths)
  for unit in units {
    let changelog = if unit.root == "" {
      config.changelog.file
    } else {
      slash(join(unit.root, config.changelog.file))
    }
    ignore(reader.read(changelog))
  }
  ignore(reader.read(".moonset/release-state.json"))
  let pre_file = if config.pre.file == ".changeset/pre.json" &&
    changeset_directory != ".changeset" &&
    changeset_directory != "" {
    slash(join(changeset_directory, "pre.json"))
  } else {
    config.pre.file
  }
  let pre = match reader.read(pre_file) {
    Some(source) => Some(@engine.parse_pre_state(source, path=pre_file))
    None => None
  }
  let raw_pre_dir_cfg = if config.pre.directory == ".changeset/pre" &&
    changeset_directory != ".changeset" &&
    changeset_directory != "" {
    slash(join(changeset_directory, "pre"))
  } else {
    config.pre.directory
  }
  let raw_pre_dir = slash(raw_pre_dir_cfg).trim().to_owned()
  let pre_dir = if raw_pre_dir.has_suffix("/") {
    raw_pre_dir[:raw_pre_dir.length() - 1].to_owned()
  } else {
    raw_pre_dir
  }
  let effective_config : @model.Config = {
    ..config,
    pre: { file: pre_file, directory: pre_dir, },
  }
  let changeset_dirs : Array[(String, Bool)] = [(changeset_directory, false)]
  if pre is Some(_) &&
    pre_dir != "" &&
    pre_dir != "." &&
    pre_dir != changeset_directory {
    changeset_dirs.push((pre_dir, true))
  }
  let changesets = []
  let changeset_commits : Map[String, String] = Map([])
  let pending_commit_paths : Array[(String, String)] = []
  let cs_entries : Array[(String, String, Bool)] = []
  let cs_paths : Array[String] = []
  for pair in changeset_dirs {
    let (dir, in_pre) = pair
    let cs_files = reader.files(dir)
    for file in cs_files {
      if is_ignored_changeset_filename(file) {
        continue
      }
      let path = slash(join(dir, file))
      if since is Some(_) && !changed_files.contains(path) {
        continue
      }
      cs_entries.push((file, path, in_pre))
      cs_paths.push(path)
    }
  }
  reader.prefetch(cs_paths)
  for entry in cs_entries {
    let (file, path, in_pre_dir) = entry
    if reader.read(path) is Some(source) {
      let cs = @engine.parse_changeset(
        source,
        id=file[:file.length() - 3].to_owned(),
        path~,
        mixed=config.is_mixed(),
        in_pre_dir~,
      )
      changesets.push(cs)
      if include_commits {
        pending_commit_paths.push((cs.id, path))
      }
    }
  }
  if include_commits && !pending_commit_paths.is_empty() {
    if reader.git_root is Some(repo) {
      let is_shallow = (git(repo, ["rev-parse", "--is-shallow-repository"]) catch {
          _ => "false"
        })
        .trim()
        .to_owned() ==
        "true"
      if is_shallow {
        warnings.push(
          @model.diagnostic(
            "shallow-repository",
            "Git clone is shallow; changeset commit attribution may be incomplete (use fetch-depth: 0 in CI)",
            path=root,
          ),
        )
      }
      let cs_dir_rels : Array[String] = []
      for pair in changeset_dirs {
        let dir = pair.0
        let rel = relative(repo, join(root, dir)) catch { _ => dir }
        if !cs_dir_rels.contains(rel) {
          cs_dir_rels.push(rel)
        }
      }
      let added_by_path : Map[String, String] = Map([])
      let log_added = git(
        repo,
        [
          "log", "--diff-filter=A", "--name-only", "--format=__MOONSET_COMMIT__%H",
          "--",
        ] +
        cs_dir_rels,
      ) catch {
        _ => ""
      }
      let mut current_sha = ""
      for raw in log_added.replace_all(old="\r\n", new="\n").split("\n") {
        let line = raw.trim().to_owned()
        if line == "" {
          continue
        }
        if line.has_prefix("__MOONSET_COMMIT__") {
          current_sha = line[18:].to_owned()
        } else if current_sha != "" && !added_by_path.contains(line) {
          added_by_path[line] = current_sha
        }
      }
      for item in pending_commit_paths {
        let (cs_id, path) = item
        let repo_rel = relative(repo, join(root, path)) catch { _ => path }
        match added_by_path.get(repo_rel) {
          Some(sha) => changeset_commits[cs_id] = sha
          None => {
            // Follow renames (e.g. `.changeset/foo.md` moved to `.changeset/pre/foo.md`)
            let followed = git(repo, [
              "log", "--follow", "--diff-filter=A", "-n", "1", "--format=%H", "--",
              repo_rel,
            ]) catch {
              _ => ""
            }
            let sha = followed.trim().to_owned()
            if sha != "" {
              changeset_commits[cs_id] = sha
            }
          }
        }
      }
    }
  }
  {
    snapshot: {
      root,
      workspaces,
      units,
      ownership,
      unmanaged,
      config: effective_config,
      sources: reader.sources,
      changed_files,
      warnings,
      git_head: reader.head,
    },
    changesets,
    pre,
    changeset_directory,
    changeset_commits,
  }
}
