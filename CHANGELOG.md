# Changelog

All notable changes to hivesmith are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versioning follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- **Harness scaffolding.** `hivesmith-init` now lays down a `docs/` system-of-record tree (`design-docs/`, `exec-plans/{active,completed}/`, `product-specs/`, `references/`, `generated/`) and top-level stubs (`DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `FRONTEND.md`, `golden-principles.md`). `AGENTS.md` is now a ~70-line table of contents pointing into the new tree, following the pattern documented in OpenAI's "Harness engineering" post.
- `ralph-loop` skill — drives a PR through review → autofix → re-review until findings clear or escalation criteria hit (max iterations, loop-detection, RISKY-fix authorization, repeated CI failure). Independent of the feature pipeline; works on any PR.
- `doc-garden` skill — recurring sweep over `docs/` for staleness signals (broken cross-links, dead symbol references, generated-doc drift, resolved tech-debt rows). Opens one scoped fix-up PR per doc.
- `gc-sweep` skill — reads `golden-principles.md`, scans the codebase for deviations, and opens small targeted refactor PRs (one principle violation cluster per PR). Updates `QUALITY_SCORE.md` and tech-debt tracker.
- `hivesmith-init --migrate` — one-shot migration that splits existing `features/<state>/<NNN>-*.md` files into product specs (`docs/product-specs/`) and exec plans (`docs/exec-plans/{active,completed}/`). Decision log and progress preserved verbatim. Legacy `features/` is left untouched as a fallback.

### Changed
- **Feature pipeline writes to `docs/` first, falls back to `features/` for one release.** Specs land in `docs/product-specs/`, exec plans in `docs/exec-plans/{active,completed}/`. The historical record (the *what* and *why*) and the engineering log (the *how* with append-only Decision log + Progress) are now separate artifacts. `feature-{ingest,new,triage,research,plan,implement,loop,next}` updated.
- `feature-implement` and `feature-loop` now drive PR convergence via `/ralph-loop` after opening the PR, rather than stopping at "PR opened". Option 1 in `feature-loop` Gate 5 is the recommended path.
- `templates/AGENTS.md` rewritten as a table of contents that points into `docs/` and the new top-level stubs, instead of inlining module-map / build-test / convention sections.
- `templates/AGENTS.hivesmith.md` documents the new `docs/` layout, `ralph-loop`, `doc-garden`, and `gc-sweep`.

## [0.3.0] — 2026-04-21

### Changed
- `install.sh` — auto-upgrade cron is now **opt-in** (`--auto-upgrade`); the choice is persisted as `auto_upgrade` in `~/.hivesmith.toml`, so subsequent runs honor it without re-passing the flag. `--no-auto-upgrade` opts back out and removes any existing cron. `--no-auto-update` is kept as a deprecated alias. Existing cron entries are detected on first upgrade and treated as implicit opt-in so nothing disappears unexpectedly.

### Added
- `autofix` skill — automatically fix safe, low-risk findings from `/review-pr` output, CI failures, or PR feedback comments. Classifies each finding by fix confidence: mechanically determinable fixes are applied in batch; risky or ambiguous items are surfaced individually for the user to approve, skip, or redirect. Runs project checks after applying fixes.
- `namecheck` skill — check whether one or more candidate names are free on npm, GitHub (user / org / repo), and popular TLD domains (`.com .net .org .io .dev .app .ai` by default; `--tlds` to override, `--no-domains` to skip). Domains are resolved via RDAP (cached IANA bootstrap) with a `whois` fallback for TLDs without RDAP (notably `.io`). Backed by `skills/namecheck/namecheck.sh`.

## [0.2.1] — 2026-04-13

### Security
- Harden feature pipeline against stored prompt injection: GitHub issue body is now wrapped in `EXTERNAL CONTENT` markers on ingest, and all pipeline skills (`feature-triage`, `feature-research`, `feature-plan`, `feature-implement`, `feature-loop`) include an explicit anti-injection rule.
- SHA-pin third-party GitHub Actions (`action-shellcheck`, `gitleaks-action`, `action-actionlint`) to prevent supply chain compromise via mutable tags.

### Changed
- `feature-loop` skill — all confirmation gates now use `AskUserQuestion` with numbered choices; Gate 5 (push/PR) lets the user choose between `/review-pr`, `/gstack-review`, or skipping review.

## [0.2.0] — 2026-04-12

### Added
- `feature-loop` skill — drives a single feature through the full pipeline (TRIAGE → RESEARCH → PLAN → IMPLEMENT → DONE) with confirmation gates at each stage, auto-runs `/review-pr` after PR creation.
- OSS-readiness: CONTRIBUTING.md, SECURITY.md, PR template, issue templates, CI + secret-scanning workflows, Dependabot for GitHub Actions.
- `install.sh`: fail fast with a clear error if `python3` is missing.

### Changed
- README rewritten with "Why" section, MIT badge, and improved organization.
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
