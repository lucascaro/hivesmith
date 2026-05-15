---
issue: 24
title: Plan-first starting point for hs-feature-loop
type: enhancement
complexity: S
priority: P2
stage: DONE
pr: 25
shipped: 2026-05-12
---

# Plan-first starting point for hs-feature-loop

- **Exec plan:** [docs/exec-plans/completed/024-plan-first-starting-point-for-feature-loop.md](../exec-plans/completed/024-plan-first-starting-point-for-feature-loop.md)

## Problem

`/hs-feature-loop` always enters at TRIAGE for new text input and walks every gate (triage → research → plan → implement). When the user already has enough context to design the implementation directly, the early gates are friction. There is no way to start by iterating on a plan and then have the skill backfill the upstream artifacts.

## Desired behavior

Invoking `/hs-feature-loop plan <description>` (or `plan` alone, then prompting for the description) enters Claude Code's plan mode immediately. The user iterates on the implementation plan until satisfied and approves via ExitPlanMode. On approval, the skill scaffolds all upstream artifacts — GitHub issue (per `.hivesmith/config.toml` policy), spec file with TRIAGE fields filled, exec plan with Research and Approach sections populated from the accepted plan, index row — and advances Stage to IMPLEMENT. The TRIAGE / RESEARCH / PLAN gates are treated as auto-satisfied by the user's plan-mode approval; the loop then continues from Phase 5 (Implement).

## Success criteria

- `/hs-feature-loop plan <description>` enters plan mode on the first turn and does not write any files until the user approves the plan.
- After approval, the spec, exec plan, index row, and (per policy) GitHub issue all exist and reflect the accepted plan.
- The exec plan's Stage is `IMPLEMENT` and the index row shows `IMPLEMENT` immediately after scaffolding.
- Resuming with `/hs-feature-loop 24` after a plan-first run lands directly in Phase 5 (Implement).

## Non-goals

- Changing the default (non-`plan`) input behavior.
- Auto-implementing the plan without the existing Phase 5 push/PR gate.
- Adding plan-first entry to the sub-skills (`/hs-feature-triage`, `/hs-feature-research`, `/hs-feature-plan`) — this is loop-only.

## Notes

Related skills: `hs-feature-plan`, `hs-feature-research`, `hs-feature-triage`.
