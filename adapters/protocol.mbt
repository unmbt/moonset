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
/// Injectable filesystem port used by operational adapters.
pub(all) struct FileHost {
  read_text : (String) -> String?
  write_text : (String, String) -> Unit raise @model.MoonsetError
  exists : (String) -> Bool
}

///|
/// Injectable process port. Implementations must invoke executable/argv directly.
pub(all) struct ProcessHost {
  run : (
    String,
    Array[String],
    String?,
    Map[String, String],
    String,
    Int32,
    Int32,
  ) -> ProcessResult raise @model.MoonsetError
}

///|
/// Injectable registry queries and publication port; credentials remain host-owned.
pub(all) struct RegistryHost {
  already_published : (String, String, String) -> Bool raise @model.MoonsetError
  preflight : (String, String, String) -> Unit raise @model.MoonsetError
  publish : (String, String, String) -> String raise @model.MoonsetError
}

///|
/// Experimental operation ports: v1 contracts may change before v2.
pub(open) trait DiscoveryPort {
  fn discover(Self, String) -> Array[@model.ReleaseUnit] raise @model.MoonsetError
}

///|
pub(open) trait RangePort {
  fn satisfies(Self, String, String) -> Bool
  fn rewrite(Self, String, String) -> String raise @model.MoonsetError
}

///|
pub(open) trait OwnershipPort {
  fn ownership(Self, Array[String]) -> Array[@model.Ownership] raise @model.MoonsetError
}

///|
pub(open) trait LockfilePort {
  fn stage_lockfile(Self, @model.WorkspaceSnapshot, String) -> Array[
    @model.FileEdit,
  ] raise @model.MoonsetError
}

///|
pub(open) trait ArtifactPort {
  fn pack(Self, @model.ArtifactIntent) -> @model.PackResult raise @model.MoonsetError
}

///|
pub(open) trait PublisherPort {
  fn already_published(Self, @model.PublishTarget) -> Bool raise @model.MoonsetError
  fn preflight(Self, @model.PublishTarget) -> Unit raise @model.MoonsetError
  fn publish(Self, @model.PublishTarget) -> String raise @model.MoonsetError
}

///|
/// Combined experimental adapter facade for all executable operations.
pub(open) trait OperationalAdapter {
  fn name(Self) -> String
  fn capabilities(Self) -> Array[Capability]
  fn discover(Self, String) -> Array[@model.ReleaseUnit] raise @model.MoonsetError
  fn satisfies(Self, String, String) -> Bool
  fn rewrite_range(Self, String, String) -> String raise @model.MoonsetError
  fn ownership(Self, Array[String]) -> Array[@model.Ownership] raise @model.MoonsetError
  fn stage_lockfile(Self, @model.WorkspaceSnapshot, String) -> Array[
    @model.FileEdit,
  ] raise @model.MoonsetError
  fn pack(Self, @model.ArtifactIntent) -> @model.PackResult raise @model.MoonsetError
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
  .split("\n")
  .filter(x => x.trim() != "")
  .map(x => x.trim().to_owned())
  .collect()
}

///|
/// Execute one request without invoking a shell or inheriting credentials.
pub async fn run_jsonl(
  spec : PluginSpec,
  request : JsonlRequest,
) -> JsonlResponse raise @model.MoonsetError {
  if !spec.allowed_programs.contains(spec.program) {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-permission-denied", "Plugin executable is not explicitly registered",
      ),
    )
  }
  let command = @shell.Cmd(
    spec.program,
    spec.args,
    cwd?=spec.cwd,
    inherit_env=false,
    env=spec.environment,
    stdin=@shell.Text(request.to_json().stringify() + "\n"),
  )
  let output = command.output(
    timeout_ms=spec.timeout_ms,
    max_output_bytes=spec.max_output_bytes,
  ) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic(
          "plugin-execution-failed", "Plugin timed out or exceeded the output limit",
        ),
      )
  }
  if output.exit_code() != 0 {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-crashed",
        "Plugin exited with code " + output.exit_code().to_string(),
      ),
    )
  }
  let lines = split_lines(output.stdout())
  if lines.length() != 1 {
    raise @model.Invalid(
      @model.diagnostic(
        "plugin-invalid-output", "Plugin must return exactly one JSONL response",
      ),
    )
  }
  let parsed = @json.parse(lines[0]) catch {
    _ =>
      raise @model.Invalid(
        @model.diagnostic("plugin-invalid-output", "Plugin output is not JSON"),
      )
  }
  parse_response(parsed)
}

///|
/// Capability names used by the adapter conformance suite.
#derive(Eq)
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
pub(all) struct CapabilityReport {
  adapter : String
  supported : Array[Capability]
}

///|
pub(all) struct PublisherRegistry {
  plugins : Map[String, PluginSpec]
}

///|
/// Built-in operational adapter registrations used by CLI routing.
pub(all) struct AdapterRegistry {
  adapters : Map[String, CapabilityReport]
}

///|
pub fn AdapterRegistry::with_builtins() -> AdapterRegistry {
  let adapters : Map[String, CapabilityReport] = Map([])
  let capabilities = [Discovery, Range, Ownership, Lockfile, Artifact, Publish]
  for ecosystem in ["moonbit", "npm", "cargo"] {
    adapters[ecosystem] = { adapter: ecosystem, supported: capabilities, }
  }
  { adapters, }
}

///|
pub fn AdapterRegistry::require(
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
pub fn PublisherRegistry::new() -> PublisherRegistry {
  { plugins: Map([]), }
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
  let spec = self.plugins
    .get(name)
    .unwrap_or({
      program: "",
      args: [],
      cwd: None,
      timeout_ms: 30000,
      max_output_bytes: 1048576,
      allowed_programs: [],
      environment: Map([]),
    })
  let response = run_jsonl(spec, {
    schema_version: 1,
    protocol_method,
    payload,
  })
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
pub fn validate_conformance(
  report : CapabilityReport,
) -> Unit raise @model.MoonsetError {
  for capability in [Discovery, Range, Ownership, Lockfile, Artifact, Publish] {
    require_capability(report, capability)
  }
}

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
/// Adapter contracts are intentionally data-oriented for cross-package conformance.
pub(open) trait EcosystemAdapter {
  fn name(Self) -> String
  fn capabilities(Self) -> Array[Capability]
}

///|
pub(open) trait ArtifactProvider {
  fn artifacts(Self, Array[@model.ArtifactIntent]) -> Array[@model.PackResult]
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
