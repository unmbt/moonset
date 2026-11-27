///|
test "config supports commit: true, commit.skipCI, alsoSkipDependentsOfSkipped, deno, yarn, line protocol" {
  let cfg1 = @engine.parse_config(
    "{\"schemaVersion\":1,\"commit\":true,\"alsoSkipDependentsOfSkipped\":true,\"format\":\"deno\"}",
  )
  assert_eq(cfg1.commit.mode, @model.CommitMode::Both)
  assert_false(cfg1.commit.skip_ci)
  assert_true(cfg1.also_skip_dependents_of_skipped)
  assert_eq(@engine.resolve_formatter(cfg1), "deno")
  assert_true(@engine.formatter_supports_path("deno", "CHANGELOG.md"))
  assert_eq(
    @engine.formatter_command("deno", ["CHANGELOG.md"]),
    Some(("deno", ["fmt", "--", "CHANGELOG.md"])),
  )

  let cfg2 = @engine.parse_config(
    (
      #|{
      #|  "schemaVersion": 1,
      #|  "commit": { "mode": "version", "skipCI": true },
      #|  "plugins": {
      #|    "generators": {
      #|      "line-hook": {
      #|        "program": "node",
      #|        "args": ["hook.mjs"],
      #|        "allowedPrograms": ["node"],
      #|        "environment": ["PATH"],
      #|        "protocol": "line"
      #|      }
      #|    }
      #|  },
      #|  "experimental": {
      #|    "mixedWorkspaces": {
      #|      "mode": "unified",
      #|      "workspaces": [
      #|        { "id": "js", "ecosystem": "npm", "root": "js", "manager": "yarn", "includeRoot": false }
      #|      ]
      #|    }
      #|  }
      #|}
    ),
  )
  assert_eq(cfg2.commit.mode, @model.CommitMode::Version)
  assert_true(cfg2.commit.skip_ci)
  assert_eq(cfg2.generators["line-hook"].protocol, "line")
  assert_eq(cfg2.mixed_workspaces()[0].manager, @model.PackageManager::Yarn)
}

///|
test "alsoSkipDependentsOfSkipped transitively skips dependents of ignored or private units" {
  let cfg = @engine.parse_config(
    "{\"schemaVersion\":1,\"ignore\":[\"moonbit:acme/base\"],\"alsoSkipDependentsOfSkipped\":true}",
  )
  let base : @model.ReleaseUnit = {
    id: "moonbit:acme/base",
    native_name: "acme/base",
    ecosystem: @model.MoonBit,
    workspace_id: "moon",
    root: "base",
    manifest: "base/moon.mod",
    version_path: "base/moon.mod",
    version_field: "version",
    version: Some("0.1.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let mid : @model.ReleaseUnit = {
    id: "moonbit:acme/mid",
    native_name: "acme/mid",
    ecosystem: @model.MoonBit,
    workspace_id: "moon",
    root: "mid",
    manifest: "mid/moon.mod",
    version_path: "mid/moon.mod",
    version_field: "version",
    version: Some("0.1.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [
      {
        producer: "moonbit:acme/base",
        requirement: "0.1.0",
        kind: @model.Runtime,
        path: "mid/moon.mod",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let unrelated : @model.ReleaseUnit = {
    id: "moonbit:acme/other",
    native_name: "acme/other",
    ecosystem: @model.MoonBit,
    workspace_id: "moon",
    root: "other",
    manifest: "other/moon.mod",
    version_path: "other/moon.mod",
    version_field: "version",
    version: Some("0.1.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let snapshot : @model.WorkspaceSnapshot = {
    root: ".",
    workspaces: [
      {
        id: "moon",
        root: ".",
        ecosystem: @model.MoonBit,
        manager: @model.Moon,
      },
    ],
    units: [base, mid, unrelated],
    ownership: [
      { path: "base/moon.mod", field: "version", owner: base.id, },
      { path: "mid/moon.mod", field: "version", owner: mid.id, },
      { path: "other/moon.mod", field: "version", owner: unrelated.id, },
    ],
    unmanaged: [],
    config: cfg,
    sources: Map([]),
    changed_files: [],
    warnings: [],
    git_head: None,
  }
  let cs_mid = @engine.parse_changeset(
    "---\n\"acme/mid\": minor\n---\nIgnored transitively\n",
    id="cs-mid",
    path=".changeset/cs-mid.md",
  )
  let cs_other = @engine.parse_changeset(
    "---\n\"acme/other\": patch\n---\nStill releases\n",
    id="cs-other",
    path=".changeset/cs-other.md",
  )
  let plan = @engine.build_plan(snapshot, [cs_mid, cs_other])
  assert_eq(plan.releases.length(), 1)
  assert_eq(plan.releases[0].unit_id, "moonbit:acme/other")
  assert_true(plan.warnings.any(w => w.code == "skipped-dependent"))
}

///|
test "pr_comment supports GITHUB_SERVER_URL and scoped partition markers" {
  let cfg = @engine.parse_config("{\"schemaVersion\":1}")
  let unit : @model.ReleaseUnit = {
    id: "moonbit:acme/app",
    native_name: "acme/app",
    ecosystem: @model.MoonBit,
    workspace_id: "moon",
    root: "",
    manifest: "moon.mod",
    version_path: "moon.mod",
    version_field: "version",
    version: Some("0.1.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let snapshot : @model.WorkspaceSnapshot = {
    root: ".",
    workspaces: [
      {
        id: "moon",
        root: ".",
        ecosystem: @model.MoonBit,
        manager: @model.Moon,
      },
    ],
    units: [unit],
    ownership: [{ path: "moon.mod", field: "version", owner: unit.id, }],
    unmanaged: [],
    config: cfg,
    sources: Map([]),
    changed_files: ["src/lib.mbt"],
    warnings: [],
    git_head: Some("deadbeef1234"),
  }
  let plan = @engine.build_plan(snapshot, [])
  let md = @engine.status_markdown(snapshot, plan, options={
    ..@engine.CommentOptions::default(),
    head_repo: Some("acme/repo"),
    head_ref: Some("feat/ghe"),
    server_url: "https://git.corp.example/",
    marker_scope: Some("packages/moon"),
  })
  assert_true(
    md.has_prefix("<!-- moonset-bot:changeset-check:packages/moon -->\n"),
  )
  assert_true(md.contains("https://git.corp.example/acme/repo/new/feat/ghe"))
}

///|
test "detect_auto_formatter prioritizes project config files" {
  assert_eq(
    @engine.detect_auto_formatter(["biome.json", ".prettierrc"]),
    "biome",
  )
  assert_eq(@engine.detect_auto_formatter(["dprint.json"]), "dprint")
  assert_eq(@engine.detect_auto_formatter([".oxfmtrc.json"]), "oxfmt")
  assert_eq(@engine.detect_auto_formatter([".prettierrc.json"]), "prettier")
  assert_eq(@engine.detect_auto_formatter(["deno.jsonc"]), "deno")
  assert_eq(@engine.detect_auto_formatter(["README.md"]), "builtin")
}
