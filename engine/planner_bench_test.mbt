///|
priv struct SyntheticChangeset {
  id : String
  path : String
  text : String
}

///|
fn synthetic_scale_fixture(
  unit_count : Int32,
  changeset_count : Int32,
) -> (@model.WorkspaceSnapshot, Array[SyntheticChangeset]) {
  let units : Array[@model.ReleaseUnit] = []
  let changed_files : Array[String] = []
  for i in 0..<unit_count {
    let name = "acme/pkg-" + i.to_string()
    let id = "moonbit:" + name
    let root = "packages/pkg-" + i.to_string()
    let manifest = root + "/moon.mod"
    let deps : Array[@model.DependencyEdge] = []
    if i > 0 {
      deps.push({
        producer: "moonbit:acme/pkg-" + (i - 1).to_string(),
        requirement: "1.0.0",
        kind: @model.Runtime,
        path: manifest,
        start: 0,
        end: 0,
        target_condition: None,
      })
    }
    if i >= 10 && i % 5 == 0 {
      deps.push({
        producer: "moonbit:acme/pkg-0",
        requirement: "1.0.0",
        kind: @model.Runtime,
        path: manifest,
        start: 0,
        end: 0,
        target_condition: None,
      })
    }
    units.push({
      id,
      native_name: name,
      ecosystem: "moonbit",
      workspace_id: "main",
      root,
      manifest,
      version_path: manifest,
      version_field: "version",
      version: Some("1.0.0"),
      visibility: "public",
      publish: true,
      dependencies: deps,
    })
    changed_files.push(root + "/lib.mbt")
  }
  let config : @model.Config = {
    ..@model.Config::default(),
    fixed: [
      ["moonbit:acme/pkg-0", "moonbit:acme/pkg-1", "moonbit:acme/pkg-2"],
      ["moonbit:acme/pkg-50", "moonbit:acme/pkg-51", "moonbit:acme/pkg-52"],
    ],
  }
  let snapshot : @model.WorkspaceSnapshot = {
    root: "/bench-repo",
    workspaces: [
      { id: "main", root: "", ecosystem: "moonbit", manager: "moon", },
    ],
    units,
    ownership: [],
    unmanaged: [],
    config,
    sources: Map([]),
    changed_files,
    warnings: [],
    git_head: Some("benchhead"),
  }
  let changesets : Array[SyntheticChangeset] = []
  for j in 0..<changeset_count {
    let idx = j % unit_count
    let bump = if j % 20 == 0 { "minor" } else { "patch" }
    let id = "cs-" + j.to_string()
    let path = ".changeset/" + id + ".md"
    let text = "---\n\"moonbit:acme/pkg-" +
      idx.to_string() +
      "\": " +
      bump +
      "\n---\n\nUpdate pkg-" +
      idx.to_string() +
      " (#" +
      j.to_string() +
      ")\n"
    changesets.push({ id, path, text, })
  }
  (snapshot, changesets)
}

///|
test "NFR-005 synthetic 100 units and 1000 changesets correctness" {
  let (snapshot, sources) = synthetic_scale_fixture(100, 1000)
  let parsed : Array[@model.Changeset] = []
  for item in sources {
    parsed.push(@engine.parse_changeset(item.text, id=item.id, path=item.path))
  }
  let plan = @engine.build_plan(snapshot, parsed)
  assert_eq(plan.releases.length(), 100)
  assert_eq(plan.releases[0].new_version, "1.1.0")
  assert_eq(plan.releases[1].new_version, "1.1.0")
  assert_eq(plan.releases[2].new_version, "1.1.0")
  let status = @engine.status_json(snapshot, plan)
  assert_true(status is { "hasRelease": True, "errors": [], .. })
  let md = @engine.status_markdown(snapshot, plan)
  assert_true(md.has_prefix("<!-- moonset-bot:changeset-check -->"))
}

///|
test "bench: parse + plan + status (100 units / 1000 changesets)" (b : @bench.T) {
  let (snapshot, sources) = synthetic_scale_fixture(100, 1000)
  b.bench(name="nfr005-100u-1000cs", () => {
    let parsed : Array[@model.Changeset] = []
    for item in sources {
      parsed.push(
        try! @engine.parse_changeset(item.text, id=item.id, path=item.path),
      )
    }
    let plan = try! @engine.build_plan(snapshot, parsed)
    let json = @engine.status_json(snapshot, plan)
    let md = @engine.status_markdown(snapshot, plan)
    b.keep((json, md))
  })
}
