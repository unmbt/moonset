///|
async fn stderr(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(message + "\n"))
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
  if relative.split("/").any(x => x == ".git") ||
    relative.has_prefix(changeset_directory + "/") {
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
  if options.command == "help" {
    println(
      "moonset Phase 1\n  status [--since ref] [--verbose] [--output human|json]\n  publish-plan [--since ref] [--output path|-] [--pretty]\n  Global: --cwd path --config path --json --quiet --no-color --help --version",
    )
    return 0
  }
  if options.command == "version-info" {
    println("moonset 0.1.0-alpha.1")
    return 0
  }
  let loaded = @workspace.discover(
    options.cwd,
    config_path?=options.config,
    since?=options.since,
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
  let result = if options.command == "status" { status } else { plan.to_json() }
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
  let wants_json = args.contains("--json") ||
    args.contains("publish-plan") ||
    args.contains("json")
  execute(arguments(args)) catch {
    error => {
      let (code, diagnostic) = match error {
        @model.Invalid(diagnostic) => (2, diagnostic)
        @model.Io(message) => (3, @model.diagnostic("external-error", message))
        _ => (3, @model.diagnostic("external-error", error.to_string()))
      }
      if wants_json {
        println(
          @model.canonical_json({
            "schemaVersion": 1,
            "workspace": Json::null(),
            "changesets": [],
            "releases": [],
            "warnings": [],
            "errors": [diagnostic.to_json()],
            "hasChanges": false,
            "hasRelease": false,
          }),
        )
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
