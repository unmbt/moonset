///|
priv struct Options {
  command : String
  help_topic : String?
  help_text : String?
  cwd : String
  config : String?
  since : String?
  json : Bool
  markdown : Bool
  output : String
  pretty : Bool
  quiet : Bool
  verbose : Bool
  force : Bool
  no_color : Bool
  packages : Array[String]
  ignore_packages : Array[String]
  bump : String?
  summary : String?
  empty : Bool
  id : String?
  open_editor : Bool
  head_repo : String?
  head_ref : String?
  initial_version : Bool
  pre_action : String?
  pre_tag : String?
  dry_run : Bool
  no_changelog : Bool
  no_commit : Bool
  no_tag : Bool
  no_format : Bool
  recover : Bool
  snapshot_enabled : Bool
  snapshot : String?
  tag_push : Bool
  tag_force : Bool
  tag_format : String
  yes : Bool
  only : Array[String]
  registry : String?
  dist_tag : String?
  otp : String?
  reconcile : Bool
  retry : Int32
  allow_uncommitted : Bool
  frozen : Bool
  check_registry : Bool
  fix : Bool
  release_version : String?
  file_path : String?
  from_state : Bool
  pack_target : String?
  manifest_out : String?
  artifacts_dir : String?
  verify_artifacts : Bool
  commit_metadata_path : String?
  snapshot_prerelease_template : String?
  pr_body_out : String?
  output_file : String?
  marker_scope : String?
  access : String?
  ignore_scripts : Bool
  from_manifests : Bool
}

///|
fn parse_non_negative_int(value : String) -> Int32? {
  if value == "" {
    return None
  }
  let mut acc : Int32 = 0
  for ch in value.to_array() {
    if ch < '0' || ch > '9' {
      return None
    }
    let digit = ch.to_int() - '0'.to_int()
    if acc > 214748364 || (acc == 214748364 && digit > 7) {
      return None
    }
    acc = acc * 10 + digit
  }
  Some(acc)
}

///|
fn usage_error(message : String) -> Unit raise @model.MoonsetError {
  raise @model.Invalid(@model.diagnostic("usage", message))
}

///|
fn is_known_subcommand(token : String) -> Bool {
  [
    "init", "add", "pre", "status", "publish-plan", "version", "tag", "git-tag",
    "pack", "publish", "doctor", "release-notes",
  ].contains(token)
}

///|
/// Expand `--flag=value` into `["--flag", "value"]` before `--` so all downstream
/// detectors and parsers handle both `--flag value` and `--flag=value` identically.
fn normalize_cli_args(raw_args : Array[String]) -> Array[String] {
  let out : Array[String] = []
  let mut after_double_dash = false
  for arg in raw_args {
    if after_double_dash {
      out.push(arg)
      continue
    }
    if arg == "--" {
      after_double_dash = true
      out.push(arg)
      continue
    }
    if arg.has_prefix("--") {
      match arg.find("=") {
        Some(idx) if idx > 2 => {
          let name = arg[:idx].to_owned()
          let value = arg[idx + 1:].to_owned()
          out.push(name)
          out.push(value)
        }
        _ => out.push(arg)
      }
    } else {
      out.push(arg)
    }
  }
  out
}

///|
fn is_always_value_flag(arg : String) -> Bool {
  match arg {
    "--cwd"
    | "--config"
    | "--since"
    | "--output"
    | "--format"
    | "--package"
    | "--ignore"
    | "--type"
    | "--summary"
    | "--message"
    | "-m"
    | "--id"
    | "--head-repo"
    | "--head-ref"
    | "--only"
    | "--tag-format"
    | "--tag"
    | "--otp"
    | "--retry"
    | "--file"
    | "--target"
    | "--manifest-out"
    | "--artifacts-dir"
    | "--commit-metadata"
    | "--snapshot-prerelease-template"
    | "--pr-body-out"
    | "--output-file"
    | "-o"
    | "--marker-scope"
    | "--access" => true
    _ => false
  }
}

