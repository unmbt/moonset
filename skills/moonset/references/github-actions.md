# GitHub Actions Automation Reference

`moonset` provides modular composite GitHub Actions — no GitHub App or hosted server is required:
- `unmbt/moonset/setup@v1`: Downloads and SHA-256 verifies the pre-compiled `moonset` CLI.
- `unmbt/moonset/pr-check@v1`: Read-only PR changeset check (outputs `comment`, `state`, `should-comment`).
- `unmbt/moonset/pr-comment@v1`: Idempotent PR comment updater (no code checkout).
- `unmbt/moonset@v1`: Root release action (`mode: version-pr` and `mode: publish`).

## 1. PR Bot Workflow (`.github/workflows/moonset-pr-bot.yml`)

Two-job design safely supports external Fork PRs without exposing write tokens to untrusted PR code:

```yaml
name: moonset bot

on:
  pull_request_target:
    types: [opened, synchronize, reopened, ready_for_review]

concurrency:
  group: moonset-pr-bot-${{ github.event.pull_request.number }}
  cancel-in-progress: true

permissions: {}

jobs:
  check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
    outputs:
      comment: ${{ steps.check.outputs.comment }}
      state: ${{ steps.check.outputs.state }}
      should-comment: ${{ steps.check.outputs.should-comment }}
    steps:
      - uses: actions/checkout@v5
        with:
          ref: ${{ github.event.pull_request.head.sha }}
          fetch-depth: 0
          persist-credentials: false
      - id: check
        uses: unmbt/moonset/pr-check@v1
        with:
          base-sha: ${{ github.event.pull_request.base.sha }}
          head-repo: ${{ github.event.pull_request.head.repo.full_name }}
          head-ref: ${{ github.event.pull_request.head.ref }}

  comment:
    needs: check
    runs-on: ubuntu-latest
    permissions:
      pull-requests: write
    steps:
      - uses: unmbt/moonset/pr-comment@v1
        with:
          comment: ${{ needs.check.outputs.comment }}
          state: ${{ needs.check.outputs.state }}
          should-comment: ${{ needs.check.outputs.should-comment }}
```

Optional `pr-comment` inputs:
- `fail-on-missing: 'true'` — fail check when `state` is `missing` or `error`.
- `label: 'moonset/missing-changeset'` — add/remove label automatically (requires `issues: write`).

## 2. Auto Release PR & Publish Workflow (`.github/workflows/moonset-release.yml`)

Adjust `branches` (`main` vs `master`) to match `.changeset/config.json` `baseBranch`:

```yaml
name: moonset release

on:
  push:
    branches:
      - main

concurrency:
  group: moonset-release-${{ github.ref }}
  cancel-in-progress: false

permissions: {}

jobs:
  version-pr:
    runs-on: ubuntu-latest
    permissions:
      contents: write
      pull-requests: write
    outputs:
      has-changesets: ${{ steps.release.outputs.has-changesets }}
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - id: release
        uses: unmbt/moonset@v1
        with:
          mode: version-pr

  publish:
    needs: version-pr
    if: needs.version-pr.outputs.has-changesets == 'false'
    runs-on: ubuntu-latest
    concurrency:
      group: moonset-publish
      cancel-in-progress: false
    permissions:
      contents: write
      id-token: write
    steps:
      - uses: actions/checkout@v5
        with:
          fetch-depth: 0
      - uses: hustcer/setup-moonbit@v1
      - uses: unmbt/moonset@v1
        with:
          mode: publish
          mooncakes-credentials: ${{ secrets.MOONCAKES_CREDENTIALS }}
```

## 3. Security Rules (`SEC-005`) — Never Violate When Generating Workflows

1. **No untrusted builds under `pull_request_target`**: In the `check` job that checks out PR head code, **never** run `moon build`, `moon test`, `npm install`, `cargo build`, or custom scripts. Only run the trusted pre-compiled `moonset` binary.
2. **Keep `persist-credentials: false`** on the `pr-check` checkout and **never checkout code** in `pr-comment`.
3. **Separate tokens by job**: Never pass `MOONCAKES_CREDENTIALS` / `NPM_TOKEN` / `CARGO_REGISTRY_TOKEN` into `pr-check`, `pr-comment`, or `version-pr`.
4. **Prevent script injection**: Bind `${{ github.event.* }}` and `${{ inputs.* }}` to `env:` variables and quote `"$VAR"` in shell; never interpolate expressions directly into `run:`.
5. **Keep temporary binaries outside the repo**: If passing `binary-path` in `version-pr`, put the binary in `${{ runner.temp }}/moonset-cli` (never inside the repo, because `version-pr` runs `git add -A`).

## 4. Pre-Flight Setup Checklist (Remind the User)

1. **Enable PR creation by Actions**: Repository (or Org) **Settings → Actions → General → Workflow permissions** → check **Allow GitHub Actions to create and approve pull requests**.
2. **Configure `MOONCAKES_CREDENTIALS` secret**: Run `moon login` locally and paste the full contents of `~/.moon/credentials.json` into **Settings → Secrets and variables → Actions → `MOONCAKES_CREDENTIALS`**.
3. **Match `baseBranch`**: Ensure `on.push.branches` matches `baseBranch` in `.changeset/config.json`.
4. **Triggering binary builds on tag**: Pushing a tag with default `GITHUB_TOKEN` does **not** trigger `on: push: tags:` workflows. Chain a reusable workflow via `workflow_call` from `moonset-release.yml` instead of creating a long-lived PAT.
