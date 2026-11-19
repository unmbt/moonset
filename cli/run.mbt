///|
fn cli_version() -> String {
  let document = @manifest.parse(
    @manifest.Kind::Mod,
    embedded_moon_mod,
    path="moon.mod",
  )
  document.version().unwrap_or("0.0.0")
}

///|
async fn stderr(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(message + "\n"))
}

///|
async fn load_commit_metadata(
  cwd : String,
  path_opt : String?,
) -> Map[String, (String?, String?)] {
  let out : Map[String, (String?, String?)] = Map([])
  guard path_opt is Some(raw_path) else { return out }
  let resolved = resolve_cli_path(cwd, raw_path)
  if !@fs.exists(resolved) {
    raise @model.Invalid(
      @model.diagnostic(
        "usage",
        "Commit metadata file does not exist: " + resolved,
        path=resolved,
      ),
    )
  }
  let parsed = @json.parse(@fs.read_text(resolved)) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-json",
          "Commit metadata file is not valid JSON",
          path=resolved,
        ),
      )
  }
  guard parsed is Object(entries) else {
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-json",
        "Commit metadata JSON must be an object keyed by commit SHA",
        path=resolved,
      ),
    )
  }
  for sha, item in entries {
    if item is Object(_) {
      let pr = match item {
        { "pr": String(s), .. } =>
          if s.trim() == "" {
            None
          } else {
            Some(s.trim().to_owned())
          }
        { "pr": Number(n, ..), .. } => Some(n.to_int().to_string())
        _ => None
      }
      let author = match item {
        { "author": String(s), .. } => {
          let clean = if s.trim().has_prefix("@") {
            s.trim()[1:].trim().to_owned()
          } else {
            s.trim().to_owned()
          }
          if clean == "" {
            None
          } else {
            Some(clean)
          }
        }
        _ => None
      }
      out[sha] = (pr, author)
    }
  }
  out
}

