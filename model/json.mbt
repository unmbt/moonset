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
pub fn PreState::to_json(self : PreState) -> Json {
  {
    "mode": self.mode,
    "tag": self.tag,
    "initialVersions": self.initial_versions,
    "nextNumbers": self.next_numbers,
    "consumed": self.consumed,
  }
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
pub fn WorkspaceSnapshot::to_json(self : WorkspaceSnapshot) -> Json {
  {
    "root": self.root,
    "gitHead": nullable(self.git_head),
    "workspaces": self.workspaces.map(x => {
      (
        {
          "id": x.id,
          "root": x.root,
          "ecosystem": x.ecosystem,
          "manager": x.manager,
        } : Json)
    }),
    "units": self.units.map(x => {
      (
        {
          "unitId": x.id,
          "name": x.native_name,
          "ecosystem": x.ecosystem,
          "workspaceId": x.workspace_id,
          "root": x.root,
          "manifest": x.manifest,
          "version": nullable(x.version),
          "visibility": x.visibility,
          "publish": x.publish,
        } : Json)
    }),
    "ownership": self.ownership.map(x => {
      ({ "path": x.path, "field": x.field, "owner": x.owner } : Json)
    }),
    "unmanaged": self.unmanaged,
    "changedFiles": self.changed_files,
    "capabilities": ["moonbit-discovery", "analysis-plan", "pre-plan"],
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
    "releases": self.releases.map(x => x.to_json()),
    "changesets": self.changesets.map(x => x.to_json()),
    "dependencyUpdates": self.dependency_updates.map(x => {
      (
        {
          "consumer": x.consumer,
          "producer": x.producer,
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
    "releases": self.releases.map(x => x.to_json()),
    "tags": self.tags.map(x => x.to_json()),
    "consumedChangesets": self.consumed_changesets,
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
