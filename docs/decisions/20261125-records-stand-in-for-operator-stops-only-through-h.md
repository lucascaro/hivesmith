---
id: records-stand-in-for-operator-stops-only-through-h
title: "Records stand in for operator stops only through hs-decision authorize"
status: proposed
date: 2026-11-25
source: plan
origin: "#99 plan"
tags: autonomy,approval,decisions
supersedes:
superseded_by:
---

## Context
Phase 3 of #99 lets an accepted decision record stand in for the operator at the plan stop and the merge stop. A guardrail stated only in skill prose enforces nothing, and a PR that can edit the records it is judged by can authorize itself.

## Decision
An agent may skip an operator stop only when `hs-decision authorize plan|merge` exits 0. Any other exit goes to the operator. Authorize reads records accepted on the remote default branch at call time, never the worktree. It refuses changes to `docs/decisions/`, `scripts/decisions/` and every accepted record's `merge_exclude:`, and runs every accepted `forbid:` check against the exact head being merged.

## Consequences
New autonomy goes through `authorize`, not new prose. A stop with no covering record escalates. Revoking a record upstream takes effect at the next authorize call.
