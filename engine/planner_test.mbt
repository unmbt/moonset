///|
fn find_quoted_version_span(
  source : String,
  version : String,
) -> @model.TextSpan? {
  let needle = "\"" + version + "\""
  let bytes = @utf8.encode(source)
  let needle_bytes = @utf8.encode(needle)
  if needle_bytes.length() == 0 || bytes.length() < needle_bytes.length() {
    return None
  }
  for i in 0..<=(bytes.length() - needle_bytes.length()) {
    let mut matched = true
    for j in 0..<needle_bytes.length() {
      if bytes[i + j] != needle_bytes[j] {
        matched = false
        break
      }
    }
    if matched {
      return Some({ start: i, end: i + needle_bytes.length(), })
    }
  }
  None
}

///|
fn unit_with_source(
  name : String,
  source : String,
  version~ : String = "0.1.0",
  deps~ : Array[(String, String)] = [],
) -> @model.ReleaseUnit {
  {
    ..unit(name, version~, deps~),
    version_span: find_quoted_version_span(source, version),
  }
}

///|
fn unit(
  name : String,
  version~ : String = "0.1.0",
  deps~ : Array[(String, String)] = [],
) -> @model.ReleaseUnit {
  {
    id: "moonbit:" + name,
    native_name: name,
    ecosystem: @model.MoonBit,
    workspace_id: "main",
    root: name,
    manifest: name + "/moon.mod",
    version_path: name + "/moon.mod",
    version_field: "version",
    version: Some(version),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: deps.map(pair => {
      producer: "moonbit:" + pair.0,
      requirement: pair.1,
      kind: @model.Runtime,
      path: name + "/moon.mod",
      start: 0,
      end: 0,
      target_condition: None,
    }),
  }
}

///|
fn snapshot(
  units : Array[@model.ReleaseUnit],
  config~ : String = "{}",
) -> @model.WorkspaceSnapshot raise {
  {
    root: ".",
    units,
    config: @engine.parse_config(config),
    workspaces: [],
    ownership: [],
    unmanaged: [],
    sources: Map([]),
    changed_files: [],
    warnings: [],
    git_head: None,
  }
}

///|
fn change(
  name : String,
  bump~ : String = "patch",
  id~ : String = "test",
) -> @model.Changeset raise {
  @engine.parse_changeset(
    "---\n\"" + name + "\": " + bump + "\n---\nSummary",
    id~,
    path=id + ".md",
  )
}

///|
test "compatible dependency alone does not release unchanged consumer" {
  let ws = snapshot([unit("acme/a"), unit("acme/b", deps=[("acme/a", "0.1.0")])])
  let plan = @engine.build_plan(ws, [change("acme/a")])
  assert_eq(plan.releases.length(), 1)
  assert_eq(plan.releases[0].new_version, "0.1.1")
  assert_eq(plan.dependency_updates.length(), 0)
  let both = @engine.build_plan(ws, [
    change("acme/a"),
    change("acme/b", id="second"),
  ])
  assert_eq(both.dependency_updates[0].new_requirement, "0.1.1")
}

///|
test "always propagation closes a dependency chain without repeated increments" {
  let ws = snapshot(
    [
      unit("acme/a"),
      unit("acme/b", deps=[("acme/a", "0.1.0")]),
      unit("acme/c", deps=[("acme/b", "0.1.0")]),
    ],
    config="{\"updateInternalDependents\":\"always\"}",
  )
  let plan = @engine.build_plan(ws, [change("acme/a")])
  assert_eq(plan.releases.map(x => x.new_version), ["0.1.1", "0.1.1", "0.1.1"])
  assert_eq(plan.dependency_updates.length(), 2)
  assert_eq(
    @model.canonical_json(plan.to_json()),
    @model.canonical_json(@engine.build_plan(ws, [change("acme/a")]).to_json()),
  )
}

///|
test "out of range forces patch and declaration update even at minor threshold" {
  let ws = snapshot(
    [
      unit("acme/a", version="1.9.0"),
      unit("acme/b", deps=[("acme/a", "1.9.0")]),
    ],
    config="{\"updateInternalDependencies\":\"minor\"}",
  )
  let plan = @engine.build_plan(ws, [change("acme/a", bump="major")])
  assert_eq(plan.releases.map(x => x.new_version), ["2.0.0", "0.1.1"])
  assert_eq(plan.dependency_updates[0].new_requirement, "2.0.0")
}

