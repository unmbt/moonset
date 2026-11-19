///|
/// Per-target artifact declaration parsed from `experimental.mixedWorkspaces.units.<id>.artifacts`.
pub(all) struct ArtifactTargetSpec {
  target : String
  package_unit_id : String?
  required : Bool
  path : String?
}

///|
/// One build or publish node in the separated execution DAG.
pub(all) struct ExecutionNode {
  id : String
  unit_id : String
  version : String
  target : String
  phase : String
  required : Bool
  depends_on : Array[String]
}

///|
pub fn ExecutionNode::to_json(self : ExecutionNode) -> Json {
  {
    "id": self.id,
    "unitId": self.unit_id,
    "version": self.version,
    "target": self.target,
    "phase": self.phase,
    "required": self.required,
    "dependsOn": self.depends_on.map(Json::string),
  }
}

///|
/// Separated build and publish DAG derived deterministically from a ReleasePlan.
pub(all) struct ExecutionDag {
  plan_fingerprint : String
  artifacts : Array[@model.ArtifactIntent]
  build_nodes : Array[ExecutionNode]
  publish_nodes : Array[ExecutionNode]
  publish_order : Array[String]
}

///|
pub fn ExecutionDag::to_json(self : ExecutionDag) -> Json {
  {
    "planFingerprint": self.plan_fingerprint,
    "artifacts": self.artifacts.map(x => x.to_json()),
    "buildNodes": self.build_nodes.map(x => x.to_json()),
    "publishNodes": self.publish_nodes.map(x => x.to_json()),
    "publishOrder": self.publish_order.map(Json::string),
  }
}

///|
/// Verification issue found while validating packed artifacts against ArtifactIntents.
pub(all) struct ArtifactIssue {
  unit_id : String
  target : String
  artifact_id : String
  code : String
  message : String
  blocking : Bool
}

///|
pub fn ArtifactIssue::to_json(self : ArtifactIssue) -> Json {
  {
    "unitId": self.unit_id,
    "target": self.target,
    "artifactId": self.artifact_id,
    "code": self.code,
    "message": self.message,
    "blocking": self.blocking,
  }
}

///|
/// Aggregate artifact verification report.
pub(all) struct ArtifactVerificationReport {
  ok : Bool
  checked : Int32
  issues : Array[ArtifactIssue]
  blocked_units : Array[String]
}

///|
pub fn ArtifactVerificationReport::to_json(
  self : ArtifactVerificationReport,
) -> Json {
  {
    "schemaVersion": 1,
    "ok": self.ok,
    "checked": self.checked.to_double(),
    "issues": self.issues.map(x => x.to_json()),
    "blockedUnits": self.blocked_units.map(Json::string),
  }
}

///|
/// Parse per-unit `artifacts` declarations from `Config.raw`.
pub fn parse_artifact_specs(
  config : @model.Config,
) -> Map[String, Array[ArtifactTargetSpec]] {
  let out : Map[String, Array[ArtifactTargetSpec]] = Map([])
  guard config.raw
    is {
      "experimental": { "mixedWorkspaces": { "units": Object(units), .. }, .. },
      ..
    } else {
    return out
  }
  for unit_id, override_json in units {
    if override_json is { "artifacts": Array(items), .. } {
      let specs : Array[ArtifactTargetSpec] = []
      for item in items {
        if item is { "target": String(target), .. } {
          let package_unit_id = match item {
            { "package": String(pkg), .. } => Some(canonical_id(pkg))
            _ => None
          }
          let required = match item {
            { "required": False, .. } => false
            _ => true
          }
          let path = match item {
            { "path": String(p), .. } => Some(p)
            _ => None
          }
          specs.push({ target, package_unit_id, required, path, })
        }
      }
      if !specs.is_empty() {
        out[canonical_id(unit_id)] = specs
      }
    }
  }
  out
}

///|
/// Return true when any unit declares multi-target artifact specs.
pub fn has_artifact_specs(config : @model.Config) -> Bool {
  !parse_artifact_specs(config).is_empty()
}

