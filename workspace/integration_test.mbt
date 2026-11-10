///|
async fn write(root : String, path : String, content : String) -> Unit {
  let absolute = @path.Path(root).join(@path.Path(path)).to_string()
  @fs.mkdir(
    @path.Path(absolute).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(absolute, content)
}

///|
async fn run_git(root : String, args : Array[String]) -> String {
  let out = @shell.Cmd("git", args, cwd=root).output()
  if out.exit_code() != 0 {
    fail(out.stderr())
  }
  out.stdout().trim().to_owned()
}

///|
async test "discover explicit workspace members and same-directory JS without writes" {
  let root = @fs.tmpdir(prefix="moonset-discovery-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  let a = "name = \"acme/a\"\r\nversion = \"0.1.0\"\r\nprivate = true\r\n"
  write(root, "moon.work", "members = [\"./a\", \"./b\"]")
  write(root, "a/moon.mod", a)
  write(
    root, "a/package.json", "{\"name\":\"@acme/a\",\"version\":\"9.0.0\",\"private\":true}",
  )
  write(
    root, "b/moon.mod", "name = \"acme/b\"\nversion = \"0.1.0\"\nimport { \"acme/a@0.1.0\" }",
  )
  write(root, ".changeset/config.json", "{}")
  write(root, ".changeset/change.md", "---\nacme/a: patch\n---\nSummary")
  let loaded = @workspace.discover(root)
  assert_eq(loaded.snapshot.units.length(), 2)
  assert_eq(loaded.snapshot.units[0].visibility, "restricted")
  assert_true(loaded.snapshot.units[0].publish)
  assert_eq(loaded.snapshot.unmanaged, ["a/package.json"])
  let plan = @engine.build_plan(loaded.snapshot, loaded.changesets)
  assert_eq(plan.releases.length(), 1)
  assert_eq(
    @fs.read_text(@path.Path(root).join(@path.Path("a/moon.mod")).to_string()),
    a,
  )
}

///|
async test "HEAD snapshot excludes dirty input and merge-base excludes base-only changesets" {
  let root = @fs.tmpdir(prefix="moonset-git-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  ignore(run_git(root, ["init", "-b", "main"]))
  ignore(run_git(root, ["config", "user.email", "test@example.invalid"]))
  ignore(run_git(root, ["config", "user.name", "Moonset Test"]))
  write(root, "moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"")
  write(root, ".changeset/config.json", "{}")
  write(root, ".changeset/old.md", "---\nacme/a: minor\n---\nAlready pending")
  ignore(run_git(root, ["add", "."]))
  ignore(run_git(root, ["commit", "-m", "base"]))
  let base = run_git(root, ["rev-parse", "HEAD"])
  ignore(run_git(root, ["switch", "-c", "feature"]))
  write(root, "source.mbt", "// changed")
  write(root, ".changeset/new.md", "---\n---\nNo release needed")
  ignore(run_git(root, ["add", "."]))
  ignore(run_git(root, ["commit", "-m", "feature"]))
  write(root, "moon.mod", "this is invalid and must not be parsed in --since")
  let before = run_git(root, ["status", "--porcelain"])
  let loaded = @workspace.discover(root, since=base)
  assert_eq(loaded.snapshot.units[0].version, Some("0.1.0"))
  assert_eq(loaded.changesets.map(x => x.id), ["new"])
  assert_eq(loaded.snapshot.warnings[0].code, "uncommitted-excluded")
  let plan = @engine.build_plan(loaded.snapshot, loaded.changesets)
  assert_true(
    @engine.status_json(loaded.snapshot, plan)
    is { "errors": [], "hasChanges": True, "hasRelease": False, .. },
  )
  assert_eq(run_git(root, ["status", "--porcelain"]), before)
}

///|
async test "workspace escape duplicate ownership and unsupported adapter fail before writes" {
  let root = @fs.tmpdir(prefix="moonset-invalid-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write(root, "moon.work", "members = [\"../outside\"]")
  let rejected = try {
    ignore(@workspace.discover(root))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  write(root, "moon.work", "members = [\"a\", \"./a\"]")
  write(root, "a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"")
  let rejected = try {
    ignore(@workspace.discover(root))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  write(
    root, ".changeset/config.json", "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\".\",\"manager\":\"pnpm\",\"includeRoot\":true}]}}}",
  )
  let rejected = try {
    ignore(@workspace.discover(root))
    false
  } catch {
    @model.Invalid(d) => d.code == "unsupported-capability"
    _ => false
  }
  assert_true(rejected)
}

///|
async test "coexist uses a separate changeset directory and excludes nested checkout" {
  let root = @fs.tmpdir(prefix="moonset-coexist-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write(root, "moon.work", "members = [\"packages/a\", \"vendor\"]")
  write(root, "packages/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"")
  write(root, "vendor/.git", "gitdir: ../other")
  write(root, "vendor/moon.mod", "name = \"acme/vendor\"\nversion = \"9.0.0\"")
  write(
    root, ".changeset/js.md", "This belongs to another tool and is not a Moonset changeset",
  )
  write(
    root, ".moonset/config.json", "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"moon\",\"ecosystem\":\"moonbit\",\"root\":\".\",\"manager\":\"moon\",\"includeRoot\":false}]}}}",
  )
  write(root, ".moonset/release.md", "---\nmoonbit:acme/a: patch\n---\nSummary")
  let loaded = @workspace.discover(root, config_path=".moonset/config.json")
  assert_eq(loaded.snapshot.units.length(), 1)
  assert_eq(loaded.snapshot.units[0].root, "packages/a")
  assert_eq(loaded.changesets.map(x => x.id), ["release"])
  assert_eq(loaded.snapshot.warnings[0].code, "nested-checkout-excluded")
  assert_eq(
    @engine.build_plan(loaded.snapshot, loaded.changesets).releases[0].new_version,
    "0.1.1",
  )
}
