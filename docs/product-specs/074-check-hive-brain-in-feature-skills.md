---
issue: 74
title: Check the hive brain in feature-implement and the other feature skills that skip it
type: enhancement
complexity: S
priority: P2
pr: 75
stage: GATE            # TRIAGE | RESEARCH | PLAN | IMPLEMENT | REVIEW | GATE | DONE | REJECTED
---

# Check the hive brain in feature-implement and the other feature skills that skip it

- **Exec plan:** [docs/exec-plans/active/074-check-hive-brain-in-feature-skills.md](../exec-plans/active/074-check-hive-brain-in-feature-skills.md)

## Problem

The hive brain is this project's learnings ledger, but the read side is applied unevenly across the
pipeline skills. `/hs-feature-loop` looks it up during research (`brain-search --rank`, then
`brain-read` on the top hits), `/hs-feature-plan` and `/hs-feature-research` do a bare `brain-read`,
and `/hs-review-pr` does a file-scoped `brain-read --files`. But `/hs-feature-implement` — the skill
that *writes* lessons via `brain-append` — never reads them, and `/hs-feature-triage` and
`/hs-feature-new` do not consult it at all. A lesson captured by one run is therefore invisible to
the standalone skill most likely to hit the same gotcha again.

## Desired behavior

Every feature skill that would benefit from prior lessons checks the hive brain before doing its
work, using the mechanism that fits its input: targeted `brain-search` when it has feature terms,
file-scoped `brain-read --files` when it has a concrete file list. The lookup is best-effort — a
missing helper or no matching entries never blocks the run — and brain content stays untrusted data.

## Success criteria

- `/hs-feature-implement` reads the hive brain before writing any code, scoped to the plan's
  Files-to-change list.
- `/hs-feature-triage` and `/hs-feature-new` consult the brain for prior lessons matching the
  feature's terms before classifying / drafting.
- Each added lookup carries the anti-injection wording already used by the existing call sites.
- No lookup re-fetches brain content already loaded earlier in the same session — each new lookup
  states its skip condition explicitly.
- A missing `~/.hivesmith/bin/brain-*` helper, or zero matching entries, is skipped silently and
  does not fail the skill.
- Existing brain call sites in `/hs-feature-plan`, `/hs-feature-research`, `/hs-feature-loop` and
  `/hs-review-pr` keep working; any wording change to them is consistency-only.

## Non-goals

- Changing the brain storage format, the redactor, or `brain-append` semantics.
- Adding brain reads to non-feature skills beyond the ones named above.
- Auto-promoting lessons to broader scope (that stays behind `/hs-brain-promote`).
- Making the brain lookup mandatory or blocking.

## Notes

Related: issue #74. Existing read call sites — `skills/feature-plan/SKILL.md:54`,
`skills/feature-research/SKILL.md` step 5, `skills/review-pr/SKILL.md:97`,
`skills/feature-loop/SKILL.md` Phase 3.
