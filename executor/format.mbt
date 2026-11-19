///|
/// Result returned by running a configured formatter over written files.
pub(all) struct FormatResult {
  formatter : String
  formatted : Array[String]
  skipped : Bool
}

///|
/// Execute the configured external formatter (prettier/oxfmt/biome/dprint)
/// over supported written files using parameterized argv (never a shell).
pub async fn[H : ExecutionHost] format_files_with(
  host : H,
  root : String,
  config : @model.Config,
  paths : Array[String],
  no_format~ : Bool = false,
) -> FormatResult {
  let formatter = @engine.resolve_formatter(config, no_format~)
  if formatter == "none" || formatter == "builtin" {
    return { formatter, formatted: [], skipped: true, }
  }
  let eligible : Array[String] = []
  for raw_path in paths {
    let rel = raw_path.replace_all(old="\\", new="/").trim().to_owned()
    if rel == "" || eligible.contains(rel) {
      continue
    }
    if !@engine.formatter_supports_path(formatter, rel) {
      continue
    }
    let abs = absolute_path(root, rel)
    if host.exists(abs) {
      eligible.push(rel)
    }
  }
  guard @engine.formatter_command(formatter, eligible) is Some((program, args)) else {
    return { formatter, formatted: [], skipped: true, }
  }
  let output = host.run(program, args, Some(root)) catch {
    error =>
      if host.getenv("ComSpec") is Some(_) {
        host.run(program + ".cmd", args, Some(root))
      } else {
        raise error
      }
  }
  if output.exit_code != 0 {
    let detail = if output.stderr.trim() != "" {
      output.stderr.trim().to_owned()
    } else {
      output.stdout.trim().to_owned()
    }
    raise @model.Io("Formatter '" + formatter + "' failed: " + detail)
  }
  { formatter, formatted: eligible, skipped: false, }
}

///|
pub async fn format_files(
  root : String,
  config : @model.Config,
  paths : Array[String],
  no_format~ : Bool = false,
) -> FormatResult {
  format_files_with(native_host(), root, config, paths, no_format~)
}
