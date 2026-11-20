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
  assert_eq(loaded.snapshot.units[0].visibility, @model.Restricted)
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
  write(root, "moon.work", "members = [\"a\"]")
  write(
    root, ".changeset/config.json", "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"moon\",\"ecosystem\":\"moonbit\",\"root\":\".\",\"manager\":\"moon\",\"includeRoot\":false},{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\".\",\"manager\":\"pnpm\",\"includeRoot\":true}]}}}",
  )
  write(
    root, "package.json", "{\"name\":\"acme/root\",\"version\":\"1.0.0\",\"private\":true}",
  )
  let accepted = try {
    ignore(@workspace.discover(root))
    true
  } catch {
    _ => false
  }
  assert_true(accepted)
}

///|
async test "coexist uses a separate changeset directory and excludes nested checkout" {
  let root = @fs.tmpdir(prefix="moonset-coexist-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write(root, "moon.work", "members = [\"packages/a\", \"vendor\"]")
  write(root, "packages/a/moon.mod", "name = \"acme/a\"\nversion = \"0.1.0\"")
  write(root, "vendor/.git", "gitdir: ../other")
  write(root, "vendor/moon.mod", "name = \"acme/vendor\"\nversion = \"9.0.0\"")
  write(root, ".changeset/config.json", "{\"baseBranch\":\"main\"}")
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
  assert_eq(loaded.snapshot.unmanaged, [
    "changeset-config:.changeset/config.json",
  ])
  let plan = @engine.build_plan(loaded.snapshot, loaded.changesets)
  assert_eq(plan.releases[0].new_version, "0.1.1")
  assert_true(
    @engine.status_json(
      loaded.snapshot,
      plan,
      changeset_directory=loaded.changeset_directory,
    )
    is {
      "coexistence": {
        "mode": "coexist",
        "managedWorkspaces": ["moon"],
        "foreignChangesetDirectories": [".changeset"],
        ..
      },
      ..
    },
  )
  assert_eq(
    @fs.read_text(
      @path.Path(root).join(@path.Path(".changeset/js.md")).to_string(),
    ),
    "This belongs to another tool and is not a Moonset changeset",
  )
}

///|
async test "mixed publisher overrides, custom changelog.file preload, and --since npm/cargo glob isolation" {
  let root = @fs.tmpdir(prefix="moonset-mixed-since-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  ignore(run_git(root, ["init", "-b", "main"]))
  ignore(run_git(root, ["config", "user.email", "test@example.invalid"]))
  ignore(run_git(root, ["config", "user.name", "Moonset Test"]))
  write(
    root, ".changeset/config.json", "{\"changelog\":{\"generator\":\"builtin\",\"file\":\"HISTORY.md\"},\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\"js\",\"manager\":\"npm\",\"includeRoot\":false},{\"id\":\"rs\",\"ecosystem\":\"cargo\",\"root\":\"rs\",\"manager\":\"cargo\",\"includeRoot\":false}],\"units\":{\"npm:@acme/a\":{\"publisher\":\"npm\"},\"cargo:acme-rs\":{\"publisher\":\"cargo\"}}}}}",
  )
  write(
    root, "js/package.json", "{\"name\":\"js-root\",\"workspaces\":[\"packages/*\"]}",
  )
  write(
    root, "js/packages/a/package.json", "{\"name\":\"@acme/a\",\"version\":\"1.0.0\"}",
  )
  write(root, "js/packages/a/HISTORY.md", "# History\n")
  write(root, "rs/Cargo.toml", "[workspace]\nmembers = [\"crates/*\"]\n")
  write(
    root, "rs/crates/a/Cargo.toml", "[package]\nname = \"acme-rs\"\nversion = \"0.1.0\"\n",
  )
  write(root, "rs/crates/a/HISTORY.md", "# Rust History\n")
  ignore(run_git(root, ["add", "."]))
  ignore(run_git(root, ["commit", "-m", "init"]))
  let base = run_git(root, ["rev-parse", "HEAD"])
  // Create uncommitted packages that MUST NOT leak into --since discovery
  write(
    root, "js/packages/dirty/package.json", "{\"name\":\"@acme/dirty\",\"version\":\"9.9.9\"}",
  )
  write(
    root, "rs/crates/dirty/Cargo.toml", "[package]\nname = \"acme-dirty\"\nversion = \"9.9.9\"\n",
  )
  let loaded = @workspace.discover(root, since=base)
  assert_eq(loaded.snapshot.units.map(u => u.id), [
    "npm:@acme/a", "cargo:acme-rs",
  ])
  assert_eq(
    loaded.snapshot.sources.get("js/packages/a/HISTORY.md"),
    Some("# History\n"),
  )
  assert_eq(
    loaded.snapshot.sources.get("rs/crates/a/HISTORY.md"),
    Some("# Rust History\n"),
  )
}

///|
async test "Cargo publish=[], inline version span with path, ** glob, pnpm comments, and Git changeset commits" {
  let root = @fs.tmpdir(prefix="moonset-cargo-pnpm-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  ignore(run_git(root, ["init", "-b", "main"]))
  ignore(run_git(root, ["config", "user.email", "test@example.invalid"]))
  ignore(run_git(root, ["config", "user.name", "Moonset Test"]))
  write(
    root, ".changeset/config.json", "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\"js\",\"manager\":\"pnpm\",\"includeRoot\":false},{\"id\":\"rs\",\"ecosystem\":\"cargo\",\"root\":\"rs\",\"manager\":\"cargo\",\"includeRoot\":false}]}}}",
  )
  write(root, "js/package.json", "{\"name\":\"js-root\"}")
  write(
    root, "js/pnpm-workspace.yaml", "packages: # root workspaces\n  - \"packages/*\" # public\n  - \"!packages/ignored\"\n",
  )
  write(
    root, "js/packages/app/package.json", "{\"name\":\"@acme/app\",\"version\":\"1.0.0\",\"private\":true}",
  )
  write(
    root, "js/packages/ignored/package.json", "{\"name\":\"@acme/ignored\",\"version\":\"1.0.0\"}",
  )
  write(root, "rs/Cargo.toml", "[workspace]\nmembers = [\"crates/**\"]\n")
  write(
    root, "rs/crates/core/Cargo.toml", "[package]\nname = \"acme-core\"\nversion = \"0.1.0\"\npublish = []\n",
  )
  write(
    root, "rs/crates/nested/app/Cargo.toml", "[package]\nname = \"acme-app\"\nversion = \"0.1.0\"\n\n[dependencies]\nacme-core = { path = \"../../version-core\", version = \"0.1.0\" }\n",
  )
  write(
    root, ".changeset/c1.md", "---\n\"cargo:acme-core\": patch\n---\nCore patch",
  )
  ignore(run_git(root, ["add", "."]))
  ignore(run_git(root, ["commit", "-m", "initial commit"]))
  let head = run_git(root, ["rev-parse", "HEAD"])
  let loaded = @workspace.discover(root)
  assert_eq(loaded.changeset_commits.get("c1"), Some(head))
  let core = loaded.snapshot.units
    .iter()
    .find_first(u => u.id == "cargo:acme-core")
    .unwrap()
  assert_false(core.publish)
  let app = loaded.snapshot.units
    .iter()
    .find_first(u => u.id == "cargo:acme-app")
    .unwrap()
  let dep = app.dependencies[0]
  let app_src = loaded.snapshot.sources[app.manifest]
  assert_eq(
    @utf8.decode_lossy(@utf8.encode(app_src)[dep.start:dep.end]),
    "0.1.0",
  )
  assert_false(loaded.snapshot.units.any(u => u.id == "npm:@acme/ignored"))
}

///|
async test "SDD minimal fixtures discover and validate expected plans" {
  let single = @workspace.discover("fixtures/single-module")
  assert_eq(
    @engine.build_plan(single.snapshot, single.changesets).releases[0].new_version,
    "0.1.1",
  )

  let two = @workspace.discover("fixtures/workspace-two-modules")
  let two_plan = @engine.build_plan(two.snapshot, two.changesets)
  assert_eq(two_plan.releases.length(), 2)

  let fixed_linked = @workspace.discover("fixtures/fixed-and-linked")
  let fl_plan = @engine.build_plan(
    fixed_linked.snapshot,
    fixed_linked.changesets,
  )
  assert_eq(fl_plan.releases.length(), 3)

  let priv_ign = @workspace.discover("fixtures/private-and-ignore")
  let pi_plan = @engine.build_plan(priv_ign.snapshot, priv_ign.changesets)
  assert_eq(pi_plan.releases.map(r => r.unit_id), [
    "moonbit:acme/pub", "moonbit:acme/priv",
  ])

  let pre_fx = @workspace.discover("fixtures/prerelease")
  let pre_plan = @engine.build_plan(
    pre_fx.snapshot,
    pre_fx.changesets,
    pre?=pre_fx.pre,
  )
  assert_eq(pre_plan.releases[0].new_version, "0.2.0-alpha.1")

  let invalid_rejected = try {
    ignore(@workspace.discover("fixtures/invalid-frontmatter"))
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(invalid_rejected)
}

///|
async test "FR-029 workspace discovery loads pre.directory changesets across active and exit pre modes" {
  let root = @fs.tmpdir(prefix="moonset-pre-dir-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write(
    root, "moon.mod", "name = \"acme/preiso\"\nversion = \"0.2.0-alpha.0\"\n",
  )
  write(
    root, ".changeset/config.json", "{\"schemaVersion\":1,\"pre\":{\"file\":\".changeset/pre.json\",\"directory\":\".changeset/pre\"}}",
  )
  write(
    root, ".changeset/pre.json", "{\"mode\":\"active\",\"tag\":\"alpha\",\"initialVersions\":{\"moonbit:acme/preiso\":\"0.1.0\"},\"nextNumbers\":{\"moonbit:acme/preiso\":1},\"consumed\":[\"c1\"]}\n",
  )
  write(
    root, ".changeset/pre/c1.md", "---\nacme/preiso: minor\n---\nAlready prereleased\n",
  )
  write(
    root, ".changeset/c2.md", "---\nacme/preiso: patch\n---\nSecond prerelease fix\n",
  )
  let loaded_active = @workspace.discover(root, include_commits=false)
  assert_eq(loaded_active.changesets.length(), 2)
  assert_true(
    loaded_active.changesets.any(c => c.path == ".changeset/pre/c1.md"),
  )
  assert_true(loaded_active.changesets.any(c => c.path == ".changeset/c2.md"))
  let plan_active = @engine.build_plan(
    loaded_active.snapshot,
    loaded_active.changesets,
    pre?=loaded_active.pre,
  )
  assert_eq(plan_active.releases.length(), 1)
  assert_eq(plan_active.releases[0].new_version, "0.2.0-alpha.1")
  assert_eq(plan_active.releases[0].changesets, ["c2"])

  // Switch to exit mode: both isolated c1 and c2 are discovered and deleted upon graduation
  write(
    root, ".changeset/pre.json", "{\"mode\":\"exit\",\"tag\":\"alpha\",\"initialVersions\":{\"moonbit:acme/preiso\":\"0.1.0\"},\"nextNumbers\":{\"moonbit:acme/preiso\":1},\"consumed\":[\"c1\"]}\n",
  )
  let loaded_exit = @workspace.discover(root, include_commits=false)
  assert_eq(loaded_exit.changesets.length(), 2)
  let plan_exit = @engine.build_plan(
    loaded_exit.snapshot,
    loaded_exit.changesets,
    pre?=loaded_exit.pre,
  )
  let vp_exit = @engine.build_version_plan(
    loaded_exit.snapshot,
    plan_exit,
    { dry_run: true, no_changelog: false, snapshot: false, snapshot_tag: None, },
    generated_at="2026-11-19",
  )
  assert_eq(vp_exit.tags[0].version, "0.2.0")
  assert_true(
    vp_exit.edits.any(e => {
      e.path == ".changeset/pre/c1.md" && e.after_text == ""
    }),
  )
  assert_true(
    vp_exit.edits.any(e => e.path == ".changeset/c2.md" && e.after_text == ""),
  )
}

///|
async test "v0.3.0 npm includeRoot, pnpm precedence, publishConfig, packages/build, AGENTS.md ignore" {
  let root = @fs.tmpdir(prefix="moonset-npm-v030-")
  defer (@fs.rmdir(root, recursive=true) catch { _ => () })
  write(
    root, ".changeset/config.json", "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\"js\",\"manager\":\"pnpm\",\"includeRoot\":true}]}}}",
  )
  // Should be ignored by changeset discovery
  write(root, ".changeset/AGENTS.md", "# Agent instructions")
  write(root, ".changeset/readme.md", "# Readme")
  write(
    root, "js/package.json", "{\"name\":\"@acme/js-root\",\"version\":\"1.0.0\",\"workspaces\":[\"ignored-by-pnpm/*\"]}",
  )
  write(
    root, "js/pnpm-workspace.yaml", "packages: ['packages/*', '!packages/skip']\n",
  )
  write(
    root, "js/packages/build/package.json", "{\"name\":\"@acme/build\",\"version\":\"0.4.0\",\"publishConfig\":{\"access\":\"restricted\",\"registry\":\"https://npm.example.test\",\"directory\":\"dist\"}}",
  )
  write(
    root, "js/packages/skip/package.json", "{\"name\":\"@acme/skip\",\"version\":\"0.1.0\"}",
  )
  let loaded = @workspace.discover(root, include_commits=false)
  assert_eq(loaded.changesets.length(), 0)
  assert_eq(loaded.snapshot.units.map(u => u.id), [
    "npm:@acme/build", "npm:@acme/js-root",
  ])
  let build_pkg = loaded.snapshot.units[0]
  assert_true(build_pkg.publish_config is Some(_))
  let pc = build_pkg.publish_config.unwrap()
  assert_eq(pc.access, Some(@model.Access::Restricted))
  assert_eq(pc.registry, Some("https://npm.example.test"))
  assert_eq(pc.directory, Some("dist"))
  assert_true(build_pkg.version_span is Some(_))
  // Managed root manifest must NOT be reported as unmanaged
  assert_false(loaded.snapshot.unmanaged.contains("js/package.json"))
}
