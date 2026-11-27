///|
priv enum RegistryLookup {
  Present
  Absent
  LookupUnknown(String)
}

///|
priv struct DriverPublishConfig {
  registry : String?
  dist_tag : String?
  access : @model.Access
  otp : String?
  archive_path : String?
  ignore_scripts : Bool
}

///|
fn registry_for_ecosystem(ecosystem : @model.Ecosystem) -> String {
  match ecosystem {
    @model.Cargo => "crates.io"
    @model.Npm => "npm"
    @model.MoonBit => "mooncakes"
  }
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
fn parse_npm_pack_filename(stdout : String) -> (String, String) {
  let parsed = @json.parse(stdout) catch { _ => Json::null() }
  match parsed {
    Array(
      [{ "filename": String(filename), "integrity": String(integrity), .. }, ..],
    ) => return (filename, integrity)
    Array([{ "filename": String(filename), .. }, ..]) => return (filename, "")
    { "filename": String(filename), "integrity": String(integrity), .. } =>
      return (filename, integrity)
    { "filename": String(filename), .. } => return (filename, "")
    _ => ()
  }
  // Fallback for plain text output (e.g., older npm or pnpm without --json)
  let lines = stdout
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.trim().to_owned())
    .filter(x => x != "")
    .collect()
  let mut idx = lines.length() - 1
  while idx >= 0 {
    if lines[idx].has_suffix(".tgz") {
      return (lines[idx], "")
    }
    idx -= 1
  }
  ("", "")
}

///|
/// Query the authoritative ecosystem registry for whether `unit@version` exists.
async fn[H : ExecutionHost] driver_registry_lookup(
  host : H,
  unit : @model.ReleaseUnit,
  manager : @model.PackageManager,
  version : String,
  cwd : String,
  registry_override : String?,
) -> RegistryLookup {
  let name = unit.native_name
  match unit.ecosystem {
    @model.MoonBit => {
      let output = host.run(
        "moon",
        ["view", name + "@" + version, "--json"],
        Some(cwd),
      )
      let raw = output.stdout.trim().to_owned()
      let lower = (raw + "\n" + output.stderr).to_lower()
      if raw == "" {
        if lower.contains("404") || lower.contains("not found") {
          return Absent
        }
        return LookupUnknown(
          "moon view returned empty output: " + process_failure_detail(output),
        )
      }
      let parsed = @json.parse(raw) catch { _ => Json::null() }
      match parsed {
        { "status": "success", "result": Object(_), .. } => Present
        { "status": "failure", .. } =>
          if lower.contains("404") || lower.contains("not found") {
            Absent
          } else {
            LookupUnknown("moon view failed: " + raw)
          }
        _ =>
          if lower.contains("404") || lower.contains("not found") {
            Absent
          } else {
            LookupUnknown("moon view unexpected response: " + raw)
          }
      }
    }
    @model.Cargo => {
      let args = ["info", name + "@" + version]
      if registry_override is Some(reg) {
        args.push("--registry")
        args.push(reg)
      }
      let output = host.run("cargo", args, Some(cwd))
      if output.exit_code == 0 {
        return Present
      }
      let combined = (output.stdout + "\n" + output.stderr).to_lower()
      if combined.contains("could not find") ||
        combined.contains("does not exist") ||
        combined.contains("not found") ||
        combined.contains("no matching package") ||
        combined.contains("failed to select a version") {
        Absent
      } else {
        LookupUnknown("cargo info failed: " + process_failure_detail(output))
      }
    }
    @model.Npm => {
      let args = ["view", name + "@" + version, "version", "--json"]
      if registry_override is Some(reg) {
        args.push("--registry")
        args.push(reg)
      }
      // Yarn v2+ lacks `yarn view`; query registry reliably via `npm view`.
      let lookup_manager = if manager == @model.PackageManager::Yarn {
        @model.PackageManager::Npm
      } else {
        manager
      }
      let program = package_manager_program(host, lookup_manager)
      let output = host.run(program, args, Some(cwd))
      if output.exit_code == 0 {
        let trimmed = output.stdout.trim().to_owned()
        if trimmed == "" || trimmed == "null" || trimmed == "[]" {
          // npm 9/10 can exit 0 with empty stdout when a version does not exist
          return Absent
        }
        return Present
      }
      let combined = (output.stdout + "\n" + output.stderr).to_lower()
      if combined.contains("e404") ||
        combined.contains("404 not found") ||
        combined.contains("err_pnpm_fetch_404") ||
        combined.contains("err_pnpm_package_not_found") ||
        combined.contains("no match found for version") {
        Absent
      } else {
        LookupUnknown(
          program + " view failed: " + process_failure_detail(output),
        )
      }
    }
  }
}

