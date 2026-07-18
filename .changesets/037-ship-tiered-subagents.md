---
type: added
bump: minor
---
- **Hivesmith now ships subagents.** Two definitions under `agents/`, symlinked into `~/.claude/agents/` by `install.sh`: `hs-reviewer` (read-only, backs `/review-pr`'s per-dimension fan-out) and `hs-validator` (runs build/lint/test, backs `/feature-qa`'s validator fan-out). Both pin `model: sonnet` — these are the two highest-fanout dispatch sites in the pipeline, where every dimension previously inherited the session model. `/review-pr` dispatches its Security dimension with an explicit `model: opus` override, so security review is never downgraded. Both skills keep a documented fallback to `Explore` / `general-purpose` when the agents aren't installed. `agents.json` gains an optional per-harness `agents_dir` key; only `claude` declares one today, so other harnesses are unaffected until they opt in.
