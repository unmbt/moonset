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
fn[H : ExecutionHost] verify_command_publisher_allowlist(
  host : H,
  program : String,
) -> Unit raise @model.MoonsetError {
  if program.trim() == "" {
    raise invalid_error(
      "plugin-permission-denied", "Command publisher executable cannot be empty",
    )
  }
  match host.getenv("MOONSET_ALLOWED_PLUGIN_PROGRAMS") {
    Some(raw) => {
      let allowed : Array[String] = []
      for item in raw.split(",") {
        let trimmed = item.trim().to_owned()
        if trimmed != "" {
          allowed.push(trimmed)
        }
      }
      if !allowed.contains(program) {
        raise invalid_error(
          "plugin-permission-denied",
          "Command publisher executable is not allowed by host allowlist: " +
          program,
        )
      }
    }
    None => ()
  }
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
  verify_command_publisher_allowlist(host, cmd[0])
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
async fn[H : ExecutionHost] query_unit_registry(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  ctx : PublishPlanContext,
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
  match ctx.unit_api_map.get(unit.id) {
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
      if ctx.use_command_publisher {
        let payload = build_command_payload(
          unit, version, registry, tag_override, access, archive,
        )
        let resp = run_command_publisher(
          host,
          loaded.snapshot.root,
          ctx.command_cmd,
          ctx.command_env,
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
        driver_registry_lookup(host, unit, manager, version, cwd, reg_override)
      }
  }
}

///|
/// Wait briefly for newly published same-batch MoonBit upstreams to become
/// visible on mooncakes and refresh the local registry index via `moon update`
/// so isolated `moon publish --dry-run` / `moon publish` checks can resolve them.
async fn[H : ExecutionHost] sync_moonbit_upstream_registry(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  ctx : PublishPlanContext,
  unit : @model.ReleaseUnit,
  cwd : String,
  unsynced_moonbit : Map[String, (@model.ReleaseUnit, String, String)],
) -> Bool {
  if unit.ecosystem != @model.MoonBit ||
    ctx.use_command_publisher ||
    ctx.unit_api_map.contains(unit.id) {
    return false
  }
  let upstreams = upstream_producers(
    unit.id,
    ctx.units_map,
    loaded.snapshot.config.bridges(),
    ctx.specs_by_unit,
  )
  let pending_ids : Array[String] = []
  for dep_id in upstreams {
    if unsynced_moonbit.contains(dep_id) {
      pending_ids.push(dep_id)
    }
  }
  if pending_ids.is_empty() {
    return false
  }
  let max_polls = 6
  for dep_id in pending_ids {
    if unsynced_moonbit.get(dep_id) is Some((dep_unit, dep_ver, dep_cwd)) {
      let dep_mgr = resolve_unit_manager(loaded, dep_unit)
      let mut poll = 0
      while poll < max_polls {
        if poll > 0 {
          host.sleep_ms(1000 * poll)
        }
        match
          driver_registry_lookup(
            host,
            dep_unit,
            dep_mgr,
            dep_ver,
            dep_cwd,
            None,
          ) {
          Present => break
          Absent | LookupUnknown(_) => poll += 1
        }
      }
    }
  }
  driver_refresh_moonbit_registry(host, cwd)
  for dep_id in pending_ids {
    ignore(unsynced_moonbit.remove(dep_id))
  }
  true
}

///|
async fn[H : ExecutionHost] execute_publish_units(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
  ctx : PublishPlanContext,
  preflight : PublishPreflightOutcome,
) -> (Bool, Array[String]) {
  let max_attempts = if options.retry > 0 { options.retry + 1 } else { 1 }
  let published_unit_ids : Array[String] = []
  let failed_units = preflight.failed_units
  let unsynced_moonbit : Map[String, (@model.ReleaseUnit, String, String)] = Map([],
  )
  let same_batch_published_moonbit : Map[String, Bool] = Map([])
  let mut failed = preflight.failed
  let mut step_idx = 0
  for item in preflight.to_publish {
    let (unit, version, manager, cwd) = item
    let unit_id = unit.id
    let key = status_key(unit_id, version, "source")
    let effective_registry = ctx.unit_registry_overrides
      .get(unit_id)
      .unwrap_or(None)
    let unit_tag_override = ctx.unit_tag_overrides.get(unit_id).unwrap_or(None)
    let unit_access = ctx.unit_access_map
      .get(unit_id)
      .unwrap_or(loaded.snapshot.config.access)
    let unit_archive = ctx.verified_archives.get(unit_id)
    let registry = effective_registry.unwrap_or(
      registry_for_ecosystem(unit.ecosystem),
    )
    let upstreams = upstream_producers(
      unit_id,
      ctx.units_map,
      loaded.snapshot.config.bridges(),
      ctx.specs_by_unit,
    )
    let blocked_by = upstreams.filter(p => failed_units.contains(p))
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
      ignore(
        save_publish_state(
          host,
          loaded.snapshot.root,
          ctx.plan_id,
          ctx.order_keys,
          ctx.status_map,
          "blocked-" + step_idx.to_string(),
        ),
      )
      step_idx += 1
      continue
    }
    let has_same_batch_moonbit_upstream = unit.ecosystem == @model.MoonBit &&
      !ctx.use_command_publisher &&
      !ctx.unit_api_map.contains(unit_id) &&
      upstreams.any(p => same_batch_published_moonbit.contains(p))
    ignore(
      sync_moonbit_upstream_registry(
        host, loaded, ctx, unit, cwd, unsynced_moonbit,
      ),
    )
    if preflight.deferred_preflight.contains(unit_id) &&
      loaded.snapshot.config.publisher.dry_run_first {
      let max_pf_attempts = if has_same_batch_moonbit_upstream {
        if max_attempts > 5 {
          max_attempts
        } else {
          5
        }
      } else {
        1
      }
      let mut pf_attempt = 0
      let mut pf_ok = false
      let mut pf_dup = false
      let mut pf_detail = ""
      while pf_attempt < max_pf_attempts {
        if pf_attempt > 0 {
          host.sleep_ms(2000 * pf_attempt)
          driver_refresh_moonbit_registry(host, cwd)
        }
        let (ok_i, dup_i, detail_i) = preflight_single_unit(
          host, loaded, options, ctx, unit, version, manager, cwd, registry, effective_registry,
          unit_tag_override, unit_access, unit_archive,
        )
        pf_ok = ok_i
        pf_dup = dup_i
        pf_detail = detail_i
        if pf_ok ||
          pf_dup ||
          !has_same_batch_moonbit_upstream ||
          !is_moonbit_registry_propagation_error(pf_detail) {
          break
        }
        pf_attempt += 1
      }
      if pf_dup {
        published_unit_ids.push(unit_id)
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
        ignore(
          save_publish_state(
            host,
            loaded.snapshot.root,
            ctx.plan_id,
            ctx.order_keys,
            ctx.status_map,
            "done-" + step_idx.to_string(),
          ),
        )
        step_idx += 1
        continue
      }
      if !pf_ok {
        failed = true
        failed_units[unit_id] = true
        ctx.status_map[key] = {
          plan_id: ctx.plan_id,
          unit_id,
          version,
          target: "source",
          registry,
          state: @model.Failed,
          digest: None,
          external_id: None,
          message: Some(pf_detail),
        }
        ignore(
          save_publish_state(
            host,
            loaded.snapshot.root,
            ctx.plan_id,
            ctx.order_keys,
            ctx.status_map,
            "failed-preflight-" + step_idx.to_string(),
          ),
        )
        step_idx += 1
        continue
      }
    }
    ctx.status_map[key] = {
      plan_id: ctx.plan_id,
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
        ctx.plan_id,
        ctx.order_keys,
        ctx.status_map,
        "inflight-" + step_idx.to_string(),
      ),
    )
    let mut attempt = 0
    let mut propagation_retries = 0
    let max_propagation_retries = if has_same_batch_moonbit_upstream {
      4
    } else {
      0
    }
    let mut published_ok = false
    let mut external_id : String? = None
    let mut digest : String? = None
    let mut last_error = ""
    while (
            attempt < max_attempts ||
            propagation_retries < max_propagation_retries
          ) &&
          !published_ok {
      if attempt > 0 || propagation_retries > 0 {
        if propagation_retries > 0 &&
          is_moonbit_registry_propagation_error(last_error) {
          host.sleep_ms(2000 * propagation_retries)
          driver_refresh_moonbit_registry(host, cwd)
        } else {
          host.sleep_ms(500 * attempt)
        }
        match
          query_unit_registry(
            host, loaded, ctx, unit, version, manager, cwd, registry, effective_registry,
            unit_tag_override, unit_access, unit_archive,
          ) {
          Present => {
            published_ok = true
            break
          }
          _ => ()
        }
      }
      match ctx.unit_api_map.get(unit_id) {
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
          if ctx.use_command_publisher {
            let payload = build_command_payload(
              unit, version, registry, unit_tag_override, unit_access, unit_archive,
            )
            try {
              let resp = run_command_publisher(
                host,
                loaded.snapshot.root,
                ctx.command_cmd,
                ctx.command_env,
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
              ignore_scripts: options.ignore_scripts,
            })
            if pub_ok {
              published_ok = true
            } else {
              last_error = detail
            }
          }
      }
      if !published_ok {
        if has_same_batch_moonbit_upstream &&
          is_moonbit_registry_propagation_error(last_error) &&
          propagation_retries < max_propagation_retries {
          propagation_retries += 1
        } else {
          attempt += 1
          if attempt >= max_attempts {
            break
          }
        }
      }
    }
    if published_ok {
      published_unit_ids.push(unit_id)
      if unit.ecosystem == @model.MoonBit &&
        !ctx.use_command_publisher &&
        !ctx.unit_api_map.contains(unit_id) {
        unsynced_moonbit[unit_id] = (unit, version, cwd)
        same_batch_published_moonbit[unit_id] = true
      }
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
      ctx.status_map[key] = {
        plan_id: ctx.plan_id,
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
        ctx.plan_id,
        ctx.order_keys,
        ctx.status_map,
        "done-" + step_idx.to_string(),
      ),
    )
    step_idx += 1
  }
  (failed, published_unit_ids)
}
