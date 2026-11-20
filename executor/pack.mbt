///|
pub(all) struct PackOptions {
  dry_run : Bool
  frozen : Bool
  packages : Array[String]
  target : String
  manifest_out : String?
}

///|
pub fn PackOptions::new(
  dry_run~ : Bool = false,
  frozen~ : Bool = false,
  packages~ : Array[String] = [],
  target~ : String = "source",
  manifest_out? : String,
) -> PackOptions {
  { dry_run, frozen, packages, target, manifest_out, }
}

///|
fn sanitize_target_filename(target : String) -> String {
  let out = StringBuilder()
  for ch in target.to_array() {
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.' {
      out.write_char(ch)
    } else {
      out.write_char('_')
    }
  }
  let rendered = out.to_string()
  if rendered == "" || rendered == "." || rendered == ".." {
    "target"
  } else {
    rendered
  }
}

///|
fn declared_target_spec(
  specs_by_unit : Map[String, Array[@model.ArtifactTargetSpec]],
  unit_id : String,
  target : String,
) -> @model.ArtifactTargetSpec? {
  for spec in specs_by_unit.get(unit_id).unwrap_or([]) {
    if spec.target == target {
      return Some(spec)
    }
  }
  for _, specs in specs_by_unit {
    for spec in specs {
      if spec.target == target && spec.linked_package == Some(unit_id) {
        return Some(spec)
      }
    }
  }
  None
}

///|
fn parse_pack_result_json(item : Json) -> @model.PackResult? {
  guard item
    is {
      "artifactId": String(artifact_id),
      "unitId": String(unit_id),
      "version": String(version),
      "target": String(target),
      "archivePath": String(archive_path),
      "contentHash": String(content_hash),
      "verified": verified_json,
      ..
    } else {
    return None
  }
  let source_commit = match item {
    { "sourceCommit": String(commit), .. } => Some(commit)
    _ => None
  }
  Some({
    artifact_id,
    unit_id,
    version,
    target,
    archive_path,
    source_commit,
    content_hash,
    verified: verified_json == Json::boolean(true),
  })
}

///|
fn parse_artifact_intent_json(item : Json) -> @model.ArtifactIntent? {
  guard item
    is {
      "id": String(id),
      "unitId": String(unit_id),
      "version": String(version),
      "target": String(target),
      "required": required_json,
      ..
    } else {
    return None
  }
  let source_commit = match item {
    { "sourceCommit": String(commit), .. } => Some(commit)
    _ => None
  }
  let expected_hash = match item {
    { "expectedHash": String(hash), .. } => Some(hash)
    _ => None
  }
  let path = match item {
    { "path": String(p), .. } => Some(p)
    _ => None
  }
  Some({
    id,
    unit_id,
    version,
    target,
    required: required_json == Json::boolean(true),
    source_commit,
    expected_hash,
    path,
  })
}

///|
/// Pack release units for `options.target` and atomically write a target-scoped manifest.
pub async fn[H : ExecutionHost] pack_artifacts_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
) -> Array[@model.PackResult] {
  let target = if options.target.trim() == "" {
    "source"
  } else {
    options.target.trim().to_owned()
  }
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
  let specs_by_unit = @engine.parse_artifact_specs(loaded.snapshot.config)
  let requested : Array[String] = []
  for pkg in options.packages {
    let trimmed = pkg.trim().to_owned()
    if trimmed == "" {
      continue
    }
    let canonical = @engine.canonical_id(trimmed)
    let matched = loaded.snapshot.units
      .iter()
      .find_first(u => {
        u.id == trimmed || u.id == canonical || u.native_name == trimmed
      })
    guard matched is Some(found) else {
      raise invalid_error(
        "unknown-unit",
        "Unknown package requested for pack: " + pkg,
      )
    }
    if !requested.contains(found.id) {
      requested.push(found.id)
    }
  }
  let results : Array[@model.PackResult] = []
  for unit in loaded.snapshot.units {
    if !requested.is_empty() && !requested.contains(unit.id) {
      continue
    }
    adapter_registry.require(unit.ecosystem, @adapters.Artifact)
    guard unit.version is Some(version) else {
      if !requested.is_empty() {
        raise invalid_error(
          "missing-version",
          "Cannot pack versionless unit: " + unit.id,
          path=unit.manifest,
        )
      }
      continue
    }
    if !unit.publish {
      if !requested.is_empty() {
        raise invalid_error(
          "private-policy",
          "Unit is marked publish=false: " + unit.id,
          path=unit.manifest,
        )
      }
      continue
    }
    let cwd = absolute_path(loaded.snapshot.root, unit.root)
    let custom_spec = if target != "source" {
      declared_target_spec(specs_by_unit, unit.id, target)
    } else {
      None
    }
    let (archive, content_hash, verified) = match custom_spec {
      Some({ path: Some(declared_path), .. }) =>
        if options.dry_run {
          (declared_path, "", true)
        } else {
          let root_candidate = absolute_path(
            loaded.snapshot.root,
            declared_path,
          )
          let cwd_candidate = absolute_path(cwd, declared_path)
          let resolved = if host.exists(root_candidate) {
            root_candidate
          } else {
            cwd_candidate
          }
          if host.exists(resolved) {
            (resolved, bytes_fingerprint(host.read_binary(resolved)), true)
          } else {
            raise invalid_error(
              "artifact-missing",
              "Declared artifact path does not exist for target " +
              target +
              ": " +
              declared_path,
              path=declared_path,
            )
          }
        }
      _ => {
        let manager = manager_for_unit(loaded.snapshot, unit)
        driver_pack(
          host,
          loaded,
          unit,
          manager,
          version,
          cwd,
          options.dry_run,
          options.frozen,
        )
      }
    }
    let artifact_id = if target == "source" {
      unit.id + "@" + version
    } else {
      unit.id + "@" + version + "/" + target
    }
    results.push({
      artifact_id,
      unit_id: unit.id,
      version,
      target,
      archive_path: archive,
      source_commit: loaded.snapshot.git_head,
      content_hash,
      verified,
    })
  }
  if !options.dry_run && !results.is_empty() {
    let manifest_rel = match options.manifest_out {
      Some(path) => path
      None =>
        if target == "source" {
          ".moonset/pack-results.json"
        } else {
          ".moonset/pack-results-" + sanitize_target_filename(target) + ".json"
        }
    }
    let pack_state_path = absolute_path(loaded.snapshot.root, manifest_rel)
    atomic_write_text(
      host,
      pack_state_path,
      @model.canonical_json({
        "schemaVersion": 1,
        "target": target,
        "results": results.map(x => x.to_json()),
      }) +
      "\n",
      "pack",
    )
  }
  results
}

