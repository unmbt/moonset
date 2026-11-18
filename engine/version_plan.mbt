///|
fn version_date(value : String) -> String {
  if value.length() >= 10 {
    value[:10].to_owned()
  } else if value == "" {
    "1970-01-01"
  } else {
    value
  }
}

///|
fn planned_version(
  base : String,
  options : @model.VersionOptions,
  generated_at : String,
) -> String {
  match options.snapshot_tag {
    None => base
    Some(tag) => {
      let clean = tag.trim()
      if clean == "" {
        base
      } else {
        let stamp = generated_at
          .replace_all(old="-", new="")
          .replace_all(old=":", new="")
        base +
        "-" +
        clean.to_owned() +
        "." +
        (if stamp == "" { "0" } else { stamp })
      }
    }
  }
}

///|
fn edit_hash(source : String) -> String {
  @model.fingerprint(Json::string(source))
}

///|
fn quote_string(value : String) -> String {
  Json::string(value).stringify()
}

///|
fn replace_byte_span(
  source : String,
  start : Int32,
  end : Int32,
  value : String,
) -> String {
  let bytes = @utf8.encode(source)
  let left = @utf8.decode_lossy(bytes[:start])
  let right = @utf8.decode_lossy(bytes[end:])
  left + value + right
}

///|
fn dependency_literal(intent : @model.DependencyIntent) -> String {
  if intent.producer.has_prefix("cargo:") {
    return intent.new_requirement
  }
  let producer = if intent.producer.has_prefix("moonbit:") {
    intent.producer[8:].to_owned()
  } else {
    intent.producer
  }
  quote_string(producer + "@" + intent.new_requirement)
}

///|
fn common_prefix_length(left : String, right : String) -> Int32 {
  let a = @utf8.encode(left)
  let b = @utf8.encode(right)
  let mut index = 0
  while index < a.length() && index < b.length() && a[index] == b[index] {
    index += 1
  }
  index
}

///|
fn replace_json_string(
  source : String,
  key : String,
  value : String,
) -> String raise @model.MoonsetError {
  let parsed = parse_json(source, "package.json")
  match parsed {
    Object(fields) => {
      fields[key] = Json::string(value)
      parsed.stringify(indent=2) + "\n"
    }
    _ => source
  }
}

///|
fn replace_toml_version(
  source : String,
  section : String,
  version : String,
) -> String {
  let mut active = ""
  let mut offset = 0
  for raw in source.replace_all(old="\r\n", new="\n").split("\n") {
    let line = raw.to_owned()
    let trimmed = line.trim().to_owned()
    if trimmed.has_prefix("[") && trimmed.has_suffix("]") {
      active = trimmed[1:trimmed.length() - 1].to_owned()
    } else if active == section && trimmed.has_prefix("version = \"") {
      let local_offset = line.find("\"").unwrap() + 1
      let value_start = offset + local_offset
      let end = source[value_start:].find("\"").unwrap()
      return replace_byte_span(source, value_start, value_start + end, version)
    }
    offset += line.length() + 1
  }
  source
}

///|
fn section_for(bump : @model.Bump) -> String {
  match bump {
    @model.Major | @model.Minor => "Features"
    @model.Patch => "Fixes"
    @model.None => ""
  }
}

