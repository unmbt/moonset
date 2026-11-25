///|
fn render_help(topic : String?) -> String {
  let cli = build_cli()
  match topic {
    None => cli.render_help()
    Some(t) =>
      match
        (cli.parse(argv=[t, "--help"], run=false) catch {
          _ => Help(cli.render_help())
        }) {
        Help(text) => text
        _ => cli.render_help()
      }
  }
}

///|
async fn execute(options : Options) -> Int32 {
  if options.command == "" {
    if !options.json && !is_non_interactive() {
      return add_command(options)
    }
    usage_error("Subcommand is required in non-interactive or CI mode")
  }
  match options.command {
    "help" => {
      println(
        options.help_text.unwrap_or_else(() => render_help(options.help_topic)),
      )
      0
    }
    "version-info" => {
      println("moonset " + cli_version())
      0
    }
    "init" => init_command(options)
    "add" => add_command(options)
    "pre" => pre_command(options)
    "version" => version_command(options)
    "tag" | "git-tag" => tag_command(options)
    "pack" => pack_command(options)
    "publish" => publish_command(options)
    "doctor" => doctor_command(options)
    "release-notes" => release_notes_command(options)
    _ => status_or_plan_command(options)
  }
}

///|
fn format_diagnostic_stderr(
  diagnostic : @model.Diagnostic,
  color~ : Bool = false,
) -> String {
  let code = style_error(diagnostic.code, color)
  let message = diagnostic.message
  if diagnostic.path != "" {
    style_pkg(diagnostic.path, color) +
    ":\{diagnostic.line}:\{diagnostic.column}: " +
    code +
    ": " +
    message
  } else {
    code + ": " + message
  }
}

///|
/// Run CLI arguments without the executable name. Errors never escape this boundary.
pub async fn run(args : Array[String]) -> Int32 {
  let wants_json = wants_json_output(args)
  let wants_markdown = wants_markdown_output(args)
  let command_name = detect_subcommand(args)
  execute(arguments(args)) catch {
    error => {
      let (code, diagnostic) = match error {
        @model.Invalid(diagnostic) => {
          let policy_codes = [
            "missing-changeset", "confirmation-required", "dirty-working-tree", "incomplete-selection",
          ]
          let exit_code : Int32 = if policy_codes.contains(diagnostic.code) {
            1
          } else {
            2
          }
          (exit_code, diagnostic)
        }
        @model.Io(message) => (3, @model.diagnostic("external-error", message))
        _ => (3, @model.diagnostic("external-error", error.to_string()))
      }
      if wants_markdown {
        @stdio.stdout.write(@utf8.encode(@engine.error_markdown(diagnostic)))
      } else if wants_json {
        let payload : Json = if command_name == "status" {
          {
            "schemaVersion": 1,
            "ok": false,
            "workspace": Json::null(),
            "changesets": [],
            "releases": [],
            "warnings": [],
            "errors": [diagnostic.to_json()],
            "hasChanges": false,
            "hasRelease": false,
          }
        } else {
          {
            "schemaVersion": 1,
            "ok": false,
            "command": command_name,
            "errors": [diagnostic.to_json()],
          }
        }
        println(@model.canonical_json(payload))
      }
      let color_errors = !wants_json &&
        !wants_markdown &&
        terminal_color_enabled(has_no_color_flag(args), true)
      stderr(format_diagnostic_stderr(diagnostic, color=color_errors)) catch {
        _ => ()
      }
      code
    }
  }
}
