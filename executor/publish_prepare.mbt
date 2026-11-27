///|
priv struct PublishPlanContext {
  release_state : @model.ReleaseState
  plan_id : String
  specs_by_unit : Map[String, Array[@model.ArtifactTargetSpec]]
  units_map : Map[String, @model.ReleaseUnit]
  release_versions : Map[String, String]
  selected_ids : Array[String]
  ordered_ids : Array[String]
  order_keys : Array[String]
  status_map : Map[String, @model.PublishStatus]
  use_command_publisher : Bool
  command_cmd : Array[String]
  command_env : Map[String, String]
  worktree_dirty : Bool
  verified_archives : Map[String, String]
  unit_api_map : Map[String, (String, ApiPublisher)]
  unit_registry_overrides : Map[String, String?]
  unit_tag_overrides : Map[String, String?]
  unit_access_map : Map[String, @model.Access]
  artifact_blocked_messages : Map[String, String]
}

///|
priv struct PublishPreflightOutcome {
  failed : Bool
  failed_units : Map[String, Bool]
  to_publish : Array[
    (@model.ReleaseUnit, String, @model.PackageManager, String),
  ]
}

///|
fn resolve_unit_manager(
  loaded : @workspace.LoadedWorkspace,
  unit : @model.ReleaseUnit,
) -> @model.PackageManager {
  let unit_pub = loaded.snapshot.config
    .unit_overrides()
    .get(unit.id)
    .bind(x => x.publisher)
  match unit_pub {
    Some("npm") => @model.PackageManager::Npm
    Some("pnpm") => @model.PackageManager::Pnpm
    Some("yarn") => @model.PackageManager::Yarn
    _ => manager_for_unit(loaded.snapshot, unit)
  }
}

///|
async fn[H : ExecutionHost] prepare_publish_context(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> PublishPlanContext {
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
  // upstream success are permitted.
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
      if packed_by_unit.get(unit_id) is Some(pack_entry) {
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
      // when the caller did not specify `--tag`, preventing accidental `latest` overwrite.
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
      let eff_access = match options.access {
        Some(cli_acc) => cli_acc
        None =>
          unit.publish_config
          .bind(pc => pc.access)
          .unwrap_or(loaded.snapshot.config.access)
      }
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
            "unsupported-capability", "Only npm/pnpm/yarn registries support --tag dist-tag overrides",
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
  {
    release_state,
    plan_id,
    specs_by_unit,
    units_map,
    release_versions,
    selected_ids,
    ordered_ids,
    order_keys,
    status_map,
    use_command_publisher,
    command_cmd,
    command_env,
    worktree_dirty,
    verified_archives,
    unit_api_map,
    unit_registry_overrides,
    unit_tag_overrides,
    unit_access_map,
    artifact_blocked_messages,
  }
}

///|
async fn[H : ExecutionHost] run_publish_preflight(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  ctx : PublishPlanContext,
) -> PublishPreflightOutcome {
  let mut failed = false
  let failed_units : Map[String, Bool] = Map([])
  let to_publish : Array[
    (@model.ReleaseUnit, String, @model.PackageManager, String),
  ] = []
  for unit_id in ctx.ordered_ids {
    let version = ctx.release_versions[unit_id]
    let key = status_key(unit_id, version, "source")
    let unit_opt = ctx.units_map.get(unit_id)
    let unit_reg_override = ctx.unit_registry_overrides
      .get(unit_id)
      .unwrap_or(None)
    let unit_tag_override = ctx.unit_tag_overrides.get(unit_id).unwrap_or(None)
    let unit_access = ctx.unit_access_map
      .get(unit_id)
      .unwrap_or(loaded.snapshot.config.access)
    let unit_archive = ctx.verified_archives.get(unit_id)
    let registry = match unit_opt {
      Some(unit) =>
        unit_reg_override.unwrap_or(registry_for_ecosystem(unit.ecosystem))
      None => "unknown"
    }
    if ctx.status_map.get(key) is Some(prev) {
      if prev.state == @model.Published {
        continue
      }
      if prev.state == @model.Unknown {
        if options.reconcile && unit_opt is Some(unit) {
          let eff_mgr = resolve_unit_manager(loaded, unit)
          let cwd = absolute_path(loaded.snapshot.root, unit.root)
          match
            query_unit_registry(
              host, loaded, ctx, unit, version, eff_mgr, cwd, registry, unit_reg_override,
              unit_tag_override, unit_access, unit_archive,
            ) {
            Present => {
              ctx.status_map[key] = {
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
              ctx.status_map[key] = {
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
          ctx.status_map[key] = {
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
    if ctx.artifact_blocked_messages.get(unit_id) is Some(block_msg) {
      failed = true
      failed_units[unit_id] = true
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
      ctx.units_map,
      loaded.snapshot.config.bridges(),
      ctx.specs_by_unit,
    ).filter(p => failed_units.contains(p))
    if !blocked_by.is_empty() {
      failed = true
      failed_units[unit_id] = true
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
    let effective_manager = resolve_unit_manager(loaded, unit)
    let cwd = absolute_path(loaded.snapshot.root, unit.root)
    match
      query_unit_registry(
        host, loaded, ctx, unit, version, effective_manager, cwd, registry, unit_reg_override,
        unit_tag_override, unit_access, unit_archive,
      ) {
      Present => {
        ctx.status_map[key] = {
          plan_id: ctx.plan_id,
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
        ctx.status_map[key] = {
          plan_id: ctx.plan_id,
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
      match ctx.unit_api_map.get(unit.id) {
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
          if ctx.use_command_publisher {
            let payload = build_command_payload(
              unit, version, registry, unit_tag_override, unit_access, unit_archive,
            )
            ignore(
              run_command_publisher(
                host,
                loaded.snapshot.root,
                ctx.command_cmd,
                ctx.command_env,
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
                ignore_scripts: options.ignore_scripts,
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
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
    ctx.status_map[key] = {
      plan_id: ctx.plan_id,
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
  { failed, failed_units, to_publish, }
}
