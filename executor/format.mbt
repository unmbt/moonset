///|
/// Result returned by running a configured formatter over written files.
pub(all) struct FormatResult {
  formatter : String
  formatted : Array[String]
  skipped : Bool
}

///|
async fn[H : ExecutionHost] resolve_formatter_program(
  host : H,
  root : String,
  program : String,
) -> String {
  let local_rel = "node_modules/.bin/" + program
  if is_windows_host(host) {
    let local_cmd = absolute_path(root, local_rel + ".cmd")
    if host.exists(local_cmd) {
      return local_cmd
    }
  }
  let local_bin = absolute_path(root, local_rel)
  if host.exists(local_bin) {
    return local_bin
  }
  program
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
  let resolved_program = resolve_formatter_program(host, root, program)
  let output = host.run(resolved_program, args, Some(root)) catch {
    error =>
      if is_windows_host(host) &&
        !resolved_program.to_lower().has_suffix(".cmd") {
        host.run(resolved_program + ".cmd", args, Some(root))
      } else {
        raise error
      }
  }
  if output.exit_code != 0 {
    raise @model.Io(
      "Formatter '" + formatter + "' failed: " + process_failure_detail(output),
    )
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
