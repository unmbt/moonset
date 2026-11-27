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
impl @executor.ExecutionHost for FakeHost with fn run_with_env(
  self,
  program,
  args,
  cwd,
  _env,
  _stdin,
  _timeout,
) {
  (self.runner)(program, args, cwd)
}

///|
impl @executor.ExecutionHost for FakeHost with fn sleep_ms(_self, _ms) {
  ()
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
fn mk_unit(
  id : String,
  native_name : String,
  ecosystem : @model.Ecosystem,
  workspace_id : String,
  root : String,
  manifest : String,
  version : String?,
  publish~ : Bool = true,
  publish_config? : @model.PublishConfig,
  dependencies~ : Array[@model.DependencyEdge] = [],
) -> @model.ReleaseUnit {
  {
    id,
    native_name,
    ecosystem,
    workspace_id,
    root,
    manifest,
    version_path: manifest,
    version_field: "version",
    version_span: None,
    version,
    visibility: @model.Public,
    publish,
    publish_config,
    dependencies,
  }
}

///|
fn sample_loaded(
  config_json~ : String = "{}",
  units? : Array[@model.ReleaseUnit],
  pre? : @model.PreState,
) -> @workspace.LoadedWorkspace raise {
  let config = @engine.parse_config(config_json)
  let default_units = [
    mk_unit(
      "moonbit:acme/a",
      "acme/a",
      @model.MoonBit,
      "main",
      "a",
      "a/moon.mod",
      Some("0.1.1"),
    ),
    mk_unit(
      "npm:@acme/b",
      "@acme/b",
      @model.Npm,
      "js",
      "b",
      "b/package.json",
      Some("0.1.1"),
    ),
  ]
  {
    snapshot: {
      root: "/repo",
      workspaces: [
        {
          id: "main",
          root: "a",
          ecosystem: @model.MoonBit,
          manager: @model.Moon,
        },
        {
          id: "js",
          root: "b",
          ecosystem: @model.Npm,
          manager: @model.PackageManager::Npm,
        },
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
    pre,
    changeset_directory: ".changeset",
    changeset_commits: Map([]),
  }
}

///|
fn moon_view_404() -> @adapters.ProcessResult {
  {
    exit_code: 0,
    stdout: "{\"version\":1,\"status\":\"failure\",\"result\":null,\"messages\":[{\"level\":\"error\",\"message\":\"HTTP status client error (404 Not Found)\"}]}",
    stderr: "",
  }
}

///|
async test "apply_version_plan rolls back cleanly on rename failure, blocks unfinished journal, and confines recover paths" {
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
      is_snapshot: false,
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

  // Refuses overwriting an existing unfinished journal
  host.fail_on_rename = None
  host.files["/repo/.moonset/version-journal.json"] = @utf8.encode(
    "{\"planFingerprint\":\"old\",\"entries\":[]}",
  )
  let blocked_journal = try {
    ignore(@executor.apply_version_plan_with(host, "/repo", plan))
    false
  } catch {
    @model.Invalid(d) => d.code == "unfinished-journal"
    _ => false
  }
  assert_true(blocked_journal)

  // Refuses path traversal inside tampered journal during recovery
  host.files["/repo/.moonset/version-journal.json"] = @utf8.encode(
    "{\"entries\":[{\"path\":\"../escape.txt\",\"existed\":true,\"content\":\"evil\"}]}",
  )
  let blocked_escape = try {
    ignore(@executor.recover_version_with(host, "/repo"))
    false
  } catch {
    @model.Invalid(d) => d.code == "workspace-escape"
    _ => false
  }
  assert_true(blocked_escape)
}

///|
async test "publish dry-run is strictly read-only, enforces --only closure, allows downstream retry, and supports --reconcile" {
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
      @executor.publish_release_with(
        host,
        loaded,
        @executor.PublishOptions::new(
          dry_run=true,
          only=["npm:@acme/b"],
          yes=true,
          allow_uncommitted=true,
          no_tag=true,
        ),
      ),
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
    if program == "moon" && args.contains("view") {
      return moon_view_404()
    }
    if program == "npm" && args.contains("view") {
      // npm 9/10 empty stdout with exit 0 must also be treated as absent!
      return { exit_code: 0, stdout: "", stderr: "", }
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

  // CRITICAL INVARIANT: `--dry-run` MUST NOT write `.moonset/publish-state.json`!
  let dry = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(dry_run=true, no_tag=true),
  )
  assert_true(dry.dry_run)
  assert_false(host.files.contains("/repo/.moonset/publish-state.json"))

  let first = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(!first.complete)
  assert_eq(first.statuses.length(), 2)
  assert_eq(first.statuses[0].state, @model.Published)
  assert_eq(first.statuses[1].state, @model.Unknown)

  // Retry with `--only npm:@acme/b` + `--reconcile` succeeds because upstream moonbit:acme/a is already Published!
  fail_npm = false
  let second = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(
      only=["npm:@acme/b"],
      yes=true,
      no_tag=true,
      reconcile=true,
    ),
  )
  assert_true(second.complete)
  assert_true(
    second.statuses.any(s => {
      s.unit_id == "npm:@acme/b" && s.state == @model.Published
    }),
  )
}

///|
async test "create_tags uses annotated tags, allows dry-run on dirty tree, and pushes locally skipped tags missing on remote" {
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
    mk_unit(
      "moonbit:acme/a",
      "acme/a",
      @model.MoonBit,
      "main",
      "a",
      "a/moon.mod",
      Some("0.1.1"),
    ),
  ])
  let pushed_cmds : Array[Array[String]] = []
  host.runner = (_program, args, _cwd) => {
    if args == ["rev-parse", "HEAD"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    if args == ["status", "--porcelain"] {
      return {
        exit_code: 0,
        stdout: "?? .moonset/publish-state.json\n?? .moonset/pack-results-linux-x64.json\n",
        stderr: "",
      }
    }
    if args == ["rev-parse", "--verify", "refs/tags/v0.1.1"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    if args == ["rev-list", "-n", "1", "refs/tags/v0.1.1"] {
      return { exit_code: 0, stdout: "new-release-commit-sha\n", stderr: "", }
    }
    if args == ["ls-remote", "--tags", "origin"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if args.length() > 0 && args[0] == "push" {
      pushed_cmds.push(args)
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  // Even though tag already exists locally (skipped), `--push` pushes it because it's missing on origin!
  let res = @executor.create_tags_with(
    host,
    loaded,
    @executor.TagOptions::new(push=true),
  )
  assert_eq(res.skipped, ["v0.1.1"])
  assert_eq(res.created, [])
  assert_eq(res.pushed, ["v0.1.1"])
  assert_eq(pushed_cmds, [["push", "origin", "refs/tags/v0.1.1"]])

  // Dry-run succeeds even when worktree is dirty
  host.runner = (_program, args, _cwd) => {
    if args == ["rev-parse", "HEAD"] {
      return { exit_code: 0, stdout: "sha1\n", stderr: "", }
    }
    if args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: " M README.md\n", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let dry = @executor.create_tags_with(
    host,
    loaded,
    @executor.TagOptions::new(dry_run=true),
  )
  assert_true(dry.dry_run)
  assert_eq(dry.tags, ["v0.1.1"])
}

///|
async test "pack uses cargo --list dry-run, moon --list --target-dir dry-run, doctor --fix omits pre.json gitignore, and commit uses --only" {
  let host = fake_host()
  let recorded : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    recorded.push((program, args))
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let cargo_unit = mk_unit(
    "cargo:acme-rs",
    "acme-rs",
    @model.Cargo,
    "rs",
    "rs",
    "rs/Cargo.toml",
    Some("0.1.0"),
  )
  let mbt_unit = mk_unit(
    "moonbit:acme/a",
    "acme/a",
    @model.MoonBit,
    "main",
    "a",
    "a/moon.mod",
    Some("0.1.0"),
  )
  let loaded = sample_loaded(units=[mbt_unit, cargo_unit])
  let packed = @executor.pack_artifacts_with(
    host,
    loaded,
    @executor.PackOptions::new(dry_run=true, frozen=true),
  )
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
      pair.1.contains("--list") &&
      pair.1.contains("--target-dir") &&
      !pair.1.contains("--dry-run") &&
      pair.1.contains("--frozen")
    }),
  )

  // doctor --fix initializes missing files cleanly without gitignoring pre.json
  let doc_host = fake_host()
  doc_host.files["/repo/moon.mod"] = @utf8.encode(
    "name = \"acme/doc\"\nversion = \"0.1.0\"\n",
  )
  let rep = @executor.run_doctor_with(doc_host, "/repo", fix=true)
  assert_true(doc_host.files.contains("/repo/.changeset/config.json"))
  assert_true(doc_host.files.contains("/repo/.changeset/README.md"))
  assert_false(doc_host.files.contains("/repo/.changeset/.gitignore"))
  let ms_ignore = @utf8.decode_lossy(
    doc_host.files["/repo/.moonset/.gitignore"],
  )
  assert_true(ms_ignore.contains("pack-results-*.json"))
  assert_true(rep.checks.any(c => c.name == "fix" && c.ok))

  // commit_changes_with invokes git commit --only -- <paths>
  let git_cmds : Array[Array[String]] = []
  let git_host = fake_host()
  git_host.runner = (_program, args, _cwd) => {
    git_cmds.push(args)
    if args.length() >= 3 && args[0] == "diff" && args[1] == "--cached" {
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
  assert_true(
    git_cmds.any(a => {
      a ==
      [
        "commit", "--only", "-m", "chore: add changeset", "--", ".changeset/a.md",
      ]
    }),
  )
}

///|
async test "publish uses moon view --json to skip already-published moonbit units and proceed on 404" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "plan-mb-1",
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
        ],
        "tags": [],
        "consumedChangesets": [],
      } : Json).stringify(),
  )
  let loaded = sample_loaded(units=[
    mk_unit(
      "moonbit:acme/a",
      "acme/a",
      @model.MoonBit,
      "main",
      "a",
      "a/moon.mod",
      Some("0.1.1"),
    ),
  ])
  let mut publish_called = false
  host.runner = (program, args, _cwd) => {
    if program == "moon" && args == ["view", "acme/a@0.1.1", "--json"] {
      return {
        exit_code: 0,
        stdout: "{\"version\":1,\"status\":\"success\",\"result\":{\"module\":\"acme/a\",\"version\":\"0.1.1\"},\"messages\":[]}",
        stderr: "",
      }
    }
    if program == "moon" && args.contains("publish") {
      publish_called = true
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let skipped = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(skipped.complete)
  assert_true(!publish_called)
  assert_eq(skipped.statuses[0].state, @model.Published)
  assert_eq(skipped.statuses[0].message, Some("already published"))

  // 404 from moon view means absent -> proceeds with publish
  host.files.remove("/repo/.moonset/publish-state.json") |> ignore
  host.runner = (program, args, _cwd) => {
    if program == "moon" && args == ["view", "acme/a@0.1.1", "--json"] {
      return moon_view_404()
    }
    if program == "moon" && args == ["publish"] {
      publish_called = true
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let published = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(published.complete)
  assert_true(publish_called)
  assert_eq(published.statuses[0].state, @model.Published)
}

///|
async test "MIX-010 multi-platform artifact verification blocks missing required targets and preserves partial publish retry" {
  let host = fake_host()
  let cfg =
    #|{
    #|  "schemaVersion": 1,
    #|  "experimental": {
    #|    "mixedWorkspaces": {
    #|      "mode": "unified",
    #|      "workspaces": [
    #|        {"id": "native", "ecosystem": "moonbit", "root": "native", "manager": "moon", "includeRoot": false},
    #|        {"id": "js", "ecosystem": "npm", "root": "js", "manager": "npm", "includeRoot": false}
    #|      ],
    #|      "units": {
    #|        "moonbit:acme/engine": { "publish": false },
    #|        "npm:@acme/engine": {
    #|          "artifacts": [
    #|            { "target": "linux-x64", "package": "npm:@acme/engine-linux-x64", "required": true }
    #|          ]
    #|        }
    #|      },
    #|      "bridges": [
    #|        {
    #|          "consumer": "npm:@acme/engine",
    #|          "producer": "moonbit:acme/engine",
    #|          "kind": "build",
    #|          "bump": "patch",
    #|          "waitFor": "build"
    #|        }
    #|      ]
    #|    }
    #|  }
    #|}
  let units : Array[@model.ReleaseUnit] = [
    mk_unit(
      "moonbit:acme/engine",
      "acme/engine",
      @model.MoonBit,
      "native",
      "native",
      "native/moon.mod",
      Some("0.2.0"),
      publish=false,
    ),
    mk_unit(
      "npm:@acme/engine-linux-x64",
      "@acme/engine-linux-x64",
      @model.Npm,
      "js",
      "js/linux",
      "js/linux/package.json",
      Some("0.1.1"),
    ),
    mk_unit(
      "npm:@acme/engine",
      "@acme/engine",
      @model.Npm,
      "js",
      "js/main",
      "js/main/package.json",
      Some("0.1.1"),
    ),
  ]
  let loaded = sample_loaded(config_json=cfg, units~)
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "plan-mix-10",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "moonbit:acme/engine",
            "oldVersion": "0.1.0",
            "newVersion": "0.2.0",
            "level": "minor",
            "reasons": [],
            "changesets": [],
            "publish": false,
          },
          {
            "unitId": "npm:@acme/engine-linux-x64",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "npm:@acme/engine",
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
            "unitId": "npm:@acme/engine",
            "version": "0.1.1",
            "name": "npm/@acme/engine@0.1.1",
          },
        ],
        "consumedChangesets": [],
        "artifacts": [
          {
            "id": "npm:@acme/engine@0.1.1",
            "unitId": "npm:@acme/engine",
            "version": "0.1.1",
            "target": "source",
            "required": true,
          },
          {
            "id": "npm:@acme/engine-linux-x64@0.1.1/linux-x64",
            "unitId": "npm:@acme/engine-linux-x64",
            "version": "0.1.1",
            "target": "linux-x64",
            "required": true,
          },
        ],
      } : Json).stringify(),
  )
  host.files["/repo/js/main/engine.tgz"] = @utf8.encode("main-pkg")
  host.files["/repo/js/linux/linux.tgz"] = @utf8.encode("linux-pkg")

  let mut tag_called = false
  let publish_order : Array[String] = []
  host.runner = (program, args, cwd) => {
    if program == "git" && args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "git" && args.contains("tag") {
      tag_called = true
    }
    if program == "npm" && args.contains("pack") {
      if cwd.map(norm) == Some("/repo/js/main") {
        return {
          exit_code: 0,
          stdout: "[{\"filename\":\"engine.tgz\",\"integrity\":\"sha512-main\"}]",
          stderr: "",
        }
      }
      return {
        exit_code: 0,
        stdout: "[{\"filename\":\"linux.tgz\",\"integrity\":\"sha512-linux\"}]",
        stderr: "",
      }
    }
    if program == "npm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    if program == "npm" &&
      args.contains("publish") &&
      !args.contains("--dry-run") {
      if cwd is Some(dir) {
        publish_order.push(norm(dir))
      }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }

  ignore(
    @executor.pack_artifacts_with(
      host,
      loaded,
      @executor.PackOptions::new(packages=["npm:@acme/engine"], target="source"),
    ),
  )
  let missing_report = @executor.verify_artifacts_with(host, loaded)
  assert_true(!missing_report.ok)
  assert_true(missing_report.blocked_units.contains("npm:@acme/engine"))

  let blocked_pub = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=false),
  )
  assert_true(!blocked_pub.complete)
  assert_true(!tag_called)
  assert_true(blocked_pub.statuses.all(s => s.state == @model.Blocked))

  ignore(
    @executor.pack_artifacts_with(
      host,
      loaded,
      @executor.PackOptions::new(
        packages=["@acme/engine-linux-x64"],
        target="linux-x64",
      ),
    ),
  )
  let ok_report = @executor.verify_artifacts_with(host, loaded)
  assert_true(ok_report.ok)
  host.files.remove("/repo/.moonset/publish-state.json") |> ignore
  let ok_pub = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(ok_pub.complete)
  assert_eq(publish_order, ["/repo/js/linux", "/repo/js/main"])
}

