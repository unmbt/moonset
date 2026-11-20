///|
async test "discover cargo workspace members and inherited versions" {
  let root = @fs.tmpdir(prefix="moonset-cargo-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(
    @path.Path(root).join(@path.Path(".changeset")).to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(
    @path.Path(root).join(@path.Path(".changeset/config.json")).to_string(),
    "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"rust\",\"ecosystem\":\"cargo\",\"root\":\".\",\"manager\":\"cargo\",\"includeRoot\":false}]}}}",
  )
  @fs.write_text(
    @path.Path(root).join(@path.Path("Cargo.toml")).to_string(),
    "[workspace]\nmembers = [\"crates/*\"]\n[workspace.package]\nversion = \"1.2.3\"\n",
  )
  for name in ["a", "b"] {
    let path = @path.Path(root).join(@path.Path("crates/" + name)).to_string()
    @fs.mkdir(path, recursive=true, allow_exist=true)
    @fs.write_text(
      @path.Path(path).join(@path.Path("Cargo.toml")).to_string(),
      if name == "a" {
        "[package]\nname = \"acme-a\"\nversion.workspace = true\n[dependencies]\nacme-b = { path = \"../b\", version = \"^1.2.3\" }\n[dev-dependencies]\nacme-b = { path = \"../b\", version = \"~1.2.3\", optional = true }\n[target.'cfg(unix)'.dependencies]\nacme-b = { path = \"../b\", version = \"^1.2.3\" }\n"
      } else {
        "[package]\nname = \"acme-b\"\nversion.workspace = true\n"
      },
    )
  }
  let loaded = @workspace.discover(root) catch {
    @model.Invalid(diagnostic) => {
      println(
        diagnostic.code + ": " + diagnostic.message + " @ " + diagnostic.path,
      )
      fail("discovery failed")
    }
    @model.Io(message) => fail(message)
    _ => fail("unexpected discovery error")
  }
  assert_eq(loaded.snapshot.units.length(), 2)
  assert_eq(loaded.snapshot.units[0].ecosystem, @model.Cargo)
  assert_eq(loaded.snapshot.units[0].version, Some("1.2.3"))
  assert_eq(loaded.snapshot.units[0].dependencies.length(), 3)
  assert_true(
    loaded.snapshot.units[0].dependencies.any(x => x.kind == @model.Optional),
  )
  assert_true(
    loaded.snapshot.units[0].dependencies.any(x => {
      x.target_condition == Some("cfg(unix)")
    }),
  )
  let plan = @engine.build_plan(loaded.snapshot, [
    {
      id: "cargo-release",
      releases: [{ unit_id: "cargo:acme-a", bump: @model.Patch, }],
      summary: "Cargo release",
      path: ".changeset/cargo.md",
      in_pre_dir: false,
    },
  ]) catch {
    @model.Invalid(diagnostic) => {
      println(
        diagnostic.code + ": " + diagnostic.message + " @ " + diagnostic.path,
      )
      fail("planning failed")
    }
    @model.Io(message) => fail(message)
  }
  assert_eq(plan.releases.length(), 2)
  let executable = @engine.build_version_plan(loaded.snapshot, plan, @model.VersionOptions::{
    dry_run: true,
    no_changelog: true,
    snapshot: false,
    snapshot_tag: None,
  }) catch {
    @model.Invalid(diagnostic) => {
      println(
        diagnostic.code + ": " + diagnostic.message + " @ " + diagnostic.path,
      )
      fail("version plan failed")
    }
    @model.Io(message) => fail(message)
  }
  assert_true(
    executable.edits.any(x => {
      x.path == "Cargo.toml" && x.after_text.contains("version = \"1.2.4\"")
    }),
  )
}

///|
async test "v0.3.0 Cargo TOML parser: multiline strings, publish.workspace, subtables, compound inline ranges, exclude, single-crate" {
  let root = @fs.tmpdir(prefix="moonset-cargo-toml-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  @fs.mkdir(
    @path.Path(root).join(@path.Path(".changeset")).to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(
    @path.Path(root).join(@path.Path(".changeset/config.json")).to_string(),
    "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"rust\",\"ecosystem\":\"cargo\",\"root\":\".\",\"manager\":\"cargo\",\"includeRoot\":false}]}}}",
  )
  @fs.write_text(
    @path.Path(root).join(@path.Path("Cargo.toml")).to_string(),
    "[workspace]\nmembers = [\n  \"crates/*\", # comment\n]\nexclude = [\"crates/excluded\"]\n[workspace.package]\nversion = \"1.0.0\"\npublish = false\n",
  )
  for name in ["core", "app", "excluded"] {
    let dir = @path.Path(root).join(@path.Path("crates/" + name)).to_string()
    @fs.mkdir(dir, recursive=true, allow_exist=true)
    @fs.write_text(
      @path.Path(dir).join(@path.Path("Cargo.toml")).to_string(),
      if name == "core" {
        "[package]\nname = \"acme-core\"\ndescription = \"\"\"\nfake\nversion = \"9.9.9\"\n\"\"\"\nversion.workspace = true\npublish.workspace = true\n"
      } else if name == "app" {
        "[package]\nname = \"acme-app\"\nversion = \"0.5.0\"\n\n[dependencies.acme-core]\npath = \"../core\"\nversion = \">=1.0.0, <2.0.0\"\n\n[build-dependencies]\nacme-core = { version = \">=1.0.0, <2.0.0\", path = \"../core\" }\n"
      } else {
        "[package]\nname = \"acme-excluded\"\nversion = \"0.1.0\"\n"
      },
    )
  }
  let loaded = @workspace.discover(root, include_commits=false)
  assert_eq(loaded.snapshot.units.map(u => u.id), [
    "cargo:acme-app", "cargo:acme-core",
  ])
  let core = loaded.snapshot.units
    .iter()
    .find_first(u => u.id == "cargo:acme-core")
    .unwrap()
  assert_eq(core.version, Some("1.0.0"))
  assert_false(core.publish)
  let app = loaded.snapshot.units
    .iter()
    .find_first(u => u.id == "cargo:acme-app")
    .unwrap()
  assert_eq(app.dependencies.length(), 2)
  assert_eq(app.dependencies[0].requirement, ">=1.0.0, <2.0.0")
  assert_eq(app.dependencies[1].requirement, ">=1.0.0, <2.0.0")
  assert_eq(app.dependencies[1].kind, @model.Build)
  // Verify exact version_span points to real version, not multiline description fake version
  assert_true(app.version_span is Some(_))
  let span = app.version_span.unwrap()
  let app_src = loaded.snapshot.sources[app.manifest]
  assert_eq(
    @utf8.decode_lossy(@utf8.encode(app_src)[span.start:span.end]),
    "0.5.0",
  )

  // Single-crate Cargo repository without [workspace]
  let single = @fs.tmpdir(prefix="moonset-cargo-single-")
  defer (@fs.rmdir(single, recursive=true) catch { _ => () })
  @fs.mkdir(
    @path.Path(single).join(@path.Path(".changeset")).to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(
    @path.Path(single).join(@path.Path(".changeset/config.json")).to_string(),
    "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"rust\",\"ecosystem\":\"cargo\",\"root\":\".\",\"manager\":\"cargo\",\"includeRoot\":true}]}}}",
  )
  @fs.write_text(
    @path.Path(single).join(@path.Path("Cargo.toml")).to_string(),
    "[package]\nname = \"solo-crate\"\nversion = \"0.3.0\"\n",
  )
  let solo_loaded = @workspace.discover(single, include_commits=false)
  assert_eq(solo_loaded.snapshot.units.map(u => u.id), ["cargo:solo-crate"])
}
