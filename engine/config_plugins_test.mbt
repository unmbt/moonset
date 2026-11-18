///|
test "registered generator config carries executable policy and limits" {
  let config = @engine.parse_config(
    "{\"plugins\":{\"generators\":{\"fixture\":{\"program\":\"node\",\"args\":[\"fixture.mjs\"],\"allowedPrograms\":[\"node\"],\"environment\":[\"PATH\"],\"timeoutMs\":1200,\"maxOutputBytes\":4096}}}}",
  )
  let plugin = config.generators.get("fixture").unwrap()
  assert_eq(plugin.program, "node")
  assert_eq(plugin.args, ["fixture.mjs"])
  assert_eq(plugin.allowed_programs, ["node"])
  assert_eq(plugin.environment, ["PATH"])
  assert_eq(plugin.timeout_ms, 1200)
  assert_eq(plugin.max_output_bytes, 4096)
}
