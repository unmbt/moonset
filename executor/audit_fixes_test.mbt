///|
async test "fixture stale-plan rejects beforeHash mismatch without touching disk" {
  let host = fake_host()
  let manifest_src = @fs.read_text("fixtures/stale-plan/moon.mod")
  let plan_src = @fs.read_text("fixtures/stale-plan/plan.json")
  host.files["/repo/moon.mod"] = @utf8.encode(manifest_src)
  let parsed = @json.parse(plan_src)
  guard parsed is { "fingerprint": String(fp), "edits": Array(raw_edits), .. } else {
    fail("Invalid stale-plan fixture")
  }
  let edits : Array[@model.FileEdit] = []
  for item in raw_edits {
    if item
      is {
        "path": String(path),
        "kind": String(kind),
        "owner": String(owner),
        "beforeHash": String(before_hash),
        "afterText": String(after_text),
        ..
      } {
      edits.push({
        path,
        kind,
        owner,
        before_hash,
        after_text,
        atomic_write: true,
      })
    }
  }
  let loaded = sample_loaded(units=[
    mk_unit(
      "moonbit:acme/stale",
      "acme/stale",
      @model.MoonBit,
      "moon",
      "",
      "moon.mod",
      Some("0.2.0"),
    ),
  ])
  let analysis = @engine.build_plan(loaded.snapshot, [])
  let version_plan : @model.VersionPlan = {
    schema_version: 1,
    stage: "version",
    executable: true,
    generated_at: Some("2026-11-27"),
    fingerprint: fp,
    analysis,
    edits,
    changelogs: [],
    tags: [],
    consumed_changesets: [],
  }
  let mut code = ""
  ignore(@executor.apply_version_plan_with(host, "/repo", version_plan)) catch {
    @model.Invalid(d) => code = d.code
    err => fail("Unexpected error: " + err.to_string())
  }
  assert_eq(code, "stale-plan")
  assert_eq(@utf8.decode_lossy(host.files["/repo/moon.mod"]), manifest_src)
  assert_false(host.files.contains("/repo/.moonset/version-journal.json"))
}

///|
async test "fixture partial-publish resumes and skips already-published unit" {
  let host = fake_host()
  let loaded = @workspace.discover(
    "fixtures/partial-publish",
    include_commits=false,
  )
  let root = loaded.snapshot.root
  host.dirs[norm(root)] = true
  host.files[norm(root) + "/.moonset/release-state.json"] = @utf8.encode(
    @fs.read_text("fixtures/partial-publish/.moonset/release-state.json"),
  )
  host.files[norm(root) + "/.moonset/publish-state.json"] = @utf8.encode(
    @fs.read_text("fixtures/partial-publish/.moonset/publish-state.json"),
  )
  let invoked : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    invoked.push((program, args))
    if program == "npm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true, allow_uncommitted=true),
  )
  assert_true(res.complete)
  // moonbit:acme/a was already published in publish-state.json, so `moon publish` must not run!
  assert_false(invoked.any(c => c.0 == "moon" && c.1.contains("publish")))
  assert_true(invoked.any(c => c.0 == "npm" && c.1.contains("publish")))
  assert_eq(res.statuses.length(), 2)
  assert_true(res.statuses.all(s => s.state == @model.Published))
}

