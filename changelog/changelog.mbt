///|
/// Changelog generation contexts are data-only and safe to serialize.
pub(all) struct ReleaseLineContext {
  changeset_id : String
  summary : String
  unit_id : String
  bump : @model.Bump
  old_version : String
  new_version : String
  commit : String?
  pull_request : String?
  authors : Array[String]
}

///|
pub(all) struct ChangelogContext {
  unit_id : String
  version : String
  date : String
  lines : Array[ReleaseLineContext]
  dependency_lines : Array[String]
  existing : String
  repository : String?
  links : Bool
  thanks : Bool
  server_url : String
}

///|
/// JSON representation used by the versioned external generator protocol.
pub fn ChangelogContext::to_json(self : ChangelogContext) -> Json {
  let lines : Array[Json] = self.lines.map(line => {
    let commit : Json = match line.commit {
      Some(value) => Json::string(value)
      None => Json::null()
    }
    let pull_request : Json = match line.pull_request {
      Some(value) => Json::string(value)
      None => Json::null()
    }
    let first_author : Json = match line.authors.get(0) {
      Some(value) => Json::string(value)
      None => Json::null()
    }
    let row : Json = {
      "changesetId": line.changeset_id,
      "summary": line.summary,
      "unitId": line.unit_id,
      "bump": line.bump.text(),
      "oldVersion": line.old_version,
      "newVersion": line.new_version,
      "commit": commit,
      "pullRequest": pull_request,
      "author": first_author,
      "authors": line.authors.map(Json::string),
    }
    row
  })
  let repository : Json = match self.repository {
    Some(value) => Json::string(value)
    None => Json::null()
  }
  {
    "unitId": self.unit_id,
    "version": self.version,
    "date": self.date,
    "lines": lines,
    "dependencyLines": self.dependency_lines,
    "existing": self.existing,
    "repository": repository,
    "links": self.links,
    "thanks": self.thanks,
    "serverUrl": self.server_url,
  }
}

///|
/// Compile-time extension contract. Implementations must remain pure.
pub(open) trait ChangelogGenerator {
  fn name(Self) -> String
  fn render(Self, ChangelogContext) -> String
}

///|
pub(all) enum GeneratorKind {
  Builtin
  Git
  GitHub
  External(String)
}

///|
pub fn generator_kind(name : String) -> GeneratorKind {
  match name {
    "builtin" => Builtin
    "git" => Git
    "github" => GitHub
    value => External(value)
  }
}

///|
/// Registry of compile-time generators. Registration is explicit and local to the caller.
pub(all) struct GeneratorRegistry {
  generators : Map[String, (ChangelogContext) -> String]
}

///|
pub fn GeneratorRegistry::new() -> GeneratorRegistry {
  let registry = { generators: Map([]), }
  registry.register("builtin", context => render_builtin(context))
  registry.register("git", context => render_git(context))
  registry.register("github", context => render_github(context))
  registry
}

///|
pub fn GeneratorRegistry::register(
  self : GeneratorRegistry,
  name : String,
  generator : (ChangelogContext) -> String,
) -> Unit {
  self.generators[name] = generator
}

///|
pub fn[T : ChangelogGenerator] GeneratorRegistry::register_generator(
  self : GeneratorRegistry,
  name : String,
  generator : T,
) -> Unit {
  self.generators[name] = context => generator.render(context)
}

///|
pub fn GeneratorRegistry::render(
  self : GeneratorRegistry,
  name : String,
  context : ChangelogContext,
) -> String raise @model.MoonsetError {
  match self.generators.get(name) {
    Some(generator) => generator(context)
    None =>
      raise @model.Invalid(
        @model.diagnostic(
          "unsupported-capability",
          "Changelog generator is not registered: " + name,
        ),
      )
  }
}

///|
/// Render a complete changelog document using a registered generator kind.
pub fn render(kind : GeneratorKind, context : ChangelogContext) -> String {
  match kind {
    Builtin => render_builtin(context)
    Git => render_git(context)
    GitHub => render_github(context)
    External(name) =>
      "# Changelog\n\n<!-- unsupported generator: " + name + " -->\n"
  }
}

