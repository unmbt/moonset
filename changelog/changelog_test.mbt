///|
test "Git and GitHub changelog generators render stable links from supplied metadata" {
  let context : @changelog.ChangelogContext = {
    unit_id: "moonbit:acme/core",
    version: "1.2.0",
    date: "2026-11-17",
    lines: [
      {
        changeset_id: "feature-1",
        summary: "Add streaming API",
        unit_id: "moonbit:acme/core",
        bump: @model.Minor,
        old_version: "1.1.0",
        new_version: "1.2.0",
        commit: Some("1234567890abcdef"),
        pull_request: Some("42"),
        author: Some("wyate"),
      },
    ],
    dependency_lines: [],
    existing: "",
    repository: Some("acme/core"),
    thanks: true,
  }
  let git = @changelog.render(@changelog.Git, context)
  assert_true(
    git.contains("https://github.com/acme/core/commit/1234567890abcdef"),
  )
  assert_false(git.contains("/pull/42"))
  let github = @changelog.render(@changelog.GitHub, context)
  assert_true(github.contains("https://github.com/acme/core/pull/42"))
  assert_true(github.contains("Thanks [@wyate]!"))
  assert_eq(github, @changelog.render(@changelog.GitHub, context))
}

///|
test "GitHub changelog gracefully retains summaries without repository metadata" {
  let context : @changelog.ChangelogContext = {
    unit_id: "npm:acme/ui",
    version: "0.2.0",
    date: "2026-11-17",
    lines: [
      {
        changeset_id: "fix-1",
        summary: "Fix rendering",
        unit_id: "npm:acme/ui",
        bump: @model.Patch,
        old_version: "0.1.0",
        new_version: "0.2.0",
        commit: None,
        pull_request: Some("9"),
        author: None,
      },
    ],
    dependency_lines: [],
    existing: "",
    repository: None,
    thanks: false,
  }
  let text = @changelog.render(@changelog.GitHub, context)
  assert_true(text.contains("Fix rendering ([#9](#9))"))
}

///|
test "compile-time generator registry supports custom renderers and rejects unknown names" {
  let registry = @changelog.GeneratorRegistry::new()
  registry.register("fixture", context => "# " + context.version)
  let context = @changelog.builtin_context(
    "moonbit:fixture", "2.0.0", "2026-11-17", "",
  )
  assert_eq(registry.render("fixture", context), "# 2.0.0")
  let rejected = try {
    ignore(registry.render("missing", context))
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "unsupported-capability"
    _ => false
  }
  assert_true(rejected)
}
