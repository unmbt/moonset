///|
pub(all) struct PublishOptions {
  dry_run : Bool
  only : Array[String]
  registry : String?
  tag : String?
  yes : Bool
  allow_uncommitted : Bool
  retry : Int32
  no_tag : Bool
}

///|
fn registry_for_ecosystem(ecosystem : String) -> String {
  if ecosystem == "cargo" {
    "crates.io"
  } else if ecosystem == "npm" {
    "npm"
  } else {
    "mooncakes"
  }
}

///|
fn parse_publish_state(name : String) -> @model.PublishState {
  match name {
    "pending" => @model.Pending
    "preflighted" => @model.Preflighted
    "published" => @model.Published
    "skipped" => @model.Skipped
    "failed" => @model.Failed
    "blocked" => @model.Blocked
    _ => @model.Unknown
  }
}

///|
fn status_key(unit_id : String, version : String, target : String) -> String {
  unit_id + "@" + version + "/" + target
}

///|
async fn[H : ExecutionHost] registry_lookup(
  host : H,
  ecosystem : String,
  manager : String,
  name : String,
  version : String,
  cwd : String,
  registry_override : String?,
) -> String {
  if ecosystem == "moonbit" {
    return "absent"
  }
  let package_id = name + "@" + version
  let (program, args) = if ecosystem == "cargo" {
    let base = ["info", package_id]
    if registry_override is Some(reg) {
      base.push("--registry")
      base.push(reg)
    }
    ("cargo", base)
  } else {
    let base = ["view", package_id, "version", "--json"]
    if registry_override is Some(reg) {
      base.push("--registry")
      base.push(reg)
    }
    (package_manager_program(host, manager), base)
  }
  let output = host.run(program, args, Some(cwd))
  if output.exit_code == 0 {
    "present"
  } else if ecosystem == "cargo" &&
    (
      output.stderr.contains("could not find") ||
      output.stderr.contains("does not exist") ||
      output.stderr.contains("not found")
    ) {
    "absent"
  } else if ecosystem == "npm" &&
    (output.stderr.contains("E404") || output.stderr.contains("404 Not Found")) {
    "absent"
  } else {
    "unknown"
  }
}

///|
fn topological_release_order(
  release_ids : Array[String],
  units_map : Map[String, @model.ReleaseUnit],
  bridges : Array[@model.Bridge],
) -> Array[String] {
  let ordered : Array[String] = []
  let visited : Map[String, Bool] = Map([])
  fn visit(id : String) {
    if visited.contains(id) {
      return
    }
    visited[id] = true
    if units_map.get(id) is Some(unit) {
      for dep in unit.dependencies {
        if dep.kind == @model.Runtime && release_ids.contains(dep.producer) {
          visit(dep.producer)
        }
      }
    }
    for bridge in bridges {
      if bridge.consumer == id && release_ids.contains(bridge.producer) {
        visit(bridge.producer)
      }
    }
    ordered.push(id)
  }
  for id in release_ids {
    visit(id)
  }
  ordered
}

///|
fn upstream_producers(
  unit_id : String,
  units_map : Map[String, @model.ReleaseUnit],
  bridges : Array[@model.Bridge],
) -> Array[String] {
  let producers : Array[String] = []
  if units_map.get(unit_id) is Some(unit) {
    for dep in unit.dependencies {
      if dep.kind == @model.Runtime && !producers.contains(dep.producer) {
        producers.push(dep.producer)
      }
    }
  }
  for bridge in bridges {
    if bridge.consumer == unit_id && !producers.contains(bridge.producer) {
      producers.push(bridge.producer)
    }
  }
  producers
}

