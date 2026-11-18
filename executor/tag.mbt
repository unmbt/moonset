///|
pub(all) struct TagOptions {
  dry_run : Bool
  push : Bool
  force : Bool
  yes : Bool
  format : String
}

///|
pub(all) struct TagResult {
  head : String
  tags : Array[String]
  created : Array[String]
  skipped : Array[String]
  pushed : Array[String]
  dry_run : Bool
}

///|
pub fn TagResult::to_json(self : TagResult) -> Json {
  {
    "schemaVersion": 1,
    "head": self.head,
    "tags": self.tags,
    "created": self.created,
    "skipped": self.skipped,
    "pushed": self.pushed,
    "dryRun": self.dry_run,
  }
}

///|
fn formatted_tag(intent : @model.TagIntent, template : String) -> String {
  @engine.format_tag_name(intent.unit_id, intent.version, intent.name, template)
}

///|
pub async fn[H : ExecutionHost] create_tags_with(
  host : H,
  loaded : @workspace.LoadedWorkspace,
  options : TagOptions,
) -> TagResult {
  let state_path = absolute_path(
    loaded.snapshot.root,
    ".moonset/release-state.json",
  )
  if !host.exists(state_path) {
    raise invalid_error(
      "usage",
      "No release state exists; run version first",
      path=state_path,
    )
  }
  let state = @json.parse(host.read_text(state_path)) catch {
    _ =>
      raise invalid_error(
        "usage",
        "Release state is not valid JSON",
        path=state_path,
      )
  }
  guard state is { "tags": Array(items), .. } else {
    raise invalid_error(
      "usage",
      "Release state has no tag intents",
      path=state_path,
    )
  }
  let planned_versions : Map[String, String] = Map([])
  if state is { "releases": Array(releases), .. } {
    for rel in releases {
      if rel is { "unitId": String(uid), "newVersion": String(ver), .. } {
        planned_versions[uid] = ver
      }
    }
  }
  let intents : Array[@model.TagIntent] = []
  for item in items {
    guard item
      is {
        "unitId": String(unit_id),
        "version": String(version),
        "name": String(name),
        ..
      } else {
      raise invalid_error(
        "usage",
        "Release state contains an invalid tag intent",
        path=state_path,
      )
    }
    intents.push({ unit_id, version, name, })
  }
  let names : Array[String] = []
  let seen_names : Map[String, Bool] = Map([])
  for intent in intents {
    let mut unit : @model.ReleaseUnit? = None
    for candidate in loaded.snapshot.units {
      if candidate.id == intent.unit_id {
        unit = Some(candidate)
      }
    }
    if unit is Some(value) {
      if value.visibility == "private" && !loaded.snapshot.config.private_tag {
        raise invalid_error(
          "private-policy",
          "Tagging private unit is disabled: " + intent.unit_id,
          path=value.manifest,
        )
      }
      if planned_versions.get(intent.unit_id) is Some(expected_version) &&
        value.version != Some(expected_version) {
        raise invalid_error(
          "stale-release-state",
          "Current manifest version does not match release-state.json for " +
          intent.unit_id,
          path=value.manifest,
        )
      }
    }
    let unit_override_format = match
      loaded.snapshot.config.unit_overrides.get(intent.unit_id) {
      Some({ tag_format: Some(fmt), .. }) => fmt
      _ => ""
    }
    let effective_format = if options.format != "" {
      options.format
    } else if unit_override_format != "" {
      unit_override_format
    } else {
      loaded.snapshot.config.tag_format
    }
    let rendered = formatted_tag(intent, effective_format)
    @engine.validate_git_tag_name(rendered)
    if seen_names.contains(rendered) {
      raise invalid_error(
        "duplicate-tag",
        "Multiple release units resolve to duplicate Git tag: " + rendered,
      )
    }
    seen_names[rendered] = true
    names.push(rendered)
  }
  let head_res = host.run(
    "git",
    ["rev-parse", "HEAD"],
    Some(loaded.snapshot.root),
  )
  if head_res.exit_code != 0 {
    raise @model.Io(head_res.stderr)
  }
  let head = head_res.stdout.trim().to_owned()
  let dirty_res = host.run(
    "git",
    ["status", "--porcelain"],
    Some(loaded.snapshot.root),
  )
  if dirty_res.exit_code == 0 && has_dirty_worktree_changes(dirty_res.stdout) {
    raise invalid_error(
      "dirty-working-tree", "Working tree is dirty; commit version changes before tagging",
    )
  }
  if options.dry_run {
    return {
      head,
      tags: names,
      created: [],
      skipped: [],
      pushed: [],
      dry_run: true,
    }
  }
  if options.force && !options.yes {
    raise invalid_error(
      "confirmation-required", "--force requires --yes for tag",
    )
  }
  let created : Array[String] = []
  let skipped : Array[String] = []
  let pushed : Array[String] = []
  for name in names {
    let existing = host.run(
      "git",
      ["rev-parse", "--verify", "refs/tags/" + name],
      Some(loaded.snapshot.root),
    )
    if existing.exit_code == 0 {
      let existing_target = host.run(
        "git",
        ["rev-list", "-n", "1", "refs/tags/" + name],
        Some(loaded.snapshot.root),
      )
      if existing_target.exit_code == 0 &&
        existing_target.stdout.trim().to_owned() == head &&
        !options.force {
        skipped.push(name)
        continue
      }
      if !options.force {
        raise invalid_error(
          "tag-conflict",
          "Tag already exists at a different commit: " + name,
        )
      }
    }
    let args = if options.force {
      ["tag", "-f", name, "HEAD"]
    } else {
      ["tag", name, "HEAD"]
    }
    let tag_res = host.run("git", args, Some(loaded.snapshot.root))
    if tag_res.exit_code != 0 {
      raise @model.Io(tag_res.stderr)
    }
    created.push(name)
  }
  if options.push {
    for name in created {
      let push_res = host.run(
        "git",
        ["push", "origin", name],
        Some(loaded.snapshot.root),
      )
      if push_res.exit_code != 0 {
        raise @model.Io("Failed pushing tag " + name + ": " + push_res.stderr)
      }
      pushed.push(name)
    }
  }
  { head, tags: names, created, skipped, pushed, dry_run: false, }
}

///|
pub async fn create_tags(
  loaded : @workspace.LoadedWorkspace,
  options : TagOptions,
) -> TagResult {
  create_tags_with(native_host(), loaded, options)
}
