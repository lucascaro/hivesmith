---
title: Convert feature-qa into a pre-merge merge-gate
type: enhancement
complexity: M
priority: P2
stage: IMPLEMENT
# pr: <number>         # uncomment when PR opens
# shipped: 2026-MM-DD  # uncomment on DONE
---

# Convert feature-qa into a pre-merge merge-gate

- **Exec plan:** [docs/exec-plans/active/036-convert-feature-qa-into-a-pre-merge-merge-gate.md](../exec-plans/active/036-convert-feature-qa-into-a-pre-merge-merge-gate.md)

## Problem

Every feature ships in two PRs. The second carries ~15 lines of markdown bookkeeping
(move the exec plan to `completed/`, flip `stage:`/`Status:`, add `pr:`/`shipped:`,
append the verdict) yet costs a full CI matrix run, a `no-changeset` label, and hours
of lag. The second PR is not something the validation needs — it is a write-ordering
artifact: `feature-loop` Phase 6 step 47 writes `stage: QA` *after* `gh pr merge`, and
`feature-qa` refuses to run unless the PR is already `MERGED`, so the bookkeeping lands
on `main` with nowhere to go. Two of the five closeouts to date bypassed the PR with a
direct push to `main` instead.

## Desired behavior

Validation runs on the PR branch after review converges and before the merge, so a
failure is fixed inside the same PR rather than filed as a follow-up issue against
already-shipped code. All bookkeeping rides along in the feature PR. One PR per feature.
The step is named `merge-gate` because pre-merge it is a merge gate, not QA, and the
pipeline stage is named `GATE` to match.

## Success criteria

- `skills/merge-gate/SKILL.md` exists with frontmatter `name: merge-gate`; `skills/feature-qa/` no longer exists.
- The gate runs exactly three dimensions — acceptance, non-goals, doc accuracy. `build/lint/test` and `regression` appear nowhere in its dimension list.
- The gate's cold-start guard accepts a PR in state `OPEN` whose plan ledger's latest entry is `verdict: APPROVE`, and refuses when the spec's `stage:` is not `GATE`.
- On PASS the gate writes the verdict, sets `Status: completed`, moves the plan to `docs/exec-plans/completed/`, repoints the spec's `Exec plan:` link, sets `pr:` and `shipped:` (today's date), sets `stage: DONE` as the last write, commits, and pushes to the feature branch.
- On FAIL the gate leaves `stage: GATE`, does not merge, and files no follow-up issue.
- `scripts/regen-generated.py` and `templates/scripts/regen-generated.py` list `GATE` (not `QA`) in both `STAGES` and `ACTIVE_STAGES`; `scripts/regen-generated.sh` exits 0 against the repo, and a spec set to `stage: QA` fails with `invalid stage 'QA'`.
- `feature-loop` merges only after the gate returns PASS: Phase 6 sets `stage: GATE` and pushes without merging, Phase 7 runs the gate, and Gate 6 runs `gh pr merge` afterwards.
- `grep -rn "feature-qa\|stage: QA\|/hs-feature-qa" skills/ templates/ scripts/ agents/ AGENTS.md README.md` returns nothing.
- Driving one feature end to end through `/hs-feature-loop` produces exactly one PR, whose diff contains the `completed/` plan rename plus `stage: DONE` and `shipped:` but does **not** contain `docs/product-specs/index.md`, and which passes `block-generated-edits` and `verify-generated`.

## Non-goals

- Changing `scripts/regen-generated.py`'s rule that `stage=DONE` requires `shipped`, or its completed-table sort key.
- Making the regenerator git-aware to derive `shipped` from commit dates.
- Adding a `QA` → `GATE` compatibility alias. No spec is at `stage: QA` today, and the regenerator's error names the fix.
- Rewriting the four existing `## QA verdict` sections in `docs/exec-plans/completed/`, or the QA references inside `docs/exec-plans/active/016-*.md` and `020-*.md`. Those are historical record.
- Changing what `/review-pr` or `/review-loop` check.
- Altering `ci.yml`, `changesets.yml`, or the generated-file enforcement model.

## Notes

Evidence behind the decision: closeout PRs #15 (+18/−5), #26 (+3/−3), #33 (+11/−5) plus
direct pushes `e7dda35` and `3b2891c`. All five recorded verdicts are PASS; plan `024`
shipped DONE with an empty `## QA verdict` section. Issue #22 ("README missing
`--full-auto` flag") is the one real catch on record and came from the doc-accuracy
dimension. The 029 verdict demonstrates the acceptance dimension working well, with
per-criterion evidence (`SC1..SC7`).
