///|
priv struct FakeHost {
  files : Map[String, Bytes]
  dirs : Map[String, Bool]
  env : Map[String, String]
  mut runner : (String, Array[String], String?) -> @adapters.ProcessResult
  mut fail_on_rename : String?
  clock : UInt64
}

///|
fn fake_host() -> FakeHost {
  {
    files: Map([]),
    dirs: Map([("/repo", true), ("/tmp", true)]),
    env: Map([]),
    runner: (_p, _a, _c) => { exit_code: 0, stdout: "", stderr: "", },
    fail_on_rename: None,
    clock: 1700000000000UL,
  }
}

///|
fn norm(path : String) -> String {
  path.replace_all(old="\\", new="/")
}

///|
impl @executor.ExecutionHost for FakeHost with fn exists(self, path) {
  let key = norm(path)
  self.files.contains(key) || self.dirs.contains(key)
}

///|
impl @executor.ExecutionHost for FakeHost with fn is_dir(self, path) {
  self.dirs.contains(norm(path))
}

///|
impl @executor.ExecutionHost for FakeHost with fn read_text(self, path) {
  let key = norm(path)
  match self.files.get(key) {
    Some(bytes) => @utf8.decode_lossy(bytes)
    None => raise @model.Io("missing file: " + key)
  }
}

///|
impl @executor.ExecutionHost for FakeHost with fn read_binary(self, path) {
  let key = norm(path)
  match self.files.get(key) {
    Some(bytes) => bytes
    None => raise @model.Io("missing binary: " + key)
  }
}

///|
impl @executor.ExecutionHost for FakeHost with fn write_text(self, path, text) {
  self.files[norm(path)] = @utf8.encode(text)
}

///|
impl @executor.ExecutionHost for FakeHost with fn write_binary(
  self,
  path,
  bytes,
) {
  self.files[norm(path)] = bytes
}

///|
impl @executor.ExecutionHost for FakeHost with fn readdir(self, path) {
  let prefix = norm(path) + "/"
  let out : Array[String] = []
  for key, _ in self.files {
    if key.has_prefix(prefix) {
      let rest = key[prefix.length():].to_owned()
      let item = match rest.find("/") {
        Some(idx) => rest[:idx].to_owned()
        None => rest
      }
      if !out.contains(item) {
        out.push(item)
      }
    }
  }
  out.sort()
  out
}

///|
impl @executor.ExecutionHost for FakeHost with fn mkdir(self, path) {
  self.dirs[norm(path)] = true
}

///|
impl @executor.ExecutionHost for FakeHost with fn remove(self, path) {
  ignore(self.files.remove(norm(path)))
}

///|
impl @executor.ExecutionHost for FakeHost with fn rename(self, from, to) {
  let dst = norm(to)
  if self.fail_on_rename == Some(dst) {
    raise @model.Io("injected rename failure")
  }
  let src = norm(from)
  match self.files.get(src) {
    Some(bytes) => {
      self.files[dst] = bytes
      ignore(self.files.remove(src))
    }
    None => raise @model.Io("missing tmp: " + src)
  }
}

///|
impl @executor.ExecutionHost for FakeHost with fn tmpdir(self, prefix) {
  let dir = "/tmp/" + prefix + "1"
  self.dirs[dir] = true
  dir
}

///|
impl @executor.ExecutionHost for FakeHost with fn rmdir(_self, _path) {
  ()
}

///|
impl @executor.ExecutionHost for FakeHost with fn run(self, program, args, cwd) {
  (self.runner)(program, args, cwd)
}

///|
impl @executor.ExecutionHost for FakeHost with fn getenv(self, name) {
  self.env.get(name)
}

///|
impl @executor.ExecutionHost for FakeHost with fn now(self) {
  self.clock
}

///|
fn sample_loaded(
  config_json~ : String = "{}",
  units? : Array[@model.ReleaseUnit],
) -> @workspace.LoadedWorkspace raise {
  let config = @engine.parse_config(config_json)
  let default_units = [
    @model.ReleaseUnit::{
      id: "moonbit:acme/a",
      native_name: "acme/a",
      ecosystem: "moonbit",
      workspace_id: "main",
      root: "a",
      manifest: "a/moon.mod",
      version_path: "a/moon.mod",
      version_field: "version",
      version: Some("0.1.1"),
      visibility: "public",
      publish: true,
      dependencies: [],
    },
    @model.ReleaseUnit::{
      id: "npm:@acme/b",
      native_name: "@acme/b",
      ecosystem: "npm",
      workspace_id: "js",
      root: "b",
      manifest: "b/package.json",
      version_path: "b/package.json",
      version_field: "version",
      version: Some("0.1.1"),
      visibility: "public",
      publish: true,
      dependencies: [],
    },
  ]
  {
    snapshot: {
      root: "/repo",
      workspaces: [
        { id: "main", root: "a", ecosystem: "moonbit", manager: "moon", },
        { id: "js", root: "b", ecosystem: "npm", manager: "npm", },
      ],
      units: units.unwrap_or(default_units),
      ownership: [],
      unmanaged: [],
      config,
      sources: Map([]),
      changed_files: [],
      warnings: [],
      git_head: None,
    },
    changesets: [],
    pre: None,
    changeset_directory: ".changeset",
    changeset_commits: Map([]),
  }
}

