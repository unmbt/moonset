# Changelog

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