///|
pub fn builtin_context(
  unit_id : String,
  version : String,
  date : String,
  existing : String,
  repository? : String,
  links~ : Bool = true,
  thanks~ : Bool = true,
  server_url~ : String = "https://github.com",
) -> ChangelogContext {
  {
    unit_id,
    version,
    date,
    lines: [],
    dependency_lines: [],
    existing,
    repository,
    links,
    thanks,
    server_url,
  }
}

///|
fn section(bump : @model.Bump) -> String {
  match bump {
    @model.Major => "Major Changes"
    @model.Minor => "Minor Changes"
    @model.Patch => "Patch Changes"
    @model.None => ""
  }
}

///|
fn is_ascii_digit(ch : Char) -> Bool {
  ch >= '0' && ch <= '9'
}

///|
fn is_ident_char(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  is_ascii_digit(ch) ||
  ch == '_' ||
  ch == '-'
}

///|
fn clean_server_url(server_url : String) -> String {
  let trimmed = server_url.trim().to_owned()
  if trimmed == "" {
    "https://github.com"
  } else if trimmed.has_suffix("/") {
    trimmed[:trimmed.length() - 1].to_owned()
  } else {
    trimmed
  }
}

///|
fn linkify_issue_refs(
  text : String,
  repository : String?,
  server_url : String,
) -> String {
  guard repository is Some(repo) else { return text }
  if repo == "" || !text.contains("#") {
    return text
  }
  let base_url = clean_server_url(server_url)
  let lines = text
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let rendered_lines : Array[String] = []
  let mut in_fence = false
  let mut fence_char = '`'
  let mut fence_len = 0
  for line in lines {
    let trimmed = line.trim_start().to_owned()
    if trimmed.has_prefix("```") || trimmed.has_prefix("~~~") {
      let fc = trimmed.to_array()[0]
      let mut fl = 0
      for ch in trimmed.to_array() {
        if ch == fc {
          fl += 1
        } else {
          break
        }
      }
      if !in_fence {
        in_fence = true
        fence_char = fc
        fence_len = fl
        rendered_lines.push(line)
        continue
      } else if fc == fence_char && fl >= fence_len {
        in_fence = false
        rendered_lines.push(line)
        continue
      }
    }
    if in_fence {
      rendered_lines.push(line)
      continue
    }
    let chars = line.to_array()
    let len = chars.length()
    let out = StringBuilder()
    let mut i = 0
    let mut code_ticks = 0
    let mut in_link_text = false
    let mut in_link_url = false
    while i < len {
      let ch = chars[i]
      if ch == '`' {
        let mut ticks = 0
        while i + ticks < len && chars[i + ticks] == '`' {
          out.write_char('`')
          ticks += 1
        }
        if code_ticks == 0 {
          code_ticks = ticks
        } else if ticks == code_ticks {
          code_ticks = 0
        }
        i += ticks
        continue
      }
      if code_ticks == 0 {
        if ch == '[' {
          in_link_text = true
          out.write_char(ch)
          i += 1
          continue
        }
        if ch == ']' && in_link_text {
          in_link_text = false
          out.write_char(ch)
          i += 1
          if i < len && chars[i] == '(' {
            in_link_url = true
            out.write_char('(')
            i += 1
          }
          continue
        }
        if ch == ')' && in_link_url {
          in_link_url = false
          out.write_char(ch)
          i += 1
          continue
        }
        if !in_link_text &&
          !in_link_url &&
          ch == '#' &&
          (
            i == 0 ||
            (
              !is_ident_char(chars[i - 1]) &&
              chars[i - 1] != '/' &&
              chars[i - 1] != '#'
            )
          ) &&
          i + 1 < len &&
          chars[i + 1] >= '1' &&
          chars[i + 1] <= '9' {
          let mut j = i + 1
          let num = StringBuilder()
          while j < len && is_ascii_digit(chars[j]) {
            num.write_char(chars[j])
            j += 1
          }
          if j == len || !is_ident_char(chars[j]) {
            let issue = num.to_string()
            out.write_string(
              "[#" +
              issue +
              "](" +
              base_url +
              "/" +
              repo +
              "/issues/" +
              issue +
              ")",
            )
            i = j
            continue
          }
        }
      }
      out.write_char(ch)
      i += 1
    }
    rendered_lines.push(out.to_string())
  }
  rendered_lines.join("\n")
}

