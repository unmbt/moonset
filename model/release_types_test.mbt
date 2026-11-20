///|
test "publish status and artifact results serialize stable fields" {
  let artifact : @model.ArtifactIntent = {
    id: "npm:@acme/core@1.0.0/linux-x64",
    unit_id: "npm:@acme/core",
    version: "1.0.0",
    target: "linux-x64",
    required: true,
    source_commit: Some("abc"),
    expected_hash: None,
    path: Some("dist/core.tgz"),
  }
  let status : @model.PublishStatus = {
    plan_id: "plan-1",
    unit_id: "npm:@acme/core",
    version: "1.0.0",
    target: "source",
    registry: "npm",
    state: @model.Published,
    digest: Some("sha256:x"),
    external_id: None,
    message: None,
  }
  assert_true(artifact.to_json().stringify().contains("linux-x64"))
  assert_true(status.to_json().stringify().contains("published"))
}

///|
test "v3 pre state and release state roundtrip" {
  let pre = @model.PreState::new(@model.Pre, "next")
  assert_eq(pre.to_json(), ({ "mode": "pre", "tag": "next" } : Json))
  assert_eq(@model.PreMode::parse("active"), Some(@model.Pre))
  assert_eq(@model.PreMode::parse("pre"), Some(@model.Pre))
  assert_eq(@model.PreMode::parse("exit"), Some(@model.Exit))

  let state : @model.ReleaseState = {
    plan_fingerprint: "fnv1a64:abc",
    source_head: Some("deadbeef"),
    is_snapshot: true,
    releases: [
      {
        unit_id: "moonbit:acme/core",
        old_version: "0.1.0",
        new_version: "0.0.0-canary-20261120",
        level: @model.Patch,
        reasons: ["changeset:cs1"],
        changesets: ["cs1"],
        publish: true,
      },
    ],
    tags: [],
    consumed_changesets: [],
  }
  let decoded = @model.ReleaseState::from_json(state.to_json())
  assert_eq(decoded.plan_fingerprint, "fnv1a64:abc")
  assert_eq(decoded.source_head, Some("deadbeef"))
  assert_true(decoded.is_snapshot)
  assert_eq(decoded.releases.length(), 1)
  assert_eq(decoded.releases[0].unit_id, "moonbit:acme/core")
}
