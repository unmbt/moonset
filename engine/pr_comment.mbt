///|
let bot_marker : String = "<!-- moonset-bot:changeset-check -->"

///|
pub(all) struct CommentOptions {
  head_repo : String?
  head_ref : String?
  changeset_directory : String
  max_length : Int32
}

///|
pub fn CommentOptions::default() -> CommentOptions {
  {
    head_repo: None,
    head_ref: None,
    changeset_directory: ".changeset",
    max_length: 60000,
  }
}

///|
fn escape_html(text : String) -> String {
  text
  .replace_all(old="&", new="&amp;")
  .replace_all(old="<", new="&lt;")
  .replace_all(old=">", new="&gt;")
}

///|
fn escape_mentions(text : String) -> String {
  text.replace_all(old="@", new="@\u{200B}")
}

///|
fn sanitize_user_text(text : String) -> String {
  escape_mentions(escape_html(text))
}

///|
/// Sanitize text placed inside backticks / shell code blocks: escape backticks
/// and newlines without injecting zero-width spaces into scoped `@org/pkg` names.
fn sanitize_code_text(text : String) -> String {
  text
  .replace_all(old="\r", new="")
  .replace_all(old="\n", new=" ")
  .replace_all(old="`", new="'")
  .replace_all(old="\"", new="'")
}

///|
fn truncate_chars(text : String, max_chars : Int32) -> String {
  let chars = text.to_array()
  if chars.length() <= max_chars {
    return text
  }
  if max_chars <= 0 {
    return ""
  }
  String::from_array(chars[:max_chars].to_owned())
}

///|
fn first_summary_line(summary : String) -> String {
  for raw in summary.replace_all(old="\r\n", new="\n").split("\n") {
    let trimmed = raw.trim().to_owned()
    if trimmed != "" {
      let truncated = if trimmed.to_array().length() > 137 {
        truncate_chars(trimmed, 137) + "..."
      } else {
        trimmed
      }
      return sanitize_user_text(truncated)
        .replace_all(old="|", new="\\|")
        .replace_all(old="`", new="\\`")
    }
  }
  "(no summary)"
}

///|
fn is_unreserved_byte(b : Int32) -> Bool {
  (b >= 0x41 && b <= 0x5A) ||
  (b >= 0x61 && b <= 0x7A) ||
  (b >= 0x30 && b <= 0x39) ||
  b == 0x2D ||
  b == 0x5F ||
  b == 0x2E ||
  b == 0x7E
}

///|
fn hex_digit(n : Int32) -> Char {
  let chars = [
    '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'A', 'B', 'C', 'D', 'E', 'F',
  ]
  chars[n & 0xF]
}

///|
fn percent_encode(text : String) -> String {
  let bytes = @utf8.encode(text)
  let out : Array[Char] = []
  for b in bytes {
    let code = b.to_int() & 0xFF
    if is_unreserved_byte(code) {
      out.push(Int32::unsafe_to_char(code))
    } else {
      out.push('%')
      out.push(hex_digit(code >> 4))
      out.push(hex_digit(code & 0xF))
    }
  }
  String::from_array(out)
}

///|
fn is_valid_repo_slug(repo : String) -> Bool {
  let parts : Array[String] = repo.split("/").map(x => x.to_owned()).collect()
  if parts.length() != 2 {
    return false
  }
  for part in parts {
    if part == "" || part == "." || part == ".." {
      return false
    }
    for ch in part.to_array() {
      let ok = (ch >= 'A' && ch <= 'Z') ||
        (ch >= 'a' && ch <= 'z') ||
        (ch >= '0' && ch <= '9') ||
        ch == '-' ||
        ch == '_' ||
        ch == '.'
      if !ok {
        return false
      }
    }
  }
  true
}