///|
async fn version_command(options : Options) -> Int32 {
  if options.markdown && !options.dry_run {
    usage_error("version --output markdown requires --dry-run")
  }
  if options.recover {
    let recovered = @executor.recover_version(options.cwd)
    if options.json {
      println(@model.canonical_json({ "recovered": recovered }))
    } else if !options.quiet {
      println(
        "Recovered " +
        recovered.length().to_string() +
        " files from .moonset/version-journal.json",
      )
    }
    return 0
  }
  let commit_metadata = load_commit_metadata(
    options.cwd,
    options.commit_metadata_path,
  )
  let loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
  )
  let generators = @changelog.GeneratorRegistry::new()
  let generator_name = loaded.snapshot.config.changelog
  let analysis = @engine.build_plan(
    loaded.snapshot,
    loaded.changesets,
    pre?=loaded.pre,
  )
  let version_options : @model.VersionOptions = {
    dry_run: options.dry_run,
    no_changelog: options.no_changelog,
    snapshot_tag: options.snapshot,
  }
  if options.snapshot is Some(tag) {
    let snap_cfg = @engine.parse_snapshot_config(loaded.snapshot.config)
    if !snap_cfg.enabled {
      raise @model.Invalid(
        @model.diagnostic(
          "snapshot-disabled", "Snapshot releases are disabled by configuration; set snapshot.enabled to true",
        ),
      )
    }
    if tag.trim() == "" {
      raise @model.Invalid(
        @model.diagnostic("invalid-input", "Snapshot tag cannot be empty"),
      )
    }
  }
  let texts : Map[String, String] = Map([])
  let metadata : Map[String, Json] = Map([])
  let today = @executor.utc_datetime(@env.now())
  if loaded.snapshot.config.changelog_enabled &&
    !options.no_changelog &&
    !["builtin", "git", "github", "none"].contains(generator_name) {
    let plugin = match loaded.snapshot.config.generators.get(generator_name) {
      Some(plugin) => plugin
      None =>
        raise @model.Invalid(
          @model.diagnostic(
            "unsupported-capability",
            "External changelog generator is not registered in plugins.generators: " +
            generator_name,
          ),
        )
    }
    let environment : Map[String, String] = Map([])
    for name in plugin.environment {
      match @env.get_env_var(name) {
        Some(value) => environment[name] = value
        None => ()
      }
    }
    let contexts = @engine.changelog_contexts_with_metadata(
      loaded.snapshot,
      analysis,
      version_options,
      generated_at=today,
      changeset_commits=loaded.changeset_commits,
      commit_metadata~,
    )
    for context in contexts {
      let response = @adapters.run_jsonl(
        {
          program: plugin.program,
          args: plugin.args,
          cwd: Some(loaded.snapshot.root),
          timeout_ms: plugin.timeout_ms,
          max_output_bytes: plugin.max_output_bytes,
          allowed_programs: plugin.allowed_programs,
          environment,
        },
        {
          schema_version: 1,
          protocol_method: "generate",
          payload: {
            "schemaVersion": 1,
            "generator": generator_name,
            "context": context.to_json(),
          },
        },
      )
      let (text, details) = @adapters.generator_result(response)
      let key = context.unit_id + "\u0000" + context.version
      texts[key] = text
      metadata[key] = details
    }
    generators.register(generator_name, context => {
      texts.get(context.unit_id + "\u0000" + context.version).unwrap_or("")
    })
  }
  let raw_plan = @engine.build_version_plan_with_metadata(
    loaded.snapshot,
    analysis,
    version_options,
    generated_at=today,
    generators~,
    changeset_commits=loaded.changeset_commits,
    commit_metadata~,
  )
  let changelogs = raw_plan.changelogs.map(entry => {
    let key = entry.unit_id + "\u0000" + entry.version
    if texts.contains(key) {
      {
        ..entry,
        generator: generator_name,
        metadata: metadata.get(key).unwrap_or(Json::empty_object()),
      }
    } else {
      entry
    }
  })
  let enriched = if texts.is_empty() {
    raw_plan
  } else {
    let generator_fingerprints : Array[Json] = changelogs.map(entry => {
      let row : Json = {
        "generator": entry.generator,
        "unitId": entry.unit_id,
        "version": entry.version,
        "metadata": entry.metadata,
        "text": entry.text,
      }
      row
    })
    let fingerprint = @model.fingerprint({
      "base": raw_plan.fingerprint,
      "generators": generator_fingerprints,
    })
    { ..raw_plan, changelogs, fingerprint, }
  }
  let plan = @executor.stage_lockfiles(loaded.snapshot.root, loaded, enriched)
  if options.json {
    let rendered = if options.pretty {
      plan.to_json().stringify(indent=2)
    } else {
      @model.canonical_json(plan.to_json())
    }
    println(rendered)
  }
  if options.dry_run {
    if options.markdown {
      let body = @engine.render_release_pr_body(
        loaded.snapshot,
        plan,
        pre?=loaded.pre,
      )
      @stdio.stdout.write(@utf8.encode(body))
    } else if !options.json && !options.quiet {
      println(
        "Dry run: \{plan.analysis.releases.length()} releases, \{plan.edits.length()} planned edits",
      )
      let planned_by_unit : Map[String, String] = Map([])
      for tag in plan.tags {
        planned_by_unit[tag.unit_id] = tag.version
      }
      for release in plan.analysis.releases {
        let target_ver = planned_by_unit
          .get(release.unit_id)
          .unwrap_or(release.new_version)
        println(
          "  " +
          release.unit_id +
          ": " +
          release.old_version +
          " -> " +
          target_ver,
        )
      }
      for edit in plan.edits {
        println("  [" + edit.kind + "] " + edit.path)
      }
    }
    return 0
  }
  if plan.edits.is_empty() {
    if !options.quiet && !options.json {
      if options.empty {
        println("No releases (acknowledged with --empty)")
      } else {
        println("No releases")
      }
    }
    return 0
  }
  ignore(@executor.apply_version_plan(loaded.snapshot.root, plan))
  let written_paths = plan.edits
    .filter(e => e.after_text != "")
    .map(e => e.path)
  ignore(
    @executor.format_files(
      loaded.snapshot.root,
      loaded.snapshot.config,
      written_paths,
      no_format=options.no_format,
    ),
  )
  let mut committed = false
  if !options.no_commit &&
    options.snapshot is None &&
    (
      loaded.snapshot.config.commit_mode == "version" ||
      loaded.snapshot.config.commit_mode == "both"
    ) {
    committed = @executor.commit_changes(
      loaded.snapshot.root,
      plan.edits.map(x => x.path),
      loaded.snapshot.config.commit_version_message,
    )
  }
  if !options.quiet && !options.json {
    println("Applied " + plan.edits.length().to_string() + " version edits")
    if committed {
      println("Committed release changes")
    }
  }
  0
}

