///|
test "FR-027 changedFilePatterns supports classes braces extglobs and negation" {
  assert_true(@engine.matches_pattern("src/a.mbt", "src/[a-z].mbt"))
  assert_true(!@engine.matches_pattern("src/1.mbt", "src/[a-z].mbt"))
  assert_true(@engine.matches_pattern("src/1.mbt", "src/[!a-z].mbt"))
  assert_true(@engine.matches_pattern("src/app.ts", "src/*.{ts,mbt}"))
  assert_true(@engine.matches_pattern("src/app.mbt", "src/*.{ts,mbt}"))
  assert_true(!@engine.matches_pattern("src/app.rs", "src/*.{ts,mbt}"))
  assert_true(@engine.matches_pattern("src/lib.mbt", "src/@(lib|main).mbt"))
  assert_true(@engine.matches_pattern("src/main.mbt", "src/@(lib|main).mbt"))
  assert_true(!@engine.matches_pattern("src/other.mbt", "src/@(lib|main).mbt"))
  assert_true(@engine.matches_pattern("src/lib.mbt", "src/!(test|spec).mbt"))
  assert_true(!@engine.matches_pattern("src/test.mbt", "src/!(test|spec).mbt"))
  assert_true(@engine.matches_pattern("src/a.mbt", "src/+(a|b).mbt"))
  assert_true(@engine.matches_pattern("src/aba.mbt", "src/+(a|b).mbt"))
  assert_true(!@engine.matches_pattern("src/.mbt", "src/+(a|b).mbt"))
  assert_true(@engine.matches_pattern("src/foo.mbt", "src/foo?(bar).mbt"))
  assert_true(@engine.matches_pattern("src/foobar.mbt", "src/foo?(bar).mbt"))
  let patterns = ["**", "!**/*.test.mbt", "!docs/**", "docs/api.md"]
  assert_true(@engine.matches_changed_patterns("src/lib.mbt", patterns))
  assert_true(!@engine.matches_changed_patterns("src/lib.test.mbt", patterns))
  assert_true(!@engine.matches_changed_patterns("docs/guide.md", patterns))
  assert_true(@engine.matches_changed_patterns("docs/api.md", patterns))
  // Negation-only patterns include everything except matched exclusions
  assert_true(@engine.matches_changed_patterns("src/lib.mbt", ["!*.md"]))
  assert_true(!@engine.matches_changed_patterns("README.md", ["!*.md"]))
}

