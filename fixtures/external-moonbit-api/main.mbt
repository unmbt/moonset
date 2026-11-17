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