///|
fn topological_nodes(
  nodes : Array[ExecutionNode],
) -> Array[ExecutionNode] raise @model.MoonsetError {
  let by_id : Map[String, ExecutionNode] = Map([])
  for node in nodes {
    by_id[node.id] = node
  }
  let marks : Map[String, Int32] = Map([])
  let ordered : Array[ExecutionNode] = []
  fn visit(
    id : String,
    trail : Array[String],
  ) -> Unit raise @model.MoonsetError {
    match marks.get(id) {
      Some(2) => return
      Some(1) => {
        let cycle = trail + [id]
        raise @model.Invalid(
          @model.diagnostic(
            "cyclic-execution-graph",
            "Execution graph contains a cycle: " + cycle.join(" -> "),
          ),
        )
      }
      _ => ()
    }
    marks[id] = 1
    if by_id.get(id) is Some(node) {
      for dep in node.depends_on {
        if by_id.contains(dep) {
          visit(dep, trail + [id])
        }
      }
      marks[id] = 2
      ordered.push(node)
    }
  }
  for node in nodes {
    visit(node.id, [])
  }
  ordered
}

///|
fn push_unique(items : Array[String], value : String) -> Unit {
  if !items.contains(value) {
    items.push(value)
  }
}

///|
/// Build separated build/publish DAG and ArtifactIntents from snapshot + ReleasePlan.
pub fn build_execution_dag(
  snapshot : @model.WorkspaceSnapshot,
  plan : @model.ReleasePlan,
  release_versions_override? : Map[String, String],
) -> ExecutionDag raise @model.MoonsetError {
  let unit_map : Map[String, @model.ReleaseUnit] = Map([])
  for unit in snapshot.units {
    unit_map[unit.id] = unit
  }
  let specs_by_unit = parse_artifact_specs(snapshot.config)
  for owner_id, specs in specs_by_unit {
    let seen_targets : Map[String, Bool] = Map([])
    for spec in specs {
      if seen_targets.contains(spec.target) {
        raise @model.Invalid(
          @model.diagnostic(
            "duplicate-artifact-target",
            "Duplicate artifact target `" +
            spec.target +
            "` for unit " +
            owner_id,
          ),
        )
      }
      seen_targets[spec.target] = true
      if spec.package_unit_id is Some(pkg) {
        if pkg == owner_id {
          raise @model.Invalid(
            @model.diagnostic(
              "cyclic-execution-graph",
              "Unit cannot reference itself as a platform artifact package: " +
              pkg,
            ),
          )
        }
        if !unit_map.contains(pkg) {
          raise @model.Invalid(
            @model.diagnostic(
              "unknown-unit",
              "Unknown artifact package unit `" +
              pkg +
              "` referenced by " +
              owner_id,
            ),
          )
        }
      }
    }
  }

  let release_by_unit : Map[String, @model.Release] = Map([])
  let versions : Map[String, String] = Map([])
  for release in plan.releases {
    release_by_unit[release.unit_id] = release
    let ver = match release_versions_override {
      Some(overrides) =>
        overrides.get(release.unit_id).unwrap_or(release.new_version)
      None => release.new_version
    }
    versions[release.unit_id] = ver
  }

  let linked_packages : Map[String, Bool] = Map([])
  for release in plan.releases {
    if release.publish {
      for spec in specs_by_unit.get(release.unit_id).unwrap_or([]) {
        if spec.package_unit_id is Some(pkg) && pkg != release.unit_id {
          linked_packages[pkg] = true
        }
      }
    }
  }

  let artifacts : Array[@model.ArtifactIntent] = []
  let seen_artifact_keys : Map[String, Bool] = Map([])
  fn emit_intent(
    unit_id : String,
    version : String,
    target : String,
    required : Bool,
    path : String?,
  ) {
    let key = unit_id + "\u0000" + target
    if seen_artifact_keys.contains(key) {
      return
    }
    seen_artifact_keys[key] = true
    let id = if target == "source" {
      unit_id + "@" + version
    } else {
      unit_id + "@" + version + "/" + target
    }
    artifacts.push({
      id,
      unit_id,
      version,
      target,
      required,
      source_commit: snapshot.git_head,
      expected_hash: None,
      path,
    })
  }

  for release in plan.releases {
    if !release.publish {
      continue
    }
    let version = versions[release.unit_id]
    let specs = specs_by_unit.get(release.unit_id).unwrap_or([])
    let self_specs = specs.filter(s => {
      s.package_unit_id is None || s.package_unit_id == Some(release.unit_id)
    })
    let linked_specs = specs.filter(s => {
      s.package_unit_id is Some(pkg) && pkg != release.unit_id
    })
    if self_specs.is_empty() {
      if !linked_packages.contains(release.unit_id) {
        emit_intent(release.unit_id, version, "source", true, None)
      }
    } else {
      for spec in self_specs {
        emit_intent(
          release.unit_id,
          version,
          spec.target,
          spec.required,
          spec.path,
        )
      }
    }
    for spec in linked_specs {
      let pkg = spec.package_unit_id.unwrap()
      let pkg_ver = match versions.get(pkg) {
        Some(v) => v
        None => unit_map.get(pkg).bind(u => u.version).unwrap_or(version)
      }
      emit_intent(pkg, pkg_ver, spec.target, spec.required, spec.path)
    }
  }

  let raw_build_nodes : Array[ExecutionNode] = []
  let raw_publish_nodes : Array[ExecutionNode] = []
  for release in plan.releases {
    let version = versions[release.unit_id]
    let build_deps : Array[String] = []
    if unit_map.get(release.unit_id) is Some(unit) {
      for dep in unit.dependencies {
        if (dep.kind == @model.Runtime || dep.kind == @model.Build) &&
          release_by_unit.contains(dep.producer) {
          push_unique(build_deps, "build:" + dep.producer)
        }
      }
    }
    for bridge in snapshot.config.bridges {
      if bridge.consumer == release.unit_id &&
        release_by_unit.contains(bridge.producer) {
        push_unique(build_deps, "build:" + bridge.producer)
      }
    }
    raw_build_nodes.push({
      id: "build:" + release.unit_id,
      unit_id: release.unit_id,
      version,
      target: "build",
      phase: "build",
      required: true,
      depends_on: build_deps,
    })

    if release.publish {
      let pub_deps : Array[String] = []
      if unit_map.get(release.unit_id) is Some(unit) {
        for dep in unit.dependencies {
          if dep.kind == @model.Runtime &&
            release_by_unit
            .get(dep.producer)
            .map(r => r.publish)
            .unwrap_or(false) {
            push_unique(pub_deps, "publish:" + dep.producer)
          }
        }
      }
      for bridge in snapshot.config.bridges {
        if bridge.consumer == release.unit_id &&
          bridge.wait_for == "publish" &&
          release_by_unit
          .get(bridge.producer)
          .map(r => r.publish)
          .unwrap_or(false) {
          push_unique(pub_deps, "publish:" + bridge.producer)
        }
      }
      for spec in specs_by_unit.get(release.unit_id).unwrap_or([]) {
        if spec.required &&
          spec.package_unit_id is Some(pkg) &&
          pkg != release.unit_id &&
          release_by_unit.get(pkg).map(r => r.publish).unwrap_or(false) {
          push_unique(pub_deps, "publish:" + pkg)
        }
      }
      raw_publish_nodes.push({
        id: "publish:" + release.unit_id,
        unit_id: release.unit_id,
        version,
        target: "source",
        phase: "publish",
        required: true,
        depends_on: pub_deps,
      })
    }
  }

  let build_nodes = topological_nodes(raw_build_nodes)
  let publish_nodes = topological_nodes(raw_publish_nodes)
  let publish_order = publish_nodes.map(n => n.unit_id)
  {
    plan_fingerprint: plan.fingerprint,
    artifacts,
    build_nodes,
    publish_nodes,
    publish_order,
  }
}