///|
test "FR-027 version groups and ignore expand globs and reject overlaps" {
  let units = [
    unit("acme/core", version="0.1.0"),
    unit("acme/cli", version="0.2.0"),
    unit("acme/example-a", version="0.1.0"),
    unit("acme/example-b", version="0.1.0"),
  ]
  let ws = snapshot(
    units,
    config="{\"fixed\":[[\"acme/{core,cli}\"]],\"ignore\":[\"acme/example-*\"],\"changedFilePatterns\":[\"**\",\"!**/README.md\"]}",
  )
  let plan = @engine.build_plan(ws, [change("acme/core", bump="minor")])
  assert_eq(plan.releases.length(), 2)
  assert_eq(plan.releases[0].unit_id, "moonbit:acme/cli")
  assert_eq(plan.releases[0].new_version, "0.3.0")
  assert_eq(plan.releases[1].unit_id, "moonbit:acme/core")
  assert_eq(plan.releases[1].new_version, "0.3.0")
  let ws_changes : @model.WorkspaceSnapshot = {
    ..ws,
    changed_files: [
      "acme/example-a/lib.mbt", "acme/core/README.md", "acme/core/lib.mbt",
    ],
  }
  assert_eq(@engine.relevant_changes(ws_changes), ["acme/core/lib.mbt"])

  // Overlapping expanded fixed + linked groups must fail cleanly
  let overlap_ws = snapshot(
    units,
    config="{\"fixed\":[[\"acme/c*\"]],\"linked\":[[\"acme/cli\"]]}",
  )
  let rejected = try {
    ignore(@engine.build_plan(overlap_ws, [change("acme/core")]))
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
}

///|
test "FR-028 snapshot config gates snapshot releases and renders templates" {
  let ws_disabled : @model.WorkspaceSnapshot = {
    ..snapshot([unit("acme/a", version="0.1.0")]),
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"\n"),
    ]),
  }
  let cs = change("acme/a", bump="minor")
  let analysis = @engine.build_plan(ws_disabled, [cs])
  let blocked = try {
    ignore(
      @engine.build_version_plan(
        ws_disabled,
        analysis,
        { dry_run: true, no_changelog: true, snapshot_tag: Some("canary"), },
        generated_at="2026-11-19T15:30:45Z",
      ),
    )
    false
  } catch {
    @model.Invalid(d) => d.code == "snapshot-disabled"
    _ => false
  }
  assert_true(blocked)

  // useCalculatedVersion = false (default) => 0.0.0-{tag}-{datetime}
  let mod_b = "name = \"acme/b\"\nversion = \"0.1.0\"\nimport {\n  \"acme/a@0.1.0\",\n}\n"
  let dep_pos = mod_b.find("\"acme/a@0.1.0\"").unwrap()
  let units_with_span = [
    unit("acme/a", version="0.1.0"),
    {
      ..unit("acme/b", version="0.1.0"),
      dependencies: [
        {
          producer: "moonbit:acme/a",
          requirement: "0.1.0",
          kind: @model.Runtime,
          path: "acme/b/moon.mod",
          start: dep_pos,
          end: dep_pos + 14,
          target_condition: None,
        },
      ],
    },
  ]
  let ws_zero : @model.WorkspaceSnapshot = {
    ..snapshot(units_with_span, config="{\"snapshot\":{\"enabled\":true}}"),
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"\n"),
      ("acme/b/moon.mod", mod_b),
    ]),
    git_head: Some("abcdef1234567890"),
  }
  let a0 = @engine.build_plan(ws_zero, [
    change("acme/a", bump="minor", id="c1"),
    change("acme/b", bump="patch", id="c2"),
  ])
  let vp0 = @engine.build_version_plan(
    ws_zero,
    a0,
    { dry_run: true, no_changelog: true, snapshot_tag: Some("canary"), },
    generated_at="2026-11-19T15:30:45Z",
  )
  assert_true(vp0.consumed_changesets.is_empty())
  assert_true(!vp0.edits.any(e => e.path == ".moonset/release-state.json"))
  assert_true(
    vp0.edits.any(e => {
      e.path == "acme/a/moon.mod" &&
      e.after_text.contains("\"0.0.0-canary-20261119153045\"")
    }),
  )
  assert_true(
    vp0.edits.any(e => {
      e.path == "acme/b/moon.mod" &&
      e.after_text.contains("\"acme/a@0.0.0-canary-20261119153045\"")
    }),
  )

  // useCalculatedVersion = true + custom template with {commit}
  let ws_calc : @model.WorkspaceSnapshot = {
    ..ws_zero,
    units: [unit("acme/a", version="0.1.0")],
    config: @engine.parse_config(
      "{\"snapshot\":{\"enabled\":true,\"useCalculatedVersion\":true,\"prereleaseTemplate\":\"{tag}.{commit}.{datetime}\"}}",
    ),
  }
  let a1 = @engine.build_plan(ws_calc, [change("acme/a", bump="minor")])
  let vp1 = @engine.build_version_plan(
    ws_calc,
    a1,
    { dry_run: true, no_changelog: true, snapshot_tag: Some("rc"), },
    generated_at="2026-11-19T15:30:45Z",
  )
  assert_true(
    vp1.edits.any(e => {
      e.path == "acme/a/moon.mod" &&
      e.after_text.contains("\"0.2.0-rc.abcdef1.20261119153045\"")
    }),
  )
}