///|
fn short_commit_link(
  commit : String,
  repository : String?,
  links : Bool,
  server_url : String,
) -> String {
  let short = if commit.length() > 7 { commit[:7].to_owned() } else { commit }
  if !links {
    return "`" + short + "`"
  }
  match repository {
    Some(repo) if repo != "" =>
      "[`" +
      short +
      "`](" +
      clean_server_url(server_url) +
      "/" +
      repo +
      "/commit/" +
      commit +
      ")"
    _ => "`" + short + "`"
  }
}

///|
fn indent_multiline_summary(text : String) -> String {
  let normalized = text.replace_all(old="\r\n", new="\n")
  let parts = normalized.split("\n").map(x => x.to_owned()).collect()
  if parts.length() <= 1 {
    return normalized
  }
  let out : Array[String] = [parts[0]]
  for i in 1..<parts.length() {
    if parts[i] == "" {
      out.push("")
    } else {
      out.push("  " + parts[i])
    }
  }
  out.join("\n")
}

///|
fn format_authors(
  authors : Array[String],
  links : Bool,
  server_url : String,
) -> String? {
  let formatted : Array[String] = []
  let base_url = clean_server_url(server_url)
  for raw in authors {
    let author = raw.trim().to_owned()
    if author == "" {
      continue
    }
    let rendered = if links {
      "[@" + author + "](" + base_url + "/" + author + ")"
    } else {
      "@" + author
    }
    if !formatted.contains(rendered) {
      formatted.push(rendered)
    }
  }
  if formatted.is_empty() {
    None
  } else {
    Some("Thanks " + formatted.join(", ") + "!")
  }
}

///|
fn line_text(
  line : ReleaseLineContext,
  kind : String,
  repository : String?,
  links : Bool,
  thanks : Bool,
  server_url : String,
) -> String {
  let summary_text = if kind == "github" && links {
    linkify_issue_refs(line.summary, repository, server_url)
  } else {
    line.summary
  }
  let body = indent_multiline_summary(summary_text)
  if kind == "builtin" {
    return "- " + body
  }
  if kind == "git" {
    return match line.commit {
      Some(commit) if commit != "" =>
        "- " +
        short_commit_link(commit, repository, links, server_url) +
        ": " +
        body
      _ => "- " + body
    }
  }
  // GitHub format aligned with @changesets/changelog-github:
  // - [#PR](...) [`short7`](...) Thanks [@author](...)! - Summary
  let prefix_parts : Array[String] = []
  let base_url = clean_server_url(server_url)
  match line.pull_request {
    Some(pr) if pr != "" =>
      if links {
        match repository {
          Some(repo) if repo != "" =>
            prefix_parts.push(
              "[#" + pr + "](" + base_url + "/" + repo + "/pull/" + pr + ")",
            )
          _ => prefix_parts.push("#" + pr)
        }
      } else {
        prefix_parts.push("#" + pr)
      }
    _ => ()
  }
  match line.commit {
    Some(commit) if commit != "" =>
      prefix_parts.push(
        short_commit_link(commit, repository, links, server_url),
      )
    _ => ()
  }
  if thanks {
    if format_authors(line.authors, links, server_url) is Some(credit) {
      prefix_parts.push(credit)
    }
  }
  if prefix_parts.is_empty() {
    "- " + body
  } else {
    "- " + prefix_parts.join(" ") + " - " + body
  }
}

