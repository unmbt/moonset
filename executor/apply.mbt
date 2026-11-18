///|
fn invalid_error(
  code : String,
  message : String,
  path~ : String = "",
) -> @model.MoonsetError {
  @model.Invalid(@model.diagnostic(code, message, path~))
}

///|
fn parse_release_state_from_edits(
  plan : @model.VersionPlan,
) -> @model.ReleaseState? {
  for edit in plan.edits {
    if edit.path == ".moonset/release-state.json" && edit.after_text != "" {
      let json = @json.parse(edit.after_text) catch { _ => return None }
      guard json
        is {
          "planFingerprint": String(plan_fingerprint),
          "releases": Array(release_items),
          "tags": Array(tag_items),
          "consumedChangesets": Array(consumed_items),
          ..
        } else {
        return None
      }
      let source_head = match json {
        { "sourceHead": String(head), .. } => Some(head)
        _ => None
      }
      let releases : Array[@model.Release] = []
      for item in release_items {
        if item
          is {
            "unitId": String(unit_id),
            "oldVersion": String(old_version),
            "newVersion": String(new_version),
            "level": String(level_text),
            "publish": publish_json,
            ..
          } {
          let level = match level_text {
            "major" => @model.Major
            "minor" => @model.Minor
            "patch" => @model.Patch
            _ => @model.None
          }
          releases.push({
            unit_id,
            old_version,
            new_version,
            level,
            reasons: [],
            changesets: [],
            publish: publish_json == Json::boolean(true),
          })
        }
      }
      let tags : Array[@model.TagIntent] = []
      for item in tag_items {
        if item
          is {
            "unitId": String(unit_id),
            "version": String(version),
            "name": String(name),
            ..
          } {
          tags.push({ unit_id, version, name, })
        }
      }
      let consumed_changesets : Array[String] = []
      for item in consumed_items {
        if item is String(id) {
          consumed_changesets.push(id)
        }
      }
      return Some({
        plan_fingerprint,
        source_head,
        releases,
        tags,
        consumed_changesets,
      })
    }
  }
  None
}

///|
pub async fn[H : ExecutionHost] recover_version_with(
  host : H,
  root : String,
) -> Array[String] {
  let journal_path = absolute_path(root, ".moonset/version-journal.json")
  if !host.exists(journal_path) {
    raise invalid_error("usage", "No version journal exists", path=journal_path)
  }
  let json = @json.parse(host.read_text(journal_path)) catch {
    _ =>
      raise invalid_error(
        "usage",
        "Version journal is not valid JSON",
        path=journal_path,
      )
  }
  guard json is { "entries": Array(entries), .. } else {
    raise invalid_error(
      "usage",
      "Version journal has an invalid shape",
      path=journal_path,
    )
  }
  let recovered : Array[String] = []
  for item in entries {
    match item {
      { "path": String(path), "existed": True, "content": String(content), .. } => {
        let target = absolute_path(root, path)
        host.mkdir(parent_dir(target))
        host.write_text(target, content)
        recovered.push(path)
      }
      { "path": String(path), "existed": False, "content": String(_), .. } => {
        host.remove(absolute_path(root, path))
        recovered.push(path)
      }
      _ =>
        raise invalid_error(
          "usage",
          "Version journal contains an invalid entry",
          path=journal_path,
        )
    }
  }
  host.remove(journal_path)
  recovered
}

///|
pub async fn recover_version(root : String) -> Array[String] {
  recover_version_with(native_host(), root)
}

///|
pub async fn[H : ExecutionHost] apply_version_plan_with(
  host : H,
  root : String,
  plan : @model.VersionPlan,
) -> @model.ApplyResult {
  if plan.edits.is_empty() {
    return { applied: false, rolled_back: false, journal: None, state: None, }
  }
  let originals : Array[Json] = []
  for edit in plan.edits {
    let target = absolute_path(root, edit.path)
    let existed = host.exists(target)
    let current = if existed { host.read_text(target) } else { "" }
    if @model.fingerprint(Json::string(current)) != edit.before_hash {
      raise invalid_error(
        "stale-plan",
        "Stale version plan input: " + edit.path,
        path=edit.path,
      )
    }
    originals.push({ "path": edit.path, "existed": existed, "content": current })
  }
  let journal_dir = absolute_path(root, ".moonset")
  let journal_path = absolute_path(root, ".moonset/version-journal.json")
  host.mkdir(journal_dir)
  host.write_text(
    journal_path,
    @model.canonical_json({
      "planFingerprint": plan.fingerprint,
      "entries": originals,
    }) +
    "\n",
  )
  try {
    let mut index = 0
    for edit in plan.edits {
      let target = absolute_path(root, edit.path)
      if (edit.kind == "changeset" || edit.kind == "state") &&
        edit.after_text == "" {
        host.remove(target)
      } else {
        let temporary = target + ".moonset-" + index.to_string() + ".tmp"
        host.mkdir(parent_dir(target))
        errdefer @async.protect_from_cancel(() => {
          host.remove(temporary) catch {
            _ => ()
          }
        })
        host.write_text(temporary, edit.after_text)
        host.rename(temporary, target)
      }
      index += 1
    }
    host.remove(journal_path)
    {
      applied: true,
      rolled_back: false,
      journal: None,
      state: parse_release_state_from_edits(plan),
    }
  } catch {
    error => {
      let mut rollback_ok = true
      for original in originals {
        match original {
          {
            "path": String(path),
            "existed": True,
            "content": String(content),
            ..
          } =>
            host.write_text(absolute_path(root, path), content) catch {
              _ => rollback_ok = false
            }
          { "path": String(path), "existed": False, .. } =>
            host.remove(absolute_path(root, path)) catch {
              _ => rollback_ok = false
            }
          _ => ()
        }
      }
      if rollback_ok {
        host.remove(journal_path) catch {
          _ => ()
        }
        raise @model.Io(error_message(error))
      } else {
        raise @model.Io(
          error_message(error) +
          " (rollback incomplete; run `moonset version --recover` using " +
          journal_path +
          ")",
        )
      }
    }
  }
}

///|
pub async fn apply_version_plan(
  root : String,
  plan : @model.VersionPlan,
) -> @model.ApplyResult {
  apply_version_plan_with(native_host(), root, plan)
}

///|
/// Stage the given domain-relative paths and commit them via parameter arrays.
pub async fn[H : ExecutionHost] commit_changes_with(
  host : H,
  root : String,
  paths : Array[String],
  message : String,
) -> Bool {
  if paths.is_empty() {
    return false
  }
  let add_args = ["add", "-A", "--"] + paths
  let added = host.run("git", add_args, Some(root))
  if added.exit_code != 0 {
    raise @model.Io("git add failed: " + added.stderr)
  }
  let diff = host.run("git", ["diff", "--cached", "--quiet"], Some(root))
  if diff.exit_code == 0 {
    return false
  }
  let committed = host.run("git", ["commit", "-m", message], Some(root))
  if committed.exit_code != 0 {
    raise @model.Io("git commit failed: " + committed.stderr)
  }
  true
}

///|
pub async fn commit_changes(
  root : String,
  paths : Array[String],
  message : String,
) -> Bool {
  commit_changes_with(native_host(), root, paths, message)
}
