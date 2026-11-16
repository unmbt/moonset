///|
async fn stderr(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(message + "\n"))
}

///|
async fn safe_exists(path : String) -> Bool raise @model.MoonsetError {
  @fs.exists(path) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
async fn safe_read(path : String) -> String raise @model.MoonsetError {
  @fs.read_text(path) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
async fn safe_write(
  path : String,
  text : String,
) -> Unit raise @model.MoonsetError {
  @fs.write_text(path, text) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
async fn safe_mkdir(path : String) -> Unit raise @model.MoonsetError {
  @fs.mkdir(path, recursive=true, allow_exist=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
async fn safe_remove(path : String) -> Unit raise @model.MoonsetError {
  @fs.remove(path, allow_missing=true) catch {
    error => raise @model.Io(error.to_string())
  }
}

///|
/// Convert the host UTC millisecond clock to the stable YYYY-MM-DD form used
/// by the builtin changelog generator.
fn utc_date(milliseconds : UInt64) -> String {
  let days = milliseconds.reinterpret_as_int64() / 86400000L
  let z = days + 719468L
  let era = if z >= 0L { z / 146097L } else { (z - 146096L) / 146097L }
  let doe = z - era * 146097L
  let yoe = (doe - doe / 1460L + doe / 36524L - doe / 146096L) / 365L
  let year0 = yoe + era * 400L
  let doy = doe - (365L * yoe + yoe / 4L - yoe / 100L)
  let month0 = (5L * doy + 2L) / 153L
  let day = doy - (153L * month0 + 2L) / 5L + 1L
  let month = month0 + (if month0 < 10L { 3L } else { -9L })
  let year = year0 + (if month <= 2L { 1L } else { 0L })
  let pad = fn(value : Int64) -> String {
    if value < 10L {
      "0" + value.to_string()
    } else {
      value.to_string()
    }
  }
  year.to_string() + "-" + pad(month) + "-" + pad(day)
}

///|
fn absolute(root : String, relative_path : String) -> String {
  @path.Path(root).join(@path.Path(relative_path)).to_string()
}

///|
/// Windows exposes npm/pnpm through command shims; invoke them directly.
fn package_manager_program(name : String) -> String {
  if @env.get_env_var("ComSpec") is Some(_) && (name == "npm" || name == "pnpm") {
    name + ".cmd"
  } else {
    name
  }
}

///|
async fn recover_version(root : String) -> Int32 raise @model.MoonsetError {
  let journal_path = absolute(root, ".moonset/version-journal.json")
  if !safe_exists(journal_path) {
    usage_error("No version journal exists")
  }
  let json = @json.parse(safe_read(journal_path)) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic("usage", "Version journal is not valid JSON"),
      )
  }
  guard json is { "entries": Array(entries), .. } else {
    raise @model.Invalid(
      @model.diagnostic("usage", "Version journal has an invalid shape"),
    )
  }
  for item in entries {
    match item {
      { "path": String(path), "existed": True, "content": String(content), .. } => {
        let target = absolute(root, path)
        safe_mkdir(@path.Path(target).dirname().to_string())
        safe_write(target, content)
      }
      { "path": String(path), "existed": False, "content": String(_), .. } =>
        safe_remove(absolute(root, path))
      _ => usage_error("Version journal contains an invalid entry")
    }
  }
  safe_remove(journal_path)
  println("Recovered version files from " + journal_path)
  0
}

///|
async fn apply_version_plan(
  root : String,
  plan : @model.VersionPlan,
) -> Unit raise @model.MoonsetError {
  let originals : Array[Json] = []
  for edit in plan.edits {
    let target = absolute(root, edit.path)
    let existed = safe_exists(target)
    let current = if existed { safe_read(target) } else { "" }
    if @model.fingerprint(Json::string(current)) != edit.before_hash {
      usage_error("Stale version plan input: " + edit.path)
    }
    originals.push({ "path": edit.path, "existed": existed, "content": current })
  }
  let journal_dir = absolute(root, ".moonset")
  let journal_path = absolute(root, ".moonset/version-journal.json")
  safe_mkdir(journal_dir)
  safe_write(
    journal_path,
    @model.canonical_json({
      "planFingerprint": plan.fingerprint,
      "entries": originals,
    }) +
    "\n",
  )
  try {
    let mut index = 0
    for edit in plan.edits {
      let target = absolute(root, edit.path)
      if edit.kind == "changeset" && edit.after_text == "" {
        safe_remove(target)
      } else {
        let temporary = target + ".moonset-" + index.to_string() + ".tmp"
        safe_mkdir(@path.Path(target).dirname().to_string())
        safe_write(temporary, edit.after_text)
        @fs.rename(temporary, target, replace=true)
      }
      index += 1
    }
    safe_remove(journal_path)
  } catch {
    error => {
      for original in originals {
        match original {
          {
            "path": String(path),
            "existed": True,
            "content": String(content),
            ..
          } => safe_write(absolute(root, path), content)
          { "path": String(path), "existed": False, .. } =>
            safe_remove(absolute(root, path))
          _ => ()
        }
      }
      safe_remove(journal_path)
      raise @model.Io(error.to_string())
    }
  }
}

///|
/// Copy the relevant source tree to an isolated temporary staging directory.
async fn copy_staging_tree(source : String, destination : String) -> Unit {
  safe_mkdir(destination)
  for entry in @fs.readdir(source, include_hidden=true) {
    if [".git", "node_modules", ".mooncakes", "_build", "target", ".moonset"].contains(
        entry,
      ) {
      continue
    }
    let from = absolute(source, entry)
    let to = absolute(destination, entry)
    let kind = @fs.kind(from)
    if kind == @fs.Directory {
      copy_staging_tree(from, to)
    } else if kind == @fs.Regular {
      safe_mkdir(@path.Path(to).dirname().to_string())
      @fs.write_binary(to, @fs.read_binary(from))
    }
  }
}

///|
/// Apply planned edits in staging and produce lockfile edits with manager validation.
async fn stage_lockfiles(
  root : String,
  loaded : @workspace.LoadedWorkspace,
  plan : @model.VersionPlan,
) -> @model.VersionPlan {
  let npm_workspaces = loaded.snapshot.config.mixed_workspaces.filter(x => {
    x.ecosystem == "npm"
  })
  if npm_workspaces.is_empty() {
    return plan
  }
  let stage = @fs.tmpdir(prefix="moonset-lock-stage-")
  defer (@fs.rmdir(stage, recursive=true, allow_missing=true) catch { _ => () })
  copy_staging_tree(root, stage)
  for edit in plan.edits {
    let target = absolute(stage, edit.path)
    if edit.kind == "changeset" && edit.after_text == "" {
      safe_remove(target)
    } else {
      safe_mkdir(@path.Path(target).dirname().to_string())
      safe_write(target, edit.after_text)
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
    let package_json = @json.parse(safe_read(absolute(stage, package_path))) catch {
      _ =>
        raise @model.Invalid(
          @model.diagnostic(
            "invalid-package",
            "Cannot parse package manager manifest",
            path=package_path,
          ),
        )
    }
    let manager_value = match package_json {
      { "packageManager": String(value), .. } => value
      _ =>
        raise @model.Invalid(
          @model.diagnostic(
            "package-manager-required",
            "package.json must declare an exact packageManager version",
            path=package_path,
          ),
        )
    }
    let expected_prefix = workspace.manager + "@"
    if !manager_value.has_prefix(expected_prefix) {
      raise @model.Invalid(
        @model.diagnostic(
          "package-manager-conflict",
          "packageManager does not match the configured workspace manager",
          path=package_path,
        ),
      )
    }
    let version_parts = manager_value[expected_prefix.length():]
      .to_owned()
      .split("+")
      .collect()
    let exact_version = version_parts[0].to_owned()
    if exact_version == "" || !exact_version.contains(".") {
      raise @model.Invalid(
        @model.diagnostic(
          "package-manager-required",
          "packageManager must contain an exact version",
          path=package_path,
        ),
      )
    }
    let manager_program = package_manager_program(workspace.manager)
    let version_probe = @shell.Cmd(
      manager_program,
      ["--version"],
      cwd=absolute(stage, workspace_root),
    ).output()
    if version_probe.exit_code() != 0 ||
      version_probe.stdout().trim().to_owned() != exact_version {
      raise @model.Invalid(
        @model.diagnostic(
          "package-manager-version",
          "Installed " +
          workspace.manager +
          " does not match packageManager " +
          exact_version,
          path=package_path,
        ),
      )
    }
    let args = if workspace.manager == "pnpm" {
      ["install", "--lockfile-only", "--ignore-scripts", "--offline"]
    } else {
      ["install", "--package-lock-only", "--ignore-scripts", "--offline"]
    }
    let install = @shell.Cmd(
      manager_program,
      args,
      cwd=absolute(stage, workspace_root),
    ).output()
    if install.exit_code() != 0 {
      raise @model.Invalid(
        @model.diagnostic(
          "lockfile-stage-failed",
          "Package manager could not resolve lockfile offline: " +
          install.stderr(),
          path=package_path,
        ),
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
    let generated_path = absolute(stage, lock_path)
    if !safe_exists(generated_path) {
      raise @model.Invalid(
        @model.diagnostic(
          "lockfile-missing",
          "Package manager did not produce its declared lockfile",
          path=lock_path,
        ),
      )
    }
    let after = safe_read(generated_path)
    let source_path = absolute(root, lock_path)
    let before = if safe_exists(source_path) {
      safe_read(source_path)
    } else {
      ""
    }
    if loaded.snapshot.config.lockfiles == "verify-only" && before != after {
      raise @model.Invalid(
        @model.diagnostic(
          "lockfile-out-of-date",
          "Generated lockfile differs in verify-only mode",
          path=lock_path,
        ),
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
async fn version_command(options : Options) -> Int32 {
  if options.recover {
    return recover_version(options.cwd)
  }
  let loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
  )
  if loaded.snapshot.config.changelog != "builtin" {
    raise @model.Invalid(
      @model.diagnostic(
        "unsupported-capability", "Phase 3 only supports the builtin changelog generator",
      ),
    )
  }
  let analysis = @engine.build_plan(
    loaded.snapshot,
    loaded.changesets,
    pre?=loaded.pre,
  )
  let raw_plan = @engine.build_version_plan(
    loaded.snapshot,
    analysis,
    @model.VersionOptions::{
      dry_run: options.dry_run,
      no_changelog: options.no_changelog,
      snapshot_tag: options.snapshot,
    },
    generated_at=utc_date(@env.now()),
  )
  let plan = stage_lockfiles(loaded.snapshot.root, loaded, raw_plan)
  let rendered = if options.pretty {
    plan.to_json().stringify(indent=2)
  } else {
    @model.canonical_json(plan.to_json())
  }
  if options.dry_run || options.json {
    println(rendered)
  }
  if options.dry_run {
    return 0
  }
  if plan.edits.is_empty() {
    if !options.quiet && !options.json {
      println("No releases")
    }
    return 0
  }
  apply_version_plan(loaded.snapshot.root, plan)
  if !options.quiet && !options.json {
    println("Applied " + plan.edits.length().to_string() + " version edits")
  }
  0
}

///|
async fn git_result(
  root : String,
  args : Array[String],
) -> (Int32, String, String) {
  let output = @shell.Cmd("git", args, cwd=root).output()
  (output.exit_code(), output.stdout(), output.stderr())
}

///|
fn formatted_tag(intent : @model.TagIntent, template : String) -> String {
  if template == "" {
    return intent.name
  }
  let parts = intent.unit_id.split(":").collect()
  let ecosystem = if parts.length() > 0 {
    parts[0].to_owned()
  } else {
    "moonbit"
  }
  let name = if intent.unit_id.find(":") is Some(index) {
    intent.unit_id[index + 1:].to_owned()
  } else {
    intent.unit_id
  }
  template
  .replace_all(old="{ecosystem}", new=ecosystem)
  .replace_all(old="{name}", new=name)
  .replace_all(old="{version}", new=intent.version)
}

///|
async fn tag_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let state_path = absolute(loaded.snapshot.root, ".moonset/release-state.json")
  if !@fs.exists(state_path) {
    usage_error("No release state exists; run version first")
  }
  let state = @json.parse(@fs.read_text(state_path)) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic("usage", "Release state is not valid JSON"),
      )
  }
  guard state is { "tags": Array(items), .. } else {
    raise @model.Invalid(
      @model.diagnostic("usage", "Release state has no tag intents"),
    )
  }
  let intents : Array[@model.TagIntent] = []
  for item in items {
    guard item
      is {
        "unitId": String(unit_id),
        "version": String(version),
        "name": String(name),
        ..
      } else {
      usage_error("Release state contains an invalid tag intent")
    }
    intents.push({ unit_id, version, name, })
  }
  let configured_format = if options.tag_format == "" {
    loaded.snapshot.config.tag_format
  } else {
    options.tag_format
  }
  let configured_format = if configured_format == "auto" {
    ""
  } else {
    configured_format
  }
  for intent in intents {
    let mut unit : @model.ReleaseUnit? = None
    for candidate in loaded.snapshot.units {
      if candidate.id == intent.unit_id {
        unit = Some(candidate)
      }
    }
    if unit is Some(value) &&
      value.visibility == "private" &&
      !loaded.snapshot.config.private_tag {
      usage_error("Tagging private unit is disabled: " + intent.unit_id)
    }
  }
  let names = intents.map(intent => formatted_tag(intent, configured_format))
  for name in names {
    if name == "" ||
      name.contains(" ") ||
      name.contains("..") ||
      name.has_prefix("-") {
      usage_error("Invalid Git tag name: " + name)
    }
  }
  let (head_code, head_out, head_err) = git_result(loaded.snapshot.root, [
    "rev-parse", "HEAD",
  ])
  if head_code != 0 {
    raise @model.Io(head_err)
  }
  match state {
    { "sourceHead": String(source_head), .. } if source_head != "" &&
      source_head != head_out.trim().to_owned() =>
      usage_error("Git HEAD changed since version plan was applied")
    _ => ()
  }
  let (dirty_code, dirty_out, _) = git_result(loaded.snapshot.root, [
    "status", "--porcelain",
  ])
  if dirty_code == 0 && dirty_out.trim() != "" {
    usage_error("Working tree is dirty; commit version changes before tagging")
  }
  if options.dry_run || options.json {
    let output : Json = {
      "schemaVersion": 1,
      "head": head_out.trim(),
      "tags": names,
      "dryRun": options.dry_run,
    }
    println(
      if options.pretty {
        output.stringify(indent=2)
      } else {
        @model.canonical_json(output)
      },
    )
  }
  if options.dry_run {
    return 0
  }
  if options.tag_force && !options.yes {
    usage_error("--force requires --yes for tag")
  }
  for name in names {
    let (existing_code, _, _) = git_result(loaded.snapshot.root, [
      "rev-parse",
      "--verify",
      "refs/tags/" + name,
    ])
    if existing_code == 0 && !options.tag_force {
      usage_error("Tag already exists: " + name)
    }
    let args = if options.tag_force {
      ["tag", "-f", name, "HEAD"]
    } else {
      ["tag", name, "HEAD"]
    }
    let (created_code, _, created_err) = git_result(loaded.snapshot.root, args)
    if created_code != 0 {
      raise @model.Io(created_err)
    }
    if options.tag_push {
      let (pushed_code, _, pushed_err) = git_result(loaded.snapshot.root, [
        "push", "origin", name,
      ])
      if pushed_code != 0 {
        raise @model.Io(pushed_err)
      }
    }
  }
  if !options.quiet && !options.json {
    println("Created " + names.join(", "))
  }
  0
}

///|
/// Execute the native pack adapter and return a machine-readable result.
async fn pack_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let results : Array[Json] = []
  for unit in loaded.snapshot.units {
    match unit.version {
      None => ()
      Some(version) => {
        if options.dry_run && unit.ecosystem == "moonbit" {
          let result : @model.PackResult = {
            artifact_id: unit.id + "@" + version,
            unit_id: unit.id,
            version,
            target: "source",
            archive_path: "",
            source_commit: loaded.snapshot.git_head,
            content_hash: "",
            verified: false,
          }
          results.push(result.to_json())
          continue
        }
        let cwd = absolute(loaded.snapshot.root, unit.root)
        let args = if unit.ecosystem == "moonbit" {
          ["package", "--frozen"]
        } else if options.dry_run {
          ["pack", "--dry-run", "--ignore-scripts", "--json"]
        } else {
          ["pack", "--ignore-scripts", "--json"]
        }
        let program = if unit.ecosystem == "moonbit" {
          "moon"
        } else {
          package_manager_program("npm")
        }
        let output = @shell.Cmd(program, args, cwd~).output()
        if output.exit_code() != 0 {
          raise @model.Io(
            program + " pack failed for " + unit.id + ": " + output.stderr(),
          )
        }
        let packed = @json.parse(output.stdout()) catch { _ => Json::null() }
        let (archive, content_hash) = match packed {
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
          _ => ("", "")
        }
        let result : @model.PackResult = {
          artifact_id: unit.id + "@" + version,
          unit_id: unit.id,
          version,
          target: "source",
          archive_path: archive,
          source_commit: loaded.snapshot.git_head,
          content_hash,
          verified: unit.ecosystem == "npm" &&
          archive != "" &&
          content_hash != "",
        }
        results.push(result.to_json())
      }
    }
  }
  let result : Json = {
    "schemaVersion": 1,
    "dryRun": options.dry_run,
    "results": results,
  }
  if options.json {
    println(@model.canonical_json(result))
  } else {
    println("Packed " + results.length().to_string() + " artifacts")
  }
  0
}

///|
/// Publish versioned units with durable per-target status.
async fn publish_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let state_path = absolute(loaded.snapshot.root, ".moonset/release-state.json")
  if !safe_exists(state_path) {
    usage_error("No release state exists; run version first")
  }
  let state = @json.parse(safe_read(state_path)) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic("usage", "Release state is not valid JSON"),
      )
  }
  guard state
    is { "planFingerprint": String(plan_id), "releases": Array(items), .. } else {
    raise @model.Invalid(
      @model.diagnostic("usage", "Release state has an invalid shape"),
    )
  }
  let statuses : Array[Json] = []
  let completed : Map[String, Bool] = Map([])
  let previous_path = absolute(
    loaded.snapshot.root,
    ".moonset/publish-state.json",
  )
  if safe_exists(previous_path) {
    let previous = @json.parse(safe_read(previous_path)) catch {
      _ => Json::null()
    }
    match previous {
      {
        "planId": String(previous_plan),
        "statuses": Array(previous_statuses),
        ..
      } if previous_plan == plan_id =>
        for previous_status in previous_statuses {
          match previous_status {
            {
              "unitId": String(previous_unit),
              "version": String(previous_version),
              "target": String(previous_target),
              "state": String("published"),
              ..
            } =>
              completed[previous_unit +
              "@" +
              previous_version +
              "/" +
              previous_target] = true
            _ => ()
          }
          statuses.push(previous_status)
        }
      _ => ()
    }
  }
  let mut failed = false
  let targets : Array[(String, String, String, String)] = []
  for item in items {
    guard item
      is {
        "unitId": String(unit_id),
        "newVersion": String(version),
        "publish": True,
        ..
      } else {
      continue
    }
    if options.only is Some(only) && only != unit_id {
      continue
    }
    if completed.contains(unit_id + "@" + version + "/source") {
      continue
    }
    let mut unit : @model.ReleaseUnit? = None
    for candidate in loaded.snapshot.units {
      if candidate.id == unit_id {
        unit = Some(candidate)
      }
    }
    match unit {
      None => {
        failed = true
        statuses.push({
          "unitId": unit_id,
          "version": version,
          "target": "source",
          "state": "blocked",
          "message": "unit not found",
        })
      }
      Some(unit) => {
        let cwd = absolute(loaded.snapshot.root, unit.root)
        let program = if unit.ecosystem == "moonbit" {
          "moon"
        } else {
          package_manager_program("npm")
        }
        let preflight_args = if unit.ecosystem == "moonbit" {
          ["publish", "--dry-run"]
        } else {
          ["publish", "--dry-run", "--ignore-scripts"]
        }
        let preflight = @shell.Cmd(program, preflight_args, cwd~).output()
        let ok = preflight.exit_code() == 0
        if !ok {
          failed = true
        }
        statuses.push({
          "planId": plan_id,
          "unitId": unit_id,
          "version": version,
          "target": "source",
          "registry": if unit.ecosystem == "npm" {
            "npm"
          } else {
            "mooncakes"
          },
          "state": if ok {
            "preflighted"
          } else {
            "blocked"
          },
          "message": if ok {
            Json::null()
          } else {
            Json::string(preflight.stderr())
          },
        })
        if ok {
          targets.push((unit_id, version, unit.ecosystem, cwd))
        }
      }
    }
  }
  safe_mkdir(absolute(loaded.snapshot.root, ".moonset"))
  safe_write(
    absolute(loaded.snapshot.root, ".moonset/publish-state.json"),
    @model.canonical_json({
      "schemaVersion": 1,
      "planId": plan_id,
      "statuses": statuses,
    }) +
    "\n",
  )
  if options.dry_run || failed {
    let result : Json = {
      "schemaVersion": 1,
      "planId": plan_id,
      "dryRun": options.dry_run,
      "complete": false,
      "statuses": statuses,
    }
    if options.json {
      println(@model.canonical_json(result))
    } else {
      println(
        if failed {
          "Publish preflight failed"
        } else {
          "Publish preflight complete"
        },
      )
    }
    return if failed { 3 } else { 0 }
  }
  for (unit_id, version, ecosystem, cwd) in targets {
    let program = if ecosystem == "moonbit" {
      "moon"
    } else {
      package_manager_program("npm")
    }
    let args = if ecosystem == "moonbit" {
      ["publish"]
    } else {
      ["publish", "--ignore-scripts"]
    }
    let output = @shell.Cmd(program, args, cwd~).output()
    let ok = output.exit_code() == 0
    if !ok {
      failed = true
    }
    statuses.push({
      "planId": plan_id,
      "unitId": unit_id,
      "version": version,
      "target": "source",
      "registry": if ecosystem == "npm" {
        "npm"
      } else {
        "mooncakes"
      },
      "state": if ok {
        "published"
      } else {
        "failed"
      },
      "message": if ok {
        Json::null()
      } else {
        Json::string(output.stderr())
      },
    })
    safe_write(
      absolute(loaded.snapshot.root, ".moonset/publish-state.json"),
      @model.canonical_json({
        "schemaVersion": 1,
        "planId": plan_id,
        "statuses": statuses,
      }) +
      "\n",
    )
  }
  safe_mkdir(absolute(loaded.snapshot.root, ".moonset"))
  safe_write(
    absolute(loaded.snapshot.root, ".moonset/publish-state.json"),
    @model.canonical_json({
      "schemaVersion": 1,
      "planId": plan_id,
      "statuses": statuses,
    }) +
    "\n",
  )
  let result : Json = {
    "schemaVersion": 1,
    "planId": plan_id,
    "dryRun": options.dry_run,
    "complete": !failed,
    "statuses": statuses,
  }
  if options.json {
    println(@model.canonical_json(result))
  } else {
    println(
      if failed {
        "Publish failed; see .moonset/publish-state.json"
      } else {
        "Publish complete"
      },
    )
  }
  if failed {
    3
  } else {
    0
  }
}

///|
async fn write_new_file(path : String, content : String) -> Bool {
  if @fs.exists(path) {
    return false
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  let file = @fs.create(path, allow_existing=false)
  defer file.close()
  file.write(@utf8.encode(content))
  true
}

///|
async fn init_command(options : Options) -> Int32 {
  let _force = options.force
  let dir = @path.Path(options.cwd).join(@path.Path(".changeset")).to_string()
  let config_path = @path.Path(dir).join(@path.Path("config.json")).to_string()
  let config = "{\n  \"changelog\": {\"generator\": \"builtin\"},\n  \"access\": \"public\",\n  \"baseBranch\": \"main\",\n  \"commit\": {\"mode\": \"never\"},\n  \"formatter\": \"builtin\"\n}\n"
  let created : Array[String] = []
  if write_new_file(config_path, config) {
    created.push(".changeset/config.json")
  }
  let readme = @path.Path(dir).join(@path.Path("README.md")).to_string()
  if write_new_file(
      readme, "# Changesets\n\nRun moonset add to record a release.\n",
    ) {
    created.push(".changeset/README.md")
  }
  let gitignore = @path.Path(dir).join(@path.Path(".gitignore")).to_string()
  if write_new_file(gitignore, "pre.json\n") {
    created.push(".changeset/.gitignore")
  }
  let state_dir = @path.Path(options.cwd)
    .join(@path.Path(".moonset"))
    .to_string()
  let state_ignore = @path.Path(state_dir)
    .join(@path.Path(".gitignore"))
    .to_string()
  if write_new_file(state_ignore, "version-journal.json\n") {
    created.push(".moonset/.gitignore")
  }
  if options.json {
    println(@model.canonical_json({ "created": created, "config": config }))
  } else if !options.quiet {
    println(
      if created.is_empty() {
        "Changeset configuration already exists"
      } else {
        "Initialized .changeset"
      },
    )
  }
  0
}

///|
async fn add_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  if !options.json && @io.is_tty() {
    return interactive_add(options, loaded)
  }
  let summary = options.summary.unwrap_or("")
  let package_text = options.package_name.unwrap_or("")
  let names : Array[String] = if package_text == "" {
    []
  } else {
    package_text
    .split(",")
    .map(x => x.trim().to_owned())
    .filter(x => x != "")
    .collect()
  }
  let bump_text = options.bump.unwrap_or("patch")
  let bump = match bump_text {
    "major" => @model.Major
    "minor" => @model.Minor
    "patch" => @model.Patch
    "none" => @model.None
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "usage", "--type expects major, minor, patch, or none",
        ),
      )
  }
  let selected : Array[@model.Change] = if options.empty {
    []
  } else {
    names.map(name => @model.Change::{
      unit_id: @engine.canonical_id(name),
      bump,
    })
  }
  if selected.is_empty() && !options.empty {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "add requires --package or --empty in non-interactive mode",
      ),
    )
  }
  let text = if options.empty {
    "---\n---\n\n" + summary.trim().to_owned() + "\n"
  } else {
    @engine.format_changeset(@model.ChangesetDraft::{
      releases: selected,
      summary,
    })
  }
  let base = loaded.changeset_directory
  let original = options.id.unwrap_or("change-" + @env.now().to_string())
  let mut stem = original
  let mut written = ""
  let mut attempt = 0
  while written == "" {
    let path = @path.Path(loaded.snapshot.root)
      .join(@path.Path(base))
      .join(@path.Path(stem + ".md"))
      .to_string()
    if !@fs.exists(path) {
      let file = @fs.create(path, allow_existing=false)
      defer file.close()
      file.write(@utf8.encode(text))
      written = path
    } else {
      attempt += 1
      stem = original + "-" + attempt.to_string()
    }
  }
  if options.json {
    println(
      @model.canonical_json({ "id": stem, "path": written, "summary": summary }),
    )
  } else if !options.quiet {
    println("Created " + written)
  }
  0
}

