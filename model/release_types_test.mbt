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
