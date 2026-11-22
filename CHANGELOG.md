# Changelog

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

