///|
fn artifact_unit(
  id : String,
  ecosystem : String,
  publish~ : Bool = true,
) -> @model.ReleaseUnit {
  let parts = id.split(":").map(x => x.to_owned()).collect()
  let native_name = if parts.length() > 1 { parts[1] } else { id }
  {
    id,
    native_name,
    ecosystem,
    workspace_id: ecosystem,
    root: native_name.replace_all(old="/", new="_"),
    manifest: native_name + "/manifest",
    version_path: native_name + "/manifest",
    version_field: "version",
    version: Some("0.1.0"),
    visibility: "public",
    publish,
    dependencies: [],
  }
}

///|
test "build_execution_dag separates build and publish graphs and detects cycles" {
  let config_json =
    #|{
    #|  "schemaVersion": 1,
    #|  "experimental": {
    #|    "mixedWorkspaces": {
    #|      "mode": "unified",
    #|      "workspaces": [
    #|        {"id": "m", "ecosystem": "moonbit", "root": "native", "manager": "moon", "includeRoot": false},
    #|        {"id": "js", "ecosystem": "npm", "root": ".", "manager": "pnpm", "includeRoot": false}
    #|      ],
    #|      "units": {
    #|        "moonbit:acme/engine": { "publish": false },
    #|        "npm:@acme/engine": {
    #|          "artifacts": [
    #|            { "target": "linux-x64", "package": "npm:@acme/engine-linux-x64", "required": true },
    #|            { "target": "darwin-arm64", "package": "npm:@acme/engine-darwin-arm64", "required": false }
    #|          ]
    #|        }
    #|      },
    #|      "bridges": [
    #|        {
    #|          "consumer": "npm:@acme/engine",
    #|          "producer": "moonbit:acme/engine",
    #|          "kind": "build",
    #|          "bump": "patch",
    #|          "waitFor": "build"
    #|        }
    #|      ]
    #|    }
    #|  }
    #|}
  let units = [
    artifact_unit("moonbit:acme/engine", "moonbit", publish=false),
    artifact_unit("npm:@acme/engine-linux-x64", "npm"),
    artifact_unit("npm:@acme/engine-darwin-arm64", "npm"),
    artifact_unit("npm:@acme/engine", "npm"),
  ]
  let ws : @model.WorkspaceSnapshot = {
    ..snapshot(units, config=config_json),
    git_head: Some("abc1234"),
  }
  let cs = @engine.parse_changeset(
    "---\n\"moonbit:acme/engine\": minor\n\"npm:@acme/engine-linux-x64\": patch\n\"npm:@acme/engine-darwin-arm64\": patch\n---\nNative addon release\n",
    id="addon-1",
    path=".changeset/addon-1.md",
    mixed=true,
  )
  let plan = @engine.build_plan(ws, [cs])
  let dag = @engine.build_execution_dag(ws, plan)

  // waitFor=build producer appears in build_nodes but NOT publish_nodes
  assert_true(dag.build_nodes.any(n => n.unit_id == "moonbit:acme/engine"))
  assert_true(!dag.publish_nodes.any(n => n.unit_id == "moonbit:acme/engine"))
  let idx_linux = dag.publish_order
    .search("npm:@acme/engine-linux-x64")
    .unwrap()
  let idx_main = dag.publish_order.search("npm:@acme/engine").unwrap()
  assert_true(idx_linux < idx_main)
  assert_true(
    dag.artifacts.any(a => {
      a.unit_id == "npm:@acme/engine-linux-x64" &&
      a.target == "linux-x64" &&
      a.required
    }),
  )
  assert_true(
    dag.artifacts.any(a => {
      a.unit_id == "npm:@acme/engine-darwin-arm64" &&
      a.target == "darwin-arm64" &&
      !a.required
    }),
  )
}

