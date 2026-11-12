///|
/// Canonical identity: ecosystem:nativeName. Validated at input boundaries.
pub type UnitId = String

///|
#derive(Eq, Debug)
pub(all) enum Bump {
  None
  Patch
  Minor
  Major
}

///|
pub extend Bump with Eq::{equal, not_equal}

///|
pub extend Bump with Debug::{to_repr}

///|
pub fn Bump::rank(self : Bump) -> Int32 {
  match self {
    None => 0
    Patch => 1
    Minor => 2
    Major => 3
  }
}

///|
pub fn Bump::text(self : Bump) -> String {
  match self {
    None => "none"
    Patch => "patch"
    Minor => "minor"
    Major => "major"
  }
}

///|
#derive(Debug)
pub(all) struct Diagnostic {
  code : String
  message : String
  path : String
  line : Int32
  column : Int32
  json_path : String?
}

///|
pub extend Diagnostic with Debug::{to_repr}

///|
pub(all) suberror MoonsetError {
  Invalid(Diagnostic)
  Io(String)
}

///|
pub(all) struct DependencyEdge {
  producer : UnitId
  requirement : String
  kind : DependencyKind
  path : String
  start : Int32
  end : Int32
}

///|
#derive(Eq, Debug)
pub(all) enum DependencyKind {
  Runtime
  Build
}

///|
pub extend DependencyKind with Eq::{equal, not_equal}

///|
pub extend DependencyKind with Debug::{to_repr}

///|
pub fn DependencyKind::text(self : DependencyKind) -> String {
  match self {
    Runtime => "runtime"
    Build => "build"
  }
}

///|
pub(all) struct ReleaseUnit {
  id : UnitId
  native_name : String
  ecosystem : String
  workspace_id : String
  root : String
  manifest : String
  version : String?
  visibility : String
  publish : Bool
  dependencies : Array[DependencyEdge]
}

///|
pub(all) struct EcosystemWorkspace {
  id : String
  root : String
  ecosystem : String
  manager : String
}

///|
pub(all) struct Ownership {
  path : String
  field : String
  owner : UnitId
}

///|
pub(all) struct Config {
  fixed : Array[Array[UnitId]]
  linked : Array[Array[UnitId]]
  ignore : Array[UnitId]
  update_dependencies : Bump
  update_dependents : String
  changed_patterns : Array[String]
  pre_file : String
  mixed : Bool
  formatter : String
  changelog : String
  github : String?
  access : String
  base_branch : String
  private_version : Bool
  private_tag : Bool
  private_publish : Bool
  changelog_file : String
  tag_create : Bool
  tag_after_publish : Bool
  tag_format : String
  tag_push : Bool
  lockfiles : String
  mixed_workspaces : Array[MixedWorkspaceSpec]
  bridges : Array[Bridge]
  unit_overrides : Map[String, UnitOverride]
  raw : Json
}

///|
pub fn Config::default() -> Config {
  {
    fixed: [],
    linked: [],
    ignore: [],
    update_dependencies: Patch,
    update_dependents: "out-of-range",
    changed_patterns: ["**"],
    pre_file: ".changeset/pre.json",
    mixed: false,
    formatter: "builtin",
    changelog: "builtin",
    github: None,
    access: "public",
    base_branch: "main",
    private_version: false,
    private_tag: false,
    private_publish: false,
    changelog_file: "CHANGELOG.md",
    tag_create: true,
    tag_after_publish: true,
    tag_format: "auto",
    tag_push: false,
    lockfiles: "refresh",
    mixed_workspaces: [],
    bridges: [],
    unit_overrides: Map([]),
    raw: Json::empty_object(),
  }
}

///|
/// A changeset assembled by the CLI before it is formatted and written.
pub(all) struct ChangesetDraft {
  releases : Array[Change]
  summary : String
}

///|
pub(all) struct WorkspaceSnapshot {
  root : String
  workspaces : Array[EcosystemWorkspace]
  units : Array[ReleaseUnit]
  ownership : Array[Ownership]
  unmanaged : Array[String]
  config : Config
  sources : Map[String, String]
  changed_files : Array[String]
  warnings : Array[Diagnostic]
  git_head : String?
}

///|
pub(all) struct Change {
  unit_id : UnitId
  bump : Bump
}

///|
pub(all) struct Changeset {
  id : String
  releases : Array[Change]
  summary : String
  path : String
}

///|
pub(all) struct PreState {
  mode : String
  tag : String
  initial_versions : Map[UnitId, String]
  next_numbers : Map[UnitId, Int32]
  consumed : Array[String]
}

///|
pub(all) struct Release {
  unit_id : UnitId
  old_version : String
  new_version : String
  level : Bump
  reasons : Array[String]
  changesets : Array[String]
  publish : Bool
}

///|
pub(all) struct DependencyIntent {
  consumer : UnitId
  producer : UnitId
  path : String
  old_requirement : String
  new_requirement : String
  start : Int32
  end : Int32
}

///|
pub(all) struct ReleasePlan {
  fingerprint : String
  releases : Array[Release]
  dependency_updates : Array[DependencyIntent]
  affected_paths : Array[String]
  changesets : Array[Changeset]
  next_pre_state : PreState?
  warnings : Array[Diagnostic]
  generated_at : String?
}
