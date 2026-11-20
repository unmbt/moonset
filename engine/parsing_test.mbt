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
  assert_eq(config.update_dependents, @model.OutOfRange)
  assert_eq(
    @engine.parse_config("\uFEFF{\r\n\"schemaVersion\": 1\r\n}").update_dependents,
    @model.OutOfRange,
  )
  let config = @engine.parse_config(
    "{\"updateInternalDependents\":\"always\",\"updateInternalDependencies\":\"minor\"}",
  )
  assert_eq(config.update_dependencies, @model.Minor)
  assert_eq(config.update_dependents, @model.Always)
}

///|
test "config validates nested fields duplicate keys and capabilities" {
  for
    source in [
      "{\"unknown\":1}", "{\"tag\":{\"push\":\"true\"}}", "{\"ignore\":[],\"ignore\":[]}",
      "{\"fixed\":[[\"a/[unclosed\"]]}", "{\"updateInternalDependencies\":\"out-of-range\"}",
      "{\"changedFilePatterns\":[\"[z-a]\"]}", "{\"formatter\":\"prettier\",\"format\":\"biome\"}",
      "{\"snapshot\":{\"prereleaseTemplate\":\"{unknown}\"}}", "{\"pre\":{\"directory\":\"../outside\"}}",
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
test "pre states reject corrupt modes tags and unknown keys" {
  for
    text in [
      "{}", "{\"mode\":\"pre\",\"tag\":\"123\"}", "{\"mode\":\"bad\",\"tag\":\"alpha\"}",
      "{\"mode\":\"pre\",\"tag\":\"alpha\",\"unexpected\":true}",
    ] {
    let rejected = try {
      ignore(@engine.parse_pre_state(text))
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
  // v3 minimal format parses cleanly
  let v3 = @engine.parse_pre_state("{\"mode\":\"pre\",\"tag\":\"next\"}")
  assert_eq(v3.mode, @model.Pre)
  assert_eq(v3.tag, "next")
}

///|
test "schema validates propertyNames pattern and config reads changelog disabled and repo" {
  let bad_unit_key = try {
    ignore(
      @engine.parse_config(
        "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"coexist\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\".\",\"manager\":\"npm\",\"includeRoot\":false}],\"units\":{\"invalid key\":{}}}}}",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad_unit_key)

  let bad_bridge = try {
    ignore(
      @engine.parse_config(
        "{\"experimental\":{\"mixedWorkspaces\":{\"mode\":\"unified\",\"workspaces\":[{\"id\":\"js\",\"ecosystem\":\"npm\",\"root\":\".\",\"manager\":\"npm\",\"includeRoot\":false}],\"bridges\":[{\"consumer\":\"bad\",\"producer\":\"npm:@a/b\",\"kind\":\"build\",\"bump\":\"patch\",\"waitFor\":\"build\"}]}}}",
      ),
    )
    false
  } catch {
    _ => true
  }
  assert_true(bad_bridge)

  let disabled = @engine.parse_config("{\"changelog\":false}")
  assert_true(!disabled.changelog.enabled)

  let with_repo = @engine.parse_config(
    "{\"changelog\":{\"generator\":\"github\",\"options\":{\"repo\":\"unmbt/moonset\",\"disableThanks\":true}}}",
  )
  assert_eq(with_repo.github.repo, Some("unmbt/moonset"))
  assert_true(!with_repo.github.thanks)
}