///|
/// Pack one release unit using its ecosystem toolchain and verify the disk archive.
async fn[H : ExecutionHost] driver_pack(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  unit : @model.ReleaseUnit,
  manager : @model.PackageManager,
  version : String,
  cwd : String,
  dry_run : Bool,
  frozen : Bool,
) -> (String, String, Bool) {
  match unit.ecosystem {
    @model.MoonBit => {
      let args = ["package"]
      if dry_run {
        args.push("--dry-run")
      }
      if frozen {
        args.push("--frozen")
      }
      let output = host.run("moon", args, Some(cwd))
      if output.exit_code != 0 {
        raise @model.Io(
          "moon package failed for " +
          unit.id +
          ": " +
          process_failure_detail(output),
        )
      }
      if dry_run {
        return ("", "", true)
      }
      let mut found_archive : String? = None
      for rel_dir in ["_build/publish", "_build/package", "target/package"] {
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
        Some(path) => (path, bytes_fingerprint(host.read_binary(path)), true)
        None =>
          raise invalid_error(
            "artifact-missing",
            "moon package did not produce an expected archive under _build/publish or _build/package for " +
            unit.id,
            path=unit.manifest,
          )
      }
    }
    @model.Cargo => {
      let args = ["package", "--allow-dirty"]
      if dry_run {
        args.push("--list")
      }
      if frozen {
        args.push("--frozen")
      }
      let output = host.run("cargo", args, Some(cwd))
      if output.exit_code != 0 {
        raise @model.Io(
          "cargo package failed for " +
          unit.id +
          ": " +
          process_failure_detail(output),
        )
      }
      if dry_run {
        return ("", "", true)
      }
      let workspace_root = workspace_root_for_unit(loaded.snapshot, unit)
      let ws_rel = (if workspace_root == "" || workspace_root == "." {
          ""
        } else {
          workspace_root + "/"
        }) +
        "target/package/" +
        unit.native_name +
        "-" +
        version +
        ".crate"
      let unit_rel = (if unit.root == "" || unit.root == "." {
          ""
        } else {
          unit.root + "/"
        }) +
        "target/package/" +
        unit.native_name +
        "-" +
        version +
        ".crate"
      let ws_path = absolute_path(loaded.snapshot.root, ws_rel)
      let unit_path = absolute_path(loaded.snapshot.root, unit_rel)
      let archive_path = if host.exists(ws_path) { ws_path } else { unit_path }
      if host.exists(archive_path) {
        (archive_path, bytes_fingerprint(host.read_binary(archive_path)), true)
      } else {
        raise invalid_error(
          "artifact-missing",
          "cargo package did not produce the expected .crate archive",
          path=ws_rel,
        )
      }
    }
    @model.Npm => {
      let pack_cwd = match unit.publish_config {
        Some({ directory: Some(dir), .. }) if dir.trim() != "" => {
          let candidate = absolute_path(cwd, dir.trim().to_owned())
          if host.is_dir(candidate) {
            candidate
          } else {
            cwd
          }
        }
        _ => cwd
      }
      let program = package_manager_program(host, manager)
      let is_pnpm = manager == @model.PackageManager::Pnpm
      let is_yarn = manager == @model.PackageManager::Yarn
      if is_yarn {
        let clean = unit.native_name
          .replace_all(old="@", new="")
          .replace_all(old="/", new="-")
        let tgz_name = clean + "-" + version + ".tgz"
        if dry_run {
          let tmp = host.tmpdir("moonset-yarn-pack-")
          defer @async.protect_from_cancel(() => {
            host.rmdir(tmp) catch {
              _ => ()
            }
          })
          let out_file = absolute_path(tmp, tgz_name)
          let output = host.run(
            program,
            ["pack", "--filename", out_file],
            Some(pack_cwd),
          )
          if output.exit_code != 0 {
            raise @model.Io(
              program +
              " pack failed for " +
              unit.id +
              ": " +
              process_failure_detail(output),
            )
          }
          return (tgz_name, "", true)
        }
        let archive_path = absolute_path(pack_cwd, tgz_name)
        let output = host.run(
          program,
          ["pack", "--filename", archive_path],
          Some(pack_cwd),
        )
        if output.exit_code != 0 {
          raise @model.Io(
            program +
            " pack failed for " +
            unit.id +
            ": " +
            process_failure_detail(output),
          )
        }
        if !host.exists(archive_path) {
          raise invalid_error(
            "artifact-missing",
            program + " pack tarball not found on disk: " + archive_path,
            path=archive_path,
          )
        }
        let hash = bytes_fingerprint(host.read_binary(archive_path))
        return (archive_path, hash, true)
      }
      if is_pnpm && dry_run {
        // pnpm pack does not support --dry-run; pack to a temp destination and remove it.
        let tmp = host.tmpdir("moonset-pnpm-pack-")
        defer @async.protect_from_cancel(() => host.rmdir(tmp) catch { _ => () })
        let output = host.run(
          program,
          ["pack", "--pack-destination", tmp],
          Some(pack_cwd),
        )
        if output.exit_code != 0 {
          raise @model.Io(
            program +
            " pack failed for " +
            unit.id +
            ": " +
            process_failure_detail(output),
          )
        }
        let (filename, _) = parse_npm_pack_filename(output.stdout)
        return (filename, "", true)
      }
      let args = ["pack"]
      if !is_pnpm {
        if dry_run {
          args.push("--dry-run")
        }
        if frozen {
          args.push("--offline")
        }
        args.push("--json")
      }
      let output = host.run(program, args, Some(pack_cwd))
      if output.exit_code != 0 {
        raise @model.Io(
          program +
          " pack failed for " +
          unit.id +
          ": " +
          process_failure_detail(output),
        )
      }
      let (filename, integrity) = parse_npm_pack_filename(output.stdout)
      if dry_run {
        return (filename, integrity, filename != "")
      }
      if filename == "" {
        raise invalid_error(
          "artifact-missing",
          program + " pack did not report a tarball filename for " + unit.id,
          path=unit.manifest,
        )
      }
      let archive_path = if host.exists(filename) {
        filename
      } else {
        absolute_path(pack_cwd, filename)
      }
      if !host.exists(archive_path) {
        raise invalid_error(
          "artifact-missing",
          program + " pack tarball not found on disk: " + archive_path,
          path=archive_path,
        )
      }
      let hash = bytes_fingerprint(host.read_binary(archive_path))
      (archive_path, hash, true)
    }
  }
}

