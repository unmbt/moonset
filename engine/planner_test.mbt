///|
fn unit(
  name : String,
  version~ : String = "0.1.0",
  deps~ : Array[(String, String)] = [],
) -> @model.ReleaseUnit {
  {
    id: "moonbit:" + name,
    native_name: name,
    ecosystem: "moonbit",
    workspace_id: "main",
    root: name,
    manifest: name + "/moon.mod",
    version: Some(version),
    visibility: "public",
    publish: true,
    dependencies: deps.map(pair => {
      producer: "moonbit:" + pair.0,
      requirement: pair.1,
      kind: @model.Runtime,
      path: name + "/moon.mod",
      start: 0,
      end: 0,
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
  let state = @engine.parse_pre_state(
    "{\"mode\":\"active\",\"tag\":\"alpha\",\"initialVersions\":{\"moonbit:acme/a\":\"0.1.0\"},\"nextNumbers\":{},\"consumed\":[]}",
  )
  let ws = snapshot([unit("acme/a")])
  let plan = @engine.build_plan(ws, [change("acme/a", bump="minor")], pre=state)
  assert_eq(plan.releases[0].new_version, "0.2.0-alpha.0")
  assert_eq(plan.next_pre_state.unwrap().next_numbers["moonbit:acme/a"], 1)
  assert_eq(state.consumed.length(), 0)
  assert_eq(state.next_numbers.length(), 0)
  let advanced = snapshot([unit("acme/a", version="0.2.0-alpha.0")])
  let next = @engine.build_plan(
    advanced,
    [change("acme/a", bump="minor")],
    pre=plan.next_pre_state.unwrap(),
  )
  assert_eq(next.releases.length(), 0)
  let exit_state : @model.PreState = {
    ..plan.next_pre_state.unwrap(),
    mode: "exit",
  }
  let stable = @engine.build_plan(advanced, [], pre=exit_state)
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
