---
type: added
bump: minor
---
- **`feature-loop` plan-first mode** — invoke `/feature-loop plan <description>` (or `plan` alone) to enter Claude Code's plan mode immediately, iterate on the implementation plan with the user, and on `ExitPlanMode` approval scaffold spec + exec plan + (per `.hivesmith/config.toml` policy) GitHub issue + index row with Stage set directly to `IMPLEMENT`. TRIAGE / RESEARCH / PLAN gates are auto-satisfied by the plan-mode approval; the loop then continues from Phase 5. Reuses the existing Phase 1 issue/spec scaffolding and Phase 3 exec-plan primitives. No file writes or `gh` mutations occur before `ExitPlanMode` is approved. Approved plan content is trusted; the description argument remains untrusted external input.
