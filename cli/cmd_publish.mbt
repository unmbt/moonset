///|
async fn tag_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let result = @executor.create_tags(
    loaded,
    @executor.TagOptions::new(
      dry_run=options.dry_run,
      push=options.tag_push,
      force=options.tag_force,
      yes=options.yes,
      format=options.tag_format,
    ),
  )
  if options.json {
    print_json(result.to_json(), options.pretty)
  } else if !options.quiet {
    if result.dry_run {
      println("Planned tags: " + result.tags.join(", "))
    } else {
      if !result.created.is_empty() {
        println("Created " + result.created.join(", "))
      }
      if !result.skipped.is_empty() {
        println("Skipped existing tags: " + result.skipped.join(", "))
      }
      if !result.pushed.is_empty() {
        println("Pushed " + result.pushed.join(", "))
      }
    }
  }
  0
}

///|
/// Execute the native pack adapter and return a machine-readable result.
async fn pack_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  if options.verify_artifacts {
    let report = @executor.verify_artifacts(
      loaded,
      artifacts_dir?=options.artifacts_dir,
    )
    if options.json {
      print_json(report.to_json(), options.pretty)
    } else if !options.quiet {
      if report.ok {
        println("Verified " + report.checked.to_string() + " artifact intents")
      } else {
        println(
          "Artifact verification failed with " +
          report.issues.length().to_string() +
          " issue(s)",
        )
        for issue in report.issues {
          println("  [" + issue.code + "] " + issue.message)
        }
      }
    }
    return if report.ok { 0 } else { 1 }
  }
  let target = options.pack_target.unwrap_or("source")
  let results = @executor.pack_artifacts(
    loaded,
    @executor.PackOptions::new(
      dry_run=options.dry_run,
      frozen=options.frozen,
      packages=options.packages,
      target~,
      manifest_out?=options.manifest_out,
    ),
  )
  let output : Json = {
    "schemaVersion": 1,
    "ok": true,
    "dryRun": options.dry_run,
    "target": target,
    "results": results.map(x => x.to_json()),
  }
  if options.json {
    print_json(output, options.pretty)
  } else if !options.quiet {
    println("Packed " + results.length().to_string() + " artifacts")
  }
  0
}

///|
/// Publish versioned units with durable per-target status.
async fn publish_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let result = @executor.publish_release(
    loaded,
    @executor.PublishOptions::new(
      dry_run=options.dry_run,
      only=options.only,
      registry?=options.registry,
      tag?=options.dist_tag,
      otp?=options.otp,
      yes=options.yes,
      allow_uncommitted=options.allow_uncommitted,
      retry=options.retry,
      no_tag=options.no_tag,
      reconcile=options.reconcile,
      artifacts_dir?=options.artifacts_dir,
    ),
  )
  if options.json {
    print_json(result.to_json(), options.pretty)
  } else if !options.quiet {
    for status in result.statuses {
      let detail = match status.message {
        Some(m) if m != "" => " (" + m + ")"
        _ => ""
      }
      println(
        "  [" +
        status.state.text() +
        "] " +
        status.unit_id +
        "@" +
        status.version +
        " -> " +
        status.registry +
        detail,
      )
    }
    if options.dry_run {
      println("Publish preflight complete")
    } else if result.complete {
      println("Publish complete")
    } else {
      println("Publish incomplete; see .moonset/publish-state.json")
    }
  }
  let has_failed = result.statuses.any(s => {
    s.state == @model.Failed ||
    s.state == @model.Blocked ||
    s.state == @model.Unknown
  })
  if has_failed || (!options.dry_run && !result.complete) {
    3
  } else {
    0
  }
}

