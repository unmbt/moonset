///|
fn extract_mixed_mode(config : @model.Config) -> String? {
  match config.raw {
    {
      "experimental": { "mixedWorkspaces": { "mode": String(mode), .. }, .. },
      ..
    } => Some(mode)
    _ => None
  }
}

///|
fn foreign_changeset_dir(entry : String) -> String? {
  let prefix = "changeset-config:"
  if !entry.has_prefix(prefix) {
    return None
  }
  let config_path = entry[prefix.length():].to_owned()
  if config_path.has_suffix("/config.json") {
    Some(config_path[:config_path.length() - 12].to_owned())
  } else if config_path == "config.json" {
    Some(".")
  } else {
    Some(config_path)
  }
}

///|
fn changed_file_in_dir(path : String, dir : String) -> Bool {
  if dir == "" || dir == "." {
    true
  } else {
    path == dir || path.has_prefix(dir + "/")
  }
}

///|
/// Build a read-only cross-partition coordination summary for coexist workspaces
/// or when unmanaged ecosystem manifests are detected.
pub fn coexistence_json(
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory~ : String = ".changeset",
) -> Json? {
  let mode = extract_mixed_mode(snapshot.config)
  let unmanaged_manifests : Array[String] = []
  let foreign_dirs : Array[String] = []
  for entry in snapshot.unmanaged {
    match foreign_changeset_dir(entry) {
      Some(dir) => if !foreign_dirs.contains(dir) { foreign_dirs.push(dir) }
      None =>
        if !unmanaged_manifests.contains(entry) {
          unmanaged_manifests.push(entry)
        }
    }
  }
  if mode != Some("coexist") &&
    unmanaged_manifests.is_empty() &&
    foreign_dirs.is_empty() {
    return None
  }
  let unmanaged_dirs : Array[String] = []
  for manifest in unmanaged_manifests {
    match manifest.rev_find("/") {
      Some(idx) => {
        let dir = manifest[:idx].to_owned()
        if !unmanaged_dirs.contains(dir) {
          unmanaged_dirs.push(dir)
        }
      }
      None => ()
    }
  }
  let changed_unowned : Array[String] = []
  let advice : Array[Json] = []
  for path in snapshot.changed_files {
    if is_excluded_path(path) ||
      path == "moon.work" ||
      path.has_prefix(changeset_directory + "/") {
      continue
    }
    if snapshot.units.any(unit => unit_owns_path(path, unit)) {
      continue
    }
    if unmanaged_manifests.contains(path) ||
      unmanaged_dirs.any(dir => changed_file_in_dir(path, dir)) {
      continue
    }
    let in_foreign_cs = foreign_dirs.any(dir => changed_file_in_dir(path, dir))
    if !in_foreign_cs && !changed_unowned.contains(path) {
      changed_unowned.push(path)
    }
  }
  for manifest in unmanaged_manifests {
    let dir = match manifest.rev_find("/") {
      Some(idx) => manifest[:idx].to_owned()
      None => ""
    }
    let has_change = snapshot.changed_files.any(path => {
      changed_file_in_dir(path, dir)
    })
    if has_change {
      advice.push({
        "code": "cross-partition-change",
        "path": manifest,
        "message": "Changed files fall under unmanaged manifest '" +
        manifest +
        "'; moonset leaves that partition untouched.",
      })
    }
  }
  for dir in foreign_dirs {
    let has_change = snapshot.changed_files.any(path => {
      changed_file_in_dir(path, dir)
    })
    if has_change {
      advice.push({
        "code": "foreign-changeset-activity",
        "path": dir,
        "message": "Detected changes in external changeset directory '" +
        dir +
        "'; keep separate release tooling for that partition.",
      })
    }
  }
  for path in changed_unowned {
    advice.push({
      "code": "unowned-shared-change",
      "path": path,
      "message": "Changed file '" +
      path +
      "' is not owned by any managed release unit.",
    })
  }
  let resolved_mode = match mode {
    Some(value) => value
    None => "coexist"
  }
  Some({
    "mode": resolved_mode,
    "managedWorkspaces": snapshot.workspaces.map(ws => ws.id),
    "unmanaged": unmanaged_manifests,
    "foreignChangesetDirectories": foreign_dirs,
    "changedUnowned": changed_unowned,
    "advice": advice,
  })
}
