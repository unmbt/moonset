///|
fn make_test_unit(
  native_name : String,
  root : String,
  version : String,
) -> @model.ReleaseUnit {
  {
    id: "moonbit:" + native_name,
    native_name,
    ecosystem: @model.MoonBit,
    workspace_id: "main",
    root,
    manifest: if root == "" {
      "moon.mod"
    } else {
      root + "/moon.mod"
    },
    version_path: if root == "" {
      "moon.mod"
    } else {
      root + "/moon.mod"
    },
    version_field: "version",
    version: Some(version),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
}

///|
test "coexistence_json exports read-only cross-partition summary without touching foreign changesets" {
  let config = @engine.parse_config(
    "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"native\",\"ecosystem\":\"moonbit\",\"root\":\"native\",\"manager\":\"moon\",\"includeRoot\":false}]}}}",
  )
  let snapshot : @model.WorkspaceSnapshot = {
    root: "/repo",
    workspaces: [
      {
        id: "native",
        root: "native",
        ecosystem: @model.MoonBit,
        manager: @model.Moon,
      },
    ],
    units: [make_test_unit("acme/core", "native", "0.1.0")],
    ownership: [
      { path: "native/moon.mod", field: "version", owner: "moonbit:acme/core", },
    ],
    unmanaged: ["package.json", "changeset-config:.changeset/config.json"],
    config,
    sources: Map([]),
    changed_files: [
      "native/lib.mbt", "package.json", ".changeset/js-change.md", "docs/shared.md",
    ],
    warnings: [],
    git_head: Some("abc123"),
  }
  let cs = @engine.parse_changeset(
    "---\n\"moonbit:acme/core\": patch\n---\nNative fix",
    id="fix",
    path=".moonset/fix.md",
    mixed=true,
  )
  let plan = @engine.build_plan(snapshot, [cs])
  let json = @engine.status_json(snapshot, plan, changeset_directory=".moonset")
  assert_true(
    json
    is {
      "hasRelease": True,
      "coexistence": {
        "mode": "coexist",
        "managedWorkspaces": ["native"],
        "unmanaged": ["package.json"],
        "foreignChangesetDirectories": [".changeset"],
        "changedUnowned": ["docs/shared.md"],
        "advice": [_, _, _],
        ..
      },
      ..
    },
  )
}

///|
test "coexistence_json returns None for ordinary single-ecosystem snapshot without unmanaged manifests" {
  let snapshot : @model.WorkspaceSnapshot = {
    root: "/repo",
    workspaces: [
      { id: "main", root: "", ecosystem: @model.MoonBit, manager: @model.Moon, },
    ],
    units: [make_test_unit("acme/app", "", "0.1.0")],
    ownership: [],
    unmanaged: [],
    config: @model.Config::default(),
    sources: Map([]),
    changed_files: ["main.mbt"],
    warnings: [],
    git_head: Some("abc123"),
  }
  let plan = @engine.build_plan(snapshot, [])
  let json = @engine.status_json(snapshot, plan)
  assert_true(@engine.coexistence_json(snapshot) is None)
  guard json is Object(fields) else { fail("expected object") }
  assert_false(fields.contains("coexistence"))
}
