---
type: added
bump: minor
---
- **`feature-qa` skill** — post-merge validation stage. Runs build/lint/test plus checks against the spec's `## Success criteria` and `## Non-goals` via fanout sub-agent workers (acceptance, non-goals, regression, doc accuracy). Writes an append-only `## QA verdict` entry to the exec plan; on PASS advances Stage → DONE and moves the plan to `completed/`; on FAIL/NEEDS_FOLLOWUP opens follow-up issues and holds at QA. Closes the lifecycle gap between "PR merged" and "feature actually delivers what the spec promised".
