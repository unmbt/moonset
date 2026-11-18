///|
pub fn fixture_api_version() -> String {
  @api.api_version
}

///|
pub fn fixture_render() -> String {
  @changelog.render(
    @changelog.Builtin,
    @changelog.builtin_context("moonbit:fixture", "0.1.0", "2026-11-17", ""),
  )
}

///|
pub fn fixture_adapter_registry() -> Bool raise @api.MoonsetError {
  let registry = @api.AdapterRegistry::with_builtins()
  registry.require("cargo", @api.Capability::Publish)
  true
}
