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
fn normalize_rel_dir(dir : String) -> String {
  let clean = dir.replace_all(old="\\", new="/").trim().to_owned()
  let no_dot = if clean.has_prefix("./") { clean[2:].to_owned() } else { clean }
  let stripped = if no_dot.has_suffix("/") {
    no_dot[:no_dot.length() - 1].to_owned()
  } else {
    no_dot
  }
  if stripped == "." {
    ""
  } else {
    stripped
  }
}

///|
fn unit_owns_path(path : String, unit : @model.ReleaseUnit) -> Bool {
  let norm_path = path.replace_all(old="\\", new="/")
  let root = normalize_rel_dir(unit.root)
  if root == "" {
    true
  } else {
    norm_path == root || norm_path.has_prefix(root + "/")
  }
}

///|
/// Return the most-specific (longest-root) owning unit(s) for `path`,
/// preventing a root unit (`root == ""`) from shadowing child or ignored units.
fn owning_units_for_path(
  path : String,
  units : Array[@model.ReleaseUnit],
) -> Array[@model.ReleaseUnit] {
  let mut best_len : Int32 = -1
  let owners : Array[@model.ReleaseUnit] = []
  for unit in units {
    if !unit_owns_path(path, unit) {
      continue
    }
    let root = normalize_rel_dir(unit.root)
    let len = root.length()
    if len > best_len {
      best_len = len
      owners.clear()
      owners.push(unit)
    } else if len == best_len {
      owners.push(unit)
    }
  }
  owners
}

///|
pub fn relevant_changes(
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory~ : String = ".changeset",
) -> Array[String] {
  let clean_cs_dir = normalize_rel_dir(changeset_directory)
  let clean_pre_dir = normalize_rel_dir(snapshot.config.pre.directory)
  snapshot.changed_files.filter(raw_path => {
    let path = raw_path.replace_all(old="\\", new="/")
    if clean_cs_dir != "" &&
      (path == clean_cs_dir || path.has_prefix(clean_cs_dir + "/")) {
      return false
    }
    if clean_pre_dir != "" &&
      (path == clean_pre_dir || path.has_prefix(clean_pre_dir + "/")) {
      return false
    }
    if path == ".moonset" || path.has_prefix(".moonset/") {
      return false
    }
    if is_excluded_path(path) {
      return false
    }
    let owners = owning_units_for_path(path, snapshot.units)
    owners.any(unit => {
      if is_unit_ignored(snapshot.config, unit.id) {
        return false
      }
      let root = normalize_rel_dir(unit.root)
      let unit_path = if root == "" {
        path
      } else if path.length() > root.length() {
        path[root.length() + 1:].to_owned()
      } else {
        path
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
    ("ok", Json::boolean(!missing)),
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
