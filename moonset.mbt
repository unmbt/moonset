// Main package file for your library code.
// Put public APIs and shared helpers here.
// Keep blocks small and focused for easy refactors.

///|
pub using @engine {
  type ArtifactTargetSpec,
  type ExecutionNode,
  type ExecutionDag,
  type ArtifactIssue,
  type ArtifactVerificationReport,
  type SnapshotConfig,
  type PublishTargetOverride,
  build_plan,
  build_version_plan,
  build_version_plan_with_metadata,
  changelog_contexts_with_metadata,
  render_release_pr_body,
  release_pr_title,
  build_execution_dag,
  parse_artifact_specs,
  verify_artifact_matrix,
  parse_snapshot_config,
  render_snapshot_version,
  resolve_formatter,
  formatter_supports_path,
  formatter_command,
  matches_changed_patterns,
  matches_unit_pattern,
  matches_ecosystem_range,
  rewrite_ecosystem_range,
  parse_target_mapping,
  resolve_target_override,
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
  extract_release_notes,
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

///|
pub using @executor {
  type PackOptions,
  type PublishOptions,
  type TagOptions,
  type TagResult,
  type DoctorCheck,
  type DoctorReport,
  type FormatResult,
  type ApiPublisher,
  type ApiPublisherRegistry,
  trait ExecutionHost,
  apply_version_plan,
  format_files,
  commit_changes,
  recover_version,
  stage_lockfiles,
  pack_artifacts,
  pack_artifacts_for_target,
  verify_artifacts,
  publish_release,
  publish_release_with_artifacts,
  publish_release_with_api,
  create_tags,
  run_doctor,
}
