---
type: changed
bump: patch
---
- **`regenerate-generated` direct-pushes again, and fails loudly when it can't.** The PR-based path added in the previous change worked, but GitHub requires manual approval for workflow runs on any PR authored by `github-actions[bot]` — so every merge to `main` left a regen PR parked behind an "Approve and run" click. That is not automation. The job is back to a direct push, which requires the pushing identity to be allowed through branch protection: add the github-actions app (id `15368`) as a **bypass actor on a ruleset**, or set a `REGEN_TOKEN` secret. Rulesets are the only option that works on user-owned repos — classic branch protection's `bypass_pull_request_allowances` is organization-only and 422s elsewhere.
- **A rejected push is now a hard failure with the fix in the log**, instead of a silent no-op. The original version of this job failed on every push to `main` for roughly three months without anyone noticing, because a failing regenerator looks exactly like a passing one from the outside.
