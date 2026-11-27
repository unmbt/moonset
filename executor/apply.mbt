///|
fn validate_journal_relative_path(
  raw : String,
  context~ : String,
) -> String raise @model.MoonsetError {
  let clean = raw.replace_all(old="\\", new="/").trim().to_owned()
  if clean == "" ||
    clean.has_prefix("/") ||
    clean.contains("\u{0000}") ||
    (clean.length() >= 2 && clean[1] == ':') ||
    @path.Path(clean).is_absolute() {
    raise invalid_error(
      "workspace-escape",
      "Illegal absolute or empty path in " + context + ": " + raw,
      path=raw,
    )
  }
  for segment in clean.split("/") {
    if segment == ".." {
      raise invalid_error(
        "workspace-escape",
        "Path traversal is not allowed in " + context + ": " + raw,
        path=raw,
      )
    }
  }
  clean
}

///|
fn parse_release_state_from_edits(
  plan : @model.VersionPlan,
) -> @model.ReleaseState? {
  for edit in plan.edits {
    if edit.path == ".moonset/release-state.json" && edit.after_text != "" {
      let json = @json.parse(edit.after_text) catch { _ => return None }
      return Some(@model.ReleaseState::from_json(json)) catch { _ => None }
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
  // Validate all entry paths BEFORE modifying any file on disk.
  let validated : Array[(String, Bool, String)] = []
  for item in entries {
    match item {
      { "path": String(path), "existed": True, "content": String(content), .. } => {
        let safe_path = validate_journal_relative_path(
          path,
          context="version journal entry",
        )
        validated.push((safe_path, true, content))
      }
      { "path": String(path), "existed": False, "content": String(_), .. } => {
        let safe_path = validate_journal_relative_path(
          path,
          context="version journal entry",
        )
        validated.push((safe_path, false, ""))
      }
      _ =>
        raise invalid_error(
          "usage",
          "Version journal contains an invalid entry",
          path=journal_path,
        )
    }
  }
  let recovered : Array[String] = []
  let mut idx = 0
  for entry in validated {
    let (path, existed, content) = entry
    let target = absolute_path(root, path)
    if existed {
      atomic_write_text(host, target, content, "recover-" + idx.to_string())
    } else {
      host.remove(target)
    }
    recovered.push(path)
    idx += 1
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
  keep_journal~ : Bool = false,
) -> @model.ApplyResult {
  if plan.edits.is_empty() {
    return { applied: false, rolled_back: false, journal: None, state: None, }
  }
  let journal_path = absolute_path(root, ".moonset/version-journal.json")
  if host.exists(journal_path) {
    raise invalid_error(
      "unfinished-journal",
      "An unfinished version journal already exists; run `moonset version --recover` before applying a new plan",
      path=".moonset/version-journal.json",
    )
  }
  let originals : Array[(String, Bool, String)] = []
  let journal_entries : Array[Json] = []
  for edit in plan.edits {
    let safe_path = validate_journal_relative_path(
      edit.path,
      context="version plan edit",
    )
    let target = absolute_path(root, safe_path)
    let existed = host.exists(target)
    let current = if existed { host.read_text(target) } else { "" }
    if @model.fingerprint(Json::string(current)) != edit.before_hash {
      raise invalid_error(
        "stale-plan",
        "Stale version plan input: " + safe_path,
        path=safe_path,
      )
    }
    originals.push((safe_path, existed, current))
    journal_entries.push({
      "path": safe_path,
      "existed": existed,
      "content": current,
    })
  }
  atomic_write_text(
    host,
    journal_path,
    @model.canonical_json({
      "planFingerprint": plan.fingerprint,
      "entries": journal_entries,
    }) +
    "\n",
    "journal",
  )
  let mut applied_count = 0
  try {
    let mut index = 0
    for edit in plan.edits {
      let target = absolute_path(root, edit.path)
      if (edit.kind == "changeset" || edit.kind == "state") &&
        edit.after_text == "" {
        host.remove(target)
      } else {
        atomic_write_text(
          host,
          target,
          edit.after_text,
          "edit-" + index.to_string(),
        )
      }
      applied_count += 1
      index += 1
    }
  } catch {
    error => {
      // Only roll back files that were touched (0..applied_count inclusive of failing edit)
      let rollback_limit = if applied_count < originals.length() {
        applied_count + 1
      } else {
        originals.length()
      }
      let mut rollback_ok = true
      for i in 0..<rollback_limit {
        let (path, existed, content) = originals[i]
        let target = absolute_path(root, path)
        if existed {
          atomic_write_text(host, target, content, "rb-" + i.to_string()) catch {
            _ => rollback_ok = false
          }
        } else {
          host.remove(target) catch {
            _ => rollback_ok = false
          }
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
  // Remove journal outside the edit try-block so a cleanup error never rolls back applied edits.
  let remaining_journal = if keep_journal {
    Some(".moonset/version-journal.json")
  } else {
    try {
      host.remove(journal_path)
      None
    } catch {
      _ => Some(".moonset/version-journal.json")
    }
  }
  {
    applied: true,
    rolled_back: false,
    journal: remaining_journal,
    state: parse_release_state_from_edits(plan),
  }
}

///|
pub async fn[H : ExecutionHost] finalize_version_journal_with(
  host : H,
  root : String,
) -> Unit {
  let journal_path = absolute_path(root, ".moonset/version-journal.json")
  host.remove(journal_path) catch {
    _ => ()
  }
}

///|
pub async fn finalize_version_journal(root : String) -> Unit {
  finalize_version_journal_with(native_host(), root)
}

///|
pub async fn apply_version_plan(
  root : String,
  plan : @model.VersionPlan,
  keep_journal~ : Bool = false,
) -> @model.ApplyResult {
  apply_version_plan_with(native_host(), root, plan, keep_journal~)
}

///|
/// Stage and commit ONLY the specified domain-relative paths (`git commit --only`),
/// so unrelated pre-staged user changes are never swept into the release commit.
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
    raise @model.Io("git add failed: " + process_failure_detail(added))
  }
  let diff_args = ["diff", "--cached", "--quiet", "--"] + paths
  let diff = host.run("git", diff_args, Some(root))
  if diff.exit_code == 0 {
    return false
  }
  let commit_args = ["commit", "--only", "-m", message, "--"] + paths
  let committed = host.run("git", commit_args, Some(root))
  if committed.exit_code != 0 {
    raise @model.Io("git commit failed: " + process_failure_detail(committed))
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
