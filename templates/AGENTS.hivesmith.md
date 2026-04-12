<!-- BEGIN HIVESMITH -->
## Hivesmith workflow

This project uses [hivesmith](https://github.com/lucascaro/hivesmith) skills for feature work. Keep the build/test commands below current — skills read this block to calibrate their work.

**Feature pipeline:** `/feature-next` → (`/feature-new` or `/feature-ingest <#>`) → `/feature-triage` → `/feature-research` → `/feature-plan` → `/feature-implement` → `/review-pr`

Features live under `features/` (`active/`, `completed/`, `rejected/`). `features/BACKLOG.md` and the per-feature files under `features/active/` are the source of truth for work in flight.

**Changelog:** user-visible changes go under `## [Unreleased]` in `CHANGELOG.md` via `/changelog-update`. `/release` stamps the date and cuts the tag — do not edit release dates by hand.

**Build / test / lint commands** — `/feature-implement` expects all of these to pass before opening a PR:

- **Build:** `<command>`
- **Lint:** `<command>`
- **Tests:** `<command>`
- **Everything:** `<single command that runs all of the above>`
<!-- END HIVESMITH -->
