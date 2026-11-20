///|
test "Git and GitHub changelog generators render stable links from supplied metadata" {
  let context : @changelog.ChangelogContext = {
    unit_id: "moonbit:acme/core",
    version: "1.2.0",
    date: "2026-11-17",
    lines: [
      {
        changeset_id: "feature-1",
        summary: "Add streaming API for #12 (see `#99`, ``#88``, #123abc, https://example.com/#77)",
        unit_id: "moonbit:acme/core",
        bump: @model.Minor,
        old_version: "1.1.0",
        new_version: "1.2.0",
        commit: Some("1234567890abcdef"),
        pull_request: Some("42"),
        authors: ["wyate", "alice"],
      },
    ],
    dependency_lines: [],
    existing: "",
    repository: Some("acme/core"),
    links: true,
    thanks: true,
    server_url: "https://github.com",
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
      "- [#42](https://github.com/acme/core/pull/42) [`1234567`](https://github.com/acme/core/commit/1234567890abcdef) Thanks [@wyate](https://github.com/wyate), [@alice](https://github.com/alice)! - Add streaming API for [#12](https://github.com/acme/core/issues/12) (see `#99`, ``#88``, #123abc, https://example.com/#77)",
    ),
  )
  assert_eq(github, @changelog.render(@changelog.GitHub, context))
  // links: false suppresses URLs while retaining issue/commit/author info
  let no_links = @changelog.render(@changelog.GitHub, {
    ..context,
    links: false,
  })
  assert_false(no_links.contains("https://github.com"))
  assert_true(no_links.contains("- #42 `1234567` Thanks @wyate, @alice!"))
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
        authors: [],
      },
    ],
    dependency_lines: ["acme/core@1.0.0"],
    existing: "",
    repository: None,
    links: true,
    thanks: false,
    server_url: "https://github.com",
  }
  let text = @changelog.render(@changelog.GitHub, context)
  assert_true(text.contains("### Patch Changes"))
  assert_true(text.contains("- #9 - Fix rendering"))
  assert_true(text.contains("- Updated dependencies:\n  - acme/core@1.0.0"))
}

///|
test "render_document preserves # pkg title, preamble, empty-release fallback, and single trailing newline" {
  let existing = "# @acme/ui\n\nAll notable changes to this package.\n\n## 0.1.0 - 2026-11-01\n\n- Init\n"
  let ctx = @changelog.builtin_context(
    "npm:@acme/ui", "0.1.1", "2026-11-20", existing,
  )
  let rendered = @changelog.render(@changelog.Builtin, ctx)
  assert_true(
    rendered.has_prefix(
      "# @acme/ui\n\nAll notable changes to this package.\n\n## 0.1.1 - 2026-11-20",
    ),
  )
  assert_true(rendered.contains("- No changes in this release."))
  assert_false(rendered.has_suffix("\n\n"))
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
test "extract_release_notes handles code fences and aggregated headings" {
  let changelog = "# Changelog\r\n\r\n## [v0.2.0](https://example.com) - 2026-11-19\r\n\r\n### Minor Changes\r\n\r\n```md\r\n## not a heading\r\n```\r\n\r\n- Add release notes\r\n\r\n## moonbit:acme/a - 0.1.0 - 2026-11-18\r\n\r\n- Unit A note\r\n\r\n## npm:@acme/a - 0.1.0 - 2026-11-18\r\n\r\n- Unit B note\r\n"
  let notes = @changelog.extract_release_notes(changelog, "0.2.0").unwrap()
  assert_true(notes.contains("## not a heading"))
  assert_true(notes.contains("- Add release notes"))
  assert_eq(
    @changelog.extract_unit_release_notes(changelog, "npm:@acme/a", "0.1.0"),
    Some("- Unit B note"),
  )
  assert_eq(
    @changelog.extract_unit_release_notes(changelog, "moonbit:acme/a", "0.1.0"),
    Some("- Unit A note"),
  )
  assert_eq(@changelog.extract_release_notes(changelog, "0.1.1"), None)
}