///|
fn detect_subcommand(raw_args : Array[String]) -> String {
  let args = normalize_cli_args(raw_args)
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      break
    }
    if is_always_value_flag(arg) {
      if i < args.length() {
        i += 1
      }
      continue
    }
    if arg == "--registry" || arg == "--snapshot" {
      if i < args.length() &&
        !args[i].has_prefix("-") &&
        !is_known_subcommand(args[i]) {
        i += 1
      }
      continue
    }
    if !arg.has_prefix("-") {
      return arg
    }
  }
  ""
}

///|
fn is_value_flag(arg : String, subcommand : String) -> Bool {
  if is_always_value_flag(arg) {
    return true
  }
  (arg == "--registry" && subcommand != "doctor") ||
  (arg == "--version" && subcommand == "release-notes")
}

///|
fn wants_json_output(raw_args : Array[String]) -> Bool {
  let args = normalize_cli_args(raw_args)
  let subcommand = detect_subcommand(args)
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      break
    }
    if arg == "--json" ||
      (subcommand == "publish-plan" && arg == "publish-plan") {
      return true
    }
    if (arg == "--output" || arg == "--format") && i < args.length() {
      if args[i] == "json" {
        return true
      }
      i += 1
      continue
    }
    if is_value_flag(arg, subcommand) && i < args.length() {
      i += 1
    } else if arg == "--snapshot" &&
      i < args.length() &&
      !args[i].has_prefix("-") &&
      !is_known_subcommand(args[i]) {
      i += 1
    }
  }
  false
}

///|
fn wants_markdown_output(raw_args : Array[String]) -> Bool {
  let args = normalize_cli_args(raw_args)
  let subcommand = detect_subcommand(args)
  if subcommand != "status" {
    return false
  }
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      break
    }
    if (arg == "--output" || arg == "--format") && i < args.length() {
      if args[i] == "markdown" {
        return true
      }
      i += 1
      continue
    }
    if is_value_flag(arg, subcommand) && i < args.length() {
      i += 1
    }
  }
  false
}

///|
fn has_no_color_flag(raw_args : Array[String]) -> Bool {
  let args = normalize_cli_args(raw_args)
  let subcommand = detect_subcommand(args)
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if arg == "--" {
      break
    }
    if arg == "--no-color" {
      return true
    }
    if is_value_flag(arg, subcommand) && i < args.length() {
      i += 1
    } else if arg == "--snapshot" &&
      i < args.length() &&
      !args[i].has_prefix("-") &&
      !is_known_subcommand(args[i]) {
      i += 1
    }
  }
  false
}

///|
fn default_cwd() -> String {
  match @env.get_env_var("MOONSET_CWD") {
    Some(v) if v.trim() != "" => v.trim().to_owned()
    _ => @env.current_dir().unwrap_or(".")
  }
}

///|
fn default_config() -> String? {
  match @env.get_env_var("MOONSET_CONFIG") {
    Some(v) if v.trim() != "" => Some(v.trim().to_owned())
    _ => None
  }
}

///|
fn default_options(
  command : String,
  help_topic~ : String? = None,
  help_text~ : String? = None,
) -> Options {
  {
    command,
    help_topic,
    help_text,
    cwd: default_cwd(),
    config: default_config(),
    since: None,
    json: false,
    markdown: false,
    output: "",
    pretty: false,
    quiet: false,
    verbose: false,
    force: false,
    no_color: @env.get_env_var("NO_COLOR") is Some(v) && v != "",
    packages: [],
    ignore_packages: [],
    bump: None,
    summary: None,
    empty: false,
    id: None,
    open_editor: false,
    head_repo: None,
    head_ref: None,
    initial_version: false,
    pre_action: None,
    pre_tag: None,
    dry_run: false,
    no_changelog: false,
    no_commit: false,
    no_tag: false,
    no_format: false,
    recover: false,
    snapshot_enabled: false,
    snapshot: None,
    tag_push: false,
    tag_force: false,
    tag_format: "",
    yes: false,
    only: [],
    registry: None,
    dist_tag: None,
    otp: None,
    reconcile: false,
    retry: 0,
    allow_uncommitted: false,
    frozen: false,
    check_registry: false,
    fix: false,
    release_version: None,
    file_path: None,
    from_state: false,
    pack_target: None,
    manifest_out: None,
    artifacts_dir: None,
    verify_artifacts: false,
    commit_metadata_path: None,
    snapshot_prerelease_template: None,
    pr_body_out: None,
    output_file: None,
    marker_scope: None,
    access: None,
    ignore_scripts: false,
    from_manifests: false,
  }
}

