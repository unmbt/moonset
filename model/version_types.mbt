///|
/// A single planned file replacement.
pub(all) struct FileEdit {
  path : String
  kind : String
  owner : String
  before_hash : String
  after_text : String
  atomic : Bool
}

///|
/// One generated changelog entry, kept separate from its rendered document.
pub(all) struct ChangelogEntry {
  unit_id : String
  version : String
  date : String
  section : String
  text : String
  path : String
}

///|
/// A Git tag that can be created after a successful version application.
pub(all) struct TagIntent {
  unit_id : String
  version : String
  name : String
}

///|
/// Options shared by pure version-plan generation and the CLI.
pub(all) struct VersionOptions {
  dry_run : Bool
  no_changelog : Bool
  snapshot_tag : String?
}

///|
/// An executable version plan. Analysis plans remain represented by ReleasePlan.
pub(all) struct VersionPlan {
  schema_version : Int32
  stage : String
  executable : Bool
  fingerprint : String
  edits : Array[FileEdit]
  changelogs : Array[ChangelogEntry]
  tags : Array[TagIntent]
  consumed_changesets : Array[String]
  analysis : ReleasePlan
  generated_at : String?
}

///|
/// Persisted intent consumed by the tag command.
pub(all) struct ReleaseState {
  plan_fingerprint : String
  source_head : String?
  releases : Array[Release]
  tags : Array[TagIntent]
  consumed_changesets : Array[String]
}

///|
/// Result returned by an apply operation.
pub(all) struct ApplyResult {
  applied : Bool
  rolled_back : Bool
  journal : String?
  state : ReleaseState?
}

///|
/// Explicit workspace declaration for a mixed release domain.
pub(all) struct MixedWorkspaceSpec {
  id : String
  ecosystem : String
  root : String
  manager : String
  include_root : Bool
}

///|
/// Build/publish propagation that is separate from package dependencies.
pub(all) struct Bridge {
  consumer : UnitId
  producer : UnitId
  bump : Bump
  wait_for : String
}

///|
/// Per-unit policy override from mixed workspace configuration.
pub(all) struct UnitOverride {
  publish : Bool?
  publisher : String?
  tag_format : String?
}
