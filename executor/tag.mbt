///|
pub(all) struct TagOptions {
  dry_run : Bool
  push : Bool
  force : Bool
  yes : Bool
  format : String
  only_units : Array[String]
  from_manifests : Bool
}

///|
pub fn TagOptions::new(
  dry_run~ : Bool = false,
  push~ : Bool = false,
  force~ : Bool = false,
  yes~ : Bool = false,
  format~ : String = "",
  only_units~ : Array[String] = [],
  from_manifests~ : Bool = false,
) -> TagOptions {
  { dry_run, push, force, yes, format, only_units, from_manifests, }
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
fn parse_remote_tags(ls_remote_stdout : String) -> Map[String, Bool] {
  let remote : Map[String, Bool] = Map([])
  for raw_line in ls_remote_stdout.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw_line.trim().to_owned()
    if line == "" {
      continue
    }
    let parts = line.split("\t").collect()
    let ref_name = if parts.length() >= 2 {
      parts[1].trim().to_owned()
    } else {
      let ws_parts = line.split(" ").filter(x => x != "").collect()
      if ws_parts.length() >= 2 {
        ws_parts[1].to_owned()
      } else {
        ""
      }
    }
    if ref_name.has_prefix("refs/tags/") && !ref_name.has_suffix("^{}") {
      remote[ref_name[10:].to_owned()] = true
    }
  }
  remote
}

///|
fn build_manifest_tag_intents(
  loaded : @workspace.LoadedWorkspace,
) -> Array[@model.TagIntent] raise @model.MoonsetError {
  let config = loaded.snapshot.config
  let ignored = @engine.resolve_ignored_units(config, loaded.snapshot.units)
  let single_unit = loaded.snapshot.units.length() == 1
  let intents : Array[@model.TagIntent] = []
  for unit in loaded.snapshot.units {
    if ignored.contains(unit.id) {
      continue
    }
    if unit.visibility == @model.Private && !config.private_packages.tag {
      continue
    }
    guard unit.version is Some(version) else { continue }
    let default_name = if single_unit {
      "v" + version
    } else {
      unit.native_name + "@" + version
    }
    intents.push({ unit_id: unit.id, version, name: default_name, })
  }
  intents
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
  let use_manifests = options.from_manifests || !host.exists(state_path)
  let planned_versions : Map[String, String] = Map([])
  let publish_statuses : Map[String, @model.PublishStatus] = Map([])
  let all_intents : Array[@model.TagIntent] = if use_manifests {
    if !options.from_manifests && !host.exists(state_path) {
      // Stateless fallback: derive tags directly from current workspace manifests
      build_manifest_tag_intents(loaded)
    } else {
      build_manifest_tag_intents(loaded)
    }
  } else {
    let (release_state, _raw) = load_release_state(host, loaded.snapshot.root)
    if release_state.is_snapshot {
      return {
        head: loaded.snapshot.git_head.unwrap_or(""),
        tags: [],
        created: [],
        skipped: [],
        pushed: [],
        dry_run: options.dry_run,
      }
    }
    for rel in release_state.releases {
      planned_versions[rel.unit_id] = rel.new_version
    }
    for
      k, v in load_publish_state(
        host,
        loaded.snapshot.root,
        release_state.plan_fingerprint,
      ) {
      publish_statuses[k] = v
    }
    release_state.tags
  }
  let intents = if options.only_units.is_empty() {
    all_intents
  } else {
    all_intents.filter(t => options.only_units.contains(t.unit_id))
  }
  let names : Array[String] = []
  let seen_names : Map[String, Bool] = Map([])
  for intent in intents {
    if !options.force {
      let key = status_key(intent.unit_id, intent.version, "source")
      if publish_statuses.get(key) is Some(st) &&
        (
          st.state == @model.Failed ||
          st.state == @model.Blocked ||
          st.state == @model.Unknown
        ) {
        raise invalid_error(
          "unpublished-unit",
          "Cannot tag unit whose publish status is " +
          st.state.text() +
          ": " +
          intent.unit_id +
          " (retry publish or pass --force --yes)",
        )
      }
    }
    let mut unit : @model.ReleaseUnit? = None
    for candidate in loaded.snapshot.units {
      if candidate.id == intent.unit_id {
        unit = Some(candidate)
      }
    }
    if unit is Some(value) {
      if value.visibility == @model.Private &&
        !loaded.snapshot.config.private_packages.tag {
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
      loaded.snapshot.config.unit_overrides().get(intent.unit_id) {
      Some({ tag_format: Some(fmt), .. }) => fmt
      _ => ""
    }
    let effective_format = if options.format != "" {
      options.format
    } else if unit_override_format != "" {
      unit_override_format
    } else {
      loaded.snapshot.config.tag.format
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
    raise @model.Io(process_failure_detail(head_res))
  }
  let head = head_res.stdout.trim().to_owned()
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
      ["tag", "-a", "-f", name, "-m", name, "HEAD"]
    } else {
      ["tag", "-a", name, "-m", name, "HEAD"]
    }
    let tag_res = host.run("git", args, Some(loaded.snapshot.root))
    if tag_res.exit_code != 0 {
      raise @model.Io(process_failure_detail(tag_res))
    }
    created.push(name)
  }
  if options.push {
    let remote_tags = if options.force {
      Map([])
    } else {
      let ls = host.run(
        "git",
        ["ls-remote", "--tags", "origin"],
        Some(loaded.snapshot.root),
      )
      if ls.exit_code == 0 {
        parse_remote_tags(ls.stdout)
      } else {
        Map([])
      }
    }
    for name in names {
      if !options.force && remote_tags.contains(name) {
        continue
      }
      let push_args = if options.force {
        ["push", "-f", "origin", "refs/tags/" + name]
      } else {
        ["push", "origin", "refs/tags/" + name]
      }
      let push_res = host.run("git", push_args, Some(loaded.snapshot.root))
      if push_res.exit_code != 0 {
        raise @model.Io(
          "Failed pushing tag " + name + ": " + process_failure_detail(push_res),
        )
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
