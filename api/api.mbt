///|
/// Stable API entry points for Phase 5 integrations.
pub using @model {
  type UnitId,
  type ReleaseUnit,
  type WorkspaceSnapshot,
  type Changeset,
  type PreState,
  type ReleasePlan,
  type VersionPlan,
  type VersionOptions,
  type FileEdit,
  type ChangelogEntry,
  type TagIntent,
  type ReleaseState,
  type ApplyResult,
  type Diagnostic,
  type MoonsetError,
  type GeneratorPluginConfig,
  type DependencyKind,
  type DependencyEdge,
  type Ownership,
  type ArtifactIntent,
  type PackResult,
  type PublishTarget,
}

///|
/// The API contract version. It is independent of the CLI version.
pub let api_version : String = "1.0.0"

///|
pub using @engine {
  build_plan,
  build_version_plan,
  parse_changeset,
  parse_config,
  parse_pre_state,
  status_json,
}

///|
pub using @workspace {discover, type LoadedWorkspace}

///|
/// Experimental operational adapter contracts and JSONL plugin protocol.
pub using @adapters {
  type Capability,
  type CapabilityReport,
  type AdapterRegistry,
  type PluginSpec,
  type JsonlRequest,
  type JsonlResponse,
  type FileHost,
  type ProcessHost,
  type RegistryHost,
  run_jsonl,
  generator_result,
  trait DiscoveryPort,
  trait RangePort,
  trait OwnershipPort,
  trait LockfilePort,
  trait ArtifactPort,
  trait PublisherPort,
  trait OperationalAdapter,
}

///|
pub using @changelog {
  type ChangelogContext,
  type GeneratorRegistry,
  trait ChangelogGenerator,
}
