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
  access : @model.Access?
  ignore_scripts : Bool
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
  access? : @model.Access,
  ignore_scripts~ : Bool = false,
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
    access,
    ignore_scripts,
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
pub async fn[H : ExecutionHost] publish_release_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : PublishOptions,
) -> @model.PublishResult {
  let ctx = prepare_publish_context(host, loaded, options)
  let preflight = run_publish_preflight(host, loaded, options, ctx)
  // INVARIANT: `--dry-run` MUST NEVER write `.moonset/publish-state.json` or any workspace file!
  if options.dry_run {
    let (dry_statuses, _) = serialize_publish_state(
      ctx.plan_id,
      ctx.order_keys,
      ctx.status_map,
    )
    return {
      schema_version: 1,
      plan_id: ctx.plan_id,
      dry_run: true,
      complete: false,
      statuses: dry_statuses,
      recovery_path: None,
    }
  }
  let preflight_statuses = save_publish_state(
    host,
    loaded.snapshot.root,
    ctx.plan_id,
    ctx.order_keys,
    ctx.status_map,
    "preflight",
  )
  if preflight.failed {
    return {
      schema_version: 1,
      plan_id: ctx.plan_id,
      dry_run: false,
      complete: false,
      statuses: preflight_statuses,
      recovery_path: Some(".moonset/publish-state.json"),
    }
  }
  let (failed, published_unit_ids) = execute_publish_units(
    host, loaded, options, ctx, preflight,
  )
  let final_statuses = save_publish_state(
    host,
    loaded.snapshot.root,
    ctx.plan_id,
    ctx.order_keys,
    ctx.status_map,
    "final",
  )
  // Skip Git tags for snapshot releases; when `--only` was specified, only tag selected units.
  if !failed &&
    !ctx.release_state.is_snapshot &&
    !options.no_tag &&
    !ctx.worktree_dirty &&
    loaded.snapshot.config.tag.after_publish &&
    loaded.snapshot.config.tag.create {
    let tag_units = if options.only.is_empty() {
      []
    } else if !published_unit_ids.is_empty() {
      published_unit_ids
    } else {
      ctx.selected_ids
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
    plan_id: ctx.plan_id,
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
