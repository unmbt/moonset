# moonset CLI Reference

## Global Options

| Flag | Description |
|---|---|
| `--cwd <path>` | Base directory for workspace discovery and relative paths |
| `--config <path>` | Explicit config file path (errors if missing; defines release domain root) |
| `--yes` | Skip interactive confirmations (required in CI / agent runs for `publish` / `tag`) |
| `--json` | Alias for `--output json` |
| `--quiet` | Suppress non-essential human output |
| `--no-color` | Disable ANSI colors in human output |
| `-h`, `--help` | Show command help |
| `-V`, `--version` | Print CLI version |

Environment variable for agents/CI: `MOONSET_NON_INTERACTIVE=1`.

## Exit Codes & JSON Error Envelope

| Code | Meaning | Typical Causes |
|---:|---|---|
| `0` | Success | Valid plan/operation completed |
| `1` | Policy / confirmation block | `missing-changeset` (in `status --since`), `confirmation-required`, `dirty-working-tree`, `incomplete-selection` (`--only` missing fixed/bridge closure) |
| `2` | Invalid input / config | Bad `.changeset/config.json`, malformed changeset front matter, unknown package/UnitId, invalid CLI arguments, `snapshot-disabled` |
| `3` | External / I/O / partial failure | Git error, registry network error, partial publish failure |

In `--json` mode:
- `status` returns its standard JSON object with `ok: false` and `errors: [...]`.
- All other commands return:

```json
{
  "schemaVersion": 1,
  "ok": false,
  "command": "<cmd>",
  "errors": [
    { "code": "missing-changeset", "message": "...", "suggestion": "...", "path": "..." }
  ]
}
```

Always branch on `errors[].code`, never on `message` text.

## Subcommands

### `init`
```bash
moonset init [--force] [--config <path>] [--format json]
```
Creates `.changeset/config.json`, `.changeset/README.md`, `.changeset/.gitignore`, and `.moonset/.gitignore`. Never overwrites existing files (`--force` only fills missing files).

### `add`
```bash
moonset add [--package <name> ...] [--type major|minor|patch|none] \
  [--summary <text>] [--empty] [--id <id>] [--no-format] [--json]
```
Non-interactive mode requires `--package` + `--type` + `--summary`, OR `--empty`. Writes `.changeset/<id>.md`; does not auto-commit Git.

### `status`
```bash
moonset status [--since <ref>] [--verbose] [--output human|json|markdown] \
  [--head-repo <owner/name>] [--head-ref <branch>]
```
Read-only. Without `--since`, inspects working directory changesets (no Git required). With `--since <ref>`, compares `merge-base(<ref>, HEAD)..HEAD` from committed `HEAD` only.
JSON top-level keys: `schemaVersion`, `workspace`, `changesets`, `releases`, `warnings`, `errors`, `hasChanges`, `hasRelease`, optional `coexistence`.

### `publish-plan`
```bash
moonset publish-plan [--since <ref>] [--output <path|->] [--pretty]
```
Read-only analysis plan (`schemaVersion: 1`, `stage: "analysis"`, `executable: false`). Includes `artifacts` and `executionGraph` (`buildNodes`, `publishNodes`, `publishOrder`) when mixed/artifact config is present.

### `version`
```bash
moonset version [--snapshot <tag>] [--since <ref>] [--dry-run] \
  [--empty] [--no-changelog] [--no-commit] [--no-format] \
  [--output human|json|markdown] [--commit-metadata <path>] [--recover]
```
Validates all inputs before touching disk; writes manifests, lockfiles (in mixed mode), `CHANGELOG.md`, and `.moonset/release-state.json` atomically with a transaction journal.
- `--dry-run --output markdown`: renders Release PR body (table + per-package `# Releases` changelog).
- `--commit-metadata <path>`: JSON map `{"<sha>": {"pr": "12", "author": "alice"}}` for `git`/`github` changelog generators.

### `pre`
```bash
moonset pre enter <tag> [--initial-version]
moonset pre exit
moonset pre status
```
Manages `.changeset/pre.json`. Refuses a second `enter` while already active.

### `pack`
```bash
moonset pack [--package <name> ...] [--target <name>] [--manifest-out <path>] \
  [--verify] [--artifacts-dir <dir>] [--frozen] [--dry-run] [--json]
```
Routes by ecosystem:
- MoonBit: `moon package` (`--dry-run` → `moon package --dry-run`)
- npm/pnpm: configured workspace manager (`--frozen` adds `--offline`)
- Cargo: `cargo package --allow-dirty` (`--dry-run` → `cargo package --list --allow-dirty`)

Writes `.moonset/pack-results.json` (or `pack-results-<target>.json`) on non-dry-run. `--verify` validates manifests in `--artifacts-dir` against `.moonset/release-state.json`.

### `publish`
```bash
moonset publish [--dry-run] [--registry <spec>] [--only <unit[,unit...]>] \
  [--tag <spec>] [--artifacts-dir <dir>] [--retry <count>] \
  [--allow-uncommitted] [--no-tag] [--yes] [--json]
```
Validates `release-state.json` against current manifests and clean working tree (unless `--allow-uncommitted`).
- `--registry` / `--tag` support scoped mapping (`UnitId > ecosystem > global`), e.g.:
  - `--registry npm=https://npm.pkg.github.com,cargo=private`
  - `--tag npm:@acme/ui=canary`
- **Ecosystem constraints**: MoonBit does not support `--registry` or `--tag`; Cargo (`crates.io`) does not support `--tag`.
- Automatically triggers `tag` after all targets succeed on a clean tree unless `--no-tag`, `config.tag.afterPublish=false`, or `--allow-uncommitted` with dirty tree.

### `tag` (alias: `git-tag`)
```bash
moonset tag [--dry-run] [--push] [--force] [--format <template>] [--yes]
```
Default tag formats:
- Single module: `v{version}`
- Single-ecosystem workspace: `{name}@{version}`
- Mixed workspace: `{ecosystem}/{name}@{version}` (never uses raw `:` from UnitId)

`--push` pushes only newly created tags.

### `release-notes`
```bash
moonset release-notes [--version <ver>] [--file <path>] [--package <unit>] \
  [--from-state] [--json] [--pretty]
```
Read-only extraction of exact `## [v]<ver>` sections from `CHANGELOG.md` (does not confuse `0.1.0` with `0.1.0-alpha.1`).

### `doctor`
```bash
moonset doctor [--fix] [--registry] [--output human|json]
```
Read-only diagnostics for MoonBit toolchain, Git, manifests, leftover `version-journal.json`, `.changeset` config, optional `--registry` preflight, and CI env vars (never prints secret values). `--fix` safely creates missing init/gitignore files without overwriting existing ones.