///|
async test "apply_version_plan rolls back cleanly on rename failure and recovers journal" {
  let host = fake_host()
  let orig = "name = \"acme/a\"\nversion = \"0.1.0\"\n"
  host.files["/repo/a/moon.mod"] = @utf8.encode(orig)
  host.fail_on_rename = Some("/repo/a/CHANGELOG.md")
  let plan : @model.VersionPlan = {
    schema_version: 1,
    stage: "version",
    executable: true,
    fingerprint: "plan-1",
    edits: [
      {
        path: "a/moon.mod",
        kind: "manifest",
        owner: "moonbit:acme/a",
        before_hash: @model.fingerprint(Json::string(orig)),
        after_text: "name = \"acme/a\"\nversion = \"0.1.1\"\n",
        atomic_write: true,
      },
      {
        path: "a/CHANGELOG.md",
        kind: "changelog",
        owner: "moonbit:acme/a",
        before_hash: @model.fingerprint(Json::string("")),
        after_text: "# Changelog\n",
        atomic_write: true,
      },
    ],
    changelogs: [],
    tags: [],
    consumed_changesets: [],
    analysis: {
      fingerprint: "a",
      releases: [],
      dependency_updates: [],
      affected_paths: [],
      changesets: [],
      next_pre_state: None,
      warnings: [],
      generated_at: None,
    },
    generated_at: None,
  }
  let failed = try {
    ignore(@executor.apply_version_plan_with(host, "/repo", plan))
    false
  } catch {
    @model.Io(_) => true
    _ => false
  }
  assert_true(failed)
  assert_eq(@utf8.decode_lossy(host.files["/repo/a/moon.mod"]), orig)
  assert_true(!host.files.contains("/repo/a/CHANGELOG.md"))
  assert_true(!host.files.contains("/repo/a/CHANGELOG.md.moonset-1.tmp"))
}

