---
issue: 99
title: Add decision records and a correction loop so agents can act within recorded guidance
type: enhancement
complexity: L
priority: P1
pr: 102
stage: REVIEW
---

# Add decision records and a correction loop so agents can act within recorded guidance

- **Exec plan:** [docs/exec-plans/active/099-add-decision-records-and-a-correction-loop-so-agen.md](../exec-plans/active/099-add-decision-records-and-a-correction-loop-so-agen.md) (or completed/)

## Problem

Agents working in a repo have nothing durable to judge a plan, idea or issue against. That forces an operator approval at every gate and makes the operator the bottleneck. When an agent does something wrong and the operator corrects it, the correction lives only in that session. The same mistake comes back in the next session, worktree or agent. Hivesmith has the brain (lessons) and `docs/design-docs/`, but no accepted-decision record that agents must consult and that can stand in for the operator.

## Desired behavior

- The repo keeps decision records (ADRs). Each has a status (proposed, accepted, superseded), a scope, and the decision with its rationale.
- Decisions made during pipeline runs are drafted as proposed records automatically: plan approvals, gate verdicts, and operator choices in a session.
- Plan review, triage and ideation check every plan, issue and idea against the accepted records, and flag anything that contradicts one.
- An accepted record can stand in for operator approval:
  - for plan approval;
  - for merging a low-risk PR whose merge-gate passed, but only where a record explicitly declares that category merge-eligible.
- When the operator corrects an agent, the correction becomes a proposed record, guidance entry or brain lesson that the operator accepts in one step. It also leaves a regression check that fails if the mistake recurs.
- Everything works in any hivesmith-installed repo, on any supported host.

## Success criteria

- A plan that contradicts an accepted record is flagged by plan review, and the flag cites the record.
- A triaged issue or idea that conflicts with an accepted record is flagged at triage, and the flag cites the record.
- After a pipeline run with plan approval and a gate verdict, proposed records for those decisions exist without the operator asking.
- An operator correction in a session produces, in that session, a proposed record or lesson, plus a regression check when the mistake is expressible as a code pattern. Otherwise the agent's report states that no mechanical check applies. Once the record is accepted, reintroducing the same mistake makes that check fail.
- When no accepted record covers an action, an agent escalates and never self-approves. This is shown by one run with records and one run without.
- No record is ever accepted without an explicit operator action.
- Records are named `YYYYMMDD-<slug>.md` with the slug as id. Records proposed on parallel branches collide only on an identical slug, which `hs-decision lint` reports as a duplicate.
- `hs-decision prune` lists stale proposals and superseded records by default, and deletes them only with `--apply`. It never deletes accepted records; it only clears links that point at the records it deletes.
- `/doc-garden` reports decision-record drift: lint problems, failing checks, and prune candidates.

## Non-goals

- Agents accepting or superseding records themselves.
- Retroactively mining git history into records.
- Replacing the hive brain. Records are per-repo decisions; brain entries are lessons.
- The coordinator, task board and periodic jobs, which belong to #98.

## Notes

Prerequisite for #98, which uses these records as its autonomy guardrail. Split out of the #98 brainstorm on 2026-11-21.

**Flag raised at brainstorm:** merge-by-record reverses `/feature-loop`'s current rule that merge is "never automatic, under any signal". The operator chose it explicitly. Guardrails: a record must explicitly declare the category merge-eligible, merge-gate must PASS, and every auto-merge is reported.

**Phasing (2026-11-24):** three phases.
- Phase 1 added records, propose, list, accept and supersede.
- Phase 2 adds slug ids, prune, the doc-garden pass and the correction loop.
- Phase 3 adds the approval stand-in (plan auto-approve, auto-merge behind an exit-0 script) and the escalation criterion ("When no accepted record covers an action…").

**Open questions:**
- What counts as "low-risk" for merge eligibility, and is that defined per record or globally?
- How do records relate to `docs/design-docs/` and the placeholder `core-beliefs.md`: does one replace the other, or do they coexist?
- ~~What form a regression check takes for a correction that isn't about code.~~ Settled in phase 2: none. A process or tone correction gets a lesson or an unchecked record, and the agent says so.

**Evidence:**
- Brain: `subagent-tool-grants-are-the-only-enforcement` (universal). Guardrails stated only in prose are not enforced.
- `scripts/harvest/correction_episodes.py` measures escaped defects after the fact. It is not a learning loop.
