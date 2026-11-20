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
test "TUI state reducers and deterministic clack views support group multiselect, confirm, select, text, and note boxes" {
  let rows = [
    GroupHeader("changed packages", [0]),
    GroupItem(0),
    GroupHeader("unchanged packages", [1]),
    GroupItem(1),
  ]
  let labels = ["@cs-demo/ui", "@cs-demo/utils"]
  let g0 = GroupMultiselectState::new(2)
  // Required group multiselect rejects empty Enter with validation message
  let g1 = reduce_group_multiselect(g0, rows, Enter, required=true)
  assert_true(!g1.confirmed)
  assert_true(g1.error != "")
  // Optional stage allows empty Enter
  let g_skip = reduce_group_multiselect(g0, rows, Enter, required=false)
  assert_true(g_skip.confirmed)
  // Space on GroupHeader("changed packages", [0]) toggles item 0 and clears error
  let g2 = reduce_group_multiselect(g1, rows, Space, required=true)
  assert_eq(g2.selected, [true, false])
  assert_eq(g2.error, "")
  // Navigate to item 1 and toggle it
  let g3 = reduce_group_multiselect(g2, rows, Down, required=true)
  let g4 = reduce_group_multiselect(g3, rows, Down, required=true)
  let g5 = reduce_group_multiselect(g4, rows, Down, required=true)
  let g6 = reduce_group_multiselect(g5, rows, Space, required=true)
  assert_eq(g6.selected, [true, true])
  let g7 = reduce_group_multiselect(g6, rows, Enter, required=true)
  assert_true(g7.confirmed)

  let active_group_view = render_group_multiselect_prompt(
    "Which packages were affected by the changes you made?", rows, labels, g2,
  )
  assert_true(active_group_view.contains("◆  Which packages were affected"))
  assert_true(active_group_view.contains("◼ changed packages"))
  assert_true(active_group_view.contains("◼ @cs-demo/ui"))
  assert_true(active_group_view.contains("◻ @cs-demo/utils"))
  let err_group_view = render_group_multiselect_prompt(
    "Which packages were affected by the changes you made?", rows, labels, g1,
  )
  assert_true(err_group_view.contains("▲  Which packages were affected"))
  assert_true(err_group_view.contains("Please select at least one option"))
  let submitted_group_view = render_group_multiselect_prompt(
    "Which packages were affected by the changes you made?",
    rows,
    labels,
    g7,
    submitted=true,
    submitted_text="@cs-demo/ui, @cs-demo/utils",
  )
  assert_true(
    submitted_group_view.contains("◇  Which packages were affected"),
  )
  assert_true(submitted_group_view.contains("│  @cs-demo/ui, @cs-demo/utils"))

  // Confirm state machine (`init` default No, `0.x` major default Yes)
  let c0 = ConfirmState::new(initial=false)
  assert_true(!c0.value)
  let c1 = reduce_confirm(c0, Left)
  assert_true(c1.value)
  let c2 = reduce_confirm(c1, Char("n"))
  assert_true(!c2.value)
  let c3 = reduce_confirm(c2, Char("y"))
  assert_true(c3.value)
  let c4 = reduce_confirm(c3, Enter)
  assert_true(c4.confirmed && c4.value)
  let c_view = render_confirm_prompt(
    "Should the GitHub integration be used for changelogs?",
    c0,
    with_guide=false,
  )
  assert_true(c_view.contains("○ Yes / ● No"))
  assert_true(!c_view.contains("│"))

  // Single-select bump choices
  let (c_sel1, ok1, back1) = reduce_choice(2, 3, Up)
  assert_eq(c_sel1, 1)
  assert_true(!ok1 && !back1)
  let (_, ok2, back2) = reduce_choice(c_sel1, 3, Left)
  assert_true(!ok2 && !back2)
  let sel_view = render_select_prompt(
    "What kind of change is this for acme/app?",
    ["patch (X.X.X)", "minor (X.X.X)", "major (X.X.X)"],
    1,
  )
  assert_true(sel_view.contains("● minor (X.X.X)"))
  assert_true(sel_view.contains("○ patch (X.X.X)"))

  // Text prompt placeholder (`main`) and colored first-char inverse cursor
  let empty_text = SummaryState::new()
  let plain_branch = render_text_prompt(
    "Which base branch should be used?",
    empty_text,
    placeholder="main",
    with_guide=false,
    color=false,
  )
  assert_true(plain_branch.contains("main"))
  let colored_branch = render_text_prompt(
    "Which base branch should be used?",
    empty_text,
    placeholder="main",
    with_guide=false,
    color=true,
  )
  assert_true(colored_branch.contains("\u{001b}[7mm\u{001b}[0m"))
  assert_true(colored_branch.contains("\u{001b}[90main\u{001b}[0m"))

  let s1 = reduce_summary(SummaryState::new(), Char("h"))
  let s2 = reduce_summary(s1, Char("i"))
  let s3 = reduce_summary(s2, Backspace)
  assert_eq(s3.text(), "h")
  let cancel_block = render_clack_cancel("Question?", with_guide=true)
  assert_true(cancel_block.contains("■  Question?"))
  assert_true(cancel_block.contains("└  Canceled... 👋"))
  let (c_home, _, _) = reduce_choice(2, 4, Home)
  assert_eq(c_home, 0)
  let (c_end, _, _) = reduce_choice(0, 4, End)
  assert_eq(c_end, 3)

  let staged = assign_bump_stages(["a", "b", "c"], [0, 1, 2], [0], [1])
  assert_true(staged[0].bump == @model.Major)
  assert_true(staged[1].bump == @model.Minor)
  assert_true(staged[2].bump == @model.Patch)
}

