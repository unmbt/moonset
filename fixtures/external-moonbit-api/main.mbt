///|
pub fn fixture_api_version() -> String {
  @api.api_version
}

///|
pub fn fixture_root_and_core_versions() -> (String, String) {
  (@moonset.api_version, @core.api_version)
}

///|
pub fn fixture_render() -> String {
  @changelog.render(
    @changelog.Builtin,
    @changelog.builtin_context("moonbit:fixture", "0.1.0", "2026-11-17", ""),
  )
}

///|
pub fn fixture_adapter_registry() -> Bool raise @api.MoonsetError {
  let registry = @api.AdapterRegistry::with_builtins()
  registry.require(@api.Ecosystem::Cargo, @api.Capability::Publish)
  true
}

///|
pub fn fixture_plan_and_markdown() -> (String, String) raise @core.MoonsetError {
  let cfg = @core.parse_config("{\"schemaVersion\":1,\"commit\":true}")
  let cs = @core.parse_changeset(
    "---\n\"acme/ext\": minor\n---\nExternal API contract feature\n",
    id="ext-1",
    path=".changeset/ext-1.md",
  )
  let snapshot : @core.WorkspaceSnapshot = {
    root: ".",
    workspaces: [
      {
        id: "moon",
        root: ".",
        ecosystem: @core.Ecosystem::MoonBit,
        manager: @core.PackageManager::Moon,
      },
    ],
    units: [
      {
        id: "moonbit:acme/ext",
        native_name: "acme/ext",
        ecosystem: @core.Ecosystem::MoonBit,
        workspace_id: "moon",
        root: "",
        manifest: "moon.mod",
        version_path: "moon.mod",
        version_field: "version",
        version: Some("0.1.0"),
        version_span: None,
        visibility: @core.Visibility::Public,
        publish: true,
        publish_config: None,
        dependencies: [],
      },
    ],
    ownership: [
      { path: "moon.mod", field: "version", owner: "moonbit:acme/ext", },
    ],
    unmanaged: [],
    config: cfg,
    sources: Map([("moon.mod", "name = \"acme/ext\"\nversion = \"0.1.0\"\n")]),
    changed_files: [],
    warnings: [],
    git_head: None,
  }
  let plan = @core.build_plan(snapshot, [cs])
  let md = @core.status_markdown(snapshot, plan, options={
    ..@core.CommentOptions::default(),
    marker_scope: Some("ext"),
  })
  (plan.releases[0].new_version, md)
}