///|
test "FR-029 pre.directory isolates consumed changesets and cleans up on graduation" {
  let cfg = "{\"pre\":{\"file\":\".changeset/pre.json\",\"directory\":\".changeset/pre-box\"}}"
  let c1_text = "---\nacme/a: minor\n---\nFirst pre feature\n"
  let c2_text = "---\nacme/a: patch\n---\nSecond pre fix\n"
  let ws1 : @model.WorkspaceSnapshot = {
    ..snapshot([unit("acme/a", version="0.1.0")], config=cfg),
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"\n"),
      (".changeset/c1.md", c1_text),
    ]),
    changed_files: [".changeset/pre-box/c1.md"],
  }
  // Files inside pre.directory are excluded from relevant_changes
  assert_true(@engine.relevant_changes(ws1).is_empty())

  let pre0 = @engine.parse_pre_state(
    "{\"mode\":\"active\",\"tag\":\"alpha\",\"initialVersions\":{},\"nextNumbers\":{},\"consumed\":[]}",
  )
  let c1 = @engine.parse_changeset(c1_text, id="c1", path=".changeset/c1.md")
  let p1 = @engine.build_plan(ws1, [c1], pre=pre0)
  let vp1 = @engine.build_version_plan(
    ws1,
    p1,
    { dry_run: true, no_changelog: true, snapshot_tag: None, },
    generated_at="2026-11-19",
  )
  assert_true(
    vp1.edits.any(e => {
      e.path == ".changeset/pre-box/c1.md" && e.after_text == c1_text
    }),
  )
  assert_true(
    vp1.edits.any(e => e.path == ".changeset/c1.md" && e.after_text == ""),
  )

  // Next prerelease: c1 already in pre-box is untouched; c2 moves into pre-box
  let pre1 = p1.next_pre_state.unwrap()
  let ws2 : @model.WorkspaceSnapshot = {
    ..snapshot([unit("acme/a", version="0.2.0-alpha.0")], config=cfg),
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.2.0-alpha.0\"\n"),
      (".changeset/pre-box/c1.md", c1_text),
      (".changeset/c2.md", c2_text),
      (".changeset/pre.json", pre1.to_json().stringify()),
    ]),
  }
  let c1_iso = @engine.parse_changeset(
    c1_text,
    id="c1",
    path=".changeset/pre-box/c1.md",
  )
  let c2 = @engine.parse_changeset(c2_text, id="c2", path=".changeset/c2.md")
  let p2 = @engine.build_plan(ws2, [c1_iso, c2], pre=pre1)
  let vp2 = @engine.build_version_plan(
    ws2,
    p2,
    { dry_run: true, no_changelog: true, snapshot_tag: None, },
    generated_at="2026-11-19",
  )
  assert_true(!vp2.edits.any(e => e.path == ".changeset/pre-box/c1.md"))
  assert_true(
    vp2.edits.any(e => {
      e.path == ".changeset/pre-box/c2.md" && e.after_text == c2_text
    }),
  )
  assert_true(
    vp2.edits.any(e => e.path == ".changeset/c2.md" && e.after_text == ""),
  )

  // Graduation (mode: exit) deletes isolated changesets + pre.json
  let pre_exit : @model.PreState = {
    ..p2.next_pre_state.unwrap(),
    mode: "exit",
  }
  let c2_iso = @engine.parse_changeset(
    c2_text,
    id="c2",
    path=".changeset/pre-box/c2.md",
  )
  let ws3 : @model.WorkspaceSnapshot = {
    ..snapshot([unit("acme/a", version="0.2.0-alpha.1")], config=cfg),
    sources: Map([
      ("acme/a/moon.mod", "name = \"acme/a\"\nversion = \"0.2.0-alpha.1\"\n"),
      (".changeset/pre-box/c1.md", c1_text),
      (".changeset/pre-box/c2.md", c2_text),
      (".changeset/pre.json", pre_exit.to_json().stringify()),
    ]),
  }
  let p3 = @engine.build_plan(ws3, [c1_iso, c2_iso], pre=pre_exit)
  let vp3 = @engine.build_version_plan(
    ws3,
    p3,
    { dry_run: true, no_changelog: true, snapshot_tag: None, },
    generated_at="2026-11-19",
  )
  assert_true(
    vp3.edits.any(e => {
      e.path == ".changeset/pre-box/c1.md" && e.after_text == ""
    }),
  )
  assert_true(
    vp3.edits.any(e => {
      e.path == ".changeset/pre-box/c2.md" && e.after_text == ""
    }),
  )
  assert_true(
    vp3.edits.any(e => e.path == ".changeset/pre.json" && e.after_text == ""),
  )
}

