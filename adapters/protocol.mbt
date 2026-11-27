///|
/// Versioned JSONL request shared by generator and publisher plugins.
pub(all) struct JsonlRequest {
  schema_version : Int32
  protocol_method : String
  payload : Json
}

///|
pub(all) struct JsonlResponse {
  ok : Bool
  result : Json
  error : String?
}

///|
pub(all) struct PluginSpec {
  program : String
  args : Array[String]
  cwd : String?
  timeout_ms : Int32
  max_output_bytes : Int32
  allowed_programs : Array[String]
  environment : Map[String, String]
}

///|
/// Host process result; stderr is diagnostic-only and never part of a result.
pub(all) struct ProcessResult {
  exit_code : Int32
  stdout : String
  stderr : String
}

///|
/// Injectable registry queries and publication port; credentials remain host-owned.
pub(all) struct RegistryHost {
  already_published : (String, String, String) -> Bool raise @model.MoonsetError
  preflight : (String, String, String) -> Unit raise @model.MoonsetError
  publish : (String, String, String) -> String raise @model.MoonsetError
}

///|
pub(open) trait PublisherPort {
  fn already_published(Self, @model.PublishTarget) -> Bool raise @model.MoonsetError
  fn preflight(Self, @model.PublishTarget) -> Unit raise @model.MoonsetError
  fn publish(Self, @model.PublishTarget) -> String raise @model.MoonsetError
}

///|
pub fn JsonlRequest::to_json(self : JsonlRequest) -> Json {
  {
    "schemaVersion": self.schema_version,
    "method": self.protocol_method,
    "payload": self.payload,
  }
}

///|
pub fn JsonlResponse::to_json(self : JsonlResponse) -> Json {
  {
    "schemaVersion": 1,
    "ok": self.ok,
    "result": self.result,
    "error": match self.error {
      Some(value) => Json::string(value)
      None => Json::null()
    },
  }
}

///|
pub fn parse_request(value : Json) -> JsonlRequest raise @model.MoonsetError {
  match value {
    {
      "schemaVersion": Number(version, ..),
      "method": String(protocol_method),
      "payload": payload,
      ..
    } => {
      if version != 1.0 {
        raise @model.Invalid(
          @model.diagnostic("plugin-schema", "Unsupported JSONL schemaVersion"),
        )
      }
      { schema_version: 1, protocol_method, payload, }
    }
    _ =>
      raise @model.Invalid(
        @model.diagnostic("plugin-schema", "Invalid JSONL request"),
      )
  }
}

///|
pub fn parse_response(value : Json) -> JsonlResponse raise @model.MoonsetError {
  if value is { "schemaVersion": ver_json, .. } {
    match ver_json {
      Number(v, ..) if v == 1.0 => ()
      _ =>
        raise @model.Invalid(
          @model.diagnostic(
            "plugin-schema", "Unsupported JSONL response schemaVersion",
          ),
        )
    }
  }
  match value {
    { "ok": True, "result": result, .. } => { ok: true, result, error: None, }
    { "ok": False, "error": String(message), .. } =>
      { ok: false, result: Json::null(), error: Some(message), }
    _ =>
      raise @model.Invalid(
        @model.diagnostic("plugin-schema", "Invalid JSONL response"),
      )
  }
}

///|
/// Extract the required generator text and optional metadata from a response.
pub fn generator_result(
  response : JsonlResponse,
) -> (String, Json) raise @model.MoonsetError {
  guard response.ok else {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-request-failed",
        response.error.unwrap_or("Generator rejected request"),
      ),
    )
  }
  match response.result {
    { "text": String(text), "metadata": metadata, .. } => (text, metadata)
    { "text": String(text), .. } => (text, Json::empty_object())
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "plugin-schema", "Generator result requires result.text",
        ),
      )
  }
}

///|
fn split_lines(source : String) -> Array[String] {
  source
  .replace_all(old="\r\n", new="\n")
  .split("\n")
  .filter(x => x.trim() != "")
  .map(x => x.trim().to_owned())
  .collect()
}

///|
fn is_windows_env(environment : Map[String, String]) -> Bool {
  for k, _ in environment {
    if k.to_lower() == "comspec" {
      return true
    }
  }
  @env.get_env_var("ComSpec") is Some(_) ||
  @env.get_env_var("COMSPEC") is Some(_)
}

///|
fn stderr_detail(stderr : String) -> String {
  let trimmed = stderr.trim().to_owned()
  if trimmed == "" {
    ""
  } else {
    ": " + trimmed
  }
}

