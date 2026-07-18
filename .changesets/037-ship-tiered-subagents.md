---
issue: 42
pr: 42
type: added
bump: minor
---
- **Hivesmith now ships subagents.** Two definitions under `agents/`, symlinked into `~/.claude/agents/` by `install.sh`: `hs-reviewer` (backs `/review-pr`'s per-dimension fan-out) and `hs-validator` (runs build/lint/test, backs `/feature-qa`'s validator fan-out). Both pin `model: sonnet` — these are the two highest-fanout dispatch sites in the pipeline, where every dimension previously inherited the session model. `/review-pr` dispatches its Security dimension with an explicit `model: opus` override, so security review is never downgraded. Both agents hold `disallowedTools: Edit, Write, NotebookEdit` and carry an anti-injection rule covering every channel they read — the diff most of all, since it is attacker-controlled and the first thing a reviewer opens. Both skills fall back to `Explore` / `general-purpose` when a dispatch errors on an unrecognized `subagent_type`. `agents.json` gains an optional per-harness `agents_dir` key; only `claude` declares one today, so other harnesses are unaffected until they opt in. Subagents honor `disable = ["hs-reviewer"]` in `.hivesmith.toml`, are swept when renamed or removed upstream, are re-enumerated after `--update` pulls, and never clobber a symlink `install.sh` does not own. A new `subagent-linking` CI job covers all of that with a real (non-dry-run) install.
