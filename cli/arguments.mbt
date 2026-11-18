///|
priv struct Options {
  command : String
  cwd : String
  config : String?
  since : String?
  json : Bool
  output : String
  pretty : Bool
  quiet : Bool
  verbose : Bool
  force : Bool
  packages : Array[String]
  bump : String?
  summary : String?
  empty : Bool
  id : String?
  initial_version : Bool
  pre_action : String?
  pre_tag : String?
  dry_run : Bool
  no_changelog : Bool
  no_commit : Bool
  no_tag : Bool
  no_format : Bool
  recover : Bool
  snapshot : String?
  tag_push : Bool
  tag_force : Bool
  tag_format : String
  yes : Bool
  only : Array[String]
  registry : String?
  dist_tag : String?
  retry : Int32
  allow_uncommitted : Bool
  frozen : Bool
  check_registry : Bool
  fix : Bool
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
    if acc > 214748364 {
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
    "pack", "publish", "doctor",
  ].contains(token)
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
    | "--type"
    | "--summary"
    | "--id"
    | "--snapshot"
    | "--only"
    | "--tag-format"
    | "--tag"
    | "--retry" => true
    _ => false
  }
}

///|
fn detect_subcommand(args : Array[String]) -> String {
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    if is_always_value_flag(arg) {
      if i < args.length() {
        i += 1
      }
      continue
    }
    if arg == "--registry" {
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
fn is_value_flag(arg : String, has_doctor : Bool) -> Bool {
  if is_always_value_flag(arg) {
    return true
  }
  arg == "--registry" && !has_doctor
}

///|
fn wants_json_output(args : Array[String]) -> Bool {
  let subcommand = detect_subcommand(args)
  let has_doctor = subcommand == "doctor"
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
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
    if is_value_flag(arg, has_doctor) && i < args.length() {
      i += 1
    }
  }
  false
}

///|
fn arguments(args : Array[String]) -> Options raise @model.MoonsetError {
  let detected_subcommand = detect_subcommand(args)
  let has_doctor = detected_subcommand == "doctor"
  let mut command = ""
  let mut cwd = @env.current_dir().unwrap_or(".")
  let mut config = None
  let mut since = None
  let mut json = false
  let mut output = ""
  let mut pretty = false
  let mut quiet = false
  let mut verbose = false
  let mut force = false
  let mut format = "human"
  let packages : Array[String] = []
  let mut bump : String? = None
  let mut summary : String? = None
  let mut empty = false
  let mut id : String? = None
  let mut initial_version = false
  let mut pre_action : String? = None
  let mut pre_tag : String? = None
  let mut dry_run = false
  let mut no_changelog = false
  let mut no_commit = false
  let mut no_tag = false
  let mut no_format = false
  let mut recover = false
  let mut snapshot : String? = None
  let mut tag_push = false
  let mut tag_format = ""
  let mut yes = false
  let only : Array[String] = []
  let mut registry : String? = None
  let mut dist_tag : String? = None
  let mut retry : Int32 = 0
  let mut allow_uncommitted = false
  let mut frozen = false
  let mut check_registry = false
  let mut fix = false
  let mut i = 0
  while i < args.length() {
    let arg = args[i]
    i += 1
    match arg {
      "--help" | "-h" => command = "help"
      "--version" => command = "version-info"
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
      "--registry" =>
        if has_doctor {
          check_registry = true
        } else {
          if i >= args.length() {
            usage_error("Missing value for " + arg)
          }
          registry = Some(args[i])
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
      "--no-color" => ()
      "--cwd"
      | "--config"
      | "--since"
      | "--output"
      | "--format"
      | "--package"
      | "--type"
      | "--summary"
      | "--id"
      | "--snapshot"
      | "--tag-format"
      | "--tag"
      | "--retry" => {
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
          "--type" => bump = Some(value)
          "--summary" => summary = Some(value)
          "--snapshot" => snapshot = Some(value)
          "--tag-format" => tag_format = value
          "--tag" => dist_tag = Some(value)
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
  if command == "status" || command == "doctor" {
    if output != "" && output != "human" && output != "json" {
      usage_error(command + " --output expects human or json")
    }
    if output == "json" {
      json = true
    }
  } else if command == "publish-plan" {
    json = true
  } else if command != "" &&
    ![
      "help", "version-info", "init", "add", "pre", "version", "tag", "git-tag",
      "pack", "publish",
    ].contains(command) {
    usage_error("Unknown command: " + command)
  }
  if (command == "tag" || command == "git-tag") &&
    format != "human" &&
    format != "json" &&
    tag_format == "" {
    tag_format = format
    format = "human"
  }
  if format != "human" && format != "json" {
    usage_error("--format expects human or json")
  }
  if format == "json" {
    json = true
  }
  if output == "json" {
    json = true
  }
  {
    command,
    cwd,
    config,
    since,
    json,
    output,
    pretty,
    quiet,
    verbose,
    force,
    packages,
    bump,
    summary,
    empty,
    id,
    initial_version,
    pre_action,
    pre_tag,
    dry_run,
    no_changelog,
    no_commit,
    no_tag,
    no_format,
    recover,
    snapshot,
    tag_push,
    tag_force: force,
    tag_format,
    yes,
    only,
    registry,
    dist_tag,
    retry,
    allow_uncommitted,
    frozen,
    check_registry,
    fix,
  }
}