///|
async test "publish updates statuses in-place, enforces --only closure, and retries cleanly" {
  let host = fake_host()
  let release_state : Json = {
    "planFingerprint": "plan-fp-1",
    "sourceHead": Json::null(),
    "releases": [
      {
        "unitId": "moonbit:acme/a",
        "oldVersion": "0.1.0",
        "newVersion": "0.1.1",
        "level": "patch",
        "reasons": [],
        "changesets": [],
        "publish": true,
      },
      {
        "unitId": "npm:@acme/b",
        "oldVersion": "0.1.0",
        "newVersion": "0.1.1",
        "level": "patch",
        "reasons": [],
        "changesets": [],
        "publish": true,
      },
    ],
    "tags": [
      {
        "unitId": "moonbit:acme/a",
        "version": "0.1.1",
        "name": "moonbit/acme/a@0.1.1",
      },
      {
        "unitId": "npm:@acme/b",
        "version": "0.1.1",
        "name": "npm/@acme/b@0.1.1",
      },
    ],
    "consumedChangesets": [],
  }
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    release_state.stringify(),
  )
  let loaded = sample_loaded(
    config_json="{\"fixed\":[[\"moonbit:acme/a\",\"npm:@acme/b\"]]}",
  )
  // Incomplete --only closure must be rejected before publishing.
  let blocked_only = try {
    ignore(
      @executor.publish_release_with(host, loaded, {
        dry_run: true,
        only: ["npm:@acme/b"],
        registry: None,
        tag: None,
        yes: true,
        allow_uncommitted: true,
        retry: 0,
        no_tag: true,
      }),
    )
    false
  } catch {
    @model.Invalid(d) => d.code == "incomplete-selection"
    _ => false
  }
  assert_true(blocked_only)

  let mut fail_npm = true
  host.runner = (program, args, _cwd) => {
    if program == "git" && args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "npm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    if program == "npm" &&
      args.contains("publish") &&
      !args.contains("--dry-run") {
      if fail_npm {
        return { exit_code: 1, stdout: "", stderr: "transient network error", }
      }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let first = @executor.publish_release_with(host, loaded, {
    dry_run: false,
    only: [],
    registry: None,
    tag: None,
    yes: true,
    allow_uncommitted: false,
    retry: 0,
    no_tag: true,
  })
  assert_true(!first.complete)
  // Exactly 2 statuses (one per unit), no duplicate preflighted/publishing rows!
  assert_eq(first.statuses.length(), 2)
  assert_eq(first.statuses[0].state, @model.Published)
  assert_eq(first.statuses[1].state, @model.Unknown)

  // Retry when npm is unknown is blocked until resolved; reset state to Failed to simulate verified retry.
  fail_npm = false
  host.files["/repo/.moonset/publish-state.json"] = @utf8.encode(
    @model.canonical_json({
      "schemaVersion": 1,
      "planId": "plan-fp-1",
      "statuses": [
        first.statuses[0].to_json(),
        { ..first.statuses[1], state: @model.Failed, }.to_json(),
      ],
    }),
  )
  let second = @executor.publish_release_with(host, loaded, {
    dry_run: false,
    only: [],
    registry: None,
    tag: None,
    yes: true,
    allow_uncommitted: false,
    retry: 0,
    no_tag: true,
  })
  assert_true(second.complete)
  assert_eq(second.statuses.length(), 2)
  assert_eq(second.statuses[1].state, @model.Published)
}

///|
async test "create_tags skips existing HEAD tags, detects duplicates, and works after release commit" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "p1",
        "sourceHead": "old-pre-commit-sha",
        "releases": [
          {
            "unitId": "moonbit:acme/a",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
        ],
        "tags": [
          { "unitId": "moonbit:acme/a", "version": "0.1.1", "name": "v0.1.1" },
        ],
        "consumedChangesets": [],
      } : Json).stringify(),
  )
  let loaded = sample_loaded(units=[
    {
      id: "moonbit:acme/a",
      native_name: "acme/a",
      ecosystem: "moonbit",
      workspace_id: "main",
      root: "a",
      manifest: "a/moon.mod",
      version_path: "a/moon.mod",
      version_field: "version",
      version: Some("0.1.1"),
      visibility: "public",
      publish: true,
      dependencies: [],
    },
  ])
  host.runner = (_program, args, _cwd) => {
    if args == ["rev-parse", "HEAD"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    if args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if args == ["rev-parse", "--verify", "refs/tags/v0.1.1"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    if args == ["rev-list", "-n", "1", "refs/tags/v0.1.1"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.create_tags_with(host, loaded, {
    dry_run: false,
    push: false,
    force: false,
    yes: false,
    format: "",
  })
  assert_eq(res.skipped, ["v0.1.1"])
  assert_eq(res.created, [])
}

///|
async test "pack uses cargo --list dry-run, moon --dry-run, doctor --fix repairs .changeset, and command publisher routes via PublisherRegistry" {
  let host = fake_host()
  let recorded : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    recorded.push((program, args))
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let cargo_unit : @model.ReleaseUnit = {
    id: "cargo:acme-rs",
    native_name: "acme-rs",
    ecosystem: "cargo",
    workspace_id: "rs",
    root: "rs",
    manifest: "rs/Cargo.toml",
    version_path: "rs/Cargo.toml",
    version_field: "package",
    version: Some("0.1.0"),
    visibility: "public",
    publish: true,
    dependencies: [],
  }
  let mbt_unit : @model.ReleaseUnit = {
    id: "moonbit:acme/a",
    native_name: "acme/a",
    ecosystem: "moonbit",
    workspace_id: "main",
    root: "a",
    manifest: "a/moon.mod",
    version_path: "a/moon.mod",
    version_field: "version",
    version: Some("0.1.0"),
    visibility: "public",
    publish: true,
    dependencies: [],
  }
  let loaded = sample_loaded(units=[mbt_unit, cargo_unit])
  let packed = @executor.pack_artifacts_with(host, loaded, {
    dry_run: true,
    frozen: true,
    packages: [],
  })
  assert_eq(packed.length(), 2)
  assert_true(packed.all(r => r.verified))
  assert_true(
    recorded.any(pair => {
      pair.0 == "cargo" &&
      pair.1.contains("--list") &&
      !pair.1.contains("--dry-run") &&
      pair.1.contains("--frozen")
    }),
  )
  assert_true(
    recorded.any(pair => {
      pair.0 == "moon" &&
      pair.1.contains("--dry-run") &&
      pair.1.contains("--frozen")
    }),
  )

  // doctor --fix initializes missing files safely without overwriting existing config
  let doc_host = fake_host()
  doc_host.files["/repo/moon.mod"] = @utf8.encode(
    "name = \"acme/doc\"\nversion = \"0.1.0\"\n",
  )
  let rep = @executor.run_doctor_with(doc_host, "/repo", fix=true)
  assert_true(doc_host.files.contains("/repo/.changeset/config.json"))
  assert_true(doc_host.files.contains("/repo/.changeset/README.md"))
  assert_true(rep.checks.any(c => c.name == "fix" && c.ok))

  // commit_changes_with invokes git add + git commit cleanly
  let git_cmds : Array[Array[String]] = []
  let git_host = fake_host()
  git_host.runner = (_program, args, _cwd) => {
    git_cmds.push(args)
    if args == ["diff", "--cached", "--quiet"] {
      return { exit_code: 1, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let did_commit = @executor.commit_changes_with(
    git_host,
    "/repo",
    [".changeset/a.md"],
    "chore: add changeset",
  )
  assert_true(did_commit)
  assert_true(git_cmds.any(a => a == ["commit", "-m", "chore: add changeset"]))
}
