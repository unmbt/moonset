# Changelog

## 0.4.0 - 2026-11-27

### Minor Changes

- [`1cc035d`](https://github.com/unmbt/moonset/commit/1cc035ded85e339ebf985d539e90aa039717ac73) Thanks [@Wyatex](https://github.com/Wyatex)! - Complete full audit remediation across workspace, engine, changelog, executor, CLI, Actions, and wasm-gc core facade:

  - Fix MoonBit `private = true` visibility mapping to `Private` (governed by `privatePackages`), custom `--config` `pre.json` propagation, `Reader` directory caching across repeated globs, UTF-8 BOM `Cargo.toml` byte spans, journal retention across `format_files`, `NativeHost::run` default timeout, and matrix-mode verified tarball publishing.
  - Add Yarn workspace/lockfile/pack/publish support, stateless `tag` fallback (`--from-manifests`), `alsoSkipDependentsOfSkipped`, `commit: true` / `commit.skipCI`, real `format: auto` detection + `deno`, line-level changelog hooks (`ChangelogLineHooks` & JSONL `protocol: line`), and empty-release changelog cleanup.
  - Add CLI flags `--snapshot-prerelease-template`, `--pr-body-out`, `status -o` / `--marker-scope`, `publish --access` / `--ignore-scripts` / `CHANGESETS_OUTPUT`, automatic default branch detection in `init`, and `GITHUB_SERVER_URL` + multi-partition PR bot markers.
  - Harden GitHub Actions (`pr-check` built-in release PR skip, single-call `version` + empty-commit guard, `commit-mode: github-api`, `published-packages` output, and CI `shellcheck`), add `unmbt/moonset/core` `wasm-gc` pure facade, enforce `MOONSET_ALLOWED_PLUGIN_PROGRAMS` host allowlist, and split `executor/publish.mbt` & `cli/tui_app.mbt`.

### Patch Changes

- [`b47a950`](https://github.com/unmbt/moonset/commit/b47a9507d52c3ea391a508f2cb36e050e914200a) Thanks [@Wyatex](https://github.com/Wyatex)! - Migrate deprecated `@shell.Cmd` to `@process.Cmd` and avoid matching `@json.ParseError` internal constructors for MoonBit 0.1.20261126 compatibility.
- [`8491a54`](https://github.com/unmbt/moonset/commit/8491a54e19ed54bce6118fbf52db35494ab1e9cf) Thanks [@Wyatex](https://github.com/Wyatex)! - Align 'pre <enter|exit> [tag]' with Changesets v3 (remove 'pre status'), clean stale '.moonset/pack-results*.json' and '.moonset/pack/' when 'version' writes a new release state, and include version/commit details in 'stale-artifact' diagnostics.
- [`57948ca`](https://github.com/unmbt/moonset/commit/57948ca7a33aed773d075ddd2025f714e2d57a31) Thanks [@Wyatex](https://github.com/Wyatex)! - Harden Windows .cmd/.bat spawning, MoonBit dry-run & moon.work archive matching, deferred same-batch preflight, Cargo workspace sibling packaging, and .moonset/pack tarball output for npm/pnpm/yarn.
- [`2b2944d`](https://github.com/unmbt/moonset/commit/2b2944dab5a344ce805cf20ac105fd05a37411dd) Thanks [@Wyatex](https://github.com/Wyatex)! - Refresh the MoonBit registry index (`moon update` after polling `moon view`) and retry registry propagation misses between same-batch MoonBit workspace publishes, and print failed/blocked publish target summaries in `action.yml` on non-zero exit.

## 0.3.1 - 2026-11-25

### Patch Changes

- [`e0c99af`](https://github.com/unmbt/moonset/commit/e0c99afb7fff44119627a79c3c6004914aed716b) Thanks [@Wyatex](https://github.com/Wyatex)! - Adopt unmbt/cac@0.1.1 for declarative CLI command, subcommand, option, and help parsing, and adapt moonbitlang/core/async/fs calls (allow_existing and @fs.remove) to the latest MoonBit toolchain.
- [`62b9e73`](https://github.com/unmbt/moonset/commit/62b9e730649ddef707555a5d23ca473d7e63ee35) Thanks [@Wyatex](https://github.com/Wyatex)! - Upgrade doc-web design and UX: add double-Shift global search palette (with section-anchor deep links), View Transition navigation with scroll restoration, heading anchor copy, colored GitHub callouts, TOC sliding indicator and reading progress bar, and homepage entrance/scroll-reveal/beam-link/spotlight animations; include `skills/moonset` as an Agent Skills documentation section with a top-bar Skills entry; auto-sync version from `moon.mod`; self-host Latin fonts and lazy-load docs and terminal components to significantly reduce initial bundle size.

## 0.3.0 - 2026-11-22

### Minor Changes

- [`4cef5cf`](https://github.com/unmbt/moonset/commit/4cef5cf7b3ad967424e139fac7775276b36ad13f) Thanks [@Wyatex](https://github.com/Wyatex)! - Replicate @changesets/cli v3.0.3 (@clack/prompts) interactive `init` and `add` TUI workflows with the `🌙` banner, `-m`/`--message` alias, and pure `VERSION` constant generation (`scripts/gen-version.mbtx`) with release-PR auto-sync.
- [`cec87e3`](https://github.com/unmbt/moonset/commit/cec87e35d472e3ecf5dd04e1a5add7991b40f7a0) Thanks [@Wyatex](https://github.com/Wyatex)! - Converge architecture and API (`api_version = "2.0.0"`, ADR-008 & ADR-009), replace `mizchi/tui` with a built-in lightweight UTF-8 native TUI fixing Windows Chinese mojibake and IME input, align prerelease and snapshot flows with Changesets v3, harden Cargo/npm/pnpm workspace discovery and publishing, and fix GitHub Actions/installer reliability bugs.

### Patch Changes

- [`f957537`](https://github.com/unmbt/moonset/commit/f9575371defa968b13db82d6d046047b120feae4) Thanks [@Wyatex](https://github.com/Wyatex)! - Add interactive documentation website (doc-web) with SDD/ADR browser, Mermaid diagrams, xterm CLI demo, and GitHub Pages deployment workflow (.github/workflows/deploy-docs.yml).
- [`e7e64df`](https://github.com/unmbt/moonset/commit/e7e64df24bc61f79a19716299511c352a8e7153c) Thanks [@Wyatex](https://github.com/Wyatex)! - Fix group multiselect dimming/tree guides/footer hints, nested ANSI SGR preservation in style_text, and Windows console raw mode/confirm key handling.

## 0.2.0 - 2026-11-19

### Minor Changes

- [`2095fc4`](https://github.com/unmbt/moonset/commit/2095fc46c4b4dcb8d8b379bb202d1225e1e069d4) Thanks [@Wyatex](https://github.com/Wyatex)! - Implement v0.2.0 schema-defined configuration and routing capabilities (FR-026 through FR-031): external formatter execution (prettier/oxfmt/biome/dprint) with --no-format, full glob matching for fixed/linked/ignore and changedFilePatterns, snapshot configuration gating and prereleaseTemplate rendering, pre.directory isolation semantics, compound npm/Cargo SemVer range matching and rewriting, programmatic ApiPublisherRegistry for publisher.kind=api, and scoped mixed-ecosystem --registry/--tag mappings.

### Patch Changes

- [`5a36d82`](https://github.com/unmbt/moonset/commit/5a36d822047b02cd88b3b44b938560680f36685d) Thanks [@Wyatex](https://github.com/Wyatex)! - Fuse SDD into AGENTS.md, fix @v1 setup tag resolution, add release-notes & automatic GitHub Release creation, upgrade Release PR descriptions with full changelog details and PR/author metadata enrichment, unify Action audit-event outputs and v1 tag sync, and implement FR-022 multi-platform artifact matrix & separated build/publish DAG.

## 0.1.0 - 2026-11-18

### Minor Changes

- [`badcec4`](https://github.com/unmbt/moonset/commit/badcec4494c30c23490f2d8a72f3793cc898ff54) Thanks [@Wyatex](https://github.com/Wyatex)! - Add the Phase 5 extension ecosystem API, changelog generators, and JSONL plugin contracts.
- [`91b9e96`](https://github.com/unmbt/moonset/commit/91b9e965be6c79b29f206fcc7b86cc9e18c82e1f) Thanks [@Wyatex](https://github.com/Wyatex)! - Add modular PR Bot GitHub Actions (`setup`, `pr-check`, `pr-comment`), coexistence coordination export (`FR-023`), NFR-005 batch Git performance optimizations, user installation scripts (`~/.unmbt`), and Mooncakes publish readiness for `0.1.0`.

### Patch Changes

- [`1dabf99`](https://github.com/unmbt/moonset/commit/1dabf990e31ddc789911f3196b46de974535e487) Thanks [@Wyatex](https://github.com/Wyatex)! - Fix Phase 4 release workflow artifact invocation and status argument handling.