///|
async fn interactive_add(
  options : Options,
  loaded : @workspace.LoadedWorkspace,
) -> Int32 {
  let labels = loaded.snapshot.units.map(x => x.id)
  let versions = loaded.snapshot.units.map(x => {
    x.version.unwrap_or("unversioned")
  })
  let mut state = SelectState::new(labels.length())
  tui_begin()
  defer tui_cleanup()
  let mut done = false
  while !done && !state.cancelled {
    @tui.print_raw(
      "\u001b[2J\u001b[H" + render_package_page(labels, versions, state) + "\n",
    )
    let key = tui_key(@tui.read_key())
    state = reduce_select(state, key)
    done = state.confirmed
  }
  if state.cancelled || !state.confirmed {
    return 130
  }
  let selected = []
  for i, chosen in state.selected {
    if chosen {
      selected.push(@model.Change::{ unit_id: labels[i], bump: @model.Patch, })
    }
  }
  if selected.is_empty() {
    return 2
  }
  @tui.print_raw("\u001b[2J\u001b[H? Enter a summary for this change\n")
  let mut summary = ""
  let mut submitted = false
  while !submitted {
    @tui.print_raw("  " + summary + "\u001b[K\r")
    let key = tui_key(@tui.read_key())
    let (next, confirm, cancel) = edit_summary(summary, key)
    summary = next
    if cancel {
      return 130
    }
    submitted = confirm
  }
  let text = @engine.format_changeset(@model.ChangesetDraft::{
    releases: selected,
    summary,
  })
  let original = options.id.unwrap_or("change-" + @env.now().to_string())
  let path = @path.Path(loaded.snapshot.root)
    .join(@path.Path(loaded.changeset_directory))
    .join(@path.Path(original + ".md"))
    .to_string()
  let file = @fs.create(path, allow_existing=false)
  defer file.close()
  file.write(@utf8.encode(text))
  0
}

