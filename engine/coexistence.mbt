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
  let norm_path = path.replace_all(old="\\", new="/")
  let norm_dir = normalize_rel_dir(dir)
  if norm_dir == "" {
    // Only files directly at the repo root belong to a root manifest,
    // not files nested inside managed subdirectories or `.changeset/`.
    !norm_path.contains("/")
  } else {
    norm_path == norm_dir || norm_path.has_prefix(norm_dir + "/")
  }
}

///|
/// Build a read-only cross-partition coordination summary for coexist workspaces
/// or when unmanaged ecosystem manifests are detected.
pub fn coexistence_json(
  snapshot : @model.WorkspaceSnapshot,
  changeset_directory~ : String = ".changeset",
) -> Json? {
  let mode : @model.MixedMode? = match snapshot.config.mixed {
    Some(m) => Some(m.mode)
    None => None
  }
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
  if mode != Some(@model.Coexist) &&
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
  let clean_cs_dir = normalize_rel_dir(changeset_directory)
  let changed_unowned : Array[String] = []
  let advice : Array[Json] = []
  for raw_path in snapshot.changed_files {
    let path = raw_path.replace_all(old="\\", new="/")
    if is_excluded_path(path) ||
      path == ".moonset" ||
      path.has_prefix(".moonset/") ||
      (
        clean_cs_dir != "" &&
        (path == clean_cs_dir || path.has_prefix(clean_cs_dir + "/"))
      ) {
      continue
    }
    if !owning_units_for_path(path, snapshot.units).is_empty() {
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
    let has_change = snapshot.changed_files.any(raw_path => {
      let path = raw_path.replace_all(old="\\", new="/")
      if dir == "" {
        path == manifest
      } else {
        changed_file_in_dir(path, dir)
      }
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
    let has_change = snapshot.changed_files.any(raw_path => {
      let path = raw_path.replace_all(old="\\", new="/")
      let norm_dir = normalize_rel_dir(dir)
      if norm_dir == "" {
        false
      } else {
        path == norm_dir || path.has_prefix(norm_dir + "/")
      }
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
    Some(value) => value.text()
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