///|
async fn read_bounded_process_stream(
  reader : @process.ReadFromProcess,
  captured : Ref[Int32],
  limit : Int32,
  stream : String,
) -> Bytes {
  let buffer = @buffer.Buffer(capacity=4096)
  for ;; {
    match reader.read() {
      None => break
      Some(chunk) => {
        let next_total = captured.val + chunk.length()
        if next_total > limit {
          fail("Plugin \{stream} exceeded output limit of \{limit} bytes")
        }
        captured.val = next_total
        buffer.write_bytesview(chunk)
      }
    }
  }
  buffer.to_bytes()
}

///|
/// Execute one request without invoking a shell or inheriting credentials.
/// Host-side `host_allowed_programs`, when provided, overrides `spec.allowed_programs`.
pub async fn run_jsonl(
  spec : PluginSpec,
  request : JsonlRequest,
  host_allowed_programs? : Array[String],
) -> JsonlResponse raise @model.MoonsetError {
  let allowlist = host_allowed_programs.unwrap_or(spec.allowed_programs)
  if spec.program.trim() == "" || !allowlist.contains(spec.program) {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-permission-denied", "Plugin executable is not explicitly registered",
      ),
    )
  }
  let stdin_bytes = @utf8.encode(request.to_json().stringify() + "\n")
  let run_once = async fn(program : String) -> ProcessResult {
    let lower = program.to_lower()
    let (eff_program, eff_args) = if is_windows_env(spec.environment) &&
      (lower.has_suffix(".cmd") || lower.has_suffix(".bat")) {
      let comspec = match @env.get_env_var("ComSpec") {
        Some(v) if v.trim() != "" => v.trim().to_owned()
        _ =>
          match @env.get_env_var("COMSPEC") {
            Some(v) if v.trim() != "" => v.trim().to_owned()
            _ => "cmd.exe"
          }
      }
      for part in [program] + spec.args {
        if part.contains("\r") ||
          part.contains("\n") ||
          part.contains("\u{0000}") {
          fail("Illegal control character in Windows batch command")
        }
      }
      (comspec, ["/d", "/c", program] + spec.args)
    } else {
      (program, spec.args)
    }
    let command = @process.Cmd(
      eff_program,
      eff_args,
      cwd?=spec.cwd.map(dir => dir[:]),
      inherit_env=false,
      extra_env=spec.environment,
    )
    @async.with_timeout(spec.timeout_ms, () => {
      let mut exit_code : Int32 = 0
      let mut stdout_bytes = b""
      let mut stderr_bytes = b""
      @async.with_task_group(group => {
        let child = command.spawn(
          group,
          stdin=FeedFromParent,
          stdout=Collect,
          stderr=Collect,
          cancel_handler=@process.hard_cancel(),
        )
        let captured : Ref[Int32] = Ref(0)
        group.spawn_bg(allow_failure=true, () => {
          defer child.stdin.close()
          child.stdin.write(stdin_bytes)
        })
        let stdout_task = group.spawn(() => {
          defer child.stdout.close()
          read_bounded_process_stream(
            child.stdout,
            captured,
            spec.max_output_bytes,
            "stdout",
          )
        })
        let stderr_task = group.spawn(() => {
          defer child.stderr.close()
          read_bounded_process_stream(
            child.stderr,
            captured,
            spec.max_output_bytes,
            "stderr",
          )
        })
        exit_code = child.wait()
        stdout_bytes = stdout_task.wait()
        stderr_bytes = stderr_task.wait()
      })
      {
        exit_code,
        stdout: @utf8.decode_lossy(stdout_bytes),
        stderr: @utf8.decode_lossy(stderr_bytes),
      }
    })
  }
  let output = run_once(spec.program) catch {
    first_err =>
      if is_windows_env(spec.environment) &&
        !spec.program.to_lower().has_suffix(".exe") &&
        !spec.program.to_lower().has_suffix(".cmd") &&
        !spec.program.to_lower().has_suffix(".bat") {
        run_once(spec.program + ".cmd") catch {
          _ =>
            raise @model.Io(
              "Plugin execution failed (" +
              spec.program +
              "): " +
              first_err.to_string(),
            )
        }
      } else {
        raise @model.Io(
          "Plugin execution failed (" +
          spec.program +
          "): " +
          first_err.to_string(),
        )
      }
  }
  if output.exit_code != 0 {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-crashed",
        "Plugin exited with code " +
        output.exit_code.to_string() +
        stderr_detail(output.stderr),
      ),
    )
  }
  let lines = split_lines(output.stdout)
  if lines.length() != 1 {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-invalid-output",
        "Plugin must return exactly one JSONL response" +
        stderr_detail(output.stderr),
      ),
    )
  }
  let parsed = @json.parse(lines[0]) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "plugin-invalid-output",
          "Plugin output is not JSON" + stderr_detail(output.stderr),
        ),
      )
  }
  parse_response(parsed)
}

