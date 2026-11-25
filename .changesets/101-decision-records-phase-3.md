---
issue: 99
type: added
bump: minor
pr: 103
---
- **Decision records, phase 3 of 3: an accepted record can stand in for you at the plan stop and the merge stop.**
  - **The mechanism:** `hs-decision authorize plan|merge` is the only way a record skips an operator stop. Exit 0 authorizes. Any other exit escalates to you with an `escalate: <reason>` line.
  - **Which records count:** only records accepted on origin's default branch, fetched when it runs, never the PR's own copy. A branch cannot authorize itself, and superseding or deleting a record upstream takes effect immediately.
  - **Plan stop:** a record with `authorizes: plan` and `plan_paths:` approves an `S` plan whose second opinion is `approve` at confidence ≥8, with no must-fix items, no record conflicts, and every file in scope.
  - **Merge stop:** a record with `authorizes: merge` merges a PR whose gate passed, as long as the PR touches nothing under `docs/decisions/`, `scripts/decisions/` or any accepted record's `merge_exclude:`. Every accepted `forbid:` check must pass on the exact head, and `/feature-loop` merges with `--match-head-commit`.
  - **Reporting:** every auto-merge posts a PR comment naming the record, and every stand-in emits a new `auto_approved` metric.
  - **Merge gate:** gains a fourth dimension, **decision records**, which checks every PR against the accepted records (`hs-decision check`, plus a read of the diff against relevant records).
  - **Breaking change to the stops:** this reverses the "exactly two operator stops" contract from the autonomous-by-default `/feature-loop`. Nothing changes until you accept a record with `authorizes:`.
