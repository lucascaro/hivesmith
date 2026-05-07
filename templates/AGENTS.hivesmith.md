<!-- BEGIN HIVESMITH -->
## Hivesmith workflow

This project uses [hivesmith](https://github.com/lucascaro/hivesmith) skills. Keep the build/test commands below current — skills read this block to calibrate their work.

**Feature pipeline:** `/feature-next` → (`/feature-new` or `/feature-ingest <#>`) → `/feature-triage` → `/feature-research` → `/feature-plan` → `/feature-implement` → `/ralph-loop`

**PR convergence:** `/ralph-loop` drives review → autofix → re-review on any PR until findings clear or escalation criteria hit. Independent of the feature pipeline.

**Background workflows:**
- `/doc-garden` — scans `docs/` for staleness against the code, opens fix-up PRs.
- `/gc-sweep` — reads `golden-principles.md`, opens small refactor PRs for deviations.

**Philosophy: boil the lake.** Completeness is cheap when AI does the work. When a complete fix or implementation is a *lake* (bounded, achievable in the current change), do all of it — don't recommend or accept partial shortcuts and don't park the rest as "future work." Only treat something as an *ocean* (multi-quarter migration, cross-cutting contract change, requires coordination) if it genuinely is one — and when it is, say so explicitly and propose a staged plan rather than half-doing it. The default bias is toward doing all of it, now. Skills that consume this stance: `/review-pr`, `/autofix`, `/gc-sweep`, `/doc-garden`, `/feature-plan`, `/feature-implement`, `/ralph-loop`.

**Repository layout:**
- `docs/product-specs/` — what to build and why (the historical record).
- `docs/exec-plans/active/` — what's being built right now (decision logs append-only).
- `docs/exec-plans/completed/` — what was built (preserved for future agent runs).
- `docs/design-docs/` — non-obvious architectural decisions.
- `docs/references/` — external docs pulled in for agent context.
- `golden-principles.md` — mechanical rules `/gc-sweep` enforces.

The legacy `features/` layout is read with one-release fallback; new work lands in `docs/`.

**Changelog:** user-visible changes go under `## [Unreleased]` in `CHANGELOG.md` via `/changelog-update`. `/release` stamps the date and cuts the tag — do not edit release dates by hand.

**Build / test / lint commands** — `/feature-implement` expects all of these to pass before opening a PR:

- **Build:** `<command>`
- **Lint:** `<command>`
- **Tests:** `<command>`
- **Everything:** `<single command that runs all of the above>`
<!-- END HIVESMITH -->
