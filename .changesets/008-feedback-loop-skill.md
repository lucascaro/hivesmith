---
type: added
bump: minor
---
- **`feedback-loop` skill** — `audit` and `design` modes for the production-feedback loop of any app using hivesmith. Audit scores six dimensions (instrumentation, error visibility, user voice, metrics, triage cadence, closure of loop) 0–10 with evidence and writes a date-stamped trend report to `docs/design-docs/feedback-loop-audit-<date>.md`. Design proposes concrete fixes for low-scoring dimensions, writes `docs/design-docs/feedback-loop.md`, and auto-creates TRIAGE specs in the index for each unimplemented dimension.
