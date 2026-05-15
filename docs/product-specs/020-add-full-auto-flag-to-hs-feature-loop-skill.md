---
issue: 20
title: Add --full-auto flag to hs-feature-loop skill
type: enhancement
complexity: M
priority: P3
stage: IMPLEMENT
---

# Add `--full-auto` flag to hs-feature-loop skill

- **Exec plan:** [docs/exec-plans/active/020-add-full-auto-flag-to-hs-feature-loop-skill.md](../exec-plans/active/020-add-full-auto-flag-to-hs-feature-loop-skill.md)

## Problem

Running `/hs-feature-loop` end-to-end currently requires a human to sit through six confirmation gates (issue creation, triage, research, plan, push/PR, merge) even when the right choice at each step is obvious. For low-risk features and routine work this wastes the user's attention and makes overnight/unattended runs impossible.

## Desired behavior

When the user passes `--full-auto`, the skill runs the pipeline without prompting at gates whose answer is unambiguous (e.g. recommended option per policy, convergence-driving review path on a green plan). For decisions that are ambiguous or carry non-trivial risk, the skill spawns a subagent to evaluate the choice and either auto-proceeds on a high-confidence recommendation or escalates back to the user with the subagent's reasoning. The flag never causes destructive operations to bypass human confirmation when the subagent reports low confidence.

## Success criteria

- Invoking `/hs-feature-loop <description> --full-auto` on a clear-cut feature completes TRIAGE → IMPLEMENT (and optionally REVIEW) without any user prompts.
- When a gate's answer is ambiguous, the skill invokes a subagent and surfaces its recommendation; on low confidence it falls back to the normal AskUserQuestion gate.
- The flag can be combined with the existing input forms (number, text, no-arg) and is documented in `argument-hint`.
- A user without the flag sees no behavior change.

## Non-goals

- Bypassing the merge gate when review-loop has not produced a clean APPROVE.
- Changing the underlying phase structure or the set of stages.
- Implementing auto-confidence scoring for `/hs-review-loop` itself.

## Notes

Related skills: `/hs-review-loop` already drives convergence non-interactively, so REVIEW phase already has a non-interactive path.
