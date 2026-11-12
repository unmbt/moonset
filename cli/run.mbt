///|
async fn stderr(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(message + "\n"))
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
  let dir = @path.Path(options.cwd).join(@path.Path(".changeset")).to_string()
  let config_path = @path.Path(dir).join(@path.Path("config.json")).to_string()
  let config = "{\n  \"changelog\": {\"generator\": \"builtin\"},\n  \"access\": \"public\",\n  \"baseBranch\": \"main\",\n  \"commit\": {\"mode\": \"never\"},\n  \"formatter\": \"builtin\"\n}\n"
  let created : Array[String] = []
  if write_new_file(config_path, config) {
    created.push(".changeset/config.json")
  }
  let readme = @path.Path(dir).join(@path.Path("README.md")).to_string()
  if write_new_file(
      readme, "# Changesets\n\nRun moonset add to record a release.\n",
    ) {
    created.push(".changeset/README.md")
  }
  let gitignore = @path.Path(dir).join(@path.Path(".gitignore")).to_string()
  if write_new_file(gitignore, "pre.json\n") {
    created.push(".changeset/.gitignore")
  }
  if options.json {
    println(@model.canonical_json({ "created": created, "config": config }))
  } else if !options.quiet {
    println(
      if created.is_empty() {
        "Changeset configuration already exists"
      } else {
        "Initialized .changeset"
      },
    )
  }
  0
}

///|
async fn add_command(options : Options) -> Int32 {
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  if !options.json && @io.is_tty() {
    return interactive_add(options, loaded)
  }
  let summary = options.summary.unwrap_or("")
  let package_text = options.package_name.unwrap_or("")
  let names : Array[String] = if package_text == "" {
    []
  } else {
    package_text
    .split(",")
    .map(x => x.trim().to_owned())
    .filter(x => x != "")
    .collect()
  }
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
  let selected : Array[@model.Change] = if options.empty {
    []
  } else {
    names.map(name => @model.Change::{
      unit_id: @engine.canonical_id(name),
      bump,
    })
  }
  if selected.is_empty() && !options.empty {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "add requires --package or --empty in non-interactive mode",
      ),
    )
  }
  let text = if options.empty {
    "---\n---\n\n" + summary.trim().to_owned() + "\n"
  } else {
    @engine.format_changeset(@model.ChangesetDraft::{
      releases: selected,
      summary,
    })
  }
  let base = loaded.changeset_directory
  let original = options.id.unwrap_or("change-" + @env.now().to_string())
  let mut stem = original
  let mut written = ""
  let mut attempt = 0
  while written == "" {
    let path = @path.Path(loaded.snapshot.root)
      .join(@path.Path(base))
      .join(@path.Path(stem + ".md"))
      .to_string()
    if !@fs.exists(path) {
      let file = @fs.create(path, allow_existing=false)
      defer file.close()
      file.write(@utf8.encode(text))
      written = path
    } else {
      attempt += 1
      stem = original + "-" + attempt.to_string()
    }
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
  let selected = []
  for i, chosen in state.selected {
    if chosen {
      selected.push(@model.Change::{ unit_id: labels[i], bump: @model.Patch, })
    }
  }
  if selected.is_empty() {
    return 2
  }
  @tui.print_raw("\u001b[2J\u001b[H? Enter a summary for this change\n")
  let mut summary = ""
  let mut submitted = false
  while !submitted {
    @tui.print_raw("  " + summary + "\u001b[K\r")
    let key = tui_key(@tui.read_key())
    let (next, confirm, cancel) = edit_summary(summary, key)
    summary = next
    if cancel {
      return 130
    }
    submitted = confirm
  }
  let text = @engine.format_changeset(@model.ChangesetDraft::{
    releases: selected,
    summary,
  })
  let original = options.id.unwrap_or("change-" + @env.now().to_string())
  let path = @path.Path(loaded.snapshot.root)
    .join(@path.Path(loaded.changeset_directory))
    .join(@path.Path(original + ".md"))
    .to_string()
  let file = @fs.create(path, allow_existing=false)
  defer file.close()
  file.write(@utf8.encode(text))
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
    if @fs.exists(path) {
      println(@fs.read_text(path))
    } else {
      println("null")
    }
    return 0
  }
  if action == "exit" {
    if @fs.exists(path) {
      @fs.remove(path, allow_missing=true)
    }
    return 0
  }
  if action != "enter" {
    raise @model.Invalid(
      @model.diagnostic("usage", "pre expects enter, exit, or status"),
    )
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
    tag: "next",
    initial_versions: initial,
    next_numbers: Map([]),
    consumed: [],
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
  )
  @fs.write_text(path, state.to_json().stringify(indent=2) + "\n")
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
      "moonset Phase 2\n  init [--force]\n  add --package unit[,unit] --type major|minor|patch|none --summary text\n  pre enter|exit|status [--initial-version]\n  status [--since ref] [--verbose] [--output human|json]\n  publish-plan [--since ref] [--output path|-] [--pretty]\n  Global: --cwd path --config path --json --quiet --no-color --help --version",
    )
    return 0
  }
  if options.command == "version-info" {
    println("moonset 0.1.0-alpha.1")
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
