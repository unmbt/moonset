///|
async fn pre_command(options : Options) -> Int32 {
  let color = terminal_color_enabled(options.no_color, false)
  let loaded = @workspace.discover(options.cwd, config_path?=options.config)
  let path = resolve_cli_path(
    loaded.snapshot.root,
    loaded.snapshot.config.pre.file,
  )
  guard options.pre_action is Some(action) else {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "Missing required args for command `pre <enter|exit> [tag]`",
      ),
    )
  }
  if action == "exit" {
    if !@fs.exists(path) {
      raise @model.Invalid(
        @model.diagnostic("usage", "Not currently in prerelease mode", path~),
      )
    }
    let current = @engine.parse_pre_state(@fs.read_text(path), path~)
    if current.mode == @model.PreMode::Exit {
      raise @model.Invalid(
        @model.diagnostic("usage", "Already exited prerelease mode", path~),
      )
    }
    let updated : @model.PreState = { ..current, mode: @model.PreMode::Exit, }
    let text = updated.to_json().stringify(indent=2) + "\n"
    @fs.write_text(path, text)
    if options.json {
      print_json(updated.to_json(), options.pretty)
    } else if !options.quiet {
      println(
        style_success("Exited prerelease mode", color) +
        "; run `moonset version` to graduate",
      )
    }
    return 0
  }
  if action != "enter" {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "Only `enter` or `exit` is accepted after `pre`",
      ),
    )
  }
  guard options.pre_tag is Some(tag) && tag != "" else {
    raise @model.Invalid(
      @model.diagnostic(
        "usage", "pre enter requires a tag, e.g. `pre enter alpha`",
      ),
    )
  }
  if options.initial_version && !options.quiet {
    let warning_color = terminal_color_enabled(
      options.no_color || options.json || options.markdown,
      true,
    )
    stderr(
      style_warn("note", warning_color) +
      ": --initial-version is deprecated in v0.3.0 (Changesets v3 derives prerelease versions directly from manifests)",
    )
  }
  if @fs.exists(path) {
    let existing = @engine.parse_pre_state(@fs.read_text(path), path~)
    if existing.mode == @model.PreMode::Pre {
      raise @model.Invalid(
        @model.diagnostic(
          "usage",
          "Already in active prerelease mode (" + existing.tag + ")",
          path~,
        ),
      )
    }
  }
  let state : @model.PreState = {
    mode: @model.PreMode::Pre,
    tag,
    legacy_consumed: [],
  }
  let text = state.to_json().stringify(indent=2) + "\n"
  ignore(@engine.parse_pre_state(text, path~))
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_existing=true,
  )
  @fs.write_text(path, text)
  if options.json {
    print_json(state.to_json(), options.pretty)
  } else if !options.quiet {
    println(
      style_success("Entered prerelease mode", color) +
      " with tag '" +
      style_pkg(tag, color) +
      "'",
    )
  }
  0
}
