///|
priv struct InitAnswers {
  use_github : Bool
  github_repo : String
  auto_commit : Bool
  access : String
  base_branch : String
}

///|
fn build_init_config_json(answers : InitAnswers) -> String {
  let base_branch = if answers.base_branch.trim() == "" {
    "main"
  } else {
    answers.base_branch.trim().to_owned()
  }
  let access = if answers.access == "public" { "public" } else { "restricted" }
  let changelog_block = if answers.use_github {
    let repo_json = Json::string(answers.github_repo.trim().to_owned()).stringify()
    "{\n    \"generator\": \"github\",\n    \"options\": {\n      \"repo\": " +
    repo_json +
    "\n    }\n  }"
  } else {
    "{\n    \"generator\": \"builtin\"\n  }"
  }
  let commit_mode = if answers.auto_commit { "both" } else { "never" }
  "{\n" +
  "  \"$schema\": \"https://moonset.dev/schema/config-v1.json\",\n" +
  "  \"schemaVersion\": 1,\n" +
  "  \"baseBranch\": " +
  Json::string(base_branch).stringify() +
  ",\n" +
  "  \"access\": " +
  Json::string(access).stringify() +
  ",\n" +
  "  \"changelog\": " +
  changelog_block +
  ",\n" +
  "  \"commit\": {\n" +
  "    \"mode\": \"" +
  commit_mode +
  "\"\n" +
  "  },\n" +
  "  \"formatter\": \"builtin\",\n" +
  "  \"ignore\": [],\n" +
  "  \"fixed\": [],\n" +
  "  \"linked\": [],\n" +
  "  \"updateInternalDependencies\": \"patch\"\n" +
  "}\n"
}

///|
async fn interactive_init(
  options : Options,
  config_path : String,
  dir : String,
) -> Int32 {
  let color = terminal_color_enabled(options.no_color, false)
  let render_state = TuiRenderState::new()
  tui_print_static(
    render_state,
    render_clack_intro(
      "🌙 moonset v" + cli_version(),
      with_guide=false,
      color~,
    ),
  )
  let state_ignore = resolve_cli_path(options.cwd, ".moonset/.gitignore")
  if @fs.exists(config_path) && !options.force {
    ignore(
      write_init_file(
        state_ignore,
        @executor.default_moonset_gitignore(),
        false,
      ),
    )
    tui_print_static(
      render_state,
      render_clack_log(
        "success",
        [
          style_green("Changesets", color) + " has already been initialized.",
          "Changeset commands can be run with no problems.",
        ],
        with_guide=false,
        trailing_bar=false,
        color~,
      ),
    )
    return 0
  }
  tui_print_static(
    render_state,
    render_clack_log(
      "info",
      [
        "A new " +
        style_blue("Changeset", color) +
        " configuration is being initialized...",
      ],
      with_guide=false,
      trailing_bar=true,
      color~,
    ),
  )

  tui_begin(render_state)
  defer tui_cleanup(render_state)

  let use_github = match
    tui_ask_confirm(
      render_state,
      "Should the GitHub integration be used for changelogs?",
      initial_value=false,
      with_guide=false,
      color~,
    ) {
    Some(v) => v
    None => return 130
  }
  let github_repo = if use_github {
    match
      tui_ask_text(
        render_state,
        "What is the GitHub repository? (e.g. org/repo)",
        placeholder="org/repo",
        not_empty=true,
        with_guide=false,
        color~,
      ) {
      TextSubmitted(repo) => repo
      _ => return 130
    }
  } else {
    ""
  }
  let auto_commit = match
    tui_ask_confirm(
      render_state,
      "Should changeset files and version bumps be automatically committed?",
      initial_value=false,
      with_guide=false,
      color~,
    ) {
    Some(v) => v
    None => return 130
  }
  let access_idx = match
    tui_ask_select(
      render_state,
      "Should packages be published publicly or privately by default?",
      ["Private", "Public"],
      with_guide=false,
      color~,
    ) {
    Some(i) => i
    None => return 130
  }
  let access = if access_idx == 0 { "restricted" } else { "public" }
  let base_branch = match
    tui_ask_text(
      render_state,
      "Which base branch should be used?",
      placeholder="main",
      default_value="main",
      with_guide=false,
      color~,
    ) {
    TextSubmitted(branch) => branch
    _ => return 130
  }

  tui_cleanup(render_state)

  let config_json = build_init_config_json({
    use_github,
    github_repo,
    auto_commit,
    access,
    base_branch,
  })
  ignore(write_init_file(config_path, config_json, options.force))
  let readme = @path.Path(dir).join(@path.Path("README.md")).to_string()
  ignore(write_init_file(readme, @executor.default_changeset_readme(), false))
  ignore(
    write_init_file(state_ignore, @executor.default_moonset_gitignore(), false),
  )

  let folder_rel = @path.Path(dir)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  let folder_label = if folder_rel == "" || folder_rel == "." {
    ".changeset"
  } else {
    folder_rel
  }
  tui_print_static(
    render_state,
    render_clack_log(
      "success",
      [
        "",
        style_green("Changesets", color) + " initialization is complete.",
        "The " +
        style_blue(folder_label, color) +
        " folder has been updated with:",
        "- " +
        style_blue("config.json", color) +
        " (customized based on the provided preferences)",
        "- " +
        style_blue("README.md", color) +
        " (a quick guide for using changesets)",
      ],
      with_guide=false,
      trailing_bar=false,
      color~,
    ),
  )
  0
}

