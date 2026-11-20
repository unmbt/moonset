///|
pub fn diagnostic(
  code : String,
  message : String,
  path~ : String = "",
  line~ : Int32 = 1,
  column~ : Int32 = 1,
  json_path? : String,
) -> Diagnostic {
  { code, message, path, line, column, json_path, }
}

///|
pub fn Diagnostic::to_json(self : Diagnostic) -> Json {
  {
    "code": self.code,
    "message": self.message,
    "path": self.path,
    "line": self.line,
    "column": self.column,
    "jsonPath": nullable(self.json_path),
  }
}

///|
/// Changesets v3 minimal pre.json serialization.
pub fn PreState::to_json(self : PreState) -> Json {
  { "mode": self.mode.text(), "tag": self.tag }
}

///|
pub fn Changeset::to_json(self : Changeset) -> Json {
  {
    "id": self.id,
    "path": self.path,
    "summary": self.summary,
    "releases": self.releases.map(x => {
      ({ "unitId": x.unit_id, "type": x.bump.text() } : Json)
    }),
  }
}

///|
pub fn Release::to_json(self : Release) -> Json {
  {
    "unitId": self.unit_id,
    "oldVersion": self.old_version,
    "newVersion": self.new_version,
    "level": self.level.text(),
    "reasons": self.reasons,
    "changesets": self.changesets,
    "publish": self.publish,
  }
}

///|
pub fn Config::to_json(self : Config) -> Json {
  let mixed_json : Json = match self.mixed {
    Some(m) => {
      let units_map : Map[String, Json] = Map([])
      for id, ov in m.unit_overrides {
        let fields : Map[String, Json] = Map([])
        if ov.publish is Some(p) {
          fields["publish"] = Json::boolean(p)
        }
        if ov.publisher is Some(pub_name) {
          fields["publisher"] = Json::string(pub_name)
        }
        if ov.tag_format is Some(fmt) {
          fields["tagFormat"] = Json::string(fmt)
        }
        if !ov.artifacts.is_empty() {
          fields["artifacts"] = Json::array(
            ov.artifacts.map(a => {
              let af : Map[String, Json] = Map([
                ("target", Json::string(a.target)),
                ("required", Json::boolean(a.required)),
              ])
              if a.linked_package is Some(pkg) {
                af["package"] = Json::string(pkg)
              }
              if a.path is Some(p) {
                af["path"] = Json::string(p)
              }
              Json::object(af)
            }),
          )
        }
        units_map[id] = Json::object(fields)
      }
      {
        "mode": m.mode.text(),
        "workspaces": m.workspaces.map(ws => {
          (
            {
              "id": ws.id,
              "ecosystem": ws.ecosystem.text(),
              "root": ws.root,
              "manager": ws.manager.text(),
              "includeRoot": ws.include_root,
            } : Json)
        }),
        "bridges": m.bridges.map(b => {
          (
            {
              "consumer": b.consumer,
              "producer": b.producer,
              "bump": b.bump.text(),
              "waitFor": b.wait_for.text(),
            } : Json)
        }),
        "units": Json::object(units_map),
        "lockfiles": m.lockfiles.text(),
      }
    }
    None => Json::null()
  }
  {
    "fixed": self.fixed,
    "linked": self.linked,
    "ignore": self.ignore,
    "updateInternalDependencies": self.update_dependencies.text(),
    "updateInternalDependents": self.update_dependents.text(),
    "onlyUpdatePeerDependentsWhenOutOfRange": self.only_update_peer_dependents_when_out_of_range,
    "bumpVersionsWithWorkspaceProtocolOnly": self.bump_versions_with_workspace_protocol_only,
    "changedFilePatterns": self.changed_patterns,
    "formatter": self.formatter,
    "format": self.format_mode,
    "access": self.access.text(),
    "baseBranch": self.base_branch,
    "changelog": {
      "enabled": self.changelog.enabled,
      "generator": self.changelog.generator,
      "file": self.changelog.file,
    },
    "commit": {
      "mode": self.commit.mode.text(),
      "addMessage": self.commit.add_message,
      "versionMessage": self.commit.version_message,
    },
    "privatePackages": {
      "version": self.private_packages.version,
      "tag": self.private_packages.tag,
      "publish": self.private_packages.publish,
    },
    "pre": { "file": self.pre.file, "directory": self.pre.directory },
    "snapshot": {
      "enabled": self.snapshot.enabled,
      "useCalculatedVersion": self.snapshot.use_calculated_version,
      "prereleaseTemplate": self.snapshot.prerelease_template,
    },
    "tag": {
      "create": self.tag.create,
      "afterPublish": self.tag.after_publish,
      "format": self.tag.format,
      "push": self.tag.push,
    },
    "publisher": {
      "kind": self.publisher.kind,
      "registry": self.publisher.registry,
      "dryRunFirst": self.publisher.dry_run_first,
      "command": self.publisher.command,
      "tokenEnv": nullable(self.publisher.token_env),
    },
    "github": {
      "repo": nullable(self.github.repo),
      "links": self.github.links,
      "thanks": self.github.thanks,
    },
    "mixedWorkspaces": mixed_json,
  }
}