///|
async fn tag_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let result = @executor.create_tags(loaded, {
    dry_run: options.dry_run,
    push: options.tag_push,
    force: options.tag_force,
    yes: options.yes,
    format: options.tag_format,
  })
  if options.json {
    let json = result.to_json()
    println(
      if options.pretty {
        json.stringify(indent=2)
      } else {
        @model.canonical_json(json)
      },
    )
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
    let json = report.to_json()
    if options.json {
      println(
        if options.pretty {
          json.stringify(indent=2)
        } else {
          @model.canonical_json(json)
        },
      )
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
  let results = @executor.pack_artifacts_for_target(
    loaded,
    {
      dry_run: options.dry_run,
      frozen: options.frozen,
      packages: options.packages,
    },
    target~,
    manifest_out?=options.manifest_out,
  )
  let output : Json = {
    "schemaVersion": 1,
    "dryRun": options.dry_run,
    "target": target,
    "results": results.map(x => x.to_json()),
  }
  if options.json {
    println(
      if options.pretty {
        output.stringify(indent=2)
      } else {
        @model.canonical_json(output)
      },
    )
  } else if !options.quiet {
    println("Packed " + results.length().to_string() + " artifacts")
  }
  0
}

///|
/// Publish versioned units with durable per-target status.
async fn publish_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let result = @executor.publish_release_with_artifacts(
    loaded,
    {
      dry_run: options.dry_run,
      only: options.only,
      registry: options.registry,
      tag: options.dist_tag,
      yes: options.yes,
      allow_uncommitted: options.allow_uncommitted,
      retry: options.retry,
      no_tag: options.no_tag,
    },
    artifacts_dir?=options.artifacts_dir,
  )
  let json = result.to_json()
  if options.json {
    println(
      if options.pretty {
        json.stringify(indent=2)
      } else {
        @model.canonical_json(json)
      },
    )
  } else if !options.quiet {
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
fn resolve_cli_path(cwd : String, rel_or_abs : String) -> String {
  if @path.Path(rel_or_abs).is_absolute() {
    rel_or_abs
  } else {
    @executor.absolute_path(cwd, rel_or_abs)
  }
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
    let state_path = resolve_cli_path(
      options.cwd,
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
    let state = @json.parse(@fs.read_text(state_path)) catch {
      _ =>
        raise @model.Invalid(
          @model.diagnostic(
            "usage",
            "Release state is not valid JSON",
            path=state_path,
          ),
        )
    }
    guard state is { "tags": Array(tag_items), .. } else {
      raise @model.Invalid(
        @model.diagnostic(
          "usage",
          "Release state has an invalid shape",
          path=state_path,
        ),
      )
    }
    let loaded = @workspace.discover(
      options.cwd,
      config_path?=options.config,
      include_commits=false,
    )
    let unit_roots : Map[String, String] = Map([])
    for unit in loaded.snapshot.units {
      unit_roots[unit.id] = unit.root
    }
    let changelog_file = loaded.snapshot.config.changelog_file
    let notes_json : Array[Json] = []
    let found_bodies : Array[String] = []
    for item in tag_items {
      if item
        is {
          "name": String(tag_name),
          "unitId": String(unit_id),
          "version": String(ver),
          ..
        } {
        let unit_root = unit_roots.get(unit_id).unwrap_or("")
        let rel_path = if unit_root == "" || unit_root == "." {
          changelog_file
        } else {
          unit_root + "/" + changelog_file
        }
        let abs_path = resolve_cli_path(loaded.snapshot.root, rel_path)
        let body = if @fs.exists(abs_path) {
          @changelog.extract_release_notes(@fs.read_text(abs_path), ver).unwrap_or(
            "",
          )
        } else {
          ""
        }
        let found = body != ""
        if found {
          found_bodies.push(body)
        }
        let row : Json = {
          "tag": tag_name,
          "unitId": unit_id,
          "version": normalize_release_tag_version(ver),
          "changelogPath": rel_path,
          "found": found,
          "prerelease": is_prerelease_tag_version(ver),
          "body": body,
        }
        notes_json.push(row)
      }
    }
    let payload : Json = { "schemaVersion": 1, "notes": notes_json }
    if options.json {
      println(
        if options.pretty {
          payload.stringify(indent=2)
        } else {
          @model.canonical_json(payload)
        },
      )
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
      loaded.snapshot.config.changelog_file,
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
    @changelog.extract_release_notes(@fs.read_text(abs_path), norm_ver).unwrap_or(
      "",
    )
  } else {
    ""
  }
  let found = body != ""
  if options.json {
    let payload : Json = {
      "schemaVersion": 1,
      "version": norm_ver,
      "changelogPath": rel_path,
      "found": found,
      "prerelease": is_prerelease_tag_version(norm_ver),
      "body": body,
    }
    println(
      if options.pretty {
        payload.stringify(indent=2)
      } else {
        @model.canonical_json(payload)
      },
    )
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
    let json = report.to_json()
    println(
      if options.pretty {
        json.stringify(indent=2)
      } else {
        @model.canonical_json(json)
      },
    )
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

///|
async fn write_new_file(path : String, content : String) -> Bool {
  if @fs.exists(path) {
    return false
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  let file = @fs.create(path, allow_existing=false)
  defer file.close()
  file.write(@utf8.encode(content))
  true
}

///|
async fn init_command(options : Options) -> Int32 {
  let _force = options.force
  let config_path = match options.config {
    Some(custom) =>
      if @path.Path(custom).is_absolute() {
        custom
      } else {
        @path.Path(options.cwd).join(@path.Path(custom)).to_string()
      }
    None =>
      @path.Path(options.cwd)
      .join(@path.Path(".changeset/config.json"))
      .to_string()
  }
  let dir = @path.Path(config_path).dirname().to_string()
  let config = "{\n  \"schemaVersion\": 1,\n  \"changelog\": {\"generator\": \"builtin\"},\n  \"access\": \"public\",\n  \"baseBranch\": \"main\",\n  \"commit\": {\"mode\": \"never\"},\n  \"formatter\": \"builtin\"\n}\n"
  let created : Array[String] = []
  let skipped : Array[String] = []
  let conflicts : Array[String] = []
  let rel_config = @path.Path(config_path)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  if write_new_file(config_path, config) {
    created.push(rel_config)
  } else {
    skipped.push(rel_config)
  }
  let readme = @path.Path(dir).join(@path.Path("README.md")).to_string()
  let rel_readme = @path.Path(readme)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  if write_new_file(
      readme, "# Changesets\n\nRun moonset add to record a release.\n",
    ) {
    created.push(rel_readme)
  } else {
    skipped.push(rel_readme)
  }
  let gitignore = @path.Path(dir).join(@path.Path(".gitignore")).to_string()
  let rel_gitignore = @path.Path(gitignore)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  if write_new_file(gitignore, "pre.json\n") {
    created.push(rel_gitignore)
  } else {
    skipped.push(rel_gitignore)
  }
  let state_dir = @path.Path(options.cwd)
    .join(@path.Path(".moonset"))
    .to_string()
  let state_ignore = @path.Path(state_dir)
    .join(@path.Path(".gitignore"))
    .to_string()
  if write_new_file(state_ignore, "version-journal.json\n") {
    created.push(".moonset/.gitignore")
  } else {
    skipped.push(".moonset/.gitignore")
  }
  if options.json {
    println(
      @model.canonical_json({
        "created": created,
        "skipped": skipped,
        "conflicts": conflicts,
        "config": config,
      }),
    )
  } else if !options.quiet {
    println(
      if created.is_empty() {
        "Changeset configuration already exists"
      } else {
        "Initialized " + dir
      },
    )
  }
  0
}

///|
async fn write_unique_changeset(
  root : String,
  base : String,
  preferred_id : String?,
  text : String,
) -> (String, String) {
  let original = preferred_id.unwrap_or("change-" + @env.now().to_string())
  let mut stem = original
  let mut attempt = 0
  for ;; {
    let path = @path.Path(root)
      .join(@path.Path(base))
      .join(@path.Path(stem + ".md"))
      .to_string()
    if !@fs.exists(path) {
      @fs.mkdir(
        @path.Path(path).dirname().to_string(),
        recursive=true,
        allow_exist=true,
      )
      let file = @fs.create(path, allow_existing=false)
      defer file.close()
      file.write(@utf8.encode(text))
      return (stem, path)
    }
    attempt += 1
    stem = original + "-" + attempt.to_string()
  }
}

///|
async fn add_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  if !options.json &&
    options.packages.is_empty() &&
    !options.empty &&
    options.summary is None &&
    @io.is_tty() &&
    @env.get_env_var("CI") is None {
    return interactive_add(options, loaded)
  }
  let summary = options.summary.unwrap_or("").trim().to_owned()
  let bump_text = options.bump.unwrap_or("patch")
  let bump = match bump_text {
    "major" => @model.Major
    "minor" => @model.Minor
    "patch" => @model.Patch
    "none" => @model.None
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "usage", "--type expects major, minor, patch, or none",
        ),
      )
  }
  let selected : Array[@model.Change] = []
  if !options.empty {
    if options.packages.is_empty() {
      raise @model.Invalid(
        @model.diagnostic(
          "usage", "add requires --package or --empty in non-interactive mode",
        ),
      )
    }
    for name in options.packages {
      if loaded.snapshot.config.mixed && !name.contains(":") {
        raise @model.Invalid(
          @model.diagnostic(
            "invalid-input",
            "Mixed mode requires ecosystem-prefixed UnitId: " + name,
          ),
        )
      }
      let unit_id = @engine.canonical_id(name)
      if !loaded.snapshot.units.any(u => u.id == unit_id) {
        raise @model.Invalid(
          @model.diagnostic("unknown-unit", "Unknown package: " + name),
        )
      }
      if !selected.any(c => c.unit_id == unit_id) {
        selected.push({ unit_id, bump, })
      }
    }
    if summary == "" {
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-input", "Changeset summary cannot be empty without --empty",
        ),
      )
    }
  }
  let text = if options.empty {
    if summary == "" {
      "---\n---\n"
    } else {
      "---\n---\n\n" + summary + "\n"
    }
  } else {
    @engine.format_changeset(@model.ChangesetDraft::{
      releases: selected,
      summary,
    })
  }
  let (stem, written) = write_unique_changeset(
    loaded.snapshot.root,
    loaded.changeset_directory,
    options.id,
    text,
  )
  let rel_written = @path.Path(written)
    .relative(base=@path.Path(loaded.snapshot.root))
    .to_string()
    .replace_all(old="\\", new="/")
  ignore(
    @executor.format_files(
      loaded.snapshot.root,
      loaded.snapshot.config,
      [rel_written],
      no_format=options.no_format,
    ),
  )
  if !options.no_commit &&
    (
      loaded.snapshot.config.commit_mode == "add" ||
      loaded.snapshot.config.commit_mode == "both"
    ) {
    ignore(
      @executor.commit_changes(
        loaded.snapshot.root,
        [rel_written],
        loaded.snapshot.config.commit_add_message,
      ),
    )
  }
  if options.json {
    println(
      @model.canonical_json({ "id": stem, "path": written, "summary": summary }),
    )
  } else if !options.quiet {
    println("Created " + written)
  }
  0
}

///|
async fn interactive_add(
  options : Options,
  loaded : @workspace.LoadedWorkspace,
) -> Int32 {
  let labels = loaded.snapshot.units.map(x => x.id)
  let versions = loaded.snapshot.units.map(x => {
    x.version.unwrap_or("unversioned")
  })
  let mut state = SelectState::new(labels.length())
  tui_begin()
  defer tui_cleanup()
  let mut done = false
  while !done && !state.cancelled {
    @tui.print_raw(
      "\u001b[2J\u001b[H" + render_package_page(labels, versions, state) + "\n",
    )
    let key = tui_key(@tui.read_key())
    state = reduce_select(state, key)
    done = state.confirmed
  }
  if state.cancelled || !state.confirmed {
    return 130
  }
  let chosen_indices : Array[Int32] = []
  for i, chosen in state.selected {
    if chosen {
      chosen_indices.push(i)
    }
  }
  if chosen_indices.is_empty() {
    return 2
  }
  let bumps = Array::make(chosen_indices.length(), 2)
  let choices = [@model.Major, @model.Minor, @model.Patch, @model.None]
  let mut pkg_step = 0
  while pkg_step < chosen_indices.length() {
    let unit_idx = chosen_indices[pkg_step]
    @tui.print_raw(
      "\u001b[2J\u001b[H" +
      render_bump_page(labels[unit_idx], versions[unit_idx], bumps[pkg_step]) +
      "\n",
    )
    let key = tui_key(@tui.read_key())
    let (next_cursor, confirmed, back) = reduce_choice(bumps[pkg_step], 4, key)
    bumps[pkg_step] = next_cursor
    if back {
      if key == Cancel {
        return 130
      }
      if pkg_step > 0 {
        pkg_step -= 1
      }
    } else if confirmed {
      pkg_step += 1
    }
  }
  let selected : Array[@model.Change] = []
  for i, unit_idx in chosen_indices {
    selected.push({ unit_id: labels[unit_idx], bump: choices[bumps[i]], })
  }
  let mut summary = ""
  let mut finalized = false
  while !finalized {
    @tui.print_raw("\u001b[2J\u001b[H? Enter a summary for this change\n")
    let mut submitted = false
    while !submitted {
      @tui.print_raw("  " + summary + "\u001b[K\r")
      let key = tui_key(@tui.read_key())
      let (next, confirm, cancel) = edit_summary(summary, key)
      summary = next
      if cancel {
        return 130
      }
      if confirm && summary.trim() != "" {
        submitted = true
      }
    }
    @tui.print_raw(
      "\u001b[2J\u001b[H" +
      render_confirmation(summary.trim().to_owned(), selected) +
      "\n",
    )
    let mut decided = false
    while !decided {
      let key = tui_key(@tui.read_key())
      match key {
        Enter => {
          decided = true
          finalized = true
        }
        Left => decided = true
        Cancel => return 130
        _ => ()
      }
    }
  }
  let text = @engine.format_changeset(@model.ChangesetDraft::{
    releases: selected,
    summary: summary.trim().to_owned(),
  })
  let (_, written) = write_unique_changeset(
    loaded.snapshot.root,
    loaded.changeset_directory,
    options.id,
    text,
  )
  let rel_written = @path.Path(written)
    .relative(base=@path.Path(loaded.snapshot.root))
    .to_string()
    .replace_all(old="\\", new="/")
  ignore(
    @executor.format_files(
      loaded.snapshot.root,
      loaded.snapshot.config,
      [rel_written],
      no_format=options.no_format,
    ),
  )
  if !options.no_commit &&
    (
      loaded.snapshot.config.commit_mode == "add" ||
      loaded.snapshot.config.commit_mode == "both"
    ) {
    ignore(
      @executor.commit_changes(
        loaded.snapshot.root,
        [rel_written],
        loaded.snapshot.config.commit_add_message,
      ),
    )
  }
  if !options.quiet {
    @tui.print_raw("\u001b[2J\u001b[HCreated " + written + "\n")
  }
  0
}

///|
async fn pre_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let path = @path.Path(loaded.snapshot.root)
    .join(@path.Path(loaded.snapshot.config.pre_file))
    .to_string()
  let action = options.pre_action.unwrap_or("status")
  if action == "status" {
    let raw_state : Json = if @fs.exists(path) {
      @engine.parse_pre_state(@fs.read_text(path), path~).to_json()
    } else {
      Json::null()
    }
    if options.json {
      println(
        if options.pretty {
          raw_state.stringify(indent=2)
        } else {
          @model.canonical_json(raw_state)
        },
      )
    } else if !options.quiet {
      println(raw_state.stringify(indent=2))
    }
    return 0
  }
  if action == "exit" {
    if !@fs.exists(path) {
      raise @model.Invalid(
        @model.diagnostic("usage", "Not currently in prerelease mode", path~),
      )
    }
    let current = @engine.parse_pre_state(@fs.read_text(path), path~)
    if current.mode == "exit" {
      raise @model.Invalid(
        @model.diagnostic("usage", "Already exited prerelease mode", path~),
      )
    }
    let updated : @model.PreState = { ..current, mode: "exit", }
    let text = updated.to_json().stringify(indent=2) + "\n"
    @fs.write_text(path, text)
    if options.json {
      println(@model.canonical_json(updated.to_json()))
    } else if !options.quiet {
      println("Exited prerelease mode; run `moonset version` to graduate")
    }
    return 0
  }
  if action != "enter" {
    raise @model.Invalid(
      @model.diagnostic("usage", "pre expects enter, exit, or status"),
    )
  }
  guard options.pre_tag is Some(tag) && tag != "" else {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "pre enter requires a tag, e.g. `pre enter alpha`",
      ),
    )
  }
  if @fs.exists(path) {
    let existing = @engine.parse_pre_state(@fs.read_text(path), path~)
    if existing.mode == "active" {
      raise @model.Invalid(
        @model.diagnostic(
          "usage",
          "Already in active prerelease mode (" + existing.tag + ")",
          path~,
        ),
      )
    }
  }
  let initial : Map[String, String] = Map([])
  if options.initial_version {
    for unit in loaded.snapshot.units {
      match unit.version {
        Some(v) => initial[unit.id] = v
        None => ()
      }
    }
  }
  let state : @model.PreState = {
    mode: "active",
    tag,
    initial_versions: initial,
    next_numbers: Map([]),
    consumed: [],
  }
  let text = state.to_json().stringify(indent=2) + "\n"
  ignore(@engine.parse_pre_state(text, path~))
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(path, text)
  if options.json {
    println(@model.canonical_json(state.to_json()))
  } else if !options.quiet {
    println("Entered prerelease mode with tag '" + tag + "'")
  }
  0
}

