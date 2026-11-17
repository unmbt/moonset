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
fn line_text(
  line : ReleaseLineContext,
  kind : String,
  repository : String?,
  thanks : Bool,
) -> String {
  let mut text = "- " + line.summary.replace_all(old="\n", new="\n  ")
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
          text = text + " Thanks [@" + author + "]!"
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