///|
async fn pre_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let path = @path.Path(loaded.snapshot.root)
    .join(@path.Path(loaded.snapshot.config.pre_file))
    .to_string()
  let action = options.pre_action.unwrap_or("status")
  if action == "status" {
    if @fs.exists(path) {
      println(@fs.read_text(path))
    } else {
      println("null")
    }
    return 0
  }
  if action == "exit" {
    if @fs.exists(path) {
      @fs.remove(path, allow_missing=true)
    }
    return 0
  }
  if action != "enter" {
    raise @model.Invalid(
      @model.diagnostic("usage", "pre expects enter, exit, or status"),
    )
  }
  let initial : Map[String, String] = Map([])
  if options.initial_version {
    for unit in loaded.snapshot.units {
      match unit.version {
        Some(v) => initial[unit.id] = v
        None => ()
      }
    }
  }
  let state : @model.PreState = {
    mode: "active",
    tag: "next",
    initial_versions: initial,
    next_numbers: Map([]),
    consumed: [],
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(path, state.to_json().stringify(indent=2) + "\n")
  0
}

///|
async fn write_plan(
  path : String,
  text : String,
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory : String,
) -> Unit {
  let absolute = @path.Path(path).resolve().to_string()
  let directory = @fs.realpath(@path.Path(absolute).dirname().to_string())
  let resolved = if @fs.exists(absolute) {
    @fs.realpath(absolute)
  } else {
    @path.Path(directory)
    .join(@path.Path(@path.Path(absolute).basename().to_owned()))
    .to_string()
  }
  for source in snapshot.sources.keys() {
    let input = @path.Path(snapshot.root)
      .join(@path.Path(source))
      .normalize()
      .to_string()
    let canonical = if @fs.exists(input) { @fs.realpath(input) } else { input }
    if @path.Path(resolved) == @path.Path(canonical) {
      usage_error("Plan output cannot overwrite an input file: " + source)
    }
  }
  let basename = @path.Path(absolute).basename().to_owned()
  if ["moon.mod", "moon.pkg", "moon.work", "package.json", "Cargo.toml"].contains(
      basename,
    ) {
    usage_error("Plan output cannot overwrite a manifest")
  }
  let relative = @path.Path(resolved)
    .relative(base=@path.Path(snapshot.root))
    .to_string()
    .replace_all(old="\\", new="/")
  if relative.split("/").any(x => x == ".git") ||
    relative.has_prefix(changeset_directory + "/") {
    usage_error("Plan output cannot overwrite release or Git inputs")
  }
  if @fs.exists(absolute) {
    let existing = @json.parse(@fs.read_text(absolute)) catch {
      _ => Json::null()
    }
    if !(existing
      is { "schemaVersion": 1, "stage": "analysis", "executable": False, .. }) {
      usage_error(
        "Existing output is not a moonset analysis plan; refusing to overwrite it",
      )
    }
  }
  let temporary = @path.Path(directory)
    .join(@path.Path(".moonset-plan-\{@env.now()}.tmp"))
    .to_string()
  let file = @fs.create(temporary, allow_existing=false)
  defer (@fs.remove(temporary, allow_missing=true) catch { _ => () })
  {
    defer file.close()
    file.write(@utf8.encode(text + "\n"))
  }
  @fs.rename(temporary, absolute, replace=true)
}