///|
async fn write_plan(
  path : String,
  text : String,
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory : String,
) -> Unit {
  let absolute = @path.Path(path).resolve().to_string()
  let directory = @fs.realpath(@path.Path(absolute).dirname().to_string())
  let resolved = if @fs.exists(absolute) {
    @fs.realpath(absolute)
  } else {
    @path.Path(directory)
    .join(@path.Path(@path.Path(absolute).basename().to_owned()))
    .to_string()
  }
  for source in snapshot.sources.keys() {
    let input = @path.Path(snapshot.root)
      .join(@path.Path(source))
      .normalize()
      .to_string()
    let canonical = if @fs.exists(input) { @fs.realpath(input) } else { input }
    if @path.Path(resolved) == @path.Path(canonical) {
      usage_error("Plan output cannot overwrite an input file: " + source)
    }
  }
  let basename = @path.Path(absolute).basename().to_owned()
  if ["moon.mod", "moon.pkg", "moon.work", "package.json", "Cargo.toml"].contains(
      basename,
    ) {
    usage_error("Plan output cannot overwrite a manifest")
  }
  let relative = @path.Path(resolved)
    .relative(base=@path.Path(snapshot.root))
    .to_string()
    .replace_all(old="\\", new="/")
  let pre_dir = snapshot.config.pre_directory
    .replace_all(old="\\", new="/")
    .trim()
    .to_owned()
  let clean_pre_dir = if pre_dir.has_suffix("/") {
    pre_dir[:pre_dir.length() - 1].to_owned()
  } else {
    pre_dir
  }
  if relative.split("/").any(x => x == ".git") ||
    relative.has_prefix(changeset_directory + "/") ||
    (
      clean_pre_dir != "" &&
      clean_pre_dir != "." &&
      relative.has_prefix(clean_pre_dir + "/")
    ) {
    usage_error("Plan output cannot overwrite release or Git inputs")
  }
  if @fs.exists(absolute) {
    let existing = @json.parse(@fs.read_text(absolute)) catch {
      _ => Json::null()
    }
    if !(existing
      is { "schemaVersion": 1, "stage": "analysis", "executable": False, .. }) {
      usage_error(
        "Existing output is not a moonset analysis plan; refusing to overwrite it",
      )
    }
  }
  let temporary = @path.Path(directory)
    .join(@path.Path(".moonset-plan-\{@env.now()}.tmp"))
    .to_string()
  let file = @fs.create(temporary, allow_existing=false)
  defer (@fs.remove(temporary, allow_missing=true) catch { _ => () })
  {
    defer file.close()
    file.write(@utf8.encode(text + "\n"))
  }
  @fs.rename(temporary, absolute, replace=true)
}

