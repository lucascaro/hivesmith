---
type: added
bump: minor
issue: 78
pr: 80
---

- **`/pr-queue` — triage, explain, approve and land an inbound PR queue.** Orders open PRs by
  dependency and readiness, runs a read-only premise-first triage per PR (is the bug real, is the
  diff real or a line-ending conversion, is the base stale, is each red check mechanical or
  substantive, do the PR body's claims hold against the actual source), and explains each one in
  terms of what a user would notice. Every action is gated on a per-PR operator decision. Execution
  routes on push-ability: a fork or a protected branch is reviewed read-only with `/review-pr`,
  while a branch you can push to may go through `/review-loop`. Merging honors the repo's real
  mechanism, including merge queues, and never deletes a fork's branch.
- **Pipeline metrics gain `pr_triaged` and `pr_landed`.** Keyed by PR number and carrying no
  `feature` field, so queue throughput is measurable without ever mixing contributor PRs into this
  project's feature counts. `report.py` gains a `PR QUEUE` section, gated by 10 new cases in `scripts/metrics/backfill-test.sh`.
