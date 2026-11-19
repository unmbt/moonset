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
  snapshot : @model.WorkspaceSnapshot,
  base : String,
  options : @model.VersionOptions,
  generated_at : String,
) -> String raise @model.MoonsetError {
  match options.snapshot_tag {
    None => base
    Some(tag) => {
      let snap_cfg = parse_snapshot_config(snapshot.config)
      render_snapshot_version(
        base,
        tag,
        snap_cfg,
        generated_at~,
        git_head?=snapshot.git_head,
      )
    }
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
fn skip_json_ws(bytes : Bytes, index : Int32) -> Int32 {
  let mut i = index
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
      i += 1
    } else {
      break
    }
  }
  i
}

///|
fn scan_json_string_end(bytes : Bytes, start_quote : Int32) -> Int32? {
  let mut i = start_quote + 1
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x5C {
      i += 2
      continue
    }
    if b == 0x22 {
      return Some(i + 1)
    }
    i += 1
  }
  None
}

///|
/// Find the UTF-8 byte span (including quotes) of a JSON string field at depth 1
/// or inside a named depth-1 object section (e.g. "dependencies").
fn find_json_string_span(
  source : String,
  section : String?,
  key : String,
) -> (Int32, Int32)? {
  let bytes = @utf8.encode(source)
  let mut depth = 0
  let mut active_section = ""
  let mut i : Int32 = 0
  while i < bytes.length() {
    let b = bytes[i].to_int()
    if b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D {
      i += 1
      continue
    }
    if b == 0x7B || b == 0x5B {
      depth += 1
      i += 1
      continue
    }
    if b == 0x7D || b == 0x5D {
      if depth == 2 {
        active_section = ""
      }
      depth -= 1
      i += 1
      continue
    }
    if b == 0x22 {
      guard scan_json_string_end(bytes, i) is Some(str_end) else { return None }
      let raw_lit = @utf8.decode_lossy(bytes[i:str_end])
      let parsed_key = @json.parse(raw_lit) catch { _ => Json::null() }
      let after_ws = skip_json_ws(bytes, str_end)
      if after_ws < bytes.length() && bytes[after_ws].to_int() == 0x3A {
        let val_start = skip_json_ws(bytes, after_ws + 1)
        if parsed_key is String(field_name) {
          if section is None && depth == 1 && field_name == key {
            if val_start < bytes.length() && bytes[val_start].to_int() == 0x22 {
              guard scan_json_string_end(bytes, val_start) is Some(val_end) else {
                return None
              }
              return Some((val_start, val_end))
            }
          } else if section is Some(sec) {
            if depth == 1 &&
              val_start < bytes.length() &&
              bytes[val_start].to_int() == 0x7B {
              active_section = field_name
            } else if depth == 2 &&
              active_section == sec &&
              field_name == key &&
              val_start < bytes.length() &&
              bytes[val_start].to_int() == 0x22 {
              guard scan_json_string_end(bytes, val_start) is Some(val_end) else {
                return None
              }
              return Some((val_start, val_end))
            }
          }
        }
      }
      i = str_end
      continue
    }
    i += 1
  }
  None
}

///|
fn strip_toml_comment(line : String) -> String {
  let mut in_double = false
  let mut in_single = false
  let mut escaped = false
  let chars = line.to_array()
  let out : Array[Char] = []
  for ch in chars {
    if escaped {
      out.push(ch)
      escaped = false
      continue
    }
    if in_double && ch == '\\' {
      out.push(ch)
      escaped = true
      continue
    }
    if !in_single && ch == '"' {
      in_double = !in_double
      out.push(ch)
      continue
    }
    if !in_double && ch == '\'' {
      in_single = !in_single
      out.push(ch)
      continue
    }
    if !in_double && !in_single && ch == '#' {
      break
    }
    out.push(ch)
  }
  String::from_array(out)
}

