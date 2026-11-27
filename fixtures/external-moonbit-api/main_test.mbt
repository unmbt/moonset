///|
test "external fixture imports root, api, core (wasm-gc), and changelog facades" {
  assert_eq(@external-moonbit-api.fixture_api_version(), "2.0.0")
  assert_eq(
    @external-moonbit-api.fixture_root_and_core_versions(),
    ("2.0.0", "2.0.0"),
  )
  assert_true(@external-moonbit-api.fixture_render().contains("# Changelog"))
  assert_true(@external-moonbit-api.fixture_adapter_registry())
  let (next_ver, md) = @external-moonbit-api.fixture_plan_and_markdown()
  assert_eq(next_ver, "0.2.0")
  assert_true(md.contains("<!-- moonset-bot:changeset-check:ext -->"))
  assert_true(
    md.contains("| `moonbit:acme/ext` | `0.1.0` → `0.2.0` | `minor` |"),
  )
}
