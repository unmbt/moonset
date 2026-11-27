///|
let cached_config_schema : Ref[Json?] = Ref(None)

///|
fn builtin_config_schema() -> Json raise @model.MoonsetError {
  match cached_config_schema.val {
    Some(schema) => schema
    None => {
      let parsed = parse_json(config_schema_text, "builtin-config-schema")
      cached_config_schema.val = Some(parsed)
      parsed
    }
  }
}

///|
fn parse_json_error_position(message : String) -> (Int32, Int32)? {
  guard message.rev_find(" at line ") is Some(line_prefix) else { return None }
  let tail = message[line_prefix + 9:].to_owned()
  guard tail.find(", column ") is Some(col_sep) else { return None }
  let line_text = tail[:col_sep].to_owned()
  let col_text = tail[col_sep + 9:].to_owned()
  fn parse_digits(s : String) -> Int32? {
    if s == "" {
      return None
    }
    let mut acc : Int32 = 0
    for ch in s.to_array() {
      if ch < '0' || ch > '9' {
        return None
      }
      acc = acc * 10 + (ch.to_int() - '0'.to_int())
    }
    Some(acc)
  }

  match (parse_digits(line_text), parse_digits(col_text)) {
    (Some(line), Some(col)) => Some((line, col + 1))
    _ => None
  }
}

///|
pub fn parse_json(
  source : String,
  path : String,
) -> Json raise @model.MoonsetError {
  let input = if source.has_prefix("\uFEFF") {
    " " + source[1:].to_owned()
  } else {
    source
  }
  @json.parse(input, reject_duplicate_keys=true) catch {
    error => {
      let message = error.to_string()
      let (line, column) = match parse_json_error_position(message) {
        Some(pos) => pos
        None =>
          (
            source.split("\n").count(),
            source.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
          )
      }
      raise @model.Invalid(
        @model.diagnostic("invalid-json", message, path~, line~, column~),
      )
    }
  }
}

///|
fn strings(value : Json) -> Array[String] {
  match value {
    Array(items) =>
      items.filter_map(x => {
        match x {
          String(s) => Some(s)
          _ => None
        }
      })
    _ => []
  }
}

///|
fn normalize_group_entry(entry : String) -> String {
  if entry.has_prefix("!") && !entry.has_prefix("!(") {
    "!" + unit_pattern_key(entry[1:].to_owned())
  } else {
    unit_pattern_key(entry)
  }
}

///|
fn groups(value : Json) -> Array[Array[String]] {
  match value {
    Array(items) => items.map(x => strings(x).map(normalize_group_entry))
    _ => []
  }
}

///|
fn validate_domain_relative_path(
  label : String,
  raw_path : String,
  config_path : String,
) -> Unit raise @model.MoonsetError {
  let normalized = raw_path.replace_all(old="\\", new="/").trim().to_owned()
  let has_drive = normalized.length() >= 2 &&
    (
      (normalized[0] >= 'A' && normalized[0] <= 'Z') ||
      (normalized[0] >= 'a' && normalized[0] <= 'z')
    ) &&
    normalized[1] == ':'
  if normalized == "" ||
    normalized.has_prefix("/") ||
    has_drive ||
    normalized.split("/").any(seg => seg.to_owned() == "..") {
    invalid(
      label + " must stay inside the release domain: " + raw_path,
      path=config_path,
      code="invalid-config",
    )
  }
}