///|
fn find_toml_version_span(source : String, section : String) -> (Int32, Int32)? {
  let bytes = @utf8.encode(source)
  let mut active = ""
  let mut pos : Int32 = 0
  while pos <= bytes.length() {
    let mut nl = pos
    while nl < bytes.length() && bytes[nl].to_int() != 0x0A {
      nl += 1
    }
    let line_end = if nl > pos && bytes[nl - 1].to_int() == 0x0D {
      nl - 1
    } else {
      nl
    }
    let line_text = @utf8.decode_lossy(bytes[pos:line_end])
    let clean = strip_toml_comment(line_text).trim().to_owned()
    if clean.has_prefix("[") && clean.has_suffix("]") {
      active = clean[1:clean.length() - 1].trim().to_owned()
    } else if active == section && clean.has_prefix("version") {
      let rest = clean[7:].trim().to_owned()
      if rest.has_prefix("=") {
        let mut idx = pos
        while idx < line_end && bytes[idx].to_int() != 0x3D {
          idx += 1
        }
        if idx < line_end {
          let mut q_idx = idx + 1
          while q_idx < line_end &&
                (bytes[q_idx].to_int() == 0x20 || bytes[q_idx].to_int() == 0x09) {
            q_idx += 1
          }
          if q_idx < line_end &&
            (bytes[q_idx].to_int() == 0x22 || bytes[q_idx].to_int() == 0x27) {
            let quote = bytes[q_idx].to_int()
            let val_start = q_idx + 1
            let mut val_end = val_start
            while val_end < line_end && bytes[val_end].to_int() != quote {
              if quote == 0x22 && bytes[val_end].to_int() == 0x5C {
                val_end += 2
              } else {
                val_end += 1
              }
            }
            if val_end < line_end {
              return Some((val_start, val_end))
            }
          }
        }
      }
    }
    if nl >= bytes.length() {
      break
    }
    pos = nl + 1
  }
  None
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
  if name == "" ||
    name.contains(" ") ||
    name.contains("\t") ||
    name.contains("\n") ||
    name.contains("\r") ||
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
/// Extract optional `pr:` / `commit:` / `author:` hint lines from a changeset
/// summary while keeping non-metadata Markdown lines intact.
fn extract_summary_metadata(
  summary : String,
) -> (String, String?, String?, String?) {
  let mut pr : String? = None
  let mut commit : String? = None
  let mut author : String? = None
  let body : Array[String] = []
  for raw_line in summary.replace_all(old="\r\n", new="\n").split("\n") {
    let trimmed = raw_line.trim().to_owned()
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
      if value != "" {
        pr = Some(value)
        continue
      }
    } else if lower.has_prefix("commit:") && trimmed.find(":") is Some(colon) {
      let value = trimmed[colon + 1:].trim().to_owned()
      if value != "" {
        commit = Some(value)
        continue
      }
    } else if (lower.has_prefix("author:") || lower.has_prefix("user:")) &&
      trimmed.find(":") is Some(colon) {
      let mut value = trimmed[colon + 1:].trim().to_owned()
      if value.has_prefix("@") {
        value = value[1:].trim().to_owned()
      }
      if value != "" {
        author = Some(value)
        continue
      }
    }
    body.push(raw_line.to_owned())
  }
  let cleaned = body.join("\n").trim().to_owned()
  (if cleaned == "" { summary } else { cleaned }, commit, pr, author)
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
  repository : String?,
  thanks : Bool,
  changeset_commits : Map[String, String],
  commit_metadata~ : Map[String, (String?, String?)] = Map([]),
) -> @changelog.ChangelogContext {
  let lines : Array[@changelog.ReleaseLineContext] = []
  for changeset in changesets {
    if !direct_ids.is_empty() && !direct_ids.contains(changeset.id) {
      continue
    }
    for change in changeset.releases {
      if change.unit_id == unit_id &&
        change.bump != @model.None &&
        changeset.summary != "" {
        let (clean_summary, commit_hint, pr_hint, author_hint) = extract_summary_metadata(
          changeset.summary,
        )
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
        let author = match author_hint {
          Some(_) => author_hint
          None => meta_author
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
          author,
        })
      }
    }
  }
  let dependencies : Array[String] = []
  for update in dependency_updates {
    if update.consumer == unit_id {
      let line = "`" +
        update.producer +
        "` updated to `" +
        update.new_requirement +
        "`."
      if !dependencies.contains(line) {
        dependencies.push(line)
      }
    }
  }
  {
    unit_id,
    version: release_version,
    date: version_date(date),
    lines,
    dependency_lines: dependencies,
    existing,
    repository,
    thanks,
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
  let context = build_changelog_context(
    unit_id,
    "",
    version,
    date,
    changesets,
    [],
    dependency_updates,
    existing,
    None,
    false,
    Map([]),
  )
  @changelog.render(@changelog.Builtin, context)
}

