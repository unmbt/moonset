///|
async fn write_init_file(path : String, content : String, force : Bool) -> Bool {
  if @fs.exists(path) && !force {
    return false
  }
  @fs.mkdir(
    @path.Path(path).dirname().to_string(),
    recursive=true,
    allow_exist=true,
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
