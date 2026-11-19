///|
test "Git and GitHub changelog generators render stable links from supplied metadata" {
  let context : @changelog.ChangelogContext = {
    unit_id: "moonbit:acme/core",
    version: "1.2.0",
    date: "2026-11-17",
    lines: [
      {
        changeset_id: "feature-1",
        summary: "Add streaming API for #12 (see `#99`)",
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
  assert_true(git.contains("### Minor Changes"))
  assert_true(
    git.contains(
      "- [`1234567`](https://github.com/acme/core/commit/1234567890abcdef): Add streaming API",
    ),
  )
  assert_false(git.contains("/pull/42"))
  let github = @changelog.render(@changelog.GitHub, context)
  assert_true(github.contains("### Minor Changes"))
  assert_true(
    github.contains(
      "- [#42](https://github.com/acme/core/pull/42) [`1234567`](https://github.com/acme/core/commit/1234567890abcdef) Thanks [@wyate](https://github.com/wyate)! - Add streaming API for [#12](https://github.com/acme/core/issues/12) (see `#99`)",
    ),
  )
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
    dependency_lines: ["acme/core@1.0.0"],
    existing: "",
    repository: None,
    thanks: false,
  }
  let text = @changelog.render(@changelog.GitHub, context)
  assert_true(text.contains("### Patch Changes"))
  assert_true(text.contains("- [#9](#9) - Fix rendering"))
  assert_true(text.contains("- Updated dependencies:\n  - acme/core@1.0.0"))
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

///|
test "extract_release_notes matches exact version sections across formats" {
  let changelog = "# Changelog\r\n\r\n## [v0.2.0](https://example.com) - 2026-11-19\r\n\r\n### Features\r\n\r\n- Add release notes\r\n\r\n## 0.1.0 - 2026-11-18\r\n\r\n### Fixes\r\n\r\n- Initial release\r\n\r\n## 0.1.0-alpha.1 - 2026-11-17\r\n\r\n- Alpha build\r\n"
  assert_eq(
    @changelog.extract_release_notes(changelog, "0.2.0"),
    Some("### Features\n\n- Add release notes"),
  )
  assert_eq(
    @changelog.extract_release_notes(changelog, "v0.1.0"),
    Some("### Fixes\n\n- Initial release"),
  )
  assert_eq(
    @changelog.extract_release_notes(changelog, "0.1.0-alpha.1"),
    Some("- Alpha build"),
  )
  assert_eq(@changelog.extract_release_notes(changelog, "0.1.1"), None)
  let empty_section = "# Changelog\n\n## 0.3.0 - 2026-11-20\n\n\n## 0.2.0 - 2026-11-19\n\n- Old\n"
  assert_eq(@changelog.extract_release_notes(empty_section, "0.3.0"), None)
}
