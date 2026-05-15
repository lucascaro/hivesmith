---
issue: 32
title: Decentralize indices and changelog to eliminate merge conflicts
type: enhancement
complexity: L
priority: P2
stage: IMPLEMENT
---

# Decentralize indices and changelog to eliminate merge conflicts

- **Exec plan:** [docs/exec-plans/active/032-decentralize-indices-and-changelog.md](../exec-plans/active/032-decentralize-indices-and-changelog.md)

## Problem

Working multiple features in parallel produces merge conflicts on three central files that every active PR touches:

1. `CHANGELOG.md` — every user-visible PR appends to the same `[Unreleased]` section.
2. `docs/product-specs/index.md` — every stage transition (TRIAGE → … → DONE) edits the same Active/Completed tables; `feature-populate-backlog` appends N rows at once; `feature-triage` reorders by priority.
3. `docs/exec-plans/tech-debt-tracker.md` — written by `gc-sweep`.

Per-spec, per-plan, per-brain-entry files are already decentralized and conflict-free. The conflict surface is concentrated in those three aggregates, and it scales linearly with parallelism — every additional concurrent feature increases the rebase burden.

## Desired behavior

Each PR writes only per-PR contribution files (`.changesets/<NNN>-<slug>.md`, spec frontmatter, optionally `.tech-debt/<id>.md`). A GitHub Action regenerates the three aggregates on push to `main`. A PR Action hard-fails any diff that touches a generated file (with a labelled escape hatch). N feature PRs can run concurrently with zero conflicts on shared files. Skills no longer perform read-modify-write on shared markdown tables.

## Success criteria

- Two branches that each (a) add a `.changesets/*.md` and (b) toggle a different spec's `stage:` can be merged in either order with **zero conflicts** on `CHANGELOG.md`, `docs/product-specs/index.md`, or `docs/exec-plans/tech-debt-tracker.md`.
- A PR that hand-edits `CHANGELOG.md` or `docs/product-specs/index.md` fails CI with an explicit error message and a documented bypass label.
- `scripts/regen-generated.sh` is idempotent: running it on a clean main produces an empty diff. Running it on a PR's `merge_commit_sha` catches interaction bugs pre-merge.
- The spec's YAML frontmatter `stage:` field is the sole source of truth for stage — no skill writes the index directly; the exec-plan `Stage:` line is removed.
- Release flow (`scripts/release.sh`) pins to a starting SHA, rolls `.changesets/*.md` into a stamped version section, and lands via a release PR.
- `hivesmith-init`-managed downstream projects get a `.hivesmith/template-version` stamp and a `hivesmith doctor` mode that offers migration when out of date.

## Non-goals

- Eliminating conflicts on per-feature files (specs, exec plans). Those are inherently one-PR-per-file and don't conflict.
- Changing the canonical lifecycle (`TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → QA → DONE`).
- Replacing markdown for any of the source-of-truth or generated files. YAML frontmatter is the only structured-data addition.
- Adopting GitHub merge queues. (Recommended as a future orthogonal improvement; not in scope here.)
- Building a general-purpose markdown-frontmatter library. The regenerator is hivesmith-specific.

## Notes

The full design plan went through plan-mode iteration and adversarial review before implementation. The decision ledger (12 findings triaged, 8 accepted, 4 rejected with reasons) is reproduced verbatim in the exec plan's Decision log.
