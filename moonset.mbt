// Main package file for your library code.
// Put public APIs and shared helpers here.
// Keep blocks small and focused for easy refactors.

///|
pub using @engine {
  build_plan,
  build_version_plan,
  parse_changeset,
  parse_config,
  parse_pre_state,
  render_builtin_changelog,
  status_json,
}

///|
pub using @workspace {discover, type LoadedWorkspace}

///|
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
}

///|
pub using @changelog {
  type ChangelogContext,
  type ReleaseLineContext,
  type GeneratorKind,
  type GeneratorRegistry,
  generator_kind,
  render,
}

///|
pub using @changelog {trait ChangelogGenerator}

///|
pub using @adapters {
  type JsonlRequest,
  type JsonlResponse,
  type PluginSpec,
  type Capability,
  type CapabilityReport,
  type PublisherRegistry,
  parse_request,
  parse_response,
  run_jsonl,
  require_capability,
  validate_conformance,
}

///|
pub using @api {api_version}

///|
pub using @api {
  type AdapterRegistry,
  type FileHost,
  type ProcessHost,
  type RegistryHost,
  trait DiscoveryPort,
  trait RangePort,
  trait OwnershipPort,
  trait LockfilePort,
  trait ArtifactPort,
  trait PublisherPort,
  trait OperationalAdapter,
  generator_result,
}