///|
/// Build the exact data-only contexts supplied to configured generators, with optional commit metadata.
pub fn changelog_contexts_with_metadata(
  snapshot : @model.WorkspaceSnapshot,
  analysis : @model.ReleasePlan,
  options : @model.VersionOptions,
  generated_at~ : String = "",
  changeset_commits~ : Map[String, String] = Map([]),
  commit_metadata~ : Map[String, (String?, String?)] = Map([]),
) -> Array[@changelog.ChangelogContext] {
  let contexts : Array[@changelog.ChangelogContext] = []
  for release in analysis.releases {
    let release_version = planned_version(
      snapshot,
      release.new_version,
      options,
      generated_at,
    ) catch {
      _ => release.new_version
    }
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
    contexts.push(
      build_changelog_context(
        unit.id,
        release.old_version,
        release_version,
        generated_at,
        analysis.changesets,
        release.changesets,
        analysis.dependency_updates,
        snapshot.sources.get(path).unwrap_or(""),
        snapshot.config.github,
        snapshot.config.changelog == "github" && snapshot.config.github_thanks,
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
fn prepend_changelog_sections(existing : String, section : String) -> String {
  if existing == "" {
    return "# Changelog\n\n" + section.trim().to_owned() + "\n"
  }
  let normalized = existing.replace_all(old="\r\n", new="\n")
  let body = section.trim().to_owned() + "\n"
  if normalized.has_prefix("# Changelog") {
    match normalized.find("\n") {
      Some(nl) => {
        let head = normalized[:nl + 1].to_owned()
        let tail = normalized[nl + 1:].trim_start().to_owned()
        if tail == "" {
          head + "\n" + body
        } else {
          head + "\n" + body + "\n" + tail
        }
      }
      None => normalized + "\n\n" + body
    }
  } else {
    "# Changelog\n\n" + body + "\n" + normalized
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
) -> @model.VersionPlan raise @model.MoonsetError {
  let registry = generators.unwrap_or(@changelog.GeneratorRegistry::new())
  let date = version_date(generated_at)
  let edits : Array[@model.FileEdit] = []
  let changelogs : Array[@model.ChangelogEntry] = []
  let tags : Array[@model.TagIntent] = []
  let seen_tags : Map[String, Bool] = Map([])
  let changelog_paths_order : Array[String] = []
  let changelog_groups : Map[String, Array[(String, String, String)]] = Map([])
  let manifest_spans : Map[String, Array[ByteEdit]] = Map([])
  let version_targets : Map[String, String] = Map([])
  let mixed = snapshot.units.any(x => x.ecosystem != "moonbit")
  let generate_changelogs = !options.no_changelog &&
    snapshot.config.changelog_enabled
  let is_snapshot = options.snapshot_tag is Some(_)
  if options.snapshot_tag is Some(tag) {
    let snap_cfg = parse_snapshot_config(snapshot.config)
    if !snap_cfg.enabled {
      invalid(
        "Snapshot releases are disabled by configuration; set snapshot.enabled to true",
        code="snapshot-disabled",
      )
    }
    if tag.trim() == "" {
      invalid("Snapshot tag cannot be empty", code="invalid-input")
    }
    validate_snapshot_template(snap_cfg.prerelease_template)
  }
  let release_versions_override : Map[String, String] = Map([])
  let units_by_id : Map[String, @model.ReleaseUnit] = Map([])
  for unit in snapshot.units {
    units_by_id[unit.id] = unit
  }
  for release in analysis.releases {
    let release_version = planned_version(
      snapshot,
      release.new_version,
      options,
      generated_at,
    )
    release_versions_override[release.unit_id] = release_version
    let unit = units_by_id[release.unit_id]
    let version_path = unit.version_path
    let source = snapshot.sources.get(version_path).unwrap_or("")
    let span_and_lit : (Int32, Int32, String)? = if unit.ecosystem == "moonbit" {
      let document = @manifest.parse(@manifest.Mod, source, path=unit.manifest)
      match document.string_field("version") {
        Some(field) =>
          Some(
            (field.span.start, field.span.end, quote_string(release_version)),
          )
        None => None
      }
    } else if unit.ecosystem == "cargo" {
      match find_toml_version_span(source, unit.version_field) {
        Some((start, end)) => Some((start, end, release_version))
        None => None
      }
    } else {
      match find_json_string_span(source, None, "version") {
        Some((start, end)) => Some((start, end, quote_string(release_version)))
        None => None
      }
    }
    guard span_and_lit is Some((v_start, v_end, v_rep)) else {
      raise @model.Invalid(
        @model.diagnostic(
          "missing-version-field",
          "Cannot locate version field",
          path=unit.manifest,
        ),
      )
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
        start: v_start,
        end: v_end,
        replacement: v_rep,
        owner: unit.id,
      })
      manifest_spans[version_path] = list
    }
    let default_tag_name = if mixed {
      unit.ecosystem + "/" + unit.native_name + "@" + release_version
    } else if snapshot.units.length() == 1 {
      "v" + release_version
    } else {
      unit.native_name + "@" + release_version
    }
    let unit_tag_template = match snapshot.config.unit_overrides.get(unit.id) {
      Some({ tag_format: Some(fmt), .. }) => fmt
      _ => snapshot.config.tag_format
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
    if generate_changelogs {
      let changelog_file = snapshot.config.changelog_file
      let path = if unit.root == "" {
        changelog_file
      } else {
        unit.root + "/" + changelog_file
      }
      let existing = snapshot.sources.get(path).unwrap_or("")
      let context = build_changelog_context(
        unit.id,
        release.old_version,
        release_version,
        date,
        analysis.changesets,
        release.changesets,
        analysis.dependency_updates,
        existing,
        snapshot.config.github,
        snapshot.config.changelog == "github" && snapshot.config.github_thanks,
        changeset_commits,
        commit_metadata~,
      )
      let unit_doc = registry.render(snapshot.config.changelog, context)
      if !changelog_groups.contains(path) {
        changelog_paths_order.push(path)
      }
      let entries = changelog_groups.get(path).unwrap_or([])
      entries.push((unit.id, release_version, unit_doc))
      changelog_groups[path] = entries
    }
  }
  if generate_changelogs {
    for path in changelog_paths_order {
      let group = changelog_groups[path]
      let existing = snapshot.sources.get(path).unwrap_or("")
      if group.length() == 1 {
        let (unit_id, release_version, text) = group[0]
        changelogs.push({
          unit_id,
          version: release_version,
          date,
          section: snapshot.config.changelog,
          text,
          path,
          generator: snapshot.config.changelog,
          metadata: Json::empty_object(),
        })
        add_edit(edits, path, "changelog", unit_id, existing, text)
      } else {
        let section_blocks : Array[String] = []
        for entry in group {
          let (unit_id, release_version, _) = entry
          let mut selected : @model.Release? = None
          for rel in analysis.releases {
            if rel.unit_id == unit_id {
              selected = Some(rel)
            }
          }
          let old_ver = selected.map(r => r.old_version).unwrap_or("")
          let direct_ids = selected.map(r => r.changesets).unwrap_or([])
          let single_ctx = build_changelog_context(
            unit_id,
            old_ver,
            release_version,
            date,
            analysis.changesets,
            direct_ids,
            analysis.dependency_updates,
            "",
            snapshot.config.github,
            snapshot.config.changelog == "github" &&
            snapshot.config.github_thanks,
            changeset_commits,
            commit_metadata~,
          )
          let rendered_single = registry.render(
            snapshot.config.changelog,
            single_ctx,
          )
          let stripped = strip_changelog_title(rendered_single)
          let heading_prefix = "## " + release_version
          let annotated = if stripped.has_prefix(heading_prefix) {
            "## " +
            unit_id +
            " - " +
            release_version +
            stripped[heading_prefix.length():].to_owned()
          } else {
            "### " + unit_id + "\n\n" + stripped
          }
          section_blocks.push(annotated.trim().to_owned())
        }
        let combined_section = section_blocks.join("\n\n")
        let full_text = prepend_changelog_sections(existing, combined_section)
        for entry in group {
          let (unit_id, release_version, _) = entry
          changelogs.push({
            unit_id,
            version: release_version,
            date,
            section: snapshot.config.changelog,
            text: full_text,
            path,
            generator: snapshot.config.changelog,
            metadata: Json::empty_object(),
          })
        }
        add_edit(edits, path, "changelog", "moonset", existing, full_text)
      }
    }
  }
  for raw_intent in analysis.dependency_updates {
    let intent : @model.DependencyIntent = if is_snapshot {
      match release_versions_override.get(raw_intent.producer) {
        Some(snap_ver) => {
          let consumer_eco = units_by_id
            .get(raw_intent.consumer)
            .map(u => u.ecosystem)
            .unwrap_or("moonbit")
          let rewritten = rewrite_ecosystem_range(
            consumer_eco,
            raw_intent.old_requirement,
            snap_ver,
          ) catch {
            _ => snap_ver
          }
          { ..raw_intent, new_requirement: rewritten, }
        }
        None => raw_intent
      }
    } else {
      raw_intent
    }
    let source = snapshot.sources.get(intent.path).unwrap_or("")
    let source_bytes = @utf8.encode(source)
    let (span_start, span_end) = if intent.start == 0 &&
      intent.end == 0 &&
      intent.producer.has_prefix("npm:") {
      let pkg = intent.producer[4:].to_owned()
      let mut found : (Int32, Int32)? = None
      for sec in ["dependencies", "peerDependencies", "optionalDependencies"] {
        if found is None {
          found = find_json_string_span(source, Some(sec), pkg)
        }
      }
      found.unwrap_or((intent.start, intent.end))
    } else {
      (intent.start, intent.end)
    }
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
  let consumed = if is_snapshot {
    []
  } else {
    analysis.changesets.map(x => x.id)
  }
  if !is_snapshot {
    match analysis.next_pre_state {
      Some(next_pre) =>
        if !analysis.releases.is_empty() {
          add_edit(
            edits,
            snapshot.config.pre_file,
            "state",
            "moonset",
            snapshot.sources.get(snapshot.config.pre_file).unwrap_or(""),
            next_pre.to_json().stringify(indent=2) + "\n",
          )
          let pre_dir = normalize_pre_directory(snapshot.config.pre_directory)
          if pre_dir != "" {
            for changeset in analysis.changesets {
              if next_pre.consumed.contains(changeset.id) {
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
        if snapshot.sources.contains(snapshot.config.pre_file) {
          add_edit(
            edits,
            snapshot.config.pre_file,
            "state",
            "moonset",
            snapshot.sources.get(snapshot.config.pre_file).unwrap_or(""),
            "",
          )
        }
      }
    }
  }
  let include_dag = has_artifact_specs(snapshot.config) ||
    !snapshot.config.bridges.is_empty()
  let dag_opt = if include_dag {
    Some(build_execution_dag(snapshot, analysis, release_versions_override~))
  } else {
    None
  }
  let state : @model.ReleaseState = {
    plan_fingerprint: analysis.fingerprint,
    source_head: snapshot.git_head,
    releases: analysis.releases.map(release => {
      unit_id: release.unit_id,
      old_version: release.old_version,
      new_version: release_versions_override
      .get(release.unit_id)
      .unwrap_or(release.new_version),
      level: release.level,
      reasons: release.reasons,
      changesets: release.changesets,
      publish: release.publish,
    }),
    tags,
    consumed_changesets: consumed,
  }
  if !analysis.releases.is_empty() && !is_snapshot {
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
