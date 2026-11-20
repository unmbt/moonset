///|
fn cli_version() -> String {
  let document = @manifest.parse(
    @manifest.Kind::Mod,
    embedded_moon_mod,
    path="moon.mod",
  )
  document.version().unwrap_or("0.0.0")
}

///|
async fn stderr(message : String) -> Unit {
  @stdio.stderr.write(@utf8.encode(message + "\n"))
}

///|
fn print_json(value : Json, pretty : Bool) -> Unit {
  println(
    if pretty {
      value.stringify(indent=2)
    } else {
      @model.canonical_json(value)
    },
  )
}

///|
fn resolve_cli_path(cwd : String, rel_or_abs : String) -> String {
  if @path.Path(rel_or_abs).is_absolute() {
    rel_or_abs
  } else if rel_or_abs == "" || rel_or_abs == "." {
    cwd
  } else {
    @path.Path(cwd).join(@path.Path(rel_or_abs)).to_string()
  }
}

///|
fn is_non_interactive() -> Bool {
  if @env.get_env_var("CI") is Some(v) && v != "" && v != "false" && v != "0" {
    return true
  }
  if @env.get_env_var("MOONSET_NON_INTERACTIVE") is Some(v) &&
    v != "" &&
    v != "false" &&
    v != "0" {
    return true
  }
  !tty_is_tty()
}

///|
/// Validate changeset `--id` to prevent path traversal (`../`, `/`, `\`, hidden dotfiles).
fn validate_changeset_id(raw : String) -> String raise @model.MoonsetError {
  let trimmed = raw.trim().to_owned()
  if trimmed == "" ||
    trimmed == "." ||
    trimmed == ".." ||
    trimmed.has_prefix(".") {
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-input",
        "Changeset --id must be a safe filename stem without leading dots or path separators: " +
        raw,
      ),
    )
  }
  for ch in trimmed.to_array() {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_' ||
      ch == '.'
    if !ok {
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-input",
          "Changeset --id contains illegal character '" +
          ch.to_string() +
          "': " +
          raw,
        ),
      )
    }
  }
  trimmed
}
