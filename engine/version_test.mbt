///|
test "builtin changelog groups release summaries and dependency updates" {
  let cs = @engine.parse_changeset(
    "---\nacme/a: minor\n---\nAdd streaming support",
    id="feature",
    path=".changeset/feature.md",
  )
  let text = @engine.render_builtin_changelog(
    "moonbit:acme/a",
    "0.2.0",
    "2026-11-12",
    [cs],
    [],
    "# Changelog\n\n## 0.1.0 - 2026-11-01\n\n### Fixes\n\n- Old fix\n",
  )
  assert_true(text.contains("## 0.2.0 - 2026-11-12"))
  assert_true(text.contains("### Features"))
  assert_true(text.contains("Add streaming support"))
  assert_true(text.contains("## 0.1.0 - 2026-11-01"))
}

///|
test "version plan is executable and consumes changesets" {
  let ws0 = snapshot([unit("acme/a")])
  let ws : @model.WorkspaceSnapshot = {
    ..ws0,
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"\n"),
      (".changeset/test.md", "---\nacme/a: patch\n---\nFix\n"),
    ]),
  }
  let cs = change("acme/a")
  let analysis = @engine.build_plan(ws, [cs])
  let version = @engine.build_version_plan(
    ws,
    analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
    },
    generated_at="2026-11-12",
  )
  assert_true(version.executable)
  assert_eq(version.stage, "version")
  assert_true(version.edits.any(x => x.kind == "manifest"))
  assert_true(version.edits.any(x => x.kind == "changelog"))
  assert_true(version.edits.any(x => x.kind == "changeset"))
  assert_true(version.edits.any(x => x.kind == "state"))
}
