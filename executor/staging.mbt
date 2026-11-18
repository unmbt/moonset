///|
/// Copy the relevant source tree to an isolated temporary staging directory.
async fn[H : ExecutionHost] copy_staging_tree(
  host : H,
  source : String,
  destination : String,
) -> Unit {
  host.mkdir(destination)
  for entry in host.readdir(source) {
    if [".git", "node_modules", ".mooncakes", "_build", "target", ".moonset"].contains(
        entry,
      ) {
      continue
    }
    let from = absolute_path(source, entry)
    let to = absolute_path(destination, entry)
    if host.is_dir(from) {
      copy_staging_tree(host, from, to)
    } else if host.exists(from) {
      host.mkdir(parent_dir(to))
      host.write_binary(to, host.read_binary(from))
    }
  }
}

///|
/// Apply planned edits in staging and produce lockfile edits with manager validation.
pub async fn[H : ExecutionHost] stage_lockfiles_with(
  host : H,
  root : String,
  loaded : @workspace.LoadedWorkspace,
  plan : @model.VersionPlan,
) -> @model.VersionPlan {
  let npm_workspaces = loaded.snapshot.config.mixed_workspaces.filter(x => {
    x.ecosystem == "npm"
  })
  let cargo_workspaces = loaded.snapshot.config.mixed_workspaces.filter(x => {
    x.ecosystem == "cargo"
  })
  if npm_workspaces.is_empty() && cargo_workspaces.is_empty() {
    return plan
  }
  let stage = host.tmpdir("moonset-lock-stage-")
  defer @async.protect_from_cancel(() => host.rmdir(stage) catch { _ => () })
  copy_staging_tree(host, root, stage)
  for edit in plan.edits {
    let target = absolute_path(stage, edit.path)
    if (edit.kind == "changeset" || edit.kind == "state") &&
      edit.after_text == "" {
      host.remove(target)
    } else {
      host.mkdir(parent_dir(target))
      host.write_text(target, edit.after_text)
    }
  }
  let lock_edits : Array[@model.FileEdit] = []
  for workspace in npm_workspaces {
    let workspace_root = if workspace.root == "." { "" } else { workspace.root }
    let package_path = if workspace_root == "" {
      "package.json"
    } else {
      workspace_root + "/package.json"
    }
    let package_json = @json.parse(
      host.read_text(absolute_path(stage, package_path)),
    ) catch {
      _ =>
        raise invalid_error(
          "invalid-package",
          "Cannot parse package manager manifest",
          path=package_path,
        )
    }
    let manager_value = match package_json {
      { "packageManager": String(value), .. } => value
      _ =>
        raise invalid_error(
          "package-manager-required",
          "package.json must declare an exact packageManager version",
          path=package_path,
        )
    }
    let expected_prefix = workspace.manager + "@"
    if !manager_value.has_prefix(expected_prefix) {
      raise invalid_error(
        "package-manager-conflict",
        "packageManager does not match the configured workspace manager",
        path=package_path,
      )
    }
    let version_parts = manager_value[expected_prefix.length():]
      .to_owned()
      .split("+")
      .collect()
    let exact_version = version_parts[0].to_owned()
    if exact_version == "" || !exact_version.contains(".") {
      raise invalid_error(
        "package-manager-required",
        "packageManager must contain an exact version",
        path=package_path,
      )
    }
    let manager_program = package_manager_program(host, workspace.manager)
    let version_probe = host.run(
      manager_program,
      ["--version"],
      Some(absolute_path(stage, workspace_root)),
    )
    if version_probe.exit_code != 0 ||
      version_probe.stdout.trim().to_owned() != exact_version {
      raise invalid_error(
        "package-manager-version",
        "Installed " +
        workspace.manager +
        " does not match packageManager " +
        exact_version,
        path=package_path,
      )
    }
    let args = if workspace.manager == "pnpm" {
      ["install", "--lockfile-only", "--ignore-scripts", "--offline"]
    } else {
      ["install", "--package-lock-only", "--ignore-scripts", "--offline"]
    }
    let install = host.run(
      manager_program,
      args,
      Some(absolute_path(stage, workspace_root)),
    )
    if install.exit_code != 0 {
      raise invalid_error(
        "lockfile-stage-failed",
        "Package manager could not resolve lockfile offline: " + install.stderr,
        path=package_path,
      )
    }
    let lock_path = if workspace.manager == "pnpm" {
      if workspace_root == "" {
        "pnpm-lock.yaml"
      } else {
        workspace_root + "/pnpm-lock.yaml"
      }
    } else if workspace_root == "" {
      "package-lock.json"
    } else {
      workspace_root + "/package-lock.json"
    }
    let generated_path = absolute_path(stage, lock_path)
    if !host.exists(generated_path) {
      raise invalid_error(
        "lockfile-missing",
        "Package manager did not produce its declared lockfile",
        path=lock_path,
      )
    }
    let after = host.read_text(generated_path)
    let source_path = absolute_path(root, lock_path)
    let before = if host.exists(source_path) {
      host.read_text(source_path)
    } else {
      ""
    }
    if loaded.snapshot.config.lockfiles == "verify-only" && before != after {
      raise invalid_error(
        "lockfile-out-of-date",
        "Generated lockfile differs in verify-only mode",
        path=lock_path,
      )
    }
    if before != after {
      lock_edits.push({
        path: lock_path,
        kind: "lockfile",
        owner: workspace.id,
        before_hash: @model.fingerprint(Json::string(before)),
        after_text: after,
        atomic_write: true,
      })
    }
  }
  for workspace in cargo_workspaces {
    let workspace_root = if workspace.root == "." { "" } else { workspace.root }
    let cwd = absolute_path(stage, workspace_root)
    let generated = host.run(
      "cargo",
      ["generate-lockfile", "--offline"],
      Some(cwd),
    )
    if generated.exit_code != 0 {
      raise invalid_error(
        "lockfile-stage-failed",
        "Cargo could not stage Cargo.lock: " + generated.stderr,
      )
    }
    let lock_path = if workspace_root == "" {
      "Cargo.lock"
    } else {
      workspace_root + "/Cargo.lock"
    }
    let generated_path = absolute_path(stage, lock_path)
    if !host.exists(generated_path) {
      raise invalid_error(
        "lockfile-missing",
        "Cargo did not produce Cargo.lock",
        path=lock_path,
      )
    }
    let after = host.read_text(generated_path)
    let source_path = absolute_path(root, lock_path)
    let before = if host.exists(source_path) {
      host.read_text(source_path)
    } else {
      ""
    }
    if loaded.snapshot.config.lockfiles == "verify-only" && before != after {
      raise invalid_error(
        "lockfile-out-of-date",
        "Cargo.lock differs in verify-only mode",
        path=lock_path,
      )
    }
    if before != after {
      lock_edits.push({
        path: lock_path,
        kind: "lockfile",
        owner: workspace.id,
        before_hash: @model.fingerprint(Json::string(before)),
        after_text: after,
        atomic_write: true,
      })
    }
  }
  if loaded.snapshot.config.lockfiles == "verify-only" {
    return plan
  }
  let edits = plan.edits + lock_edits
  {
    ..plan,
    edits,
    fingerprint: @model.fingerprint({
      "base": plan.fingerprint,
      "lockfiles": lock_edits.map(x => x.to_json()),
    }),
  }
}

///|
pub async fn stage_lockfiles(
  root : String,
  loaded : @workspace.LoadedWorkspace,
  plan : @model.VersionPlan,
) -> @model.VersionPlan {
  stage_lockfiles_with(native_host(), root, loaded, plan)
}
