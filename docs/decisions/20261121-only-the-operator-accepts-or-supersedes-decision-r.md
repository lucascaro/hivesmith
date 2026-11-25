---
id: only-the-operator-accepts-or-supersedes-decision-r
title: "Only the operator accepts or supersedes decision records"
status: proposed
date: 2026-11-23
source: gate
origin: "#99 gate"
tags: decisions,approval,autonomy
supersedes:
superseded_by:
---

## Context

#99 adds decision records that agents check plans, issues and ideas against, and that #99 Phase 2 lets stand in for operator approval. If an agent could accept a record, it could grant itself the authority the record later confers.

## Decision

Agents may list and propose records. Only the operator accepts or supersedes one, via `hs-decision accept` or `hs-decision supersede`, and only on an explicit request in the current session. `supersede` also accepts the replacement, so an accepted rule never disappears with nothing in its place.

## Consequences

Record review stays a human step, and proposals queue until the operator acts. A plan that has a skill, hook or scheduled job run `accept` or `supersede` without an explicit operator request contradicts this record, as does one that infers acceptance from merge, age or a reviewer's approval.