///|
fn snapshot_capabilities(snapshot : WorkspaceSnapshot) -> Array[String] {
  let caps : Array[String] = ["analysis-plan", "pre-plan", "snapshot-plan"]
  let has_moon = snapshot.workspaces.any(w => w.ecosystem == MoonBit) ||
    snapshot.units.any(u => u.ecosystem == MoonBit)
  let has_npm = snapshot.workspaces.any(w => w.ecosystem == Npm) ||
    snapshot.units.any(u => u.ecosystem == Npm)
  let has_cargo = snapshot.workspaces.any(w => w.ecosystem == Cargo) ||
    snapshot.units.any(u => u.ecosystem == Cargo)
  if has_moon {
    caps.push("moonbit-discovery")
  }
  if has_npm {
    caps.push("npm-discovery")
    caps.push("npm-lockfiles")
  }
  if has_cargo {
    caps.push("cargo-discovery")
    caps.push("cargo-lockfiles")
  }
  if snapshot.config.is_mixed() {
    caps.push("mixed-workspaces")
  }
  caps.sort()
  caps
}

///|
pub fn WorkspaceSnapshot::to_json(self : WorkspaceSnapshot) -> Json {
  {
    "root": self.root,
    "gitHead": nullable(self.git_head),
    "workspaces": self.workspaces.map(x => {
      (
        {
          "id": x.id,
          "root": x.root,
          "ecosystem": x.ecosystem.text(),
          "manager": x.manager.text(),
        } : Json)
    }),
    "units": self.units.map(x => {
      (
        {
          "unitId": x.id,
          "name": x.native_name,
          "ecosystem": x.ecosystem.text(),
          "workspaceId": x.workspace_id,
          "root": x.root,
          "manifest": x.manifest,
          "version": nullable(x.version),
          "visibility": x.visibility.text(),
          "publish": x.publish,
        } : Json)
    }),
    "ownership": self.ownership.map(x => {
      ({ "path": x.path, "field": x.field, "owner": x.owner } : Json)
    }),
    "unmanaged": self.unmanaged,
    "changedFiles": self.changed_files,
    "capabilities": snapshot_capabilities(self),
  }
}

///|
pub fn ReleasePlan::to_json(self : ReleasePlan) -> Json {
  {
    "schemaVersion": 1,
    "stage": "analysis",
    "executable": false,
    "fingerprint": self.fingerprint,
    "generatedAt": nullable(self.generated_at),
    "isSnapshot": self.is_snapshot,
    "releases": self.releases.map(x => x.to_json()),
    "changesets": self.changesets.map(x => x.to_json()),
    "dependencyUpdates": self.dependency_updates.map(x => {
      (
        {
          "consumer": x.consumer,
          "producer": x.producer,
          "kind": x.kind.text(),
          "producerVersion": x.producer_version,
          "path": x.path,
          "oldRequirement": x.old_requirement,
          "newRequirement": x.new_requirement,
          "start": x.start,
          "end": x.end,
        } : Json)
    }),
    "affectedPaths": self.affected_paths,
    "nextPreState": match self.next_pre_state {
      Some(state) => state.to_json()
      None => Json::null()
    },
    "warnings": self.warnings.map(x => x.to_json()),
  }
}

