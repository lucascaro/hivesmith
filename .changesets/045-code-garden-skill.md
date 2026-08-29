---
type: added
bump: minor
---
- **`/code-garden` skill.** Daily incremental code-hygiene sweep: rotates one category per run (stale refs, deprecated usage, dead code, lint drift, dep patches, TODO triage, test gaps, flaky tests), fixes one bounded thing, verifies, opens at most one small PR. State in a committed `.hivesmith/garden-ledger.md` so declined items are never re-proposed.
