///|
test "render_release_pr_body renders intro, pre banner, summary table, and per-package changelog details" {
  let ws0 = snapshot(
    [unit("unmbt/moonset", version="0.2.0-next.0")],
    config="{\"baseBranch\":\"master\",\"changelog\":{\"generator\":\"github\",\"options\":{\"repo\":\"unmbt/moonset\"}}}",
  )
  let ws : @model.WorkspaceSnapshot = {
    ..ws0,
    sources: Map([
      (
        "unmbt/moonset/moon.mod", "name = \"unmbt/moonset\"\nversion = \"0.2.0-next.0\"\n",
      ),
      (
        ".changeset/feat-1.md", "---\nunmbt/moonset: minor\n---\nAdd automatic GitHub Release creation (#12)\n",
      ),
    ]),
  }
  let cs = @engine.parse_changeset(
    "---\nunmbt/moonset: minor\n---\nAdd automatic GitHub Release creation (#12)\n",
    id="feat-1",
    path=".changeset/feat-1.md",
  )
  let pre_active = @engine.parse_pre_state(
    "{\"mode\":\"active\",\"tag\":\"next\",\"initialVersions\":{\"moonbit:unmbt/moonset\":\"0.1.0\"},\"nextNumbers\":{\"moonbit:unmbt/moonset\":1},\"consumed\":[]}",
  )
  let analysis = @engine.build_plan(ws, [cs], pre=pre_active)
  let vp = @engine.build_version_plan_with_metadata(
    ws,
    analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
    },
    generated_at="2026-11-19",
    changeset_commits=Map([
      ("feat-1", "a0efac361243493498b2b1ae3a6f2f56f26cfe40"),
    ]),
    commit_metadata=Map([
      ("a0efac361243493498b2b1ae3a6f2f56f26cfe40", (Some("15"), Some("wyatex"))),
    ]),
  )
  let body = @engine.render_release_pr_body(ws, vp, pre=pre_active)
  assert_true(body.contains("`master` is currently in **pre mode** (`next`)"))
  assert_true(body.contains("## Release Summary"))
  assert_true(
    body.contains(
      "| `moonbit:unmbt/moonset` | `0.2.0-next.0` → `0.2.0-next.1` | `minor` |",
    ),
  )
  assert_true(body.contains("# Releases"))
  assert_true(body.contains("## unmbt/moonset@0.2.0-next.1"))
  assert_true(body.contains("### Minor Changes"))
  assert_true(body.contains("https://github.com/unmbt/moonset/pull/15"))
  assert_true(body.contains("https://github.com/unmbt/moonset/issues/12"))
  assert_true(body.contains("Thanks [@wyatex](https://github.com/wyatex)!"))
  assert_eq(
    @engine.release_pr_title("chore: release packages", pre=pre_active),
    "chore: release packages (next)",
  )
  assert_eq(
    @engine.release_pr_title("chore: release packages (next)", pre=pre_active),
    "chore: release packages (next)",
  )
}
