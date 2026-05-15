# Contributing

## Setup

<Clone, install dependencies, run locally.>

```
git clone <repo>
cd <project>
<install command>
<run command>
```

## Build / Test / Lint

See `AGENTS.md` → "Build / Test / Lint Commands". All commands must pass before opening a PR.

## Feature Workflow

This project uses the [hivesmith](https://github.com/lucascaro/hivesmith) feature pipeline. From inside your AI coding agent (Claude Code, Codex, Gemini, Copilot, Factory):

1. `/feature-next` — see the current pipeline state and next recommended action
2. `/feature-new <description>` or `/feature-ingest <issue#>` — add a new item
3. `/feature-triage [#]` → `/feature-research [#]` → `/feature-plan [#]` → `/feature-implement [#]`
4. `/changelog-update` — scaffold a `.changesets/<NNN>-<slug>.md` for any user-visible change
5. `/review-pr <#>` — deep parallel review before merge
6. `/release <version>` — cut a release once at least one changeset is present

Specs live under `docs/product-specs/<NNN>-<slug>.md` with YAML frontmatter (`stage:` is the source of truth). Exec plans live under `docs/exec-plans/{active,completed}/`. Per-PR changelog entries live under `.changesets/`; `CHANGELOG.md` itself is **generated** on push to `main` by `scripts/regen-generated.sh` — never edit it directly. `docs/product-specs/index.md` and `docs/exec-plans/tech-debt-tracker.md` are generated the same way.

## Commit Style

<Conventional commits: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`, `release:`. Link issues with `Fixes #<number>`.>

## Pull Request Checklist

- [ ] Build, lint, and tests pass (see `AGENTS.md`)
- [ ] `.changesets/<NNN>-<slug>.md` added if user-visible (use `/changelog-update`); use the `no-changeset` PR label for docs- or CI-only changes
- [ ] `AGENTS.md` updated if module map or conventions changed
- [ ] Relevant docs updated (`README.md`, `docs/`)
- [ ] PR description references the issue (`Fixes #<number>`)

## Design Guidelines

<Project-specific design/UX rules go here. Delete this section if not applicable.>
