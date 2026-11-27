///|
fn visit_execution(
  id : String,
  units : Map[String, @model.ReleaseUnit],
  bridges : Array[@model.Bridge],
  marks : Map[String, Int32],
  trail : Array[String],
) -> Unit raise @model.MoonsetError {
  match marks.get(id) {
    Some(2) => return
    Some(1) =>
      invalid(
        "Dependency cycle: " + (trail + [id]).join(" -> "),
        path=units[id].manifest,
        code="dependency-cycle",
      )
    _ => ()
  }
  marks[id] = 1
  for dep in units[id].dependencies {
    // Only runtime and build edges constrain publish/build execution ordering;
    // legal devDependencies / peerDependencies cycles are allowed.
    if (dep.kind == @model.Runtime || dep.kind == @model.Build) &&
      units.contains(dep.producer) {
      visit_execution(dep.producer, units, bridges, marks, trail + [id])
    }
  }
  for bridge in bridges {
    if bridge.consumer == id && units.contains(bridge.producer) {
      visit_execution(bridge.producer, units, bridges, marks, trail + [id])
    }
  }
  marks[id] = 2
}

///|
fn should_skip_versioning(
  unit : @model.ReleaseUnit,
  config : @model.Config,
  resolved_ignore : Array[String],
) -> Bool {
  resolved_ignore.contains(unit.id) ||
  unit.version is None ||
  (unit.visibility == @model.Private && !config.private_packages.version)
}

///|
fn add_reason(
  reasons : Map[String, Array[String]],
  id : String,
  reason : String,
) -> Unit {
  let list = reasons.get(id).unwrap_or([])
  if !list.contains(reason) {
    list.push(reason)
  }
  reasons[id] = list
}

///|
fn propagate_bridges(
  bridges : Array[@model.Bridge],
  units : Map[String, @model.ReleaseUnit],
  config : @model.Config,
  resolved_ignore : Array[String],
  levels : Map[String, @model.Bump],
  reasons : Map[String, Array[String]],
) -> Bool raise @model.MoonsetError {
  let mut changed = false
  for bridge in bridges {
    if levels.contains(bridge.producer) {
      if resolved_ignore.contains(bridge.consumer) {
        invalid(
          "Build bridge propagation requires ignored unit: " + bridge.consumer,
          code="unsupported-capability",
        )
      }
      if units.get(bridge.consumer) is Some(consumer_unit) {
        if should_skip_versioning(consumer_unit, config, resolved_ignore) {
          continue
        }
      }
      let current = levels.get(bridge.consumer).unwrap_or(@model.None)
      if bridge.bump.rank() > current.rank() {
        levels[bridge.consumer] = bridge.bump
        changed = true
      }
      add_reason(
        reasons,
        bridge.consumer,
        "bridge:" + bridge.producer + ":" + bridge.wait_for.text(),
      )
    }
  }
  changed
}

///|
fn workspace_manager_for_unit(
  snapshot : @model.WorkspaceSnapshot,
  unit : @model.ReleaseUnit,
) -> @model.PackageManager? {
  for ws in snapshot.workspaces {
    if ws.id == unit.workspace_id {
      return Some(ws.manager)
    }
  }
  None
}

///|
fn is_dependency_trackable(
  unit : @model.ReleaseUnit,
  dep : @model.DependencyEdge,
  config : @model.Config,
) -> Bool {
  match unit.ecosystem {
    @model.MoonBit => dep.kind == @model.Runtime
    @model.Cargo => true
    @model.Npm => {
      if is_npm_external_protocol(dep.requirement) {
        return false
      }
      if config.bump_versions_with_workspace_protocol_only &&
        !is_workspace_protocol(dep.requirement) {
        return false
      }
      true
    }
  }
}