///|
async fn execute(options : Options) -> Int32 {
  let _ = options.no_commit
  if options.command == "help" {
    println(
      "moonset Phase 4\n  init [--force]\n  add --package unit[,unit] --type major|minor|patch|none --summary text\n  pre enter|exit|status [--initial-version]\n  status [--since ref] [--verbose] [--output human|json]\n  publish-plan [--since ref] [--output path|-] [--pretty]\n  version [--dry-run] [--no-changelog] [--recover]\n  pack [--dry-run] [--json]\n  publish [--dry-run] [--only unit] [--yes] [--json]\n  tag|git-tag [--dry-run] [--push] [--force] [--format template]\n  Global: --cwd path --config path --json --quiet --no-color --help --version",
    )
    return 0
  }
  if options.command == "version-info" {
    println("moonset 0.1.0-alpha.1")
    return 0
  }
  if options.command == "init" {
    return init_command(options)
  }
  if options.command == "add" {
    return add_command(options)
  }
  if options.command == "pre" {
    return pre_command(options)
  }
  if options.command == "version" {
    return version_command(options)
  }
  if options.command == "tag" || options.command == "git-tag" {
    return tag_command(options)
  }
  if options.command == "pack" {
    return pack_command(options)
  }
  if options.command == "publish" {
    return publish_command(options)
  }
  let loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
  )
  let plan = @engine.build_plan(
    loaded.snapshot,
    loaded.changesets,
    pre?=loaded.pre,
  )
  let status = @engine.status_json(
    loaded.snapshot,
    plan,
    changeset_directory=loaded.changeset_directory,
  )
  let result = if options.command == "status" { status } else { plan.to_json() }
  for warning in plan.warnings {
    stderr(warning.code + ": " + warning.message)
  }
  let text = if options.pretty {
    result.stringify(indent=2)
  } else {
    @model.canonical_json(result)
  }
  if options.command == "publish-plan" &&
    options.output != "" &&
    options.output != "-" {
    let path = if @path.Path(options.output).is_absolute() {
      options.output
    } else {
      @path.Path(options.cwd).join(@path.Path(options.output)).to_string()
    }
    write_plan(path, text, loaded.snapshot, loaded.changeset_directory)
  } else if options.json {
    println(text)
  } else if !options.quiet {
    println(
      "\{loaded.snapshot.units.length()} modules; \{loaded.changesets.length()} changesets; \{plan.releases.length()} releases",
    )
    for release in plan.releases {
      println(
        release.unit_id +
        ": " +
        release.old_version +
        " -> " +
        release.new_version,
      )
      if options.verbose {
        println("  " + release.reasons.join(", "))
      }
    }
    if options.verbose {
      for path in loaded.snapshot.unmanaged {
        println("unmanaged: " + path)
      }
      for path in loaded.snapshot.changed_files {
        println("changed: " + path)
      }
    }
  }
  if options.command == "status" &&
    status is { "errors": Array(errors), .. } &&
    !errors.is_empty() {
    stderr(
      "missing-changeset: Relevant committed files changed without a changeset",
    )
    1
  } else {
    0
  }
}

///|
/// Run CLI arguments without the executable name. Errors never escape this boundary.
pub async fn run(args : Array[String]) -> Int32 {
  let wants_json = args.contains("--json") ||
    args.contains("publish-plan") ||
    args.contains("json")
  execute(arguments(args)) catch {
    error => {
      let (code, diagnostic) = match error {
        @model.Invalid(diagnostic) => (2, diagnostic)
        @model.Io(message) => (3, @model.diagnostic("external-error", message))
        _ => (3, @model.diagnostic("external-error", error.to_string()))
      }
      if wants_json {
        println(
          @model.canonical_json({
            "schemaVersion": 1,
            "workspace": Json::null(),
            "changesets": [],
            "releases": [],
            "warnings": [],
            "errors": [diagnostic.to_json()],
            "hasChanges": false,
            "hasRelease": false,
          }),
        )
      }
      stderr(
        "\{diagnostic.path}:\{diagnostic.line}:\{diagnostic.column}: " +
        diagnostic.code +
        ": " +
        diagnostic.message,
      ) catch {
        _ => ()
      }
      code
    }
  }
}
