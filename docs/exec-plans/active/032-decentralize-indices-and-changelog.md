# Decentralize indices and changelog

- **Spec:** [docs/product-specs/032-decentralize-indices-and-changelog.md](../../product-specs/032-decentralize-indices-and-changelog.md)
- **Issue:** #32
- **Status:** active
- **PR:** —
- **Branch:** feat/decentralize-indices

## Summary

Drive `CHANGELOG.md`, `docs/product-specs/index.md`, and `docs/exec-plans/tech-debt-tracker.md` out of the PR diff. Each PR writes per-PR contribution files (`.changesets/`, spec frontmatter, `.tech-debt/`); a GitHub Action regenerates the three aggregates on push to `main`; a PR Action hard-fails any direct edit to a generated file.

## Research

- Current centralized writers (skill list): `changelog-update`, `feature-{new,triage,research,plan,implement,qa,populate-backlog,loop,next}`, `release`, `gc-sweep`, `hivesmith-init`. See `skills/*/SKILL.md`.
- Current CI: `.github/workflows/ci.yml` — `changelog` job requires `[Unreleased]` non-empty (lines 74–89).
- Current spec layout: `docs/product-specs/_template.md` has no YAML frontmatter today; `docs/product-specs/index.md` carries Stage/Type/Complexity/Priority as table cells.
- Current exec-plan layout: `docs/exec-plans/_template.md` carries `Stage:` (per the index conventions block, "Stage is owned by the exec plan"). This plan reverses that — frontmatter becomes sole SoR for Stage.
- Existing per-item pattern that works: brain entries (`~/.hivesmith/brain/entries/`) regenerate `INDEX.md` via `scripts/brain/index.sh`. Reuse that idea here.
- PR #28 (just landed): `feature-plan` and `feature-loop` use a runtime-neutral draft+approve pattern (native plan mode vs inline). Both branches must honor the new "stage write is last" + "frontmatter as SoR" rules.

## Approach

Adopt a single-process Python frontmatter parser. Stdlib-only — the frontmatter we use is flat scalars (`key: value` per line), so a small hand-rolled parser in `scripts/regen-generated.py` is plenty and avoids a PyYAML dependency. One process reads every spec/changeset/tech-debt file in one pass; scales to ~500 specs in <1s. Bash wrapper for CI portability and shellcheck conformance.

### Files to change

- `.github/workflows/ci.yml` — replace `changelog` job; add `regenerate-generated` (main push), `block-generated-edits` (PR, with `regen-override` label bypass), `verify-generated` (PR, dry-run regen + `merge_commit_sha` interaction-bug pre-check + changeset presence).
- `CHANGELOG.md` — header tweak; `[Unreleased]` body becomes generated.
- `docs/product-specs/index.md` — becomes fully generated (`<!-- generated, do not edit -->` header).
- `docs/product-specs/_template.md` — adds YAML frontmatter section to the template.
- `docs/product-specs/{011,016,020,024}-*.md` — add frontmatter to each.
- `docs/exec-plans/_template.md` — remove `Stage:` line (frontmatter is sole SoR).
- `docs/exec-plans/active/{016,020}-*.md` and completed `{011,024}-*.md` — remove `Stage:` line.
- `scripts/release.sh` — capture `RELEASE_SHA` at start, call regen with `--release <version>` to roll changesets, verify `origin/main` hasn't advanced before pushing, then direct-push (matches existing behavior). The SHA pin is the race protection; the release PR pattern was considered but not adopted because it would require restructuring `gh release create` to attach to a separate PR commit.
- `skills/*/SKILL.md` — 13 skills per audit table; stage write is the last write in each multi-write sequence; idempotent recovery on partial state; never edit generated files directly.
- `templates/CHANGELOG.md` — "managed by `.changesets/`" boilerplate.
- `templates/scripts/release.sh` — invoke new regenerator on release.
- `templates/AGENTS.md`, `templates/AGENTS.hivesmith.md`, `templates/CONTRIBUTING.md` — "how do I record a change" → `.changesets/`.
- `templates/docs/product-specs/_template.md` (if exists) — match new spec template.

### New files

