# AGENTS.md

Table of contents for AI agents (and humans) working in this repo. **Keep this file short.** It is a map, not an encyclopedia. Detailed rules live in the linked files; this file just routes you there.

## Project Overview

<2–3 sentences. What this project is, the stack, the core user problem.>

## How to navigate this repo

| If you need to know... | Read |
|------------------------|------|
| What this project does at a high level | `README.md` |
| The architectural shape — domains, layers, cross-cutting concerns | [`DESIGN.md`](DESIGN.md) |
| Project-wide design beliefs | [`docs/design-docs/core-beliefs.md`](docs/design-docs/core-beliefs.md) |
| Per-decision design rationale | [`docs/design-docs/`](docs/design-docs/index.md) |
| What's planned and why (product-side) | [`docs/product-specs/`](docs/product-specs/index.md) |
| What's being built right now (engineering-side) | [`docs/exec-plans/active/`](docs/exec-plans/active/) |
| What was built and the decisions made along the way | [`docs/exec-plans/completed/`](docs/exec-plans/completed/) |
| Mechanical rules `gc-sweep` enforces | [`golden-principles.md`](golden-principles.md) |
| Reliability targets and verification | [`RELIABILITY.md`](RELIABILITY.md) |
| Security posture and trust boundaries | [`SECURITY.md`](SECURITY.md) |
| Quality grades per domain/layer | [`QUALITY_SCORE.md`](QUALITY_SCORE.md) |
| Product taste and tie-breaker heuristics | [`PRODUCT_SENSE.md`](PRODUCT_SENSE.md) |
| Frontend conventions (if applicable) | [`FRONTEND.md`](FRONTEND.md) |
| How planning works | [`PLANS.md`](PLANS.md) |
| Known shortcuts and deferrals | [`docs/exec-plans/tech-debt-tracker.md`](docs/exec-plans/tech-debt-tracker.md) |
| External docs pulled in for agent context | [`docs/references/`](docs/references/README.md) |

## Build / Test / Lint

All of these must pass before a PR merges. `/feature-implement` runs them.

- **Build:** `<command>`
- **Lint:** `<command>`
- **Tests:** `<command>`
- **Everything:** `<single command that runs all of the above>`

## Module Map

<Top-level packages/directories with one line each.>

- `src/<...>` — <...>

## Workflows

This project uses [hivesmith](https://github.com/lucascaro/hivesmith) skills:

- **Feature pipeline** — `/feature-next` → (`/feature-new` or `/feature-ingest <#>`) → `/feature-triage` → `/feature-research` → `/feature-plan` → `/feature-implement` → `/ralph-loop`
- **PR convergence** — `/ralph-loop` drives review-respond-iterate on any PR until findings clear or it escalates.
- **Doc gardening** — `/doc-garden` scans `docs/` for staleness and opens fix-up PRs.
- **Golden-principle GC** — `/gc-sweep` reads `golden-principles.md` and opens small refactor PRs for deviations.

The previous flat `features/` layout has moved into `docs/`: specs to `docs/product-specs/`, plans to `docs/exec-plans/{active,completed}/`. `feature-*` skills read the new locations and fall back to `features/` for one release.

## Documentation Maintenance

- `CHANGELOG.md` — every user-visible change goes under `[Unreleased]` (use `/changelog-update`; `/release` stamps the date).
- `AGENTS.md` (this file) — update when the navigation table or workflows change. Otherwise, edit the deeper files.
- `README.md` — update for user-visible feature additions or setup changes.
- `docs/` — update alongside the feature, not after. `/doc-garden` will catch drift but it's cheaper to keep it fresh.

## Commit Style

Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `release:`. Link issues with `Fixes #<number>`.
