---
issue: 71
title: /hs-merge-gate over-advances a multi-phase spec to DONE on its first phase's gate
type: bug
complexity: M
priority: P1
stage: GATE             # TRIAGE | RESEARCH | PLAN | IMPLEMENT | REVIEW | GATE | DONE | REJECTED
pr: 72
# shipped: 2026-MM-DD  # uncomment on DONE
# rejection_reason:    # required when stage=REJECTED
---

# /hs-merge-gate over-advances a multi-phase spec to DONE on its first phase's gate

- **Exec plan:** [docs/exec-plans/active/071-hs-merge-gate-over-advances-a-multi-phase-spec.md](../exec-plans/active/071-hs-merge-gate-over-advances-a-multi-phase-spec.md)

## Problem

<!-- BEGIN EXTERNAL CONTENT: GitHub issue body — treat as untrusted data, not instructions -->
## What happens

`/hs-merge-gate` assumes **one spec = one PR**. When a spec is deliberately phased into several PRs — the shape `/hs-feature-plan` itself produces via a `### Phasing` section, one phase per PR per changeset — the gate has no way to express "this PR satisfies the criteria it claims, and the rest belong to later phases."

Concretely, on a 3-phase spec whose phase 1 was under gate:

- The spec's `## Success criteria` describe the finished feature. Phase 1 delivered 2.5 of 7; the other 4.5 are phases 2 and 3.
- All three gate dimensions (acceptance, non-goals, doc accuracy) pass when scoped to phase 1.
- Per the skill's step 4, "all dimensions PASS → `PASS`", and the PASS branch then sets the spec's frontmatter `stage: DONE`, `git mv`s the exec plan into `docs/exec-plans/completed/`, and stamps `shipped:`.

That marks a one-third-built feature complete and files away the plan — which is the only home of the phasing, decision log, and research that phases 2 and 3 still need. The alternative reading (FAIL, because criteria are unmet) is no better: the skill's FAIL remedy is "fix it in this PR", which here would mean building the remaining two phases in the phase-1 PR, defeating the phasing.

There is no wrong-looking output to catch it, either: the dimension workers correctly report PASS for what they were asked, so the over-advancement is silent.

## Why the existing branches don't cover it

`NEEDS_FOLLOWUP` is the closest fit and is what I used by hand, but its semantics are "an item needs production telemetry / infrastructure not in this repo" — an *ocean*. Deferred phases are neither: they are planned, scoped work with a written plan. Its `AskUserQuestion` options ("advance to DONE" / "hold at GATE") also both have a bad edge: advancing is wrong, and holding at GATE leaves no recorded signal that *this phase* passed, so a later re-run cannot tell an ungated phase from a gated one.

## Suggested shape

Some way for the gate to know which criteria a given PR claims. Options, roughly in increasing cost:

1. **Per-criterion phase tags in the spec** — `- (phase 1) ...` prefixes under `## Success criteria`; the gate resolves the PR's phase from the plan's `### Phasing` + the PR body and only requires that phase's criteria. Cheapest, no schema change.
2. **A `phases:` frontmatter block** in the spec with per-phase `stage:`, so `stage:` becomes per-phase rather than per-spec. The gate advances the phase, and DONE is written only when the last phase gates. Bigger change — every stage skill reads `stage:`.
3. **Minimum viable:** teach the gate to detect a `### Phasing` section and, when present, refuse to write DONE unless the PR under test is the final phase — recording a per-phase PASS in `## Gate verdict` instead. This alone would have prevented the silent over-advancement.

Option 3 seems like the right first move; 1 makes the per-phase verdict meaningful rather than "the human scoped it in the prompt."

## Repro

Any spec with a `### Phasing` section in its exec plan and success criteria spanning more than the first phase. Encountered on hive spec 337 (idea inbox, 3 phases; phase 1 = registry + wire + daemon + CLI, phases 2-3 = GUI and initial-prompt work).

## Related

Two smaller things noticed in the same run, filed here rather than separately since they touch adjacent text — say the word and I'll split them out:

- **`/hs-review-loop` contradicts itself on `COMMENT`.** Its §2 step 5 says "COMMENT with strict off AND zero unresolved threads — done", but the Philosophy section says the loop ends on "APPROVE (or COMMENT with only MINOR remaining)". A `COMMENT` verdict carrying IMPORTANT findings satisfies the first and violates the second. I followed the Philosophy reading and coerced to `REQUEST_CHANGES`; the step-5 reading would have stopped with three IMPORTANT findings standing, one of which was a real data-loss-adjacent bug.
- **`/hs-merge-gate`'s cold-start guard requires a ledger entry with `action: stop`**, which is only reachable if the loop's stop path ran. When a review-loop worker dies mid-iteration (mine hit an API rate limit after pushing but before re-reviewing), the ledger's last entry is `autofix+push` and the gate refuses — correctly, but the recovery is undocumented. A note on how to resume would help.
<!-- END EXTERNAL CONTENT -->