- `scripts/regen-generated.sh` — bash wrapper + embedded Python parser. Supports `--release VERSION` to roll changesets into a stamped section.
- `scripts/migrate-to-changesets.sh` — one-shot migration tool (parses current `[Unreleased]` bullets + current `index.md` rows). Used by this PR and shipped for downstream consumers via `hivesmith-init`.
- `.changesets/README.md` — schema, naming, sort rule.
- `.changesets/.gitkeep` — to keep the empty dir tracked between releases.
- `.changesets/032-decentralize-indices.md` — this PR's own changeset (with the agent-runnable migration instructions).
- `templates/.changesets/README.md` — downstream-project copy.
- `templates/.hivesmith/template-version` — stamp file for `hivesmith doctor` to detect stale layouts.

### Tests

This repo uses shell-script smokes, not unit tests. Equivalent verifications:

- `scripts/regen-generated.sh` is idempotent on a clean tree (run twice → second produces zero diff).
- Conflict smoke: two branches off `main`, each adds a `.changesets/*.md` and toggles a different spec's `stage:`, both merge to a third branch with **zero** conflicts on `CHANGELOG.md` / `index.md` / `tech-debt-tracker.md`.
- Hand-edit guard: PR that edits `CHANGELOG.md` directly fails `block-generated-edits`; same PR with `regen-override` label passes.
- Source-fault guard: PR adding a `.changesets/X.md` with invalid `type:` fails `verify-generated` with the regenerator's error.
- Interaction-bug guard: PR pair that's individually valid but jointly invalid (e.g. rename spec in A + reference old issue in B's changeset) — `verify-generated` against `merge_commit_sha` catches it on the second PR.
- Release smoke: bump VERSION, run `scripts/release.sh` — `.changesets/` is emptied, new `## [X.Y.Z] — <date>` section appears, `[Unreleased]` body is regenerated empty.
- Shellcheck: `scripts/regen-generated.sh` and `scripts/migrate-to-changesets.sh` are listed in CI's `additional_files`.

## Decision log

- **2026-05-15** — Frontmatter is the sole source of truth for `stage:`; `Stage:` line removed from exec-plan template. Why: adversarial review #5 — two writers with no arbiter risks unrecoverable hybrid state on partial writes.
- **2026-05-15** — Sort `.changesets/` strictly by filename (monotonic `NNN-slug.md`) within each `### <Type>` section, never by content or timestamp. Why: adversarial review #11 — content-based sort produces gratuitous bot-commit churn and re-introduces conflicts on long-running branches.
- **2026-05-15** — Single Python process for frontmatter parsing; not one subprocess per file. Why: adversarial review #10 — 30ms × N file forks doesn't scale to 500 specs and runs on every PR.
- **2026-05-15** — `block-generated-edits` has a `regen-override` label bypass; `no-changeset` defaults to trust (no path-filter gating). Why: adversarial review #7 (need an escape hatch for the migration PR itself + regen bug fixes) and #12 reject (default trust is fine).
- **2026-05-15** — Bot direct-pushes to `main` with `[skip ci]`. Why: branch protection allows GitHub Actions to bypass in this repo's config; `[skip ci]` prevents runaway retrigger (adversarial review #1/#2 rejected).
- **2026-05-15** — `verify-generated` adds a `merge_commit_sha` pre-check to catch interaction bugs. Why: adversarial review #3 — two individually-valid PRs can fail regen jointly; surface the bug pre-merge.
- **2026-05-15** — `release.sh` pins to start-of-release SHA and verifies `origin/main` hasn't advanced before pushing. Why: adversarial review #6 — direct push races the regenerator bot. Chose SHA-pin over the release-PR pattern because the existing `gh release create` flow assumes the tag is reachable from the pushed commit; the SHA pin gives equivalent safety without restructuring `release.sh`.
- **2026-05-15** — Migration in a single PR with `regen-override` label. Why: simplest coherent state — the PR touches all three centralized files at once and downstream projects migrate via `scripts/migrate-to-changesets.sh` documented in the PR's own changeset.

## Progress

- **2026-05-15** — Branch `feat/decentralize-indices` created. Spec + exec plan filed at IMPLEMENT (plan was approved in plan mode).

## Open questions

- _Closed._ Issue #32 filed mid-PR; spec/plan/changeset renamed from `029` to `032` to match.

## PR convergence ledger

- **2026-05-15 iter 1** — verdict: APPROVE; findings_hash: empty; threads_open: 0; action: stop; head_sha: 0aaad6e.

## QA verdict

<empty until /feature-qa runs>
