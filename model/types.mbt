///|
/// Canonical identity: ecosystem:nativeName. Validated at input boundaries.
pub type UnitId = String

///|
/// UTF-8 byte offset span inside a manifest source file.
#derive(Eq, Debug)
pub(all) struct TextSpan {
  start : Int32
  end : Int32
}

///|
pub extend TextSpan with Eq::{equal, not_equal}

///|
pub extend TextSpan with Debug::{to_repr}

///|
#derive(Eq, Debug)
pub(all) enum Ecosystem {
  MoonBit
  Npm
  Cargo
}

///|
pub extend Ecosystem with Eq::{equal, not_equal}

///|
pub extend Ecosystem with Debug::{to_repr}

///|
pub fn Ecosystem::text(self : Ecosystem) -> String {
  match self {
    MoonBit => "moonbit"
    Npm => "npm"
    Cargo => "cargo"
  }
}

///|
pub fn Ecosystem::parse(value : String) -> Ecosystem? {
  match value {
    "moonbit" => Some(MoonBit)
    "npm" => Some(Npm)
    "cargo" => Some(Cargo)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum PackageManager {
  Moon
  Npm
  Pnpm
  Yarn
  Cargo
}

///|
pub extend PackageManager with Eq::{equal, not_equal}

///|
pub extend PackageManager with Debug::{to_repr}

///|
pub fn PackageManager::text(self : PackageManager) -> String {
  match self {
    Moon => "moon"
    Npm => "npm"
    Pnpm => "pnpm"
    Yarn => "yarn"
    Cargo => "cargo"
  }
}

///|
pub fn PackageManager::parse(value : String) -> PackageManager? {
  match value {
    "moon" => Some(Moon)
    "npm" => Some(Npm)
    "pnpm" => Some(Pnpm)
    "yarn" => Some(Yarn)
    "cargo" => Some(Cargo)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum Visibility {
  Public
  Restricted
  Private
}

///|
pub extend Visibility with Eq::{equal, not_equal}

///|
pub extend Visibility with Debug::{to_repr}

///|
pub fn Visibility::text(self : Visibility) -> String {
  match self {
    Public => "public"
    Restricted => "restricted"
    Private => "private"
  }
}

///|
pub fn Visibility::parse(value : String) -> Visibility? {
  match value {
    "public" => Some(Public)
    "restricted" => Some(Restricted)
    "private" => Some(Private)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum PreMode {
  Pre
  Exit
}

///|
pub extend PreMode with Eq::{equal, not_equal}

///|
pub extend PreMode with Debug::{to_repr}

///|
pub fn PreMode::text(self : PreMode) -> String {
  match self {
    Pre => "pre"
    Exit => "exit"
  }
}

///|
pub fn PreMode::parse(value : String) -> PreMode? {
  match value {
    "pre" | "active" => Some(Pre)
    "exit" => Some(Exit)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum UpdateDependents {
  OutOfRange
  Always
}

///|
pub extend UpdateDependents with Eq::{equal, not_equal}

///|
pub extend UpdateDependents with Debug::{to_repr}

///|
pub fn UpdateDependents::text(self : UpdateDependents) -> String {
  match self {
    OutOfRange => "out-of-range"
    Always => "always"
  }
}

///|
pub fn UpdateDependents::parse(value : String) -> UpdateDependents? {
  match value {
    "out-of-range" => Some(OutOfRange)
    "always" => Some(Always)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum Access {
  Public
  Restricted
}

///|
pub extend Access with Eq::{equal, not_equal}

///|
pub extend Access with Debug::{to_repr}

///|
pub fn Access::text(self : Access) -> String {
  match self {
    Public => "public"
    Restricted => "restricted"
  }
}

///|
pub fn Access::parse(value : String) -> Access? {
  match value {
    "public" => Some(Public)
    "restricted" => Some(Restricted)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum CommitMode {
  Never
  Add
  Version
  Both
}

///|
pub extend CommitMode with Eq::{equal, not_equal}

///|
pub extend CommitMode with Debug::{to_repr}

///|
pub fn CommitMode::text(self : CommitMode) -> String {
  match self {
    Never => "never"
    Add => "add"
    Version => "version"
    Both => "both"
  }
}

///|
pub fn CommitMode::parse(value : String) -> CommitMode? {
  match value {
    "never" => Some(Never)
    "add" => Some(Add)
    "version" => Some(Version)
    "both" => Some(Both)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum LockfileMode {
  Refresh
  VerifyOnly
}

///|
pub extend LockfileMode with Eq::{equal, not_equal}

///|
pub extend LockfileMode with Debug::{to_repr}

///|
pub fn LockfileMode::text(self : LockfileMode) -> String {
  match self {
    Refresh => "refresh"
    VerifyOnly => "verify-only"
  }
}

///|
pub fn LockfileMode::parse(value : String) -> LockfileMode? {
  match value {
    "refresh" => Some(Refresh)
    "verify-only" => Some(VerifyOnly)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum BridgeWaitFor {
  Build
  Publish
}

///|
pub extend BridgeWaitFor with Eq::{equal, not_equal}

///|
pub extend BridgeWaitFor with Debug::{to_repr}

///|
pub fn BridgeWaitFor::text(self : BridgeWaitFor) -> String {
  match self {
    Build => "build"
    Publish => "publish"
  }
}

///|
pub fn BridgeWaitFor::parse(value : String) -> BridgeWaitFor? {
  match value {
    "build" => Some(Build)
    "publish" => Some(Publish)
    _ => None
  }
}

///|
#derive(Eq, Debug)
pub(all) enum MixedMode {
  Coexist
  Unified
}

///|
pub extend MixedMode with Eq::{equal, not_equal}

///|
pub extend MixedMode with Debug::{to_repr}

///|
pub fn MixedMode::text(self : MixedMode) -> String {
  match self {
    Coexist => "coexist"
    Unified => "unified"
  }
}

///|
pub fn MixedMode::parse(value : String) -> MixedMode? {
  match value {
    "coexist" => Some(Coexist)
    "unified" => Some(Unified)
    _ => None
  }
}

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
pub fn Bump::parse(value : String) -> Bump? {
  match value {
    "none" => Some(None)
    "patch" => Some(Patch)
    "minor" => Some(Minor)
    "major" => Some(Major)
    _ => None
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
  target_condition : String?
}

///|
#derive(Eq, Debug)
pub(all) enum DependencyKind {
  Runtime
  Build
  Development
  Optional
  Peer
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
    Development => "development"
    Optional => "optional"
    Peer => "peer"
  }
}

///|
pub fn DependencyKind::parse(value : String) -> DependencyKind? {
  match value {
    "runtime" => Some(Runtime)
    "build" => Some(Build)
    "development" => Some(Development)
    "optional" => Some(Optional)
    "peer" => Some(Peer)
    _ => None
  }
}

///|
/// Per-package publishConfig metadata extracted from native manifests (e.g. npm package.json).
#derive(Eq, Debug)
pub(all) struct PublishConfig {
  access : Access?
  registry : String?
  directory : String?
}

///|
pub extend PublishConfig with Eq::{equal, not_equal}

///|
pub extend PublishConfig with Debug::{to_repr}

///|
pub(all) struct ReleaseUnit {
  id : UnitId
  native_name : String
  ecosystem : Ecosystem
  workspace_id : String
  root : String
  manifest : String
  version_path : String
  version_field : String
  version : String?
  version_span : TextSpan?
  visibility : Visibility
  publish : Bool
  publish_config : PublishConfig?
  dependencies : Array[DependencyEdge]
}

///|
pub(all) struct EcosystemWorkspace {
  id : String
  root : String
  ecosystem : Ecosystem
  manager : PackageManager
}

///|
pub(all) struct Ownership {
  path : String
  field : String
  owner : UnitId
}

///|
pub(all) struct ChangelogConfig {
  enabled : Bool
  generator : String
  file : String
}

///|
pub fn ChangelogConfig::default() -> ChangelogConfig {
  { enabled: true, generator: "builtin", file: "CHANGELOG.md", }
}

///|
pub(all) struct CommitConfig {
  mode : CommitMode
  add_message : String
  version_message : String
  skip_ci : Bool
}

///|
pub fn CommitConfig::default() -> CommitConfig {
  {
    mode: Never,
    add_message: "chore: add changeset",
    version_message: "chore: release",
    skip_ci: false,
  }
}

///|
pub(all) struct PrivatePackagesConfig {
  version : Bool
  tag : Bool
  publish : Bool
}

///|
pub fn PrivatePackagesConfig::default() -> PrivatePackagesConfig {
  { version: false, tag: false, publish: false, }
}

///|
pub(all) struct PreConfig {
  file : String
  directory : String
}

///|
pub fn PreConfig::default() -> PreConfig {
  { file: ".changeset/pre.json", directory: ".changeset/pre", }
}

///|
pub(all) struct SnapshotConfig {
  enabled : Bool
  use_calculated_version : Bool
  prerelease_template : String
}

///|
pub fn SnapshotConfig::default() -> SnapshotConfig {
  {
    enabled: true,
    use_calculated_version: false,
    prerelease_template: "{tag}-{datetime}",
  }
}

///|
pub(all) struct TagConfig {
  create : Bool
  after_publish : Bool
  format : String
  push : Bool
}

///|
pub fn TagConfig::default() -> TagConfig {
  { create: true, after_publish: true, format: "auto", push: false, }
}

///|
pub(all) struct PublisherConfig {
  kind : String
  registry : String
  dry_run_first : Bool
  command : Array[String]
  token_env : String?
}

///|
pub fn PublisherConfig::default() -> PublisherConfig {
  {
    kind: "moon",
    registry: "default",
    dry_run_first: true,
    command: [],
    token_env: None,
  }
}

///|
pub(all) struct GithubConfig {
  repo : String?
  links : Bool
  thanks : Bool
}

///|
pub fn GithubConfig::default() -> GithubConfig {
  { repo: None, links: true, thanks: true, }
}

///|
/// Declared multi-platform artifact specification for a release unit.
#derive(Eq, Debug)
pub(all) struct ArtifactTargetSpec {
  target : String
  linked_package : UnitId?
  required : Bool
  path : String?
}

///|
pub extend ArtifactTargetSpec with Eq::{equal, not_equal}

///|
pub extend ArtifactTargetSpec with Debug::{to_repr}

///|
pub(all) struct MixedWorkspacesConfig {
  mode : MixedMode
  workspaces : Array[MixedWorkspaceSpec]
  bridges : Array[Bridge]
  unit_overrides : Map[String, UnitOverride]
  lockfiles : LockfileMode
}

///|
pub(all) struct Config {
  fixed : Array[Array[UnitId]]
  linked : Array[Array[UnitId]]
  ignore : Array[UnitId]
  update_dependencies : Bump
  update_dependents : UpdateDependents
  only_update_peer_dependents_when_out_of_range : Bool
  bump_versions_with_workspace_protocol_only : Bool
  also_skip_dependents_of_skipped : Bool
  changed_patterns : Array[String]
  formatter : String
  format_mode : String
  access : Access
  base_branch : String
  changelog : ChangelogConfig
  commit : CommitConfig
  private_packages : PrivatePackagesConfig
  pre : PreConfig
  snapshot : SnapshotConfig
  tag : TagConfig
  publisher : PublisherConfig
  github : GithubConfig
  generators : Map[String, GeneratorPluginConfig]
  mixed : MixedWorkspacesConfig?
}

///|
/// Explicitly registered executable used by the external generator protocol.
pub(all) struct GeneratorPluginConfig {
  program : String
  args : Array[String]
  allowed_programs : Array[String]
  environment : Array[String]
  timeout_ms : Int32
  max_output_bytes : Int32
  protocol : String
}

///|
pub fn Config::default() -> Config {
  {
    fixed: [],
    linked: [],
    ignore: [],
    update_dependencies: Patch,
    update_dependents: OutOfRange,
    only_update_peer_dependents_when_out_of_range: false,
    bump_versions_with_workspace_protocol_only: false,
    also_skip_dependents_of_skipped: false,
    changed_patterns: ["**"],
    formatter: "builtin",
    format_mode: "auto",
    access: Public,
    base_branch: "main",
    changelog: ChangelogConfig::default(),
    commit: CommitConfig::default(),
    private_packages: PrivatePackagesConfig::default(),
    pre: PreConfig::default(),
    snapshot: SnapshotConfig::default(),
    tag: TagConfig::default(),
    publisher: PublisherConfig::default(),
    github: GithubConfig::default(),
    generators: Map([]),
    mixed: None,
  }
}

///|
pub fn Config::is_mixed(self : Config) -> Bool {
  self.mixed is Some(_)
}

///|
pub fn Config::mixed_workspaces(self : Config) -> Array[MixedWorkspaceSpec] {
  match self.mixed {
    Some(m) => m.workspaces
    None => []
  }
}

///|
pub fn Config::bridges(self : Config) -> Array[Bridge] {
  match self.mixed {
    Some(m) => m.bridges
    None => []
  }
}

///|
pub fn Config::unit_overrides(self : Config) -> Map[String, UnitOverride] {
  match self.mixed {
    Some(m) => m.unit_overrides
    None => Map([])
  }
}

///|
pub fn Config::lockfiles(self : Config) -> LockfileMode {
  match self.mixed {
    Some(m) => m.lockfiles
    None => Refresh
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
  in_pre_dir : Bool
}

///|
/// Changesets v3 minimal prerelease state (`{ mode: "pre" | "exit", tag }`).
/// `legacy_consumed` is populated only when migrating legacy v2 pre.json files.
pub(all) struct PreState {
  mode : PreMode
  tag : String
  legacy_consumed : Array[String]
}

///|
pub fn PreState::new(mode : PreMode, tag : String) -> PreState {
  { mode, tag, legacy_consumed: [], }
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
  kind : DependencyKind
  producer_version : String
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
  is_snapshot : Bool
}
