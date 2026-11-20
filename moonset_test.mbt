///|
test "root moonset facade re-exports unified v2.0.0 API surface" {
  assert_eq(@moonset.api_version, "2.0.0")
  let cfg : @moonset.Config = @moonset.parse_config("{}")
  assert_eq(cfg.access, @moonset.Access::Public)
  assert_true(cfg.snapshot.enabled)
  let reg = @moonset.AdapterRegistry::with_builtins()
  reg.require(@moonset.Ecosystem::MoonBit, @moonset.Capability::Publish)
  reg.require(@moonset.Ecosystem::Cargo, @moonset.Capability::Lockfile)
  let pub_opts = @moonset.PublishOptions::new(dry_run=true, reconcile=true)
  assert_true(pub_opts.dry_run && pub_opts.reconcile)
}