///|
fn plugin_specs(value : Json) -> Map[String, @model.GeneratorPluginConfig] {
  let result : Map[String, @model.GeneratorPluginConfig] = Map([])
  match value {
    Object(items) =>
      for name, item in items {
        match item {
          {
            "program": String(program),
            "args": Array(args),
            "allowedPrograms": Array(allowed),
            "environment": Array(environment),
            ..
          } => {
            let argv = args.filter_map(x => {
              match x {
                String(s) => Some(s)
                _ => None
              }
            })
            let programs = allowed.filter_map(x => {
              match x {
                String(s) => Some(s)
                _ => None
              }
            })
            let env = environment.filter_map(x => {
              match x {
                String(s) => Some(s)
                _ => None
              }
            })
            let timeout_ms = match property(item, "timeoutMs") {
              Number(value, ..) => value.to_int()
              _ => 30000
            }
            let max_output_bytes = match property(item, "maxOutputBytes") {
              Number(value, ..) => value.to_int()
              _ => 1048576
            }
            result[name] = {
              program,
              args: argv,
              allowed_programs: programs,
              environment: env,
              timeout_ms,
              max_output_bytes,
            }
          }
          _ => ()
        }
      }
    _ => ()
  }
  result
}

///|
fn locate_json_path(source : String, json_path : String) -> (Int32, Int32) {
  let mut offset = 0
  for segment in json_path.split(".") {
    let raw = segment.to_owned()
    if raw == "$" || raw == "" {
      continue
    }
    let key = match raw.find("[") {
      Some(index) => raw[:index].to_owned()
      None => raw
    }
    if key == "" {
      continue
    }
    let needle = Json::string(key).stringify()
    if source[offset:].find(needle) is Some(found) {
      offset = offset + found
    }
  }
  let prefix = source[:offset].to_owned()
  (
    prefix.split("\n").count(),
    prefix.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
  )
}

///|
fn parse_artifacts_field(value : Json) -> Array[@model.ArtifactTargetSpec] {
  let specs : Array[@model.ArtifactTargetSpec] = []
  match property(value, "artifacts") {
    Array(items) =>
      for item in items {
        if item is { "target": String(target), .. } {
          let linked_package = match item {
            { "package": String(pkg), .. } => Some(canonical_id(pkg))
            _ => None
          }
          let required = match item {
            { "required": False, .. } => false
            _ => true
          }
          let path = match item {
            { "path": String(p), .. } => Some(p)
            _ => None
          }
          specs.push({ target, linked_package, required, path, })
        }
      }
    _ => ()
  }
  specs
}

