///|
test "arguments parse pre tag, doctor, publish flags, and tag format without conflicts" {
  let pre_enter = arguments(["pre", "enter", "alpha", "--initial-version"])
  assert_eq(pre_enter.command, "pre")
  assert_eq(pre_enter.pre_action, Some("enter"))
  assert_eq(pre_enter.pre_tag, Some("alpha"))
  assert_true(pre_enter.initial_version)

  let tag_json = arguments([
    "tag", "--format", "json", "--tag-format", "{ecosystem}/{name}@{version}", "--push",
  ])
  assert_eq(tag_json.command, "tag")
  assert_true(tag_json.json)
  assert_eq(tag_json.tag_format, "{ecosystem}/{name}@{version}")
  assert_true(tag_json.tag_push)

  let tag_compat = arguments(["tag", "v{version}"]) catch {
    _ => arguments(["tag", "--format", "v{version}"])
  }
  assert_eq(tag_compat.tag_format, "v{version}")
  assert_true(!tag_compat.json)

  let ver_short = arguments(["-V"])
  assert_eq(ver_short.command, "version-info")
  let ver_long = arguments(["--version"])
  assert_eq(ver_long.command, "version-info")
  assert_true(cli_version() != "" && cli_version() != "0.0.0")

  let doc = arguments(["doctor", "--registry", "--output", "json"])
  assert_eq(doc.command, "doctor")
  assert_true(doc.check_registry)
  assert_true(doc.json)

  let pub_opts = arguments([
    "publish", "--only", "npm:@acme/a,moonbit:acme/b", "--registry", "https://registry.npmjs.org",
    "--tag", "next", "--retry", "2", "--allow-uncommitted", "--no-tag", "--yes",
  ])
  assert_eq(pub_opts.only, ["npm:@acme/a", "moonbit:acme/b"])
  assert_eq(pub_opts.registry, Some("https://registry.npmjs.org"))
  assert_eq(pub_opts.dist_tag, Some("next"))
  assert_eq(pub_opts.retry, 2)
  assert_true(pub_opts.allow_uncommitted)
  assert_true(pub_opts.no_tag)
  assert_true(pub_opts.yes)

  assert_true(
    !wants_json_output(["add", "--package", "acme/a", "--summary", "json"]),
  )
  assert_true(
    !wants_json_output(["add", "--package", "acme/a", "--summary", "doctor"]),
  )
  let doc_reordered = arguments(["--registry", "doctor", "--fix", "--json"])
  assert_eq(doc_reordered.command, "doctor")
  assert_true(doc_reordered.check_registry)
  assert_true(doc_reordered.fix)
  assert_true(doc_reordered.json)
  assert_true(wants_json_output(["status", "--output", "json"]))
  assert_true(wants_json_output(["publish-plan"]))

  let md_status = arguments([
    "status", "--since", "main", "--output", "markdown", "--head-repo", "unmbt/moonset",
    "--head-ref", "feat/bot",
  ])
  assert_eq(md_status.command, "status")
  assert_true(md_status.markdown)
  assert_true(!md_status.json)
  assert_eq(md_status.head_repo, Some("unmbt/moonset"))
  assert_eq(md_status.head_ref, Some("feat/bot"))
  assert_true(wants_markdown_output(["status", "--output", "markdown"]))
  assert_true(
    !wants_markdown_output(["add", "--package", "a", "--summary", "markdown"]),
  )
  let rejected_yaml = try {
    ignore(arguments(["status", "--output", "yaml"]))
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(rejected_yaml)
  let rejected_conflict = try {
    ignore(arguments(["status", "--json", "--output", "markdown"]))
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(rejected_conflict)
}

///|
test "TUI state reducers and deterministic views support package, bump, and summary flow" {
  let s0 = SelectState::new(2)
  let s1 = reduce_select(s0, Enter)
  assert_true(!s1.confirmed)
  let s2 = reduce_select(s1, Space)
  let s3 = reduce_select(s2, Down)
  let s4 = reduce_select(s3, Enter)
  assert_true(s4.confirmed)
  assert_eq(s4.selected, [true, false])
  let page = render_package_page(
    ["moonbit:acme/a", "moonbit:acme/b"],
    ["0.1.0", "0.2.0"],
    s3,
  )
  assert_true(page.contains(" [x] moonbit:acme/a  0.1.0"))
  assert_true(page.contains("> [ ] moonbit:acme/b  0.2.0"))

  let (c1, ok1, back1) = reduce_choice(2, 4, Up)
  assert_eq(c1, 1)
  assert_true(!ok1 && !back1)
  let (_, ok2, back2) = reduce_choice(c1, 4, Left)
  assert_true(!ok2 && back2)
  assert_true(
    render_bump_page("moonbit:acme/a", "0.1.0", 1).contains("> minor"),
  )

  let s1 = reduce_summary(SummaryState::new(), Char("h"))
  let s2 = reduce_summary(s1, Char("i"))
  let s3 = reduce_summary(s2, Backspace)
  assert_eq(s3.text(), "h")
  let confirm = render_confirmation("Add feature", [
    { unit_id: "moonbit:acme/a", bump: @model.Minor, },
  ])
  assert_true(confirm.contains("minor: moonbit:acme/a"))
  assert_true(confirm.contains("Add feature"))
}

///|
test "arguments parse release-notes flags without conflicting with global --version" {
  let rn = arguments([
    "release-notes", "--version", "0.1.0", "--file", "CHANGELOG.md", "--json",
  ])
  assert_eq(rn.command, "release-notes")
  assert_eq(rn.release_version, Some("0.1.0"))
  assert_eq(rn.file_path, Some("CHANGELOG.md"))
  assert_true(rn.json)
  assert_true(!rn.from_state)

  let rn_state = arguments(["release-notes", "--from-state", "--json"])
  assert_eq(rn_state.command, "release-notes")
  assert_true(rn_state.from_state)
  assert_true(rn_state.json)
  assert_true(
    wants_json_output(["release-notes", "--version", "0.1.0", "--json"]),
  )

  let pack_target = arguments([
    "pack", "--target", "linux-x64", "--manifest-out", "dist/pack.json", "--verify",
    "--artifacts-dir", "dist", "--json",
  ])
  assert_eq(pack_target.command, "pack")
  assert_eq(pack_target.pack_target, Some("linux-x64"))
  assert_eq(pack_target.manifest_out, Some("dist/pack.json"))
  assert_true(pack_target.verify_artifacts)
  assert_eq(pack_target.artifacts_dir, Some("dist"))

  let ver_md = arguments([
    "version", "--dry-run", "--output", "markdown", "--commit-metadata", "meta.json",
    "--no-format",
  ])
  assert_eq(ver_md.command, "version")
  assert_true(ver_md.dry_run)
  assert_true(ver_md.markdown)
  assert_true(ver_md.no_format)
  assert_eq(ver_md.commit_metadata_path, Some("meta.json"))

  let scoped_pub = arguments([
    "publish", "--registry", "npm=https://npm.pkg.github.com", "--registry", "cargo=private",
    "--tag", "npm=next", "--tag", "npm:@acme/ui=canary",
  ])
  assert_eq(
    scoped_pub.registry,
    Some("npm=https://npm.pkg.github.com,cargo=private"),
  )
  assert_eq(scoped_pub.dist_tag, Some("npm=next,npm:@acme/ui=canary"))
}

///|
test "v0.3.0 CLI argument parser: --flag=value, --major, tagless --snapshot, --otp, --reconcile, --help topic, --dry-run guard, int32 overflow" {
  let add_eq = arguments([
    "add", "--package=acme/a", "--major", "--summary=Breaking change", "--open",
  ])
  assert_eq(add_eq.command, "add")
  assert_eq(add_eq.packages, ["acme/a"])
  assert_eq(add_eq.bump, Some("major"))
  assert_eq(add_eq.summary, Some("Breaking change"))
  assert_true(add_eq.open_editor)

  let snap_tagless = arguments(["version", "--snapshot", "--ignore=acme/demo"])
  assert_eq(snap_tagless.command, "version")
  assert_true(snap_tagless.snapshot_enabled)
  assert_eq(snap_tagless.snapshot, None)
  assert_eq(snap_tagless.ignore_packages, ["acme/demo"])

  let snap_tagged = arguments(["version", "--snapshot=canary", "--dry-run"])
  assert_true(snap_tagged.snapshot_enabled)
  assert_eq(snap_tagged.snapshot, Some("canary"))
  assert_true(snap_tagged.dry_run)

  let pub_reconcile = arguments([
    "publish", "--otp=654321", "--reconcile", "--yes",
  ])
  assert_eq(pub_reconcile.otp, Some("654321"))
  assert_true(pub_reconcile.reconcile)

  let help_sub = arguments(["publish", "--help"])
  assert_eq(help_sub.command, "help")
  assert_eq(help_sub.help_topic, Some("publish"))
  assert_true(render_help(help_sub.help_topic).contains("--reconcile"))

  let help_before = arguments(["--help", "version"])
  assert_eq(help_before.command, "help")
  assert_eq(help_before.help_topic, Some("version"))

  // Reject `--dry-run` on unsupported subcommands
  let bad_dry = try {
    ignore(arguments(["add", "--dry-run"]))
    false
  } catch {
    @model.Invalid(d) => d.code == "usage"
    _ => false
  }
  assert_true(bad_dry)

  // Reject int32 overflow (2147483648)
  let bad_retry = try {
    ignore(arguments(["publish", "--retry", "2147483648"]))
    false
  } catch {
    @model.Invalid(d) => d.code == "usage"
    _ => false
  }
  assert_true(bad_retry)

  // Validate `--id` path traversal protection
  assert_eq(validate_changeset_id("feat-1.0_ok"), "feat-1.0_ok")
  for bad_id in ["../evil", "dir/file", "a\\b", ".hidden", "..", ""] {
    let rejected = try {
      ignore(validate_changeset_id(bad_id))
      false
    } catch {
      @model.Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "v0.3.0 built-in TUI supports Space, UTF-8 Chinese editing, cursor movement, select-all, changed badge, and 0.x major confirm" {
  // Select-all toggle ('a') and changed badge
  let s0 = SelectState::new(2)
  let s_all = reduce_select(s0, Char("a"))
  assert_eq(s_all.selected, [true, true])
  let s_none = reduce_select(s_all, Char("a"))
  assert_eq(s_none.selected, [false, false])
  let pkg_view = render_package_page(
    ["moonbit:acme/a", "moonbit:acme/b"],
    ["0.2.0", "1.0.0"],
    s_all,
    changed_flags=[true, false],
  )
  assert_true(pkg_view.contains("[changed]"))

  // Summary editor: Chinese UTF-8 + Space + Left/Right cursor + Backspace + Delete
  let mut st = SummaryState::new()
  st = reduce_summary(st, Char("修复"))
  st = reduce_summary(st, Space)
  st = reduce_summary(st, Char("中文乱码"))
  assert_eq(st.text(), "修复 中文乱码")
  st = reduce_summary(st, Left)
  st = reduce_summary(st, Left)
  st = reduce_summary(st, Char("显示"))
  assert_eq(st.text(), "修复 中文显示乱码")
  st = reduce_summary(st, Backspace)
  assert_eq(st.text(), "修复 中文显乱码")
  st = reduce_summary(st, Delete)
  assert_eq(st.text(), "修复 中文显码")
  assert_true(render_summary_page(st, true).contains("Ctrl+E"))

  // Pre-1.0 major confirmation view
  let warn = render_zero_major_confirm("moonbit:acme/a", "0.2.0", 0)
  assert_true(warn.contains("graduate this package to 1.0.0"))

  // Diagnostic stderr formatting: omit `:1:1:` when path is empty
  assert_eq(
    format_diagnostic_stderr(@model.diagnostic("usage", "missing tag")),
    "usage: missing tag",
  )
  assert_eq(
    format_diagnostic_stderr(
      @model.diagnostic(
        "invalid-json",
        "bad token",
        path="moon.mod",
        line=3,
        column=5,
      ),
    ),
    "moon.mod:3:5: invalid-json: bad token",
  )
}