///|
async fn write_init_file(path : String, content : String, force : Bool) -> Bool {
  if @fs.exists(path) && !force {
    return false
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_existing=true,
  )
  @fs.write_text(path, content)
  true
}

///|
async fn init_command(options : Options) -> Int32 {
  let config_path = match options.config {
    Some(custom) => resolve_cli_path(options.cwd, custom)
    None => resolve_cli_path(options.cwd, ".changeset/config.json")
  }
  let dir = @path.Path(config_path).dirname().to_string()
  if !options.json && !options.yes && !options.quiet && !is_non_interactive() {
    return interactive_init(options, config_path, dir)
  }
  let config = @executor.default_config_template()
  let created : Array[String] = []
  let skipped : Array[String] = []
  let conflicts : Array[String] = []
  let rel_config = @path.Path(config_path)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  if write_init_file(config_path, config, options.force) {
    created.push(rel_config)
  } else {
    skipped.push(rel_config)
  }
  let readme = @path.Path(dir).join(@path.Path("README.md")).to_string()
  let rel_readme = @path.Path(readme)
    .relative(base=@path.Path(options.cwd))
    .to_string()
    .replace_all(old="\\", new="/")
  if write_init_file(readme, @executor.default_changeset_readme(), false) {
    created.push(rel_readme)
  } else {
    skipped.push(rel_readme)
  }
  // Note: `.changeset/pre.json` is intentionally NOT gitignored (Changesets v3 / ADR-009).
  let state_ignore = resolve_cli_path(options.cwd, ".moonset/.gitignore")
  if write_init_file(state_ignore, @executor.default_moonset_gitignore(), false) {
    created.push(".moonset/.gitignore")
  } else {
    skipped.push(".moonset/.gitignore")
  }
  if options.json {
    print_json(
      {
        "schemaVersion": 1,
        "ok": true,
        "created": created,
        "skipped": skipped,
        "conflicts": conflicts,
        "config": config,
      },
      options.pretty,
    )
  } else if !options.quiet {
    let color = terminal_color_enabled(options.no_color, false)
    println(
      if created.is_empty() {
        style_warn("Changeset configuration already exists", color)
      } else {
        style_success("Initialized ", color) + style_pkg(dir, color)
      },
    )
  }
  0
}
