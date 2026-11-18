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
pub async fn[H : ExecutionHost] pack_artifacts_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PackOptions,
) -> Array[@model.PackResult] {
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
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
    let (archive, content_hash, verified) = if unit.ecosystem == "moonbit" {
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
            { "filename": String(filename), "integrity": String(integrity), .. },
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
    results.push({
      artifact_id: unit.id + "@" + version,
      unit_id: unit.id,
      version,
      target: "source",
      archive_path: archive,
      source_commit: loaded.snapshot.git_head,
      content_hash,
      verified,
    })
  }
  if !options.dry_run && !results.is_empty() {
    let pack_state_path = absolute_path(
      loaded.snapshot.root,
      ".moonset/pack-results.json",
    )
    host.mkdir(absolute_path(loaded.snapshot.root, ".moonset"))
    host.write_text(
      pack_state_path,
      @model.canonical_json({
        "schemaVersion": 1,
        "results": results.map(x => x.to_json()),
      }) +
      "\n",
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
