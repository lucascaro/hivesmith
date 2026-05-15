---
type: changed
bump: minor
---
- **Existing PR review threads are no longer ignored by `review-loop`.** `autofix` now fetches review *threads* via the GitHub GraphQL API (with `isResolved` + `thread_id`), treats every unresolved thread as a finding, and closes each one by either applying a fix and replying `Fixed in <SHA>.` + resolving the thread, or replying with a concrete rationale and resolving. Threads without a specific articulable rationale are surfaced as RISKY rather than silently dismissed. `review-loop` cannot return `APPROVE` while any thread remains unresolved; the unresolved-thread set is incorporated into the loop-detection hash, and at max iterations the loop escalates with the open thread URLs. `review-pr` no longer drops a finding just because it appears in `prior_comments` — reviewers re-flag independently identified issues so dedup happens by `thread_id` downstream. Closes the gap that twice let dangerous Copilot/human comments survive a "converged" PR.
