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

  // MoonBit pack --dry-run uses `--list --target-dir <tmp>` (never `--dry-run`)
  // and real pack locates archives in workspace root `_build/publish/` for `moon.work` members
  let moon_pack_host = fake_host()
  moon_pack_host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "mp-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "moonbit:acme/sub",
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
  let moon_pack_loaded = sample_loaded(units=[
    mk_unit(
      "moonbit:acme/sub",
      "acme/sub",
      @model.MoonBit,
      "moon",
      "sub",
      "sub/moon.mod",
      Some("0.1.1"),
    ),
  ])
  let moon_pack_calls : Array[Array[String]] = []
  moon_pack_host.runner = (program, args, _cwd) => {
    if program == "moon" {
      moon_pack_calls.push(args)
      if !args.contains("--list") {
        moon_pack_host.dirs["/repo/_build/publish"] = true
        // Put an alphabetically earlier sibling zip with the same version to verify exact name matching!
        moon_pack_host.files["/repo/_build/publish/acme-aaa-0.1.1.zip"] = b"otherzip"
        moon_pack_host.files["/repo/_build/publish/acme-sub-0.1.1.zip"] = b"zipdata"
      }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let dry_packed = @executor.pack_artifacts_with(
    moon_pack_host,
    moon_pack_loaded,
    @executor.PackOptions::new(dry_run=true),
  )
  assert_eq(dry_packed.length(), 1)
  assert_true(
    moon_pack_calls.any(a => {
      a.contains("package") &&
      a.contains("--list") &&
      a.contains("--target-dir") &&
      !a.contains("--dry-run")
    }),
  )
  let real_packed = @executor.pack_artifacts_with(
    moon_pack_host,
    moon_pack_loaded,
    @executor.PackOptions::new(dry_run=false),
  )
  assert_eq(real_packed.length(), 1)
  assert_true(real_packed[0].verified)
  assert_true(real_packed[0].archive_path.has_suffix("acme-sub-0.1.1.zip"))
}

///|
async test "publish defers per-unit preflight for MoonBit/Cargo downstream units with unpublished same-batch upstream" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "defer-pf-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "moonbit:acme/core",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "moonbit:acme/cli",
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
  let core_unit = mk_unit(
    "moonbit:acme/core",
    "acme/core",
    @model.MoonBit,
    "moon",
    "core",
    "core/moon.mod",
    Some("0.1.1"),
  )
  let cli_unit : @model.ReleaseUnit = {
    ..mk_unit(
      "moonbit:acme/cli",
      "acme/cli",
      @model.MoonBit,
      "moon",
      "cli",
      "cli/moon.mod",
      Some("0.1.1"),
    ),
    dependencies: [
      {
        producer: "moonbit:acme/core",
        requirement: "0.1.1",
        kind: @model.Runtime,
        path: "cli/moon.mod",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let loaded = sample_loaded(units=[cli_unit, core_unit])
  let events : Array[String] = []
  host.runner = (program, args, cwd) => {
    if program == "moon" && args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "404 not found", }
    }
    if program == "moon" && args.contains("publish") {
      let who = if cwd.unwrap_or("").has_suffix("core") {
        "core"
      } else {
        "cli"
      }
      let phase = if args.contains("--dry-run") {
        "preflight"
      } else {
        "publish"
      }
      events.push(who + ":" + phase)
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  // 1. `--dry-run`: runs preflight on core, defers cli cleanly as Pending
  let dry_res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(dry_run=true),
  )
  assert_eq(events, ["core:preflight"])
  assert_true(
    dry_res.statuses.any(s => {
      s.unit_id == "moonbit:acme/core" && s.state == @model.Preflighted
    }),
  )
  assert_true(
    dry_res.statuses.any(s => {
      s.unit_id == "moonbit:acme/cli" &&
      s.state == @model.Pending &&
      s.message.unwrap_or("").contains("Deferred preflight")
    }),
  )

  // 2. Real publish: core preflight -> core publish -> cli deferred preflight -> cli publish
  events.clear()
  let pub_res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(pub_res.complete)
  assert_eq(events, [
    "core:preflight", "core:publish", "cli:preflight", "cli:publish",
  ])
}

///|
async test "cargo pack uses --no-verify --exclude-lockfile for workspace crates with internal deps" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "cargo-ws-pack-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "cargo:acme-core",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "cargo:acme-app",
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
  let rs_core = mk_unit(
    "cargo:acme-core",
    "acme-core",
    @model.Cargo,
    "rs",
    "crates/core",
    "crates/core/Cargo.toml",
    Some("0.1.1"),
  )
  let rs_app : @model.ReleaseUnit = {
    ..mk_unit(
      "cargo:acme-app",
      "acme-app",
      @model.Cargo,
      "rs",
      "crates/app",
      "crates/app/Cargo.toml",
      Some("0.1.1"),
    ),
    dependencies: [
      {
        producer: "cargo:acme-core",
        requirement: "^0.1.1",
        kind: @model.Runtime,
        path: "crates/app/Cargo.toml",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let base_loaded = sample_loaded(units=[rs_core, rs_app])
  let loaded : @workspace.LoadedWorkspace = {
    ..base_loaded,
    snapshot: {
      ..base_loaded.snapshot,
      workspaces: [
        { id: "rs", root: "", ecosystem: @model.Cargo, manager: @model.Cargo, },
      ],
    },
  }
  let calls : Array[(String, Array[String])] = []
  host.runner = (program, args, cwd) => {
    if program == "cargo" {
      let who = if cwd.unwrap_or("").has_suffix("app") { "app" } else { "core" }
      calls.push((who, args))
      host.dirs["/repo/target/package"] = true
      if who == "core" {
        host.files["/repo/target/package/acme-core-0.1.1.crate"] = b"corecrate"
      } else {
        host.files["/repo/target/package/acme-app-0.1.1.crate"] = b"appcrate"
      }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let results = @executor.pack_artifacts_with(
    host,
    loaded,
    @executor.PackOptions::new(dry_run=false),
  )
  assert_eq(results.length(), 2)
  assert_true(results.all(r => r.verified))
  assert_true(
    calls.any(c => {
      c.0 == "core" &&
      !c.1.contains("--no-verify") &&
      !c.1.contains("--exclude-lockfile")
    }),
  )
  assert_true(
    calls.any(c => {
      c.0 == "app" &&
      c.1.contains("--no-verify") &&
      c.1.contains("--exclude-lockfile")
    }),
  )
}

///|
async test "npm/pnpm/yarn pack writes tarballs into .moonset/pack and dirty worktree check ignores .moonset/pack" {
  assert_true(@executor.default_moonset_gitignore().contains("pack/"))

  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "js-pack-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "npm:@acme/pnpm-pkg",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "npm:@acme/npm-pkg",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "npm:@acme/yarn-pkg",
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
  let pnpm_unit = mk_unit(
    "npm:@acme/pnpm-pkg",
    "@acme/pnpm-pkg",
    @model.Npm,
    "ws-pnpm",
    "packages/pnpm-pkg",
    "packages/pnpm-pkg/package.json",
    Some("0.1.1"),
  )
  let npm_unit = mk_unit(
    "npm:@acme/npm-pkg",
    "@acme/npm-pkg",
    @model.Npm,
    "ws-npm",
    "packages/npm-pkg",
    "packages/npm-pkg/package.json",
    Some("0.1.1"),
  )
  let yarn_unit = mk_unit(
    "npm:@acme/yarn-pkg",
    "@acme/yarn-pkg",
    @model.Npm,
    "ws-yarn",
    "packages/yarn-pkg",
    "packages/yarn-pkg/package.json",
    Some("0.1.1"),
  )
  let base_loaded = sample_loaded(units=[pnpm_unit, npm_unit, yarn_unit])
  let loaded : @workspace.LoadedWorkspace = {
    ..base_loaded,
    snapshot: {
      ..base_loaded.snapshot,
      workspaces: [
        {
          id: "ws-pnpm",
          root: "",
          ecosystem: @model.Npm,
          manager: @model.Pnpm,
        },
        { id: "ws-npm", root: "", ecosystem: @model.Npm, manager: @model.Npm, },
        {
          id: "ws-yarn",
          root: "",
          ecosystem: @model.Npm,
          manager: @model.Yarn,
        },
      ],
    },
  }
  let calls : Array[(String, Array[String])] = []
  host.runner = (program, args, _cwd) => {
    calls.push((program, args))
    if program == "pnpm" && args.contains("pack") {
      host.files["/repo/.moonset/pack/acme-pnpm-pkg-0.1.1.tgz"] = b"pnpmtgz"
      return {
        exit_code: 0,
        stdout: "..\\..\\.moonset\\pack\\acme-pnpm-pkg-0.1.1.tgz\n",
        stderr: "",
      }
    }
    if program == "npm" && args.contains("pack") {
      host.files["/repo/.moonset/pack/acme-npm-pkg-0.1.1.tgz"] = b"npmtgz"
      return {
        exit_code: 0,
        stdout: "[{\"filename\":\"acme-npm-pkg-0.1.1.tgz\",\"integrity\":\"sha512-x\"}]",
        stderr: "",
      }
    }
    if program == "yarn" && args.contains("pack") {
      host.files["/repo/.moonset/pack/acme-yarn-pkg-0.1.1.tgz"] = b"yarntgz"
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "git" && args == ["status", "--porcelain"] {
      return {
        exit_code: 0,
        stdout: "?? .moonset/pack/\n?? .moonset/pack/acme-pnpm-pkg-0.1.1.tgz\n",
        stderr: "",
      }
    }
    if args.contains("view") {
      return { exit_code: 1, stdout: "", stderr: "E404", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let packed = @executor.pack_artifacts_with(
    host,
    loaded,
    @executor.PackOptions::new(dry_run=false),
  )
  assert_eq(packed.length(), 3)
  assert_true(packed.all(r => r.verified))
  for res in packed {
    assert_true(
      res.archive_path.replace_all(old="\\", new="/").contains(".moonset/pack/"),
    )
  }
  assert_true(
    calls.any(c => {
      c.0 == "pnpm" &&
      c.1.contains("--pack-destination") &&
      c.1.any(a => a.replace_all(old="\\", new="/").has_suffix(".moonset/pack"))
    }),
  )
  assert_true(
    calls.any(c => {
      c.0 == "npm" &&
      c.1.contains("--pack-destination") &&
      c.1.contains("--json")
    }),
  )
  assert_true(
    calls.any(c => {
      c.0 == "yarn" &&
      c.1.contains("--filename") &&
      c.1.any(a => {
        a
        .replace_all(old="\\", new="/")
        .has_suffix(".moonset/pack/acme-yarn-pkg-0.1.1.tgz")
      })
    }),
  )

  // Publish dry-run / non-dirty check ignores untracked .moonset/pack/ files
  let pub_res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(pub_res.complete)
}

///|
async test "apply_version_plan cleans stale pack artifacts and publish reports detailed stale-artifact diagnostics" {
  let host = fake_host()
  host.dirs["/repo/.moonset"] = true
  host.dirs["/repo/.moonset/pack"] = true
  host.files["/repo/.moonset/.gitignore"] = @utf8.encode("pack/\n")
  host.files["/repo/.moonset/pack-results.json"] = @utf8.encode(
    "{\"results\":[]}",
  )
  host.files["/repo/.moonset/pack-results-linux-x64.json"] = @utf8.encode(
    "{\"results\":[]}",
  )
  host.files["/repo/.moonset/pack/acme-cli-0.1.1.tgz"] = b"old-tgz"

  let new_state = (
    {
      "planFingerprint": "fp-next",
      "sourceHead": Json::null(),
      "releases": [
        {
          "unitId": "npm:@acme/cli",
          "oldVersion": "0.1.1",
          "newVersion": "0.1.2",
          "level": "patch",
          "reasons": [],
          "changesets": [],
          "publish": true,
        },
      ],
      "tags": [],
      "consumedChangesets": [],
    } : Json).stringify()
  let plan : @model.VersionPlan = {
    schema_version: 1,
    stage: "version",
    executable: true,
    fingerprint: "fp-next",
    edits: [
      {
        path: ".moonset/release-state.json",
        kind: "state",
        owner: "moonset",
        before_hash: @model.fingerprint(Json::string("")),
        after_text: new_state,
        atomic_write: true,
      },
    ],
    changelogs: [],
    tags: [],
    consumed_changesets: [],
    analysis: {
      fingerprint: "fp-next",
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
  let applied = @executor.apply_version_plan_with(host, "/repo", plan)
  assert_true(applied.applied)
  assert_true(host.files.contains("/repo/.moonset/release-state.json"))
  assert_true(host.files.contains("/repo/.moonset/.gitignore"))
  assert_false(host.files.contains("/repo/.moonset/pack-results.json"))
  assert_false(
    host.files.contains("/repo/.moonset/pack-results-linux-x64.json"),
  )
  assert_false(host.dirs.contains("/repo/.moonset/pack"))

  // Verify stale-artifact error includes concrete version mismatch and remediation hint
  host.files["/repo/.moonset/pack-results.json"] = @utf8.encode(
    (
      {
        "schemaVersion": 1,
        "target": "source",
        "results": [
          {
            "unitId": "npm:@acme/cli",
            "version": "0.1.1",
            "verified": true,
            "archivePath": "/repo/.moonset/pack/acme-cli-0.1.1.tgz",
          },
        ],
      } : Json).stringify(),
  )
  let cli_unit = mk_unit(
    "npm:@acme/cli",
    "@acme/cli",
    @model.Npm,
    "ws-npm",
    "packages/cli",
    "packages/cli/package.json",
    Some("0.1.2"),
  )
  let base_loaded = sample_loaded(units=[cli_unit])
  let loaded : @workspace.LoadedWorkspace = {
    ..base_loaded,
    snapshot: {
      ..base_loaded.snapshot,
      workspaces: [
        { id: "ws-npm", root: "", ecosystem: @model.Npm, manager: @model.Npm, },
      ],
    },
  }
  let stale_msg = try {
    ignore(
      @executor.publish_release_with(
        host,
        loaded,
        @executor.PublishOptions::new(yes=true, no_tag=true),
      ),
    )
    ""
  } catch {
    @model.Invalid(d) => {
      assert_eq(d.code, "stale-artifact")
      d.message
    }
    _ => ""
  }
  assert_true(stale_msg.contains("0.1.1"))
  assert_true(stale_msg.contains("0.1.2"))
  assert_true(stale_msg.contains("moonset pack"))
}

///|
async test "moonbit publish syncs registry index after upstream publish and retries propagation misses" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "moon-sync-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "moonbit:acme/webstd",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "moonbit:acme/ciallo",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "moonbit:acme/sibling",
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
  let webstd = mk_unit(
    "moonbit:acme/webstd",
    "acme/webstd",
    @model.MoonBit,
    "moon",
    "packages/webstd",
    "packages/webstd/moon.mod",
    Some("0.1.1"),
  )
  let ciallo : @model.ReleaseUnit = {
    ..mk_unit(
      "moonbit:acme/ciallo",
      "acme/ciallo",
      @model.MoonBit,
      "moon",
      "packages/ciallo",
      "packages/ciallo/moon.mod",
      Some("0.1.1"),
    ),
    dependencies: [
      {
        producer: "moonbit:acme/webstd",
        requirement: "0.1.1",
        kind: @model.Runtime,
        path: "packages/ciallo/moon.mod",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let sibling : @model.ReleaseUnit = {
    ..mk_unit(
      "moonbit:acme/sibling",
      "acme/sibling",
      @model.MoonBit,
      "moon",
      "packages/sibling",
      "packages/sibling/moon.mod",
      Some("0.1.1"),
    ),
    dependencies: [
      {
        producer: "moonbit:acme/webstd",
        requirement: "0.1.1",
        kind: @model.Runtime,
        path: "packages/sibling/moon.mod",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let loaded = sample_loaded(units=[webstd, ciallo, sibling])
  let events : Array[String] = []
  let mut webstd_published = false
  let mut webstd_post_publish_polls = 0
  let mut ciallo_dry_runs = 0
  let mut update_count = 0
  host.runner = (program, args, cwd) => {
    if program == "moon" && args.length() >= 2 && args[0] == "view" {
      if args[1] == "acme/webstd@0.1.1" && webstd_published {
        webstd_post_publish_polls += 1
        events.push("view:webstd#" + webstd_post_publish_polls.to_string())
        if webstd_post_publish_polls >= 2 {
          return {
            exit_code: 0,
            stdout: "{\"status\":\"success\",\"result\":{\"name\":\"acme/webstd\"}}",
            stderr: "",
          }
        }
      }
      return { exit_code: 1, stdout: "", stderr: "404 not found", }
    }
    if program == "moon" && args == ["update"] {
      update_count += 1
      events.push("moon:update#" + update_count.to_string())
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "moon" && args.contains("publish") {
      let dir = cwd.unwrap_or("")
      let who = if dir.has_suffix("webstd") {
        "webstd"
      } else if dir.has_suffix("ciallo") {
        "ciallo"
      } else {
        "sibling"
      }
      let is_dry = args.contains("--dry-run")
      if who == "webstd" && !is_dry {
        webstd_published = true
      }
      if who == "ciallo" && is_dry {
        ciallo_dry_runs += 1
        events.push("ciallo:preflight#" + ciallo_dry_runs.to_string())
        if ciallo_dry_runs == 1 {
          return {
            exit_code: 1,
            stdout: "",
            stderr: "Failed to resolve registry dependency `acme/webstd` for module `acme/ciallo`: module was not found in the registry",
          }
        }
        return { exit_code: 0, stdout: "", stderr: "", }
      }
      events.push(who + ":" + (if is_dry { "preflight" } else { "publish" }))
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(res.complete)
  // Expected sequence:
  // 1. webstd preflight + publish
  // 2. ciallo waits for webstd via moon view (2 polls), runs moon update#1
  // 3. ciallo preflight#1 hits propagation miss -> moon update#2 -> preflight#2 passes -> ciallo publish
  // 4. sibling depends only on already-synced webstd -> no redundant moon update!
  assert_eq(events, [
    "webstd:preflight", "webstd:publish", "view:webstd#1", "view:webstd#2", "moon:update#1",
    "ciallo:preflight#1", "moon:update#2", "ciallo:preflight#2", "ciallo:publish",
    "sibling:preflight", "sibling:publish",
  ])
  assert_eq(update_count, 2)
}

///|
async test "moonbit publish with dryRunFirst=false still refreshes index and retries propagation misses" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "moon-sync-nodry-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "moonbit:acme/webstd",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "moonbit:acme/ciallo",
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
  let webstd = mk_unit(
    "moonbit:acme/webstd",
    "acme/webstd",
    @model.MoonBit,
    "moon",
    "packages/webstd",
    "packages/webstd/moon.mod",
    Some("0.1.1"),
  )
  let ciallo : @model.ReleaseUnit = {
    ..mk_unit(
      "moonbit:acme/ciallo",
      "acme/ciallo",
      @model.MoonBit,
      "moon",
      "packages/ciallo",
      "packages/ciallo/moon.mod",
      Some("0.1.1"),
    ),
    dependencies: [
      {
        producer: "moonbit:acme/webstd",
        requirement: "0.1.1",
        kind: @model.Runtime,
        path: "packages/ciallo/moon.mod",
        start: 0,
        end: 0,
        target_condition: None,
      },
    ],
  }
  let loaded = sample_loaded(
    config_json="{\"publisher\":{\"dryRunFirst\":false}}",
    units=[webstd, ciallo],
  )
  let events : Array[String] = []
  let mut webstd_published = false
  let mut ciallo_publishes = 0
  let mut updates = 0
  host.runner = (program, args, cwd) => {
    if program == "moon" && args.length() >= 2 && args[0] == "view" {
      if args[1] == "acme/webstd@0.1.1" && webstd_published {
        return {
          exit_code: 0,
          stdout: "{\"status\":\"success\",\"result\":{\"name\":\"acme/webstd\"}}",
          stderr: "",
        }
      }
      return { exit_code: 1, stdout: "", stderr: "404 not found", }
    }
    if program == "moon" && args == ["update"] {
      updates += 1
      events.push("moon:update#" + updates.to_string())
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if program == "moon" && args == ["publish"] {
      if cwd.unwrap_or("").has_suffix("webstd") {
        webstd_published = true
        events.push("webstd:publish")
        return { exit_code: 0, stdout: "", stderr: "", }
      }
      ciallo_publishes += 1
      events.push("ciallo:publish#" + ciallo_publishes.to_string())
      if ciallo_publishes == 1 {
        return {
          exit_code: 1,
          stdout: "",
          stderr: "Error: Failed to resolve registry dependency `acme/webstd` for module `acme/ciallo`: module was not found in the registry",
        }
      }
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(res.complete)
  assert_eq(events, [
    "webstd:publish", "moon:update#1", "ciallo:publish#1", "moon:update#2", "ciallo:publish#2",
  ])
}

///|
async test "cargo registry lookup always passes --registry crates-io to avoid matching local workspace crates" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "cargo-reg-lookup-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "cargo:acme-core",
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
  let crate_unit = mk_unit(
    "cargo:acme-core",
    "acme-core",
    @model.Cargo,
    "rs",
    "crates/core",
    "crates/core/Cargo.toml",
    Some("0.1.1"),
  )
  let base_loaded = sample_loaded(units=[crate_unit])
  let loaded : @workspace.LoadedWorkspace = {
    ..base_loaded,
    snapshot: {
      ..base_loaded.snapshot,
      workspaces: [
        { id: "rs", root: "", ecosystem: @model.Cargo, manager: @model.Cargo, },
      ],
    },
  }
  let info_calls : Array[Array[String]] = []
  let mut published_called = false
  host.runner = (program, args, _cwd) => {
    if program == "cargo" && args.length() > 0 && args[0] == "info" {
      info_calls.push(args)
      // Simulate real Cargo behavior: without `--registry`, `cargo info` resolves the local workspace crate!
      if !args.contains("--registry") {
        return {
          exit_code: 0,
          stdout: "acme-core 0.1.1 (local)\n",
          stderr: "",
        }
      }
      return {
        exit_code: 101,
        stdout: "",
        stderr: "error: could not find `acme-core@0.1.1` in registry `crates-io`",
      }
    }
    if program == "cargo" && args == ["publish", "--allow-dirty"] {
      published_called = true
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.publish_release_with(
    host,
    loaded,
    @executor.PublishOptions::new(yes=true, no_tag=true),
  )
  assert_true(res.complete)
  assert_true(published_called)
  assert_eq(info_calls, [["info", "acme-core@0.1.1", "--registry", "crates-io"]])
}

///|
async test "create_tags batches multiple tag pushes into one git push and retries once on transient failure" {
  let host = fake_host()
  host.files["/repo/.moonset/release-state.json"] = @utf8.encode(
    (
      {
        "planFingerprint": "tag-batch-push-1",
        "sourceHead": Json::null(),
        "releases": [
          {
            "unitId": "npm:@acme/sdk",
            "oldVersion": "0.1.0",
            "newVersion": "0.2.0",
            "level": "minor",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "cargo:acme-core",
            "oldVersion": "0.1.0",
            "newVersion": "0.1.1",
            "level": "patch",
            "reasons": [],
            "changesets": [],
            "publish": true,
          },
          {
            "unitId": "moonbit:acme/core",
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
            "name": "npm/@acme/sdk@0.2.0",
            "unitId": "npm:@acme/sdk",
            "version": "0.2.0",
          },
          {
            "name": "cargo/acme-core@0.1.1",
            "unitId": "cargo:acme-core",
            "version": "0.1.1",
          },
          {
            "name": "moon/acme/core@0.1.1",
            "unitId": "moonbit:acme/core",
            "version": "0.1.1",
          },
        ],
        "consumedChangesets": [],
      } : Json).stringify(),
  )
  let loaded = sample_loaded(units=[
    mk_unit(
      "npm:@acme/sdk",
      "@acme/sdk",
      @model.Npm,
      "js",
      "packages/sdk",
      "packages/sdk/package.json",
      Some("0.2.0"),
    ),
    mk_unit(
      "cargo:acme-core",
      "acme-core",
      @model.Cargo,
      "rs",
      "crates/core",
      "crates/core/Cargo.toml",
      Some("0.1.1"),
    ),
    mk_unit(
      "moonbit:acme/core",
      "acme/core",
      @model.MoonBit,
      "moon",
      "",
      "moon.mod",
      Some("0.1.1"),
    ),
  ])
  let push_calls : Array[Array[String]] = []
  let mut push_attempts = 0
  host.runner = (_program, args, _cwd) => {
    if args == ["rev-parse", "HEAD"] {
      return { exit_code: 0, stdout: "release-sha\n", stderr: "", }
    }
    if args == ["status", "--porcelain"] {
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    if args.length() >= 2 && args[0] == "rev-parse" && args[1] == "--verify" {
      return { exit_code: 1, stdout: "", stderr: "not found", }
    }
    if args == ["ls-remote", "--tags", "origin"] {
      // Simulate first tag already on remote; only remaining two should be batch-pushed
      return {
        exit_code: 0,
        stdout: "release-sha\trefs/tags/npm/@acme/sdk@0.2.0\n",
        stderr: "",
      }
    }
    if args.length() > 0 && args[0] == "push" {
      push_attempts += 1
      push_calls.push(args)
      if push_attempts == 1 {
        return {
          exit_code: 1,
          stdout: "",
          stderr: "! [remote rejected] cargo/acme-core@0.1.1 (failed)",
        }
      }
      return { exit_code: 0, stdout: "", stderr: "", }
    }
    { exit_code: 0, stdout: "", stderr: "", }
  }
  let res = @executor.create_tags_with(
    host,
    loaded,
    @executor.TagOptions::new(push=true),
  )
  assert_eq(res.pushed, ["cargo/acme-core@0.1.1", "moon/acme/core@0.1.1"])
  assert_eq(push_calls, [
    [
      "push", "origin", "refs/tags/cargo/acme-core@0.1.1", "refs/tags/moon/acme/core@0.1.1",
    ],
    [
      "push", "origin", "refs/tags/cargo/acme-core@0.1.1", "refs/tags/moon/acme/core@0.1.1",
    ],
  ])
}
