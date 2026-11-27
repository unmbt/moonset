---
"moonbit:unmbt/moonset": minor
---

Complete full audit remediation across workspace, engine, changelog, executor, CLI, Actions, and wasm-gc core facade:

- Fix MoonBit `private = true` visibility mapping to `Private` (governed by `privatePackages`), custom `--config` `pre.json` propagation, `Reader` directory caching across repeated globs, UTF-8 BOM `Cargo.toml` byte spans, journal retention across `format_files`, `NativeHost::run` default timeout, and matrix-mode verified tarball publishing.
- Add Yarn workspace/lockfile/pack/publish support, stateless `tag` fallback (`--from-manifests`), `alsoSkipDependentsOfSkipped`, `commit: true` / `commit.skipCI`, real `format: auto` detection + `deno`, line-level changelog hooks (`ChangelogLineHooks` & JSONL `protocol: line`), and empty-release changelog cleanup.
- Add CLI flags `--snapshot-prerelease-template`, `--pr-body-out`, `status -o` / `--marker-scope`, `publish --access` / `--ignore-scripts` / `CHANGESETS_OUTPUT`, automatic default branch detection in `init`, and `GITHUB_SERVER_URL` + multi-partition PR bot markers.
- Harden GitHub Actions (`pr-check` built-in release PR skip, single-call `version` + empty-commit guard, `commit-mode: github-api`, `published-packages` output, and CI `shellcheck`), add `unmbt/moonset/core` `wasm-gc` pure facade, enforce `MOONSET_ALLOWED_PLUGIN_PROGRAMS` host allowlist, and split `executor/publish.mbt` & `cli/tui_app.mbt`.