///|
fn append_csv_unique(values : Array[String], out : Array[String]) -> Unit {
  for raw in values {
    for item in raw.split(",") {
      let trimmed = item.trim().to_owned()
      if trimmed != "" && !out.contains(trimmed) {
        out.push(trimmed)
      }
    }
  }
}

///|
fn build_cli() -> @cac.CAC {
  let cli = @cac.new(name="moonset")
  cli
  .option("--cwd <path>", "Workspace directory", option_type=String)
  .option("--config <path>", "Path to config file", option_type=String)
  .option("--json", "Emit machine-readable JSON output")
  .option("--pretty", "Pretty-print JSON output")
  .option("-q, --quiet", "Suppress non-essential human output")
  .option("--no-color", "Disable ANSI terminal colors", negate=false)
  .option("--format <format>", "Output or tag format", option_type=String)
  .help()
  .version(cli_version(), custom_flags="-V, --version")
  |> ignore

  cli
  .command("", description="Create a changeset interactively (default)")
  .usage("<command> [options]")
  |> ignore

  cli
  .command("init", description="Initialize .changeset configuration")
  .option("--force", "Overwrite existing configuration")
  .option("--yes", "Skip interactive prompts")
  |> ignore

  cli
  .command("add", description="Create a changeset interactively or via flags")
  .option("--package <unit>", "Target package or UnitId", option_type=Strings)
  .option(
    "--type <bump>",
    "Version bump type (major, minor, patch, none)",
    option_type=String,
  )
  .option("--major", "Bump major version")
  .option("--minor", "Bump minor version")
  .option("--patch", "Bump patch version")
  .option(
    "-m, --message, --summary <text>",
    "Changeset summary",
    option_type=String,
  )
  .option("--empty", "Create an empty changeset")
  .option("--id <stem>", "Explicit changeset file stem", option_type=String)
  .option("--open", "Open created changeset in $EDITOR")
  .option("--no-format", "Skip running configured formatter", negate=false)
  .option("--no-commit", "Skip auto-committing changeset", negate=false)
  |> ignore

  cli
  .command("pre [action] [tag]", description="Manage prerelease mode")
  .option("--initial-version", "Deprecated no-op flag kept for compatibility")
  |> ignore

  cli
  .command("status", description="Read-only workspace and changeset analysis")
  .option("--since <ref>", "Compare changes since git ref", option_type=String)
  .option("--verbose", "Show detailed release and file diagnostics")
  .option(
    "--output <format>",
    "Output format (human|json|markdown)",
    option_type=String,
  )
  .option(
    "--head-repo <repo>",
    "PR head repository (owner/name)",
    option_type=String,
  )
  .option("--head-ref <ref>", "PR head branch ref", option_type=String)
  .option(
    "-o, --output-file <path>",
    "Write JSON status output to file",
    option_type=String,
  )
  .option(
    "--marker-scope <scope>",
    "Optional scope suffix for PR bot comment marker",
    option_type=String,
  )
  |> ignore

  cli
  .command(
    "publish-plan",
    description="Emit deterministic analysis JSON and execution DAG",
  )
  .option("--since <ref>", "Compare changes since git ref", option_type=String)
  .option(
    "--output <path>",
    "Output file path or - for stdout",
    option_type=String,
  )
  |> ignore

  cli
  .command(
    "version",
    description="Compute and apply version bumps and changelogs",
  )
  .option("--since <ref>", "Compare changes since git ref", option_type=String)
  .option("--dry-run", "Preview version plan without writing files")
  .option("--empty", "Acknowledge empty release plan")
  .option(
    "--ignore <unit>",
    "Ignore package during version bump",
    option_type=Strings,
  )
  .option("--no-changelog", "Skip CHANGELOG generation", negate=false)
  .option("--no-commit", "Skip auto-committing release changes", negate=false)
  .option("--no-format", "Skip running configured formatter", negate=false)
  .option(
    "--output <format>",
    "Output format (human|json|markdown)",
    option_type=String,
  )
  .option(
    "--commit-metadata <path>",
    "Commit metadata JSON map",
    option_type=String,
  )
  .option("--snapshot [tag]", "Create snapshot prerelease versions")
  .option(
    "--snapshot-prerelease-template <template>",
    "Override snapshot.prereleaseTemplate for this run",
    option_type=String,
  )
  .option(
    "--pr-body-out <path>",
    "Write rendered Release PR Markdown body to file",
    option_type=String,
  )
  .option("--recover", "Recover from interrupted version-journal.json")
  |> ignore

  cli
  .command("tag", description="Create and optionally push Git release tags")
  .alias_name("git-tag")
  .option("--dry-run", "Preview tags without creating Git refs")
  .option("--push", "Push newly created tags to remote")
  .option("--force", "Overwrite existing tags (requires --yes)")
  .option("--yes", "Confirm non-interactive tag operations")
  .option(
    "--from-manifests", "Derive tags directly from workspace manifests when release-state.json is absent",
  )
  .option(
    "--tag-format <template>",
    "Custom tag format template",
    option_type=String,
  )
  |> ignore

  cli
  .command(
    "pack",
    description="Pack release archives or verify artifact manifests",
  )
  .option("--package <unit>", "Target package or UnitId", option_type=Strings)
  .option("--target <name>", "Target platform label", option_type=String)
  .option(
    "--manifest-out <path>",
    "Output pack manifest path",
    option_type=String,
  )
  .option("--verify", "Verify artifact manifests against release state")
  .option("--artifacts-dir <dir>", "Artifacts directory", option_type=String)
  .option("--frozen", "Use frozen/offline package lock mode")
  .option("--dry-run", "Preview pack without writing archives")
  |> ignore

  cli
  .command("publish", description="Publish versioned units in dependency order")
  .option("--dry-run", "Run publish preflight without uploading")
  .option(
    "--only <unit>",
    "Restrict publish to selected UnitIds",
    option_type=Strings,
  )
  .option(
    "--registry <spec>",
    "Registry override (url or scope=url)",
    option_type=Strings,
  )
  .option(
    "--tag <spec>",
    "Distribution tag (tag or scope=tag)",
    option_type=Strings,
  )
  .option(
    "--otp <code>",
    "One-time password for registry auth",
    option_type=String,
  )
  .option(
    "--access <level>",
    "Package registry access override (public|restricted)",
    option_type=String,
  )
  .option("--ignore-scripts", "Pass --ignore-scripts to npm/pnpm/yarn publish")
  .option("--reconcile", "Reconcile durable publish state with registry")
  .option("--artifacts-dir <dir>", "Artifacts directory", option_type=String)
  .option("--retry <count>", "Maximum retry attempts", option_type=String)
  .option("--allow-uncommitted", "Allow publishing with dirty working tree")
  .option("--no-tag", "Skip automatic tag creation after publish", negate=false)
  .option("--yes", "Confirm non-interactive publish")
  |> ignore

  cli
  .command(
    "doctor",
    description="Check toolchain, workspace, and registry health",
  )
  .option("--fix", "Create missing default configuration files")
  .option("--registry", "Run registry preflight checks")
  .option("--output <format>", "Output format (human|json)", option_type=String)
  |> ignore

  cli
  .command(
    "release-notes",
    description="Extract release notes from CHANGELOG.md",
  )
  .option("--version <ver>", "Target release version", option_type=String)
  .option("--file <path>", "Path to CHANGELOG.md", option_type=String)
  .option("--package <unit>", "Target package or UnitId", option_type=Strings)
  .option("--from-state", "Extract notes from .moonset/release-state.json")
  |> ignore

  cli
}

