---
issue: 64
title: Make feature-loop autonomous by default
type: enhancement
complexity: M
priority: P2
stage: IMPLEMENT
---

# Make feature-loop autonomous by default

- **Exec plan:** [docs/exec-plans/active/064-make-feature-loop-autonomous-by-default.md](../exec-plans/active/064-make-feature-loop-autonomous-by-default.md)

## Problem

`/feature-loop` only runs unattended when the operator remembers `--full-auto`, and only enters plan-first mode with a `plan` keyword. Without them it stops at six gates, several of which (issue creation, push/PR, "run the next stage?") have no real decision behind them. The operator ends up babysitting a pipeline that could run itself, and the two knobs that fix that are opt-in and undiscoverable. The loop also never reads the hive brain before planning and never writes back what the run taught it, so every run starts from zero.

## Desired behavior

One invocation drives a feature to a merge-ready PR with exactly one substantive human decision: approving the plan.

The default run is: quick clarifying questions from the description (assumptions called out explicitly) → auto-triage with no gate → hive-brain lookup for prior lessons → research → a second, sharper round of clarifying questions informed by that research → plan draft → reviewer-subagent second opinion attached to the draft → **human approves the plan** → implement → checks → push + PR → `/review-loop` → `/merge-gate` → self-reflection appended to the hive brain → **stop at merge** for human review.

`--full-auto` and `plan` are gone; there is one path. Subagents are used wherever they are cheaper or faster than the main thread (research fan-out, plan second opinion, reviewer/validator dispatch), but implementation stays in the main thread. Hard stops survive: a failed `AGENTS.md` check, a `/review-loop` escalation, a `FAIL` gate verdict, or an anti-injection hit each halt the run after at most one bounded auto-retry.

## Success criteria

- Invoking `/feature-loop <description>` with no flags asks clarifying questions, then runs to a merge-ready PR, prompting the user only at plan approval and at the merge.
- The skill file contains no `--full-auto` token and no `plan`-keyword input branch; `argument-hint` is `"[issue-number | description]"`.
- New-feature runs enter at RESEARCH (triage is auto-classified into spec frontmatter without a gate) and advance to PLAN when research completes.
- The plan presented for approval carries a reviewer-subagent verdict (`approve | revise | block`, confidence, rationale) inline; a `revise` verdict is applied once before the plan is shown.
- Before drafting the plan the skill queries `~/.hivesmith/bin/brain-search`; after a PASS gate verdict and before the merge prompt it appends one entry via `~/.hivesmith/bin/brain-append` with `scope=project` and `provenance.source=feature-loop`.
- Gate 1 (issue creation) follows the `[github] create_issues` policy silently; Gate 5 (push/PR) auto-selects the convergence path when checks are green; the merge is never automatic.
- A failed check, a review-loop escalation, or a `FAIL` gate verdict stops the run after at most one bounded retry, with the reason surfaced.
- Spec #20 no longer appears as an active row in `docs/product-specs/index.md`.

## Non-goals

- Changing the individual stage skills (`/feature-triage`, `/feature-research`, `/feature-plan`, `/feature-implement`, `/review-loop`, `/merge-gate`) — the loop orchestrates them; their contracts are untouched.
- Delegating implementation to subagents.
- Automating the merge under any signal.
- Promoting brain entries beyond `scope=project` (still gated by `/brain-promote`).

## Notes

Supersedes #20 (`--full-auto` flag, PR #21, merged) — this change removes the flag it added and makes its behavior the default.
