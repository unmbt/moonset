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
async fn resolve_recovery_root(options : Options) -> String {
  // Check cwd first, then walk up via workspace discovery so running `--recover`
  // from a subdirectory finds the root `.moonset/version-journal.json`.
  let direct = resolve_cli_path(options.cwd, ".moonset/version-journal.json")
  if @fs.exists(direct) {
    return options.cwd
  }
  let discovered = Some(
    @workspace.discover(
      options.cwd,
      config_path?=options.config,
      include_commits=false,
    ),
  ) catch {
    _ => None
  }
  match discovered {
    Some(loaded) => loaded.snapshot.root
    None => options.cwd
  }
}

///|
fn host_allowed_plugin_programs() -> Array[String]? {
  match @env.get_env_var("MOONSET_ALLOWED_PLUGIN_PROGRAMS") {
    Some(raw) => {
      let allowed : Array[String] = []
      for item in raw.split(",") {
        let trimmed = item.trim().to_owned()
        if trimmed != "" && !allowed.contains(trimmed) {
          allowed.push(trimmed)
        }
      }
      Some(allowed)
    }
    None => None
  }
}

///|
fn build_version_commit_message(
  config : @model.CommitConfig,
  releases : Array[@model.Release],
) -> String {
  let base = if config.version_message == "chore: release" &&
    !releases.is_empty() {
    let lines = ["chore: version packages", ""]
    for rel in releases {
      lines.push("- " + rel.unit_id + "@" + rel.new_version)
    }
    lines.join("\n")
  } else {
    config.version_message
  }
  if config.skip_ci && !base.to_lower().contains("[skip ci]") {
    base + "\n\n[skip ci]"
  } else {
    base
  }
}

///|
async fn write_pr_body_file(cwd : String, path : String, body : String) -> Unit {
  let resolved = resolve_cli_path(cwd, path)
  @fs.mkdir(
    @path.Path(resolved).dirname().to_string(),
    recursive=true,
    allow_existing=true,
  )
  @fs.write_text(resolved, body)
}