///|
test "FR-030 npm and Cargo compound SemVer ranges match validate and rewrite" {
  // npm union, conjunction, hyphen, x-range
  assert_true(
    @engine.matches_ecosystem_range("npm", "^1.0.0 || ^2.0.0", "1.5.0"),
  )
  assert_true(
    @engine.matches_ecosystem_range("npm", "^1.0.0 || ^2.0.0", "2.3.4"),
  )
  assert_true(
    !@engine.matches_ecosystem_range("npm", "^1.0.0 || ^2.0.0", "3.0.0"),
  )
  assert_true(@engine.matches_ecosystem_range("npm", ">=1.0.0 <2.0.0", "1.9.9"))
  assert_true(
    !@engine.matches_ecosystem_range("npm", ">=1.0.0 <2.0.0", "2.0.0"),
  )
  assert_true(
    @engine.matches_ecosystem_range("npm", ">= 1.2.0 <= 1.5.0", "1.5.0"),
  )
  assert_true(@engine.matches_ecosystem_range("npm", "1.2.0 - 2.0.0", "1.9.0"))
  assert_true(!@engine.matches_ecosystem_range("npm", "1.2.0 - 2.0.0", "2.0.1"))
  assert_true(@engine.matches_ecosystem_range("npm", "1.x", "1.4.2"))
  assert_true(!@engine.matches_ecosystem_range("npm", "1.x", "2.0.0"))

  // Cargo comma conjunction, || union, >, <, bare caret
  assert_true(
    @engine.matches_ecosystem_range("cargo", ">=1.0.0, <2.0.0", "1.4.0"),
  )
  assert_true(
    !@engine.matches_ecosystem_range("cargo", ">=1.0.0, <2.0.0", "2.0.0"),
  )
  assert_true(
    @engine.matches_ecosystem_range("cargo", ">0.1.0, <=0.5.0", "0.5.0"),
  )
  assert_true(
    !@engine.matches_ecosystem_range("cargo", ">0.1.0, <=0.5.0", "0.1.0"),
  )
  assert_true(@engine.matches_ecosystem_range("cargo", "^1.0 || ^2.0", "2.1.0"))
  assert_true(@engine.matches_ecosystem_range("cargo", "0.1.0", "0.1.5"))
  assert_true(!@engine.matches_ecosystem_range("cargo", "0.1.0", "0.2.0"))

  // Rewriting preserves semantics and always satisfies target
  let r1 = @engine.rewrite_ecosystem_range("npm", ">=1.0.0 <2.0.0", "1.2.0")
  assert_eq(r1, ">=1.2.0 <2.0.0")
  assert_true(@engine.matches_ecosystem_range("npm", r1, "1.2.0"))

  let r2 = @engine.rewrite_ecosystem_range("npm", ">=1.0.0 <2.0.0", "2.0.0")
  assert_eq(r2, ">=2.0.0 <3.0.0")
  assert_true(@engine.matches_ecosystem_range("npm", r2, "2.0.0"))

  let r3 = @engine.rewrite_ecosystem_range("npm", "^1.0.0 || ^2.0.0", "2.1.0")
  assert_eq(r3, "^1.0.0 || ^2.1.0")
  assert_true(@engine.matches_ecosystem_range("npm", r3, "2.1.0"))

  let r4 = @engine.rewrite_ecosystem_range("npm", "^1.0.0 || ^2.0.0", "3.0.0")
  assert_eq(r4, "^1.0.0 || ^2.0.0 || ^3.0.0")
  assert_true(@engine.matches_ecosystem_range("npm", r4, "3.0.0"))

  let r5 = @engine.rewrite_ecosystem_range("cargo", ">=1.0.0, <2.0.0", "2.0.0")
  assert_eq(r5, ">=2.0.0, <3.0.0")
  assert_true(@engine.matches_ecosystem_range("cargo", r5, "2.0.0"))

  let r6 = @engine.rewrite_ecosystem_range("npm", "1.0.0 - 1.5.0", "2.0.0")
  assert_eq(r6, "1.0.0 - 2.0.0")
  assert_true(@engine.matches_ecosystem_range("npm", r6, "2.0.0"))

  // Malformed ranges rejected
  for bad in ["^1.0.0 | ^2.0.0", "^1.0.0 || ", ">= ", "1.2.3.4"] {
    let rejected = try {
      @engine.validate_ecosystem_range("npm", bad)
      false
    } catch {
      @model.Invalid(_) => true
      _ => false
    }
    assert_true(rejected)
  }
}

