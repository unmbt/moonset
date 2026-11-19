# Configuration & Mixed Workspaces Reference

## Config Location & Merge Precedence

Default path: `.changeset/config.json` at the release domain root (`schemaVersion: 1`). Unknown top-level keys are rejected; experimental options live under `experimental`.

```text
defaults < .changeset/config.json < MOONSET_* (non-secret runtime flags) < CLI flags
```

Never place registry tokens or secrets in `.changeset/config.json`.

## Key Configuration Fields

```json
{
  "schemaVersion": 1,
  "baseBranch": "main",
  "access": "public",
  "changelog": {
    "generator": "github",
    "file": "CHANGELOG.md",
    "options": { "repo": "owner/repo", "disableThanks": false }
  },
  "commit": {
    "mode": "never",
    "addMessage": "chore: add changeset",
    "versionMessage": "chore: release"
  },
  "updateInternalDependencies": "patch",
  "updateInternalDependents": "out-of-range",
  "changedFilePatterns": ["**"],
  "fixed": [["org/core", "org/cli"]],
  "linked": [["org/plugin-a", "org/plugin-b"]],
  "ignore": [],
  "privatePackages": { "version": false, "tag": false, "publish": false },
  "pre": { "file": ".changeset/pre.json", "directory": ".changeset/pre" },
  "snapshot": {
    "enabled": false,
    "useCalculatedVersion": false,
    "prereleaseTemplate": "{tag}-{datetime}"
  },
  "tag": { "create": true, "afterPublish": true, "format": "auto", "push": false },
  "publisher": { "kind": "moon", "registry": "default", "dryRunFirst": true },
  "formatter": "builtin",
  "format": "auto",
  "github": { "links": true, "thanks": true }
}
```

### Field Notes
- `changelog.generator`: `"builtin"`, `"git"`, `"github"`, or a registered external JSONL generator under `plugins.generators`. Set `"changelog": false` to disable.
- `fixed` / `linked` / `ignore`: Support exact names and globs (`*`, `?`, `[...]`, `{...}`, `(...)`). Overlapping `fixed` groups fail validation.
- `changedFilePatterns`: Evaluated in order relative to package root; supports `**` and `!` negation patterns.
- `snapshot.prereleaseTemplate`: Supports `{tag}`, `{datetime}`, `{commit}`, `{version}`.
- `formatter`: `"builtin"`, `"prettier"`, `"oxfmt"`, `"biome"`, or `"dprint"`. Set `"format": false` or pass `--no-format` to disable.
- `privatePackages`: Controls `version`, `tag`, `publish` independently. **Cannot** bypass npm `"private": true` or Cargo `publish = false`. Note that MoonBit `moon.mod` `private = true` means restricted visibility, not a publish ban.

---

## Mixed Workspaces (`experimental.mixedWorkspaces`)

Supports **MoonBit**, **npm / pnpm** (`ecosystem: "npm"`), and **Cargo** (`ecosystem: "cargo"`, `crates.io` only).

### Modes
- `coexist`: `moonset` manages only its explicitly declared workspaces; other ecosystems keep their own tools (e.g., Node Changesets) in separate `.changeset` partitions. Never let two tools consume the same `.changeset` directory.
- `unified`: Single release domain, single `.changeset/`, unified release plan and dependency/bridge execution graph.

### UnitId Convention
In mixed mode, **always** use `<ecosystem>:<nativeName>`:
- MoonBit: `moonbit:acme/engine`
- npm / pnpm: `npm:@acme/engine`
- Cargo: `cargo:engine-core`

Use full UnitIds everywhere: changeset front matter, `fixed`, `linked`, `ignore`, `bridges`, `units`, `--package`, and `--only`.

### Example Mixed Config

```json
{
  "schemaVersion": 1,
  "baseBranch": "main",
  "fixed": [["moonbit:acme/engine", "npm:@acme/engine"]],
  "experimental": {
    "mixedWorkspaces": {
      "mode": "unified",
      "lockfiles": "refresh",
      "workspaces": [
        { "id": "mbt", "ecosystem": "moonbit", "root": ".", "manager": "moon", "includeRoot": true },
        { "id": "js", "ecosystem": "npm", "root": "packages/js", "manager": "pnpm", "includeRoot": false },
        { "id": "rs", "ecosystem": "cargo", "root": "crates", "manager": "cargo", "includeRoot": false }
      ],
      "bridges": [
        {
          "consumer": "npm:@acme/engine",
          "producer": "moonbit:acme/engine",
          "kind": "build",
          "bump": "patch",
          "waitFor": "build"
        }
      ],
      "units": {
        "npm:@acme/engine": {
          "tagFormat": "npm/{name}@{version}"
        }
      }
    }
  }
}
```

### Key Mixed-Mode Rules
- `bridges`: Declares cross-ecosystem build/delivery dependencies (`waitFor: "build"` waits for local artifacts; `waitFor: "publish"` waits for remote registry publish). Build bridges do not rewrite native `dependencies`.
- `lockfiles`: `"refresh"` (default) updates lockfiles in staging before writing; `"verify-only"` fails if lockfiles would change.
- `--only` closure: Selecting a subset of units in `publish --only` fails with exit code `1` if any required `fixed` group or `bridge` closure member is omitted.
- **Deferred / unsupported**: Non-crates.io Cargo registries and Tauri version sync are not supported yet.
