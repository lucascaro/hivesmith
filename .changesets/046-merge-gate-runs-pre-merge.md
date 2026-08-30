---
pr: 57
type: changed
bump: minor
---
- **`/feature-qa` is now `/merge-gate`, and it runs before the merge instead of after.** Every feature used to ship in two PRs: the feature itself, then a follow-up chore PR carrying ~15 lines of bookkeeping (move the exec plan to `completed/`, flip `stage:`, add `pr:`/`shipped:`, append the verdict). That second PR was a write-ordering artifact — `/feature-loop` advanced the stage *after* `gh pr merge` and the QA skill refused to run on an unmerged PR, so the bookkeeping had nowhere to land but a new PR.

  The gate now runs on the still-open PR branch once `/review-loop` converges, and commits its bookkeeping to that same branch. A feature ships in **one PR**. More importantly, a failing check is now a fix inside the PR rather than a follow-up issue filed against code that already shipped.

  The lifecycle stage `QA` is renamed **`GATE`**: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → GATE → DONE`. `/feature-loop`'s Gate 6 merge confirmation moved to the end of Phase 7 and now requires *both* a converged review ledger and a PASS gate verdict before `--full-auto` will merge. The exec-plan template's `## QA verdict` section is now `## Gate verdict`; older plans keep their existing heading and the gate appends to it.

  The gate dropped two of its five dimensions. `build/lint/test` was run three times per feature (pre-commit, CI, then again in QA) and `regression` substantially duplicated `/review-pr`; both are gone. What remains is what nothing else does: per-criterion traceability against the spec's `## Success criteria`, the `## Non-goals` negative check, and a doc-accuracy sweep.

  A degraded post-merge path is kept for recovery — if a PR is merged before the gate runs, `/merge-gate` still validates it and falls back to filing follow-up issues, since the code has shipped and can no longer be fixed in the PR.

  No migration is needed: no spec was at `stage: QA`. A spec still carrying it fails regeneration with `invalid stage 'QA'`, which names the fix.