///|
async fn version_command(options : Options) -> Int32 {
  let color = terminal_color_enabled(options.no_color, false)
  if options.markdown && !options.dry_run {
    usage_error("version --output markdown requires --dry-run")
  }
  if options.recover {
    let recover_root = resolve_recovery_root(options)
    let recovered = @executor.recover_version(recover_root)
    if options.json {
      print_json(
        { "schemaVersion": 1, "ok": true, "recovered": recovered },
        options.pretty,
      )
    } else if !options.quiet {
      println(
        style_success("Recovered ", color) +
        recovered.length().to_string() +
        " files from " +
        style_pkg(".moonset/version-journal.json", color),
      )
    }
    return 0
  }
  let commit_metadata = load_commit_metadata(
    options.cwd,
    options.commit_metadata_path,
  )
  let raw_loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
  )
  // Apply CLI `--ignore` and `--snapshot-prerelease-template` overrides without mutating disk config.
  let base_config = raw_loaded.snapshot.config
  let merged_ignore = if options.ignore_packages.is_empty() {
    base_config.ignore
  } else {
    let copy = base_config.ignore.copy()
    for pat in options.ignore_packages {
      if !copy.contains(pat) {
        copy.push(pat)
      }
    }
    copy
  }
  let merged_snapshot = match options.snapshot_prerelease_template {
    Some(template) => {
      @engine.validate_snapshot_template(template)
      { ..base_config.snapshot, prerelease_template: template, }
    }
    None => base_config.snapshot
  }
  let loaded : @workspace.LoadedWorkspace = {
    ..raw_loaded,
    snapshot: {
      ..raw_loaded.snapshot,
      config: {
        ..base_config,
        ignore: merged_ignore,
        snapshot: merged_snapshot,
      },
    },
  }
  let generators = @changelog.GeneratorRegistry::new()
  let generator_name = loaded.snapshot.config.changelog.generator
  let now_ms = @env.now()
  let today = @executor.utc_datetime(now_ms)
  let server_url = @env.get_env_var("GITHUB_SERVER_URL").unwrap_or(
    "https://github.com",
  )
  let is_snapshot = options.snapshot_enabled || options.snapshot is Some(_)
  let analysis = @engine.build_plan(
    loaded.snapshot,
    loaded.changesets,
    pre?=loaded.pre,
    generated_at=today,
    snapshot_mode=is_snapshot,
    snapshot_tag?=options.snapshot,
    timestamp_ms=now_ms.to_string(),
  )
  let version_options : @model.VersionOptions = {
    dry_run: options.dry_run,
    no_changelog: options.no_changelog,
    snapshot: is_snapshot,
    snapshot_tag: options.snapshot,
  }
  let texts : Map[String, String] = Map([])
  let metadata : Map[String, Json] = Map([])
  if loaded.snapshot.config.changelog.enabled &&
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
      server_url~,
    )
    let host_allowlist = host_allowed_plugin_programs()
    let spec : @adapters.PluginSpec = {
      program: plugin.program,
      args: plugin.args,
      cwd: Some(loaded.snapshot.root),
      timeout_ms: plugin.timeout_ms,
      max_output_bytes: plugin.max_output_bytes,
      allowed_programs: plugin.allowed_programs,
      environment,
    }
    for context in contexts {
      let key = context.unit_id + "\u0000" + context.version
      if plugin.protocol == "line" {
        let rendered_lines : Map[String, String] = Map([])
        for line in context.lines {
          let line_payload : Json = {
            "schemaVersion": 1,
            "generator": generator_name,
            "unitId": context.unit_id,
            "version": context.version,
            "changesetId": line.changeset_id,
            "summary": line.summary,
            "bump": line.bump.text(),
            "oldVersion": line.old_version,
            "newVersion": line.new_version,
            "commit": match line.commit {
              Some(c) => Json::string(c)
              None => Json::null()
            },
            "pullRequest": match line.pull_request {
              Some(p) => Json::string(p)
              None => Json::null()
            },
            "authors": line.authors.map(Json::string),
            "repository": match context.repository {
              Some(r) => Json::string(r)
              None => Json::null()
            },
            "serverUrl": context.server_url,
          }
          let resp = @adapters.run_jsonl(
            spec,
            {
              schema_version: 1,
              protocol_method: "getReleaseLine",
              payload: line_payload,
            },
            host_allowed_programs?=host_allowlist,
          )
          let (line_text, _) = @adapters.generator_result(resp)
          rendered_lines[line.changeset_id + "\u0000" + line.bump.text()] = line_text
        }
        let mut rendered_dep = ""
        if !context.dependency_lines.is_empty() {
          let dep_resp = @adapters.run_jsonl(
            spec,
            {
              schema_version: 1,
              protocol_method: "getDependencyReleaseLine",
              payload: {
                "schemaVersion": 1,
                "generator": generator_name,
                "unitId": context.unit_id,
                "version": context.version,
                "dependencyLines": context.dependency_lines.map(Json::string),
                "repository": match context.repository {
                  Some(r) => Json::string(r)
                  None => Json::null()
                },
                "serverUrl": context.server_url,
              },
            },
            host_allowed_programs?=host_allowlist,
          )
          let (dep_text, _) = @adapters.generator_result(dep_resp)
          rendered_dep = dep_text
        }
        texts[key] = @changelog.render_with_line_hooks(context, {
          get_release_line: (line, _ctx) => {
            rendered_lines
            .get(line.changeset_id + "\u0000" + line.bump.text())
            .unwrap_or("")
          },
          get_dependency_release_line: (_deps, _ctx) => rendered_dep,
        })
        metadata[key] = { "protocol": "line" }
      } else {
        let response = @adapters.run_jsonl(
          spec,
          {
            schema_version: 1,
            protocol_method: "generate",
            payload: {
              "schemaVersion": 1,
              "generator": generator_name,
              "context": context.to_json(),
            },
          },
          host_allowed_programs?=host_allowlist,
        )
        let (text, details) = @adapters.generator_result(response)
        texts[key] = text
        metadata[key] = details
      }
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
    server_url~,
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
  if options.pr_body_out is Some(pr_out) {
    let body = @engine.render_release_pr_body(
      loaded.snapshot,
      enriched,
      pre?=loaded.pre,
    )
    write_pr_body_file(options.cwd, pr_out, body)
  }
  if options.dry_run {
    if options.json {
      print_json(enriched.to_json(), options.pretty)
    } else if options.markdown {
      let body = @engine.render_release_pr_body(
        loaded.snapshot,
        enriched,
        pre?=loaded.pre,
      )
      @stdio.stdout.write(@utf8.encode(body))
    } else if !options.quiet {
      println(
        style_title("Dry run", color) +
        ": \{enriched.analysis.releases.length()} releases, \{enriched.edits.length()} planned edits",
      )
      for release in enriched.analysis.releases {
        println(
          "  " +
          style_pkg(release.unit_id, color) +
          ": " +
          style_dim(release.old_version, color) +
          " -> " +
          style_success(release.new_version, color),
        )
      }
      for edit in enriched.edits {
        println(
          "  [" +
          style_kind(edit.kind, color) +
          "] " +
          style_pkg(edit.path, color),
        )
      }
    }
    return 0
  }
  let plan = @executor.stage_lockfiles(loaded.snapshot.root, loaded, enriched)
  if plan.edits.is_empty() {
    if options.json {
      print_json(plan.to_json(), options.pretty)
    } else if !options.quiet {
      if options.empty {
        println(
          style_warn("No releases", color) + " (acknowledged with --empty)",
        )
      } else {
        println(style_warn("No releases", color))
      }
    }
    return 0
  }
  // Apply edits with journal retained across formatting so a formatter failure
  // can still be rolled back via `moonset version --recover`.
  ignore(
    @executor.apply_version_plan(loaded.snapshot.root, plan, keep_journal=true),
  )
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
  @executor.finalize_version_journal(loaded.snapshot.root)
  let mut committed = false
  if !options.no_commit &&
    !is_snapshot &&
    (
      loaded.snapshot.config.commit.mode == @model.CommitMode::Version ||
      loaded.snapshot.config.commit.mode == @model.CommitMode::Both
    ) {
    let commit_msg = build_version_commit_message(
      loaded.snapshot.config.commit,
      plan.analysis.releases,
    )
    committed = @executor.commit_changes(
      loaded.snapshot.root,
      plan.edits.map(x => x.path),
      commit_msg,
    )
  }
  if options.json {
    print_json(plan.to_json(), options.pretty)
  } else if !options.quiet {
    println(
      style_success("Applied ", color) +
      plan.edits.length().to_string() +
      " version edits",
    )
    if committed {
      println(style_success("Committed release changes", color))
    }
  }
  0
}