///|
async fn execute(options : Options) -> Int32 {
  if options.command == "" {
    if !options.json && @io.is_tty() && @env.get_env_var("CI") is None {
      return add_command(options)
    }
    usage_error("Subcommand is required in non-interactive or CI mode")
  }
  if options.command == "help" {
    println(
      "moonset \{cli_version()}\n  init [--force] [--config path]\n  add --package unit[,unit] --type major|minor|patch|none --summary text [--no-format]\n  pre enter <tag> [--initial-version] | pre exit | pre status\n  status [--since ref] [--verbose] [--output human|json|markdown] [--head-repo owner/name] [--head-ref branch]\n  publish-plan [--since ref] [--output path|-] [--pretty]\n  version [--dry-run] [--empty] [--no-changelog] [--no-commit] [--no-format] [--output human|json|markdown] [--commit-metadata path] [--snapshot tag] [--recover]\n  pack [--package unit] [--target name] [--manifest-out path] [--verify] [--artifacts-dir dir] [--frozen] [--dry-run] [--json]\n  publish [--dry-run] [--only unit] [--registry name|scope=name] [--tag dist-tag|scope=tag] [--artifacts-dir dir] [--retry n] [--allow-uncommitted] [--no-tag] [--yes] [--json]\n  tag|git-tag [--dry-run] [--push] [--force] [--tag-format template]\n  release-notes [--version ver] [--file path] [--package unit] [--from-state] [--json]\n  doctor [--fix] [--registry] [--output human|json]\n  Global: --cwd path --config path --json --quiet --no-color -h/--help -V/--version",
    )
    return 0
  }
  if options.command == "version-info" {
    println("moonset " + cli_version())
    return 0
  }
  if options.command == "init" {
    return init_command(options)
  }
  if options.command == "add" {
    return add_command(options)
  }
  if options.command == "pre" {
    return pre_command(options)
  }
  if options.command == "version" {
    return version_command(options)
  }
  if options.command == "tag" || options.command == "git-tag" {
    return tag_command(options)
  }
  if options.command == "pack" {
    return pack_command(options)
  }
  if options.command == "publish" {
    return publish_command(options)
  }
  if options.command == "doctor" {
    return doctor_command(options)
  }
  if options.command == "release-notes" {
    return release_notes_command(options)
  }
  let loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
    include_commits=false,
  )
  let plan = @engine.build_plan(
    loaded.snapshot,
    loaded.changesets,
    pre?=loaded.pre,
  )
  let status = @engine.status_json(
    loaded.snapshot,
    plan,
    changeset_directory=loaded.changeset_directory,
  )
  let result : Json = if options.command == "status" {
    status
  } else {
    let base = plan.to_json()
    if @engine.has_artifact_specs(loaded.snapshot.config) ||
      !loaded.snapshot.config.bridges.is_empty() {
      let dag = @engine.build_execution_dag(loaded.snapshot, plan)
      match base {
        Object(fields) => {
          fields["artifacts"] = Json::array(dag.artifacts.map(x => x.to_json()))
          fields["executionGraph"] = {
            "buildNodes": dag.build_nodes.map(x => x.to_json()),
            "publishNodes": dag.publish_nodes.map(x => x.to_json()),
            "publishOrder": dag.publish_order.map(Json::string),
          }
          Json::object(fields)
        }
        _ => base
      }
    } else {
      base
    }
  }
  for warning in plan.warnings {
    stderr(warning.code + ": " + warning.message)
  }
  let text = if options.pretty {
    result.stringify(indent=2)
  } else {
    @model.canonical_json(result)
  }
  if options.command == "publish-plan" &&
    options.output != "" &&
    options.output != "-" {
    let path = if @path.Path(options.output).is_absolute() {
      options.output
    } else {
      @path.Path(options.cwd).join(@path.Path(options.output)).to_string()
    }
    write_plan(path, text, loaded.snapshot, loaded.changeset_directory)
  } else if options.command == "status" && options.markdown {
    let md = @engine.status_markdown(loaded.snapshot, plan, options={
      ..@engine.CommentOptions::default(),
      head_repo: options.head_repo,
      head_ref: options.head_ref,
      changeset_directory: loaded.changeset_directory,
    })
    @stdio.stdout.write(@utf8.encode(md))
  } else if options.json {
    println(text)
  } else if !options.quiet {
    println(
      "\{loaded.snapshot.units.length()} modules; \{loaded.changesets.length()} changesets; \{plan.releases.length()} releases",
    )
    for release in plan.releases {
      println(
        release.unit_id +
        ": " +
        release.old_version +
        " -> " +
        release.new_version,
      )
      if options.verbose {
        println("  " + release.reasons.join(", "))
      }
    }
    if options.verbose {
      for path in loaded.snapshot.unmanaged {
        println("unmanaged: " + path)
      }
      for path in loaded.snapshot.changed_files {
        println("changed: " + path)
      }
    }
  }
  if options.command == "status" &&
    status is { "errors": Array(errors), .. } &&
    !errors.is_empty() {
    stderr(
      "missing-changeset: Relevant committed files changed without a changeset",
    )
    1
  } else {
    0
  }
}

