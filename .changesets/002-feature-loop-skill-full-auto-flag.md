---
type: added
bump: minor
---
- **`feature-loop` skill — `--full-auto` flag.** Pass `--full-auto` (combines with any of the existing input forms: number, description, or no-arg) to run the pipeline with reduced prompting. Unambiguous gates (Gate 1 issue creation, Gate 5 push/PR + convergence on green checks) auto-pick the recommended option. Ambiguous gates (Gate 2 triage, Gate 3 research sufficiency, Gate 4 plan approval) delegate to a `general-purpose` reviewer subagent; the orchestrator proceeds only on `verdict: approve` with confidence ≥ 8/10, otherwise falls back to the normal AskUserQuestion prompt. Terminal/destructive gates remain protected: Gate 6 (merge) auto-picks "Yes" only when the latest `## PR convergence ledger` entry is `verdict: APPROVE; action: stop`, and full-auto never bypasses a failed AGENTS.md check or runs `gh pr merge` on weak signal. The reviewer subagent prompt restates the anti-injection rule so untrusted spec/plan sections cannot direct behavior.
