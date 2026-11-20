///|
fn comment_snapshot(
  units : Array[@model.ReleaseUnit],
  changed_files : Array[String],
  git_head : String?,
) -> @model.WorkspaceSnapshot {
  {
    root: "/repo",
    workspaces: [
      { id: "main", root: "", ecosystem: @model.MoonBit, manager: @model.Moon, },
    ],
    units,
    ownership: [],
    unmanaged: [],
    config: @model.Config::default(),
    sources: Map([]),
    changed_files,
    warnings: [],
    git_head,
  }
}

///|
test "status_markdown renders all states, escapes untrusted summary content, and truncates safely" {
  let unit = make_test_unit("acme/core", "core", "0.1.0")
  let snap_rel = comment_snapshot([unit], ["core/lib.mbt"], Some("deadbeef"))
  let cs_inject = @engine.parse_changeset(
    "---\n\"moonbit:acme/core\": minor\n---\nAdd <script> & <!-- moonset-bot:changeset-check --> | @team",
    id="feat",
    path=".changeset/feat.md",
  )
  let rel_plan = @engine.build_plan(snap_rel, [cs_inject])
  assert_eq(@engine.comment_state(snap_rel, rel_plan), "release")
  let rel_md = @engine.status_markdown(snap_rel, rel_plan)
  assert_true(rel_md.has_prefix("<!-- moonset-bot:changeset-check -->\n"))
  assert_true(
    rel_md.contains("| `moonbit:acme/core` | `0.1.0` → `0.2.0` | `minor` |"),
  )
  assert_true(rel_md.contains("&lt;script&gt; &amp; &lt;!--"))
  assert_true(rel_md.contains("\\| @\u{200B}team"))
  assert_false(rel_md[37:].contains("<!-- moonset-bot:changeset-check -->"))

  let empty_cs = @engine.parse_changeset(
    "---\n---\nSkip release",
    id="skip",
    path=".changeset/skip.md",
  )
  let empty_plan = @engine.build_plan(snap_rel, [empty_cs])
  assert_eq(@engine.comment_state(snap_rel, empty_plan), "empty")
  let empty_md = @engine.status_markdown(snap_rel, empty_plan)
  assert_true(empty_md.contains("Empty changeset"))

  let miss_plan = @engine.build_plan(snap_rel, [])
  assert_eq(@engine.comment_state(snap_rel, miss_plan), "missing")
  let miss_md = @engine.status_markdown(snap_rel, miss_plan, options={
    ..@engine.CommentOptions::default(),
    head_repo: Some("contrib/moonset"),
    head_ref: Some("feat/fix+1"),
  })
  assert_true(miss_md.contains("### ⚠️ No changeset found"))
  assert_true(
    miss_md.contains(
      "https://github.com/contrib/moonset/new/feat/fix%2B1?filename=.changeset%2F",
    ),
  )
  // Verify deterministic_changeset_slug strips "fnv1a64:" prefix (no colon / zero-entropy constant)
  assert_false(miss_md.contains("fnv1a64"))
  assert_true(miss_md.contains("moonset add --empty"))

  let miss_no_link = @engine.status_markdown(snap_rel, miss_plan, options={
    ..@engine.CommentOptions::default(),
    head_repo: Some("bad repo/name"),
    head_ref: Some("main"),
  })
  assert_false(miss_no_link.contains("Click here to add a changeset on GitHub"))

  let snap_none = comment_snapshot([unit], ["README.md"], Some("deadbeef"))
  let none_plan = @engine.build_plan(snap_none, [])
  assert_eq(@engine.comment_state(snap_none, none_plan), "none")
  assert_true(
    @engine.status_markdown(snap_none, none_plan).contains(
      "No release changes detected",
    ),
  )

  let err_md = @engine.error_markdown(
    @model.diagnostic(
      "invalid-changeset",
      "Bad <tag> @user",
      path=".changeset/bad.md",
      line=3,
      column=2,
    ),
  )
  assert_true(err_md.contains("### ❌ Failed to inspect changesets"))
  assert_true(err_md.contains(".changeset/bad.md:3:2"))
  assert_true(err_md.contains("Bad &lt;tag&gt; @\u{200B}user"))

  let many_files : Array[String] = []
  for i in 0..<40 {
    many_files.push("core/file_with_a_long_name_" + i.to_string() + ".mbt")
  }
  let snap_big = comment_snapshot([unit], many_files, Some("deadbeef"))
  let big_md = @engine.status_markdown(
    snap_big,
    @engine.build_plan(snap_big, []),
    options={ ..@engine.CommentOptions::default(), max_length: 400, },
  )
  assert_true(big_md.length() <= 400)
  assert_true(big_md.contains("Output truncated"))
}
