---
issue: 79
type: added
bump: minor
pr: 81
---
- **`/brainstorm` — a problem-space front door to the feature pipeline.** Nothing before `/feature-new` asked whether an idea was worth building, so the spec sections `/merge-gate` later validates a PR against — `## Success criteria` and `## Non-goals` — arrived thin or empty. The new skill interrogates the *problem* in at most three batched rounds (never the implementation: no file lists, no approaches, no test names — those stay owned by `/feature-research` and `/feature-plan`), drafts all four narrative spec sections, gates them with the operator, then hands them to `/feature-new`, which keeps its single implementation of the `[github] create_issues` policy. "Not worth building" and "that's four features, not one" are first-class outcomes. `/feature-loop` now refuses a description that names no concrete observable change and points here; that refusal approves nothing, so the loop still has exactly two approval gates.
