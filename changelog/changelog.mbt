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
  author : String?
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
  thanks : Bool
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
    let author : Json = match line.author {
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
      "author": author,
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
    "thanks": self.thanks,
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
/// Render a complete changelog document using a registered Phase 5 name.
pub fn render(kind : GeneratorKind, context : ChangelogContext) -> String {
  match kind {
    Builtin => render_builtin(context)
    Git => render_git(context)
    GitHub => render_github(context)
    External(name) =>
      // External generators are executed by adapters. Keeping this result
      // explicit prevents an unknown name from silently becoming builtin.
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
  thanks~ : Bool = true,
) -> ChangelogContext {
  {
    unit_id,
    version,
    date,
    lines: [],
    dependency_lines: [],
    existing,
    repository,
    thanks,
  }
}

///|
fn section(bump : @model.Bump) -> String {
  match bump {
    @model.Major | @model.Minor => "Features"
    @model.Patch => "Fixes"
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
fn linkify_issue_refs(text : String, repository : String?) -> String {
  guard repository is Some(repo) else { return text }
  if repo == "" || !text.contains("#") {
    return text
  }
  let chars = text.to_array()
  let len = chars.length()
  let out = StringBuilder()
  let mut i = 0
  let mut in_code = false
  let mut in_link_text = false
  let mut in_link_url = false
  while i < len {
    let ch = chars[i]
    if ch == '`' {
      in_code = !in_code
      out.write_char(ch)
      i += 1
      continue
    }
    if !in_code {
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
        (i == 0 || !is_ident_char(chars[i - 1])) &&
        i + 1 < len &&
        chars[i + 1] >= '1' &&
        chars[i + 1] <= '9' {
        let mut j = i + 1
        let num = StringBuilder()
        while j < len && is_ascii_digit(chars[j]) {
          num.write_char(chars[j])
          j += 1
        }
        let issue = num.to_string()
        out.write_string(
          "[#" +
          issue +
          "](https://github.com/" +
          repo +
          "/issues/" +
          issue +
          ")",
        )
        i = j
        continue
      }
    }
    out.write_char(ch)
    i += 1
  }
  out.to_string()
}

///|
fn line_text(
  line : ReleaseLineContext,
  kind : String,
  repository : String?,
  thanks : Bool,
) -> String {
  let summary_text = if kind == "github" {
    linkify_issue_refs(line.summary, repository)
  } else {
    line.summary
  }
  let mut text = "- " + summary_text.replace_all(old="\n", new="\n  ")
  if kind != "builtin" {
    match line.commit {
      Some(commit) if commit != "" => {
        let short = if commit.length() > 8 {
          commit[:8].to_owned()
        } else {
          commit
        }
        let link = match repository {
          Some(repo) =>
            "[" +
            short +
            "](https://github.com/" +
            repo +
            "/commit/" +
            commit +
            ")"
          None => short
        }
        text = text + " (" + link + ")"
      }
      _ => ()
    }
  }
  if kind == "github" {
    match line.pull_request {
      Some(pr) if pr != "" => {
        let pr_link = match repository {
          Some(repo) => "https://github.com/" + repo + "/pull/" + pr
          None => "#" + pr
        }
        text = text + " ([#" + pr + "](" + pr_link + "))"
      }
      _ => ()
    }
    if thanks {
      match line.author {
        Some(author) if author != "" =>
          text = text +
            " Thanks [@" +
            author +
            "](https://github.com/" +
            author +
            ")!"
        _ => ()
      }
    }
  }
  text
}

///|
fn render_document(context : ChangelogContext, kind : String) -> String {
  let features : Array[String] = []
  let fixes : Array[String] = []
  for line in context.lines {
    let section_name = section(line.bump)
    if section_name == "Features" {
      features.push(line_text(line, kind, context.repository, context.thanks))
    } else if section_name == "Fixes" {
      fixes.push(line_text(line, kind, context.repository, context.thanks))
    }
  }
  let sections : Array[String] = []
  if !features.is_empty() {
    sections.push("### Features\n\n" + features.join("\n") + "\n")
  }
  if !fixes.is_empty() {
    sections.push("### Fixes\n\n" + fixes.join("\n") + "\n")
  }
  if !context.dependency_lines.is_empty() {
    sections.push(
      "### Dependencies\n\n- " + context.dependency_lines.join("\n- ") + "\n",
    )
  }
  let entry = "## " +
    context.version +
    " - " +
    context.date +
    "\n\n" +
    sections.join("\n")
  if context.existing == "" {
    return "# Changelog\n\n" + entry + "\n"
  }
  let normalized = context.existing.replace_all(old="\r\n", new="\n")
  if normalized.has_prefix("# Changelog") {
    match normalized.find("\n") {
      Some(index) =>
        normalized[:index + 1].to_owned() +
        "\n" +
        entry +
        "\n" +
        normalized[index + 1:].trim_start().to_owned() +
        "\n"
      None => normalized + "\n\n" + entry + "\n"
    }
  } else {
    "# Changelog\n\n" + entry + "\n\n" + normalized
  }
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
fn parse_heading_version(line : String) -> String? {
  if !line.has_prefix("## ") {
    return None
  }
  let mut rest = line[3:].trim_start().to_owned()
  if rest.has_prefix("[") {
    rest = rest[1:].to_owned()
  }
  if rest.has_prefix("v") && rest.length() > 1 {
    rest = rest[1:].to_owned()
  }
  let buf = StringBuilder()
  for ch in rest.to_array() {
    if ch == ' ' || ch == '\t' || ch == ']' || ch == '(' {
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
/// Extract the Markdown body for a single version heading from CHANGELOG.md.
pub fn extract_release_notes(markdown : String, version : String) -> String? {
  let target = normalize_release_version(version)
  if target == "" {
    return None
  }
  let lines = markdown
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let mut found = false
  let collected : Array[String] = []
  for line in lines {
    if line.has_prefix("## ") {
      if found {
        break
      }
      if parse_heading_version(line) == Some(target) {
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