///|
async test "FR-026 format_files resolves local node_modules/.bin, executes configured formatter, and respects --no-format" {
  let host = fake_host()
  host.files["/repo/CHANGELOG.md"] = @utf8.encode("# Changelog\n")
  host.files["/repo/package.json"] = @utf8.encode("{\"name\":\"a\"}\n")
  host.files["/repo/moon.mod"] = @utf8.encode("name = \"acme/a\"\n")
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode("{}\n")
  let calls : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    calls.push((program, args))
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let prettier_cfg = @engine.parse_config("{\"formatter\":\"prettier\"}")
  let res = @executor.format_files_with(host, "/repo", prettier_cfg, [
    "CHANGELOG.md", "package.json", "moon.mod", ".moonset/release-state.json", "missing.md",
  ])
  assert_true(!res.skipped)
  assert_eq(res.formatter, "prettier")
  assert_eq(res.formatted, ["CHANGELOG.md", "package.json"])
  assert_eq(calls.length(), 1)
  assert_eq(calls[0].0, "prettier")
  assert_eq(calls[0].1, ["--write", "--", "CHANGELOG.md", "package.json"])

  // --no-format skips execution completely
  let skipped = @executor.format_files_with(
    host,
    "/repo",
    prettier_cfg,
    ["CHANGELOG.md"],
    no_format=true,
  )
  assert_true(skipped.skipped)
  assert_eq(skipped.formatter, "none")
  assert_eq(calls.length(), 1)

  // biome only formats JSON files with `biome format --write --`
  let biome_cfg = @engine.parse_config("{\"format\":\"biome\"}")
  let biome_res = @executor.format_files_with(host, "/repo", biome_cfg, [
    "CHANGELOG.md", "package.json",
  ])
  assert_eq(biome_res.formatted, ["package.json"])
  assert_eq(calls.length(), 2)
  assert_eq(calls[1].0, "biome")
  assert_eq(calls[1].1, ["format", "--write", "--", "package.json"])

  // Non-zero formatter exit raises Io error
  host.runner = (_p, _a, _c) => {
    exit_code: 1,
    stdout: "",
    stderr: "syntax error",
  }
  let failed = try {
    ignore(
      @executor.format_files_with(host, "/repo", prettier_cfg, ["CHANGELOG.md"]),
    )
    false
  } catch {
    @model.Io(msg) => msg.contains("syntax error")
    _ => false
  }
  assert_true(failed)
}

