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
  package_name : String?
  bump : String?
  summary : String?
  empty : Bool
  id : String?
  initial_version : Bool
  pre_action : String?
  dry_run : Bool
  no_changelog : Bool
  no_commit : Bool
  recover : Bool
  snapshot : String?
  tag_push : Bool
  tag_force : Bool
  tag_format : String
  yes : Bool
}

///|
fn usage_error(message : String) -> Unit raise @model.MoonsetError {
  raise @model.Invalid(@model.diagnostic("usage", message))
}

///|
fn arguments(args : Array[String]) -> Options raise @model.MoonsetError {
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
  let mut package_ : String? = None
  let mut bump : String? = None
  let mut summary : String? = None
  let mut empty = false
  let mut id : String? = None
  let mut initial_version = false
  let mut pre_action : String? = None
  let mut dry_run = false
  let mut no_changelog = false
  let mut no_commit = false
  let mut recover = false
  let mut snapshot : String? = None
  let mut tag_push = false
  let mut tag_force = false
  let mut tag_format = ""
  let mut yes = false
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
      "--recover" => recover = true
      "--push" => tag_push = true
      "--yes" => yes = true
      "--empty" => empty = true
      "--no-format" => ()
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
      | "--snapshot" => {
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
          "--package" => package_ = Some(value)
          "--type" => bump = Some(value)
          "--summary" => summary = Some(value)
          "--snapshot" => snapshot = Some(value)
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
        } else {
          usage_error("Unexpected argument: " + arg)
        }
      }
    }
  }
  if command == "status" {
    if output != "" && output != "human" && output != "json" {
      usage_error("status --output expects human or json")
    }
    if output == "json" {
      json = true
    }
  } else if command == "publish-plan" {
    json = true
  } else if ![
      "help", "version-info", "init", "add", "pre", "version", "tag", "git-tag",
    ].contains(command) {
    usage_error("Unknown command: " + command)
  }
  if command == "tag" || command == "git-tag" {
    tag_format = format
    format = "human"
  }
  if format != "human" && format != "json" {
    usage_error("--format expects human or json")
  }
  if format == "json" {
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
    package_name: package_,
    bump,
    summary,
    empty,
    id,
    initial_version,
    pre_action,
    dry_run,
    no_changelog,
    no_commit,
    recover,
    snapshot,
    tag_push,
    tag_force: force,
    tag_format,
    yes,
  }
}
