///|
test "v0.3.0 regression: glob ** boundary, prerelease range guard, and Cargo wildcards" {
  assert_true(!@engine.matches_pattern("barfoo.mbt", "**/foo.mbt"))
  assert_true(!@engine.matches_pattern("src/afoo.mbt", "src/**/foo.mbt"))
  assert_true(@engine.matches_pattern("foo.mbt", "**/foo.mbt"))
  assert_true(@engine.matches_pattern("src/sub/foo.mbt", "src/**/foo.mbt"))
  // Prerelease guards
  assert_true(!@engine.version_matches("1.0.0", "1.1.0-alpha.0"))
  assert_true(!@engine.version_matches("0.1.0", "0.2.0-alpha.0"))
  assert_true(
    !@engine.matches_ecosystem_range(@model.Npm, "*", "1.0.0-alpha.0"),
  )
  assert_true(
    !@engine.matches_ecosystem_range(@model.Npm, "x", "1.0.0-alpha.0"),
  )
  assert_true(
    !@engine.matches_ecosystem_range(@model.Cargo, "*", "1.0.0-alpha.0"),
  )
  // Cargo rejects npm disjunctions
  let cargo_or_rejected = try {
    @engine.validate_ecosystem_range(@model.Cargo, "^1.0 || ^2.0")
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(cargo_or_rejected)
}

///|
test "v0.3.0 regression: ignored changesets preserved, devDependencies cycles allowed, peerDependencies major bump" {
  let mod_a = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  let mod_ign = "name = \"acme/ign\"\nversion = \"0.1.0\"\n"
  let ws_ign : @model.WorkspaceSnapshot = {
    ..snapshot(
      [unit_with_source("acme/a", mod_a), unit_with_source("acme/ign", mod_ign)],
      config="{\"ignore\":[\"acme/ign\"]}",
    ),
    sources: Map([
      ("acme/a/moon.mod", mod_a),
      ("acme/ign/moon.mod", mod_ign),
      (".changeset/a.md", "---\n\"moonbit:acme/a\": patch\n---\nFix a\n"),
      (".changeset/ign.md", "---\n\"moonbit:acme/ign\": patch\n---\nFix ign\n"),
    ]),
  }
  let cs_a = @engine.parse_changeset(
    ws_ign.sources[".changeset/a.md"],
    id="a",
    path=".changeset/a.md",
  )
  let cs_ign = @engine.parse_changeset(
    ws_ign.sources[".changeset/ign.md"],
    id="ign",
    path=".changeset/ign.md",
  )
  let plan_ign = @engine.build_plan(ws_ign, [cs_a, cs_ign])
  let vp_ign = @engine.build_version_plan(
    ws_ign,
    plan_ign,
    @model.VersionOptions::default(),
    generated_at="2026-11-20",
  )
  // Ignored-only changeset MUST NOT be deleted!
  assert_true(
    vp_ign.edits.any(e => e.path == ".changeset/a.md" && e.after_text == ""),
  )
  assert_false(vp_ign.edits.any(e => e.path == ".changeset/ign.md"))

  // npm peerDependencies -> Major bump; devDependencies cycle allowed & range updated; catalog: allowed
  let pkg_a = "{\"name\":\"@acme/a\",\"version\":\"1.0.0\",\"devDependencies\":{\"@acme/b\":\"^1.0.0\",\"lodash\":\"catalog:\"}}"
  let pkg_b = "{\"name\":\"@acme/b\",\"version\":\"1.0.0\",\"peerDependencies\":{\"@acme/a\":\"^1.0.0\"}}"
  let a_dep_pos = pkg_a.find("\"^1.0.0\"").unwrap()
  let b_dep_pos = pkg_b.find("\"^1.0.0\"").unwrap()
  let unit_a : @model.ReleaseUnit = {
    id: "npm:@acme/a",
    native_name: "@acme/a",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "a",
    manifest: "a/package.json",
    version_path: "a/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: find_quoted_version_span(pkg_a, "1.0.0"),
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [
      {
        producer: "npm:@acme/b",
        requirement: "^1.0.0",
        kind: @model.Development,
        path: "a/package.json",
        start: a_dep_pos,
        end: a_dep_pos + 8,
        target_condition: None,
      },
      {
        producer: "npm:lodash",
        requirement: "catalog:",
        kind: @model.Development,
        path: "a/package.json",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let unit_b : @model.ReleaseUnit = {
    id: "npm:@acme/b",
    native_name: "@acme/b",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "b",
    manifest: "b/package.json",
    version_path: "b/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: find_quoted_version_span(pkg_b, "1.0.0"),
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [
      {
        producer: "npm:@acme/a",
        requirement: "^1.0.0",
        kind: @model.Peer,
        path: "b/package.json",
        start: b_dep_pos,
        end: b_dep_pos + 8,
        target_condition: None,
      },
    ],
  }
  let ws_npm : @model.WorkspaceSnapshot = {
    ..snapshot([unit_a, unit_b]),
    sources: Map([("a/package.json", pkg_a), ("b/package.json", pkg_b)]),
  }
  let cs_major = @engine.parse_changeset(
    "---\n\"npm:@acme/a\": major\n---\nBreaking change\n",
    id="m1",
    path=".changeset/m1.md",
    mixed=true,
  )
  let plan_npm = @engine.build_plan(ws_npm, [cs_major])
  let rel_b = plan_npm.releases
    .iter()
    .find_first(r => r.unit_id == "npm:@acme/b")
    .unwrap()
  assert_eq(rel_b.level, @model.Major)
  assert_eq(rel_b.new_version, "2.0.0")
  // devDependencies on @acme/b inside @acme/a gets updated too!
  assert_true(
    plan_npm.dependency_updates.any(d => {
      d.consumer == "npm:@acme/a" &&
      d.producer == "npm:@acme/b" &&
      d.kind == @model.Development &&
      d.new_requirement == "^2.0.0"
    }),
  )
}

///|
test "v0.3.0 regression: tagless snapshot, pre-mode snapshot rejection, 0.0.0-alpha.0 graduation, strict metadata" {
  let mod_a = "name = \"acme/a\"\nversion = \"0.0.0-alpha.0\"\n"
  let ws0 : @model.WorkspaceSnapshot = {
    ..snapshot([unit_with_source("acme/a", mod_a, version="0.0.0-alpha.0")]),
    sources: Map([("acme/a/moon.mod", mod_a)]),
  }
  // 0.0.0-alpha.0 graduates to 0.0.0 (not 0.0.1!)
  let exit_plan = @engine.build_plan(
    ws0,
    [],
    pre=@model.PreState::new(@model.Exit, "alpha"),
  )
  assert_eq(exit_plan.releases[0].new_version, "0.0.0")

  // Snapshot blocked during active pre mode
  let pre_snap_rejected = try {
    ignore(
      @engine.build_plan(
        ws0,
        [change("acme/a")],
        pre=@model.PreState::new(@model.Pre, "alpha"),
        snapshot_mode=true,
        generated_at="2026-11-20T10:00:00Z",
      ),
    )
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(pre_snap_rejected)

  // Tagless snapshot works by default (snapshot.enabled defaults to true!)
  let mod_s = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  let ws_s : @model.WorkspaceSnapshot = {
    ..snapshot([unit_with_source("acme/a", mod_s, version="0.1.0")]),
    sources: Map([("acme/a/moon.mod", mod_s)]),
  }
  let snap_plan = @engine.build_plan(
    ws_s,
    [change("acme/a", bump="minor")],
    snapshot_mode=true,
    generated_at="2026-11-20T10:15:30Z",
  )
  assert_true(snap_plan.is_snapshot)
  assert_eq(snap_plan.releases[0].new_version, "0.0.0-20261120101530")

  // Strict summary metadata does not strip ordinary prose lines starting with "User:"
  let ws_gh : @model.WorkspaceSnapshot = {
    ..ws_s,
    config: @engine.parse_config(
      "{\"changelog\":{\"generator\":\"github\",\"options\":{\"repo\":\"unmbt/demo\"}}}",
    ),
  }
  let cs_prose = @engine.parse_changeset(
    "---\n\"acme/a\": patch\n---\nUser: can now configure retries safely\n",
    id="p1",
    path=".changeset/p1.md",
  )
  let p_prose = @engine.build_plan(ws_gh, [cs_prose])
  let vp_prose = @engine.build_version_plan(
    ws_gh,
    p_prose,
    @model.VersionOptions::default(),
    generated_at="2026-11-20",
  )
  assert_true(
    vp_prose.changelogs[0].text.contains(
      "User: can now configure retries safely",
    ),
  )
  assert_false(vp_prose.changelogs[0].text.contains("Thanks [@"))
}
