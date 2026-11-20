///|
fn is_publish_order_dependency(kind : @model.DependencyKind) -> Bool {
  match kind {
    @model.Runtime | @model.Build | @model.Optional | @model.Peer => true
    @model.Development => false
  }
}

///|
/// Collect all upstream producers that must be published before `unit_id`.
fn upstream_producers(
  unit_id : String,
  units_map : Map[String, @model.ReleaseUnit],
  bridges : Array[@model.Bridge],
  specs_by_unit : Map[String, Array[@model.ArtifactTargetSpec]],
) -> Array[String] {
  let producers : Array[String] = []
  if units_map.get(unit_id) is Some(unit) {
    for dep in unit.dependencies {
      if is_publish_order_dependency(dep.kind) &&
        dep.producer != unit_id &&
        !producers.contains(dep.producer) {
        producers.push(dep.producer)
      }
    }
  }
  for bridge in bridges {
    if bridge.consumer == unit_id &&
      bridge.wait_for == @model.BridgeWaitFor::Publish &&
      bridge.producer != unit_id &&
      !producers.contains(bridge.producer) {
      producers.push(bridge.producer)
    }
  }
  for spec in specs_by_unit.get(unit_id).unwrap_or([]) {
    if spec.required &&
      spec.linked_package is Some(pkg) &&
      pkg != unit_id &&
      !producers.contains(pkg) {
      producers.push(pkg)
    }
  }
  producers
}

///|
/// Deterministic topological sort over `release_ids` with explicit cycle detection.
fn topological_release_order(
  release_ids : Array[String],
  units_map : Map[String, @model.ReleaseUnit],
  bridges : Array[@model.Bridge],
  specs_by_unit : Map[String, Array[@model.ArtifactTargetSpec]],
) -> Array[String] raise @model.MoonsetError {
  let ordered : Array[String] = []
  // 0 = unvisited, 1 = visiting (in stack), 2 = done
  let marks : Map[String, Int32] = Map([])
  fn visit(id : String) -> Unit raise @model.MoonsetError {
    match marks.get(id) {
      Some(2) => return
      Some(1) =>
        raise invalid_error(
          "dependency-cycle",
          "Publish dependency cycle detected involving unit: " + id,
        )
      _ => ()
    }
    marks[id] = 1
    for producer in upstream_producers(id, units_map, bridges, specs_by_unit) {
      if release_ids.contains(producer) {
        visit(producer)
      }
    }
    marks[id] = 2
    ordered.push(id)
  }
  for id in release_ids {
    visit(id)
  }
  ordered
}

///|
/// Validate `--only` selection closure, allowing downstream retries when
/// upstream producers or fixed-group siblings are already `Published`.
fn resolve_only_selection(
  only : Array[String],
  release_ids : Array[String],
  release_versions : Map[String, String],
  units_map : Map[String, @model.ReleaseUnit],
  loaded : @workspace.LoadedWorkspace,
  specs_by_unit : Map[String, Array[@model.ArtifactTargetSpec]],
  previous_statuses : Map[String, @model.PublishStatus],
) -> Array[String] raise @model.MoonsetError {
  if only.is_empty() {
    return release_ids.copy()
  }
  let chosen : Array[String] = []
  for raw in only {
    let trimmed = raw.trim().to_owned()
    if trimmed == "" {
      continue
    }
    let id = match
      loaded.snapshot.units
      .iter()
      .find_first(u => u.id == trimmed || u.native_name == trimmed) {
      Some(u) => u.id
      None => @engine.canonical_id(trimmed)
    }
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
  let is_already_published = fn(uid : String) -> Bool {
    match release_versions.get(uid) {
      Some(ver) =>
        match previous_statuses.get(status_key(uid, ver, "source")) {
          Some(st) => st.state == @model.Published
          None => false
        }
      None => false
    }
  }
  let resolved_fixed = @engine.resolve_unit_groups(
    loaded.snapshot.config.fixed,
    loaded.snapshot.units,
  )
  let missing : Array[String] = []
  for group in resolved_fixed {
    if group.any(id => chosen.contains(id)) {
      for group_member in group {
        if release_versions.contains(group_member) &&
          !chosen.contains(group_member) &&
          !is_already_published(group_member) &&
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
        loaded.snapshot.config.bridges(),
        specs_by_unit,
      ) {
      if release_versions.contains(producer) &&
        !chosen.contains(producer) &&
        !is_already_published(producer) &&
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