///|
/// Insert `entry` into an existing changelog while preserving any `# <title>`
/// heading and Keep-a-Changelog preamble before the first `## ` release section.
pub fn splice_changelog_entry(existing : String, entry : String) -> String {
  let clean_entry = entry.trim().to_owned()
  if existing.trim() == "" {
    return "# Changelog\n\n" + clean_entry + "\n"
  }
  let normalized = existing
    .replace_all(old="\r\n", new="\n")
    .trim_end()
    .to_owned()
  let lines = normalized.split("\n").map(x => x.to_owned()).collect()
  // Find the first top-level release section (`## `) outside fenced code blocks.
  let mut first_h2 = -1
  let mut in_fence = false
  for i, line in lines {
    let t = line.trim_start().to_owned()
    if t.has_prefix("```") || t.has_prefix("~~~") {
      in_fence = !in_fence
      continue
    }
    if !in_fence && line.has_prefix("## ") {
      first_h2 = i
      break
    }
  }
  if first_h2 > 0 {
    let head = lines[:first_h2].to_owned().join("\n").trim_end().to_owned()
    let tail = lines[first_h2:].to_owned().join("\n").trim_start().to_owned()
    return head + "\n\n" + clean_entry + "\n\n" + tail + "\n"
  }
  if first_h2 == 0 {
    return "# Changelog\n\n" + clean_entry + "\n\n" + normalized + "\n"
  }
  if lines.length() > 0 && lines[0].has_prefix("# ") {
    return normalized + "\n\n" + clean_entry + "\n"
  }
  "# Changelog\n\n" + clean_entry + "\n\n" + normalized + "\n"
}

///|
/// Line-level rendering hooks compatible with Changesets-style changelog formatters.
pub(all) struct ChangelogLineHooks {
  get_release_line : (ReleaseLineContext, ChangelogContext) -> String
  get_dependency_release_line : (Array[String], ChangelogContext) -> String
}

///|
/// Render a complete changelog document using custom line-level hooks.
pub fn render_with_line_hooks(
  context : ChangelogContext,
  hooks : ChangelogLineHooks,
) -> String {
  let major_changes : Array[String] = []
  let minor_changes : Array[String] = []
  let patch_changes : Array[String] = []
  for line in context.lines {
    let section_name = section(line.bump)
    let formatted = (hooks.get_release_line)(line, context).trim().to_owned()
    if formatted == "" {
      continue
    }
    if section_name == "Major Changes" {
      major_changes.push(formatted)
    } else if section_name == "Minor Changes" {
      minor_changes.push(formatted)
    } else if section_name == "Patch Changes" {
      patch_changes.push(formatted)
    }
  }
  if !context.dependency_lines.is_empty() {
    let dep_rendered = (hooks.get_dependency_release_line)(
        context.dependency_lines,
        context,
      )
      .trim()
      .to_owned()
    if dep_rendered != "" {
      patch_changes.push(dep_rendered)
    }
  }
  let sections : Array[String] = []
  if !major_changes.is_empty() {
    sections.push("### Major Changes\n\n" + major_changes.join("\n"))
  }
  if !minor_changes.is_empty() {
    sections.push("### Minor Changes\n\n" + minor_changes.join("\n"))
  }
  if !patch_changes.is_empty() {
    sections.push("### Patch Changes\n\n" + patch_changes.join("\n"))
  }
  let entry = if sections.is_empty() {
    "## " + context.version + " - " + context.date
  } else {
    "## " +
    context.version +
    " - " +
    context.date +
    "\n\n" +
    sections.join("\n\n")
  }
  splice_changelog_entry(context.existing, entry)
}

///|
fn default_dependency_release_line(
  dep_lines : Array[String],
  _context : ChangelogContext,
) -> String {
  if dep_lines.is_empty() {
    return ""
  }
  if dep_lines.length() == 1 && dep_lines[0].has_prefix("Updated dependencies") {
    "- " + dep_lines[0]
  } else {
    "- Updated dependencies:\n  - " + dep_lines.join("\n  - ")
  }
}

///|
fn render_document(context : ChangelogContext, kind : String) -> String {
  render_with_line_hooks(context, {
    get_release_line: (line, ctx) => {
      line_text(
        line,
        kind,
        ctx.repository,
        ctx.links,
        ctx.thanks,
        ctx.server_url,
      )
    },
    get_dependency_release_line: default_dependency_release_line,
  })
}

///|
fn render_builtin(context : ChangelogContext) -> String {
  render_document(context, "builtin")
}

///|
fn render_git(context : ChangelogContext) -> String {
  render_document(context, "git")
}

///|
fn render_github(context : ChangelogContext) -> String {
  render_document(context, "github")
}