///|
pub fn build_plan(
  snapshot : @model.WorkspaceSnapshot,
  changesets : Array[@model.Changeset],
  pre? : @model.PreState,
  generated_at? : String,
  snapshot_mode~ : Bool = false,
  snapshot_tag? : String,
  timestamp_ms~ : String = "",
) -> @model.ReleasePlan raise @model.MoonsetError {
  let config = snapshot.config
  let is_snapshot = snapshot_mode || snapshot_tag is Some(_)
  let effective_snapshot_tag = snapshot_tag.unwrap_or("")
  if is_snapshot {
    if !config.snapshot.enabled {
      invalid(
        "Snapshot releases are disabled by configuration; set snapshot.enabled to true",
        code="snapshot-disabled",
      )
    }
    if pre is Some(state) && state.mode == @model.Pre {
      invalid(
        "Snapshot releases cannot be run while in prerelease mode; run `moonset pre exit` first",
        code="invalid-input",
      )
    }
    validate_snapshot_template(config.snapshot.prerelease_template)
    // Validate tag/template compatibility upfront even if releases are empty.
    ignore(
      render_snapshot_version(
        "0.0.1",
        effective_snapshot_tag,
        config.snapshot,
        generated_at=generated_at.unwrap_or(""),
        timestamp_ms~,
        git_head?=snapshot.git_head,
      ),
    )
  }

  let units : Map[String, @model.ReleaseUnit] = Map([])
  let manifest_owners : Map[String, String] = Map([])
  let ids = snapshot.units.map(x => x.id)
  ids.sort()
  for unit in snapshot.units {
    if unit.id != unit.ecosystem.text() + ":" + unit.native_name {
      invalid(
        "UnitId does not match unit ecosystem and native name",
        path=unit.manifest,
      )
    }
    if manifest_owners.contains(unit.manifest) {
      invalid("Multiple version owners for manifest", path=unit.manifest)
    }
    manifest_owners[unit.manifest] = unit.id
    if units.contains(unit.id) {
      invalid("Duplicate unit: " + unit.id, path=unit.manifest)
    }
    if unit.version is Some(version) {
      ignore(parse_version(version)) catch {
        @model.Invalid(d) => raise @model.Invalid({ ..d, path: unit.manifest, })
        error => raise error
      }
    }
    let mgr = workspace_manager_for_unit(snapshot, unit)
    for dep in unit.dependencies {
      if unit.ecosystem == @model.MoonBit && dep.kind != @model.Runtime {
        invalid(
          "Unsupported dependency kind: " + dep.kind.text(),
          path=dep.path,
          code="unsupported-capability",
        )
      }
      if unit.ecosystem == @model.Npm &&
        is_workspace_protocol(dep.requirement) &&
        mgr == Some(@model.Npm) {
        invalid(
          "workspace: protocol is not supported by manager 'npm' (use 'pnpm' or 'yarn'): " +
          dep.requirement,
          path=dep.path,
          code="unsupported-capability",
        )
      }
      // Only enforce strict SemVer range validation on internal workspace deps
      // or non-external-protocol deps; external npm protocols (`catalog:`, `npm:`, `github:`, etc.) are valid.
      if unit.ecosystem == @model.Npm &&
        is_npm_external_protocol(dep.requirement) {
        continue
      }
      validate_ecosystem_range(unit.ecosystem, dep.requirement) catch {
        @model.Invalid(d) => raise @model.Invalid({ ..d, path: dep.path, })
        error => raise error
      }
    }
    units[unit.id] = unit
  }
  let marks : Map[String, Int32] = Map([])
  let fields : Map[String, String] = Map([])
  for ownership in snapshot.ownership {
    let key = ownership.path + "\u0000" + ownership.field
    if fields.contains(key) || !units.contains(ownership.owner) {
      invalid("Conflicting or unknown field owner", path=ownership.path)
    }
    fields[key] = ownership.owner
  }
  let bridges = config.bridges()
  for id in ids {
    visit_execution(id, units, bridges, marks, [])
  }
  let resolved_fixed = resolve_unit_groups(config.fixed, snapshot.units)
  let resolved_linked = resolve_unit_groups(config.linked, snapshot.units)
  let resolved_ignore = resolve_ignored_units(config, snapshot.units)
  let warnings = snapshot.warnings.copy()
  if config.also_skip_dependents_of_skipped {
    let skipped_set : Map[String, Bool] = Map([])
    for id in resolved_ignore {
      skipped_set[id] = true
    }
    for id in ids {
      if should_skip_versioning(units[id], config, resolved_ignore) {
        skipped_set[id] = true
      }
    }
    let mut expanded = true
    while expanded {
      expanded = false
      for id in ids {
        if skipped_set.contains(id) {
          continue
        }
        let unit = units[id]
        let depends_on_skipped = unit.dependencies.any(dep => {
            dep.kind != @model.Development && skipped_set.contains(dep.producer)
          }) ||
          bridges.any(b => b.consumer == id && skipped_set.contains(b.producer))
        if depends_on_skipped {
          skipped_set[id] = true
          if !resolved_ignore.contains(id) {
            resolved_ignore.push(id)
          }
          warnings.push(
            @model.diagnostic(
              "skipped-dependent",
              "Skipping dependent unit because it depends on a skipped package: " +
              id,
              path=unit.manifest,
            ),
          )
          expanded = true
        }
      }
    }
    resolved_ignore.sort()
  }
  let occupied_groups : Map[String, Bool] = Map([])
  for group in resolved_fixed + resolved_linked {
    for id in group {
      if occupied_groups.contains(id) {
        invalid("Overlapping or repeated version group member: " + id)
      }
      occupied_groups[id] = true
    }
  }
  let effective_fixed = resolved_fixed.copy()
  let cargo_version_paths : Map[String, Array[String]] = Map([])
  for id in ids {
    let unit = units[id]
    if unit.ecosystem == @model.Cargo &&
      unit.version_field == "workspace.package" {
      let group = cargo_version_paths.get(unit.version_path).unwrap_or([])
      group.push(unit.id)
      cargo_version_paths[unit.version_path] = group
    }
  }
  for _, group in cargo_version_paths {
    if group.length() > 1 {
      let occupied = effective_fixed.flatten() + resolved_linked.flatten()
      if group.any(id => occupied.contains(id)) {
        // Allow any fixed group that contains all Cargo crates sharing workspace.package.version
        if !effective_fixed.any(existing => {
            group.all(id => existing.contains(id))
          }) {
          invalid(
            "Cargo packages sharing workspace.package.version must share a fixed version group",
          )
        }
      } else {
        effective_fixed.push(group)
      }
    }
  }
  for bridge in bridges {
    if !units.contains(bridge.consumer) || !units.contains(bridge.producer) {
      invalid("Bridge references an unknown unit", code="invalid-bridge")
    }
    if bridge.consumer == bridge.producer {
      invalid("Build bridge cannot point to itself", code="dependency-cycle")
    }
  }
  if pre is Some(state) {
    validate_pre_tag(state.tag, path=config.pre.file)
  }

  let ordered = changesets.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  let levels : Map[String, @model.Bump] = Map([])
  let targets : Map[String, String] = Map([])
  let reasons : Map[String, Array[String]] = Map([])
  let direct : Map[String, Array[String]] = Map([])
  let seen_changesets : Map[String, Bool] = Map([])
  let relevant_changesets : Array[@model.Changeset] = []
  for cs in ordered {
    if seen_changesets.contains(cs.id) {
      invalid("Duplicate changeset ID: " + cs.id, path=cs.path)
    }
    seen_changesets[cs.id] = true
    let ignored = cs.releases.filter(c => resolved_ignore.contains(c.unit_id))
    if !ignored.is_empty() && ignored.length() != cs.releases.length() {
      invalid("A changeset mixes ignored and managed units", path=cs.path)
    }
    // Validate every referenced unit exists in the workspace
    for change in cs.releases {
      if !units.contains(change.unit_id) {
        invalid("Unknown changeset unit: " + change.unit_id, path=cs.path)
      }
    }
    // Ignored-only changesets are preserved untouched (not consumed, not active).
    if !cs.releases.is_empty() && ignored.length() == cs.releases.length() {
      continue
    }
    // In Changesets v3 `pre` mode, skip changesets already moved into `.changeset/pre/`
    // (or listed in legacy v2 `pre.json#consumed`).
    if pre is Some(state) &&
      state.mode == @model.Pre &&
      (cs.in_pre_dir || state.legacy_consumed.contains(cs.id)) {
      continue
    }
    relevant_changesets.push(cs)
    for change in cs.releases {
      let id = change.unit_id
      let unit = units[id]
      if unit.visibility == @model.Private && !config.private_packages.version {
        invalid(
          "Private unit versioning is disabled by configuration: " + id,
          path=cs.path,
          code="private-policy",
        )
      }
      if change.bump == @model.None {
        continue
      }
      if unit.version is None {
        invalid(
          "Release unit has no version: " + id,
          path=unit.manifest,
          code="missing-version-field",
        )
      }
      if change.bump.rank() > levels.get(id).unwrap_or(@model.None).rank() {
        levels[id] = change.bump
      }
      add_reason(reasons, id, "changeset:" + cs.id)
      add_reason(direct, id, cs.id)
    }
  }

  // On `pre exit`, any non-skipped unit still on a prerelease matching `state.tag`
  // graduates with at least a Patch bump (stripping the prerelease suffix).
  if pre is Some(state) && state.mode == @model.Exit {
    for id in ids {
      let unit = units[id]
      if should_skip_versioning(unit, config, resolved_ignore) {
        continue
      }
      if unit.version is Some(version) &&
        has_prerelease_tag(parse_version(version), state.tag) {
        if !levels.contains(id) {
          levels[id] = @model.Patch
        }
        add_reason(reasons, id, "pre:exit")
      }
    }
  }

  ignore(
    propagate_bridges(bridges, units, config, resolved_ignore, levels, reasons),
  )

  // Fixed-point propagation loop using explicit `changed` flag and bounded guard.
  let max_iterations = ids.length() * 4 + 32
  let mut iter = 0
  while iter < max_iterations {
    iter += 1
    let mut changed = false
    for id in ids {
      if levels.get(id) is Some(level) {
        let candidate = target_version(units[id], level, pre)
        match targets.get(id) {
          None => {
            targets[id] = candidate
            changed = true
          }
          Some(existing) =>
            if parse_version(candidate).compare(parse_version(existing)) > 0 {
              targets[id] = candidate
              changed = true
            }
        }
      }
    }
    if propagate_bridges(
        bridges, units, config, resolved_ignore, levels, reasons,
      ) {
      changed = true
    }
    for kind in ["fixed", "linked"] {
      let group_list = if kind == "fixed" {
        effective_fixed
      } else {
        resolved_linked
      }
      for group in group_list {
        let active = group.filter(id => levels.contains(id))
        if active.is_empty() {
          continue
        }
        let mut level = @model.Patch
        let baseline_units : Array[@model.ReleaseUnit] = []
        let target_units : Array[@model.ReleaseUnit] = []
        for id in group {
          let unit = units[id]
          if resolved_ignore.contains(id) {
            if kind == "fixed" {
              invalid("Version group requires ignored unit: " + id)
            }
            continue
          }
          if should_skip_versioning(unit, config, resolved_ignore) {
            continue
          }
          if unit.version is None {
            invalid("Version group contains versionless unit: " + id)
            continue
          }
          baseline_units.push(unit)
          if kind == "fixed" || levels.contains(id) {
            target_units.push(unit)
            let member_level = levels.get(id).unwrap_or(@model.None)
            if member_level.rank() > level.rank() {
              level = member_level
            }
          }
        }
        if target_units.is_empty() {
          continue
        }
        let target = compute_group_target_version(baseline_units, level, pre)
        for unit in target_units {
          let id = unit.id
          if level.rank() > levels.get(id).unwrap_or(@model.None).rank() {
            levels[id] = level
            changed = true
          }
          match targets.get(id) {
            None => {
              targets[id] = target
              changed = true
            }
            Some(existing) =>
              if parse_version(target).compare(parse_version(existing)) > 0 {
                targets[id] = target
                changed = true
              }
          }
          add_reason(reasons, id, kind + ":" + group.join(","))
        }
      }
    }
    for id in ids {
      let consumer_unit = units[id]
      for dep in consumer_unit.dependencies {
        if targets.get(dep.producer) is Some(target) {
          if !is_dependency_trackable(consumer_unit, dep, config) {
            continue
          }
          // `devDependencies` never bump the consumer's version (only update dep ranges below).
          if dep.kind == @model.Development {
            continue
          }
          let producer_old = units.get(dep.producer).bind(u => u.version)
          let outside = !matches_ecosystem_range(
            consumer_unit.ecosystem,
            dep.requirement,
            target,
            producer_current_version?=producer_old,
          )
          let is_peer_npm = consumer_unit.ecosystem == @model.Npm &&
            dep.kind == @model.Peer
          let should_bump = if is_peer_npm {
            if config.only_update_peer_dependents_when_out_of_range {
              outside
            } else {
              outside ||
              levels.get(dep.producer).unwrap_or(@model.None) == @model.Major
            }
          } else {
            outside || config.update_dependents == @model.Always
          }
          if should_bump {
            if resolved_ignore.contains(id) {
              // Skipped / ignored dependents do not bump version; their dep range is updated below.
              continue
            }
            if should_skip_versioning(consumer_unit, config, resolved_ignore) {
              continue
            }
            let required_bump = if is_peer_npm {
              @model.Major
            } else {
              @model.Patch
            }
            let current_bump = levels.get(id).unwrap_or(@model.None)
            if required_bump.rank() > current_bump.rank() {
              levels[id] = required_bump
              changed = true
            }
            add_reason(reasons, id, "dependency:" + dep.producer)
          }
        }
      }
    }
    if !changed {
      break
    }
  }

  // If snapshot mode is enabled, compute final snapshot versions directly in the planner
  // and pull in any non-skipped runtime/peer dependents whose ranges no longer satisfy the snapshot.
  let final_targets : Map[String, String] = Map([])
  if is_snapshot {
    // Pass 1: assign snapshot versions to currently releasing units and cascade to runtime/peer dependents.
    let mut snap_changed = true
    while snap_changed {
      snap_changed = false
      for id in ids {
        if levels.get(id) is Some(_) && !final_targets.contains(id) {
          let calc = targets[id]
          final_targets[id] = render_snapshot_version(
            calc,
            effective_snapshot_tag,
            config.snapshot,
            generated_at=generated_at.unwrap_or(""),
            timestamp_ms~,
            git_head?=snapshot.git_head,
          )
          snap_changed = true
        }
      }
      for id in ids {
        let consumer_unit = units[id]
        if levels.contains(id) ||
          should_skip_versioning(consumer_unit, config, resolved_ignore) {
          continue
        }
        for dep in consumer_unit.dependencies {
          if final_targets.get(dep.producer) is Some(snap_target) {
            if dep.kind == @model.Development ||
              !is_dependency_trackable(consumer_unit, dep, config) {
              continue
            }
            let producer_old = units.get(dep.producer).bind(u => u.version)
            let outside = !matches_ecosystem_range(
              consumer_unit.ecosystem,
              dep.requirement,
              snap_target,
              producer_current_version?=producer_old,
            )
            if outside {
              levels[id] = @model.Patch
              targets[id] = target_version(consumer_unit, @model.Patch, None)
              add_reason(reasons, id, "dependency:" + dep.producer)
              snap_changed = true
              break
            }
          }
        }
      }
    }
  } else {
    for id, ver in targets {
      final_targets[id] = ver
    }
  }

  let releases : Array[@model.Release] = []
  let dependency_updates : Array[@model.DependencyIntent] = []
  let affected_paths : Array[String] = []
  fn push_unique_path(path : String) {
    if path != "" && !affected_paths.contains(path) {
      affected_paths.push(path)
    }
  }

  for id in ids {
    let unit = units[id]
    if levels.get(id) is Some(level) {
      guard unit.version is Some(old_version) else {
        invalid("Release unit has no version: " + id, path=unit.manifest)
        continue
      }
      let new_version = final_targets[id]
      if !is_snapshot &&
        parse_version(new_version).compare(parse_version(old_version)) <= 0 {
        invalid("Target version must increase: " + id)
      }
      let why = reasons.get(id).unwrap_or([])
      why.sort()
      let cs = direct.get(id).unwrap_or([])
      cs.sort()
      releases.push({
        unit_id: id,
        old_version,
        new_version,
        level,
        reasons: why,
        changesets: cs,
        publish: unit.publish,
      })
      push_unique_path(unit.manifest)
      push_unique_path(unit.version_path)
    }
    // Compute dependency updates across ALL units (including non-bumping devDependencies,
    // ignored, private-unversioned, and versionless root manifests).
    for dep in unit.dependencies {
      if final_targets.get(dep.producer) is Some(target) {
        if !is_dependency_trackable(unit, dep, config) {
          continue
        }
        let producer_old = units.get(dep.producer).bind(u => u.version)
        let outside = !matches_ecosystem_range(
          unit.ecosystem,
          dep.requirement,
          target,
          producer_current_version?=producer_old,
        )
        let producer_level = levels.get(dep.producer).unwrap_or(@model.None)
        let is_peer_npm = unit.ecosystem == @model.Npm &&
          dep.kind == @model.Peer
        let consumer_releasing = levels.contains(id)
        let should_update = if is_snapshot {
          consumer_releasing || outside || dep.kind == @model.Development
        } else if is_peer_npm {
          outside ||
          (
            consumer_releasing &&
            !config.only_update_peer_dependents_when_out_of_range
          )
        } else if dep.kind == @model.Development {
          outside ||
          (
            consumer_releasing &&
            producer_level.rank() >= config.update_dependencies.rank()
          )
        } else {
          outside ||
          (
            consumer_releasing &&
            producer_level.rank() >= config.update_dependencies.rank()
          )
        }
        if should_update {
          let next_requirement = rewrite_ecosystem_range(
            unit.ecosystem,
            dep.requirement,
            target,
            exact_pin=is_snapshot,
          )
          if next_requirement != dep.requirement {
            dependency_updates.push({
              consumer: id,
              producer: dep.producer,
              kind: dep.kind,
              producer_version: target,
              path: dep.path,
              old_requirement: dep.requirement,
              new_requirement: next_requirement,
              start: dep.start,
              end: dep.end,
            })
            push_unique_path(dep.path)
          }
        }
      }
    }
  }
  affected_paths.sort()
  dependency_updates.sort_by((a, b) => {
    let ka = a.consumer + ":" + a.producer + ":" + a.kind.text() + ":\{a.start}"
    let kb = b.consumer + ":" + b.producer + ":" + b.kind.text() + ":\{b.start}"
    ka.compare(kb)
  })
  let next_pre_state = match pre {
    Some(state) if state.mode == @model.Pre && !is_snapshot =>
      Some(@model.PreState::new(@model.Pre, state.tag))
    _ => None
  }
  let fingerprint = @model.fingerprint({
    "workspace": snapshot.to_json(),
    "sources": snapshot.sources,
    "config": config.to_json(),
    "isSnapshot": is_snapshot,
    "snapshotTag": effective_snapshot_tag,
    "dependencies": ids.map(id => {
      (
        {
          "unitId": id,
          "edges": units[id].dependencies.map(d => {
            (
              {
                "producer": d.producer,
                "requirement": d.requirement,
                "kind": d.kind.text(),
                "path": d.path,
                "start": d.start,
                "end": d.end,
              } : Json)
          }),
        } : Json)
    }),
    "changesets": relevant_changesets.map(x => x.to_json()),
    "pre": match pre {
      Some(p) => p.to_json()
      None => Json::null()
    },
  })
  {
    fingerprint,
    releases,
    dependency_updates,
    affected_paths,
    changesets: relevant_changesets,
    next_pre_state,
    warnings,
    generated_at,
    is_snapshot,
  }
}
