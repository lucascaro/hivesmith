---
type: added
bump: minor
---
- **PR convergence ledger** — `docs/exec-plans/_template.md` gains an append-only `## PR convergence ledger` section. `/review-loop` writes one line per iteration (verdict, findings_hash, action, head_sha) so a fresh harness run can resume the loop-detection guard from the last entry instead of restarting from iteration 1.
