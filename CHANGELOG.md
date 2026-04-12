# Changelog

All notable changes to hivesmith are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `changelog-update` skill — guided `[Unreleased]` entry in Keep a Changelog format.
- `release` skill — pre-flight checks, version-bump suggestion, and wraps `scripts/release.sh`.
- `templates/CHANGELOG.md` — seed file scaffolded by `hivesmith-init`.
- `install.sh --prefix` — namespace all skills (e.g. `hs-feature-plan`). Prefix is persisted in `~/.hivesmith.toml`, rendered copies live under `.rendered/<prefix>/`, cross-skill references inside SKILL.md are rewritten so the pipeline works end-to-end with the prefix. Uninstall and update read the stored prefix.
- `templates/AGENTS.hivesmith.md` — append-only hivesmith instructions block with `<!-- BEGIN/END HIVESMITH -->` markers.

### Changed
- `hivesmith-init` now scaffolds `CHANGELOG.md`.
- `hivesmith-init` no longer clobbers an existing `AGENTS.md`; instead it asks the user before appending the delimited hivesmith instructions block. Full `templates/AGENTS.md` scaffold only runs when `AGENTS.md` is missing.
- `feature-implement` delegates changelog entry to `/changelog-update` instead of inline edits.
- `templates/CONTRIBUTING.md` and `templates/AGENTS.md` reference the new skills.

## [0.1.0] — 2026-04-12

### Added
- Initial extraction from claude-mux: 8 feature-pipeline skills plus `review-pr`.
- `hivesmith-init` skill for per-project template scaffolding.
- Multi-agent installer (`install.sh`) targeting Claude Code, Codex, Gemini, Copilot, Factory.
- `agents.json` for declarative agent-dir targeting.
- `.hivesmith.toml` user config for per-skill opt-out.
- Claude plugin packaging (`claude-plugin/`, `marketplace.json`) as secondary install path.
- Templates: `AGENTS.md`, `CONTRIBUTING.md`, `features/BACKLOG.md`, `features/templates/FEATURE.md`, `features/ingest.sh`, `scripts/release.sh`.