///|
pub fn FileEdit::to_json(self : FileEdit) -> Json {
  {
    "path": self.path,
    "kind": self.kind,
    "owner": self.owner,
    "beforeHash": self.before_hash,
    "afterText": self.after_text,
    "atomic": self.atomic_write,
  }
}

///|
pub fn ChangelogEntry::to_json(self : ChangelogEntry) -> Json {
  {
    "unitId": self.unit_id,
    "version": self.version,
    "date": self.date,
    "section": self.section,
    "text": self.text,
    "path": self.path,
    "generator": self.generator,
    "metadata": self.metadata,
  }
}

///|
pub fn TagIntent::to_json(self : TagIntent) -> Json {
  { "unitId": self.unit_id, "version": self.version, "name": self.name }
}

///|
pub fn VersionPlan::to_json(self : VersionPlan) -> Json {
  {
    "schemaVersion": self.schema_version,
    "stage": self.stage,
    "executable": self.executable,
    "fingerprint": self.fingerprint,
    "edits": self.edits.map(x => x.to_json()),
    "changelogs": self.changelogs.map(x => x.to_json()),
    "tags": self.tags.map(x => x.to_json()),
    "consumedChangesets": self.consumed_changesets,
    "analysis": self.analysis.to_json(),
    "generatedAt": nullable(self.generated_at),
  }
}

///|
pub fn ReleaseState::to_json(self : ReleaseState) -> Json {
  {
    "planFingerprint": self.plan_fingerprint,
    "sourceHead": nullable(self.source_head),
    "isSnapshot": self.is_snapshot,
    "releases": self.releases.map(x => x.to_json()),
    "tags": self.tags.map(x => x.to_json()),
    "consumedChangesets": self.consumed_changesets,
  }
}

