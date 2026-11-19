---
name: moonset
description: >-
  Guide for using the moonset CLI and GitHub Actions to manage versioning,
  changesets, changelogs, and publishing for MoonBit workspaces and mixed
  MoonBit/npm/pnpm/Cargo repositories. Use when initializing .changeset,
  adding changesets for a PR, previewing release plans, running version/pre/snapshot,
  packing or publishing to Mooncakes/npm/crates.io, tagging releases, setting up
  moonset GitHub Actions (PR Bot or auto-release), or troubleshooting moonset
  (发版、版本号、变更集、CHANGELOG、MoonBit 发布).
---

# moonset Agent Guide

`moonset` is a Changesets-style release management CLI and GitHub Actions suite for MoonBit workspaces and mixed MoonBit / npm / pnpm / Cargo (`crates.io`) repositories.

> **Tool selection**: Use `moonset` for PR-centric changesets, automated `CHANGELOG.md`, multi-package or mixed-ecosystem releases, and CI release pipelines. For quick single-module local interactive version bumps, prefer `moon-bump`.

## Non-Negotiable Rules for Agents

Follow these rules strictly when operating `moonset` in a shell:

1. **Never launch the interactive TUI.** Running `moonset` or `moonset add` without flags opens a TUI and hangs non-interactive shells. Always pass explicit flags (`--package`, `--type`, `--summary`, or `--empty`) and set `MOONSET_NON_INTERACTIVE=1` in automated runs.
2. **Prefer machine-readable JSON.** Use `--json` (or `--output json`) for `status`, `publish-plan`, `doctor`, `publish`, and `release-notes`. Branch on exit codes (`0`, `1`, `2`, `3`) and `errors[].code` rather than scraping human text.
3. **Dry-run before mutating or publishing.** Preview with `moonset version --dry-run`, `moonset pack --dry-run`, and `moonset publish --dry-run` before executing writes or network publishes. Pass `--yes` for non-interactive `publish` and `tag`.
4. **Never hand-edit state files.** Do not manually edit `.moonset/release-state.json`, `.moonset/publish-state.json`, `.moonset/version-journal.json`, or `.changeset/pre.json`.
   - **Commit** `.moonset/release-state.json` together with the release commit.
   - **Gitignore** `version-journal.json`, `publish-state.json`, and `pack-results.json` (handled automatically by `moonset init` / `moonset doctor --fix`).
5. **`publish` never runs `version` implicitly.** Always run `moonset version`, commit all version/changelog/`.moonset/release-state.json` changes, and only then run `moonset publish`.
6. **Use full `UnitId` in mixed workspaces.** When `experimental.mixedWorkspaces` is enabled, `--package`, `--only`, `fixed`, `linked`, `ignore`, and changeset front matter MUST use `<ecosystem>:<nativeName>` (e.g., `moonbit:org/pkg`, `npm:@acme/ui`, `cargo:my-crate`).

## Core Workflows

### 1. Verify Installation & Initialize

Check whether `moonset` is available and inspect the workspace:

```bash
moonset -V
moonset doctor --output json
```

If `moonset` is not installed:

```bash
# Recommended (MoonBit toolchain)
moon install unmbt/moonset/cmd/moonset

# Pre-compiled binary (macOS/Linux)
curl -fsSL https://raw.githubusercontent.com/unmbt/moonset/master/scripts/install.sh | bash

# Pre-compiled binary (Windows PowerShell)
irm https://raw.githubusercontent.com/unmbt/moonset/master/scripts/install.ps1 | iex
```

Initialize `.changeset/` (safe — never overwrites existing config):

```bash
moonset init
```

### 2. Record a Change for a PR (`add`)

First discover exact package names / UnitIds:

```bash
moonset status --output json
```

Then create a changeset non-interactively:

```bash
# Single-ecosystem MoonBit package
moonset add \
  --package unmbt/example/core \
  --type minor \
  --summary "Add streaming parser API" \
  --json

# Mixed workspace (repeat --package for multiple units)
moonset add \
  --package moonbit:acme/engine \
  --package npm:@acme/engine \
  --type patch \
  --summary "Fix newline handling in engine and JS wrapper" \
  --json

# Intentionally no release (e.g., docs/CI/refactor PR)
moonset add --empty --json
```

Verify the changeset is recognized (exit code `0` means valid):

```bash
moonset status --since main --output json
```

> Note: `--since <ref>` inspects `merge-base(<ref>, HEAD)..HEAD` from committed `HEAD` only; uncommitted changes are excluded and warned.

### 3. Preview & Apply Version + Changelog (`version`)

```bash
# Read-only plan inspection
moonset status --verbose
moonset publish-plan --pretty

# Preview manifest diffs & Release PR markdown
moonset version --dry-run

# Apply version bumps, internal dependency updates, CHANGELOG.md, and .moonset/release-state.json
moonset version

# Commit the release changes (required before publish)
git add -A && git commit -m "chore: release"
```

If an interrupted `version` leaves `.moonset/version-journal.json`, recover with:

```bash
moonset version --recover
```

### 4. Prereleases (`pre`) & Snapshots (`--snapshot`)

```bash
# Enter prerelease mode (pass --initial-version to record baseline)
moonset pre enter alpha --initial-version
moonset version

# Check prerelease state
moonset pre status

# Graduate back to stable
moonset pre exit
moonset version
```

For snapshot versions (requires `"snapshot": { "enabled": true }` in `.changeset/config.json`; does not consume stable changesets or write `release-state.json`):

```bash
moonset version --snapshot canary --dry-run
moonset version --snapshot canary
```

### 5. Pack, Publish, Tag & Release Notes

```bash
# Optional: package archives first
moonset pack --dry-run --json
moonset pack --json

# Preflight then publish (requires clean working tree & committed release-state.json)
moonset publish --dry-run --json
moonset publish --yes --json

# If --no-tag was used or tags need pushing separately
moonset tag --dry-run
moonset tag --push --yes

# Extract changelog body for GitHub Releases (read-only)
moonset release-notes --from-state --json
```

## Reference Guides (Load On Demand)

Read only the specific reference needed for the task at hand:

- **Full CLI flags, exit codes (`0/1/2/3`), JSON envelopes & error codes**: [references/cli-reference.md](./references/cli-reference.md)
- **`.changeset/config.json` options & mixed MoonBit/npm/pnpm/Cargo setup**: [references/configuration-and-mixed.md](./references/configuration-and-mixed.md)
- **GitHub Actions templates (PR Bot & Release automation) + `SEC-005` security rules**: [references/github-actions.md](./references/github-actions.md)
- **Troubleshooting common failures (journal recovery, credentials, `moon.mod.json` error, partial publish)**: [references/troubleshooting.md](./references/troubleshooting.md)
