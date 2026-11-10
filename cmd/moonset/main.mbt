///|
/// Entry point for the CLI or runnable program in this template.
/// Keep main focused; move logic into the library package.
/// Run with `moon run cmd/main` from the project root.
async fn main {
  let code = @cli.run(@env.args()[1:].to_owned())
  @env.exit(code)
}