///|
test "TUI visual width, wrapping, redraw frames, changed-package detection, and NO_COLOR policy" {
  assert_eq(visual_width("abc"), 3)
  assert_eq(visual_width("中文"), 4)
  assert_eq(visual_width("Ａ"), 2)
  assert_eq(visual_width("e\u{0301}"), 1)
  assert_eq(visual_width("✓"), 1)
  assert_eq(visual_width("✗"), 1)
  assert_eq(visual_width("👩🏽‍💻"), 2)
  assert_eq(visual_width("1️⃣"), 2)
  assert_eq(visual_width("❤️"), 2)
  assert_eq(visual_width("⚠️"), 2)
  assert_eq(visual_width("a\t"), 8)
  assert_eq(visual_width("\u{001b}[31mred\u{001b}[0m"), 3)
  assert_eq(visual_width("👩\u{200d}💻"), 2)
  assert_eq(visual_line_count("abcd", 3), 2)
  assert_eq(visual_line_count("中文a", 4), 2)
  assert_eq(visual_line_count("ab中", 3), 2)
  assert_eq(visual_line_count("ab中中", 3), 3)
  assert_eq(visual_line_count("ab\u{0301}c", 2), 2)
  assert_eq(visual_line_count("one\ntwo", 80), 2)
  assert_eq(visual_line_count("中", 1), 1)
  assert_eq(truncate_visual("中文测试abc", 7), "中文...")
  let redraw = tui_redraw_sequence(3)
  assert_true(redraw.contains("\u{001b}[3A\r\u{001b}[J"))
  assert_true(!redraw.contains("\u{001b}[2J"))
  assert_true(!redraw.contains("\u{001b}[?1049h"))
  assert_true(!redraw.contains("\u{001b}[?1049l"))
  assert_eq(tui_frame_output(2, "hello"), "\u{001b}[2A\r\u{001b}[Jhello\n")
  assert_eq(tui_frame_output(0, "hello"), "hello\n")
  assert_eq(style_text("plain", "31", false), "plain")
  assert_true(style_text("red", "31", true).contains("\u{001b}[31m"))

  // NO_COLOR policy (https://no-color.org/) & TERM=dumb
  assert_true(
    should_enable_color(
      is_tty=true,
      no_color_flag=false,
      no_color_env=None,
      term_env=Some("xterm-256color"),
    ),
  )
  assert_true(
    should_enable_color(
      is_tty=true,
      no_color_flag=false,
      no_color_env=Some(""),
      term_env=None,
    ),
  )
  assert_true(
    !should_enable_color(
      is_tty=true,
      no_color_flag=false,
      no_color_env=Some("1"),
      term_env=None,
    ),
  )
  assert_true(
    !should_enable_color(
      is_tty=true,
      no_color_flag=true,
      no_color_env=None,
      term_env=None,
    ),
  )
  assert_true(
    !should_enable_color(
      is_tty=false,
      no_color_flag=false,
      no_color_env=None,
      term_env=None,
    ),
  )
  assert_true(
    !should_enable_color(
      is_tty=true,
      no_color_flag=false,
      no_color_env=None,
      term_env=Some("dumb"),
    ),
  )

  // has_no_color_flag ignores `--no-color` inside flag values or after `--`
  assert_true(has_no_color_flag(["status", "--no-color"]))
  assert_true(!has_no_color_flag(["add", "--summary", "--no-color"]))
  assert_true(!has_no_color_flag(["status", "--", "--no-color"]))

  // Longest-prefix unit change detection ignores `.changeset/` and avoids root false-positives
  let dummy_unit = (id : String, root : String) => @model.ReleaseUnit::{
    id,
    native_name: id,
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
    version: Some("0.1.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let units = [
    dummy_unit("moonbit:acme/root", ""),
    dummy_unit("moonbit:acme/sub", "packages/sub"),
  ]
  assert_eq(
    compute_changed_flags(units, [
      ".changeset/note.md", "packages/sub/src/lib.mbt",
    ]),
    [false, true],
  )
  assert_eq(compute_changed_flags(units, ["src/main.mbt"]), [true, false])
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

  // Changesets-compatible human-id (`adjective-noun-verb` lowercase kebab-case)
  let h1 = generate_human_id(1UL)
  let h2 = generate_human_id(2UL)
  let parts1 = h1.split("-").map(x => x.to_owned()).collect()
  assert_eq(parts1.length(), 3)
  assert_true(human_id_adjectives.contains(parts1[0]))
  assert_true(human_id_nouns.contains(parts1[1]))
  assert_true(human_id_verbs.contains(parts1[2]))
  assert_eq(validate_changeset_id(h1), h1)
  assert_true(h1 != h2)
  assert_true(next_human_id("sample", 0) != next_human_id("sample", 1))
}

///|
test "v0.3.0 built-in TUI supports Space, UTF-8 Chinese editing, cursor movement, select-all, and clack note/init config" {
  // Group select-all toggle ('a')
  let rows = [
    GroupHeader("changed packages", [0]),
    GroupItem(0),
    GroupHeader("unchanged packages", [1]),
    GroupItem(1),
  ]
  let g0 = GroupMultiselectState::new(2)
  let g_all = reduce_group_multiselect(g0, rows, Char("a"), required=true)
  assert_eq(g_all.selected, [true, true])
  let g_none = reduce_group_multiselect(g_all, rows, Char("a"), required=true)
  assert_eq(g_none.selected, [false, false])

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
  assert_true(
    render_text_prompt(
      "Please enter a summary for this change (this will be in the changelogs).",
      st,
    ).contains("修复 中文显|码"),
  )
  st = reduce_summary(st, End)
  assert_true(
    render_text_prompt(
      "Please enter a summary for this change (this will be in the changelogs).",
      st,
    ).contains("修复 中文显码|"),
  )

  // Note box exact visual-width right-border alignment (including CJK and ANSI color)
  let note_box = render_note_box(
    "NOTE",
    [
      "All packages that depend on these whose required versions will be incompatible will also be patch bumped when this changeset is applied.",
      "支持中文宽字符与 ANSI 对齐测试",
    ],
    columns=60,
    color=true,
  )
  let box_lines = note_box.split("\n").map(x => x.to_owned()).collect()
  // Last line is trailing "│" when with_guide=true; lines 0..n-1 form the box
  let expected_w = visual_width(box_lines[0])
  for i in 0..<(box_lines.length() - 1) {
    assert_eq(visual_width(box_lines[i]), expected_w)
  }

  // Changeset summary & intro blocks
  let sum_block = render_changeset_summary(major=["@cs-demo/ui"], patch=[
    "@cs-demo/utils",
  ])
  assert_true(sum_block.contains("◆  Summary of changesets:"))
  assert_true(sum_block.contains("│  major:  @cs-demo/ui"))
  assert_true(sum_block.contains("│  patch:  @cs-demo/utils"))
  assert_true(
    render_clack_intro("🌙 moonset v0.3.0", with_guide=true).has_prefix(
      "┌  🌙 moonset v0.3.0\n│",
    ),
  )

  // `-m` / `--message` alias parsing
  let msg_add = arguments(["add", "-m", "short summary"])
  assert_eq(msg_add.command, "add")
  assert_eq(msg_add.summary, Some("short summary"))
  let msg_long = arguments(["add", "--message=long summary"])
  assert_eq(msg_long.summary, Some("long summary"))

  // Pre-1.0 major check
  assert_true(is_pre_one_zero_version("0.2.0"))
  assert_true(is_pre_one_zero_version("v0.0.1"))
  assert_true(!is_pre_one_zero_version("1.0.0"))

  // Interactive `init` generated config combinations validate cleanly against `config-v1.json`
  let cfg_github = build_init_config_json({
    use_github: true,
    github_repo: "test/test",
    auto_commit: true,
    access: "restricted",
    base_branch: "",
  })
  let parsed_gh = @engine.parse_config(cfg_github)
  assert_eq(parsed_gh.changelog.generator, "github")
  assert_eq(parsed_gh.github.repo, Some("test/test"))
  assert_eq(parsed_gh.commit.mode, @model.CommitMode::Both)
  assert_eq(parsed_gh.access, @model.Access::Restricted)
  assert_eq(parsed_gh.base_branch, "main")

  let cfg_builtin = build_init_config_json({
    use_github: false,
    github_repo: "",
    auto_commit: false,
    access: "public",
    base_branch: "develop",
  })
  let parsed_bi = @engine.parse_config(cfg_builtin)
  assert_eq(parsed_bi.changelog.generator, "builtin")
  assert_eq(parsed_bi.github.repo, None)
  assert_eq(parsed_bi.commit.mode, @model.CommitMode::Never)
  assert_eq(parsed_bi.access, @model.Access::Public)
  assert_eq(parsed_bi.base_branch, "develop")

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