///|
async test "FR-031 API publisher registry, npm --access/--otp/pre auto-tag, and scoped mixed-ecosystem routing" {
  let host = fake_host()
  let units : Array[@model.ReleaseUnit] = [
    mk_unit(
      "moonbit:acme/a",
      "acme/a",
      @model.MoonBit,
      "mbt",
      "a",
      "a/moon.mod",
      Some("0.2.0"),
    ),
    mk_unit(
      "npm:@acme/b",
      "@acme/b",
      @model.Npm,
      "js",
      "b",
      "b/package.json",
      Some("1.1.0"),
      publish_config={
        access: Some(@model.Access::Restricted),
        registry: None,
        directory: None,
      },
    ),
    mk_unit(
      "cargo:acme-c",
      "acme-c",
      @model.Cargo,
      "rs",
      "c",
      "c/Cargo.toml",
      Some("0.3.0"),
    ),
  ]
  let rel_state : Json = {
    "planFingerprint": "plan-mixed-1",
    "sourceHead": Json::null(),
    "releases": [
      {
        "unitId": "moonbit:acme/a",
        "oldVersion": "0.1.0",
        "newVersion": "0.2.0",
        "level": "minor",
        "reasons": [],
        "changesets": [],
        "publish": true,
      },
      {
        "unitId": "npm:@acme/b",
        "oldVersion": "1.0.0",
        "newVersion": "1.1.0",
        "level": "minor",
        "reasons": [],
        "changesets": [],
        "publish": true,
      },
      {
        "unitId": "cargo:acme-c",
        "oldVersion": "0.2.0",
        "newVersion": "0.3.0",
        "level": "minor",
        "reasons": [],
        "changesets": [],
        "publish": true,
      },
    ],
    "tags": [],
    "consumedChangesets": [],
  }
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    rel_state.stringify(),
  )
  let base_loaded = sample_loaded(units~)
  let loaded_mixed : @workspace.LoadedWorkspace = {
    ..base_loaded,
    snapshot: {
      ..base_loaded.snapshot,
      workspaces: [
        {
          id: "mbt",
          root: "a",
          ecosystem: @model.MoonBit,
          manager: @model.Moon,
        },
        {
          id: "js",
          root: "b",
          ecosystem: @model.Npm,
          manager: @model.PackageManager::Pnpm,
        },
        {
          id: "rs",
          root: "c",
          ecosystem: @model.Cargo,
          manager: @model.PackageManager::Cargo,
        },
      ],
    },
  }
  // Global --registry across mixed ecosystems is still rejected
  let global_rejected = try {
    ignore(
      @executor.publish_release_with(
        host,
        loaded_mixed,
        @executor.PublishOptions::new(
          dry_run=true,
          registry="https://registry.npmjs.org",
          yes=true,
          allow_uncommitted=true,
          no_tag=true,
        ),
      ),
    )
    false
  } catch {
    @model.Invalid(d) => d.code == "unsupported-capability"
    _ => false
  }
  assert_true(global_rejected)

  // Scoped --registry, --tag, --otp, publishConfig.access, and pnpm --no-git-checks route cleanly
  let invoked : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    invoked.push((program, args))
    if program == "git" && args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "moon" && args.contains("view") {
      return moon_view_404()
    }
    if program == "pnpm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "ERR_PNPM_FETCH_404", }
    }
    if program == "cargo" && args.contains("info") {
      return { exit_code: 1, stdout: "", stderr: "could not find", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let scoped_res = @executor.publish_release_with(
    host,
    loaded_mixed,
    @executor.PublishOptions::new(
      registry="npm=https://npm.pkg.github.com,cargo=private-crates",
      tag="npm:@acme/b=canary",
      otp="123456",
      yes=true,
      no_tag=true,
    ),
  )
  assert_true(scoped_res.complete)
  assert_true(
    invoked.any(c => {
      c.0 == "pnpm" &&
      c.1.contains("publish") &&
      c.1.contains("--no-git-checks") &&
      c.1.contains("--access") &&
      c.1.contains("restricted") &&
      c.1.contains("--otp") &&
      c.1.contains("123456") &&
      c.1.contains("https://npm.pkg.github.com") &&
      c.1.contains("canary") &&
      !c.1.contains("--ignore-scripts")
    }),
  )
  assert_true(
    invoked.any(c => {
      c.0 == "cargo" &&
      c.1.contains("publish") &&
      c.1.contains("private-crates")
    }),
  )
  assert_true(invoked.any(c => c.0 == "moon" && c.1 == ["publish"]))

  // publisher.kind = "api" routes through ApiPublisherRegistry and records external_id
  host.files.remove("/repo/.moonset/publish-state.json") |> ignore
  let loaded_api = sample_loaded(
    config_json="{\"publisher\":{\"kind\":\"api\",\"dryRunFirst\":true}}",
    units~,
  )
  let api_calls : Array[String] = []
  let registry = @executor.ApiPublisherRegistry::new()
  registry.register("default", {
    already_published: _t => false,
    preflight: t => api_calls.push("pre:" + t.unit_id + ":" + t.target),
    publish: t => {
      api_calls.push("pub:" + t.unit_id + ":" + t.registry)
      "ext-" + t.unit_id + "@" + t.version
    },
  })
  let api_res = @executor.publish_release_with(
    host,
    loaded_api,
    @executor.PublishOptions::new(
      registry="npm=https://custom.npm",
      tag="npm=next",
      yes=true,
      allow_uncommitted=true,
      no_tag=true,
      api_publishers=registry,
    ),
  )
  assert_true(api_res.complete)
  assert_true(api_calls.contains("pre:npm:@acme/b:dist-tag:next"))
  assert_true(api_calls.contains("pub:npm:@acme/b:https://custom.npm"))
  assert_true(
    api_res.statuses.any(s => {
      s.unit_id == "npm:@acme/b" &&
      s.external_id == Some("ext-npm:@acme/b@1.1.0")
    }),
  )
}

///|
async test "v0.3.0 snapshot publish auto-tags npm and skips Git tag creation" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "snap-1",
        "sourceHead": Json::null(),
        "isSnapshot": true,
        "releases": [
          {
            "unitId": "npm:@acme/b",
            "oldVersion": "0.1.0",
            "newVersion": "0.0.0-canary-20261120120000",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
        ],
        "tags": [],
        "consumedChangesets": [],
      } : Json).stringify(),
  )
  let loaded = sample_loaded(units=[
    mk_unit(
      "npm:@acme/b",
      "@acme/b",
      @model.Npm,
      "js",
      "b",
      "b/package.json",
      Some("0.0.0-canary-20261120120000"),
    ),
  ])
  let mut tag_called = false
  let npm_args : Array[Array[String]] = []
  host.runner = (program, args, _cwd) => {
    if program == "git" && args.contains("tag") {
      tag_called = true
    }
    if program == "npm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    if program == "npm" && args.contains("publish") {
      npm_args.push(args)
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=false),
  )
  assert_true(res.complete)
  assert_false(tag_called)
  assert_true(npm_args.any(a => a.contains("--tag") && a.contains("canary")))
}