///|
test "fixed and linked use highest current version with different membership" {
  let units = [unit("acme/a"), unit("acme/b", version="0.8.0")]
  let fixed = snapshot(units, config="{\"fixed\":[[\"acme/a\",\"acme/b\"]]}")
  let linked = snapshot(units, config="{\"linked\":[[\"acme/a\",\"acme/b\"]]}")
  assert_eq(
    @engine.build_plan(fixed, [change("acme/a", bump="minor")]).releases.map(x => {
      x.new_version
    }),
    ["0.9.0", "0.9.0"],
  )
  assert_eq(
    @engine.build_plan(linked, [change("acme/a", bump="minor")]).releases.map(x => {
      x.new_version
    }),
    ["0.9.0"],
  )
}

///|
test "cycles ignore conflicts and versionless releases are rejected" {
  let cyclic = snapshot([
    unit("acme/a", deps=[("acme/b", "0.1.0")]),
    unit("acme/b", deps=[("acme/a", "0.1.0")]),
  ])
  let ignored = snapshot(
    [unit("acme/a"), unit("acme/b")],
    config="{\"fixed\":[[\"acme/a\",\"acme/b\"]],\"ignore\":[\"acme/b\"]}",
  )
  let versionless = snapshot([{ ..unit("acme/a"), version: None, }])
  for ws in [cyclic, ignored, versionless] {
    let rejected = try {
      ignore(@engine.build_plan(ws, [change("acme/a")]))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "prerelease planning is pure and exit graduates published prereleases" {
  let state = @engine.parse_pre_state("{\"mode\":\"pre\",\"tag\":\"alpha\"}")
  let ws = snapshot([unit("acme/a")])
  let plan = @engine.build_plan(ws, [change("acme/a", bump="minor")], pre=state)
  assert_eq(plan.releases[0].new_version, "0.2.0-alpha.0")
  assert_eq(plan.next_pre_state.unwrap().mode, @model.Pre)
  assert_eq(plan.next_pre_state.unwrap().tag, "alpha")
  let advanced = snapshot([unit("acme/a", version="0.2.0-alpha.0")])
  let already_in_pre = @engine.parse_changeset(
    "---\n\"acme/a\": minor\n---\nSummary",
    id="test",
    path=".changeset/pre/test.md",
    in_pre_dir=true,
  )
  let next = @engine.build_plan(
    advanced,
    [already_in_pre],
    pre=plan.next_pre_state.unwrap(),
  )
  assert_eq(next.releases.length(), 0)
  let exit_state = @model.PreState::new(@model.Exit, "alpha")
  let stable = @engine.build_plan(advanced, [already_in_pre], pre=exit_state)
  assert_eq(stable.releases[0].new_version, "0.2.0")
  assert_true(stable.next_pre_state is None)
}

///|
test "JSON v1 is analysis-only with stable output and injected time" {
  let ws = snapshot([unit("acme/a")])
  let first = @engine.build_plan(ws, [], generated_at="2026-01-01T00:00:00Z")
  let second = @engine.build_plan(ws, [], generated_at="2026-02-01T00:00:00Z")
  assert_eq(first.fingerprint, second.fingerprint)
  assert_true(first.to_json() is { "generatedAt": "2026-01-01T00:00:00Z", .. })
  assert_true(ws.to_json() is { "units": [{ "version": "0.1.0", .. }], .. })
  assert_true(
    first.to_json()
    is {
      "schemaVersion": 1,
      "stage": "analysis",
      "executable": false,
      "releases": [],
      ..
    },
  )
}

///|
test "public planner validates field ownership and canonical identities" {
  let first = unit("acme/a")
  let duplicate : @model.ReleaseUnit = {
    ..unit("acme/b"),
    manifest: first.manifest,
  }
  let wrong_id : @model.ReleaseUnit = { ..first, id: "npm:@acme/a", }
  for ws in [snapshot([first, duplicate]), snapshot([wrong_id])] {
    let rejected = try {
      ignore(@engine.build_plan(ws, []))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "pre mode secondary minor bump stays monotonic under Changesets v3 model" {
  let state = @engine.parse_pre_state("{\"mode\":\"pre\",\"tag\":\"alpha\"}")
  let ws = snapshot([unit("acme/a", version="0.1.1-alpha.0")])
  let plan = @engine.build_plan(
    ws,
    [change("acme/a", bump="minor", id="c2")],
    pre=state,
  )
  assert_eq(plan.releases[0].new_version, "0.2.0-alpha.1")
  assert_eq(plan.next_pre_state.unwrap().mode, @model.Pre)
  assert_eq(plan.next_pre_state.unwrap().tag, "alpha")
}

///|
test "mixed bridges propagate consumer bumps, detect cycles, and preserve npm workspace protocol" {
  let mbt : @model.ReleaseUnit = unit("acme/native", version="0.1.0")
  let js_core : @model.ReleaseUnit = {
    id: "npm:@acme/core",
    native_name: "@acme/core",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "js/core",
    manifest: "js/core/package.json",
    version_path: "js/core/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let js_app : @model.ReleaseUnit = {
    id: "npm:@acme/app",
    native_name: "@acme/app",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "js/app",
    manifest: "js/app/package.json",
    version_path: "js/app/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [
      {
        producer: "npm:@acme/core",
        requirement: "^1.0.0",
        kind: @model.Runtime,
        path: "js/app/package.json",
        start: 0,
        end: 0,
        target_condition: None,
      },
      {
        producer: "npm:@acme/ws",
        requirement: "workspace:^",
        kind: @model.Runtime,
        path: "js/app/package.json",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let js_ws : @model.ReleaseUnit = {
    id: "npm:@acme/ws",
    native_name: "@acme/ws",
    ecosystem: @model.Npm,
    workspace_id: "js",
    root: "js/ws",
    manifest: "js/ws/package.json",
    version_path: "js/ws/package.json",
    version_field: "version",
    version: Some("1.0.0"),
    version_span: None,
    visibility: @model.Public,
    publish: true,
    publish_config: None,
    dependencies: [],
  }
  let cfg = "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"native\",\"ecosystem\":\"moonbit\",\"root\":\".\",\"manager\":\"moon\",\"includeRoot\":true},{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\"js\",\"manager\":\"pnpm\",\"includeRoot\":false}],\"bridges\":[{\"consumer\":\"npm:@acme/core\",\"producer\":\"moonbit:acme/native\",\"kind\":\"build\",\"bump\":\"patch\",\"waitFor\":\"build\"}]}}}"
  let ws = snapshot([mbt, js_core, js_app, js_ws], config=cfg)
  let plan = @engine.build_plan(ws, [
    change("moonbit:acme/native", bump="minor", id="c1"),
    change("npm:@acme/ws", bump="minor", id="c2"),
    change("npm:@acme/app", bump="patch", id="c3"),
  ])
  assert_true(
    plan.releases.any(r => {
      r.unit_id == "npm:@acme/core" && r.new_version == "1.0.1"
    }),
  )
  assert_true(
    plan.dependency_updates.any(d => {
      d.consumer == "npm:@acme/app" &&
      d.producer == "npm:@acme/core" &&
      d.new_requirement == "^1.0.1"
    }),
  )
  assert_true(!plan.dependency_updates.any(d => d.producer == "npm:@acme/ws"))

  let cyclic_cfg = "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"native\",\"ecosystem\":\"moonbit\",\"root\":\".\",\"manager\":\"moon\",\"includeRoot\":true},{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\"js\",\"manager\":\"pnpm\",\"includeRoot\":false}],\"bridges\":[{\"consumer\":\"npm:@acme/core\",\"producer\":\"moonbit:acme/native\",\"kind\":\"build\",\"bump\":\"patch\",\"waitFor\":\"build\"},{\"consumer\":\"moonbit:acme/native\",\"producer\":\"npm:@acme/core\",\"kind\":\"build\",\"bump\":\"patch\",\"waitFor\":\"build\"}]}}}"
  let cyclic_ws = snapshot([mbt, js_core], config=cyclic_cfg)
  let rejected = try {
    ignore(@engine.build_plan(cyclic_ws, [change("moonbit:acme/native")]))
    false
  } catch {
    @model.Invalid(d) => d.code == "dependency-cycle"
    _ => false
  }
  assert_true(rejected)
}

///|
test "MIX-005 MIX-006 pre fixed group stays monotonic on v3 pre model" {
  let pre_state = @engine.parse_pre_state(
    "{\"mode\":\"pre\",\"tag\":\"alpha\"}",
  )
  let ws = snapshot(
    [
      unit("acme/a", version="1.0.0-alpha.0"),
      unit("acme/b", version="1.0.0-alpha.0"),
    ],
    config="{\"fixed\":[[\"acme/a\",\"acme/b\"]]}",
  )
  let plan = @engine.build_plan(
    ws,
    [change("acme/a", bump="minor", id="c2")],
    pre=pre_state,
  )
  assert_eq(plan.releases.length(), 2)
  assert_eq(plan.releases[0].new_version, "1.0.0-alpha.1")
  assert_eq(plan.releases[1].new_version, "1.0.0-alpha.1")
}
