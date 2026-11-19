///|
pub(all) struct PackOptions {
  dry_run : Bool
  frozen : Bool
  packages : Array[String]
}

///|
fn find_moonbit_archive(
  entries : Array[String],
  unit_name : String,
  version : String,
) -> String? {
  let clean = unit_name.replace_all(old="/", new="-")
  let expected_prefix = clean + "-" + version
  for entry in entries {
    if (
        entry.has_suffix(".tar.gz") ||
        entry.has_suffix(".zip") ||
        entry.has_suffix(".pkg")
      ) &&
      (entry.contains(expected_prefix) || entry.contains(version)) {
      return Some(entry)
    }
  }
  None
}

///|
fn declared_target_spec(
  specs_by_unit : Map[String, Array[@engine.ArtifactTargetSpec]],
  unit_id : String,
  target : String,
) -> @engine.ArtifactTargetSpec? {
  for spec in specs_by_unit.get(unit_id).unwrap_or([]) {
    if spec.target == target {
      return Some(spec)
    }
  }
  for _, specs in specs_by_unit {
    for spec in specs {
      if spec.target == target && spec.package_unit_id == Some(unit_id) {
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
/// Pack release units for a given target platform and write a target-scoped manifest.
pub async fn[H : ExecutionHost] pack_artifacts_for_target_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
  target~ : String = "source",
  manifest_out? : String,
) -> Array[@model.PackResult] {
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
  let specs_by_unit = @engine.parse_artifact_specs(loaded.snapshot.config)
  let requested : Array[String] = []
  for pkg in options.packages {
    let trimmed = pkg.trim().to_owned()
    if trimmed == "" {
      continue
    }
    let id = @engine.canonical_id(trimmed)
    if !loaded.snapshot.units.any(u => u.id == id || u.native_name == trimmed) {
      raise invalid_error(
        "unknown-unit",
        "Unknown package requested for pack: " + pkg,
      )
    }
    if !requested.contains(id) {
      requested.push(id)
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
        let args = if unit.ecosystem == "moonbit" {
          let base = ["package"]
          if options.dry_run {
            base.push("--dry-run")
          }
          if options.frozen {
            base.push("--frozen")
          }
          base
        } else if unit.ecosystem == "cargo" {
          let base = ["package", "--allow-dirty"]
          if options.dry_run {
            base.push("--list")
          }
          if options.frozen {
            base.push("--frozen")
          }
          base
        } else {
          let base = ["pack"]
          if options.dry_run {
            base.push("--dry-run")
          }
          if options.frozen {
            base.push("--offline")
          }
          base.push("--ignore-scripts")
          base.push("--json")
          base
        }
        let program = if unit.ecosystem == "moonbit" {
          "moon"
        } else if unit.ecosystem == "cargo" {
          "cargo"
        } else {
          package_manager_program(host, manager_for_unit(loaded.snapshot, unit))
        }
        let output = host.run(program, args, Some(cwd))
        if output.exit_code != 0 {
          raise @model.Io(
            program + " pack failed for " + unit.id + ": " + output.stderr,
          )
        }
        if unit.ecosystem == "moonbit" {
          if options.dry_run {
            ("", "", true)
          } else {
            let mut found_archive : String? = None
            for rel_dir in ["_build/package", "target/package"] {
              if found_archive is None {
                let pkg_dir = absolute_path(cwd, rel_dir)
                if host.is_dir(pkg_dir) {
                  let entries = host.readdir(pkg_dir)
                  found_archive = find_moonbit_archive(
                    entries,
                    unit.native_name,
                    version,
                  ).map(name => absolute_path(pkg_dir, name))
                }
              }
            }
            match found_archive {
              Some(path) => {
                let bytes = host.read_binary(path)
                (path, bytes_fingerprint(bytes), true)
              }
              None => ("", "", true)
            }
          }
        } else if unit.ecosystem == "cargo" {
          if options.dry_run {
            ("", "", true)
          } else {
            let workspace_root = workspace_root_for_unit(loaded.snapshot, unit)
            let ws_rel = (if workspace_root == "" {
                ""
              } else {
                workspace_root + "/"
              }) +
              "target/package/" +
              unit.native_name +
              "-" +
              version +
              ".crate"
            let unit_rel = (if unit.root == "" { "" } else { unit.root + "/" }) +
              "target/package/" +
              unit.native_name +
              "-" +
              version +
              ".crate"
            let ws_path = absolute_path(loaded.snapshot.root, ws_rel)
            let unit_path = absolute_path(loaded.snapshot.root, unit_rel)
            let archive_path = if host.exists(ws_path) {
              ws_path
            } else {
              unit_path
            }
            if host.exists(archive_path) {
              (
                archive_path,
                bytes_fingerprint(host.read_binary(archive_path)),
                true,
              )
            } else {
              raise invalid_error(
                "artifact-missing",
                "cargo package did not produce the expected .crate archive",
                path=ws_rel,
              )
            }
          }
        } else {
          let packed = @json.parse(output.stdout) catch { _ => Json::null() }
          let (filename, integrity) = match packed {
            Array(
              [
                {
                  "filename": String(filename),
                  "integrity": String(integrity),
                  ..
                },
                ..,
              ]
            ) => (filename, integrity)
            { "filename": String(filename), "integrity": String(integrity), .. } =>
              (filename, integrity)
            _ => ("", "")
          }
          let archive_path = if filename == "" {
            ""
          } else if options.dry_run {
            filename
          } else {
            let candidate = absolute_path(cwd, filename)
            if host.exists(candidate) {
              candidate
            } else {
              filename
            }
          }
          (archive_path, integrity, filename != "" && integrity != "")
        }
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
    let manifest_rel = match manifest_out {
      Some(path) => path
      None =>
        if target == "source" {
          ".moonset/pack-results.json"
        } else {
          ".moonset/pack-results-" + target + ".json"
        }
    }
    let pack_state_path = absolute_path(loaded.snapshot.root, manifest_rel)
    host.mkdir(parent_dir(pack_state_path))
    host.write_text(
      pack_state_path,
      @model.canonical_json({
        "schemaVersion": 1,
        "target": target,
        "results": results.map(x => x.to_json()),
      }) +
      "\n",
    )
  }
  results
}

///|
pub async fn pack_artifacts_for_target(
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
  target~ : String = "source",
  manifest_out? : String,
) -> Array[@model.PackResult] {
  pack_artifacts_for_target_with(
    native_host(),
    loaded,
    options,
    target~,
    manifest_out?,
  )
}

///|
pub async fn[H : ExecutionHost] pack_artifacts_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
) -> Array[@model.PackResult] {
  pack_artifacts_for_target_with(host, loaded, options)
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
  let state_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/release-state.json",
  )
  if !host.exists(state_path) {
    raise invalid_error(
      "usage",
      "No release state exists; run version first",
      path=state_path,
    )
  }
  let state = @json.parse(host.read_text(state_path)) catch {
    _ =>
      raise invalid_error(
        "usage",
        "Release state is not valid JSON",
        path=state_path,
      )
  }
  let intents : Array[@model.ArtifactIntent] = []
  match state {
    { "artifacts": Array(items), .. } =>
      for item in items {
        if parse_artifact_intent_json(item) is Some(intent) {
          intents.push(intent)
        }
      }
    { "releases": Array(rel_items), .. } => {
      let releases : Array[@model.Release] = []
      for item in rel_items {
        if item
          is {
            "unitId": String(unit_id),
            "oldVersion": String(old_version),
            "newVersion": String(new_version),
            "level": String(level_text),
            "publish": publish_json,
            ..
          } {
          let level = match level_text {
            "major" => @model.Major
            "minor" => @model.Minor
            "patch" => @model.Patch
            _ => @model.None
          }
          releases.push({
            unit_id,
            old_version,
            new_version,
            level,
            reasons: [],
            changesets: [],
            publish: publish_json == Json::boolean(true),
          })
        }
      }
      let plan : @model.ReleasePlan = {
        fingerprint: match state {
          { "planFingerprint": String(fp), .. } => fp
          _ => ""
        },
        releases,
        dependency_updates: [],
        affected_paths: [],
        changesets: [],
        next_pre_state: None,
        warnings: [],
        generated_at: None,
      }
      let dag = @engine.build_execution_dag(loaded.snapshot, plan)
      for intent in dag.artifacts {
        intents.push(intent)
      }
    }
    _ =>
      raise invalid_error(
        "usage",
        "Release state has an invalid shape",
        path=state_path,
      )
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
      if spec.required && spec.package_unit_id is Some(pkg) && pkg != owner_id {
        let owners = owners_by_package.get(pkg).unwrap_or([])
        if !owners.contains(owner_id) {
          owners.push(owner_id)
        }
        owners_by_package[pkg] = owners
      }
    }
  }
  let expected_head = match state {
    { "sourceHead": String(head), .. } => Some(head)
    _ => loaded.snapshot.git_head
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