///|
fn normalize_release_tag_version(ver : String) -> String {
  let trimmed = ver.trim().to_owned()
  if trimmed.has_prefix("v") && trimmed.length() > 1 {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
}

///|
fn is_prerelease_tag_version(ver : String) -> Bool {
  normalize_release_tag_version(ver).contains("-")
}

///|
async fn release_notes_command(options : Options) -> Int32 {
  if options.from_state && options.release_version is Some(_) {
    usage_error("--from-state cannot be combined with --version")
  }
  if !options.from_state && options.release_version is None {
    usage_error("release-notes requires either --version <ver> or --from-state")
  }
  if options.from_state &&
    (options.file_path is Some(_) || !options.packages.is_empty()) {
    usage_error("--from-state cannot be combined with --file or --package")
  }
  if options.packages.length() > 1 {
    usage_error("release-notes accepts at most one --package")
  }
  if options.from_state {
    // Discover workspace root FIRST so `--from-state` works from subdirectories too!
    let loaded = @workspace.discover(
      options.cwd,
      config_path?=options.config,
      include_commits=false,
    )
    let state_path = resolve_cli_path(
      loaded.snapshot.root,
      ".moonset/release-state.json",
    )
    if !@fs.exists(state_path) {
      raise @model.Invalid(
        @model.diagnostic(
          "usage",
          "No release state exists; run version first",
          path=state_path,
        ),
      )
    }
    let state_json = @json.parse(@fs.read_text(state_path)) catch {
      _ =>
        raise @model.Invalid(
          @model.diagnostic(
            "usage",
            "Release state is not valid JSON",
            path=state_path,
          ),
        )
    }
    let release_state = @model.ReleaseState::from_json(state_json)
    let unit_roots : Map[String, String] = Map([])
    for unit in loaded.snapshot.units {
      unit_roots[unit.id] = unit.root
    }
    let changelog_file = loaded.snapshot.config.changelog.file
    let notes_json : Array[Json] = []
    let found_bodies : Array[String] = []
    for tag in release_state.tags {
      let unit_root = unit_roots.get(tag.unit_id).unwrap_or("")
      let rel_path = if unit_root == "" || unit_root == "." {
        changelog_file
      } else {
        unit_root + "/" + changelog_file
      }
      let abs_path = resolve_cli_path(loaded.snapshot.root, rel_path)
      let body = if @fs.exists(abs_path) {
        @changelog.extract_unit_release_notes(
          @fs.read_text(abs_path),
          tag.unit_id,
          tag.version,
        ).unwrap_or("")
      } else {
        let root_fallback = resolve_cli_path(
          loaded.snapshot.root,
          changelog_file,
        )
        if @fs.exists(root_fallback) {
          @changelog.extract_unit_release_notes(
            @fs.read_text(root_fallback),
            tag.unit_id,
            tag.version,
          ).unwrap_or("")
        } else {
          ""
        }
      }
      let found = body != ""
      if found {
        found_bodies.push(body)
      }
      let row : Json = {
        "tag": tag.name,
        "unitId": tag.unit_id,
        "version": normalize_release_tag_version(tag.version),
        "changelogPath": rel_path,
        "found": found,
        "prerelease": is_prerelease_tag_version(tag.version),
        "body": body,
      }
      notes_json.push(row)
    }
    let payload : Json = { "schemaVersion": 1, "ok": true, "notes": notes_json }
    if options.json {
      print_json(payload, options.pretty)
    } else if !options.quiet && !found_bodies.is_empty() {
      println(found_bodies.join("\n\n"))
    }
    return 0
  }
  let target_ver = options.release_version.unwrap_or("")
  let norm_ver = normalize_release_tag_version(target_ver)
  if norm_ver == "" {
    usage_error("--version requires a non-empty version")
  }
  let mut unit_filter : String? = None
  let (rel_path, abs_path) = if options.file_path is Some(custom_file) &&
    options.packages.is_empty() {
    (custom_file, resolve_cli_path(options.cwd, custom_file))
  } else {
    let loaded = @workspace.discover(
      options.cwd,
      config_path?=options.config,
      include_commits=false,
    )
    let default_file = options.file_path.unwrap_or(
      loaded.snapshot.config.changelog.file,
    )
    if !options.packages.is_empty() {
      let pkg = options.packages[0]
      let cid = @engine.canonical_id(pkg)
      let found_unit = loaded.snapshot.units
        .iter()
        .find_first(u => u.id == cid || u.native_name == pkg)
      guard found_unit is Some(unit) else {
        raise @model.Invalid(
          @model.diagnostic(
            "unknown-unit",
            "Unknown package requested for release-notes: " + pkg,
          ),
        )
      }
      unit_filter = Some(unit.id)
      let rel = if unit.root == "" || unit.root == "." {
        default_file
      } else {
        unit.root + "/" + default_file
      }
      (rel, resolve_cli_path(loaded.snapshot.root, rel))
    } else {
      (default_file, resolve_cli_path(loaded.snapshot.root, default_file))
    }
  }
  let body = if @fs.exists(abs_path) {
    let src = @fs.read_text(abs_path)
    match unit_filter {
      Some(uid) =>
        @changelog.extract_unit_release_notes(src, uid, norm_ver).unwrap_or("")
      None => @changelog.extract_release_notes(src, norm_ver).unwrap_or("")
    }
  } else {
    ""
  }
  let found = body != ""
  if options.json {
    let payload : Json = {
      "schemaVersion": 1,
      "ok": true,
      "version": norm_ver,
      "changelogPath": rel_path,
      "found": found,
      "prerelease": is_prerelease_tag_version(norm_ver),
      "body": body,
    }
    print_json(payload, options.pretty)
  } else if !options.quiet && found {
    println(body)
  }
  0
}

///|
async fn doctor_command(options : Options) -> Int32 {
  let report = @executor.run_doctor(
    options.cwd,
    config_path?=options.config,
    check_registry=options.check_registry,
    fix=options.fix,
  )
  if options.json {
    print_json(report.to_json(), options.pretty)
  } else if !options.quiet {
    for check in report.checks {
      let badge = if check.ok { "PASS" } else { "FAIL" }
      println("[" + badge + "] " + check.name + ": " + check.message)
      if check.suggestion is Some(tip) {
        println("  hint: " + tip)
      }
    }
  }
  if report.ok {
    0
  } else {
    1
  }
}
