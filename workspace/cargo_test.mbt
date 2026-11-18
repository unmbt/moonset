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
  assert_eq(loaded.snapshot.units[0].ecosystem, "cargo")
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
