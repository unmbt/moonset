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
/// Pure color-enable policy following https://no-color.org/ (`NO_COLOR` disables
/// color only when present and non-empty) and `TERM=dumb`.
fn should_enable_color(
  is_tty~ : Bool,
  no_color_flag~ : Bool,
  no_color_env~ : String?,
  term_env~ : String?,
) -> Bool {
  if !is_tty || no_color_flag {
    return false
  }
  if no_color_env is Some(v) && v != "" {
    return false
  }
  if term_env is Some(t) && t.trim().to_lower() == "dumb" {
    return false
  }
  true
}

///|
fn terminal_color_enabled(no_color : Bool, stderr_stream : Bool) -> Bool {
  should_enable_color(
    is_tty=tty_enable_color(stderr_stream),
    no_color_flag=no_color,
    no_color_env=@env.get_env_var("NO_COLOR"),
    term_env=@env.get_env_var("TERM"),
  )
}

///|
fn style_text(text : String, sgr : String, enabled : Bool) -> String {
  if enabled && text != "" {
    "\u{001b}[\{sgr}m" + text + ANSI_RESET
  } else {
    text
  }
}

///|
fn style_title(text : String, enabled : Bool) -> String {
  style_text(text, "1;36", enabled)
}

///|
fn style_success(text : String, enabled : Bool) -> String {
  style_text(text, "32;1", enabled)
}

///|
fn style_error(text : String, enabled : Bool) -> String {
  style_text(text, "31;1", enabled)
}

///|
fn style_warn(text : String, enabled : Bool) -> String {
  style_text(text, "33;1", enabled)
}

///|
fn style_warn_soft(text : String, enabled : Bool) -> String {
  style_text(text, "33", enabled)
}

///|
fn style_pkg(text : String, enabled : Bool) -> String {
  style_text(text, "1;34", enabled)
}

///|
fn style_dim(text : String, enabled : Bool) -> String {
  style_text(text, "2", enabled)
}

///|
fn style_accent(text : String, enabled : Bool) -> String {
  style_text(text, "36", enabled)
}

///|
fn style_kind(text : String, enabled : Bool) -> String {
  style_text(text, "35", enabled)
}

///|
fn style_bump(bump : String, enabled : Bool) -> String {
  let tone = match bump {
    "major" => "31;1"
    "minor" => "32;1"
    "patch" => "34;1"
    _ => "0"
  }
  if tone == "0" {
    bump
  } else {
    style_text(bump, tone, enabled)
  }
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