///|
pub async fn pack_artifacts(
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
) -> Array[@model.PackResult] {
  pack_artifacts_with(native_host(), loaded, options)
}

///|
/// Collect packed manifests from `artifacts_dir` (default `.moonset`) and verify
/// all declared `ArtifactIntent` entries against disk files and hashes.
pub async fn[H : ExecutionHost] verify_artifacts_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  artifacts_dir? : String,
) -> @engine.ArtifactVerificationReport {
  let (release_state, raw_state) = load_release_state(
    host,
    loaded.snapshot.root,
  )
  let intents : Array[@model.ArtifactIntent] = []
  match raw_state {
    { "artifacts": Array(items), .. } =>
      for item in items {
        if parse_artifact_intent_json(item) is Some(intent) {
          intents.push(intent)
        }
      }
    _ => {
      let plan : @model.ReleasePlan = {
        fingerprint: release_state.plan_fingerprint,
        releases: release_state.releases,
        dependency_updates: [],
        affected_paths: [],
        changesets: [],
        next_pre_state: None,
        is_snapshot: release_state.is_snapshot,
        warnings: [],
        generated_at: None,
      }
      let dag = @engine.build_execution_dag(loaded.snapshot, plan)
      for intent in dag.artifacts {
        intents.push(intent)
      }
    }
  }
  let scan_dir = absolute_path(
    loaded.snapshot.root,
    artifacts_dir.unwrap_or(".moonset"),
  )
  let packed : Array[@model.PackResult] = []
  if host.is_dir(scan_dir) {
    let entries = host.readdir(scan_dir)
    for entry in entries {
      if entry == "pack-results.json" ||
        (entry.has_prefix("pack-results-") && entry.has_suffix(".json")) {
        let manifest_path = absolute_path(scan_dir, entry)
        let parsed = @json.parse(host.read_text(manifest_path)) catch {
          _ => Json::null()
        }
        if parsed is { "results": Array(rows), .. } {
          for row in rows {
            if parse_pack_result_json(row) is Some(item) {
              let disk_ok = if item.archive_path == "" {
                item.verified
              } else {
                let abs_archive = if host.exists(item.archive_path) {
                  item.archive_path
                } else {
                  absolute_path(loaded.snapshot.root, item.archive_path)
                }
                if !host.exists(abs_archive) {
                  false
                } else if item.content_hash.has_prefix("fnv1a64:") {
                  bytes_fingerprint(host.read_binary(abs_archive)) ==
                  item.content_hash
                } else {
                  item.verified
                }
              }
              packed.push({ ..item, verified: disk_ok, })
            }
          }
        }
      }
    }
  }
  let specs_by_unit = @engine.parse_artifact_specs(loaded.snapshot.config)
  let owners_by_package : Map[String, Array[String]] = Map([])
  for owner_id, specs in specs_by_unit {
    for spec in specs {
      if spec.required && spec.linked_package is Some(pkg) && pkg != owner_id {
        let owners = owners_by_package.get(pkg).unwrap_or([])
        if !owners.contains(owner_id) {
          owners.push(owner_id)
        }
        owners_by_package[pkg] = owners
      }
    }
  }
  let expected_head = match release_state.source_head {
    Some(head) => Some(head)
    None => loaded.snapshot.git_head
  }
  @engine.verify_artifact_matrix(
    intents,
    packed,
    expected_head?,
    owners_by_package~,
  )
}

///|
pub async fn verify_artifacts(
  loaded : @workspace.LoadedWorkspace,
  artifacts_dir? : String,
) -> @engine.ArtifactVerificationReport {
  verify_artifacts_with(native_host(), loaded, artifacts_dir?)
}