///|
fn normalize_release_version(version : String) -> String {
  let trimmed = version.trim().to_owned()
  if trimmed.has_prefix("v") && trimmed.length() > 1 {
    trimmed[1:].to_owned()
  } else {
    trimmed
  }
}

///|
fn strip_version_token(raw : String) -> String? {
  let mut rest = raw.trim_start().to_owned()
  if rest.has_prefix("[") {
    rest = rest[1:].to_owned()
  }
  if rest.has_prefix("v") && rest.length() > 1 {
    rest = rest[1:].to_owned()
  }
  let buf = StringBuilder()
  for ch in rest.to_array() {
    if ch == ' ' || ch == '\t' || ch == ']' || ch == '(' || ch == ':' {
      break
    }
    buf.write_char(ch)
  }
  let token = buf.to_string()
  if token == "" {
    None
  } else {
    Some(token)
  }
}

///|
fn is_unit_id_prefix(text : String) -> Bool {
  (
    text.has_prefix("moonbit:") ||
    text.has_prefix("npm:") ||
    text.has_prefix("cargo:")
  ) &&
  !text.contains(" ") &&
  !text.contains("[") &&
  !text.contains("(")
}

///|
fn parse_heading_version(line : String) -> String? {
  if !line.has_prefix("## ") {
    return None
  }
  let rest = line[3:].trim_start().to_owned()
  // Support aggregated multi-unit headings: `## <unit_id> - <version> - <date>`
  if rest.find(" - ") is Some(sep) {
    let prefix = rest[:sep].trim().to_owned()
    if is_unit_id_prefix(prefix) {
      let after = rest[sep + 3:].to_owned()
      return strip_version_token(after)
    }
  }
  strip_version_token(rest)
}

///|
fn parse_aggregated_heading(line : String) -> (String, String)? {
  if !line.has_prefix("## ") {
    return None
  }
  let rest = line[3:].trim_start().to_owned()
  match rest.find(" - ") {
    Some(sep) => {
      let unit = rest[:sep].trim().to_owned()
      if !is_unit_id_prefix(unit) {
        return None
      }
      match strip_version_token(rest[sep + 3:].to_owned()) {
        Some(ver) => Some((unit, ver))
        None => None
      }
    }
    None => None
  }
}

///|
fn extract_section_matching(
  markdown : String,
  matcher : (String) -> Bool,
) -> String? {
  let lines = markdown
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let mut found = false
  let mut in_fence = false
  let collected : Array[String] = []
  for line in lines {
    let trimmed = line.trim_start().to_owned()
    if trimmed.has_prefix("```") || trimmed.has_prefix("~~~") {
      in_fence = !in_fence
      if found {
        collected.push(line)
      }
      continue
    }
    if !in_fence && line.has_prefix("## ") {
      if found {
        break
      }
      if matcher(line) {
        found = true
      }
      continue
    }
    if found {
      collected.push(line)
    }
  }
  if !found {
    return None
  }
  let mut start = 0
  while start < collected.length() && collected[start].trim() == "" {
    start += 1
  }
  let mut end = collected.length()
  while end > start && collected[end - 1].trim() == "" {
    end -= 1
  }
  if start >= end {
    None
  } else {
    Some(collected[start:end].to_owned().join("\n"))
  }
}

///|
/// Extract the Markdown body for a single version heading from CHANGELOG.md.
pub fn extract_release_notes(markdown : String, version : String) -> String? {
  let target = normalize_release_version(version)
  if target == "" {
    return None
  }
  extract_section_matching(markdown, line => {
    parse_heading_version(line) == Some(target)
  })
}

///|
/// Extract notes for a specific unit from an aggregated same-directory CHANGELOG.md,
/// falling back to standard version matching if no aggregated heading exists.
pub fn extract_unit_release_notes(
  markdown : String,
  unit_id : String,
  version : String,
) -> String? {
  let target = normalize_release_version(version)
  if target == "" {
    return None
  }
  match
    extract_section_matching(markdown, line => {
      parse_aggregated_heading(line) == Some((unit_id, target))
    }) {
    Some(body) => Some(body)
    None => extract_release_notes(markdown, version)
  }
}