///|
async test "audit fixes: keep_journal protects formatter failure for recover, auto formatter, Yarn, stateless tag, host allowlist, doctor" {
  let host = fake_host()
  let orig = "name = \"acme/j\"\nversion = \"0.1.0\"\n"
  let next = "name = \"acme/j\"\nversion = \"0.1.1\"\n"
  host.files["/repo/moon.mod"] = @utf8.encode(orig)
  let loaded = sample_loaded(config_json="{\"format\":\"auto\"}", units=[
    mk_unit(
      "moonbit:acme/j",
      "acme/j",
      @model.MoonBit,
      "moon",
      "",
      "moon.mod",
      Some("0.1.0"),
    ),
  ])
  let analysis = @engine.build_plan(loaded.snapshot, [])
  let vplan : @model.VersionPlan = {
    schema_version: 1,
    stage: "version",
    executable: true,
    generated_at: Some("2026-11-27"),
    fingerprint: "fp-j",
    analysis,
    edits: [
      {
        path: "moon.mod",
        kind: "manifest",
        owner: "moonbit:acme/j",
        before_hash: @model.fingerprint(Json::string(orig)),
        after_text: next,
        atomic_write: true,
      },
    ],
    changelogs: [],
    tags: [],
    consumed_changesets: [],
  }
  let applied = @executor.apply_version_plan_with(
    host,
    "/repo",
    vplan,
    keep_journal=true,
  )
  assert_true(applied.applied)
  assert_eq(applied.journal, Some(".moonset/version-journal.json"))
  assert_true(host.files.contains("/repo/.moonset/version-journal.json"))
  // Simulate formatter failure -> recover restores original file and removes journal
  let recovered = @executor.recover_version_with(host, "/repo")
  assert_eq(recovered, ["moon.mod"])
  assert_eq(@utf8.decode_lossy(host.files["/repo/moon.mod"]), orig)
  assert_false(host.files.contains("/repo/.moonset/version-journal.json"))

  // format: "auto" detects biome.json and probes binary availability
  host.files["/repo/biome.json"] = @utf8.encode("{}")
  host.runner = (program, args, _cwd) => {
    if program == "biome" && args == ["--version"] {
      return { exit_code: 0, stdout: "Version: 1.9.0", stderr: "", }
    }
    { exit_code: 1, stdout: "", stderr: "not found", }
  }
  let detected = @executor.detect_workspace_formatter_with(
    host,
    "/repo",
    loaded.snapshot.config,
  )
  assert_eq(detected, "biome")

  // doctor accepts injected loaded workspace without bypassing ExecutionHost
  host.runner = (program, args, _cwd) => {
    if program == "git" && args.contains("--porcelain") {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "ok", stderr: "", }
  }
  let report = @executor.run_doctor_with(host, "/repo", loaded~)
  assert_true(report.ok)

  // Stateless tag fallback works when `.moonset/release-state.json` is absent
  let tag_res = @executor.create_tags_with(
    host,
    loaded,
    @executor.TagOptions::new(dry_run=true),
  )
  assert_eq(tag_res.tags, ["v0.1.0"])

  // Yarn publish with CLI --access and --ignore-scripts
  let yarn_host = fake_host()
  yarn_host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "yarn-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "npm:@acme/y",
            "oldVersion": "0.1.0",
            "newVersion": "0.2.0",
            "level": "minor",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
        ],
        "tags": [],
        "consumedChangesets": [],
      } : Json).stringify(),
  )
  let yarn_loaded : @workspace.LoadedWorkspace = {
    ..sample_loaded(units=[
      mk_unit(
        "npm:@acme/y",
        "@acme/y",
        @model.Npm,
        "js",
        "y",
        "y/package.json",
        Some("0.2.0"),
      ),
    ]),
    snapshot: {
      ..sample_loaded(units=[
        mk_unit(
          "npm:@acme/y",
          "@acme/y",
          @model.Npm,
          "js",
          "y",
          "y/package.json",
          Some("0.2.0"),
        ),
      ]).snapshot,
      workspaces: [
        {
          id: "js",
          root: "y",
          ecosystem: @model.Npm,
          manager: @model.PackageManager::Yarn,
        },
      ],
    },
  }
  let yarn_calls : Array[(String, Array[String])] = []
  yarn_host.runner = (program, args, _cwd) => {
    yarn_calls.push((program, args))
    if program == "npm" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let yarn_res = @executor.publish_release_with(
    yarn_host,
    yarn_loaded,
    @executor.PublishOptions::new(
      access=@model.Access::Restricted,
      ignore_scripts=true,
      yes=true,
      no_tag=true,
    ),
  )
  assert_true(yarn_res.complete)
  assert_true(
    yarn_calls.any(c => {
      c.0 == "npm" &&
      c.1.contains("publish") &&
      c.1.contains("--access") &&
      c.1.contains("restricted") &&
      c.1.contains("--ignore-scripts")
    }),
  )

  // Command publisher host allowlist rejects unapproved executable
  let cmd_host = fake_host()
  cmd_host.env["MOONSET_ALLOWED_PLUGIN_PROGRAMS"] = "allowed-bin"
  cmd_host.files["/repo/.moonset/release-state.json"] = yarn_host.files["/repo/.moonset/release-state.json"]
  let cmd_loaded = sample_loaded(
    config_json="{\"publisher\":{\"kind\":\"command\",\"command\":[\"blocked-bin\",\"run\"]}}",
    units=[
      mk_unit(
        "npm:@acme/y",
        "@acme/y",
        @model.Npm,
        "js",
        "y",
        "y/package.json",
        Some("0.2.0"),
      ),
    ],
  )
  let cmd_res = @executor.publish_release_with(
    cmd_host,
    cmd_loaded,
    @executor.PublishOptions::new(dry_run=true),
  )
  assert_true(
    cmd_res.statuses.any(s => {
      s.state == @model.Blocked &&
      s.message.unwrap_or("").contains("not allowed by host allowlist")
    }),
  )
}
