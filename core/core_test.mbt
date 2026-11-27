///|
test "wasm-gc pure core facade plans, renders markdown, and runs line hooks" {
  assert_eq(@core.api_version, "2.0.0")
  let cfg = @core.parse_config(
    "{\"schemaVersion\":1,\"commit\":true,\"alsoSkipDependentsOfSkipped\":true}",
  )
  assert_eq(cfg.commit.mode, @core.CommitMode::Both)
  assert_true(cfg.also_skip_dependents_of_skipped)
  assert_eq(@core.detect_auto_formatter(["biome.json", "README.md"]), "biome")
  assert_eq(
    @core.comment_marker(scope="packages/js"),
    "<!-- moonset-bot:changeset-check:packages/js -->",
  )
  let cs = @core.parse_changeset(
    "---\n\"acme/lib\": minor\n---\n\nAdd wasm-gc core facade.\n",
    id="wasm-core",
    path=".changeset/wasm-core.md",
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
        id: "moonbit:acme/lib",
        native_name: "acme/lib",
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
      { path: "moon.mod", field: "version", owner: "moonbit:acme/lib", },
    ],
    unmanaged: [],
    config: cfg,
    sources: Map([("moon.mod", "name = \"acme/lib\"\nversion = \"0.1.0\"\n")]),
    changed_files: [],
    warnings: [],
    git_head: None,
  }
  let plan = @core.build_plan(snapshot, [cs])
  assert_eq(plan.releases.length(), 1)
  assert_eq(plan.releases[0].new_version, "0.2.0")
  let md = @core.status_markdown(snapshot, plan, options={
    ..@core.CommentOptions::default(),
    marker_scope: Some("moon"),
  })
  assert_true(md.contains("<!-- moonset-bot:changeset-check:moon -->"))
  let hooked = @core.render_with_line_hooks(
    {
      unit_id: "moonbit:acme/lib",
      version: "0.2.0",
      date: "2026-11-27",
      lines: [
        {
          changeset_id: "wasm-core",
          summary: "Add core facade",
          unit_id: "moonbit:acme/lib",
          bump: @core.Bump::Minor,
          old_version: "0.1.0",
          new_version: "0.2.0",
          commit: None,
          pull_request: None,
          authors: [],
        },
      ],
      dependency_lines: [],
      existing: "",
      repository: None,
      links: true,
      thanks: true,
      server_url: "https://github.com",
    },
    {
      get_release_line: (line, _ctx) => "- [custom] " + line.summary,
      get_dependency_release_line: (_deps, _ctx) => "",
    },
  )
  assert_true(hooked.contains("- [custom] Add core facade"))
}
