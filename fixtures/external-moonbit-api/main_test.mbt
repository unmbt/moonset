///|
test "external fixture imports stable facade and changelog API" {
  assert_eq(@external-moonbit-api.fixture_api_version(), "1.0.0")
  assert_true(@external-moonbit-api.fixture_render().contains("# Changelog"))
  assert_true(@external-moonbit-api.fixture_adapter_registry())
}