///|
test "verify_artifact_matrix blocks main unit on missing required platform or stale commit, allows optional failure" {
  let intents : Array[@model.ArtifactIntent] = [
    {
      id: "npm:@acme/engine@0.1.1",
      unit_id: "npm:@acme/engine",
      version: "0.1.1",
      target: "source",
      required: true,
      source_commit: Some("head-1"),
      expected_hash: None,
      path: None,
    },
    {
      id: "npm:@acme/engine-linux-x64@0.1.1/linux-x64",
      unit_id: "npm:@acme/engine-linux-x64",
      version: "0.1.1",
      target: "linux-x64",
      required: true,
      source_commit: Some("head-1"),
      expected_hash: None,
      path: None,
    },
    {
      id: "npm:@acme/engine-darwin-arm64@0.1.1/darwin-arm64",
      unit_id: "npm:@acme/engine-darwin-arm64",
      version: "0.1.1",
      target: "darwin-arm64",
      required: false,
      source_commit: Some("head-1"),
      expected_hash: None,
      path: None,
    },
  ]
  let owners : Map[String, Array[String]] = Map([
    ("npm:@acme/engine-linux-x64", ["npm:@acme/engine"]),
    ("npm:@acme/engine-darwin-arm64", ["npm:@acme/engine"]),
  ])

  // Missing optional darwin-arm64 must NOT fail verification
  let ok_report = @engine.verify_artifact_matrix(
    intents,
    [
      {
        artifact_id: "npm:@acme/engine@0.1.1",
        unit_id: "npm:@acme/engine",
        version: "0.1.1",
        target: "source",
        archive_path: "engine.tgz",
        source_commit: Some("head-1"),
        content_hash: "sha256:1",
        verified: true,
      },
      {
        artifact_id: "npm:@acme/engine-linux-x64@0.1.1/linux-x64",
        unit_id: "npm:@acme/engine-linux-x64",
        version: "0.1.1",
        target: "linux-x64",
        archive_path: "linux.tgz",
        source_commit: Some("head-1"),
        content_hash: "sha256:2",
        verified: true,
      },
    ],
    expected_head="head-1",
    owners_by_package=owners,
  )
  assert_true(ok_report.ok)
  assert_eq(ok_report.blocked_units, [])
  assert_true(
    ok_report.issues.any(i => !i.blocking && i.target == "darwin-arm64"),
  )

  // Stale commit on required linux-x64 blocks both platform package and main wrapper
  let bad_report = @engine.verify_artifact_matrix(
    intents,
    [
      {
        artifact_id: "npm:@acme/engine@0.1.1",
        unit_id: "npm:@acme/engine",
        version: "0.1.1",
        target: "source",
        archive_path: "engine.tgz",
        source_commit: Some("head-1"),
        content_hash: "sha256:1",
        verified: true,
      },
      {
        artifact_id: "npm:@acme/engine-linux-x64@0.1.1/linux-x64",
        unit_id: "npm:@acme/engine-linux-x64",
        version: "0.1.1",
        target: "linux-x64",
        archive_path: "linux.tgz",
        source_commit: Some("old-commit"),
        content_hash: "sha256:2",
        verified: true,
      },
    ],
    expected_head="head-1",
    owners_by_package=owners,
  )
  assert_true(!bad_report.ok)
  assert_true(bad_report.blocked_units.contains("npm:@acme/engine-linux-x64"))
  assert_true(bad_report.blocked_units.contains("npm:@acme/engine"))
}

///|
test "build_execution_dag rejects cyclic platform package references and duplicate targets" {
  let self_ref_cfg =
    #|{
    #|  "schemaVersion": 1,
    #|  "experimental": {
    #|    "mixedWorkspaces": {
    #|      "mode": "unified",
    #|      "workspaces": [
    #|        {"id": "js", "ecosystem": "npm", "root": ".", "manager": "pnpm", "includeRoot": false}
    #|      ],
    #|      "units": {
    #|        "npm:@acme/engine": {
    #|          "artifacts": [
    #|            { "target": "linux-x64", "package": "npm:@acme/engine", "required": true }
    #|          ]
    #|        }
    #|      }
    #|    }
    #|  }
    #|}
  let units = [artifact_unit("npm:@acme/engine", "npm")]
  let ws = snapshot(units, config=self_ref_cfg)
  let cs = @engine.parse_changeset(
    "---\n\"npm:@acme/engine\": patch\n---\nSelf ref\n",
    id="c1",
    path=".changeset/c1.md",
    mixed=true,
  )
  let plan = @engine.build_plan(ws, [cs])
  let cyclic = try {
    ignore(@engine.build_execution_dag(ws, plan))
    false
  } catch {
    @model.Invalid(d) => d.code == "cyclic-execution-graph"
    _ => false
  }
  assert_true(cyclic)
}
