///|
priv struct Options {
  command : String
  help_topic : String?
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
    | "--commit-metadata" => true
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
fn arguments(raw_args : Array[String]) -> Options raise @model.MoonsetError {
  let args = normalize_cli_args(raw_args)
  let detected_subcommand = detect_subcommand(args)
  let has_doctor = detected_subcommand == "doctor"
  let mut command = ""
  let mut help_requested = false
  let mut help_topic : String? = None
  let mut cwd = match @env.get_env_var("MOONSET_CWD") {
    Some(v) if v.trim() != "" => v.trim().to_owned()
    _ => @env.current_dir().unwrap_or(".")
  }
  let mut config : String? = match @env.get_env_var("MOONSET_CONFIG") {
    Some(v) if v.trim() != "" => Some(v.trim().to_owned())
    _ => None
  }
  let mut since = None
  let mut json = false
  let mut markdown = false
  let mut output = ""
  let mut pretty = false
  let mut quiet = false
  let mut verbose = false
  let mut force = false
  let mut no_color = @env.get_env_var("NO_COLOR") is Some(v) && v != ""
  let mut format = "human"
  let packages : Array[String] = []
  let ignore_packages : Array[String] = []
  let mut bump : String? = None
  let mut summary : String? = None
  let mut empty = false
  let mut id : String? = None
  let mut open_editor = false
  let mut head_repo : String? = None
  let mut head_ref : String? = None
  let mut initial_version = false
  let mut pre_action : String? = None
  let mut pre_tag : String? = None
  let mut dry_run = false
  let mut no_changelog = false
  let mut no_commit = false
  let mut no_tag = false
  let mut no_format = false
  let mut recover = false
  let mut snapshot_enabled = false
  let mut snapshot : String? = None
  let mut tag_push = false
  let mut tag_format = ""
  let mut yes = false
  let only : Array[String] = []
  let mut registry : String? = None
  let mut dist_tag : String? = None
  let mut otp : String? = None
  let mut reconcile = false
  let mut retry : Int32 = 0
  let mut allow_uncommitted = false
  let mut frozen = false
  let mut check_registry = false
  let mut fix = false
  let mut release_version : String? = None
  let mut file_path : String? = None
  let mut from_state = false
  let mut pack_target : String? = None
  let mut manifest_out : String? = None
  let mut artifacts_dir : String? = None
  let mut verify_artifacts = false
  let mut commit_metadata_path : String? = None
  let mut after_double_dash = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if !after_double_dash && arg == "--" {
      after_double_dash = true
      continue
    }
    if after_double_dash {
      if command == "" {
        command = arg
      } else if command == "pre" && pre_action is None {
        pre_action = Some(arg)
      } else if command == "pre" &&
        pre_action == Some("enter") &&
        pre_tag is None {
        pre_tag = Some(arg)
      } else {
        usage_error("Unexpected argument: " + arg)
      }
      continue
    }
    match arg {
      "--help" | "-h" => {
        help_requested = true
        if command != "" && is_known_subcommand(command) {
          help_topic = Some(command)
        } else if i < args.length() && is_known_subcommand(args[i]) {
          help_topic = Some(args[i])
          i += 1
        }
      }
      "--version" =>
        if detected_subcommand == "release-notes" {
          if i >= args.length() {
            usage_error("Missing value for " + arg)
          }
          release_version = Some(args[i])
          i += 1
        } else {
          command = "version-info"
        }
      "-V" => command = "version-info"
      "--json" => json = true
      "--pretty" => pretty = true
      "--quiet" | "-q" => quiet = true
      "--verbose" => verbose = true
      "--force" => force = true
      "--dry-run" => dry_run = true
      "--no-changelog" => no_changelog = true
      "--no-commit" => no_commit = true
      "--no-tag" => no_tag = true
      "--recover" => recover = true
      "--push" => tag_push = true
      "--yes" => yes = true
      "--allow-uncommitted" => allow_uncommitted = true
      "--frozen" => frozen = true
      "--fix" => fix = true
      "--reconcile" => reconcile = true
      "--open" => open_editor = true
      "--major" => bump = Some("major")
      "--minor" => bump = Some("minor")
      "--patch" => bump = Some("patch")
      "--snapshot" => {
        snapshot_enabled = true
        if i < args.length() &&
          !args[i].has_prefix("-") &&
          !is_known_subcommand(args[i]) {
          let tag_val = args[i]
          i += 1
          if tag_val != "" {
            snapshot = Some(tag_val)
          }
        }
      }
      "--registry" =>
        if has_doctor {
          check_registry = true
        } else {
          if i >= args.length() {
            usage_error("Missing value for " + arg)
          }
          let val = args[i]
          registry = match registry {
            Some(prev) => Some(prev + "," + val)
            None => Some(val)
          }
          i += 1
        }
      "--only" => {
        if i >= args.length() {
          usage_error("Missing value for " + arg)
        }
        let value = args[i]
        i += 1
        for unit in value.split(",") {
          let normalized = unit.trim().to_owned()
          if normalized == "" {
            usage_error("--only contains an empty UnitId")
          }
          if !only.contains(normalized) {
            only.push(normalized)
          }
        }
      }
      "--empty" => empty = true
      "--no-format" => no_format = true
      "--initial-version" => initial_version = true
      "--from-state" => from_state = true
      "--verify" => verify_artifacts = true
      "--no-color" => no_color = true
      "--cwd"
      | "--config"
      | "--since"
      | "--output"
      | "--format"
      | "--package"
      | "--ignore"
      | "--type"
      | "--summary"
      | "--id"
      | "--head-repo"
      | "--head-ref"
      | "--tag-format"
      | "--tag"
      | "--otp"
      | "--retry"
      | "--file"
      | "--target"
      | "--manifest-out"
      | "--artifacts-dir"
      | "--commit-metadata" => {
        if i >= args.length() {
          usage_error("Missing value for " + arg)
        }
        let value = args[i]
        i += 1
        match arg {
          "--cwd" => cwd = value
          "--config" => config = Some(value)
          "--since" => since = Some(value)
          "--output" => output = value
          "--format" => format = value
          "--package" =>
            for item in value.split(",") {
              let trimmed = item.trim().to_owned()
              if trimmed != "" && !packages.contains(trimmed) {
                packages.push(trimmed)
              }
            }
          "--ignore" =>
            for item in value.split(",") {
              let trimmed = item.trim().to_owned()
              if trimmed != "" && !ignore_packages.contains(trimmed) {
                ignore_packages.push(trimmed)
              }
            }
          "--type" => bump = Some(value)
          "--summary" => summary = Some(value)
          "--head-repo" => head_repo = Some(value)
          "--head-ref" => head_ref = Some(value)
          "--tag-format" => tag_format = value
          "--tag" =>
            dist_tag = match dist_tag {
              Some(prev) => Some(prev + "," + value)
              None => Some(value)
            }
          "--otp" => otp = Some(value)
          "--file" => file_path = Some(value)
          "--target" => pack_target = Some(value)
          "--manifest-out" => manifest_out = Some(value)
          "--artifacts-dir" => artifacts_dir = Some(value)
          "--commit-metadata" => commit_metadata_path = Some(value)
          "--retry" =>
            match parse_non_negative_int(value) {
              Some(n) => retry = n
              _ => usage_error("--retry expects a non-negative integer")
            }
          _ => id = Some(value)
        }
      }
      _ => {
        if arg.has_prefix("-") {
          usage_error("Unknown argument: " + arg)
        }
        if command == "" {
          command = arg
          if help_requested && is_known_subcommand(arg) && help_topic is None {
            help_topic = Some(arg)
          }
        } else if command == "pre" && pre_action is None {
          pre_action = Some(arg)
        } else if command == "pre" &&
          pre_action == Some("enter") &&
          pre_tag is None {
          pre_tag = Some(arg)
        } else {
          usage_error("Unexpected argument: " + arg)
        }
      }
    }
  }
  if help_requested {
    if help_topic is None && is_known_subcommand(command) {
      help_topic = Some(command)
    }
    command = "help"
  }
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
  } else if command != "" &&
    ![
      "help", "version-info", "init", "add", "pre", "version", "tag", "git-tag",
      "pack", "publish", "release-notes",
    ].contains(command) {
    usage_error("Unknown command: " + command)
  }
  if dry_run &&
    command != "" &&
    command != "help" &&
    !["version", "pack", "publish", "tag", "git-tag"].contains(command) {
    usage_error("--dry-run is not supported for command: " + command)
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
  if format == "json" {
    json = true
  }
  if output == "json" {
    json = true
  }
  if json && markdown {
    usage_error("Cannot combine --json with --output markdown")
  }
  {
    command,
    help_topic,
    cwd,
    config,
    since,
    json,
    markdown,
    output,
    pretty,
    quiet,
    verbose,
    force,
    no_color,
    packages,
    ignore_packages,
    bump,
    summary,
    empty,
    id,
    open_editor,
    head_repo,
    head_ref,
    initial_version,
    pre_action,
    pre_tag,
    dry_run,
    no_changelog,
    no_commit,
    no_tag,
    no_format,
    recover,
    snapshot_enabled,
    snapshot,
    tag_push,
    tag_force: force,
    tag_format,
    yes,
    only,
    registry,
    dist_tag,
    otp,
    reconcile,
    retry,
    allow_uncommitted,
    frozen,
    check_registry,
    fix,
    release_version,
    file_path,
    from_state,
    pack_target,
    manifest_out,
    artifacts_dir,
    verify_artifacts,
    commit_metadata_path,
  }
}