///|
/// Render the deterministic builtin changelog document for one release unit.
pub fn render_builtin_changelog(
  unit_id : String,
  version : String,
  date : String,
  changesets : Array[@model.Changeset],
  dependency_updates : Array[@model.DependencyIntent],
  existing : String,
) -> String {
  let lines : Array[@changelog.ReleaseLineContext] = []
  for changeset in changesets {
    for change in changeset.releases {
      if change.unit_id != unit_id {
        continue
      }
      if section_for(change.bump) == "" || changeset.summary == "" {
        continue
      }
      lines.push({
        changeset_id: changeset.id,
        summary: changeset.summary,
        unit_id,
        bump: change.bump,
        old_version: "",
        new_version: version,
        commit: None,
        pull_request: None,
        author: None,
      })
    }
  }
  let dependencies : Array[String] = []
  for update in dependency_updates {
    if update.consumer == unit_id {
      let item = "- `" +
        update.producer +
        "` updated to `" +
        update.new_requirement +
        "`."
      if !dependencies.contains(item) {
        dependencies.push(item)
      }
    }
  }
  let context : @changelog.ChangelogContext = {
    unit_id,
    version,
    date: version_date(date),
    lines,
    dependency_lines: dependencies.map(x => x[2:].to_owned()),
    existing,
    repository: None,
    thanks: false,
  }
  @changelog.render(@changelog.Builtin, context)
}

///|
/// Render the configured generator while preserving the pure plan boundary.
fn render_configured_changelog(
  generator : String,
  unit_id : String,
  version : String,
  date : String,
  changesets : Array[@model.Changeset],
  dependency_updates : Array[@model.DependencyIntent],
  existing : String,
  repository : String?,
  registry : @changelog.GeneratorRegistry,
) -> String raise @model.MoonsetError {
  let lines : Array[@changelog.ReleaseLineContext] = []
  for changeset in changesets {
    for change in changeset.releases {
      if change.unit_id == unit_id &&
        change.bump != @model.None &&
        changeset.summary != "" {
        lines.push({
          changeset_id: changeset.id,
          summary: changeset.summary,
          unit_id,
          bump: change.bump,
          old_version: "",
          new_version: version,
          commit: None,
          pull_request: None,
          author: None,
        })
      }
    }
  }
  let dependencies = dependency_updates
    .filter(x => x.consumer == unit_id)
    .map(x => "`" + x.producer + "` updated to `" + x.new_requirement + "`.")
  registry.render(generator, {
    unit_id,
    version,
    date: version_date(date),
    lines,
    dependency_lines: dependencies,
    existing,
    repository,
    thanks: generator == "github",
  })
}

///|
/// Build the exact data-only contexts supplied to configured generators.
pub fn changelog_contexts(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
) -> Array[@changelog.ChangelogContext] {
  let contexts : Array[@changelog.ChangelogContext] = []
  for release in analysis.releases {
    let release_version = planned_version(
      release.new_version,
      options,
      generated_at,
    )
    let mut selected : @model.ReleaseUnit? = None
    for candidate in snapshot.units {
      if candidate.id == release.unit_id {
        selected = Some(candidate)
      }
    }
    let unit = selected.unwrap()
    let path = if unit.root == "" {
      snapshot.config.changelog_file
    } else {
      unit.root + "/" + snapshot.config.changelog_file
    }
    let lines : Array[@changelog.ReleaseLineContext] = []
    for changeset in analysis.changesets {
      for change in changeset.releases {
        if change.unit_id == unit.id &&
          change.bump != @model.None &&
          changeset.summary != "" {
          lines.push({
            changeset_id: changeset.id,
            summary: changeset.summary,
            unit_id: unit.id,
            bump: change.bump,
            old_version: release.old_version,
            new_version: release_version,
            commit: None,
            pull_request: None,
            author: None,
          })
        }
      }
    }
    let dependencies = analysis.dependency_updates
      .filter(x => x.consumer == unit.id)
      .map(x => "`" + x.producer + "` updated to `" + x.new_requirement + "`. ")
    contexts.push({
      unit_id: unit.id,
      version: release_version,
      date: version_date(generated_at),
      lines,
      dependency_lines: dependencies,
      existing: snapshot.sources.get(path).unwrap_or(""),
      repository: snapshot.config.github,
      thanks: snapshot.config.changelog == "github",
    })
  }
  contexts
}

///|
fn add_edit(
  edits : Array[@model.FileEdit],
  path : String,
  kind : String,
  owner : String,
  before : String,
  after : String,
) -> Unit {
  edits.push({
    path,
    kind,
    owner,
    before_hash: edit_hash(before),
    after_text: after,
    atomic_write: true,
  })
}