///|
/// Capability names used by the adapter conformance suite.
#derive(Eq, Debug)
pub(all) enum Capability {
  Discovery
  Range
  Ownership
  Lockfile
  Artifact
  Publish
}

///|
pub extend Capability with Eq::{equal, not_equal}

///|
pub extend Capability with Debug::{to_repr}

///|
pub fn Capability::text(self : Capability) -> String {
  match self {
    Discovery => "discovery"
    Range => "range"
    Ownership => "ownership"
    Lockfile => "lockfile"
    Artifact => "artifact"
    Publish => "publish"
  }
}

///|
pub(all) struct CapabilityReport {
  adapter : String
  supported : Array[Capability]
}

///|
pub(all) struct PublisherRegistry {
  plugins : Map[String, PluginSpec]
  allowed_programs : Array[String]
}

///|
/// Built-in operational adapter registrations used by CLI and executor routing.
pub(all) struct AdapterRegistry {
  adapters : Map[String, CapabilityReport]
}

///|
pub fn AdapterRegistry::with_builtins() -> AdapterRegistry {
  let adapters : Map[String, CapabilityReport] = Map([])
  adapters["moonbit"] = {
    adapter: "moonbit",
    supported: [Discovery, Range, Ownership, Artifact, Publish],
  }
  adapters["npm"] = {
    adapter: "npm",
    supported: [Discovery, Range, Ownership, Lockfile, Artifact, Publish],
  }
  adapters["cargo"] = {
    adapter: "cargo",
    supported: [Discovery, Range, Ownership, Lockfile, Artifact, Publish],
  }
  { adapters, }
}

///|
pub fn AdapterRegistry::require(
  self : AdapterRegistry,
  ecosystem : @model.Ecosystem,
  capability : Capability,
) -> Unit raise @model.MoonsetError {
  self.require_named(ecosystem.text(), capability)
}

///|
pub fn AdapterRegistry::require_named(
  self : AdapterRegistry,
  ecosystem : String,
  capability : Capability,
) -> Unit raise @model.MoonsetError {
  match self.adapters.get(ecosystem) {
    Some(report) => require_capability(report, capability)
    None =>
      raise @model.Invalid(
        @model.diagnostic(
          "unsupported-capability",
          "No adapter is registered for ecosystem: " + ecosystem,
        ),
      )
  }
}

///|
pub fn PublisherRegistry::new(
  allowed_programs~ : Array[String] = [],
) -> PublisherRegistry {
  { plugins: Map([]), allowed_programs, }
}

///|
pub fn PublisherRegistry::register(
  self : PublisherRegistry,
  name : String,
  spec : PluginSpec,
) -> Unit {
  self.plugins[name] = spec
}

///|
/// Execute an explicitly registered JSONL publisher method.
pub async fn PublisherRegistry::execute(
  self : PublisherRegistry,
  name : String,
  protocol_method : String,
  payload : Json,
) -> Json raise @model.MoonsetError {
  if !["preflight", "publish", "already-published"].contains(protocol_method) {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-method-denied",
        "Unsupported publisher method: " + protocol_method,
      ),
    )
  }
  let spec = match self.plugins.get(name) {
    Some(found) => found
    None =>
      raise @model.Invalid(
        @model.diagnostic(
          "plugin-permission-denied",
          "Publisher plugin is not registered: " + name,
        ),
      )
  }
  let host_allowed = if self.allowed_programs.is_empty() {
    None
  } else {
    Some(self.allowed_programs)
  }
  let response = run_jsonl(
    spec,
    { schema_version: 1, protocol_method, payload, },
    host_allowed_programs?=host_allowed,
  )
  if !response.ok {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-request-failed",
        response.error.unwrap_or("Publisher plugin rejected request"),
      ),
    )
  }
  response.result
}

///|
/// Validate that an adapter declares all five universal release capabilities.
pub fn validate_conformance(
  report : CapabilityReport,
) -> Unit raise @model.MoonsetError {
  for capability in [Discovery, Range, Ownership, Artifact, Publish] {
    require_capability(report, capability)
  }
}

///|
/// Validate that a requested capability is declared before apply/publish.
pub fn require_capability(
  report : CapabilityReport,
  capability : Capability,
) -> Unit raise @model.MoonsetError {
  if !report.supported.contains(capability) {
    raise @model.Invalid(
      @model.diagnostic(
        "unsupported-capability",
        "Adapter " + report.adapter + " does not support " + capability.text(),
      ),
    )
  }
}
