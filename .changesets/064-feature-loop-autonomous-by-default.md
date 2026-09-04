---
issue: 64
pr: 65
type: changed
bump: minor
---
- **`feature-loop` is now autonomous by default.** One invocation takes a description to a merge-ready PR with exactly two operator stops: approving the plan, and merging. The run asks a quick round of clarifying questions up front (with its assumptions stated explicitly), auto-classifies triage without a gate, researches, asks a second sharper round only for ambiguities the research actually surfaced, then drafts a plan carrying a reviewer subagent's second opinion inline. After the plan is approved, implement → checks → push → PR → `/review-loop` → `/merge-gate` run without prompting. The merge is never automatic under any signal.

  The `--full-auto` flag and the `plan <description>` entry form are **removed** — the behaviour they gated is the default, and there is one path instead of three. Triage no longer prompts — it still fills `type`/`complexity`/`priority` into spec frontmatter so the generated index stays useful, then advances the run to `RESEARCH` on its own. `/feature-loop` also resolves the `[github] create_issues` policy without prompting (`opt-out`/`always` create, `opt-in` stays local), prompting only under `ask`; `/feature-new` is unchanged.

  Stalls are bounded: a failed `AGENTS.md` check or a `FAIL` gate verdict gets exactly one retry before the run stops, and a `/review-loop` escalation stops immediately.

- **`feature-loop` reads and writes the hive brain.** The Phase 3 research subagents run `brain-search` and return distilled bullets, so raw entries never enter the orchestrator's context — retrieval is capped at 8 ranked hits with at most 3 full reads. After a PASS gate verdict and before the merge stop, the run appends at most one `scope=project` entry capturing what a future run would want to have known; nothing is written on an escalated or failed run, or when no durable lesson surfaced.
