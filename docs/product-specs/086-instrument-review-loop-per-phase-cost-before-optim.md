---
issue: 86
title: Instrument review-loop cost and harden behaviour-changing autofix fixes
type: enhancement
complexity: M
priority: P2
pr: 87
shipped: 2026-09-26
stage: DONE
---

# Instrument review-loop cost and harden behaviour-changing autofix fixes

- **Exec plan:** [docs/exec-plans/active/086-instrument-review-loop-per-phase-cost-before-optim.md](../exec-plans/completed/086-instrument-review-loop-per-phase-cost-before-optim.md) (or completed/)

## Problem

Every `/hs-review-loop` iteration does a full `/hs-review-pr`, then autofix, then waits for CI with `gh pr checks --watch`. After an autofix push, the gap to the next iteration is a median of 11 min and a p90 of 36 min. 29 of 42 PRs need 2–7 iterations. The operator suspects that full re-reviews and serial CI waits are wasteful, but the telemetry can't say where the time, tokens and operator attention actually go:
- `review_iteration` records no phase durations and no token usage.
- It doesn't record how long an escalation waits for a human, and escalations are 47 of 136 iterations, 36 of them "risky fix needs human decision".
- It doesn't record whether a re-review's findings come from the fix diff, sit near it, carry over, or are new in untouched code.

Without that, a narrowed re-review could remove the pass that catches fix-induced regressions, which a prior brain lesson (review-fixes-need-their-own-review-pass) found to be the most defect-dense code in a PR.

Those fix-induced defects have a visible cause in `/hs-autofix`: a fix that changes behaviour (a RISKY fix the operator approved) is applied by reading only the target file and making the minimal edit. Autofix doesn't check the callers or the rules nearby code depends on, it applies the reviewer's single-line "proposed approach" as given, and it adds no test proving the fixed behaviour. The only verification is the project's existing checks, which by construction never caught the bug being fixed.

## Desired behavior

Every `/hs-review-loop` iteration records, from measured values rather than estimates:
- wall-clock time spent in review, autofix, and waiting on CI;
- whole-worker token usage per iteration, when the harness exposes it (otherwise the field is left out). Review and autofix share one worker context, so no per-phase token split exists;
- for iterations after the first, each BLOCKING/IMPORTANT finding classified as *in fix diff*, *near fix diff* (touches code the previous fix's changed hunks call or depend on), *carried over* from the previous iteration, or *new in untouched code*;
- for an escalation, how long it waited from escalation until the loop resumed on that PR.

`scripts/metrics/report.py` shows a review-loop cost view built from this data. The operator can see which phase dominates, how often re-reviews catch fix-induced findings versus findings in untouched code, and how much time escalations spend waiting. That's enough to scope the follow-up optimization with evidence.

Every behaviour-changing fix `/hs-autofix` applies (a RISKY fix the operator approved, or the operator's own instruction) goes through three steps before it's committed:
1. **Check the blast radius.** List the callers of each symbol the fix edits and the rules they rely on (`graphify affected` when the project has a graph, a search for the symbol otherwise), and check the fix against each one.
2. **State the rule first.** Write down the rule the fixed code must hold, independently of the reviewer's proposed approach, and check the chosen fix against it rather than taking the proposal as given.
3. **Add a regression test.** Add a test that fails without the fix and passes with it, when the project defines a test command. When it doesn't, say so explicitly in the fix summary.

Each of these steps shows up in autofix's per-fix summary, so the operator (and `/hs-review-loop`'s next iteration) can see what was checked.

## Success criteria

- A `/hs-review-loop` run on a real PR emits events that `hs-metric` accepts, with measured `review`, `autofix` and `ci_wait` durations per iteration. No duration field is ever filled with an estimate.
- Token fields appear only when the harness supplies real counts. On a harness that doesn't, the events still validate and leave those fields out.
- Every BLOCKING/IMPORTANT finding in iteration ≥2 carries exactly one of the four classifications, and the per-iteration counts add up to that iteration's `findings_count`.
- Re-running `/hs-review-loop` on a PR whose last iteration escalated records how long the escalation waited, and the report shows it.
- `scripts/metrics/report.py` prints a review-loop section with per-phase duration p50/p90, the split of finding classifications, and escalation wait p50/p90. It stays correct when older events lack the new fields.
- `scripts/metrics/emit-test.sh` covers the new fields, including rejecting an invalid classification value.
- Iteration decisions don't change: for the same envelope, the verdict, stop, escalation and ledger outcomes match those before the change.
- For every behaviour-changing fix, `/hs-autofix`'s summary lists the callers and rules it checked, the rule it stated up front, and either the regression test it added or the explicit reason none was added (no test command defined).
- A behaviour-changing fix applied in a project that defines a test command lands with a test that fails if the fix is reverted.
- SAFE fixes (mechanical: lint, imports, typos) follow the same path as before, with no new steps.
- `autofix_applied` events record, per run, how many behaviour-changing fixes got a regression test and how many didn't, so #86's classification data can be compared against fixes with and without these steps.

## Non-goals

- Any optimization of the loop: targeted re-review, CI overlap, skipping CI waits, cheaper reviews. That's the follow-up spec.
- Any change to iteration logic, stop rules, escalation criteria or the CI wait.
- A separate reviewer agent that checks each fix before it's pushed (tracked in Notes for the follow-up).
- Changing how autofix classifies findings as SAFE or RISKY.
- Backfilling durations or classifications for the existing events.
- Estimating tokens or durations when the harness doesn't expose them.

## Notes

Carry-forward from `/hs-brainstorm` for the follow-up optimization spec (#2):

- The operator weights wall-clock, tokens and operator attention **equally**, so spec #2 has to show gains without regressing any of them.
- **Targeted re-review scope** is set: fix diff plus neighbours (the invariants and callers it touches), never the fix diff alone.
- **CI overlap** is set: a CI result counts as a finding for the next iteration, and the loop waits on CI only before declaring convergence.
- There's no data threshold for starting spec #2; the operator decides when.
- Still open: escalations dominate the stalls, so spec #2 may find that the biggest lever is autofix's risky-fix classification rather than review scope or CI.

Fix-quality follow-up (tracked, not in scope here):

- **Reviewing a fix before it's pushed.** A second agent would review only the fix diff and the code around it before the push. It's the targeted re-review from spec #2 moved earlier, so decide it there.
- **Measurement caveat.** This spec both measures fix-induced findings and changes how fixes are made, so there will be no clean "before" baseline for them. The 136 existing `review_iteration` events (finding counts growing after a fix: 1→2, 5→8, 9→12) are the only prior signal. The per-run regression-test counts on `autofix_applied` let the new data split fixes into with and without the new steps.
- **Evidence so far.** One detailed case (PR #341, brain entry `review-fixes-need-their-own-review-pass`) plus those growing counts. Revisit the three new steps if the classification data shows few findings inside or next to a fix.
