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
      let (line, column) = match error {
        @json.DuplicateKey(pos, _)
        | @json.InvalidChar(pos, _)
        | @json.InvalidIdentEscape(pos)
        | @json.InvalidNumber(pos, _) => (pos.line, pos.column + 1)
        _ =>
          (
            source.split("\n").count(),
            source.split("\n").last().map(x => x.length() + 1).unwrap_or(1),
          )
      }
      raise @model.Invalid(
        @model.diagnostic(
          "invalid-json",
          error.to_string(),
          path~,
          line~,
          column~,
        ),
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
fn groups(value : Json) -> Array[Array[String]] {
  match value {
    Array(items) => items.map(x => strings(x).map(canonical_id))
    _ => []
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
pub fn parse_config(
  source : String,
  path~ : String = ".changeset/config.json",
) -> @model.Config raise @model.MoonsetError {
  let raw = parse_json(source, path)
  let schema = parse_json(config_schema_text, "builtin-config-schema")
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
  let ignore = strings(property(raw, "ignore")).map(canonical_id)
  let occupied : Map[String, Bool] = Map([])
  for group in fixed + linked {
    for id in group {
      if occupied.contains(id) {
        invalid("Overlapping or repeated version group member: " + id, path~)
      }
      occupied[id] = true
    }
  }
  for id in occupied.keys().collect() + ignore {
    validate_glob_pattern(id, allow_negation=false, path~)
  }
  let mixed = property(property(raw, "experimental"), "mixedWorkspaces")
  let mixed_workspaces : Array[@model.MixedWorkspaceSpec] = []
  let bridges : Array[@model.Bridge] = []
  let unit_overrides : Map[String, @model.UnitOverride] = Map([])
  if mixed != Json::null() {
    let ids : Map[String, Bool] = Map([])
    match mixed {
      { "workspaces": Array(workspaces), .. } =>
        for ws in workspaces {
          guard ws
            is {
              "id": String(id),
              "ecosystem": String(ecosystem),
              "root": String(root),
              "manager": String(manager),
              "includeRoot": include_root,
              ..
            } else {
            invalid("Invalid mixed workspace declaration", path~)
            continue
          }
          if ids.contains(id) {
            invalid("Duplicate workspace ID: " + id, path~)
          }
          if !["moon", "npm", "pnpm", "cargo"].contains(manager) {
            invalid("Unsupported workspace manager: " + manager, path~)
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
    match mixed {
      { "bridges": Array(items), .. } =>
        for item in items {
          guard item
            is {
              "consumer": String(consumer),
              "producer": String(producer),
              "bump": String(bump),
              "waitFor": String(wait_for),
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
          if !["build", "publish"].contains(wait_for) {
            invalid("Bridge waitFor must be build or publish", path~)
          }
          bridges.push({ consumer, producer, bump: level, wait_for, })
        }
      _ => ()
    }
    match mixed {
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
          unit_overrides[id] = { publish, publisher, tag_format, }
        }
      _ => ()
    }
  }
  let changed_patterns = match property(raw, "changedFilePatterns") {
    Array(_) as xs => strings(xs)
    _ => defaults.changed_patterns
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
  let changelog = match changelog_raw {
    False => "none"
    String(s) => s
    { "generator": String(s), .. } => s
    _ => defaults.changelog
  }
  let changelog_file = match changelog_raw {
    { "file": String(file), .. } => file
    _ => defaults.changelog_file
  }
  let changelog_options = property(changelog_raw, "options")
  let github_section = property(raw, "github")
  let github = match property(changelog_options, "repo") {
    String(s) if s != "" => Some(s)
    _ =>
      match property(github_section, "repo") {
        String(s) if s != "" => Some(s)
        _ =>
          match property(changelog_raw, "repo") {
            String(s) if s != "" => Some(s)
            _ => None
          }
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
    String(s) => s
    _ => defaults.access
  }
  let base_branch = match property(raw, "baseBranch") {
    String(s) => s
    _ => defaults.base_branch
  }
  let commit_raw = property(raw, "commit")
  let commit_mode = match commit_raw {
    False => "never"
    { "mode": String(mode), .. } => mode
    _ => defaults.commit_mode
  }
  let commit_add_message = match property(commit_raw, "addMessage") {
    String(msg) if msg.trim() != "" => msg
    _ => defaults.commit_add_message
  }
  let commit_version_message = match property(commit_raw, "versionMessage") {
    String(msg) if msg.trim() != "" => msg
    _ => defaults.commit_version_message
  }
  let publisher = property(raw, "publisher")
  let publisher_kind = match property(publisher, "kind") {
    String(kind) => kind
    _ => defaults.publisher_kind
  }
  let publisher_registry = match property(publisher, "registry") {
    String(registry) => registry
    _ => defaults.publisher_registry
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
  match property(property(raw, "snapshot"), "prereleaseTemplate") {
    String(template) => validate_snapshot_template(template, path~)
    _ => ()
  }
  let pre_directory = match property(property(raw, "pre"), "directory") {
    String(s) => s
    _ => defaults.pre_directory
  }
  let normalized_pre_dir = pre_directory.replace_all(old="\\", new="/")
  if normalized_pre_dir.has_prefix("/") ||
    normalized_pre_dir.split("/").any(seg => seg.to_owned() == "..") {
    invalid(
      "pre.directory must stay inside the release domain: " + pre_directory,
      path~,
      code="invalid-config",
    )
  }
  let private_packages = property(raw, "privatePackages")
  let private_version = property(private_packages, "version") ==
    Json::boolean(true)
  let private_tag = property(private_packages, "tag") == Json::boolean(true)
  let private_publish = property(private_packages, "publish") ==
    Json::boolean(true)
  let tag = property(raw, "tag")
  let tag_create = match property(tag, "create") {
    False => false
    _ => true
  }
  let tag_after_publish = match property(tag, "afterPublish") {
    False => false
    _ => true
  }
  let tag_format = match property(tag, "format") {
    String(format) => format
    _ => defaults.tag_format
  }
  let tag_push = property(tag, "push") == Json::boolean(true)
  let lockfiles = match mixed {
    { "lockfiles": String(mode), .. } => mode
    _ => defaults.lockfiles
  }
  for pattern in changed_patterns {
    validate_glob_pattern(pattern, allow_negation=true, path~)
  }
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
    update_dependents: match property(raw, "updateInternalDependents") {
      String(s) => s
      _ => defaults.update_dependents
    },
    changed_patterns,
    pre_file: match property(property(raw, "pre"), "file") {
      String(s) => s
      _ => defaults.pre_file
    },
    pre_directory,
    mixed: mixed != Json::null(),
    formatter,
    format_mode,
    changelog_enabled,
    changelog,
    github,
    github_links,
    github_thanks,
    access,
    base_branch,
    commit_mode,
    commit_add_message,
    commit_version_message,
    private_version,
    private_tag,
    private_publish,
    changelog_file,
    tag_create,
    tag_after_publish,
    tag_format,
    tag_push,
    publisher_kind,
    publisher_registry,
    publisher_dry_run_first,
    publisher_command,
    publisher_token_env,
    lockfiles,
    mixed_workspaces,
    bridges,
    unit_overrides,
    generators,
    raw,
  }
}