///|
/// Build all deterministic file edits needed by `version` without touching disk.
pub fn build_version_plan(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
  generators? : @changelog.GeneratorRegistry,
) -> @model.VersionPlan raise @model.MoonsetError {
  let registry = generators.unwrap_or(@changelog.GeneratorRegistry::new())
  let date = version_date(generated_at)
  let edits : Array[@model.FileEdit] = []
  let changelogs : Array[@model.ChangelogEntry] = []
  let tags : Array[@model.TagIntent] = []
  let changed_paths : Map[String, String] = Map([])
  for release in analysis.releases {
    let release_version = planned_version(
      release.new_version,
      options,
      generated_at,
    )
    let mut unit : @model.ReleaseUnit? = None
    for candidate in snapshot.units {
      if candidate.id == release.unit_id {
        unit = Some(candidate)
      }
    }
    let unit = unit.unwrap()
    let version_path = unit.version_path
    let source = snapshot.sources.get(version_path).unwrap_or("")
    let after_version = if unit.ecosystem == "moonbit" {
      let document = @manifest.parse(@manifest.Mod, source, path=unit.manifest)
      document.replace_string("version", release_version)
    } else if unit.ecosystem == "cargo" {
      replace_toml_version(source, unit.version_field, release_version)
    } else {
      replace_json_string(source, "version", release_version)
    }
    if after_version == source {
      raise @model.Invalid(
        @model.diagnostic(
          "missing-version-field",
          "Cannot locate version field",
          path=unit.manifest,
        ),
      )
    }
    if changed_paths.get(version_path) is Some(_) {
      let mut existing_edit : @model.FileEdit? = None
      for candidate in edits {
        if candidate.path == version_path && candidate.kind == "manifest" {
          existing_edit = Some(candidate)
        }
      }
      if existing_edit is Some(edit) && edit.after_text == after_version {
        ()
      } else {
        raise @model.Invalid(
          @model.diagnostic(
            "ownership-conflict",
            "Multiple release units require different versions in one manifest",
            path=version_path,
          ),
        )
      }
    } else {
      add_edit(edits, version_path, "manifest", unit.id, source, after_version)
      changed_paths[version_path] = unit.id
    }
    let mixed = snapshot.units.any(x => x.ecosystem != "moonbit")
    let tag_name = if mixed {
      unit.ecosystem + "/" + unit.native_name + "@" + release_version
    } else if snapshot.units.length() == 1 {
      "v" + release_version
    } else {
      unit.native_name + "@" + release_version
    }
    tags.push({ unit_id: unit.id, version: release_version, name: tag_name, })
    if !options.no_changelog {
      let changelog_file = snapshot.config.changelog_file
      let path = if unit.root == "" {
        changelog_file
      } else {
        unit.root + "/" + changelog_file
      }
      if changed_paths.get(path) is Some(other) && other != unit.id {
        raise @model.Invalid(
          @model.diagnostic(
            "ownership-conflict",
            "Multiple release units target the same changelog",
            path~,
          ),
        )
      }
      let existing = snapshot.sources.get(path).unwrap_or("")
      let text = render_configured_changelog(
        snapshot.config.changelog,
        unit.id,
        release_version,
        date,
        analysis.changesets,
        analysis.dependency_updates,
        existing,
        snapshot.config.github,
        registry,
      )
      changelogs.push({
        unit_id: unit.id,
        version: release_version,
        date,
        section: "builtin",
        text,
        path,
        generator: snapshot.config.changelog,
        metadata: Json::empty_object(),
      })
      add_edit(edits, path, "changelog", unit.id, existing, text)
      changed_paths[path] = unit.id
    }
  }
  let grouped_dependencies : Map[String, Array[@model.DependencyIntent]] = Map([])
  for intent in analysis.dependency_updates {
    let group = grouped_dependencies.get(intent.path).unwrap_or([])
    group.push(intent)
    grouped_dependencies[intent.path] = group
  }
  for path in grouped_dependencies.keys().collect() {
    let source = snapshot.sources.get(path).unwrap_or("")
    let intents = grouped_dependencies[path]
    intents.sort_by((a, b) => b.start.compare(a.start))
    let mut manifest_index : Int32? = None
    for index, edit in edits {
      if edit.path == path && edit.kind == "manifest" {
        manifest_index = Some(index)
      }
    }
    let mut after = match manifest_index {
      Some(index) => edits[index].after_text
      None => source
    }
    let shift = match manifest_index {
      Some(index) => {
        let changed = edits[index].after_text
        if common_prefix_length(source, changed) < intents.last().unwrap().start {
          @utf8.encode(changed).length() - @utf8.encode(source).length()
        } else {
          0
        }
      }
      None => 0
    }
    let seen_spans : Map[String, Bool] = Map([])
    for intent in intents {
      let span_key = intent.start.to_string() + ":" + intent.end.to_string()
      if seen_spans.contains(span_key) {
        continue
      }
      seen_spans[span_key] = true
      let source_bytes = @utf8.encode(source)
      if intent.start < 0 ||
        intent.end > source_bytes.length() ||
        intent.start >= intent.end {
        raise @model.Invalid(
          @model.diagnostic(
            "stale-dependency-span",
            "Dependency span is outside the manifest",
            path~,
          ),
        )
      }
      let original = @utf8.decode_lossy(source_bytes[intent.start:intent.end])
      let start = intent.start + shift
      let end = start + intent.end - intent.start
      let current_bytes = @utf8.encode(after)
      if start < 0 ||
        end > current_bytes.length() ||
        @utf8.decode_lossy(current_bytes[start:end]) != original {
        raise @model.Invalid(
          @model.diagnostic(
            "stale-dependency-span",
            "Dependency span changed before merging",
            path~,
          ),
        )
      }
      after = replace_byte_span(after, start, end, dependency_literal(intent))
    }
    match manifest_index {
      Some(index) => edits[index] = { ..edits[index], after_text: after, }
      None =>
        add_edit(edits, path, "dependency", intents[0].consumer, source, after)
    }
  }
  let consumed = analysis.changesets.map(x => x.id)
  for changeset in analysis.changesets {
    add_edit(
      edits,
      changeset.path,
      "changeset",
      "moonset",
      snapshot.sources.get(changeset.path).unwrap_or(""),
      "",
    )
  }
  let state : @model.ReleaseState = {
    plan_fingerprint: analysis.fingerprint,
    source_head: snapshot.git_head,
    releases: analysis.releases.map(release => {
      unit_id: release.unit_id,
      old_version: release.old_version,
      new_version: planned_version(release.new_version, options, generated_at),
      level: release.level,
      reasons: release.reasons,
      changesets: release.changesets,
      publish: release.publish,
    }),
    tags,
    consumed_changesets: consumed,
  }
  if !analysis.releases.is_empty() {
    let state_path = ".moonset/release-state.json"
    add_edit(
      edits,
      state_path,
      "state",
      "moonset",
      snapshot.sources.get(state_path).unwrap_or(""),
      @model.canonical_json(state.to_json()) + "\n",
    )
  }
  let plan_fingerprint = @model.fingerprint({
    "analysis": analysis.to_json(),
    "edits": edits.map(x => x.to_json()),
    "tags": tags.map(x => x.to_json()),
  })
  {
    schema_version: 1,
    stage: "version",
    executable: true,
    fingerprint: plan_fingerprint,
    edits,
    changelogs,
    tags,
    consumed_changesets: consumed,
    analysis,
    generated_at: if generated_at == "" {
      None
    } else {
      Some(generated_at)
    },
  }
}
