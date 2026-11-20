///|
fn render_help(topic : String?) -> String {
  match topic {
    Some("init") =>
      "moonset init [--force] [--config path] [--yes] [--json]\n  Initialize .changeset/config.json, .changeset/README.md, and .moonset/.gitignore."
    Some("add") =>
      "moonset add [--package unit[,unit]] [--type major|minor|patch|none | --major | --minor | --patch] [-m|--message|--summary text] [--empty] [--id stem] [--open] [--no-format] [--no-commit] [--json]\n  Create a changeset interactively (TUI) or non-interactively via flags."
    Some("pre") =>
      "moonset pre enter <tag> | exit | status [--json]\n  Manage Changesets v3 minimal prerelease mode (.changeset/pre.json + .changeset/pre/)."
    Some("status") =>
      "moonset status [--since ref] [--verbose] [--output human|json|markdown] [--head-repo owner/name] [--head-ref branch]\n  Read-only workspace & changeset analysis."
    Some("publish-plan") =>
      "moonset publish-plan [--since ref] [--output path|-] [--pretty]\n  Emit deterministic analysis JSON and execution DAG."
    Some("version") =>
      "moonset version [--dry-run] [--empty] [--ignore unit] [--no-changelog] [--no-commit] [--no-format] [--output human|json|markdown] [--commit-metadata path] [--snapshot [tag]] [--recover]\n  Compute and atomically apply version bumps, changelogs, and lockfiles."
    Some("pack") =>
      "moonset pack [--package unit] [--target name] [--manifest-out path] [--verify] [--artifacts-dir dir] [--frozen] [--dry-run] [--json]\n  Pack release archives or verify multi-platform artifact manifests."
    Some("publish") =>
      "moonset publish [--dry-run] [--only unit] [--registry name|scope=name] [--tag dist-tag|scope=tag] [--otp code] [--reconcile] [--artifacts-dir dir] [--retry n] [--allow-uncommitted] [--no-tag] [--yes] [--json]\n  Publish versioned units in dependency order with durable state recovery."
    Some("tag" | "git-tag") =>
      "moonset tag [--dry-run] [--push] [--force --yes] [--tag-format template] [--json]\n  Create (annotated) and optionally push Git release tags from .moonset/release-state.json."
    Some("release-notes") =>
      "moonset release-notes [--version ver] [--file path] [--package unit] [--from-state] [--json]\n  Extract release notes from CHANGELOG.md."
    Some("doctor") =>
      "moonset doctor [--fix] [--registry] [--output human|json]\n  Check toolchain, workspace config, recovery journal, worktree, and registry preflight."
    _ =>
      "moonset \{cli_version()}\n  init [--force] [--config path]\n  add [--package unit[,unit]] [--type major|minor|patch|none|--major|--minor|--patch] [--summary text] [--empty] [--open] [--no-format]\n  pre enter <tag> | pre exit | pre status\n  status [--since ref] [--verbose] [--output human|json|markdown] [--head-repo owner/name] [--head-ref branch]\n  publish-plan [--since ref] [--output path|-] [--pretty]\n  version [--dry-run] [--empty] [--ignore unit] [--no-changelog] [--no-commit] [--no-format] [--output human|json|markdown] [--commit-metadata path] [--snapshot [tag]] [--recover]\n  pack [--package unit] [--target name] [--manifest-out path] [--verify] [--artifacts-dir dir] [--frozen] [--dry-run] [--json]\n  publish [--dry-run] [--only unit] [--registry name|scope=name] [--tag dist-tag|scope=tag] [--otp code] [--reconcile] [--artifacts-dir dir] [--retry n] [--allow-uncommitted] [--no-tag] [--yes] [--json]\n  tag|git-tag [--dry-run] [--push] [--force --yes] [--tag-format template]\n  release-notes [--version ver] [--file path] [--package unit] [--from-state] [--json]\n  doctor [--fix] [--registry] [--output human|json]\n  Global: --cwd path --config path --json --pretty --quiet --no-color -h/--help [cmd] -V/--version"
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
      println(render_help(options.help_topic))
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
