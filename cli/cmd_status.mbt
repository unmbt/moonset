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
  let pre_dir = snapshot.config.pre.directory
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
async fn status_or_plan_command(options : Options) -> Int32 {
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
      !loaded.snapshot.config.bridges().is_empty() {
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
  let warning_color = terminal_color_enabled(
    options.no_color || options.json || options.markdown,
    true,
  )
  for warning in plan.warnings {
    stderr(style_warn(warning.code, warning_color) + ": " + warning.message)
  }
  let text = if options.pretty {
    result.stringify(indent=2)
  } else {
    @model.canonical_json(result)
  }
  if options.command == "publish-plan" &&
    options.output != "" &&
    options.output != "-" {
    let path = resolve_cli_path(options.cwd, options.output)
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
    let color = terminal_color_enabled(options.no_color, false)
    println(
      style_title("\{loaded.snapshot.units.length()} modules", color) +
      "; \{loaded.changesets.length()} changesets; " +
      style_success("\{plan.releases.length()} releases", color),
    )
    for release in plan.releases {
      println(
        style_pkg(release.unit_id, color) +
        ": " +
        style_dim(release.old_version, color) +
        " -> " +
        style_success(release.new_version, color),
      )
      if options.verbose {
        println("  " + release.reasons.join(", "))
      }
    }
    if options.verbose {
      for path in loaded.snapshot.unmanaged {
        println(style_warn_soft("unmanaged: ", color) + style_pkg(path, color))
      }
      for path in loaded.snapshot.changed_files {
        println(style_accent("changed: ", color) + style_pkg(path, color))
      }
    }
  }
  if options.command == "status" &&
    status is { "errors": Array(errors), .. } &&
    !errors.is_empty() {
    stderr(
      style_warn("missing-changeset", warning_color) +
      ": Relevant committed files changed without a changeset",
    )
    1
  } else {
    0
  }
}