///|
/// Verify packed results against declared ArtifactIntents.
pub fn verify_artifact_matrix(
  intents : Array[@model.ArtifactIntent],
  packed : Array[@model.PackResult],
  expected_head? : String,
  owners_by_package? : Map[String, Array[String]],
) -> ArtifactVerificationReport {
  let by_key : Map[String, @model.PackResult] = Map([])
  for result in packed {
    by_key[result.unit_id + "\u0000" + result.target] = result
  }
  let source_claimed : Map[String, Bool] = Map([])
  for intent in intents {
    if intent.target == "source" {
      source_claimed[intent.unit_id] = true
    }
  }
  let issues : Array[ArtifactIssue] = []
  let blocked_units : Array[String] = []
  fn block_unit(uid : String) {
    push_unique(blocked_units, uid)
    if owners_by_package is Some(owners_map) {
      if owners_map.get(uid) is Some(owners) {
        for owner in owners {
          push_unique(blocked_units, owner)
        }
      }
    }
  }

  for intent in intents {
    let exact = by_key.get(intent.unit_id + "\u0000" + intent.target)
    let matched = match exact {
      Some(hit) => Some(hit)
      None =>
        if intent.target != "source" &&
          !source_claimed.contains(intent.unit_id) &&
          intent.path is None {
          by_key.get(intent.unit_id + "\u0000source")
        } else {
          None
        }
    }
    match matched {
      None => {
        issues.push({
          unit_id: intent.unit_id,
          target: intent.target,
          artifact_id: intent.id,
          code: "artifact-missing",
          message: "Missing packed artifact for " +
          intent.unit_id +
          " (" +
          intent.target +
          ")",
          blocking: intent.required,
        })
        if intent.required {
          block_unit(intent.unit_id)
        }
      }
      Some(pack) => {
        let mut issue_added = false
        if !pack.verified {
          issues.push({
            unit_id: intent.unit_id,
            target: intent.target,
            artifact_id: intent.id,
            code: "artifact-unverified",
            message: "Packed artifact is marked unverified for " +
            intent.unit_id +
            " (" +
            intent.target +
            ")",
            blocking: intent.required,
          })
          issue_added = true
        } else if pack.version != intent.version {
          issues.push({
            unit_id: intent.unit_id,
            target: intent.target,
            artifact_id: intent.id,
            code: "stale-artifact",
            message: "Packed artifact version " +
            pack.version +
            " does not match expected " +
            intent.version +
            " for " +
            intent.unit_id,
            blocking: intent.required,
          })
          issue_added = true
        } else if expected_head is Some(head) &&
          pack.source_commit is Some(pc) &&
          pc != head {
          issues.push({
            unit_id: intent.unit_id,
            target: intent.target,
            artifact_id: intent.id,
            code: "stale-artifact",
            message: "Packed artifact commit " +
            pc +
            " does not match HEAD " +
            head +
            " for " +
            intent.unit_id,
            blocking: intent.required,
          })
          issue_added = true
        } else if pack.content_hash == "" {
          issues.push({
            unit_id: intent.unit_id,
            target: intent.target,
            artifact_id: intent.id,
            code: "artifact-unverified",
            message: "Packed artifact has an empty content hash for " +
            intent.unit_id +
            " (" +
            intent.target +
            ")",
            blocking: intent.required,
          })
          issue_added = true
        } else if intent.expected_hash is Some(exp) && pack.content_hash != exp {
          issues.push({
            unit_id: intent.unit_id,
            target: intent.target,
            artifact_id: intent.id,
            code: "artifact-hash-mismatch",
            message: "Packed artifact hash mismatch for " +
            intent.unit_id +
            " (" +
            intent.target +
            ")",
            blocking: intent.required,
          })
          issue_added = true
        } else if intent.path is Some(exp_path) && pack.archive_path != "" {
          let actual_norm = pack.archive_path.replace_all(old="\\", new="/")
          let expected_norm = exp_path.replace_all(old="\\", new="/")
          if actual_norm != expected_norm &&
            !actual_norm.has_suffix("/" + expected_norm) {
            issues.push({
              unit_id: intent.unit_id,
              target: intent.target,
              artifact_id: intent.id,
              code: "artifact-path-mismatch",
              message: "Packed artifact path does not match expected " +
              exp_path +
              " for " +
              intent.unit_id,
              blocking: intent.required,
            })
            issue_added = true
          }
        }
        if issue_added && intent.required {
          block_unit(intent.unit_id)
        }
      }
    }
  }

  let ok = !issues.any(i => i.blocking)
  { ok, checked: intents.length(), issues, blocked_units, }
}
