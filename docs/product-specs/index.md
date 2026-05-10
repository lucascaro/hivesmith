# Product specs

The *what* and *why* of work this project plans to do. Each spec describes user value, success criteria, and explicit non-goals. The *how* lives in `docs/exec-plans/`.

## Active

| Priority | Issue | Title | Stage | Spec |
|----------|-------|-------|-------|------|
| P1 | #11 | Add hive brain — a second brain for hivesmith | QA | [011-add-hive-brain-second-brain-for-hivesmith](011-add-hive-brain-second-brain-for-hivesmith.md) |

## Completed

| Issue | Title | PR | Shipped | Spec |
|-------|-------|----|---------|------|
| #<n> | <title> | #<pr> | <date> | [<slug>](<slug>.md) |

## Rejected

| Issue | Title | Reason |
|-------|-------|--------|
| #<n> | <title> | <one line> |

## Conventions

- Stage is owned by the exec plan, not the spec — when stage changes, update this index from the plan.
- Canonical lifecycle: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → QA → DONE`. `REVIEW` = PR open, `/ralph-loop` driving convergence. `QA` = PR merged, awaiting `/feature-qa` validation. `DONE` = QA verdict PASS recorded.
- A spec is created in TRIAGE and lives forever (it is the historical record of *why we built it*). The exec plan moves to `docs/exec-plans/completed/` on QA PASS; the spec stays put.
- `feature-next` reads from this file's Active table, ordered by priority.
