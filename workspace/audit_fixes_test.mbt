///|
async fn write_audit_file(
  root : String,
  rel : String,
  content : String,
) -> Unit {
  let abs = @path.Path(root).join(@path.Path(rel)).to_string()
  @fs.mkdir(
    @path.Path(abs).dirname().to_string(),
    recursive=true,
    allow_existing=true,
  )
  @fs.write_text(abs, content)
}

///|
async test "audit fixes: MoonBit private=true maps to Private, custom --config updates pre.file, repeated glob dirs, BOM Cargo.toml" {
  let root = @fs.tmpdir(prefix="moonset-audit-ws-")
  defer (@fs.remove(root, recursive=true) catch { _ => () })
  write_audit_file(
    root, "moon.work", "members = [\"./pub-pkg\", \"./priv-pkg\"]\n",
  )
  write_audit_file(
    root, "pub-pkg/moon.mod", "name = \"acme/pub\"\nversion = \"0.1.0\"\n",
  )
  write_audit_file(
    root, "priv-pkg/moon.mod", "name = \"acme/priv\"\nversion = \"0.1.0\"\nprivate = true\n",
  )
  write_audit_file(
    root,
    ".moonset/config.json",
    (
      #|{
      #|  "schemaVersion": 1,
      #|  "experimental": {
      #|    "mixedWorkspaces": {
      #|      "mode": "unified",
      #|      "workspaces": [
      #|        { "id": "moon", "ecosystem": "moonbit", "root": ".", "manager": "moon", "includeRoot": false },
      #|        { "id": "js", "ecosystem": "npm", "root": "js", "manager": "yarn", "includeRoot": false },
      #|        { "id": "rs", "ecosystem": "cargo", "root": "rs", "manager": "cargo", "includeRoot": true }
      #|      ]
      #|    }
      #|  }
      #|}
    ),
  )
  write_audit_file(
    root, ".moonset/pre.json", "{\"mode\":\"pre\",\"tag\":\"alpha\"}\n",
  )
  // Multiple overlapping npm workspace globs scanning the same parent `js/packages` twice
  write_audit_file(
    root, "js/package.json", "{\"name\":\"@acme/js-root\",\"private\":true,\"workspaces\":[\"packages/a*\",\"packages/b*\"]}\n",
  )
  write_audit_file(
    root, "js/packages/alpha/package.json", "{\"name\":\"@acme/alpha\",\"version\":\"1.0.0\"}\n",
  )
  write_audit_file(
    root, "js/packages/beta/package.json", "{\"name\":\"@acme/beta\",\"version\":\"1.0.0\",\"dependencies\":{\"@acme/alpha\":\"workspace:^\"}}\n",
  )
  // Cargo.toml with UTF-8 BOM
  let bom_cargo = "\uFEFF[package]\nname = \"acme-bom\"\nversion = \"0.3.0\"\nedition = \"2021\"\n"
  write_audit_file(root, "rs/Cargo.toml", bom_cargo)

  let loaded = @workspace.discover(
    root,
    config_path=".moonset/config.json",
    include_commits=false,
  ) catch {
    @model.Invalid(d) =>
      fail("discover failed: " + d.code + " - " + d.message + " @ " + d.path)
    err => raise err
  }
  // 1. Custom --config writes effective pre.file and pre.directory into snapshot.config.pre
  assert_eq(loaded.snapshot.config.pre.file, ".moonset/pre.json")
  assert_eq(loaded.snapshot.config.pre.directory, ".moonset/pre")
  assert_true(loaded.pre is Some({ mode: @model.Pre, tag: "alpha", .. }))

  // 2. MoonBit private = true -> visibility == Private, publish == false
  let found_ids = loaded.snapshot.units.map(u => u.id).join(", ")
  guard loaded.snapshot.units
    .iter()
    .find_first(u => u.id == "moonbit:acme/priv")
    is Some(priv_unit) else {
    fail("Missing moonbit:acme/priv in units: " + found_ids)
  }
  assert_eq(priv_unit.visibility, @model.Visibility::Private)
  assert_false(priv_unit.publish)

  // 3. Repeated glob scans on js/packages/* find BOTH alpha and beta (no visited_dirs drop)
  assert_true(loaded.snapshot.units.any(u => u.id == "npm:@acme/alpha"))
  assert_true(loaded.snapshot.units.any(u => u.id == "npm:@acme/beta"))

  // 4. UTF-8 BOM Cargo.toml span matches exact original bytes
  guard loaded.snapshot.units.iter().find_first(u => u.id == "cargo:acme-bom")
    is Some(rs_unit) else {
    fail("Missing cargo:acme-bom in units: " + found_ids)
  }
  guard rs_unit.version_span is Some(span) else {
    fail("Expected version_span for BOM Cargo.toml")
  }
  guard loaded.snapshot.sources.get(rs_unit.manifest) is Some(rs_source) else {
    fail("Missing source for " + rs_unit.manifest)
  }
  let raw_bytes = @utf8.encode(rs_source)
  assert_eq(@utf8.decode_lossy(raw_bytes[span.start:span.end]), "0.3.0")
}
