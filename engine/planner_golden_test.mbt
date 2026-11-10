///|
test "golden single patch plan schema v1" {
  let plan = @engine.build_plan(snapshot([unit("acme/a")]), [change("acme/a")])
  inspect(
    @model.canonical_json(plan.to_json()),
    content=(
      #|{"stage":"analysis","releases":[{"level":"patch","unitId":"moonbit:acme/a","publish":true,"reasons":["changeset:test"],"changesets":["test"],"newVersion":"0.1.1","oldVersion":"0.1.0"}],"warnings":[],"changesets":[{"id":"test","path":"test.md","summary":"Summary","releases":[{"type":"patch","unitId":"moonbit:acme/a"}]}],"executable":false,"fingerprint":"fnv1a64:9214b1fda9f5527","generatedAt":null,"nextPreState":null,"affectedPaths":["acme/a/moon.mod"],"schemaVersion":1,"dependencyUpdates":[]}
    ),
  )
}

///|
test "glob matching crosses directories only with double star" {
  assert_true(@engine.matches_pattern("a.mbt", "**/*.mbt"))
  assert_true(@engine.matches_pattern("src/a.mbt", "**/*.mbt"))
  assert_true(!@engine.matches_pattern("src/a.mbt", "*.mbt"))
  assert_true(!@engine.matches_pattern("src/a.js", "**/*.mbt"))
}