///|
/// Run CLI arguments without the executable name. Errors never escape this boundary.
pub async fn run(args : Array[String]) -> Int32 {
  let wants_json = wants_json_output(args)
  let wants_markdown = wants_markdown_output(args)
  let command_name = detect_subcommand(args)
  execute(arguments(args)) catch {
    error => {
      let (code, diagnostic) = match error {
        @model.Invalid(diagnostic) => {
          let policy_codes = [
            "missing-changeset", "confirmation-required", "dirty-working-tree", "incomplete-selection",
          ]
          let exit_code : Int32 = if policy_codes.contains(diagnostic.code) {
            1
          } else {
            2
          }
          (exit_code, diagnostic)
        }
        @model.Io(message) => (3, @model.diagnostic("external-error", message))
        _ => (3, @model.diagnostic("external-error", error.to_string()))
      }
      if wants_markdown {
        @stdio.stdout.write(@utf8.encode(@engine.error_markdown(diagnostic)))
      } else if wants_json {
        let payload : Json = if command_name == "status" {
          {
            "schemaVersion": 1,
            "ok": false,
            "workspace": Json::null(),
            "changesets": [],
            "releases": [],
            "warnings": [],
            "errors": [diagnostic.to_json()],
            "hasChanges": false,
            "hasRelease": false,
          }
        } else {
          {
            "schemaVersion": 1,
            "ok": false,
            "command": command_name,
            "errors": [diagnostic.to_json()],
          }
        }
        println(@model.canonical_json(payload))
      }
      stderr(
        "\{diagnostic.path}:\{diagnostic.line}:\{diagnostic.column}: " +
        diagnostic.code +
        ": " +
        diagnostic.message,
      ) catch {
        _ => ()
      }
      code
    }
  }
}
