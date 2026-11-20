///|
test "JSONL request and response schemas are versioned and validated" {
  let request : @adapters.JsonlRequest = {
    schema_version: 1,
    protocol_method: "generate",
    payload: { "text": "release" },
  }
  let decoded_request = @adapters.parse_request(
    @json.parse(request.to_json().stringify()),
  )
  assert_eq(decoded_request.protocol_method, "generate")
  let decoded_response = @adapters.parse_response(
    @json.parse("{\"schemaVersion\":1,\"ok\":true,\"result\":\"done\"}"),
  )
  assert_true(decoded_response.ok)
  assert_eq(decoded_response.result, Json::string("done"))
  let bad_version = try {
    ignore(
      @adapters.parse_response(
        @json.parse("{\"schemaVersion\":2,\"ok\":true,\"result\":\"done\"}"),
      ),
    )
    false
  } catch {
    @model.Invalid(d) => d.code == "plugin-schema"
    _ => false
  }
  assert_true(bad_version)
  let rejected = try {
    ignore(@adapters.parse_response(@json.parse("{\"ok\":true}")))
    false
  } catch {
    @model.Invalid(_) => true
    _ => false
  }
  assert_true(rejected)
  let (text, metadata) = @adapters.generator_result(
    @adapters.parse_response(
      @json.parse(
        "{\"ok\":true,\"result\":{\"text\":\"generated\",\"metadata\":{\"source\":\"fixture\"}}}",
      ),
    ),
  )
  assert_eq(text, "generated")
  assert_true(metadata is { "source": "fixture", .. })
}

///|
test "adapter capability is rejected before execution when absent" {
  let rejected = try {
    @adapters.require_capability(
      { adapter: "fixture", supported: [Discovery], },
      @adapters.Publish,
    )
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "unsupported-capability"
    _ => false
  }
  assert_true(rejected)
}

///|
test "built-in adapter registry declares honest capabilities and refuses undeclared ecosystems" {
  let registry = @adapters.AdapterRegistry::with_builtins()
  registry.require(@model.Cargo, @adapters.Publish)
  registry.require(@model.Cargo, @adapters.Lockfile)
  registry.require(@model.Npm, @adapters.Lockfile)
  registry.require(@model.MoonBit, @adapters.Publish)
  // MoonBit must not falsely declare Lockfile staging
  let moon_lock_rejected = try {
    registry.require(@model.MoonBit, @adapters.Lockfile)
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "unsupported-capability"
    _ => false
  }
  assert_true(moon_lock_rejected)
  let rejected = try {
    registry.require_named("tauri", @adapters.Publish)
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "unsupported-capability"
    _ => false
  }
  assert_true(rejected)
}

///|
test "conformance requires the five universal adapter capabilities" {
  let complete = try {
    @adapters.validate_conformance({
      adapter: "fixture",
      supported: [Discovery, Range, Ownership, Artifact, Publish],
    })
    true
  } catch {
    _ => false
  }
  assert_true(complete)
  let missing = try {
    @adapters.validate_conformance({
      adapter: "partial",
      supported: [@adapters.Discovery, @adapters.Range],
    })
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "unsupported-capability"
    _ => false
  }
  assert_true(missing)
}

///|
async test "unregistered plugin executable and host allowlist mismatch are refused before launch" {
  let rejected = try {
    ignore(
      @adapters.run_jsonl(
        {
          program: "this-program-must-not-run",
          args: [],
          cwd: None,
          timeout_ms: 30000,
          max_output_bytes: 1048576,
          allowed_programs: [],
          environment: Map([]),
        },
        {
          schema_version: 1,
          protocol_method: "generate",
          payload: Json::null(),
        },
      ),
    )
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "plugin-permission-denied"
    _ => false
  }
  assert_true(rejected)

  // Host-side allowlist overrides self-declared spec.allowed_programs
  let host_blocked = try {
    ignore(
      @adapters.run_jsonl(
        {
          program: "node",
          args: [],
          cwd: None,
          timeout_ms: 30000,
          max_output_bytes: 1048576,
          allowed_programs: ["node"],
          environment: Map([]),
        },
        {
          schema_version: 1,
          protocol_method: "generate",
          payload: Json::null(),
        },
        host_allowed_programs=["moon"],
      ),
    )
    false
  } catch {
    @model.Invalid(diagnostic) => diagnostic.code == "plugin-permission-denied"
    _ => false
  }
  assert_true(host_blocked)
}

///|
async fn run_plugin_fixture(
  mode : String,
  timeout : Int32,
  limit : Int32,
) -> String? {
  let program = "node"
  let path = @env.get_env_var("PATH").unwrap_or("")
  let environment : Map[String, String] = { "PATH": path }
  match @env.get_env_var("SystemRoot") {
    Some(value) => environment["SystemRoot"] = value
    None => ()
  }
  try {
    let response = @adapters.run_jsonl(
      {
        program,
        args: ["fixtures/phase5-plugin.mjs", mode],
        cwd: None,
        timeout_ms: timeout,
        max_output_bytes: limit,
        allowed_programs: [program],
        environment,
      },
      { schema_version: 1, protocol_method: "generate", payload: Json::null(), },
    )
    Some(response.result.stringify())
  } catch {
    @model.Invalid(diagnostic) => Some(diagnostic.code)
    @model.Io(_) => Some("io-error")
  }
}

///|
async test "JSONL plugin process succeeds and classifies malformed, crashed, oversized, and timed-out runs" {
  assert_eq(
    run_plugin_fixture("success", 30000, 1048576),
    Some("{\"text\":\"phase5-fixture\",\"metadata\":{\"fixture\":true}}"),
  )
  assert_eq(
    run_plugin_fixture("invalid", 30000, 1048576),
    Some("plugin-invalid-output"),
  )
  assert_eq(run_plugin_fixture("oversized", 30000, 64), Some("io-error"))
  assert_eq(run_plugin_fixture("slow", 1, 1048576), Some("io-error"))
  assert_eq(run_plugin_fixture("crash", 30000, 1048576), Some("plugin-crashed"))
}

///|
async test "publisher registry routes the three v1 publisher methods" {
  let registry = @adapters.PublisherRegistry::new(allowed_programs=["node"])
  registry.register("fixture", {
    program: "node",
    args: ["fixtures/phase5-plugin.mjs", "success"],
    cwd: None,
    timeout_ms: 30000,
    max_output_bytes: 1048576,
    allowed_programs: ["node"],
    environment: {
      "PATH": @env.get_env_var("PATH").unwrap_or(""),
      "SystemRoot": @env.get_env_var("SystemRoot").unwrap_or(""),
    },
  })
  for protocol_method in ["preflight", "publish", "already-published"] {
    let result = registry.execute("fixture", protocol_method, Json::null())
    assert_true(result is { "accepted": True, .. })
  }
}
