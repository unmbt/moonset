///|
fn match_glob(
  path : String,
  pattern : String,
  i : Int32,
  j : Int32,
  memo : Map[String, Bool],
) -> Bool {
  let key = "\{i}:\{j}"
  if memo.get(key) is Some(found) {
    return found
  }
  let matched = if j == pattern.length() {
    i == path.length()
  } else if pattern[j] == '*' {
    let double = j + 1 < pattern.length() && pattern[j + 1] == '*'
    let next = j + (if double { 2 } else { 1 })
    (
      double &&
      next < pattern.length() &&
      pattern[next] == '/' &&
      match_glob(path, pattern, i, next + 1, memo)
    ) ||
    match_glob(path, pattern, i, next, memo) ||
    (
      i < path.length() &&
      (double || path[i] != '/') &&
      match_glob(path, pattern, i + 1, j, memo)
    )
  } else if i < path.length() &&
    (pattern[j] == path[i] || (pattern[j] == '?' && path[i] != '/')) {
    match_glob(path, pattern, i + 1, j + 1, memo)
  } else {
    false
  }
  memo[key] = matched
  matched
}

///|
pub fn matches_pattern(path : String, pattern : String) -> Bool {
  match_glob(path, pattern, 0, 0, Map([]))
}

///|
pub fn relevant_changes(
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory~ : String = ".changeset",
) -> Array[String] {
  snapshot.changed_files.filter(path => {
    if path.has_prefix(changeset_directory + "/") {
      return false
    }
    if path
      .split("/")
      .any(x => {
        [".git", "node_modules", "_build", "target", ".mooncakes"].contains(
          x.to_owned(),
        )
      }) {
      return false
    }
    if path == "moon.work" {
      return true
    }
    snapshot.units.any(unit => {
      if snapshot.config.ignore.contains(unit.id) {
        return false
      }
      let unit_path = if unit.root == "" {
        path
      } else if path.has_prefix(unit.root + "/") {
        path[unit.root.length() + 1:].to_owned()
      } else {
        return false
      }
      snapshot.config.changed_patterns.any(pattern => {
        matches_pattern(unit_path, pattern)
      })
    })
  })
}

///|
pub fn status_json(
  snapshot : @model.WorkspaceSnapshot,
  plan : @model.ReleasePlan,
  changeset_directory~ : String = ".changeset",
) -> Json {
  let changed = relevant_changes(snapshot, changeset_directory~)
  let missing = snapshot.git_head is Some(_) &&
    !changed.is_empty() &&
    plan.changesets.is_empty()
  {
    "schemaVersion": 1,
    "workspace": snapshot.to_json(),
    "changesets": plan.changesets.map(x => x.to_json()),
    "releases": plan.releases.map(x => x.to_json()),
    "warnings": plan.warnings.map(x => x.to_json()),
    "errors": if missing {
      [
        @model.diagnostic(
          "missing-changeset", "Relevant committed files changed without a changeset",
        ).to_json(),
      ]
    } else {
      []
    },
    "hasChanges": !changed.is_empty() || !plan.changesets.is_empty(),
    "hasRelease": !plan.releases.is_empty(),
  }
}