///|
fn build_npm_publish_args(
  manager : @model.PackageManager,
  cfg : DriverPublishConfig,
  dry_run : Bool,
) -> Array[String] {
  let args : Array[String] = ["publish"]
  if cfg.archive_path is Some(archive) && archive.trim() != "" {
    args.push(archive)
  }
  if dry_run {
    args.push("--dry-run")
  }
  if manager == @model.PackageManager::Pnpm {
    args.push("--no-git-checks")
  }
  args.push("--access")
  args.push(cfg.access.text())
  if cfg.registry is Some(reg) {
    args.push("--registry")
    args.push(reg)
  }
  if cfg.dist_tag is Some(dist_tag) {
    args.push("--tag")
    args.push(dist_tag)
  }
  if cfg.ignore_scripts {
    args.push("--ignore-scripts")
  }
  if cfg.otp is Some(otp) && otp.trim() != "" {
    args.push("--otp")
    args.push(otp.trim().to_owned())
  }
  args
}

///|
async fn[H : ExecutionHost] npm_effective_cwd(
  host : H,
  unit : @model.ReleaseUnit,
  cwd : String,
  archive_path : String?,
) -> String {
  if archive_path is Some(path) && path.trim() != "" {
    return cwd
  }
  match unit.publish_config {
    Some({ directory: Some(dir), .. }) if dir.trim() != "" => {
      let candidate = absolute_path(cwd, dir.trim().to_owned())
      if host.is_dir(candidate) {
        candidate
      } else {
        cwd
      }
    }
    _ => cwd
  }
}

