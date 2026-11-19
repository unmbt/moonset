///|
fn is_excluded_path(path : String) -> Bool {
  path
  .split("/")
  .any(x => {
    [".git", "node_modules", "_build", "target", ".mooncakes"].contains(
      x.to_owned(),
    )
  })
}

///|
fn unit_owns_path(path : String, unit : @model.ReleaseUnit) -> Bool {
  if unit.root == "" {
    true
  } else {
    path.has_prefix(unit.root + "/")
  }
}

///|
pub fn relevant_changes(
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory~ : String = ".changeset",
) -> Array[String] {
  let pre_dir = snapshot.config.pre_directory
    .replace_all(old="\\", new="/")
    .trim()
    .to_owned()
  let clean_pre_dir = if pre_dir.has_suffix("/") {
    pre_dir[:pre_dir.length() - 1].to_owned()
  } else {
    pre_dir
  }
  snapshot.changed_files.filter(path => {
    if path.has_prefix(changeset_directory + "/") {
      return false
    }
    if clean_pre_dir != "" &&
      clean_pre_dir != "." &&
      path.has_prefix(clean_pre_dir + "/") {
      return false
    }
    if is_excluded_path(path) {
      return false
    }
    if path == "moon.work" {
      return true
    }
    snapshot.units.any(unit => {
      if is_unit_ignored(snapshot.config, unit.id) {
        return false
      }
      if !unit_owns_path(path, unit) {
        return false
      }
      let unit_path = if unit.root == "" {
        path
      } else {
        path[unit.root.length() + 1:].to_owned()
      }
      matches_changed_patterns(unit_path, snapshot.config.changed_patterns)
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
  let fields : Map[String, Json] = Map([
    ("schemaVersion", Json::number(1.0)),
    ("workspace", snapshot.to_json()),
    ("changesets", Json::array(plan.changesets.map(x => x.to_json()))),
    ("releases", Json::array(plan.releases.map(x => x.to_json()))),
    ("warnings", Json::array(plan.warnings.map(x => x.to_json()))),
    (
      "errors",
      Json::array(
        if missing {
          [
            @model.diagnostic(
              "missing-changeset", "Relevant committed files changed without a changeset",
            ).to_json(),
          ]
        } else {
          []
        },
      ),
    ),
    (
      "hasChanges",
      Json::boolean(!changed.is_empty() || !plan.changesets.is_empty()),
    ),
    ("hasRelease", Json::boolean(!plan.releases.is_empty())),
  ])
  if coexistence_json(snapshot, changeset_directory~) is Some(coex) {
    fields["coexistence"] = coex
  }
  Json::object(fields)
}
