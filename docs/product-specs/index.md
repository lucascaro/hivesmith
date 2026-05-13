# Product specs

The *what* and *why* of work this project plans to do. Each spec describes user value, success criteria, and explicit non-goals. The *how* lives in `docs/exec-plans/`.

## Active

| Priority | Issue | Title | Stage | Spec |
|----------|-------|-------|-------|------|
| P2 | #16 | Rename hs-ralph-loop skill to hs-review-loop | REVIEW | [016-rename-hs-ralph-loop-skill-to-hs-review-loop](016-rename-hs-ralph-loop-skill-to-hs-review-loop.md) |
| P3 | #20 | Add --full-auto flag to hs-feature-loop skill | IMPLEMENT | [020-add-full-auto-flag-to-hs-feature-loop-skill](020-add-full-auto-flag-to-hs-feature-loop-skill.md) |

## Completed

| Issue | Title | PR | Shipped | Spec |
|-------|-------|----|---------|------|
| #11 | Add hive brain — a second brain for hivesmith | #12 | 2026-05-10 | [011-add-hive-brain-second-brain-for-hivesmith](011-add-hive-brain-second-brain-for-hivesmith.md) |
| #24 | Add plan-first starting point to hs-feature-loop | #25 | 2026-05-12 | [024-plan-first-starting-point-for-feature-loop](024-plan-first-starting-point-for-feature-loop.md) |

## Rejected

| Issue | Title | Reason |
|-------|-------|--------|
| #<n> | <title> | <one line> |

## Conventions

- Stage is owned by the exec plan, not the spec — when stage changes, update this index from the plan.
- Canonical lifecycle: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → QA → DONE`. `REVIEW` = PR open, `/review-loop` driving convergence. `QA` = PR merged, awaiting `/feature-qa` validation. `DONE` = QA verdict PASS recorded.
- A spec is created in TRIAGE and lives forever (it is the historical record of *why we built it*). The exec plan moves to `docs/exec-plans/completed/` on QA PASS; the spec stays put.
- `feature-next` reads from this file's Active table, ordered by priority.