///|
fn json_string_array(value : Json) -> Array[String] {
  match value {
    Array(items) =>
      items.filter_map(x => {
        match x {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
}

///|
/// Canonical ReleaseState JSON parser shared across pack, publish, tag, and CLI.
pub fn ReleaseState::from_json(
  json : Json,
  path~ : String = ".moonset/release-state.json",
) -> ReleaseState raise MoonsetError {
  guard json is Object(fields) else {
    raise Invalid(
      diagnostic(
        "invalid-release-state",
        "Expected release-state JSON object",
        path~,
      ),
    )
  }
  let plan_fingerprint = match fields.get("planFingerprint") {
    Some(String(s)) => s
    _ =>
      raise Invalid(
        diagnostic(
          "invalid-release-state",
          "Missing planFingerprint in release-state.json",
          path~,
        ),
      )
  }
  let source_head = match fields.get("sourceHead") {
    Some(String(s)) if s != "" => Some(s)
    _ => None
  }
  let is_snapshot = match fields.get("isSnapshot") {
    Some(True) => true
    _ => false
  }
  let releases : Array[Release] = []
  match fields.get("releases") {
    Some(Array(items)) =>
      for item in items {
        guard item
          is {
            "unitId": String(unit_id),
            "oldVersion": String(old_version),
            "newVersion": String(new_version),
            ..
          } else {
          raise Invalid(
            diagnostic(
              "invalid-release-state",
              "Invalid release entry in release-state.json",
              path~,
            ),
          )
        }
        let level = match item {
          { "level": String(l), .. } => Bump::parse(l).unwrap_or(Patch)
          _ => Patch
        }
        let reasons = match item {
          { "reasons": arr, .. } => json_string_array(arr)
          _ => []
        }
        let changesets = match item {
          { "changesets": arr, .. } => json_string_array(arr)
          _ => []
        }
        let publish = match item {
          { "publish": False, .. } => false
          _ => true
        }
        releases.push({
          unit_id,
          old_version,
          new_version,
          level,
          reasons,
          changesets,
          publish,
        })
      }
    _ => ()
  }
  let tags : Array[TagIntent] = []
  match fields.get("tags") {
    Some(Array(items)) =>
      for item in items {
        if item
          is {
            "unitId": String(unit_id),
            "version": String(version),
            "name": String(name),
            ..
          } {
          tags.push({ unit_id, version, name, })
        }
      }
    _ => ()
  }
  let consumed_changesets = match fields.get("consumedChangesets") {
    Some(arr) => json_string_array(arr)
    None => []
  }
  {
    plan_fingerprint,
    source_head,
    is_snapshot,
    releases,
    tags,
    consumed_changesets,
  }
}

///|
pub fn ApplyResult::to_json(self : ApplyResult) -> Json {
  {
    "applied": self.applied,
    "rolledBack": self.rolled_back,
    "journal": nullable(self.journal),
    "state": match self.state {
      Some(value) => value.to_json()
      None => Json::null()
    },
  }
}

///|
pub fn ArtifactIntent::to_json(self : ArtifactIntent) -> Json {
  {
    "id": self.id,
    "unitId": self.unit_id,
    "version": self.version,
    "target": self.target,
    "required": self.required,
    "sourceCommit": nullable(self.source_commit),
    "expectedHash": nullable(self.expected_hash),
    "path": nullable(self.path),
  }
}

///|
pub fn PackResult::to_json(self : PackResult) -> Json {
  {
    "artifactId": self.artifact_id,
    "unitId": self.unit_id,
    "version": self.version,
    "target": self.target,
    "archivePath": self.archive_path,
    "sourceCommit": nullable(self.source_commit),
    "contentHash": self.content_hash,
    "verified": self.verified,
  }
}

///|
pub fn PublishTarget::to_json(self : PublishTarget) -> Json {
  {
    "unitId": self.unit_id,
    "version": self.version,
    "target": self.target,
    "registry": self.registry,
    "publisher": self.publisher,
    "artifactId": nullable(self.artifact_id),
    "required": self.required,
  }
}

///|
pub fn PublishState::text(self : PublishState) -> String {
  match self {
    Pending => "pending"
    Preflighted => "preflighted"
    Published => "published"
    Skipped => "skipped"
    Failed => "failed"
    Blocked => "blocked"
    Unknown => "unknown"
  }
}

///|
pub fn PublishStatus::to_json(self : PublishStatus) -> Json {
  {
    "planId": self.plan_id,
    "unitId": self.unit_id,
    "version": self.version,
    "target": self.target,
    "registry": self.registry,
    "state": self.state.text(),
    "digest": nullable(self.digest),
    "externalId": nullable(self.external_id),
    "message": nullable(self.message),
  }
}

///|
pub fn PublishResult::to_json(self : PublishResult) -> Json {
  {
    "schemaVersion": self.schema_version,
    "planId": self.plan_id,
    "dryRun": self.dry_run,
    "complete": self.complete,
    "statuses": self.statuses.map(x => x.to_json()),
    "recoveryPath": nullable(self.recovery_path),
  }
}

///|
/// Stable compact JSON: object keys sorted, arrays retain their semantic order.
pub fn canonical_json(value : Json) -> String {
  match value {
    Object(fields) => {
      let keys = fields.keys().collect()
      keys.sort()
      "{" +
      keys
      .map(key => {
        Json::string(key).stringify() + ":" + canonical_json(fields[key])
      })
      .join(",") +
      "}"
    }
    Array(items) => "[" + items.map(canonical_json).join(",") + "]"
    _ => value.stringify()
  }
}

///|
/// Non-cryptographic analysis identity, not an execution authorization digest.
pub fn fingerprint(value : Json) -> String {
  let bytes = @utf8.encode(canonical_json(value))
  let mut hash : UInt64 = 14695981039346656037UL
  for byte in bytes {
    hash = (hash ^ byte.to_uint64()) * 1099511628211UL
  }
  "fnv1a64:" + hash.to_string(radix=16)
}

///|
fn nullable(value : String?) -> Json {
  match value {
    Some(text) => Json::string(text)
    None => Json::null()
  }
}
