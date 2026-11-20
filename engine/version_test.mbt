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
  assert_true(text.contains("### Minor Changes"))
  assert_true(text.contains("Add streaming support"))
  assert_true(text.contains("## 0.1.0 - 2026-11-01"))
}

///|
test "version plan is executable and consumes changesets" {
  let mod_a = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  let ws0 = snapshot([unit_with_source("acme/a", mod_a)])
  let ws : @model.WorkspaceSnapshot = {
    ..ws0,
    sources: Map([
      ("acme/a/moon.mod", mod_a),
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
      snapshot: false,
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

///|
test "version plan preserves package.json formatting, Cargo CRLF/UTF-8 offsets, pre state, and changelog=false" {
  let pkg_source = "{\r\n    \"name\": \"@acme/ui\",\r\n    \"version\": \"1.0.0\",\r\n    \"private\": false\r\n}\r\n"
  let cargo_source = "# 中文注释 😀\r\n[package]\r\nname = \"acme-rs\"\r\nversion = \"0.1.0\" # inline\r\n"
  let npm_unit : @model.ReleaseUnit = {
    id: "npm:@acme/ui",
    native_name: "@acme/ui",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "js",
    manifest: "js/package.json",
    version_path: "js/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: find_quoted_version_span(pkg_source, "1.0.0"),
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let cargo_unit : @model.ReleaseUnit = {
    id: "cargo:acme-rs",
    native_name: "acme-rs",
    ecosystem: @model.Cargo,
    workspace_id: "rs",
    root: "rs",
    manifest: "rs/Cargo.toml",
    version_path: "rs/Cargo.toml",
    version_field: "package",
    version: Some("0.1.0"),
    version_span: find_quoted_version_span(cargo_source, "0.1.0"),
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let ws : @model.WorkspaceSnapshot = {
    ..snapshot([npm_unit, cargo_unit], config="{\"changelog\":false}"),
    sources: Map([
      ("js/package.json", pkg_source),
      ("rs/Cargo.toml", cargo_source),
      (
        ".changeset/c1.md", "---\n\"npm:@acme/ui\": patch\n\"cargo:acme-rs\": minor\n---\nBump\n",
      ),
    ]),
  }
  let cs = @engine.parse_changeset(
    "---\n\"npm:@acme/ui\": patch\n\"cargo:acme-rs\": minor\n---\nBump\n",
    id="c1",
    path=".changeset/c1.md",
    mixed=true,
  )
  let pre_state = @engine.parse_pre_state("{\"mode\":\"pre\",\"tag\":\"rc\"}")
  let analysis = @engine.build_plan(ws, [cs], pre=pre_state)
  let vp = @engine.build_version_plan(
    ws,
    analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
      snapshot: false,
    },
    generated_at="2026-11-18",
  )
  assert_true(vp.changelogs.is_empty())
  assert_true(!vp.edits.any(e => e.kind == "changelog"))
  // Pre mode moves consumed changeset into pre.directory and writes minimal v3 pre.json!
  assert_true(
    vp.edits.any(e => {
      e.kind == "changeset" &&
      e.path == ".changeset/pre/c1.md" &&
      e.after_text.contains("npm:@acme/ui")
    }),
  )
  assert_true(
    vp.edits.any(e => {
      e.kind == "changeset" &&
      e.path == ".changeset/c1.md" &&
      e.after_text == ""
    }),
  )
  assert_true(
    vp.edits.any(e => {
      e.path == ".changeset/pre.json" &&
      e.after_text.contains("\"mode\": \"pre\"") &&
      e.after_text.contains("\"tag\": \"rc\"")
    }),
  )
  let pkg_edit = vp.edits
    .iter()
    .find_first(e => e.path == "js/package.json")
    .unwrap()
  assert_eq(
    pkg_edit.after_text,
    "{\r\n    \"name\": \"@acme/ui\",\r\n    \"version\": \"1.0.1-rc.0\",\r\n    \"private\": false\r\n}\r\n",
  )
  let cargo_edit = vp.edits
    .iter()
    .find_first(e => e.path == "rs/Cargo.toml")
    .unwrap()
  assert_eq(
    cargo_edit.after_text,
    "# 中文注释 😀\r\n[package]\r\nname = \"acme-rs\"\r\nversion = \"0.2.0-rc.0\" # inline\r\n",
  )
}

///|
test "pre skips consumed changelogs, empty pre writes nothing, exit cleans pre.json, and multi-unit dir aggregates changelog" {
  let mod_pre = "name = \"acme/a\"\nversion = \"0.2.0-alpha.0\"\n"
  let ws_pre : @model.WorkspaceSnapshot = {
    ..snapshot([unit_with_source("acme/a", mod_pre, version="0.2.0-alpha.0")]),
    sources: Map([
      ("acme/a/moon.mod", mod_pre),
      (".changeset/pre.json", "{\"mode\":\"pre\",\"tag\":\"alpha\"}"),
    ]),
  }
  let c1 = @engine.parse_changeset(
    "---\nacme/a: minor\n---\nOld feature already released",
    id="c1",
    path=".changeset/pre/c1.md",
    in_pre_dir=true,
  )
  let c2 = @engine.parse_changeset(
    "---\nacme/a: patch\n---\nPR: #77\nAuthor: @wyate\nNew fix in alpha.1",
    id="c2",
    path=".changeset/c2.md",
  )
  let pre_active = @engine.parse_pre_state(
    ws_pre.sources[".changeset/pre.json"],
  )
  // No new changesets => zero releases => zero FileEdits invariant!
  let empty_analysis = @engine.build_plan(ws_pre, [c1], pre=pre_active)
  let empty_vp = @engine.build_version_plan(
    ws_pre,
    empty_analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
      snapshot: false,
    },
    generated_at="2026-11-18",
  )
  assert_true(empty_vp.edits.is_empty())

  // Second prerelease only renders c2 in changelog, not c1, and applies git/github metadata!
  let ws_gh : @model.WorkspaceSnapshot = {
    ..ws_pre,
    config: @engine.parse_config(
      "{\"changelog\":{\"generator\":\"github\",\"options\":{\"repo\":\"unmbt/moonset\"}}}",
    ),
  }
  let next_analysis = @engine.build_plan(ws_gh, [c1, c2], pre=pre_active)
  let next_vp = @engine.build_version_plan(
    ws_gh,
    next_analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
      snapshot: false,
    },
    generated_at="2026-11-18",
    changeset_commits=Map([("c2", "abcdef1234567890")]),
  )
  let cl = next_vp.changelogs[0].text
  assert_true(cl.contains("New fix in alpha.1"))
  assert_true(!cl.contains("Old feature already released"))
  assert_true(cl.contains("https://github.com/unmbt/moonset/pull/77"))
  assert_true(cl.contains("Thanks [@wyate](https://github.com/wyate)!"))
  assert_true(cl.contains("`abcdef1`"))

  // Pre exit with zero prereleases still cleans up pre.json
  let exit_state = @engine.parse_pre_state(
    "{\"mode\":\"exit\",\"tag\":\"alpha\"}",
  )
  let mod_exit = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  let ws_exit : @model.WorkspaceSnapshot = {
    ..snapshot([unit_with_source("acme/a", mod_exit, version="0.1.0")]),
    sources: Map([(".changeset/pre.json", "{}")]),
  }
  let exit_analysis = @engine.build_plan(ws_exit, [], pre=exit_state)
  let exit_vp = @engine.build_version_plan(
    ws_exit,
    exit_analysis,
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
      snapshot: false,
    },
    generated_at="2026-11-18",
  )
  assert_true(
    exit_vp.edits.any(e => e.path == ".changeset/pre.json" && e.after_text == ""),
  )

  // Same-directory dual-manifest units aggregate into one CHANGELOG.md edit + apply tagFormat
  let mbt_src = "name = \"acme/same\"\nversion = \"0.1.0\"\n"
  let npm_src = "{\"name\":\"@acme/same\",\"version\":\"1.0.0\"}\n"
  let mbt_same : @model.ReleaseUnit = {
    ..unit_with_source("acme/same", mbt_src),
    root: "",
    manifest: "moon.mod",
    version_path: "moon.mod",
  }
  let npm_same : @model.ReleaseUnit = {
    id: "npm:@acme/same",
    native_name: "@acme/same",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "",
    manifest: "package.json",
    version_path: "package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: find_quoted_version_span(npm_src, "1.0.0"),
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let cfg_mixed = "{\"tag\":{\"format\":\"{ecosystem}/{name}-v{version}\"},\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"mbt\",\"ecosystem\":\"moonbit\",\"root\":\".\",\"manager\":\"moon\",\"includeRoot\":true},{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\".\",\"manager\":\"npm\",\"includeRoot\":true}]}}}"
  let ws_same : @model.WorkspaceSnapshot = {
    ..snapshot([mbt_same, npm_same], config=cfg_mixed),
    sources: Map([("moon.mod", mbt_src), ("package.json", npm_src)]),
  }
  let cs_same = @engine.parse_changeset(
    "---\n\"moonbit:acme/same\": patch\n\"npm:@acme/same\": minor\n---\nCo-located update",
    id="same",
    path=".changeset/same.md",
    mixed=true,
  )
  let vp_same = @engine.build_version_plan(
    ws_same,
    @engine.build_plan(ws_same, [cs_same]),
    @model.VersionOptions::{
      dry_run: true,
      no_changelog: false,
      snapshot_tag: None,
      snapshot: false,
    },
    generated_at="2026-11-18",
  )
  let cl_edits = vp_same.edits.filter(e => e.path == "CHANGELOG.md")
  assert_eq(cl_edits.length(), 1)
  assert_true(cl_edits[0].after_text.contains("## moonbit:acme/same - 0.1.1"))
  assert_true(cl_edits[0].after_text.contains("## npm:@acme/same - 1.1.0"))
  assert_true(vp_same.tags.any(t => t.name == "moonbit/acme/same-v0.1.1"))
  assert_true(vp_same.tags.any(t => t.name == "npm/@acme/same-v1.1.0"))
}

///|
test "Changesets-aligned Major/Minor/Patch Changes and Updated dependencies with commit links" {
  let mod_a = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  let mod_b = "name = \"acme/b\"\nversion = \"0.1.0\"\nimport {\n  \"acme/a@0.1.0\",\n}\n"
  let dep_pos = mod_b.find("\"acme/a@0.1.0\"").unwrap()
  let ws : @model.WorkspaceSnapshot = {
    ..snapshot(
      [
        unit_with_source("acme/a", mod_a, version="0.1.0"),
        {
          ..unit_with_source("acme/b", mod_b, version="0.1.0"),
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
      ],
      config="{\"changelog\":{\"generator\":\"github\",\"options\":{\"repo\":\"unmbt/demo\"}},\"updateInternalDependents\":\"always\"}",
    ),
    sources: Map([("acme/a/moon.mod", mod_a), ("acme/b/moon.mod", mod_b)]),
  }
  let cs = @engine.parse_changeset(
    "---\nacme/a: major\n---\nPR: #2015\nAuthor: @alice\nRemoved legacy error",
    id="c1",
    path=".changeset/c1.md",
  )
  let plan = @engine.build_plan(ws, [cs])
  let vp = @engine.build_version_plan(
    ws,
    plan,
    { dry_run: true, no_changelog: false, snapshot_tag: None, snapshot: false, },
    generated_at="2026-11-19",
    changeset_commits=Map([("c1", "6a05002deadbeef")]),
  )
  let cl_a = vp.changelogs
    .iter()
    .find_first(c => c.unit_id == "moonbit:acme/a")
    .unwrap().text
  assert_true(cl_a.contains("### Major Changes"))
  assert_true(
    cl_a.contains(
      "- [#2015](https://github.com/unmbt/demo/pull/2015) [`6a05002`](https://github.com/unmbt/demo/commit/6a05002deadbeef) Thanks [@alice](https://github.com/alice)! - Removed legacy error",
    ),
  )
  let cl_b = vp.changelogs
    .iter()
    .find_first(c => c.unit_id == "moonbit:acme/b")
    .unwrap().text
  assert_true(cl_b.contains("### Patch Changes"))
  assert_true(
    cl_b.contains(
      "- Updated dependencies [[`6a05002`](https://github.com/unmbt/demo/commit/6a05002deadbeef)]:\n  - acme/a@1.0.0",
    ),
  )
}
