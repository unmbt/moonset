///|
fn visit(
  id : String,
  units : Map[String, @model.ReleaseUnit],
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
    if units.contains(dep.producer) {
      visit(dep.producer, units, marks, trail + [id])
    }
  }
  marks[id] = 2
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
pub fn build_plan(
  snapshot : @model.WorkspaceSnapshot,
  changesets : Array[@model.Changeset],
  pre? : @model.PreState,
  generated_at? : String,
) -> @model.ReleasePlan raise @model.MoonsetError {
  let config = snapshot.config
  let units : Map[String, @model.ReleaseUnit] = Map([])
  let manifest_owners : Map[String, String] = Map([])
  let ids = snapshot.units.map(x => x.id)
  ids.sort()
  for unit in snapshot.units {
    if unit.id != "moonbit:" + unit.native_name {
      invalid(
        "UnitId does not match the MoonBit module identity",
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
    if unit.ecosystem != "moonbit" {
      invalid(
        "Unsupported ecosystem: " + unit.ecosystem,
        code="unsupported-capability",
      )
    }
    if unit.version is Some(version) {
      ignore(parse_version(version)) catch {
        @model.Invalid(d) => raise @model.Invalid({ ..d, path: unit.manifest, })
        error => raise error
      }
    }
    for dep in unit.dependencies {
      if dep.kind != @model.Runtime {
        invalid(
          "Unsupported dependency kind: " + dep.kind.text(),
          path=dep.path,
          code="unsupported-capability",
        )
      }
      ignore(parse_version(dep.requirement)) catch {
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
  for id in ids {
    visit(id, units, marks, [])
  }
  for id in config.fixed.flatten() + config.linked.flatten() + config.ignore {
    if !units.contains(id) {
      invalid("Unknown configured unit: " + id)
    }
  }
  if pre is Some(state) {
    ignore(
      parse_pre_state(
        @model.canonical_json(state.to_json()),
        path=config.pre_file,
      ),
    )
    if state.mode != "active" && state.mode != "exit" {
      invalid("Invalid pre mode")
    }
    for id, _ in state.initial_versions {
      if !units.contains(id) {
        invalid("Pre state references missing unit: " + id)
      }
    }
    for id, n in state.next_numbers {
      if !units.contains(id) || n < 0 || n >= 2147483647 {
        invalid("Invalid pre counter: " + id)
      }
    }
  }
  let ordered = changesets.copy()
  ordered.sort_by((a, b) => a.id.compare(b.id))
  let levels : Map[String, @model.Bump] = Map([])
  let targets : Map[String, String] = Map([])
  let reasons : Map[String, Array[String]] = Map([])
  let direct : Map[String, Array[String]] = Map([])
  let seen_changesets : Map[String, Bool] = Map([])
  let warnings = snapshot.warnings.copy()
  for cs in ordered {
    if seen_changesets.contains(cs.id) {
      invalid("Duplicate changeset ID: " + cs.id, path=cs.path)
    }
    seen_changesets[cs.id] = true
    let ignored = cs.releases.filter(c => config.ignore.contains(c.unit_id))
    if !ignored.is_empty() && ignored.length() != cs.releases.length() {
      invalid("A changeset mixes ignored and managed units", path=cs.path)
    }
    for change in cs.releases {
      let id = change.unit_id
      if !units.contains(id) {
        invalid("Unknown changeset unit: " + id, path=cs.path)
      }
      if config.ignore.contains(id) {
        continue
      }
      if pre is Some(state) &&
        state.mode == "active" &&
        state.consumed.contains(cs.id) {
        continue
      }
      if change.bump == @model.None {
        continue
      }
      if change.bump.rank() > levels.get(id).unwrap_or(@model.None).rank() {
        levels[id] = change.bump
      }
      add_reason(reasons, id, "changeset:" + cs.id)
      add_reason(direct, id, cs.id)
    }
  }
  if pre is Some(state) && state.mode == "exit" {
    for id in ids {
      if config.ignore.contains(id) {
        continue
      }
      if units[id].version is Some(version) &&
        parse_version(version).is_prerelease() {
        if !levels.contains(id) {
          levels[id] = @model.Patch
        }
        add_reason(reasons, id, "pre:exit")
      }
    }
  }
  for ;; {
    let before = @model.canonical_json({
      "levels": levels.map((k, v) => (k, v.text())),
      "targets": targets,
    })
    for id in ids {
      if levels.get(id) is Some(level) {
        let candidate = target_version(units[id], level, pre)
        if !targets.contains(id) ||
          parse_version(candidate).compare(parse_version(targets[id])) > 0 {
          targets[id] = candidate
        }
      }
    }
    for kind in ["fixed", "linked"] {
      let groups = if kind == "fixed" { config.fixed } else { config.linked }
      for group in groups {
        let active = group.filter(id => levels.contains(id))
        if active.is_empty() {
          continue
        }
        let mut level = @model.Patch
        let mut highest = "0.0.0"
        let mut max_counter = 0
        for id in group {
          guard units[id].version is Some(version) else {
            invalid("Version group contains versionless unit: " + id)
            continue
          }
          if parse_version(version).compare(parse_version(highest)) > 0 {
            highest = version
          }
          let member_level = levels.get(id).unwrap_or(@model.None)
          if member_level.rank() > level.rank() {
            level = member_level
          }
          if pre is Some(state) {
            max_counter = max_counter.max(
              state.next_numbers.get(id).unwrap_or(0),
            )
          }
        }
        let target = increment(highest, level) +
          (match pre {
            Some(state) if state.mode == "active" =>
              "-" + state.tag + ".\{max_counter}"
            _ => ""
          })
        for id in group {
          if kind == "linked" && !levels.contains(id) {
            continue
          }
          if config.ignore.contains(id) {
            invalid("Version group requires ignored unit: " + id)
          }
          if level.rank() > levels.get(id).unwrap_or(@model.None).rank() {
            levels[id] = level
          }
          if !targets.contains(id) ||
            parse_version(target).compare(parse_version(targets[id])) > 0 {
            targets[id] = target
          }
          add_reason(reasons, id, kind + ":" + group.join(","))
        }
      }
    }
    for id in ids {
      for dep in units[id].dependencies {
        if targets.get(dep.producer) is Some(target) {
          let outside = !version_matches(dep.requirement, target)
          if outside || config.update_dependents == "always" {
            if config.ignore.contains(id) {
              invalid(
                "Dependency propagation requires ignored unit: " + id,
                path=dep.path,
              )
            }
            if !levels.contains(id) {
              levels[id] = @model.Patch
            }
            add_reason(reasons, id, "dependency:" + dep.producer)
          }
        }
      }
    }
    let after = @model.canonical_json({
      "levels": levels.map((k, v) => (k, v.text())),
      "targets": targets,
    })
    if before == after {
      break
    }
  }
  let releases : Array[@model.Release] = []
  let dependency_updates : Array[@model.DependencyIntent] = []
  let affected_paths : Array[String] = []
  for id in ids {
    if levels.get(id) is Some(level) {
      let unit = units[id]
      let old_version = unit.version.unwrap()
      let new_version = targets[id]
      if parse_version(new_version).compare(parse_version(old_version)) <= 0 {
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
      affected_paths.push(unit.manifest)
      for dep in unit.dependencies {
        if targets.get(dep.producer) is Some(target) &&
          target != dep.requirement {
          if !version_matches(dep.requirement, target) ||
            levels[dep.producer].rank() >= config.update_dependencies.rank() {
            dependency_updates.push({
              consumer: id,
              producer: dep.producer,
              path: dep.path,
              old_requirement: dep.requirement,
              new_requirement: target,
              start: dep.start,
              end: dep.end,
            })
          }
        }
      }
    }
  }
  affected_paths.sort()
  dependency_updates.sort_by((a, b) => {
    (a.consumer + ":" + a.producer).compare(b.consumer + ":" + b.producer)
  })
  let next_pre_state = match pre {
    Some(state) if state.mode == "active" => {
      let numbers = state.next_numbers.copy()
      let initial = state.initial_versions.copy()
      let consumed = state.consumed.copy()
      for release in releases {
        if !initial.contains(release.unit_id) {
          initial[release.unit_id] = release.old_version
        }
        let version = parse_version(release.new_version)
        if version.pre.last() is Some(@semver.Num(n)) {
          numbers[release.unit_id] = n + 1
        }
      }
      for cs in ordered {
        if !consumed.contains(cs.id) &&
          cs.releases.all(x => !config.ignore.contains(x.unit_id)) {
          consumed.push(cs.id)
        }
      }
      consumed.sort()
      Some(@model.PreState::{
        ..state,
        initial_versions: initial,
        next_numbers: numbers,
        consumed,
      })
    }
    _ => None
  }
  let fingerprint = @model.fingerprint({
    "workspace": snapshot.to_json(),
    "sources": snapshot.sources,
    "config": config.raw,
    "effectiveConfig": {
      "fixed": config.fixed,
      "linked": config.linked,
      "ignore": config.ignore,
      "updateInternalDependencies": config.update_dependencies.text(),
      "updateInternalDependents": config.update_dependents,
      "changedFilePatterns": config.changed_patterns,
      "preFile": config.pre_file,
      "mixed": config.mixed,
    },
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
    "changesets": ordered.map(x => x.to_json()),
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
    changesets: ordered,
    next_pre_state,
    warnings,
    generated_at,
  }
}