///|
fn sanitize_slug_token(text : String) -> String {
  let out : Array[Char] = []
  let mut last_dash = false
  for ch in text.to_lower().to_array() {
    let ok = (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9')
    if ok {
      out.push(ch)
      last_dash = false
    } else if !last_dash && !out.is_empty() {
      out.push('-')
      last_dash = true
    }
    if out.length() >= 24 {
      break
    }
  }
  while !out.is_empty() && out[out.length() - 1] == '-' {
    ignore(out.pop())
  }
  if out.is_empty() {
    "pr"
  } else {
    String::from_array(out)
  }
}

///|
fn deterministic_changeset_slug(
  head_ref : String,
  changed : Array[String],
) -> String {
  let digest = @model.fingerprint({
    "headRef": head_ref,
    "changed": Json::array(changed.map(Json::string)),
  })
  // Strip algorithm prefix (`fnv1a64:`) before slicing so the slug carries actual
  // hex hash entropy and never contains `:` (illegal in Windows filenames).
  let hex = match digest.find(":") {
    Some(idx) => digest[idx + 1:].to_owned()
    None => digest
  }
  let short_hash = if hex.length() > 8 { hex[:8].to_owned() } else { hex }
  sanitize_slug_token(head_ref) + "-" + short_hash
}

///|
fn encode_ref_path(head_ref : String) -> String {
  head_ref
  .split("/")
  .map(seg => percent_encode(seg.to_owned()))
  .collect()
  .join("/")
}

///|
fn truncate_markdown(body : String, max_length : Int32) -> String {
  let limit = if max_length < 256 { 256 } else { max_length }
  let body_chars = body.to_array()
  if body_chars.length() <= limit {
    return body
  }
  let suffix = "\n\n> ⚠️ Output truncated due to comment length limit; see the workflow run logs for full details.\n"
  let suffix_len = suffix.to_array().length()
  let budget = limit - suffix_len
  let cut_raw = if budget > 0 { truncate_chars(body, budget) } else { "" }
  let cut = match cut_raw.rev_find("\n") {
    Some(idx) if idx > 0 => cut_raw[:idx].to_owned()
    _ => cut_raw
  }
  cut + suffix
}

///|
fn touched_units(
  snapshot : @model.WorkspaceSnapshot,
  changed : Array[String],
) -> Array[@model.ReleaseUnit] {
  let result : Array[@model.ReleaseUnit] = []
  let seen : Map[String, Bool] = Map([])
  for path in changed {
    for unit in owning_units_for_path(path, snapshot.units) {
      if is_unit_ignored(snapshot.config, unit.id) || seen.contains(unit.id) {
        continue
      }
      seen[unit.id] = true
      result.push(unit)
    }
  }
  if result.is_empty() {
    for unit in snapshot.units {
      if !is_unit_ignored(snapshot.config, unit.id) {
        result.push(unit)
        break
      }
    }
  }
  result
}

///|
pub fn comment_state(
  snapshot : @model.WorkspaceSnapshot,
  plan : @model.ReleasePlan,
  changeset_directory~ : String = ".changeset",
) -> String {
  let changed = relevant_changes(snapshot, changeset_directory~)
  let missing = snapshot.git_head is Some(_) &&
    !changed.is_empty() &&
    plan.changesets.is_empty()
  if !plan.releases.is_empty() {
    "release"
  } else if missing {
    "missing"
  } else if !plan.changesets.is_empty() {
    "empty"
  } else {
    "none"
  }
}

///|
fn append_coexistence_section(
  lines : Array[String],
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory : String,
) -> Unit {
  guard coexistence_json(snapshot, changeset_directory~) is Some(coex) else {
    return
  }
  if coex is { "advice": Array(advice), .. } && !advice.is_empty() {
    lines.push("")
    lines.push("### Cross-partition notices")
    lines.push("")
    for item in advice {
      if item is { "message": String(msg), .. } {
        lines.push("- " + sanitize_user_text(msg))
      }
    }
  }
}

///|
pub fn status_markdown(
  snapshot : @model.WorkspaceSnapshot,
  plan : @model.ReleasePlan,
  options~ : CommentOptions = CommentOptions::default(),
) -> String {
  let dir = options.changeset_directory
  let changed = relevant_changes(snapshot, changeset_directory=dir)
  let state = comment_state(snapshot, plan, changeset_directory=dir)
  let lines : Array[String] = [bot_marker]
  match state {
    "release" => {
      lines.push("### ✅ Changeset detected — release preview")
      lines.push("")
      lines.push(
        "The following packages will be updated when this changeset is released:",
      )
      lines.push("")
      lines.push("| Package | Version | Bump |")
      lines.push("|---|---|---|")
      let released_ids : Map[String, Bool] = Map([])
      for release in plan.releases {
        released_ids[release.unit_id] = true
        lines.push(
          "| `" +
          sanitize_code_text(release.unit_id).replace_all(old="|", new="\\|") +
          "` | `" +
          sanitize_code_text(release.old_version) +
          "` → `" +
          sanitize_code_text(release.new_version) +
          "` | `" +
          release.level.text() +
          "` |",
        )
      }
      // Highlight modified managed units not covered by any release in this PR (like changesets/bot).
      if !changed.is_empty() && snapshot.units.length() > 1 {
        let uncovered : Array[String] = []
        for unit in touched_units(snapshot, changed) {
          if !released_ids.contains(unit.id) && !uncovered.contains(unit.id) {
            uncovered.push(unit.id)
          }
        }
        if !uncovered.is_empty() {
          lines.push("")
          lines.push(
            "> ℹ️ Modified packages without a changeset in this PR: " +
            uncovered.map(id => "`" + sanitize_code_text(id) + "`").join(", "),
          )
        }
      }
      if !plan.changesets.is_empty() {
        lines.push("")
        lines.push("<details>")
        lines.push(
          "<summary>Changesets (" +
          plan.changesets.length().to_string() +
          ")</summary>",
        )
        lines.push("")
        for cs in plan.changesets {
          lines.push(
            "- `" +
            sanitize_code_text(cs.path) +
            "`: " +
            first_summary_line(cs.summary),
          )
        }
        lines.push("")
        lines.push("</details>")
      }
      append_coexistence_section(lines, snapshot, dir)
    }
    "missing" => {
      lines.push("### ⚠️ No changeset found")
      lines.push("")
      lines.push(
        "Relevant files in managed packages changed in this PR without a changeset:",
      )
      lines.push("")
      let shown = if changed.length() > 20 { 20 } else { changed.length() }
      for i in 0..<shown {
        lines.push("- `" + sanitize_code_text(changed[i]) + "`")
      }
      if changed.length() > 20 {
        lines.push(
          "- ... and " + (changed.length() - 20).to_string() + " more file(s)",
        )
      }
      let units = touched_units(snapshot, changed)
      let sample_unit = if units.is_empty() { "org/pkg" } else { units[0].id }
      lines.push("")
      lines.push("Run locally to add a changeset:")
      lines.push("")
      lines.push("```sh")
      lines.push(
        "moonset add --package \"" +
        sanitize_code_text(sample_unit) +
        "\" --type patch --summary \"Describe your change\"",
      )
      lines.push("```")
      if options.head_repo is Some(repo) &&
        options.head_ref is Some(branch) &&
        is_valid_repo_slug(repo) &&
        branch.trim() != "" {
        let slug = deterministic_changeset_slug(branch, changed)
        let template_lines = ["---"]
        for unit in units {
          template_lines.push("\"" + unit.id + "\": patch")
        }
        template_lines.push("---")
        template_lines.push("")
        template_lines.push("Describe your change.")
        template_lines.push("")
        let template = template_lines.join("\n")
        let rel_dir = if dir == "" || dir == "." { ".changeset" } else { dir }
        let url = "https://github.com/" +
          repo +
          "/new/" +
          encode_ref_path(branch) +
          "?filename=" +
          percent_encode(rel_dir + "/" + slug + ".md") +
          "&value=" +
          percent_encode(template)
        lines.push("")
        lines.push("[➕ Click here to add a changeset on GitHub](" + url + ")")
      }
      lines.push("")
      lines.push(
        "If this PR does not require a release, add an empty changeset with `moonset add --empty`.",
      )
      append_coexistence_section(lines, snapshot, dir)
    }
    "empty" => {
      lines.push("### ℹ️ Empty changeset — no release required")
      lines.push("")
      lines.push(
        "An empty or `none` changeset is present. No package versions will be bumped by this PR.",
      )
      append_coexistence_section(lines, snapshot, dir)
    }
    _ => {
      lines.push("### ℹ️ No release changes detected")
      lines.push("")
      lines.push("No managed packages require a version bump in this PR.")
      append_coexistence_section(lines, snapshot, dir)
    }
  }
  truncate_markdown(lines.join("\n") + "\n", options.max_length)
}

///|
pub fn error_markdown(
  diagnostic : @model.Diagnostic,
  max_length~ : Int32 = 60000,
) -> String {
  let loc = if diagnostic.path == "" {
    "(workspace)"
  } else {
    sanitize_code_text(diagnostic.path) +
    ":" +
    diagnostic.line.to_string() +
    ":" +
    diagnostic.column.to_string()
  }
  let lines = [
    bot_marker,
    "### ❌ Failed to inspect changesets",
    "",
    "- **Code**: `" + sanitize_code_text(diagnostic.code) + "`",
    "- **Location**: `" + loc + "`",
    "- **Message**: " + sanitize_user_text(diagnostic.message),
    "",
    "Fix the configuration or changeset error above and push a new commit.",
  ]
  truncate_markdown(lines.join("\n") + "\n", max_length)
}