///|
/// Execute ecosystem registry preflight (`--dry-run`) and return `(ok, already_published, detail)`.
async fn[H : ExecutionHost] driver_preflight(
  host : H,
  unit : @model.ReleaseUnit,
  manager : @model.PackageManager,
  cwd : String,
  cfg : DriverPublishConfig,
) -> (Bool, Bool, String) {
  match unit.ecosystem {
    @model.MoonBit => {
      let output = host.run("moon", ["publish", "--dry-run"], Some(cwd))
      if output.exit_code == 0 {
        return (true, false, "")
      }
      let combined = output.stdout + "\n" + output.stderr
      if combined.contains("409 Conflict") ||
        combined.contains("duplicated with an existing version") {
        return (true, true, "already published")
      }
      (
        false,
        false,
        "moon publish --dry-run failed: " + process_failure_detail(output),
      )
    }
    @model.Cargo => {
      let args = ["publish", "--dry-run", "--allow-dirty"]
      if cfg.registry is Some(reg) {
        args.push("--registry")
        args.push(reg)
      }
      let output = host.run("cargo", args, Some(cwd))
      if output.exit_code == 0 {
        (true, false, "")
      } else {
        (
          false,
          false,
          "cargo publish --dry-run failed: " + process_failure_detail(output),
        )
      }
    }
    @model.Npm => {
      // Yarn v1/v2 publish flags diverge widely; npm publish supports tarballs, --access, --tag, --otp, --ignore-scripts uniformly.
      let publish_manager = if manager == @model.PackageManager::Yarn {
        @model.PackageManager::Npm
      } else {
        manager
      }
      let program = package_manager_program(host, publish_manager)
      let args = build_npm_publish_args(publish_manager, cfg, true)
      let effective_cwd = npm_effective_cwd(host, unit, cwd, cfg.archive_path)
      let output = host.run(program, args, Some(effective_cwd))
      if output.exit_code == 0 {
        (true, false, "")
      } else {
        (
          false,
          false,
          program +
          " publish --dry-run failed: " +
          process_failure_detail(output),
        )
      }
    }
  }
}

///|
/// Execute real ecosystem publication and return `(ok, detail)`.
async fn[H : ExecutionHost] driver_publish(
  host : H,
  unit : @model.ReleaseUnit,
  manager : @model.PackageManager,
  cwd : String,
  cfg : DriverPublishConfig,
) -> (Bool, String) {
  match unit.ecosystem {
    @model.MoonBit => {
      let output = host.run("moon", ["publish"], Some(cwd))
      if output.exit_code == 0 {
        (true, "")
      } else {
        (false, "moon publish failed: " + process_failure_detail(output))
      }
    }
    @model.Cargo => {
      let args = ["publish", "--allow-dirty"]
      if cfg.registry is Some(reg) {
        args.push("--registry")
        args.push(reg)
      }
      let output = host.run("cargo", args, Some(cwd))
      if output.exit_code == 0 {
        (true, "")
      } else {
        (false, "cargo publish failed: " + process_failure_detail(output))
      }
    }
    @model.Npm => {
      let publish_manager = if manager == @model.PackageManager::Yarn {
        @model.PackageManager::Npm
      } else {
        manager
      }
      let program = package_manager_program(host, publish_manager)
      let args = build_npm_publish_args(publish_manager, cfg, false)
      let effective_cwd = npm_effective_cwd(host, unit, cwd, cfg.archive_path)
      let output = host.run(program, args, Some(effective_cwd))
      if output.exit_code == 0 {
        (true, "")
      } else {
        (false, program + " publish failed: " + process_failure_detail(output))
      }
    }
  }
}