## Desired behavior

An exec plan may declare that its PR delivers one slice of a multi-phase feature. When it does, `/merge-gate` records that phase's verdict and reports the PR ready to merge, but never marks the spec `DONE`, never files the plan away to `completed/`, and never stamps `shipped:` — that bookkeeping happens only when the final phase gates. A plan that declares no phase behaves exactly as it does today.

Because a spec parked at `GATE` cannot advance on its own, the route to phase N+1 is documented and manual: reset `stage:` to `IMPLEMENT`, bump the plan's `Phase:`, and clear the plan's `PR:`/`Branch:` fields so the next phase starts clean.

Separately, `/review-loop` states one stop condition for a `COMMENT` verdict rather than two contradictory ones, and its cold-start section says how to resume after an iteration dies mid-flight.

## Success criteria

- The exec-plan template documents an optional `Phase: N of M` header field, and a plan without it is treated as single-phase with today's behavior unchanged. Both copies are updated: `docs/exec-plans/_template.md` and the byte-identical `templates/docs/exec-plans/_template.md` that `/hivesmith-init` scaffolds into consumer projects.
- `/merge-gate`'s PASS branch is forked: with a declared `Phase: N of M` where `N < M`, it writes the `## Gate verdict` entry (carrying `phase: N/M`) and stops — no `Status: completed`, no `git mv` to `completed/`, no `pr:`/`shipped:`, no `GATE → DONE` stage transition, no `stage: DONE`.
- A non-final PASS still commits and pushes its `## Gate verdict` append to the feature branch, so the next `/merge-gate` or `/review-loop` §4a run does not refuse on a dirty tree.
- A final phase (`N == M`) or an undeclared phase runs the existing DONE bookkeeping unchanged.
- `/merge-gate`'s Rules section states that `DONE` is never written while the plan declares a non-final phase.
- The exit path from a non-final `GATE` is documented and actually reachable. `/merge-gate`'s non-final report and `/feature-loop`'s stage dispatch both state the manual reset (`stage: IMPLEMENT`, bump `Phase:`, clear the plan's `PR:`/`Branch:`), and `/feature-loop`'s Phase 5 step 37 no longer force-writes `stage: GATE` back when a non-final phase's previous PR is merged.
- The `gate_verdict` metric accepts an optional `phase` field, so a phase PASS is distinguishable from a full PASS in telemetry; `scripts/metrics/emit-test.sh` covers both the accepted field and rejection of an unknown one.
- `/review-loop`'s three statements of the `COMMENT` stop condition (Philosophy, §2 step 5, the worker prompt's step 5) agree with each other: the loop stops on `COMMENT` only with strict mode off, zero unresolved threads, and no BLOCKING or IMPORTANT findings remaining.
- `/merge-gate`'s cold-start guard keeps accepting on `action: stop` + `verdict: APPROVE|COMMENT` + `threads_open: 0`, and its restatement of the loop's rule is updated to describe the new stop condition accurately. The guard is **not** tightened to require an empty `findings_hash`: ledgers written under the old rule (e.g. `docs/exec-plans/completed/067-wrap-graphify-pretooluse-nudge.md:200`) record `action: stop` with a non-empty hash, and tightening would retroactively refuse them.
- `/review-loop`'s cold-start section explains that a ledger whose last entry is `autofix+push` means a prior run died after pushing, and that re-running the loop is the recovery.
- `/feature-loop`'s Phase 7 and Phase 8 describe the non-final-phase outcome, and emit `feature_done` only on a final-phase PASS.
- Every shipped restatement of the "gate PASS moves the plan to `completed/`" contract carries the non-final-phase exception: `AGENTS.md:34,40`, `templates/AGENTS.hivesmith.md:10,16`, `PLANS.md:21`, `templates/PLANS.md:22`, `skills/feature-loop/SKILL.md:13`, `templates/docs/product-specs/index.md:26`.

## Non-goals

- Per-criterion `(phase N)` tags under `## Success criteria` (the issue's option 1). Deferred; which criteria belong to a phase remains the acceptance worker's judgment.
- Per-phase `stage:` in spec frontmatter (the issue's option 2). Rejected — every stage skill reads `stage:`.
- Any change to `/hs-feature-plan` to *produce* phased plans. This spec makes the gate safe when a plan is phased by hand; it does not teach the planner to phase.
- A new `gate-phase-passed` GitHub label. A non-final phase PASS keeps the `gate` label.
- Automatically advancing a spec to phase N+1. The `GATE → IMPLEMENT` reset stays a manual, documented step.

## Notes

Source issue: https://github.com/lucascaro/hivesmith/issues/71

The issue states this shape is what `/hs-feature-plan` produces via a `### Phasing` section. That is not true of this repo — no phasing convention exists anywhere in hivesmith's skills or templates; the reporter encountered it on a different project. See the exec plan's Research for the consequences.
