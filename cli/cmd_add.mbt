///|
async fn write_unique_changeset(
  root : String,
  base : String,
  preferred_id : String?,
  text : String,
) -> (String, String) {
  let original = match preferred_id {
    Some(raw) => validate_changeset_id(raw)
    None => "change-" + @env.now().to_string()
  }
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
    !is_non_interactive() {
    return interactive_add(options, loaded)
  }
  let summary = options.summary.unwrap_or("").trim().to_owned()
  let bump_text = options.bump.unwrap_or("patch")
  let bump = match @model.Bump::parse(bump_text) {
    Some(b) => b
    None =>
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
      if loaded.snapshot.config.is_mixed() && !name.contains(":") {
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
      loaded.snapshot.config.commit.mode == @model.CommitMode::Add ||
      loaded.snapshot.config.commit.mode == @model.CommitMode::Both
    ) {
    ignore(
      @executor.commit_changes(
        loaded.snapshot.root,
        [rel_written],
        loaded.snapshot.config.commit.add_message,
      ),
    )
  }
  if options.open_editor && !options.json {
    ignore(open_in_external_editor(written))
  }
  if options.json {
    print_json(
      {
        "schemaVersion": 1,
        "ok": true,
        "id": stem,
        "path": written,
        "summary": summary,
      },
      options.pretty,
    )
  } else if !options.quiet {
    let color = terminal_color_enabled(options.no_color, false)
    println(style_success("Created ", color) + style_pkg(written, color))
  }
  0
}
