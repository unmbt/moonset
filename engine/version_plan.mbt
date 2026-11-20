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
fn normalize_pre_directory(dir : String) -> String {
  let clean = dir.replace_all(old="\\", new="/").trim().to_owned()
  let stripped = if clean.has_suffix("/") {
    clean[:clean.length() - 1].to_owned()
  } else {
    clean
  }
  if stripped == "." {
    ""
  } else {
    stripped
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
fn dependency_literal(
  intent : @model.DependencyIntent,
  original : String,
) -> String {
  if intent.producer.has_prefix("cargo:") {
    return intent.new_requirement
  }
  if original.has_prefix("\"") {
    if original.contains("@") && intent.producer.has_prefix("moonbit:") {
      let producer = intent.producer[8:].to_owned()
      return quote_string(producer + "@" + intent.new_requirement)
    }
    return quote_string(intent.new_requirement)
  }
  if intent.producer.has_prefix("npm:") {
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
/// Format a Git tag name from a template (`{ecosystem}`, `{name}`, `{version}`),
/// falling back to `default_name` when template is empty or `"auto"`.
pub fn format_tag_name(
  unit_id : String,
  version : String,
  default_name : String,
  template : String,
) -> String {
  if template == "" || template == "auto" {
    return default_name
  }
  let parts = unit_id.split(":").collect()
  let ecosystem = if parts.length() > 0 {
    parts[0].to_owned()
  } else {
    "moonbit"
  }
  let name = if unit_id.find(":") is Some(index) {
    unit_id[index + 1:].to_owned()
  } else {
    unit_id
  }
  template
  .replace_all(old="{ecosystem}", new=ecosystem)
  .replace_all(old="{name}", new=name)
  .replace_all(old="{version}", new=version)
}

///|
/// Validate a rendered Git tag name against git-check-ref-format rules.
pub fn validate_git_tag_name(name : String) -> Unit raise @model.MoonsetError {
  let invalid_ctrl = name
    .to_array()
    .any(ch => {
      let code = ch.to_int()
      code < 0x20 || code == 0x7F
    })
  let bad_component = name
    .split("/")
    .any(seg => {
      let s = seg.to_owned()
      s == "" || s.has_prefix(".") || s.has_suffix(".lock")
    })
  if name == "" ||
    name == "@" ||
    invalid_ctrl ||
    bad_component ||
    name.contains(" ") ||
    name.contains("..") ||
    name.contains(":") ||
    name.contains("@{") ||
    name.contains("~") ||
    name.contains("^") ||
    name.contains("?") ||
    name.contains("*") ||
    name.contains("[") ||
    name.contains("\\") ||
    name.has_prefix("-") ||
    name.has_prefix("/") ||
    name.has_prefix(".") ||
    name.has_suffix("/") ||
    name.has_suffix(".") ||
    name.has_suffix(".lock") ||
    name.contains("//") {
    raise @model.Invalid(
      @model.diagnostic("invalid-tag", "Invalid Git tag name: " + name),
    )
  }
}

///|
fn is_hex_sha(text : String) -> Bool {
  if text.length() < 7 || text.length() > 40 {
    return false
  }
  for ch in text.to_array() {
    let ok = (ch >= '0' && ch <= '9') ||
      (ch >= 'a' && ch <= 'f') ||
      (ch >= 'A' && ch <= 'F')
    if !ok {
      return false
    }
  }
  true
}

///|
fn is_valid_github_user(text : String) -> Bool {
  if text == "" ||
    text.length() > 39 ||
    text.has_prefix("-") ||
    text.has_suffix("-") {
    return false
  }
  for ch in text.to_array() {
    let ok = (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '-' ||
      ch == '_'
    if !ok {
      return false
    }
  }
  true
}

///|
/// Extract strict `pr: #123` / `commit: <hex>` / `author: @user` metadata lines
/// from a changeset summary (aligned with @changesets/changelog-github).
/// Only strips lines whose values strictly match PR numbers, hex SHAs, or GitHub usernames,
/// leaving ordinary prose (e.g. `User: can now configure retries`) untouched.
fn extract_summary_metadata(
  summary : String,
) -> (String, String?, String?, Array[String]) {
  let mut pr : String? = None
  let mut commit : String? = None
  let authors : Array[String] = []
  let body : Array[String] = []
  let mut in_fence = false
  for raw_line in summary.replace_all(old="\r\n", new="\n").split("\n") {
    let trimmed = raw_line.trim().to_owned()
    if trimmed.has_prefix("```") || trimmed.has_prefix("~~~") {
      in_fence = !in_fence
      body.push(raw_line.to_owned())
      continue
    }
    if !in_fence {
      let lower = trimmed.to_lower()
      if (
          lower.has_prefix("pr:") ||
          lower.has_prefix("pull:") ||
          lower.has_prefix("pull request:")
        ) &&
        trimmed.find(":") is Some(colon) {
        let mut value = trimmed[colon + 1:].trim().to_owned()
        if value.has_prefix("#") {
          value = value[1:].trim().to_owned()
        }
        if is_all_ascii_digits(value) && value != "0" {
          pr = Some(value)
          continue
        }
      } else if lower.has_prefix("commit:") && trimmed.find(":") is Some(colon) {
        let value = trimmed[colon + 1:].trim().to_owned()
        if is_hex_sha(value) {
          commit = Some(value)
          continue
        }
      } else if (lower.has_prefix("author:") || lower.has_prefix("user:")) &&
        trimmed.find(":") is Some(colon) {
        let mut value = trimmed[colon + 1:].trim().to_owned()
        if value.has_prefix("@") {
          value = value[1:].trim().to_owned()
        }
        if is_valid_github_user(value) {
          if !authors.contains(value) {
            authors.push(value)
          }
          continue
        }
      }
    }
    body.push(raw_line.to_owned())
  }
  let cleaned = body.join("\n").trim().to_owned()
  (if cleaned == "" { summary } else { cleaned }, commit, pr, authors)
}

///|
fn build_changelog_context(
  unit_id : String,
  old_version : String,
  release_version : String,
  date : String,
  changesets : Array[@model.Changeset],
  direct_ids : Array[String],
  dependency_updates : Array[@model.DependencyIntent],
  existing : String,
  generator_name : String,
  repository : String?,
  links : Bool,
  thanks : Bool,
  server_url : String,
  changeset_commits : Map[String, String],
  commit_metadata~ : Map[String, (String?, String?)] = Map([]),
) -> @changelog.ChangelogContext {
  let lines : Array[@changelog.ReleaseLineContext] = []
  let parse_hints = generator_name == "git" || generator_name == "github"
  // Only include direct changesets recorded for this release (if `direct_ids` is empty,
  // this unit was bumped purely via dependency propagation, fixed group, or pre:exit).
  for changeset in changesets {
    if !direct_ids.contains(changeset.id) {
      continue
    }
    for change in changeset.releases {
      if change.unit_id == unit_id &&
        change.bump != @model.None &&
        changeset.summary != "" {
        let (clean_summary, commit_hint, pr_hint, author_hints) = if parse_hints {
          extract_summary_metadata(changeset.summary)
        } else {
          (changeset.summary, None, None, [])
        }
        let commit = match commit_hint {
          Some(c) => Some(c)
          None => changeset_commits.get(changeset.id)
        }
        let (meta_pr, meta_author) = match commit {
          Some(sha) => commit_metadata.get(sha).unwrap_or((None, None))
          None => (None, None)
        }
        let pull_request = match pr_hint {
          Some(_) => pr_hint
          None => meta_pr
        }
        let authors = author_hints.copy()
        if authors.is_empty() {
          if meta_author is Some(a) && a != "" {
            authors.push(a)
          }
        }
        lines.push({
          changeset_id: changeset.id,
          summary: clean_summary,
          unit_id,
          bump: change.bump,
          old_version,
          new_version: release_version,
          commit,
          pull_request,
          authors,
        })
      }
    }
  }
  let dep_items : Array[String] = []
  let dep_producers : Array[String] = []
  for update in dependency_updates {
    if update.consumer == unit_id {
      let display_name = match update.producer.find(":") {
        Some(idx) => update.producer[idx + 1:].to_owned()
        None => update.producer
      }
      let item = display_name + "@" + update.producer_version
      if !dep_items.contains(item) {
        dep_items.push(item)
      }
      if !dep_producers.contains(update.producer) {
        dep_producers.push(update.producer)
      }
    }
  }
  let dependencies : Array[String] = []
  if !dep_items.is_empty() {
    let dep_commit_links : Array[String] = []
    let seen_commits : Array[String] = []
    if generator_name == "git" || generator_name == "github" {
      let base_url = if server_url.has_suffix("/") {
        server_url[:server_url.length() - 1].to_owned()
      } else {
        server_url
      }
      for cs in changesets {
        if cs.releases.any(c => {
            c.bump != @model.None && dep_producers.contains(c.unit_id)
          }) {
          if changeset_commits.get(cs.id) is Some(sha) &&
            sha != "" &&
            !seen_commits.contains(sha) {
            seen_commits.push(sha)
            let short = if sha.length() > 7 { sha[:7].to_owned() } else { sha }
            let link = if links {
              match repository {
                Some(repo) if repo != "" =>
                  "[`" +
                  short +
                  "`](" +
                  base_url +
                  "/" +
                  repo +
                  "/commit/" +
                  sha +
                  ")"
                _ => "`" + short + "`"
              }
            } else {
              "`" + short + "`"
            }
            dep_commit_links.push(link)
          }
        }
      }
    }
    let header = if dep_commit_links.is_empty() {
      "Updated dependencies:"
    } else {
      "Updated dependencies [" + dep_commit_links.join(", ") + "]:"
    }
    dependencies.push(header + "\n  - " + dep_items.join("\n  - "))
  }
  {
    unit_id,
    version: release_version,
    date: version_date(date),
    lines,
    dependency_lines: dependencies,
    existing,
    repository,
    links,
    thanks,
    server_url,
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
  let direct_ids = changesets.map(c => c.id)
  let context = build_changelog_context(
    unit_id,
    "",
    version,
    date,
    changesets,
    direct_ids,
    dependency_updates,
    existing,
    "builtin",
    None,
    false,
    false,
    "https://github.com",
    Map([]),
  )
  @changelog.render(@changelog.Builtin, context)
}

///|
/// Build the exact data-only contexts supplied to configured generators, with optional commit metadata.
pub fn changelog_contexts_with_metadata(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  _options : @model.VersionOptions,
  generated_at~ : String = "",
  changeset_commits~ : Map[String, String] = Map([]),
  commit_metadata~ : Map[String, (String?, String?)] = Map([]),
  server_url~ : String = "https://github.com",
) -> Array[@changelog.ChangelogContext] {
  let contexts : Array[@changelog.ChangelogContext] = []
  let units_by_id : Map[String, @model.ReleaseUnit] = Map([])
  for u in snapshot.units {
    units_by_id[u.id] = u
  }
  for release in analysis.releases {
    guard units_by_id.get(release.unit_id) is Some(unit) else { continue }
    let path = if unit.root == "" {
      snapshot.config.changelog.file
    } else {
      unit.root + "/" + snapshot.config.changelog.file
    }
    contexts.push(
      build_changelog_context(
        unit.id,
        release.old_version,
        release.new_version,
        generated_at,
        analysis.changesets,
        release.changesets,
        analysis.dependency_updates,
        snapshot.sources.get(path).unwrap_or(""),
        snapshot.config.changelog.generator,
        snapshot.config.github.repo,
        snapshot.config.github.links,
        snapshot.config.changelog.generator == "github" &&
        snapshot.config.github.thanks,
        server_url,
        changeset_commits,
        commit_metadata~,
      ),
    )
  }
  contexts
}

///|
/// Build the exact data-only contexts supplied to configured generators.
pub fn changelog_contexts(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
  changeset_commits~ : Map[String, String] = Map([]),
) -> Array[@changelog.ChangelogContext] {
  changelog_contexts_with_metadata(
    snapshot,
    analysis,
    options,
    generated_at~,
    changeset_commits~,
  )
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
priv struct ByteEdit {
  start : Int32
  end : Int32
  replacement : String
  owner : String
}

///|
fn strip_changelog_title(document : String) -> String {
  let normalized = document.replace_all(old="\r\n", new="\n")
  if normalized.has_prefix("# Changelog\n\n") {
    normalized[13:].to_owned()
  } else if normalized.has_prefix("# Changelog\n") {
    normalized[12:].to_owned()
  } else {
    normalized
  }
}

///|
/// Build all deterministic file edits needed by `version` without touching disk.
pub fn build_version_plan(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
  generators? : @changelog.GeneratorRegistry,
  changeset_commits~ : Map[String, String] = Map([]),
) -> @model.VersionPlan raise @model.MoonsetError {
  build_version_plan_with_metadata(
    snapshot,
    analysis,
    options,
    generated_at~,
    generators?,
    changeset_commits~,
  )
}

///|
/// Build all deterministic file edits needed by `version` with optional commit PR/author metadata.
pub fn build_version_plan_with_metadata(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
  generators? : @changelog.GeneratorRegistry,
  changeset_commits~ : Map[String, String] = Map([]),
  commit_metadata~ : Map[String, (String?, String?)] = Map([]),
  server_url~ : String = "https://github.com",
) -> @model.VersionPlan raise @model.MoonsetError {
  let registry = generators.unwrap_or(@changelog.GeneratorRegistry::new())
  let date = version_date(generated_at)
  let edits : Array[@model.FileEdit] = []
  let changelogs : Array[@model.ChangelogEntry] = []
  let tags : Array[@model.TagIntent] = []
  let seen_tags : Map[String, Bool] = Map([])
  let changelog_paths_order : Array[String] = []
  let changelog_groups : Map[String, Array[@model.Release]] = Map([])
  let manifest_spans : Map[String, Array[ByteEdit]] = Map([])
  let version_targets : Map[String, String] = Map([])
  let mixed = snapshot.units.any(x => x.ecosystem != @model.MoonBit)
  let generate_changelogs = !options.no_changelog &&
    snapshot.config.changelog.enabled
  let is_snapshot = analysis.is_snapshot ||
    options.snapshot ||
    options.snapshot_tag is Some(_)
  let units_by_id : Map[String, @model.ReleaseUnit] = Map([])
  for unit in snapshot.units {
    units_by_id[unit.id] = unit
  }
  let overrides = snapshot.config.unit_overrides()
  for release in analysis.releases {
    guard units_by_id.get(release.unit_id) is Some(unit) else {
      raise @model.Invalid(
        @model.diagnostic(
          "unknown-unit",
          "Unknown release unit: " + release.unit_id,
        ),
      )
    }
    let release_version = release.new_version
    let version_path = unit.version_path
    let source = snapshot.sources.get(version_path).unwrap_or("")
    let source_bytes = @utf8.encode(source)
    guard unit.version_span is Some(vspan) &&
      vspan.start >= 0 &&
      vspan.end <= source_bytes.length() &&
      vspan.start < vspan.end else {
      raise @model.Invalid(
        @model.diagnostic(
          "missing-version-field",
          "Cannot locate version field span in manifest",
          path=unit.manifest,
        ),
      )
    }
    let original_ver_slice = @utf8.decode_lossy(
      source_bytes[vspan.start:vspan.end],
    )
    let v_rep = if unit.ecosystem == @model.Cargo {
      if original_ver_slice.has_prefix("\"") ||
        original_ver_slice.has_prefix("'") {
        quote_string(release_version)
      } else {
        release_version
      }
    } else {
      quote_string(release_version)
    }
    if version_targets.get(version_path) is Some(prev_version) {
      if prev_version != release_version {
        raise @model.Invalid(
          @model.diagnostic(
            "ownership-conflict",
            "Multiple release units require different versions in one manifest",
            path=version_path,
          ),
        )
      }
    } else {
      version_targets[version_path] = release_version
      let list = manifest_spans.get(version_path).unwrap_or([])
      list.push({
        start: vspan.start,
        end: vspan.end,
        replacement: v_rep,
        owner: unit.id,
      })
      manifest_spans[version_path] = list
    }
    // Emit Git tag intents only when tag.create is enabled, not a snapshot, and private policy permits tagging.
    let allow_tag = !is_snapshot &&
      snapshot.config.tag.create &&
      (
        unit.visibility != @model.Private ||
        snapshot.config.private_packages.tag
      )
    if allow_tag {
      let default_tag_name = if mixed {
        unit.ecosystem.text() + "/" + unit.native_name + "@" + release_version
      } else if snapshot.units.length() == 1 {
        "v" + release_version
      } else {
        unit.native_name + "@" + release_version
      }
      let unit_tag_template = match overrides.get(unit.id) {
        Some({ tag_format: Some(fmt), .. }) => fmt
        _ => snapshot.config.tag.format
      }
      let tag_name = format_tag_name(
        unit.id,
        release_version,
        default_tag_name,
        unit_tag_template,
      )
      validate_git_tag_name(tag_name)
      if seen_tags.contains(tag_name) {
        raise @model.Invalid(
          @model.diagnostic(
            "duplicate-tag",
            "Multiple release units resolve to duplicate Git tag: " + tag_name,
          ),
        )
      }
      seen_tags[tag_name] = true
      tags.push({ unit_id: unit.id, version: release_version, name: tag_name, })
    }
    if generate_changelogs {
      let changelog_file = snapshot.config.changelog.file
      let path = if unit.root == "" {
        changelog_file
      } else {
        unit.root + "/" + changelog_file
      }
      if !changelog_groups.contains(path) {
        changelog_paths_order.push(path)
      }
      let entries = changelog_groups.get(path).unwrap_or([])
      entries.push(release)
      changelog_groups[path] = entries
    }
  }

  // Render changelogs in a single pass per unit (eliminating redundant double-rendering).
  if generate_changelogs {
    for path in changelog_paths_order {
      let group = changelog_groups[path]
      let existing = snapshot.sources.get(path).unwrap_or("")
      if group.length() == 1 {
        let release = group[0]
        let ctx = build_changelog_context(
          release.unit_id,
          release.old_version,
          release.new_version,
          date,
          analysis.changesets,
          release.changesets,
          analysis.dependency_updates,
          existing,
          snapshot.config.changelog.generator,
          snapshot.config.github.repo,
          snapshot.config.github.links,
          snapshot.config.changelog.generator == "github" &&
          snapshot.config.github.thanks,
          server_url,
          changeset_commits,
          commit_metadata~,
        )
        let text = registry.render(snapshot.config.changelog.generator, ctx)
        changelogs.push({
          unit_id: release.unit_id,
          version: release.new_version,
          date,
          section: snapshot.config.changelog.generator,
          text,
          path,
          generator: snapshot.config.changelog.generator,
          metadata: Json::empty_object(),
        })
        add_edit(edits, path, "changelog", release.unit_id, existing, text)
      } else {
        let section_blocks : Array[String] = []
        for release in group {
          let single_ctx = build_changelog_context(
            release.unit_id,
            release.old_version,
            release.new_version,
            date,
            analysis.changesets,
            release.changesets,
            analysis.dependency_updates,
            "",
            snapshot.config.changelog.generator,
            snapshot.config.github.repo,
            snapshot.config.github.links,
            snapshot.config.changelog.generator == "github" &&
            snapshot.config.github.thanks,
            server_url,
            changeset_commits,
            commit_metadata~,
          )
          let rendered_single = registry.render(
            snapshot.config.changelog.generator,
            single_ctx,
          )
          let stripped = strip_changelog_title(rendered_single)
          let heading_prefix = "## " + release.new_version
          let annotated = if stripped.has_prefix(heading_prefix) {
            "## " +
            release.unit_id +
            " - " +
            release.new_version +
            stripped[heading_prefix.length():].to_owned()
          } else {
            "## " +
            release.unit_id +
            " - " +
            release.new_version +
            "\n\n" +
            stripped
          }
          section_blocks.push(annotated.trim().to_owned())
        }
        let combined_section = section_blocks.join("\n\n")
        let full_text = @changelog.splice_changelog_entry(
          existing, combined_section,
        )
        for release in group {
          changelogs.push({
            unit_id: release.unit_id,
            version: release.new_version,
            date,
            section: snapshot.config.changelog.generator,
            text: full_text,
            path,
            generator: snapshot.config.changelog.generator,
            metadata: Json::empty_object(),
          })
        }
        add_edit(edits, path, "changelog", "moonset", existing, full_text)
      }
    }
  }

  for intent in analysis.dependency_updates {
    let source = snapshot.sources.get(intent.path).unwrap_or("")
    let source_bytes = @utf8.encode(source)
    let span_start = intent.start
    let span_end = intent.end
    if span_start < 0 ||
      span_end > source_bytes.length() ||
      span_start >= span_end {
      raise @model.Invalid(
        @model.diagnostic(
          "stale-dependency-span",
          "Dependency span is outside the manifest",
          path=intent.path,
        ),
      )
    }
    let original = @utf8.decode_lossy(source_bytes[span_start:span_end])
    let list = manifest_spans.get(intent.path).unwrap_or([])
    if !list.any(x => x.start == span_start && x.end == span_end) {
      list.push({
        start: span_start,
        end: span_end,
        replacement: dependency_literal(intent, original),
        owner: intent.consumer,
      })
      manifest_spans[intent.path] = list
    }
  }
  let manifest_paths = manifest_spans.keys().collect()
  manifest_paths.sort()
  for path in manifest_paths {
    let source = snapshot.sources.get(path).unwrap_or("")
    let spans = manifest_spans[path]
    spans.sort_by((a, b) => b.start.compare(a.start))
    let mut after = source
    let mut prev_start = @utf8.encode(source).length() + 1
    for item in spans {
      if item.end > prev_start {
        raise @model.Invalid(
          @model.diagnostic(
            "stale-dependency-span",
            "Overlapping manifest byte spans",
            path~,
          ),
        )
      }
      prev_start = item.start
      after = replace_byte_span(after, item.start, item.end, item.replacement)
    }
    let kind = if version_targets.contains(path) {
      "manifest"
    } else {
      "dependency"
    }
    let owner = spans.last().map(x => x.owner).unwrap_or("moonset")
    add_edit(edits, path, kind, owner, source, after)
  }

  // `analysis.changesets` already excludes ignored-only changesets and already-consumed pre changesets.
  let consumed = if is_snapshot {
    []
  } else {
    analysis.changesets.map(x => x.id)
  }
  if !is_snapshot {
    match analysis.next_pre_state {
      Some(next_pre) =>
        if !analysis.releases.is_empty() || !analysis.changesets.is_empty() {
          add_edit(
            edits,
            snapshot.config.pre.file,
            "state",
            "moonset",
            snapshot.sources.get(snapshot.config.pre.file).unwrap_or(""),
            next_pre.to_json().stringify(indent=2) + "\n",
          )
          let pre_dir = normalize_pre_directory(snapshot.config.pre.directory)
          if pre_dir != "" {
            for changeset in analysis.changesets {
              let target_path = pre_dir + "/" + changeset.id + ".md"
              if changeset.path != target_path {
                if snapshot.sources.get(changeset.path) is Some(content) &&
                  content != "" {
                  add_edit(
                    edits,
                    target_path,
                    "changeset",
                    "moonset",
                    snapshot.sources.get(target_path).unwrap_or(""),
                    content,
                  )
                  add_edit(
                    edits,
                    changeset.path,
                    "changeset",
                    "moonset",
                    content,
                    "",
                  )
                }
              }
            }
          }
        }
      None => {
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
        if snapshot.sources.contains(snapshot.config.pre.file) {
          add_edit(
            edits,
            snapshot.config.pre.file,
            "state",
            "moonset",
            snapshot.sources.get(snapshot.config.pre.file).unwrap_or(""),
            "",
          )
        }
      }
    }
  }

  let include_dag = has_artifact_specs(snapshot.config) ||
    !snapshot.config.bridges().is_empty()
  let dag_opt = if include_dag {
    Some(build_execution_dag(snapshot, analysis))
  } else {
    None
  }
  let state : @model.ReleaseState = {
    plan_fingerprint: analysis.fingerprint,
    source_head: snapshot.git_head,
    is_snapshot,
    releases: analysis.releases,
    tags,
    consumed_changesets: consumed,
  }
  if !analysis.releases.is_empty() {
    let state_path = ".moonset/release-state.json"
    let state_json : Json = match dag_opt {
      Some(dag) => {
        let base = state.to_json()
        match base {
          Object(fields) => {
            fields["artifacts"] = Json::array(
              dag.artifacts.map(x => x.to_json()),
            )
            fields["executionGraph"] = {
              "buildNodes": dag.build_nodes.map(x => x.to_json()),
              "publishNodes": dag.publish_nodes.map(x => x.to_json()),
              "publishOrder": dag.publish_order.map(Json::string),
            }
            Json::object(fields)
          }
          _ => base
        }
      }
      None => state.to_json()
    }
    add_edit(
      edits,
      state_path,
      "state",
      "moonset",
      snapshot.sources.get(state_path).unwrap_or(""),
      @model.canonical_json(state_json) + "\n",
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
