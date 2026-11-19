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
    let output = host.run(
      "moon",
      ["view", name + "@" + version, "--json"],
      Some(cwd),
    )
    let raw = output.stdout.trim().to_owned()
    if raw == "" {
      // Compatibility fallback for stubbed test hosts returning empty output.
      return if output.exit_code == 0 { "absent" } else { "unknown" }
    }
    let parsed = @json.parse(raw) catch { _ => Json::null() }
    match parsed {
      { "status": "success", "result": Object(_), .. } => return "present"
      { "status": "failure", .. } => {
        let lower = (raw + "\n" + output.stderr).to_lower()
        if lower.contains("404") || lower.contains("not found") {
          return "absent"
        }
        return "unknown"
      }
      _ => {
        let lower = (raw + "\n" + output.stderr).to_lower()
        if lower.contains("404") || lower.contains("not found") {
          return "absent"
        }
        return "unknown"
      }
    }
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
  specs_by_unit : Map[String, Array[@engine.ArtifactTargetSpec]],
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
      if bridge.consumer == id &&
        bridge.wait_for == "publish" &&
        release_ids.contains(bridge.producer) {
        visit(bridge.producer)
      }
    }
    for spec in specs_by_unit.get(id).unwrap_or([]) {
      if spec.required &&
        spec.package_unit_id is Some(pkg) &&
        pkg != id &&
        release_ids.contains(pkg) {
        visit(pkg)
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
  specs_by_unit : Map[String, Array[@engine.ArtifactTargetSpec]],
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
    if bridge.consumer == unit_id &&
      bridge.wait_for == "publish" &&
      !producers.contains(bridge.producer) {
      producers.push(bridge.producer)
    }
  }
  for spec in specs_by_unit.get(unit_id).unwrap_or([]) {
    if spec.required &&
      spec.package_unit_id is Some(pkg) &&
      pkg != unit_id &&
      !producers.contains(pkg) {
      producers.push(pkg)
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
/// Programmatic publisher implementation registered for `publisher.kind = "api"`
/// or per-unit custom publisher routing.
pub(all) struct ApiPublisher {
  already_published : (@model.PublishTarget) -> Bool raise @model.MoonsetError
  preflight : (@model.PublishTarget) -> Unit raise @model.MoonsetError
  publish : (@model.PublishTarget) -> String raise @model.MoonsetError
}

///|
/// Construct an `ApiPublisher` from an injectable `@adapters.RegistryHost`.
pub fn ApiPublisher::from_registry_host(
  host : @adapters.RegistryHost,
) -> ApiPublisher {
  {
    already_published: target => {
      (host.already_published)(target.unit_id, target.version, target.registry)
    },
    preflight: target => {
      (host.preflight)(target.unit_id, target.version, target.registry)
    },
    publish: target => {
      (host.publish)(target.unit_id, target.version, target.registry)
    },
  }
}

///|
/// Registry of programmatic API publishers keyed by custom publisher name,
/// canonical UnitId, ecosystem name, or `"default"`/`"api"`.
pub(all) struct ApiPublisherRegistry {
  publishers : Map[String, ApiPublisher]
}

///|
pub fn ApiPublisherRegistry::new() -> ApiPublisherRegistry {
  { publishers: Map([]), }
}

///|
pub fn ApiPublisherRegistry::register(
  self : ApiPublisherRegistry,
  name : String,
  publisher : ApiPublisher,
) -> Unit {
  self.publishers[name] = publisher
}

///|
pub fn[P : @adapters.PublisherPort] ApiPublisherRegistry::register_port(
  self : ApiPublisherRegistry,
  name : String,
  port : P,
) -> Unit {
  self.publishers[name] = {
    already_published: target => port.already_published(target),
    preflight: target => port.preflight(target),
    publish: target => port.publish(target),
  }
}

///|
fn ApiPublisherRegistry::resolve(
  self : ApiPublisherRegistry,
  unit : @model.ReleaseUnit,
  unit_override_publisher : String?,
  is_global_api : Bool,
) -> (String, ApiPublisher)? {
  if unit_override_publisher is Some(name) {
    if self.publishers.get(name) is Some(pub_impl) {
      return Some((name, pub_impl))
    }
  }
  if self.publishers.get(unit.id) is Some(pub_impl) {
    return Some((unit.id, pub_impl))
  }
  if self.publishers.get(unit.ecosystem) is Some(pub_impl) {
    return Some((unit.ecosystem, pub_impl))
  }
  if is_global_api {
    if self.publishers.get("default") is Some(pub_impl) {
      return Some(("default", pub_impl))
    }
    if self.publishers.get("api") is Some(pub_impl) {
      return Some(("api", pub_impl))
    }
  }
  None
}

///|
fn make_publish_target(
  unit_id : String,
  version : String,
  registry : String,
  publisher : String,
  dist_tag : String?,
) -> @model.PublishTarget {
  let target = match dist_tag {
    Some(tag) if tag != "" => "dist-tag:" + tag
    _ => "source"
  }
  {
    unit_id,
    version,
    target,
    registry,
    publisher,
    artifact_id: None,
    required: true,
  }
}

///|
async fn[H : ExecutionHost] publish_release_core(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  artifacts_dir : String?,
  api_publishers : ApiPublisherRegistry?,
) -> @model.PublishResult {
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
  let specs_by_unit = @engine.parse_artifact_specs(loaded.snapshot.config)
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
  let resolved_fixed = @engine.resolve_unit_groups(
    loaded.snapshot.config.fixed,
    loaded.snapshot.units,
  )
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
    for group in resolved_fixed {
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
          specs_by_unit,
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
  let is_global_api = loaded.snapshot.config.publisher_kind == "api"
  if is_global_api && api_publishers is None {
    raise invalid_error(
      "unsupported-capability", "publisher.kind='api' must be invoked programmatically through publish_release_with_api",
    )
  }
  let use_command_publisher = loaded.snapshot.config.publisher_kind == "command"
  let cli_registry_map = @engine.parse_target_mapping(options.registry)
  let cli_tag_map = @engine.parse_target_mapping(options.tag)
  let cfg_registry_map = if loaded.snapshot.config.publisher_registry !=
    "default" {
    @engine.parse_target_mapping(
      Some(loaded.snapshot.config.publisher_registry),
    )
  } else {
    @engine.parse_target_mapping(None)
  }
  for uid, _ in cli_registry_map.by_unit {
    if !units_map.contains(uid) {
      raise invalid_error(
        "unknown-unit",
        "--registry references an unknown unit: " + uid,
      )
    }
  }
  for uid, _ in cli_tag_map.by_unit {
    if !units_map.contains(uid) {
      raise invalid_error(
        "unknown-unit",
        "--tag references an unknown unit: " + uid,
      )
    }
  }
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
    worktree_dirty = dirty.exit_code == 0 &&
      has_dirty_worktree_changes(dirty.stdout)
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
  let should_verify_matrix = artifacts_dir is Some(_) ||
    (!specs_by_unit.is_empty() && !options.dry_run)
  let pack_state_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/pack-results.json",
  )
  let packed_by_unit : Map[String, Json] = Map([])
  if !should_verify_matrix && host.exists(pack_state_path) {
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
  let unit_api_map : Map[String, (String, ApiPublisher)] = Map([])
  let unit_registry_overrides : Map[String, String?] = Map([])
  let unit_tag_overrides : Map[String, String?] = Map([])
  for unit_id in selected_ids {
    if units_map.get(unit_id) is Some(unit) {
      let unit_override_pub = loaded.snapshot.config.unit_overrides
        .get(unit.id)
        .bind(x => x.publisher)
      let resolved_api = match api_publishers {
        Some(reg) => reg.resolve(unit, unit_override_pub, is_global_api)
        None => None
      }
      if is_global_api && resolved_api is None {
        raise invalid_error(
          "unsupported-capability",
          "No API publisher registered for unit " + unit.id,
        )
      }
      if resolved_api is Some(pair) {
        unit_api_map[unit.id] = pair
      } else if !use_command_publisher {
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
      let reg_override = match
        @engine.resolve_target_override(
          cli_registry_map,
          unit.id,
          unit.ecosystem,
        ) {
        Some(v) => Some(v)
        None =>
          @engine.resolve_target_override(
            cfg_registry_map,
            unit.id,
            unit.ecosystem,
          )
      }
      let tag_override = @engine.resolve_target_override(
        cli_tag_map,
        unit.id,
        unit.ecosystem,
      )
      unit_registry_overrides[unit.id] = reg_override
      unit_tag_overrides[unit.id] = tag_override
    }
  }
  if selected_ecosystems.length() > 1 &&
    !use_command_publisher &&
    !is_global_api &&
    (cli_registry_map.global is Some(_) || cli_tag_map.global is Some(_)) {
    raise invalid_error(
      "unsupported-capability", "--registry and --tag overrides cannot be applied across mixed ecosystems; use scoped syntax like npm=<value>,cargo=<value>",
    )
  }
  for unit_id in selected_ids {
    if units_map.get(unit_id) is Some(unit) {
      let has_custom = use_command_publisher || unit_api_map.contains(unit.id)
      if !has_custom {
        let reg_override = unit_registry_overrides.get(unit.id).unwrap_or(None)
        let tag_override = unit_tag_overrides.get(unit.id).unwrap_or(None)
        if unit.ecosystem == "moonbit" && reg_override is Some(_) {
          raise invalid_error(
            "unsupported-capability", "Mooncakes CLI does not support --registry overrides",
          )
        }
        if (unit.ecosystem == "moonbit" || unit.ecosystem == "cargo") &&
          tag_override is Some(_) {
          raise invalid_error(
            "unsupported-capability", "Only npm/pnpm registries support --tag dist-tag overrides",
          )
        }
      }
    }
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
  let artifact_blocked_messages : Map[String, String] = Map([])
  if should_verify_matrix {
    let report = verify_artifacts_with(host, loaded, artifacts_dir?)
    for issue in report.issues {
      if issue.blocking && !artifact_blocked_messages.contains(issue.unit_id) {
        artifact_blocked_messages[issue.unit_id] = issue.message
      }
    }
    for blocked_uid in report.blocked_units {
      if !artifact_blocked_messages.contains(blocked_uid) {
        let mut msg = "Required platform artifact verification failed for " +
          blocked_uid
        for spec in specs_by_unit.get(blocked_uid).unwrap_or([]) {
          if spec.required && spec.package_unit_id is Some(pkg) {
            if artifact_blocked_messages.get(pkg) is Some(sub_msg) {
              msg = "Blocked by artifact verification failure: " + sub_msg
              break
            }
          }
        }
        artifact_blocked_messages[blocked_uid] = msg
      }
    }
  }
  let ordered_ids = topological_release_order(
    selected_ids,
    units_map,
    loaded.snapshot.config.bridges,
    specs_by_unit,
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
    let unit_reg_override = unit_registry_overrides.get(unit_id).unwrap_or(None)
    let unit_tag_override = unit_tag_overrides.get(unit_id).unwrap_or(None)
    let registry = match unit_opt {
      Some(unit) =>
        unit_reg_override.unwrap_or(registry_for_ecosystem(unit.ecosystem))
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
    if artifact_blocked_messages.get(unit_id) is Some(block_msg) {
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
        message: Some(block_msg),
      }
      continue
    }
    let blocked_by = upstream_producers(
      unit_id,
      units_map,
      loaded.snapshot.config.bridges,
      specs_by_unit,
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
    let effective_registry = unit_reg_override
    let unit_publisher = loaded.snapshot.config.unit_overrides
      .get(unit.id)
      .bind(x => x.publisher)
    let effective_manager = match unit_publisher {
      Some("npm" | "pnpm" as mgr) => mgr
      _ => manager_for_unit(loaded.snapshot, unit)
    }
    let cwd = absolute_path(loaded.snapshot.root, unit.root)
    let unit_api_opt = unit_api_map.get(unit.id)
    let registry_state = match unit_api_opt {
      Some((pub_name, api_pub)) => {
        let target = make_publish_target(
          unit.id,
          version,
          registry,
          pub_name,
          unit_tag_override,
        )
        let present = (api_pub.already_published)(target) catch { _ => false }
        if present {
          "present"
        } else {
          "absent"
        }
      }
      None =>
        if use_command_publisher {
          let payload : Map[String, Json] = Map([
            ("unitId", Json::string(unit.id)),
            ("name", Json::string(unit.native_name)),
            ("version", Json::string(version)),
            ("ecosystem", Json::string(unit.ecosystem)),
            ("registry", Json::string(registry)),
          ])
          if unit_tag_override is Some(dt) {
            payload["distTag"] = Json::string(dt)
          }
          let resp = command_publishers.execute(
            "command",
            "already-published",
            Json::object(payload),
          )
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
    let mut preflight_already_published = false
    if options.dry_run || loaded.snapshot.config.publisher_dry_run_first {
      match unit_api_opt {
        Some((pub_name, api_pub)) => {
          let target = make_publish_target(
            unit.id,
            version,
            registry,
            pub_name,
            unit_tag_override,
          )
          let preflight_ok = try {
            (api_pub.preflight)(target)
            true
          } catch {
            _ => false
          }
          ok = preflight_ok
        }
        None =>
          if use_command_publisher {
            let payload : Map[String, Json] = Map([
              ("unitId", Json::string(unit.id)),
              ("name", Json::string(unit.native_name)),
              ("version", Json::string(version)),
              ("ecosystem", Json::string(unit.ecosystem)),
              ("registry", Json::string(registry)),
            ])
            if unit_tag_override is Some(dt) {
              payload["distTag"] = Json::string(dt)
            }
            let preflight_ok = try {
              ignore(
                command_publishers.execute(
                  "command",
                  "preflight",
                  Json::object(payload),
                ),
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
              if unit_tag_override is Some(dist_tag) {
                args.push("--tag")
                args.push(dist_tag)
              }
              args
            }
            let preflight = host.run(program, preflight_args, Some(cwd))
            ok = preflight.exit_code == 0
            if !ok && unit.ecosystem == "moonbit" {
              let combined = preflight.stdout + "\n" + preflight.stderr
              if combined.contains("409 Conflict") ||
                combined.contains("duplicated with an existing version") {
                preflight_already_published = true
              }
            }
          }
      }
    }
    if preflight_already_published {
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
    let effective_registry = unit_registry_overrides
      .get(unit_id)
      .unwrap_or(None)
    let unit_tag_override = unit_tag_overrides.get(unit_id).unwrap_or(None)
    let registry = effective_registry.unwrap_or(
      registry_for_ecosystem(ecosystem),
    )
    let unit_api_opt = unit_api_map.get(unit_id)
    let blocked_by = upstream_producers(
      unit_id,
      units_map,
      loaded.snapshot.config.bridges,
      specs_by_unit,
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
      if unit_tag_override is Some(dist_tag) {
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
    let mut external_id : String? = None
    while attempt < max_attempts && !published_ok {
      if attempt > 0 {
        let unit_name = units_map
          .get(unit_id)
          .map(u => u.native_name)
          .unwrap_or(unit_id)
        let probe = match unit_api_opt {
          Some((pub_name, api_pub)) => {
            let target = make_publish_target(
              unit_id, version, registry, pub_name, unit_tag_override,
            )
            let present = (api_pub.already_published)(target) catch {
              _ => false
            }
            if present {
              "present"
            } else {
              "absent"
            }
          }
          None =>
            if use_command_publisher {
              let payload : Map[String, Json] = Map([
                ("unitId", Json::string(unit_id)),
                ("name", Json::string(unit_name)),
                ("version", Json::string(version)),
                ("ecosystem", Json::string(ecosystem)),
                ("registry", Json::string(registry)),
              ])
              if unit_tag_override is Some(dt) {
                payload["distTag"] = Json::string(dt)
              }
              let resp = command_publishers.execute(
                "command",
                "already-published",
                Json::object(payload),
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
        }
        if probe == "present" {
          published_ok = true
          break
        }
      }
      match unit_api_opt {
        Some((pub_name, api_pub)) => {
          let target = make_publish_target(
            unit_id, version, registry, pub_name, unit_tag_override,
          )
          let ext_opt = Some((api_pub.publish)(target)) catch { _ => None }
          if ext_opt is Some(ext) {
            published_ok = true
            if ext.trim() != "" {
              external_id = Some(ext)
            }
          }
        }
        None =>
          if use_command_publisher {
            let unit_name = units_map
              .get(unit_id)
              .map(u => u.native_name)
              .unwrap_or(unit_id)
            let payload : Map[String, Json] = Map([
              ("unitId", Json::string(unit_id)),
              ("name", Json::string(unit_name)),
              ("version", Json::string(version)),
              ("ecosystem", Json::string(ecosystem)),
              ("registry", Json::string(registry)),
            ])
            if unit_tag_override is Some(dt) {
              payload["distTag"] = Json::string(dt)
            }
            let invoked = try {
              ignore(
                command_publishers.execute(
                  "command",
                  "publish",
                  Json::object(payload),
                ),
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
        external_id,
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
pub async fn[H : ExecutionHost] publish_release_with_api_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  api_publishers : ApiPublisherRegistry,
  artifacts_dir? : String,
) -> @model.PublishResult {
  publish_release_core(
    host,
    loaded,
    options,
    artifacts_dir,
    Some(api_publishers),
  )
}

///|
pub async fn publish_release_with_api(
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  api_publishers : ApiPublisherRegistry,
  artifacts_dir? : String,
) -> @model.PublishResult {
  publish_release_with_api_with(
    native_host(),
    loaded,
    options,
    api_publishers,
    artifacts_dir?,
  )
}

///|
pub async fn[H : ExecutionHost] publish_release_with_artifacts_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  artifacts_dir? : String,
) -> @model.PublishResult {
  publish_release_core(host, loaded, options, artifacts_dir, None)
}

///|
pub async fn publish_release_with_artifacts(
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  artifacts_dir? : String,
) -> @model.PublishResult {
  publish_release_with_artifacts_with(
    native_host(),
    loaded,
    options,
    artifacts_dir?,
  )
}

///|
pub async fn[H : ExecutionHost] publish_release_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  publish_release_with_artifacts_with(host, loaded, options)
}

///|
pub async fn publish_release(
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  publish_release_with(native_host(), loaded, options)
}
