---
issue: 99
type: added
bump: minor
pr: 102
---
- **Decision records, phase 2 of 3: slug ids, pruning, and corrections that stay corrected.**
  - **Slug ids:** records are now `docs/decisions/YYYYMMDD-<slug>.md`, and the slug is the id. Two branches proposing records at the same time no longer fight over the next number. Proposing an identical title again is a no-op; a different title with the same slug is refused. `accept` and `supersede` take a slug.
  - **If you installed from main** before this change, any 4-digit `0001-<slug>.md` record still loads, but `hs-decision lint` names it and asks you to rename it to `YYYYMMDD-<slug>.md` and set `id:` to the slug.
  - **Regression checks:** a record can carry `forbid:` (an extended regex) and `paths:`. The new `hs-decision check` fails when code under `paths:` matches an *accepted* record's `forbid:`. That includes untracked files. Proposed records are never enforced.
  - **Corrections:** when you correct an agent, the hivesmith block in `AGENTS.md` now tells it to propose a record in the same session, with a `forbid:` check whenever the mistake is a code pattern. Once you accept it, the mistake can't quietly come back.
  - **`hs-decision prune [--apply]`:** lists superseded records and proposals older than 30 days, and deletes them only with `--apply`. Accepted records are never touched.
  - **`/doc-garden`:** now reports decision-record drift (lint problems, failing checks) and opens one PR that prunes stale records. It never edits, accepts or supersedes a record.
