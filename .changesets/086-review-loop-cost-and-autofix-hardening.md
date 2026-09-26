---
issue: 86
type: added
bump: minor
pr: 87
---
- **`/review-loop` now records where each iteration's time goes.**
  - Every `review_iteration` event carries measured wall-clock for review (`review_s`), autofix (`autofix_s`) and the CI wait (`ci_wait_s`).
  - It also carries the worker's total token count when the runtime reports one.
  - The first iteration of a run that resumes a worker-raised escalation records how long it waited on a human (`escalation_wait_s`). This only works when the run resumes in the same worktree.
  - Nothing is estimated. A value that wasn't measured is left out, not zeroed.
  - From iteration 2 on, each BLOCKING/IMPORTANT finding is classified against the previous iteration's fix: inside it, near it, carried over, or new. `/review-loop` reads none of these back into its decisions; they are measurement only.
  - `findings_summary`, and with it `findings_count`, now lists BLOCKING and IMPORTANT findings only. Counts on rows from before this change aren't directly comparable.
- **`/autofix` hardens behaviour-changing fixes before committing them.** A risky fix you approve, or one you describe yourself, now goes through three steps:
  1. State the rule the fixed code must hold, derived from the code rather than the reviewer's suggestion.
  2. Check its callers, via graphify when it's wired up and grep otherwise, and ask before widening the fix.
  3. Add a regression test that is proven to fail with the fix reverted.
  - When there's no test, the summary gives the reason: no test command, a prompt/doc change, a test that still doesn't bite after one rewrite, or a test that has to live in the same file as the fix.
  - Each fix gets a `Hardening:` line in the summary, and `autofix_applied` counts fixes with and without a test.
  - SAFE fixes and merge-conflict resolution are unchanged.
- **`scripts/metrics/report.py` prints a `REVIEW LOOP COST` block.** It shows per-phase p50/p90, the finding-origin split, escalation wait, and autofix regression-test counts. It reads only rows that carry the new fields.
- **`hs-metric` rejects cost values that can't be true.** A negative duration or count now fails, as does a partial `origin_*` set or one that doesn't sum to `findings_count`, and a regression-test count that exceeds `risky`.
