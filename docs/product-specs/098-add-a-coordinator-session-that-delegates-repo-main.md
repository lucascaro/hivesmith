---
issue: 98
title: Add a coordinator session that delegates repo maintenance to subagents and runs periodic jobs
type: enhancement
complexity: L
priority: P2
stage: RESEARCH
---

# Add a coordinator session that delegates repo maintenance to subagents and runs periodic jobs

- **Exec plan:** [docs/exec-plans/active/098-add-a-coordinator-session-that-delegates-repo-main.md](../exec-plans/active/098-add-a-coordinator-session-that-delegates-repo-main.md) (or completed/)

## Problem

A maintainer running hivesmith from a single session does most of the coordination by hand. They have to remember which of the roughly 30 skills applies at each stage. They track parallel features, PRs and sweeps in their head, and often learn late that one of them needed a decision. Periodic maintenance (gardens, gc-sweep, dependency bumps, brain-garden) only happens when they remember to start it, and nothing does market/competitive research or feature ideation at all. The result is that hands-on work agents could own stays with the operator, and decisions get lost across streams.

## Desired behavior

**Phase 1: coordinator.**
- The operator works through one coordinator session. It understands requests and routes them to existing hivesmith skills or subagents, which do the investigation and implementation. The coordinator itself never edits files or runs long investigations.
- It runs several streams in parallel (for example two features plus a PR queue) and surfaces only the decisions that need the operator: plan approval, merge, release and destructive actions.
- On a fresh session it reads durable state, not chat history. Without being asked, it shows every in-flight stream with its stage and lists the pending decisions.
- A task board lives in a local file shared by every worktree of the repo, under the repo's git common dir. It is never committed or pushed, and it regenerates automatically.
- The coordinator pulls triaged issues from the backlog and works them on its own when the work is safe and clear. Safe and clear means all four of these hold:
  - no accepted decision record (#99) conflicts with it;
  - an accepted record covers its direction;
  - the spec has checkable success criteria;
  - the task has low ambiguity and a reviewer agent has no feedback.

  If any one fails, the coordinator escalates to the operator.
- Agents file new issues for problems they discover along the way.
- The coordinator auto-merges only PRs in a category that an accepted record declares merge-eligible, and only after merge-gate passes. Every other merge waits for the operator.

**Phase 2: periodic cadence.**
- A repo declares which maintenance jobs run and how often.
- The jobs run unattended from a local session (`/loop` or cron) and produce only PRs, issues or reports.
- A job skips its run while its earlier output is still unreviewed.
- Coordinator status shows each job's last run, next run, and any output waiting on the operator.

**Phase 3: research and ideation workers.**
- Market/competitive research and feature-ideation jobs, runnable on demand or on the Phase 2 cadence.
- Each run writes a dated report under `docs/`, adds candidate features as TRIAGE specs, and records durable lessons in the hive brain.

Everything works in any hivesmith-installed repo, on any supported host. Existing skills keep working on their own.

## Success criteria

- **P1:** In a non-hivesmith repo with hivesmith installed, an operator starts the coordinator and asks for two features. Both reach PR-open in separate worktrees, and the coordinator session's transcript shows no file edits made by the coordinator itself.
- **P1:** The coordinator never releases or runs a destructive operation without an explicit operator answer in that session. It merges only PRs in a category that an accepted record declares merge-eligible, and only with a merge-gate PASS. Every such merge is listed in status.
- **P1:** The task board reflects every stream within one regeneration and is identical when read from any worktree. No board file ever appears in `git status`.
- **P1:** Given one triaged issue that the records cover and one they don't, the coordinator takes the covered issue to PR without operator input and escalates the uncovered one.
- **P1:** Kill and restart the session mid-stream. The coordinator's opening message lists every in-flight stream with its stage and every pending decision, and no finished stage is re-dispatched.
- **P1:** A request that matches an existing skill (for example "review PR 12") is routed to that skill, not reimplemented.
- **P2:** A repo can declare a job (for example code-garden daily). Run under `/loop`, the job produces a PR or issue without operator input. While its earlier output is still unreviewed, the next run exits early and logs a skip.
- **P2:** Coordinator status shows each declared job's last run, next due time, and any unreviewed output.
- **P3:** A research or ideation run produces a dated report under `docs/`, at least one TRIAGE spec, and brain entries. All three are discoverable via `/feature-next` and `brain-search`.
- **All phases:** `/feature-loop`, `/pr-queue`, `/review-loop` and the gardens still pass their existing tests and work when invoked directly.

## Non-goals

- Auto-release under any signal, and auto-merge outside the categories that records declare merge-eligible.
- A committed or pushed board, or any GitHub Projects sync.
- The decision records and correction loop themselves, which #99 covers.
- Parallel writers in one worktree. Implementation stays single-writer per worktree.
- Cloud or CI runners (routines, claude-code-action, gh-aw) for periodic jobs. This spec covers local runs only.
- Token or time budgets per run. The only cap is on unreviewed output.
- Replacing or deprecating `/feature-loop` or any other existing skill.
- Depending on Claude Code agent teams, which are experimental, Claude-only, and cannot resume.
- A GUI or dashboard. Status appears in the coordinator's chat output.

## Notes

Shipped in three phases (one PR each, per-phase gate). The operator chose one spec over three.

**Depends on #99.** The decision records and correction loop in #99 are the guardrail for autonomous work and auto-merge. Phase 1's autonomy criteria cannot pass until #99 ships.

**Open questions (from /brainstorm):**
- What "low ambiguity" means, stated in a form someone outside the conversation can check.
- Can Phase 3 research work on hosts without web access, or should it degrade gracefully?
- How does the coordinator's durable state relate to the existing exec-plan ledgers: one source of truth or two?

**Prior art and evidence (researched 2026-11-21):**
- obra/superpowers `subagent-driven-development`. The controller never codes. Its most expensive failure is re-dispatching finished work after compaction, which it fixes with a ledger. It forbids parallel implementers.
- Anthropic, "How we built our multi-agent research system": a multi-agent run costs about 15x a chat's tokens, delegation briefs decide quality, and agents tend to over-spawn. https://www.anthropic.com/engineering/multi-agent-research-system
- Cognition, "Multi-Agents: What's Actually Working" (2026-04): keep writes single-threaded, and use a clean-context reviewer as the best-evidenced win. https://cognition.com/blog/multi-agents-working
- Claude Code agent teams: experimental, no resume, same-file overwrite. https://code.claude.com/docs/en/agent-teams
- GitHub Agentic Workflows Repo Assist: scheduled maintenance, a few tasks per run, and output as issues and PRs only. https://github.github.com/gh-aw/gallery/maintaining-repos/
- Brain: `subagent-tool-grants-are-the-only-enforcement` (universal). "Coordinator never edits" must be enforced through tool grants, not prose.
