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
      "--no-color" => ()
      "--cwd" | "--config" | "--since" | "--output" => {
        if i >= args.length() {
          usage_error("Missing value for " + arg)
        }
        let value = args[i]
        i += 1
        match arg {
          "--cwd" => cwd = value
          "--config" => config = Some(value)
          "--since" => since = Some(value)
          _ => output = value
        }
      }
      _ => {
        if arg.has_prefix("-") ||
          (command != "" && command != "help" && command != "version-info") {
          usage_error("Unknown argument: " + arg)
        }
        if command == "" {
          command = arg
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
  } else if command != "help" && command != "version-info" {
    usage_error("Phase 1 implements status and publish-plan; use --help")
  }
  { command, cwd, config, since, json, output, pretty, quiet, verbose, }
}