///|
fn persist_publish_state(
  plan_id : String,
  order_keys : Array[String],
  status_map : Map[String, @model.PublishStatus],
) -> (Array[@model.PublishStatus], String) {
  let statuses : Array[@model.PublishStatus] = []
  for key in order_keys {
    if status_map.get(key) is Some(item) {
      statuses.push(item)
    }
  }
  for key, item in status_map {
    if !order_keys.contains(key) {
      statuses.push(item)
    }
  }
  let text = @model.canonical_json({
      "schemaVersion": 1,
      "planId": plan_id,
      "statuses": statuses.map(x => x.to_json()),
    }) +
    "\n"
  (statuses, text)
}

///|
pub async fn[H : ExecutionHost] publish_release_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
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
  guard state
    is { "planFingerprint": String(plan_id), "releases": Array(items), .. } else {
    raise invalid_error(
      "usage",
      "Release state has an invalid shape",
      path=state_path,
    )
  }
  let units_map : Map[String, @model.ReleaseUnit] = Map([])
  for unit in loaded.snapshot.units {
    units_map[unit.id] = unit
  }
  let release_versions : Map[String, String] = Map([])
  let release_ids : Array[String] = []
  for item in items {
    if item
      is {
        "unitId": String(unit_id),
        "newVersion": String(version),
        "publish": True,
        ..
      } {
      release_versions[unit_id] = version
      release_ids.push(unit_id)
    }
  }
  let selected_ids : Array[String] = if options.only.is_empty() {
    release_ids.copy()
  } else {
    let chosen : Array[String] = []
    for raw in options.only {
      let id = @engine.canonical_id(raw)
      if !release_versions.contains(id) {
        raise invalid_error(
          "unknown-unit",
          "--only references a unit not in the release plan: " + raw,
        )
      }
      if !chosen.contains(id) {
        chosen.push(id)
      }
    }
    let missing : Array[String] = []
    for group in loaded.snapshot.config.fixed {
      if group.any(id => chosen.contains(id)) {
        for group_member in group {
          if release_versions.contains(group_member) &&
            !chosen.contains(group_member) &&
            !missing.contains(group_member) {
            missing.push(group_member)
          }
        }
      }
    }
    for id in chosen {
      for
        producer in upstream_producers(
          id,
          units_map,
          loaded.snapshot.config.bridges,
        ) {
        if release_versions.contains(producer) &&
          !chosen.contains(producer) &&
          !missing.contains(producer) {
          missing.push(producer)
        }
      }
    }
    if !missing.is_empty() {
      missing.sort()
      raise invalid_error(
        "incomplete-selection",
        "Incomplete --only selection; missing required closure members: " +
        missing.join(", "),
      )
    }
    chosen
  }
  if loaded.snapshot.config.publisher_kind == "api" {
    raise invalid_error(
      "unsupported-capability", "publisher.kind='api' must be invoked programmatically through an adapter",
    )
  }
  let use_command_publisher = loaded.snapshot.config.publisher_kind == "command"
  let command_publishers = @adapters.PublisherRegistry::new()
  if use_command_publisher {
    let cmd = loaded.snapshot.config.publisher_command
    if cmd.is_empty() {
      raise invalid_error(
        "invalid-config", "publisher.command must not be empty when publisher.kind='command'",
      )
    }
    let env : Map[String, String] = Map([])
    for key in ["PATH", "SystemRoot"] {
      if host.getenv(key) is Some(val) {
        env[key] = val
      }
    }
    if loaded.snapshot.config.publisher_token_env is Some(token_var) {
      if host.getenv(token_var) is Some(val) {
        env[token_var] = val
      }
    }
    command_publishers.register("command", {
      program: cmd[0],
      args: cmd[1:].to_owned(),
      cwd: Some(loaded.snapshot.root),
      timeout_ms: 30000,
      max_output_bytes: 1048576,
      allowed_programs: [cmd[0]],
      environment: env,
    })
  }
  let mut worktree_dirty = false
  if !options.dry_run {
    let dirty = host.run(
      "git",
      ["status", "--porcelain"],
      Some(loaded.snapshot.root),
    )
    worktree_dirty = dirty.exit_code == 0 && dirty.stdout.trim() != ""
    if worktree_dirty && !options.allow_uncommitted {
      raise invalid_error(
        "dirty-working-tree", "Working tree is dirty; commit release changes or pass --allow-uncommitted",
      )
    }
  }
  if !options.dry_run && !options.yes {
    raise invalid_error(
      "confirmation-required", "Real publish requires explicit --yes confirmation",
    )
  }
  let pack_state_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/pack-results.json",
  )
  let packed_by_unit : Map[String, Json] = Map([])
  if host.exists(pack_state_path) {
    let pack_json = @json.parse(host.read_text(pack_state_path)) catch {
      _ => Json::null()
    }
    if pack_json is { "results": Array(entries), .. } {
      for entry in entries {
        if entry is { "unitId": String(uid), .. } {
          packed_by_unit[uid] = entry
        }
      }
    }
  }
  let selected_ecosystems : Array[String] = []
  for unit_id in selected_ids {
    if units_map.get(unit_id) is Some(unit) {
      if !use_command_publisher {
        adapter_registry.require(unit.ecosystem, @adapters.Publish)
      }
      if unit.version != Some(release_versions[unit_id]) {
        raise invalid_error(
          "stale-release-state",
          "Current manifest version does not match release-state.json for " +
          unit.id,
          path=unit.manifest,
        )
      }
      if packed_by_unit.get(unit_id) is Some(pack_entry) {
        match pack_entry {
          {
            "version": String(pack_ver),
            "verified": True,
            "archivePath": String(archive_path),
            ..
          } => {
            if pack_ver != release_versions[unit_id] {
              raise invalid_error(
                "stale-artifact",
                "Packed artifact version does not match release state for " +
                unit.id,
                path=pack_state_path,
              )
            }
            if archive_path != "" && !host.exists(archive_path) {
              raise invalid_error(
                "artifact-missing",
                "Packed artifact is missing on disk: " + archive_path,
                path=archive_path,
              )
            }
            if pack_entry is { "sourceCommit": String(pack_commit), .. } &&
              loaded.snapshot.git_head is Some(head) &&
              pack_commit != head {
              raise invalid_error(
                "stale-artifact",
                "Packed artifact commit does not match current HEAD for " +
                unit.id,
                path=pack_state_path,
              )
            }
          }
          _ =>
            raise invalid_error(
              "artifact-missing",
              "Packed artifact is unverified for " + unit.id,
              path=pack_state_path,
            )
        }
      }
      if unit.visibility == "private" && !loaded.snapshot.config.private_publish {
        raise invalid_error(
          "private-policy",
          "Publishing private unit is disabled: " + unit.id,
          path=unit.manifest,
        )
      }
      if !selected_ecosystems.contains(unit.ecosystem) {
        selected_ecosystems.push(unit.ecosystem)
      }
    }
  }
  if selected_ecosystems.length() > 1 &&
    (options.registry is Some(_) || options.tag is Some(_)) {
    raise invalid_error(
      "unsupported-capability", "--registry and --tag overrides cannot be applied across mixed ecosystems",
    )
  }
  if !use_command_publisher &&
    options.registry is Some(_) &&
    selected_ecosystems.contains("moonbit") {
    raise invalid_error(
      "unsupported-capability", "Mooncakes CLI does not support --registry overrides",
    )
  }
  if options.tag is Some(_) &&
    (
      selected_ecosystems.contains("moonbit") ||
      selected_ecosystems.contains("cargo")
    ) {
    raise invalid_error(
      "unsupported-capability", "Only npm/pnpm registries support --tag dist-tag overrides",
    )
  }
  let status_map : Map[String, @model.PublishStatus] = Map([])
  let previous_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/publish-state.json",
  )
  if host.exists(previous_path) {
    let previous = @json.parse(host.read_text(previous_path)) catch {
      _ => Json::null()
    }
    match previous {
      {
        "planId": String(previous_plan),
        "statuses": Array(previous_statuses),
        ..
      } if previous_plan == plan_id =>
        for previous_status in previous_statuses {
          if previous_status
            is {
              "unitId": String(previous_unit),
              "version": String(previous_version),
              "target": String(previous_target),
              "state": String(previous_state),
              ..
            } {
            let registry = match previous_status {
              { "registry": String(reg), .. } => reg
              _ => "unknown"
            }
            let message = match previous_status {
              { "message": String(msg), .. } => Some(msg)
              _ => None
            }
            let parsed_state = if previous_state == "publishing" {
              @model.Unknown
            } else {
              parse_publish_state(previous_state)
            }
            let key = status_key(
              previous_unit, previous_version, previous_target,
            )
            status_map[key] = {
              plan_id,
              unit_id: previous_unit,
              version: previous_version,
              target: previous_target,
              registry,
              state: parsed_state,
              digest: None,
              external_id: None,
              message,
            }
          }
        }
      _ => ()
    }
  }
  let ordered_ids = topological_release_order(
    selected_ids,
    units_map,
    loaded.snapshot.config.bridges,
  )
  let order_keys = ordered_ids.map(id => {
    status_key(id, release_versions[id], "source")
  })
  let mut failed = false
  let failed_units : Map[String, Bool] = Map([])
  let to_publish : Array[(String, String, String, String, String)] = []
  for unit_id in ordered_ids {
    let version = release_versions[unit_id]
    let key = status_key(unit_id, version, "source")
    let unit_opt = units_map.get(unit_id)
    let registry = match unit_opt {
      Some(unit) =>
        options.registry.unwrap_or(registry_for_ecosystem(unit.ecosystem))
      None => "unknown"
    }
    if status_map.get(key) is Some(prev) {
      if prev.state == @model.Published {
        continue
      }
      if prev.state == @model.Unknown {
        failed = true
        failed_units[unit_id] = true
        status_map[key] = {
          ..prev,
          state: @model.Blocked,
          message: Some(
            "Previous publish outcome is unknown; verify the registry before retrying",
          ),
        }
        continue
      }
    }
    let blocked_by = upstream_producers(
      unit_id,
      units_map,
      loaded.snapshot.config.bridges,
    ).filter(p => failed_units.contains(p))
    if !blocked_by.is_empty() {
      failed = true
      failed_units[unit_id] = true
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Blocked,
        digest: None,
        external_id: None,
        message: Some("Blocked by failed upstream dependency: " + blocked_by[0]),
      }
      continue
    }
    guard unit_opt is Some(unit) else {
      failed = true
      failed_units[unit_id] = true
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Blocked,
        digest: None,
        external_id: None,
        message: Some("unit not found"),
      }
      continue
    }
    let configured_registry = if loaded.snapshot.config.publisher_registry !=
      "default" {
      Some(loaded.snapshot.config.publisher_registry)
    } else {
      None
    }
    let effective_registry = match options.registry {
      Some(reg) => Some(reg)
      None => configured_registry
    }
    let unit_publisher = loaded.snapshot.config.unit_overrides
      .get(unit.id)
      .bind(x => x.publisher)
    let effective_manager = match unit_publisher {
      Some("npm" | "pnpm" as mgr) => mgr
      _ => manager_for_unit(loaded.snapshot, unit)
    }
    let cwd = absolute_path(loaded.snapshot.root, unit.root)
    let registry_state = if use_command_publisher {
      let resp = command_publishers.execute("command", "already-published", {
        "unitId": unit.id,
        "name": unit.native_name,
        "version": version,
        "ecosystem": unit.ecosystem,
        "registry": registry,
      })
      match resp {
        { "published": True, .. } | True => "present"
        _ => "absent"
      }
    } else {
      registry_lookup(
        host,
        unit.ecosystem,
        effective_manager,
        unit.native_name,
        version,
        cwd,
        effective_registry,
      )
    }
    if registry_state == "present" {
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Published,
        digest: None,
        external_id: None,
        message: Some("already published"),
      }
      continue
    }
    if registry_state == "unknown" {
      failed = true
      failed_units[unit_id] = true
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Blocked,
        digest: None,
        external_id: None,
        message: Some(
          "Could not determine whether the package is already published",
        ),
      }
      continue
    }
    let mut ok = true
    if options.dry_run || loaded.snapshot.config.publisher_dry_run_first {
      if use_command_publisher {
        let preflight_ok = try {
          ignore(
            command_publishers.execute("command", "preflight", {
              "unitId": unit.id,
              "name": unit.native_name,
              "version": version,
              "ecosystem": unit.ecosystem,
              "registry": registry,
            }),
          )
          true
        } catch {
          _ => false
        }
        ok = preflight_ok
      } else {
        let program = if unit.ecosystem == "moonbit" {
          "moon"
        } else if unit.ecosystem == "cargo" {
          "cargo"
        } else {
          package_manager_program(host, effective_manager)
        }
        let preflight_args = if unit.ecosystem == "moonbit" {
          ["publish", "--dry-run"]
        } else if unit.ecosystem == "cargo" {
          let args = ["publish", "--dry-run", "--allow-dirty"]
          if effective_registry is Some(reg) {
            args.push("--registry")
            args.push(reg)
          }
          args
        } else {
          let args = ["publish", "--dry-run", "--ignore-scripts"]
          if effective_registry is Some(reg) {
            args.push("--registry")
            args.push(reg)
          }
          if options.tag is Some(dist_tag) {
            args.push("--tag")
            args.push(dist_tag)
          }
          args
        }
        let preflight = host.run(program, preflight_args, Some(cwd))
        ok = preflight.exit_code == 0
      }
    }
    if !ok {
      failed = true
      failed_units[unit_id] = true
    }
    status_map[key] = {
      plan_id,
      unit_id,
      version,
      target: "source",
      registry,
      state: if ok {
        @model.Preflighted
      } else {
        @model.Failed
      },
      digest: None,
      external_id: None,
      message: if ok {
        None
      } else {
        Some("Registry preflight failed")
      },
    }
    if ok {
      to_publish.push(
        (unit_id, version, unit.ecosystem, effective_manager, cwd),
      )
    }
  }
  host.mkdir(absolute_path(loaded.snapshot.root, ".moonset"))
  let (preflight_statuses, preflight_text) = persist_publish_state(
    plan_id, order_keys, status_map,
  )
  host.write_text(previous_path, preflight_text)
  if options.dry_run || failed {
    return {
      schema_version: 1,
      plan_id,
      dry_run: options.dry_run,
      complete: false,
      statuses: preflight_statuses,
      recovery_path: if failed {
        Some(".moonset/publish-state.json")
      } else {
        None
      },
    }
  }
  let max_attempts = if options.retry > 0 { options.retry + 1 } else { 1 }
  for item in to_publish {
    let (unit_id, version, ecosystem, manager, cwd) = item
    let key = status_key(unit_id, version, "source")
    let registry = options.registry.unwrap_or(registry_for_ecosystem(ecosystem))
    let blocked_by = upstream_producers(
      unit_id,
      units_map,
      loaded.snapshot.config.bridges,
    ).filter(p => failed_units.contains(p))
    if !blocked_by.is_empty() {
      failed = true
      failed_units[unit_id] = true
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Blocked,
        digest: None,
        external_id: None,
        message: Some("Blocked by failed upstream dependency: " + blocked_by[0]),
      }
      let (_, text) = persist_publish_state(plan_id, order_keys, status_map)
      host.write_text(previous_path, text)
      continue
    }
    let configured_registry = if loaded.snapshot.config.publisher_registry !=
      "default" {
      Some(loaded.snapshot.config.publisher_registry)
    } else {
      None
    }
    let effective_registry = match options.registry {
      Some(reg) => Some(reg)
      None => configured_registry
    }
    let program = if ecosystem == "moonbit" {
      "moon"
    } else if ecosystem == "cargo" {
      "cargo"
    } else {
      package_manager_program(host, manager)
    }
    let args = if ecosystem == "moonbit" {
      ["publish"]
    } else if ecosystem == "cargo" {
      let base = ["publish", "--allow-dirty"]
      if effective_registry is Some(reg) {
        base.push("--registry")
        base.push(reg)
      }
      base
    } else {
      let base = ["publish", "--ignore-scripts"]
      if effective_registry is Some(reg) {
        base.push("--registry")
        base.push(reg)
      }
      if options.tag is Some(dist_tag) {
        base.push("--tag")
        base.push(dist_tag)
      }
      base
    }
    status_map[key] = {
      plan_id,
      unit_id,
      version,
      target: "source",
      registry,
      state: @model.Unknown,
      digest: None,
      external_id: None,
      message: Some("Publishing in progress"),
    }
    let (_, inflight_text) = persist_publish_state(
      plan_id, order_keys, status_map,
    )
    host.write_text(previous_path, inflight_text)
    let mut attempt = 0
    let mut published_ok = false
    while attempt < max_attempts && !published_ok {
      if attempt > 0 {
        let unit_name = units_map
          .get(unit_id)
          .map(u => u.native_name)
          .unwrap_or(unit_id)
        let probe = if use_command_publisher {
          let resp = command_publishers.execute(
            "command",
            "already-published",
            {
              "unitId": unit_id,
              "name": unit_name,
              "version": version,
              "ecosystem": ecosystem,
              "registry": registry,
            },
          ) catch {
            _ => Json::boolean(false)
          }
          match resp {
            { "published": True, .. } | True => "present"
            _ => "absent"
          }
        } else {
          registry_lookup(
            host, ecosystem, manager, unit_name, version, cwd, effective_registry,
          )
        }
        if probe == "present" {
          published_ok = true
          break
        }
      }
      if use_command_publisher {
        let unit_name = units_map
          .get(unit_id)
          .map(u => u.native_name)
          .unwrap_or(unit_id)
        let invoked = try {
          ignore(
            command_publishers.execute("command", "publish", {
              "unitId": unit_id,
              "name": unit_name,
              "version": version,
              "ecosystem": ecosystem,
              "registry": registry,
            }),
          )
          true
        } catch {
          _ => false
        }
        if invoked {
          published_ok = true
        }
      } else {
        let output = host.run(program, args, Some(cwd))
        if output.exit_code == 0 {
          published_ok = true
        }
      }
      attempt += 1
    }
    if published_ok {
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Published,
        digest: None,
        external_id: None,
        message: None,
      }
    } else {
      failed = true
      failed_units[unit_id] = true
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Unknown,
        digest: None,
        external_id: None,
        message: Some(
          "Publisher failed after invocation; verify registry state before retrying",
        ),
      }
    }
    let (_, updated_text) = persist_publish_state(
      plan_id, order_keys, status_map,
    )
    host.write_text(previous_path, updated_text)
  }
  let (final_statuses, final_text) = persist_publish_state(
    plan_id, order_keys, status_map,
  )
  host.write_text(previous_path, final_text)
  if !failed &&
    !options.no_tag &&
    !worktree_dirty &&
    loaded.snapshot.config.tag_after_publish &&
    loaded.snapshot.config.tag_create {
    ignore(
      create_tags_with(host, loaded, {
        dry_run: false,
        push: loaded.snapshot.config.tag_push,
        force: false,
        yes: options.yes,
        format: "",
      }),
    )
  }
  {
    schema_version: 1,
    plan_id,
    dry_run: false,
    complete: !failed,
    statuses: final_statuses,
    recovery_path: if failed {
      Some(".moonset/publish-state.json")
    } else {
      None
    },
  }
}

///|
pub async fn publish_release(
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  publish_release_with(native_host(), loaded, options)
}