///|
pub fn parse_config(
  source : String,
  path~ : String = ".changeset/config.json",
) -> @model.Config raise @model.MoonsetError {
  let raw = parse_json(source, path)
  let schema = builtin_config_schema()
  if schema_issue(raw, schema, schema, "$") is Some(issue) {
    let json_path = issue.split(":").next().unwrap_or("$").to_owned()
    let (line, column) = locate_json_path(source, json_path)
    raise @model.Invalid(
      @model.diagnostic(
        "invalid-config",
        issue,
        path~,
        line~,
        column~,
        json_path~,
      ),
    )
  }
  let defaults = @model.Config::default()
  let generators = plugin_specs(
    property(property(raw, "plugins"), "generators"),
  )
  for name, plugin in generators {
    if name.trim() == "" || !plugin.allowed_programs.contains(plugin.program) {
      invalid("Generator executable must be explicitly allowed: " + name, path~)
    }
    if plugin.timeout_ms < 1 || plugin.max_output_bytes < 1 {
      invalid(
        "Generator timeout and output limit must be positive: " + name,
        path~,
      )
    }
  }
  let fixed = groups(property(raw, "fixed"))
  let linked = groups(property(raw, "linked"))
  let ignore = strings(property(raw, "ignore")).map(normalize_group_entry)
  let occupied : Map[String, Bool] = Map([])
  for group in fixed + linked {
    for id in group {
      validate_glob_pattern(id, allow_negation=true, path~)
      if !(id.has_prefix("!") && !id.has_prefix("!(")) {
        if !has_glob_meta(id) && occupied.contains(id) {
          invalid("Overlapping or repeated version group member: " + id, path~)
        }
        occupied[id] = true
      }
    }
  }
  for id in ignore {
    validate_glob_pattern(id, allow_negation=true, path~)
  }
  let mixed_raw = property(property(raw, "experimental"), "mixedWorkspaces")
  let mixed : @model.MixedWorkspacesConfig? = if mixed_raw != Json::null() {
    let mode = match property(mixed_raw, "mode") {
      String(s) =>
        match @model.MixedMode::parse(s) {
          Some(m) => m
          None => {
            invalid("Invalid mixedWorkspaces.mode: " + s, path~)
            @model.Coexist
          }
        }
      _ => @model.Coexist
    }
    let mixed_workspaces : Array[@model.MixedWorkspaceSpec] = []
    let bridges : Array[@model.Bridge] = []
    let unit_overrides : Map[String, @model.UnitOverride] = Map([])
    let ids : Map[String, Bool] = Map([])
    match mixed_raw {
      { "workspaces": Array(workspaces), .. } =>
        for ws in workspaces {
          guard ws
            is {
              "id": String(id),
              "ecosystem": String(eco_str),
              "root": String(root),
              "manager": String(mgr_str),
              "includeRoot": include_root,
              ..
            } else {
            invalid("Invalid mixed workspace declaration", path~)
            continue
          }
          if ids.contains(id) {
            invalid("Duplicate workspace ID: " + id, path~)
          }
          guard @model.Ecosystem::parse(eco_str) is Some(ecosystem) else {
            invalid("Unsupported workspace ecosystem: " + eco_str, path~)
            continue
          }
          guard @model.PackageManager::parse(mgr_str) is Some(manager) else {
            invalid("Unsupported workspace manager: " + mgr_str, path~)
            continue
          }
          ids[id] = true
          mixed_workspaces.push({
            id,
            ecosystem,
            root,
            manager,
            include_root: include_root == Json::boolean(true),
          })
        }
      _ => invalid("Mixed workspaces require a workspaces array", path~)
    }
    match mixed_raw {
      { "bridges": Array(items), .. } =>
        for item in items {
          guard item
            is {
              "consumer": String(consumer),
              "producer": String(producer),
              "bump": String(bump),
              "waitFor": String(wait_for_str),
              ..
            } else {
            invalid("Invalid build bridge declaration", path~)
            continue
          }
          let level = match bump {
            "major" => @model.Major
            "minor" => @model.Minor
            "patch" => @model.Patch
            _ => {
              invalid("Bridge bump must be major, minor, or patch", path~)
              @model.Patch
            }
          }
          guard @model.BridgeWaitFor::parse(wait_for_str) is Some(wait_for) else {
            invalid("Bridge waitFor must be build or publish", path~)
            continue
          }
          bridges.push({ consumer, producer, bump: level, wait_for, })
        }
      _ => ()
    }
    match mixed_raw {
      { "units": Object(items), .. } =>
        for id, value in items {
          let publish = match property(value, "publish") {
            True => Some(true)
            False => Some(false)
            _ => None
          }
          let publisher = match property(value, "publisher") {
            String(name) => Some(name)
            _ => None
          }
          let tag_format = match property(value, "tagFormat") {
            String(format) => Some(format)
            _ => None
          }
          let artifacts = parse_artifacts_field(value)
          unit_overrides[canonical_id(id)] = {
            publish,
            publisher,
            tag_format,
            artifacts,
          }
        }
      _ => ()
    }
    let lockfiles = match property(mixed_raw, "lockfiles") {
      String(s) =>
        match @model.LockfileMode::parse(s) {
          Some(m) => m
          None => @model.Refresh
        }
      _ => @model.Refresh
    }
    Some({
      mode,
      workspaces: mixed_workspaces,
      bridges,
      unit_overrides,
      lockfiles,
    })
  } else {
    None
  }
  let changed_patterns = match property(raw, "changedFilePatterns") {
    Array(_) as xs => strings(xs)
    _ => defaults.changed_patterns
  }
  for pattern in changed_patterns {
    validate_glob_pattern(pattern, allow_negation=true, path~)
  }
  let formatter = match property(raw, "formatter") {
    String(s) => s
    _ => defaults.formatter
  }
  if !["builtin", "prettier", "oxfmt", "biome", "dprint"].contains(formatter) {
    invalid(
      "Unsupported formatter: " + formatter,
      path~,
      code="unsupported-capability",
    )
  }
  let format_mode = match property(raw, "format") {
    False => "false"
    String(s) => s
    _ => defaults.format_mode
  }
  if !["false", "auto", "prettier", "oxfmt", "biome", "dprint"].contains(
      format_mode,
    ) {
    invalid(
      "Unsupported format mode: " + format_mode,
      path~,
      code="unsupported-capability",
    )
  }
  if formatter != "builtin" &&
    format_mode != "auto" &&
    format_mode != "false" &&
    format_mode != formatter {
    invalid(
      "Conflicting formatter and format settings: " +
      formatter +
      " vs " +
      format_mode,
      path~,
      code="invalid-config",
    )
  }
  let changelog_raw = property(raw, "changelog")
  let changelog_enabled = changelog_raw != Json::boolean(false)
  let changelog_generator = match changelog_raw {
    False => "none"
    { "generator": String(s), .. } => s
    _ => defaults.changelog.generator
  }
  let changelog_file = match changelog_raw {
    { "file": String(file), .. } => file
    _ => defaults.changelog.file
  }
  validate_domain_relative_path("changelog.file", changelog_file, path)
  let changelog_options = property(changelog_raw, "options")
  let github_section = property(raw, "github")
  let github_repo = match property(changelog_options, "repo") {
    String(s) if s != "" => Some(s)
    _ =>
      match property(github_section, "repo") {
        String(s) if s != "" => Some(s)
        _ => None
      }
  }
  let github_links = property(github_section, "links") != Json::boolean(false)
  let github_thanks = if property(changelog_options, "disableThanks") ==
    Json::boolean(true) {
    false
  } else {
    property(github_section, "thanks") != Json::boolean(false)
  }
  let access = match property(raw, "access") {
    String(s) => @model.Access::parse(s).unwrap_or(defaults.access)
    _ => defaults.access
  }
  let base_branch = match property(raw, "baseBranch") {
    String(s) => s
    _ => defaults.base_branch
  }
  let commit_raw = property(raw, "commit")
  let commit_mode = match commit_raw {
    False => @model.Never
    { "mode": String(m), .. } =>
      @model.CommitMode::parse(m).unwrap_or(defaults.commit.mode)
    _ => defaults.commit.mode
  }
  let commit_add_message = match property(commit_raw, "addMessage") {
    String(msg) if msg.trim() != "" => msg
    _ => defaults.commit.add_message
  }
  let commit_version_message = match property(commit_raw, "versionMessage") {
    String(msg) if msg.trim() != "" => msg
    _ => defaults.commit.version_message
  }
  let publisher = property(raw, "publisher")
  let publisher_kind = match property(publisher, "kind") {
    String(kind) => kind
    _ => defaults.publisher.kind
  }
  let publisher_registry = match property(publisher, "registry") {
    String(registry) => registry
    _ => defaults.publisher.registry
  }
  let publisher_dry_run_first = property(publisher, "dryRunFirst") !=
    Json::boolean(false)
  let publisher_command = strings(property(publisher, "command"))
  let publisher_token_env = match property(publisher, "tokenEnv") {
    String(name) if name.trim() != "" => Some(name)
    _ => None
  }
  if publisher_kind == "command" && publisher_command.is_empty() {
    invalid(
      "publisher.command is required when publisher.kind is 'command'",
      path~,
    )
  }
  if publisher_registry != "default" {
    let _ = parse_target_mapping(Some(publisher_registry))
  }
  let snap_raw = property(raw, "snapshot")
  let snap_enabled = match property(snap_raw, "enabled") {
    False => false
    True => true
    _ => defaults.snapshot.enabled
  }
  let snap_use_calc = property(snap_raw, "useCalculatedVersion") ==
    Json::boolean(true)
  let snap_template = match property(snap_raw, "prereleaseTemplate") {
    String(template) => {
      validate_snapshot_template(template, path~)
      template
    }
    _ => defaults.snapshot.prerelease_template
  }
  let pre_raw = property(raw, "pre")
  let pre_file = match property(pre_raw, "file") {
    String(s) => s
    _ => defaults.pre.file
  }
  validate_domain_relative_path("pre.file", pre_file, path)
  let pre_directory = match property(pre_raw, "directory") {
    String(s) => s
    _ => defaults.pre.directory
  }
  validate_domain_relative_path("pre.directory", pre_directory, path)
  let private_raw = property(raw, "privatePackages")
  let (private_version, private_tag, private_publish) = match private_raw {
    True => (true, true, false)
    False => (false, false, false)
    Object(_) =>
      (
        property(private_raw, "version") == Json::boolean(true),
        property(private_raw, "tag") == Json::boolean(true),
        property(private_raw, "publish") == Json::boolean(true),
      )
    _ =>
      (
        defaults.private_packages.version,
        defaults.private_packages.tag,
        defaults.private_packages.publish,
      )
  }
  if !private_version && (private_tag || private_publish) {
    invalid(
      "privatePackages.tag and privatePackages.publish require privatePackages.version to be true",
      path~,
      code="invalid-config",
    )
  }
  let tag_raw = property(raw, "tag")
  let tag_create = match property(tag_raw, "create") {
    False => false
    _ => true
  }
  let tag_after_publish = match property(tag_raw, "afterPublish") {
    False => false
    _ => true
  }
  let tag_format = match property(tag_raw, "format") {
    String(format) => format
    _ => defaults.tag.format
  }
  let tag_push = property(tag_raw, "push") == Json::boolean(true)
  let update_dependents = match property(raw, "updateInternalDependents") {
    String(s) =>
      @model.UpdateDependents::parse(s).unwrap_or(defaults.update_dependents)
    _ => defaults.update_dependents
  }
  let only_peer_out_of_range = property(
      raw, "onlyUpdatePeerDependentsWhenOutOfRange",
    ) ==
    Json::boolean(true)
  let workspace_protocol_only = property(
      raw, "bumpVersionsWithWorkspaceProtocolOnly",
    ) ==
    Json::boolean(true)
  {
    fixed,
    linked,
    ignore,
    update_dependencies: if property(raw, "updateInternalDependencies") ==
      Json::string("minor") {
      @model.Minor
    } else {
      @model.Patch
    },
    update_dependents,
    only_update_peer_dependents_when_out_of_range: only_peer_out_of_range,
    bump_versions_with_workspace_protocol_only: workspace_protocol_only,
    changed_patterns,
    formatter,
    format_mode,
    access,
    base_branch,
    changelog: {
      enabled: changelog_enabled,
      generator: changelog_generator,
      file: changelog_file,
    },
    commit: {
      mode: commit_mode,
      add_message: commit_add_message,
      version_message: commit_version_message,
    },
    private_packages: {
      version: private_version,
      tag: private_tag,
      publish: private_publish,
    },
    pre: { file: pre_file, directory: pre_directory, },
    snapshot: {
      enabled: snap_enabled,
      use_calculated_version: snap_use_calc,
      prerelease_template: snap_template,
    },
    tag: {
      create: tag_create,
      after_publish: tag_after_publish,
      format: tag_format,
      push: tag_push,
    },
    publisher: {
      kind: publisher_kind,
      registry: publisher_registry,
      dry_run_first: publisher_dry_run_first,
      command: publisher_command,
      token_env: publisher_token_env,
    },
    github: { repo: github_repo, links: github_links, thanks: github_thanks, },
    generators,
    mixed,
  }
}
