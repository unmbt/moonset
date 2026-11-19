///|
fn pr_unit_display_name(unit_id : String, mixed : Bool) -> String {
  if mixed {
    return unit_id
  }
  match unit_id.find(":") {
    Some(idx) => unit_id[idx + 1:].to_owned()
    None => unit_id
  }
}

///|
fn extract_aggregated_unit_notes(
  markdown : String,
  unit_id : String,
  version : String,
) -> String? {
  let heading_prefix = "## " + unit_id + " - " + version
  let lines = markdown
    .replace_all(old="\r\n", new="\n")
    .split("\n")
    .map(x => x.to_owned())
    .collect()
  let mut found = false
  let collected : Array[String] = []
  for line in lines {
    if line.has_prefix("## ") {
      if found {
        break
      }
      if line == heading_prefix || line.has_prefix(heading_prefix + " ") {
        found = true
      }
      continue
    }
    if found {
      collected.push(line)
    }
  }
  if !found {
    return None
  }
  let mut start = 0
  while start < collected.length() && collected[start].trim() == "" {
    start += 1
  }
  let mut end = collected.length()
  while end > start && collected[end - 1].trim() == "" {
    end -= 1
  }
  if start >= end {
    None
  } else {
    Some(collected[start:end].to_owned().join("\n"))
  }
}

///|
/// Compute the Release PR title, appending `(<tag>)` when pre-release mode is active.
pub fn release_pr_title(base_title : String, pre? : @model.PreState) -> String {
  let trimmed = base_title.trim().to_owned()
  match pre {
    Some(state) if state.mode == "active" && state.tag != "" => {
      let suffix = " (" + state.tag + ")"
      if trimmed.has_suffix(suffix) {
        trimmed
      } else {
        trimmed + suffix
      }
    }
    _ => trimmed
  }
}

///|
/// Render a full Changesets-style Release PR body from a VersionPlan without I/O.
pub fn render_release_pr_body(
  snapshot : @model.WorkspaceSnapshot,
  version_plan : @model.VersionPlan,
  pre? : @model.PreState,
  max_chars~ : Int32 = 60000,
) -> String {
  let base_branch = if snapshot.config.base_branch == "" {
    "main"
  } else {
    snapshot.config.base_branch
  }
  let mixed = snapshot.units.any(u => u.ecosystem != "moonbit")
  let sections : Array[String] = []
  sections.push(
    "This PR was opened by the [moonset release](https://github.com/unmbt/moonset) GitHub Action. When you're ready to do a release, merge this PR to publish and tag automatically (or run `moonset publish` locally). If you're not ready to do a release yet, whenever you add more changesets to `" +
    base_branch +
    "`, this PR will be updated.",
  )
  match pre {
    Some(state) if state.mode == "active" && state.tag != "" =>
      sections.push(
        "⚠️⚠️⚠️⚠️⚠️⚠️\n\n`" +
        base_branch +
        "` is currently in **pre mode** (`" +
        state.tag +
        "`) so this branch contains prereleases rather than normal releases. If you want to exit prerelease mode, run `moonset pre exit` on `" +
        base_branch +
        "`.\n\n⚠️⚠️⚠️⚠️⚠️⚠️",
      )
    _ => ()
  }
  let version_by_unit : Map[String, String] = Map([])
  for entry in version_plan.changelogs {
    version_by_unit[entry.unit_id] = entry.version
  }
  for tag_intent in version_plan.tags {
    if !version_by_unit.contains(tag_intent.unit_id) {
      version_by_unit[tag_intent.unit_id] = tag_intent.version
    }
  }
  if !version_plan.analysis.releases.is_empty() {
    let table_rows : Array[String] = [
      "## Release Summary", "", "| Package | Version | Bump |", "|---|---|---|",
    ]
    for release in version_plan.analysis.releases {
      let target_ver = version_by_unit
        .get(release.unit_id)
        .unwrap_or(release.new_version)
      table_rows.push(
        "| `" +
        release.unit_id +
        "` | `" +
        release.old_version +
        "` → `" +
        target_ver +
        "` | `" +
        release.level.text() +
        "` |",
      )
    }
    sections.push(table_rows.join("\n"))

    let changelog_by_unit : Map[String, @model.ChangelogEntry] = Map([])
    for entry in version_plan.changelogs {
      changelog_by_unit[entry.unit_id] = entry
    }
    let release_blocks : Array[String] = ["# Releases"]
    for release in version_plan.analysis.releases {
      let target_ver = version_by_unit
        .get(release.unit_id)
        .unwrap_or(release.new_version)
      let display_name = pr_unit_display_name(release.unit_id, mixed)
      let heading = "## " + display_name + "@" + target_ver
      let extracted : String? = match changelog_by_unit.get(release.unit_id) {
        Some(entry) =>
          match @changelog.extract_release_notes(entry.text, entry.version) {
            Some(body) => Some(body)
            None =>
              extract_aggregated_unit_notes(
                entry.text,
                entry.unit_id,
                entry.version,
              )
          }
        None => None
      }
      let body = match extracted {
        Some(text) => text
        None =>
          "- Version bump: `" +
          release.level.text() +
          "` (" +
          release.reasons.join(", ") +
          ")"
      }
      release_blocks.push(heading + "\n\n" + body)
    }
    sections.push(release_blocks.join("\n\n"))
  }
  let full = sections.join("\n\n") + "\n"
  if full.length() <= max_chars {
    return full
  }
  let notice = "\n\n> _Release notes truncated to fit GitHub PR limits; see each package's `CHANGELOG.md` for full details._\n"
  let budget = if max_chars > notice.length() {
    max_chars - notice.length()
  } else {
    0
  }
  let mut cut = budget
  while cut > 0 && full[cut - 1] != '\n' {
    cut -= 1
  }
  if cut == 0 {
    cut = budget
  }
  full[:cut].to_owned() + notice
}
