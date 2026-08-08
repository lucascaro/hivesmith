---
type: fixed
bump: patch
---
- **Every in-flight exec plan can be handed off again.** `/feature-plan-handoff` gates on the exec plan's `## Verification` section, which was added to `docs/exec-plans/_template.md` in the previous release — so all five plans under `docs/exec-plans/active/` predated it and the gate refused every one of them. Backfilled each with runnable commands lifted from its own `### Tests` section plus the relevant `AGENTS.md` gates. `tests/manual/plan-lane-smoke.md` gains an automatable step that fails if any active plan (or either template) loses the section again.
- **Fix: the three plan skills disagreed about who backfills a missing `## Verification`.** `feature-plan-handoff` said `/feature-plan-review` does it, `feature-plan` said it did it itself. All three now state the same shared rule: `/feature-plan` and `/feature-plan-review` both backfill, whichever reaches the plan first; `/feature-plan-handoff` never does — it refuses, so the added commands get reviewed rather than waved through.
- **Fix: `HIVESMITH_PLAN_HTML=0` / `--no-html` became undiscoverable from `/feature-loop`.** Folding the duplicated plan-html invocation into a single canonical sequence dropped the opt-out mention from the file a user actually reads when they want to turn the HTML plan off. Restored at both call sites.
