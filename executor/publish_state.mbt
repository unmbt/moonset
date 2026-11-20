///|
fn status_key(unit_id : String, version : String, target : String) -> String {
  unit_id + "@" + version + "/" + target
}

///|
fn parse_publish_state(name : String) -> @model.PublishState {
  if name == "publishing" {
    @model.Unknown
  } else {
    @model.PublishState::parse(name).unwrap_or(@model.Unknown)
  }
}

///|
/// Load and validate `.moonset/release-state.json` via the canonical model parser.
async fn[H : ExecutionHost] load_release_state(
  host : H,
  root : String,
) -> (@model.ReleaseState, Json) {
  let state_path = absolute_path(root, ".moonset/release-state.json")
  if !host.exists(state_path) {
    raise invalid_error(
      "usage",
      "No release state exists; run version first",
      path=state_path,
    )
  }
  let raw = @json.parse(host.read_text(state_path)) catch {
    _ =>
      raise invalid_error(
        "usage",
        "Release state is not valid JSON",
        path=state_path,
      )
  }
  let state = @model.ReleaseState::from_json(raw) catch {
    @model.Invalid(diag) =>
      raise invalid_error(diag.code, diag.message, path=state_path)
    other => raise other
  }
  (state, raw)
}

///|
/// Load previously persisted `.moonset/publish-state.json` matching `plan_id`,
/// preserving `digest` and `external_id` across retries.
async fn[H : ExecutionHost] load_publish_state(
  host : H,
  root : String,
  plan_id : String,
) -> Map[String, @model.PublishStatus] {
  let status_map : Map[String, @model.PublishStatus] = Map([])
  let previous_path = absolute_path(root, ".moonset/publish-state.json")
  if !host.exists(previous_path) {
    return status_map
  }
  let previous = @json.parse(host.read_text(previous_path)) catch {
    _ => return status_map
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
          let digest = match previous_status {
            { "digest": String(d), .. } => Some(d)
            _ => None
          }
          let external_id = match previous_status {
            { "externalId": String(e), .. } => Some(e)
            _ => None
          }
          let key = status_key(previous_unit, previous_version, previous_target)
          status_map[key] = {
            plan_id,
            unit_id: previous_unit,
            version: previous_version,
            target: previous_target,
            registry,
            state: parse_publish_state(previous_state),
            digest,
            external_id,
            message,
          }
        }
      }
    _ => ()
  }
  status_map
}

///|
fn serialize_publish_state(
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
/// Atomically persist `.moonset/publish-state.json` via temp file + rename.
async fn[H : ExecutionHost] save_publish_state(
  host : H,
  root : String,
  plan_id : String,
  order_keys : Array[String],
  status_map : Map[String, @model.PublishStatus],
  tag : String,
) -> Array[@model.PublishStatus] {
  let (statuses, text) = serialize_publish_state(
    plan_id, order_keys, status_map,
  )
  let target = absolute_path(root, ".moonset/publish-state.json")
  atomic_write_text(host, target, text, "pub-" + tag)
  statuses
}
