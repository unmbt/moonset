///|
test "changeset maps BOM CRLF qualified names and preserves summary" {
  let cs = @engine.parse_changeset(
    "\uFEFF---\r\n\"moonbit:acme/a\": 'minor'\r\n---\r\n\r\n中文 **summary**",
    id="a",
    path="a.md",
    mixed=true,
  ) catch {
    @model.Invalid(d) => fail(d.message)
    error => raise error
  }
  assert_eq(cs.releases[0].unit_id, "moonbit:acme/a")
  assert_eq(cs.releases[0].bump, @model.Minor)
  assert_eq(cs.summary, "中文 **summary**")
  assert_eq(
    @engine.parse_changeset("---\n---\n", id="empty", path="e.md").releases.length(),
    0,
  )
}

///|
test "changeset rejects duplicates nesting and aliases" {
  for
    source in [
      "---\na/b: patch\na/b: minor\n---", "---\n  a/b: patch\n---", "---\na/b: &alias\n---",
      "---\na/b: major",
    ] {
    let rejected = try {
      ignore(@engine.parse_changeset(source, id="a", path="a.md"))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "config defaults split declaration updates from dependents" {
  let config = @engine.parse_config("{}")
  assert_eq(config.update_dependencies, @model.Patch)
  assert_eq(config.update_dependents, "out-of-range")
  let config = @engine.parse_config(
    "{\"updateInternalDependents\":\"always\",\"updateInternalDependencies\":\"minor\"}",
  )
  assert_eq(config.update_dependencies, @model.Minor)
  assert_eq(config.update_dependents, "always")
}

///|
test "config validates nested fields duplicate keys and capabilities" {
  for
    source in [
      "{\"unknown\":1}", "{\"tag\":{\"push\":\"true\"}}", "{\"ignore\":[],\"ignore\":[]}",
      "{\"fixed\":[[\"a/*\"]]}", "{\"updateInternalDependencies\":\"out-of-range\"}",
    ] {
    let rejected = try {
      ignore(@engine.parse_config(source))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "Moon MVS differs from npm caret" {
  assert_true(@engine.version_matches("0.1.0", "0.9.0"))
  assert_true(@engine.version_matches("0.1.0", "1.0.0"))
  assert_true(!@engine.version_matches("0.1.0", "2.0.0"))
  assert_true(!@engine.version_matches("0.1.0", "0.0.9"))
  assert_true(@engine.version_matches("0.2.0-alpha.1", "0.2.0-alpha.2"))
}

///|
test "JSON diagnostics retain line column and source path" {
  let result = try {
    ignore(
      @engine.parse_config(
        "{\n  \"ignore\": [],\n  \"ignore\": []\n}",
        path="config.json",
      ),
    )
    None
  } catch {
    @model.Invalid(d) => Some(d)
    _ => None
  }
  let diagnostic = result.unwrap()
  assert_eq(diagnostic.path, "config.json")
  assert_eq(diagnostic.line, 3)
  assert_eq(diagnostic.column, 3)
}

///|
test "SemVer rejects malformed versions and compares prerelease ordering" {
  assert_true(@engine.version_matches("0.1.0-alpha.2", "0.1.0-alpha.10"))
  assert_true(!@engine.version_matches("0.1.0", "0.1.0-alpha.10"))
  for version in ["01.2.3", "1.2", "1.2.3-alpha.01", "1.2.3+", "1.2.3-"] {
    let rejected = try {
      ignore(@engine.version_matches(version, "1.2.3"))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "pre states reject corrupt modes tags and counters" {
  for
    text in [
      "{}", "{\"mode\":\"active\",\"tag\":\"123\",\"initialVersions\":{},\"nextNumbers\":{},\"consumed\":[]}",
      "{\"mode\":\"active\",\"tag\":\"alpha\",\"initialVersions\":{},\"nextNumbers\":{\"moonbit:a/b\":-1},\"consumed\":[]}",
    ] {
    let rejected = try {
      ignore(@engine.parse_pre_state(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}
