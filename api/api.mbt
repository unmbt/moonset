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
  extract_release_notes,
}

///|
/// Operational execution facade backed by injectable ExecutionHost ports.
pub using @executor {
  type NativeHost,
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
  native_host,
  utc_date,
  utc_datetime,
  apply_version_plan,
  apply_version_plan_with,
  format_files,
  format_files_with,
  commit_changes,
  commit_changes_with,
  recover_version,
  recover_version_with,
  stage_lockfiles,
  stage_lockfiles_with,
  pack_artifacts,
  pack_artifacts_with,
  pack_artifacts_for_target,
  pack_artifacts_for_target_with,
  verify_artifacts,
  verify_artifacts_with,
  publish_release,
  publish_release_with,
  publish_release_with_artifacts,
  publish_release_with_artifacts_with,
  publish_release_with_api,
  publish_release_with_api_with,
  create_tags,
  create_tags_with,
  run_doctor,
  run_doctor_with,
}