///|
test "FR-026 formatter resolution and FR-031 scoped publish target mapping" {
  let c1 = @engine.parse_config("{\"formatter\":\"prettier\"}")
  assert_eq(@engine.resolve_formatter(c1), "prettier")
  assert_eq(@engine.resolve_formatter(c1, no_format=true), "none")
  let c2 = @engine.parse_config("{\"formatter\":\"prettier\",\"format\":false}")
  assert_eq(@engine.resolve_formatter(c2), "none")
  let c3 = @engine.parse_config("{\"format\":\"biome\"}")
  assert_eq(@engine.resolve_formatter(c3), "biome")
  assert_true(@engine.formatter_supports_path("prettier", "CHANGELOG.md"))
  assert_true(@engine.formatter_supports_path("prettier", "package.json"))
  assert_true(!@engine.formatter_supports_path("prettier", "moon.mod"))
  assert_true(
    !@engine.formatter_supports_path("prettier", ".moonset/release-state.json"),
  )
  assert_true(@engine.formatter_supports_path("biome", "package.json"))
  assert_true(!@engine.formatter_supports_path("biome", "CHANGELOG.md"))
  assert_true(@engine.formatter_supports_path("dprint", "Cargo.toml"))
  assert_eq(
    @engine.formatter_command("biome", ["package.json"]),
    Some(("biome", ["format", "--write", "package.json"])),
  )

  let scoped = @engine.parse_target_mapping(
    Some(
      "npm=https://npm.pkg.github.com,cargo=private,npm:@acme/ui=https://ui.reg",
    ),
  )
  assert_eq(scoped.global, None)
  assert_eq(
    @engine.resolve_target_override(scoped, "npm:@acme/ui", "npm"),
    Some("https://ui.reg"),
  )
  assert_eq(
    @engine.resolve_target_override(scoped, "npm:@acme/core", "npm"),
    Some("https://npm.pkg.github.com"),
  )
  assert_eq(
    @engine.resolve_target_override(scoped, "cargo:acme-rs", "cargo"),
    Some("private"),
  )
  assert_eq(
    @engine.resolve_target_override(scoped, "moonbit:acme/a", "moonbit"),
    None,
  )
  // Plain URL with '=' in query string remains a global value
  let url_global = @engine.parse_target_mapping(
    Some("https://reg.example.com/?token=1"),
  )
  assert_eq(url_global.global, Some("https://reg.example.com/?token=1"))
}