///|
fn map_cac_error(err : @cac.CacError) -> @model.MoonsetError {
  match err {
    UnusedArgs(command="", args~) if !args.is_empty() =>
      @model.Invalid(@model.diagnostic("usage", "Unknown command: " + args[0]))
    UnusedArgs(args~, ..) if !args.is_empty() =>
      @model.Invalid(
        @model.diagnostic("usage", "Unexpected argument: " + args[0]),
      )
    UnknownOption(flag) =>
      @model.Invalid(@model.diagnostic("usage", "Unknown argument: " + flag))
    MissingOptionValue(raw) =>
      @model.Invalid(@model.diagnostic("usage", "Missing value for " + raw))
    _ => @model.Invalid(@model.diagnostic("usage", Show::to_string(err)))
  }
}

///|
fn arguments(raw_args : Array[String]) -> Options raise @model.MoonsetError {
  let cli = build_cli()
  let outcome = cli.parse(argv=raw_args, run=false) catch {
    err => raise map_cac_error(err)
  }
  match outcome {
    Help(text) =>
      return default_options(
        "help",
        help_topic=cli.matched_command_name(),
        help_text=Some(text),
      )
    Version(_) => return default_options("version-info")
    Matched(ctx) => {
      if !ctx.raw_rest.is_empty() {
        usage_error("Unexpected argument: " + ctx.raw_rest[0])
      }
      let command = ctx.command_name
      let pre_action = if command == "pre" { ctx.arg("action") } else { None }
      let pre_tag = if command == "pre" { ctx.arg("tag") } else { None }
      if command == "pre" &&
        pre_tag is Some(extra) &&
        pre_action != Some("enter") {
        usage_error("Unexpected argument: " + extra)
      }
      let cwd = ctx.string("cwd").unwrap_or_else(default_cwd)
      let config = match ctx.string("config") {
        Some(v) => Some(v)
        None => default_config()
      }
      let mut json = ctx.bool("json")
      let mut markdown = false
      let output = ctx.string("output").unwrap_or("")
      let mut format = ctx.string("format").unwrap_or("human")
      let force = ctx.bool("force")
      let no_color = ctx.bool("noColor") ||
        (@env.get_env_var("NO_COLOR") is Some(v) && v != "")
      let packages : Array[String] = []
      append_csv_unique(ctx.strings("package"), packages)
      let ignore_packages : Array[String] = []
      append_csv_unique(ctx.strings("ignore"), ignore_packages)
      let only : Array[String] = []
      for raw in ctx.strings("only") {
        for unit in raw.split(",") {
          let normalized = unit.trim().to_owned()
          if normalized == "" {
            usage_error("--only contains an empty UnitId")
          }
          if !only.contains(normalized) {
            only.push(normalized)
          }
        }
      }
      let bump = if ctx.bool("major") {
        Some("major")
      } else if ctx.bool("minor") {
        Some("minor")
      } else if ctx.bool("patch") {
        Some("patch")
      } else {
        ctx.string("type")
      }
      let retry : Int32 = match ctx.string("retry") {
        None => 0
        Some(value) =>
          match parse_non_negative_int(value) {
            Some(n) => n
            None =>
              raise @model.Invalid(
                @model.diagnostic(
                  "usage", "--retry expects a non-negative integer",
                ),
              )
          }
      }
      let (snapshot_enabled, snapshot) : (Bool, String?) = match
        ctx.get("snapshot") {
        Some(True) => (true, None)
        Some(String(s)) => (true, if s == "" { None } else { Some(s) })
        _ => (false, None)
      }
      let check_registry = command == "doctor" && ctx.bool("registry")
      let registry = if command == "publish" {
        let vals = ctx.strings("registry")
        if vals.is_empty() {
          None
        } else {
          Some(vals.join(","))
        }
      } else {
        None
      }
      let dist_tag = {
        let vals = ctx.strings("tag")
        if vals.is_empty() {
          None
        } else {
          Some(vals.join(","))
        }
      }
      let mut tag_format = ctx.string("tagFormat").unwrap_or("")
      let dry_run = ctx.bool("dryRun")
      if command == "status" {
        if output != "" &&
          output != "human" &&
          output != "json" &&
          output != "markdown" {
          usage_error("status --output expects human, json, or markdown")
        }
        if output == "json" {
          json = true
        } else if output == "markdown" {
          markdown = true
        }
      } else if command == "version" {
        if output != "" &&
          output != "human" &&
          output != "json" &&
          output != "markdown" {
          usage_error("version --output expects human, json, or markdown")
        }
        if output == "json" {
          json = true
        } else if output == "markdown" {
          markdown = true
        }
      } else if command == "doctor" {
        if output != "" && output != "human" && output != "json" {
          usage_error("doctor --output expects human or json")
        }
        if output == "json" {
          json = true
        }
      } else if command == "publish-plan" {
        json = true
      }
      if (command == "tag" || command == "git-tag") &&
        format != "human" &&
        format != "json" &&
        tag_format == "" {
        tag_format = format
        format = "human"
      }
      if format == "markdown" && (command == "status" || command == "version") {
        markdown = true
      } else if format != "human" && format != "json" {
        usage_error("--format expects human or json")
      }
      if format == "json" || output == "json" {
        json = true
      }
      if json && markdown {
        usage_error("Cannot combine --json with --output markdown")
      }
      {
        command,
        help_topic: None,
        help_text: None,
        cwd,
        config,
        since: ctx.string("since"),
        json,
        markdown,
        output,
        pretty: ctx.bool("pretty"),
        quiet: ctx.bool("quiet"),
        verbose: ctx.bool("verbose"),
        force,
        no_color,
        packages,
        ignore_packages,
        bump,
        summary: ctx.string("summary"),
        empty: ctx.bool("empty"),
        id: ctx.string("id"),
        open_editor: ctx.bool("open"),
        head_repo: ctx.string("headRepo"),
        head_ref: ctx.string("headRef"),
        initial_version: ctx.bool("initialVersion"),
        pre_action,
        pre_tag,
        dry_run,
        no_changelog: ctx.bool("noChangelog"),
        no_commit: ctx.bool("noCommit"),
        no_tag: ctx.bool("noTag"),
        no_format: ctx.bool("noFormat"),
        recover: ctx.bool("recover"),
        snapshot_enabled,
        snapshot,
        tag_push: ctx.bool("push"),
        tag_force: force,
        tag_format,
        yes: ctx.bool("yes"),
        only,
        registry,
        dist_tag,
        otp: ctx.string("otp"),
        reconcile: ctx.bool("reconcile"),
        retry,
        allow_uncommitted: ctx.bool("allowUncommitted"),
        frozen: ctx.bool("frozen"),
        check_registry,
        fix: ctx.bool("fix"),
        release_version: if command == "release-notes" {
          ctx.string("version")
        } else {
          None
        },
        file_path: ctx.string("file"),
        from_state: ctx.bool("fromState"),
        pack_target: ctx.string("target"),
        manifest_out: ctx.string("manifestOut"),
        artifacts_dir: ctx.string("artifactsDir"),
        verify_artifacts: ctx.bool("verify"),
        commit_metadata_path: ctx.string("commitMetadata"),
        snapshot_prerelease_template: ctx.string("snapshotPrereleaseTemplate"),
        pr_body_out: ctx.string("prBodyOut"),
        output_file: ctx.string("outputFile"),
        marker_scope: ctx.string("markerScope"),
        access: ctx.string("access"),
        ignore_scripts: ctx.bool("ignoreScripts"),
        from_manifests: ctx.bool("fromManifests"),
      }
    }
  }
}
