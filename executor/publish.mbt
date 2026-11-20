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
  if self.publishers.get(unit.ecosystem.text()) is Some(pub_impl) {
    return Some((unit.ecosystem.text(), pub_impl))
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
pub(all) struct PublishOptions {
  dry_run : Bool
  only : Array[String]
  registry : String?
  tag : String?
  otp : String?
  yes : Bool
  allow_uncommitted : Bool
  retry : Int32
  no_tag : Bool
  reconcile : Bool
  artifacts_dir : String?
  api_publishers : ApiPublisherRegistry?
}

///|
pub fn PublishOptions::new(
  dry_run~ : Bool = false,
  only~ : Array[String] = [],
  registry? : String,
  tag? : String,
  otp? : String,
  yes~ : Bool = false,
  allow_uncommitted~ : Bool = false,
  retry~ : Int32 = 0,
  no_tag~ : Bool = false,
  reconcile~ : Bool = false,
  artifacts_dir? : String,
  api_publishers? : ApiPublisherRegistry,
) -> PublishOptions {
  {
    dry_run,
    only,
    registry,
    tag,
    otp,
    yes,
    allow_uncommitted,
    retry,
    no_tag,
    reconcile,
    artifacts_dir,
    api_publishers,
  }
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
/// Build safe base environment for command publisher plugins without leaking unrelated secrets.
fn[H : ExecutionHost] build_command_publisher_env(
  host : H,
  token_env : String?,
) -> Map[String, String] {
  let env : Map[String, String] = Map([])
  for
    key in [
      "PATH", "SystemRoot", "HOME", "USERPROFILE", "PATHEXT", "TEMP", "TMP", "ComSpec",
      "COMSPEC",
    ] {
    if host.getenv(key) is Some(val) {
      env[key] = val
    }
  }
  if token_env is Some(token_var) {
    if host.getenv(token_var) is Some(val) {
      env[token_var] = val
    }
  }
  env
}

///|
/// Execute one JSONL command publisher request through `ExecutionHost` so it is
/// testable, auditable, and never bypasses the host boundary.
async fn[H : ExecutionHost] run_command_publisher(
  host : H,
  root : String,
  cmd : Array[String],
  env : Map[String, String],
  protocol_method : String,
  payload : Json,
) -> Json {
  let request : @adapters.JsonlRequest = {
    schema_version: 1,
    protocol_method,
    payload,
  }
  let stdin_text = request.to_json().stringify() + "\n"
  let output = host.run_with_env(
    cmd[0],
    cmd[1:].to_owned(),
    Some(root),
    env,
    Some(stdin_text),
    Some(30000),
  )
  if output.exit_code != 0 {
    raise invalid_error(
      "plugin-crashed",
      "Publisher command exited with code " +
      output.exit_code.to_string() +
      ": " +
      process_failure_detail(output),
    )
  }
  let lines = output.stdout
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.trim().to_owned())
    .filter(x => x != "")
    .collect()
  if lines.length() != 1 {
    raise invalid_error(
      "plugin-invalid-output", "Publisher command must return exactly one JSONL response",
    )
  }
  let parsed = @json.parse(lines[0]) catch {
    _ =>
      raise invalid_error(
        "plugin-invalid-output", "Publisher command output is not JSON",
      )
  }
  let response = @adapters.parse_response(parsed)
  if !response.ok {
    raise invalid_error(
      "plugin-request-failed",
      response.error.unwrap_or("Publisher command rejected request"),
    )
  }
  response.result
}

///|
fn infer_snapshot_dist_tag(version : String) -> String {
  match version.find("-") {
    Some(idx) => {
      let pre = version[idx + 1:].to_owned()
      let first = pre.split("-").collect()[0].to_owned()
      let is_all_digits = first != "" &&
        first.to_array().all(ch => ch >= '0' && ch <= '9')
      if first != "" && !is_all_digits {
        first
      } else {
        "snapshot"
      }
    }
    None => "snapshot"
  }
}

///|
fn build_command_payload(
  unit : @model.ReleaseUnit,
  version : String,
  registry : String,
  dist_tag : String?,
  access : @model.Access,
  archive_path : String?,
) -> Json {
  let payload : Map[String, Json] = Map([
    ("unitId", Json::string(unit.id)),
    ("name", Json::string(unit.native_name)),
    ("version", Json::string(version)),
    ("ecosystem", Json::string(unit.ecosystem.text())),
    ("registry", Json::string(registry)),
    ("access", Json::string(access.text())),
  ])
  if dist_tag is Some(dt) {
    payload["distTag"] = Json::string(dt)
  }
  if archive_path is Some(path) && path != "" {
    payload["archivePath"] = Json::string(path)
  }
  Json::object(payload)
}

///|
pub async fn[H : ExecutionHost] publish_release_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  let adapter_registry = @adapters.AdapterRegistry::with_builtins()
  let specs_by_unit = @engine.parse_artifact_specs(loaded.snapshot.config)
  let (release_state, _raw_state) = load_release_state(
    host,
    loaded.snapshot.root,
  )
  let plan_id = release_state.plan_fingerprint
  let units_map : Map[String, @model.ReleaseUnit] = Map([])
  for unit in loaded.snapshot.units {
    units_map[unit.id] = unit
  }
  let release_versions : Map[String, String] = Map([])
  let release_ids : Array[String] = []
  for rel in release_state.releases {
    if rel.publish {
      release_versions[rel.unit_id] = rel.new_version
      release_ids.push(rel.unit_id)
    }
  }
  // Load existing publish-state before resolving --only closure so retries after
  // upstream success are permitted!
  let status_map = load_publish_state(host, loaded.snapshot.root, plan_id)
  let selected_ids = resolve_only_selection(
    options.only,
    release_ids,
    release_versions,
    units_map,
    loaded,
    specs_by_unit,
    status_map,
  )
  let is_global_api = loaded.snapshot.config.publisher.kind == "api"
  if is_global_api && options.api_publishers is None {
    raise invalid_error(
      "unsupported-capability", "publisher.kind='api' requires PublishOptions.api_publishers",
    )
  }
  let use_command_publisher = loaded.snapshot.config.publisher.kind == "command"
  let cli_registry_map = @engine.parse_target_mapping(options.registry)
  let cli_tag_map = @engine.parse_target_mapping(options.tag)
  let cfg_registry_map = if loaded.snapshot.config.publisher.registry !=
    "default" {
    @engine.parse_target_mapping(
      Some(loaded.snapshot.config.publisher.registry),
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
  let command_cmd = loaded.snapshot.config.publisher.command
  if use_command_publisher && command_cmd.is_empty() {
    raise invalid_error(
      "invalid-config", "publisher.command must not be empty when publisher.kind='command'",
    )
  }
  let command_env = if use_command_publisher {
    build_command_publisher_env(
      host,
      loaded.snapshot.config.publisher.token_env,
    )
  } else {
    Map([])
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
  let should_verify_matrix = options.artifacts_dir is Some(_) ||
    (!specs_by_unit.is_empty() && !options.dry_run)
  let pack_state_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/pack-results.json",
  )
  let packed_by_unit : Map[String, Json] = Map([])
  let verified_archives : Map[String, String] = Map([])
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
  let selected_ecosystems : Array[@model.Ecosystem] = []
  let unit_api_map : Map[String, (String, ApiPublisher)] = Map([])
  let unit_registry_overrides : Map[String, String?] = Map([])
  let unit_tag_overrides : Map[String, String?] = Map([])
  let unit_access_map : Map[String, @model.Access] = Map([])
  for unit_id in selected_ids {
    if units_map.get(unit_id) is Some(unit) {
      let unit_override_pub = loaded.snapshot.config
        .unit_overrides()
        .get(unit.id)
        .bind(x => x.publisher)
      let resolved_api = match options.api_publishers {
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
      let target_ver = release_versions[unit_id]
      if unit.version != Some(target_ver) {
        raise invalid_error(
          "stale-release-state",
          "Current manifest version does not match release-state.json for " +
          unit.id,
          path=unit.manifest,
        )
      }
      if !should_verify_matrix &&
        packed_by_unit.get(unit_id) is Some(pack_entry) {
        match pack_entry {
          {
            "version": String(pack_ver),
            "verified": True,
            "archivePath": String(archive_path),
            ..
          } => {
            if pack_ver != target_ver {
              raise invalid_error(
                "stale-artifact",
                "Packed artifact version does not match release state for " +
                unit.id,
                path=pack_state_path,
              )
            }
            if archive_path != "" {
              let resolved_arch = if host.exists(archive_path) {
                archive_path
              } else {
                absolute_path(loaded.snapshot.root, archive_path)
              }
              if !host.exists(resolved_arch) {
                raise invalid_error(
                  "artifact-missing",
                  "Packed artifact is missing on disk: " + archive_path,
                  path=archive_path,
                )
              }
              if pack_entry is { "contentHash": String(ch), .. } &&
                ch.has_prefix("fnv1a64:") &&
                bytes_fingerprint(host.read_binary(resolved_arch)) != ch {
                raise invalid_error(
                  "stale-artifact",
                  "Packed artifact hash mismatch on disk for " + unit.id,
                  path=resolved_arch,
                )
              }
              verified_archives[unit.id] = resolved_arch
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
      if unit.visibility == @model.Private &&
        !loaded.snapshot.config.private_packages.publish {
        raise invalid_error(
          "private-policy",
          "Publishing private unit is disabled: " + unit.id,
          path=unit.manifest,
        )
      }
      if !selected_ecosystems.contains(unit.ecosystem) {
        selected_ecosystems.push(unit.ecosystem)
      }
      let cli_or_cfg_reg = match
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
      let reg_override = match cli_or_cfg_reg {
        Some(v) => Some(v)
        None => unit.publish_config.bind(pc => pc.registry)
      }
      let cli_tag = @engine.resolve_target_override(
        cli_tag_map,
        unit.id,
        unit.ecosystem,
      )
      // Automatically route npm prerelease/snapshot publishes to an explicit dist-tag
      // when the caller did not specify `--tag`, preventing accidental `latest` overwrite!
      let auto_tag = match cli_tag {
        Some(t) => Some(t)
        None =>
          if unit.ecosystem == @model.Npm {
            if release_state.is_snapshot {
              Some(infer_snapshot_dist_tag(target_ver))
            } else if loaded.pre is Some({ mode: @model.Pre, tag: pre_tag, .. }) &&
              target_ver.contains("-") {
              Some(pre_tag)
            } else {
              None
            }
          } else {
            None
          }
      }
      let eff_access = unit.publish_config
        .bind(pc => pc.access)
        .unwrap_or(loaded.snapshot.config.access)
      unit_registry_overrides[unit.id] = reg_override
      unit_tag_overrides[unit.id] = auto_tag
      unit_access_map[unit.id] = eff_access
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
        if unit.ecosystem == @model.MoonBit && reg_override is Some(_) {
          raise invalid_error(
            "unsupported-capability", "Mooncakes CLI does not support --registry overrides",
          )
        }
        if (unit.ecosystem == @model.MoonBit || unit.ecosystem == @model.Cargo) &&
          tag_override is Some(_) {
          raise invalid_error(
            "unsupported-capability", "Only npm/pnpm registries support --tag dist-tag overrides",
          )
        }
      }
    }
  }
  let artifact_blocked_messages : Map[String, String] = Map([])
  if should_verify_matrix {
    let report = verify_artifacts_with(
      host,
      loaded,
      artifacts_dir?=options.artifacts_dir,
    )
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
          if spec.required && spec.linked_package is Some(pkg) {
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
    loaded.snapshot.config.bridges(),
    specs_by_unit,
  )
  let order_keys = ordered_ids.map(id => {
    status_key(id, release_versions[id], "source")
  })
  let mut failed = false
  let failed_units : Map[String, Bool] = Map([])
  let to_publish : Array[
    (@model.ReleaseUnit, String, @model.PackageManager, String),
  ] = []
  let query_registry = async fn(
    unit : @model.ReleaseUnit,
    version : String,
    manager : @model.PackageManager,
    cwd : String,
    registry : String,
    reg_override : String?,
    tag_override : String?,
    access : @model.Access,
    archive : String?,
  ) -> RegistryLookup {
    match unit_api_map.get(unit.id) {
      Some((pub_name, api_pub)) => {
        let target = make_publish_target(
          unit.id,
          version,
          registry,
          pub_name,
          tag_override,
        )
        let present = (api_pub.already_published)(target) catch {
          err => return LookupUnknown(error_message(err))
        }
        if present {
          Present
        } else {
          Absent
        }
      }
      None =>
        if use_command_publisher {
          let payload = build_command_payload(
            unit, version, registry, tag_override, access, archive,
          )
          let resp = run_command_publisher(
            host,
            loaded.snapshot.root,
            command_cmd,
            command_env,
            "already-published",
            payload,
          ) catch {
            err => return LookupUnknown(error_message(err))
          }
          match resp {
            { "published": True, .. } | True => Present
            _ => Absent
          }
        } else {
          driver_registry_lookup(
            host, unit, manager, version, cwd, reg_override,
          )
        }
    }
  }
  for unit_id in ordered_ids {
    let version = release_versions[unit_id]
    let key = status_key(unit_id, version, "source")
    let unit_opt = units_map.get(unit_id)
    let unit_reg_override = unit_registry_overrides.get(unit_id).unwrap_or(None)
    let unit_tag_override = unit_tag_overrides.get(unit_id).unwrap_or(None)
    let unit_access = unit_access_map
      .get(unit_id)
      .unwrap_or(loaded.snapshot.config.access)
    let unit_archive = verified_archives.get(unit_id)
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
        if options.reconcile && unit_opt is Some(unit) {
          let unit_pub = loaded.snapshot.config
            .unit_overrides()
            .get(unit.id)
            .bind(x => x.publisher)
          let eff_mgr = match unit_pub {
            Some("npm") => @model.PackageManager::Npm
            Some("pnpm") => @model.PackageManager::Pnpm
            _ => manager_for_unit(loaded.snapshot, unit)
          }
          let cwd = absolute_path(loaded.snapshot.root, unit.root)
          match
            query_registry(
              unit, version, eff_mgr, cwd, registry, unit_reg_override, unit_tag_override,
              unit_access, unit_archive,
            ) {
            Present => {
              status_map[key] = {
                ..prev,
                state: @model.Published,
                message: Some("reconciled as already published"),
              }
              continue
            }
            Absent => ()
            LookupUnknown(detail) => {
              failed = true
              failed_units[unit_id] = true
              status_map[key] = {
                ..prev,
                state: @model.Blocked,
                message: Some(
                  "Reconcile could not determine registry state: " + detail,
                ),
              }
              continue
            }
          }
        } else {
          failed = true
          failed_units[unit_id] = true
          status_map[key] = {
            ..prev,
            state: @model.Blocked,
            message: Some(
              "Previous publish outcome is unknown; verify the registry or retry with --reconcile",
            ),
          }
          continue
        }
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
      loaded.snapshot.config.bridges(),
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
    let unit_publisher = loaded.snapshot.config
      .unit_overrides()
      .get(unit.id)
      .bind(x => x.publisher)
    let effective_manager = match unit_publisher {
      Some("npm") => @model.PackageManager::Npm
      Some("pnpm") => @model.PackageManager::Pnpm
      _ => manager_for_unit(loaded.snapshot, unit)
    }
    let cwd = absolute_path(loaded.snapshot.root, unit.root)
    match
      query_registry(
        unit, version, effective_manager, cwd, registry, unit_reg_override, unit_tag_override,
        unit_access, unit_archive,
      ) {
      Present => {
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
      LookupUnknown(detail) => {
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
            "Could not determine whether the package is already published: " +
            detail,
          ),
        }
        continue
      }
      Absent => ()
    }
    let mut ok = true
    let mut preflight_already_published = false
    let mut preflight_err_detail = "Registry preflight failed"
    if options.dry_run || loaded.snapshot.config.publisher.dry_run_first {
      match unit_api_map.get(unit.id) {
        Some((pub_name, api_pub)) => {
          let target = make_publish_target(
            unit.id,
            version,
            registry,
            pub_name,
            unit_tag_override,
          )
          (api_pub.preflight)(target) catch {
            err => {
              ok = false
              preflight_err_detail = error_message(err)
            }
          }
        }
        None =>
          if use_command_publisher {
            let payload = build_command_payload(
              unit, version, registry, unit_tag_override, unit_access, unit_archive,
            )
            ignore(
              run_command_publisher(
                host,
                loaded.snapshot.root,
                command_cmd,
                command_env,
                "preflight",
                payload,
              ),
            ) catch {
              err => {
                ok = false
                preflight_err_detail = error_message(err)
              }
            }
          } else {
            let (pf_ok, pf_dup, detail) = driver_preflight(
              host,
              unit,
              effective_manager,
              cwd,
              {
                registry: unit_reg_override,
                dist_tag: unit_tag_override,
                access: unit_access,
                otp: options.otp,
                archive_path: unit_archive,
              },
            )
            ok = pf_ok
            preflight_already_published = pf_dup
            if detail != "" {
              preflight_err_detail = detail
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
        Some(preflight_err_detail)
      },
    }
    if ok {
      to_publish.push((unit, version, effective_manager, cwd))
    }
  }
  // INVARIANT: `--dry-run` MUST NEVER write `.moonset/publish-state.json` or any workspace file!
  if options.dry_run {
    let (dry_statuses, _) = serialize_publish_state(
      plan_id, order_keys, status_map,
    )
    return {
      schema_version: 1,
      plan_id,
      dry_run: true,
      complete: false,
      statuses: dry_statuses,
      recovery_path: None,
    }
  }
  let preflight_statuses = save_publish_state(
    host,
    loaded.snapshot.root,
    plan_id,
    order_keys,
    status_map,
    "preflight",
  )
  if failed {
    return {
      schema_version: 1,
      plan_id,
      dry_run: false,
      complete: false,
      statuses: preflight_statuses,
      recovery_path: Some(".moonset/publish-state.json"),
    }
  }
  let max_attempts = if options.retry > 0 { options.retry + 1 } else { 1 }
  let published_unit_ids : Array[String] = []
  let mut step_idx = 0
  for item in to_publish {
    let (unit, version, manager, cwd) = item
    let unit_id = unit.id
    let key = status_key(unit_id, version, "source")
    let effective_registry = unit_registry_overrides
      .get(unit_id)
      .unwrap_or(None)
    let unit_tag_override = unit_tag_overrides.get(unit_id).unwrap_or(None)
    let unit_access = unit_access_map
      .get(unit_id)
      .unwrap_or(loaded.snapshot.config.access)
    let unit_archive = verified_archives.get(unit_id)
    let registry = effective_registry.unwrap_or(
      registry_for_ecosystem(unit.ecosystem),
    )
    let blocked_by = upstream_producers(
      unit_id,
      units_map,
      loaded.snapshot.config.bridges(),
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
      ignore(
        save_publish_state(
          host,
          loaded.snapshot.root,
          plan_id,
          order_keys,
          status_map,
          "blocked-" + step_idx.to_string(),
        ),
      )
      step_idx += 1
      continue
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
    ignore(
      save_publish_state(
        host,
        loaded.snapshot.root,
        plan_id,
        order_keys,
        status_map,
        "inflight-" + step_idx.to_string(),
      ),
    )
    let mut attempt = 0
    let mut published_ok = false
    let mut external_id : String? = None
    let mut digest : String? = None
    let mut last_error = ""
    while attempt < max_attempts && !published_ok {
      if attempt > 0 {
        host.sleep_ms(500 * attempt)
        match
          query_registry(
            unit, version, manager, cwd, registry, effective_registry, unit_tag_override,
            unit_access, unit_archive,
          ) {
          Present => {
            published_ok = true
            break
          }
          _ => ()
        }
      }
      match unit_api_map.get(unit_id) {
        Some((pub_name, api_pub)) => {
          let target = make_publish_target(
            unit_id, version, registry, pub_name, unit_tag_override,
          )
          try {
            let ext = (api_pub.publish)(target)
            published_ok = true
            if ext.trim() != "" {
              external_id = Some(ext.trim().to_owned())
            }
          } catch {
            err => last_error = error_message(err)
          }
        }
        None =>
          if use_command_publisher {
            let payload = build_command_payload(
              unit, version, registry, unit_tag_override, unit_access, unit_archive,
            )
            try {
              let resp = run_command_publisher(
                host,
                loaded.snapshot.root,
                command_cmd,
                command_env,
                "publish",
                payload,
              )
              published_ok = true
              if resp is { "externalId": String(ext), .. } && ext.trim() != "" {
                external_id = Some(ext.trim().to_owned())
              }
              if resp is { "digest": String(d), .. } && d.trim() != "" {
                digest = Some(d.trim().to_owned())
              }
            } catch {
              err => last_error = error_message(err)
            }
          } else {
            let (pub_ok, detail) = driver_publish(host, unit, manager, cwd, {
              registry: effective_registry,
              dist_tag: unit_tag_override,
              access: unit_access,
              otp: options.otp,
              archive_path: unit_archive,
            })
            if pub_ok {
              published_ok = true
            } else {
              last_error = detail
            }
          }
      }
      attempt += 1
    }
    if published_ok {
      published_unit_ids.push(unit_id)
      status_map[key] = {
        plan_id,
        unit_id,
        version,
        target: "source",
        registry,
        state: @model.Published,
        digest,
        external_id,
        message: None,
      }
    } else {
      failed = true
      failed_units[unit_id] = true
      let msg = if last_error != "" {
        last_error + " (verify registry state or retry with --reconcile)"
      } else {
        "Publisher failed after invocation; verify registry state or retry with --reconcile"
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
        message: Some(msg),
      }
    }
    ignore(
      save_publish_state(
        host,
        loaded.snapshot.root,
        plan_id,
        order_keys,
        status_map,
        "done-" + step_idx.to_string(),
      ),
    )
    step_idx += 1
  }
  let final_statuses = save_publish_state(
    host,
    loaded.snapshot.root,
    plan_id,
    order_keys,
    status_map,
    "final",
  )
  // Skip Git tags for snapshot releases; when `--only` was specified, only tag selected units.
  if !failed &&
    !release_state.is_snapshot &&
    !options.no_tag &&
    !worktree_dirty &&
    loaded.snapshot.config.tag.after_publish &&
    loaded.snapshot.config.tag.create {
    let tag_units = if options.only.is_empty() {
      []
    } else if !published_unit_ids.is_empty() {
      published_unit_ids
    } else {
      selected_ids
    }
    ignore(
      create_tags_with(
        host,
        loaded,
        TagOptions::new(
          dry_run=false,
          push=loaded.snapshot.config.tag.push,
          force=false,
          yes=options.yes,
          format="",
          only_units=tag_units,
        ),
      ),
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
