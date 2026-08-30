# Convert feature-qa into a pre-merge merge-gate

- **Spec:** [docs/product-specs/036-convert-feature-qa-into-a-pre-merge-merge-gate.md](../../product-specs/036-convert-feature-qa-into-a-pre-merge-merge-gate.md)
- **Issue:** —
- **Status:** completed
- **PR:** #57
- **Branch:** `feature/036-convert-feature-qa-into-a-pre-merge-merge-gate`

<!--
Stage is **not** carried here. The spec's YAML frontmatter `stage:` is the
sole source of truth. Skills read and write stage from the spec — never from
this file or from the generated `docs/product-specs/index.md`.
-->


## Summary

Move the post-merge `feature-qa` validation to run on the PR branch before merge, and
rename it `merge-gate` (stage `QA` → `GATE`). This collapses the two-PR-per-feature
pattern into one and makes a failing check actionable inside the PR instead of a
follow-up issue against shipped code. Authored via plan-first mode.

## Research

Authored via plan-first mode; the findings below come from that session.

- `skills/feature-qa/SKILL.md:25` — cold-start guard refuses unless `gh pr view --json state` is `MERGED`. This, plus `skills/feature-loop/SKILL.md` Phase 6 step 47 writing `stage: QA` *after* `gh pr merge`, is the sole reason a second PR exists. Nothing in the validation logic needs the merge.
- `skills/feature-qa/SKILL.md:41-45` — five dimensions. `build/lint/test` duplicates `feature-loop` step 40 (pre-commit) and `.github/workflows/ci.yml` (6 jobs on every PR). `regression` substantially overlaps `/review-pr`. Unique value is `acceptance` (per-criterion spec traceability) and `non-goals` (negative scope check); `doc accuracy` produced the one real catch on record (issue #22).
- `scripts/regen-generated.py:39-40` — `STAGES` / `ACTIVE_STAGES` enums carry `QA`. `:247` rejects unknown stages, `:251` requires `shipped` when `stage: DONE`, `:282` sorts the completed table by `shipped`. `:338-339` emits the lifecycle blurb into the generated index. `templates/scripts/regen-generated.py` is a parallel copy.
- `scripts/regen-generated.py:241-243` — `issue` is optional in spec frontmatter; only `title` and `stage` are required. Spec 036 omits it (local-only feature).
- `.github/workflows/changesets.yml` — `block-generated-edits` hard-fails any PR touching `CHANGELOG.md`, `docs/product-specs/index.md`, or `docs/exec-plans/tech-debt-tracker.md`; `verify-generated` requires ≥1 new `.changesets/*.md`; `regenerate-generated` rebuilds and direct-pushes the aggregates on push to `main`. The exec plan under `completed/` is not generated, so it may ride in the PR.
- `skills/review-loop/SKILL.md:175` (`## 4a. On merge`) — a second source of orphan post-merge commits: it sets `stage: QA` after detecting a merge.
- `skills/feature-implement/SKILL.md:18,60,62` — already-merged short-circuit hands off to `/feature-qa`.
- `agents/hs-validator.md` — the per-dimension worker (`tools: Read, Grep, Glob, Bash`, `model: sonnet`).
- Current stage distribution: 016/033/035 = REVIEW, 020/032 = IMPLEMENT, 011/024/029/034 = DONE. **No spec is at `stage: QA`**, so the rename needs zero data migration.
- `~/.claude/skills/hs-*` are symlinks into `/Users/lucascaro/checkout/hivesmith/.rendered/` (the main clone, not this worktree), populated by `install.sh`. Use `scripts/dev-link-local.sh` to dogfood from the worktree.

Evidence for the decision: closeout PRs #15 (+18/−5, ~4h lag), #26 (+3/−3, ~8h), #33 (+11/−5, ~11min), plus direct-to-main pushes `e7dda35` and `3b2891c`. Five verdicts, all PASS; plan `024` shipped DONE with an empty `## QA verdict` section.

## Approach

Run the validation on the PR branch between review convergence and merge, rather than on
`main` after merge. Chosen over the obvious alternative — keeping the post-merge position
and merely batching the bookkeeping into a later commit — because the position, not the
batching, is what costs: post-merge a failure can only become a follow-up issue against
already-shipped code, whereas pre-merge it is a fix in the open PR. Collapsing to one PR
is a side effect of fixing the ordering, not the goal.

Rejected alternative for `shipped:`: making the regenerator derive it from git commit
dates. That buys an exact merge date at the cost of making `regen-generated.py` git-aware
and shelling out per DONE spec. The gate instead writes today's date; the merge follows
within minutes, so drift is effectively zero and never exceeds a day.

New pipeline shape:

```
Phase 6  REVIEW  /review-loop converges (APPROVE)
                 -> set spec stage: GATE, commit + push to the SAME branch
Phase 7  GATE    /merge-gate <pr>
                 -> acceptance + non-goals + doc accuracy on the branch
                 PASS: append verdict, Status: completed, git mv plan to completed/,
                       repoint spec's `Exec plan:` link, set pr:/shipped:,
                       last write stage: DONE -> commit + push to the SAME branch
                 FAIL: fix in this PR (no follow-up issues against unshipped code)
Gate 6           confirm merge -> gh pr merge --squash --delete-branch
Phase 8  DONE    summary
```

### Files to change

1. `skills/feature-qa/` → `skills/merge-gate/` (`git mv`), then rewrite `SKILL.md`:
   - Frontmatter `name: merge-gate`; description → validates a PR against its spec before merge.
   - Cold-start guard: accept `stage: GATE`; require PR state `OPEN` **and** the plan's `## PR convergence ledger` latest entry `verdict: APPROVE`. Keep a degraded post-merge path for recovery (PR already `MERGED`), with the git range swapped to the merge commit. Refuse on `CLOSED` and not merged. Ensure the branch is checked out and current with the remote.
   - Dimensions → 3. Remove `build/lint/test` and `regression` from the step-2 table and the verdict-block example; state that build/lint/test is owned by `feature-loop` step 40 and `ci.yml`.
   - Git ranges in surviving dimensions: `<merge-sha>~1..<merge-sha>` → `main...HEAD`.
   - PASS: keep the write ordering (non-stage writes first, `stage:` last — that is what makes a crashed run resumable), but source `shipped:` from today's date, not `gh pr view --json mergedAt`. Commit `chore: gate pass for #<n>`; push to the feature branch.
   - FAIL: report failing criteria, stop at `GATE`, file no follow-up issue. Issue-filing survives only on the degraded post-merge path.
   - Labels `qa-*` → `gate-*`; remove-label `qa` → `gate`. Keep the "only when a GitHub issue exists" gating.
   - Keep the anti-injection rule and the "refuse if the spec has no Success criteria" rule verbatim.
2. `agents/hs-validator.md` — dimension list → the 3 survivors; QA wording → gate. Keep `tools`/`disallowedTools`/`model` and the "Run it, don't read it" + command-vetting rules.
3. `skills/feature-loop/SKILL.md` — `:13` lifecycle blurb; Phase 6 step 47 stops merging and instead sets `stage: GATE` + pushes; Gate 6 moves after the gate; Phase 7 becomes the gate invocation; full-auto Gate 6 requires ledger `APPROVE`+`stop` **and** gate `PASS`; Phase 0 stage map and Phase 5 step 37 `QA` → `GATE`; Phase 8 summary wording.
4. `skills/review-loop/SKILL.md:175` — `## 4a` fires on `APPROVE` (pre-merge) setting `REVIEW` → `GATE` and pointing at `/merge-gate <pr>`, instead of firing on merge detection. Keep "never merge from inside the loop" and "do not move the plan file".
5. `skills/feature-implement/SKILL.md:18,60,62` — already-merged short-circuit advances to `GATE` and points at `/merge-gate`.
6. `scripts/regen-generated.py` + `templates/scripts/regen-generated.py` — `:39` `STAGES` and `:40` `ACTIVE_STAGES` `"QA"` → `"GATE"`; `:338-339` lifecycle blurb rewritten. Leave `:251` and `:282` untouched.
7. Prose-only renames (same pattern each: swap skill name and stage token, keep logic) — `skills/feature-next/SKILL.md:33`, `skills/feature-triage/SKILL.md:21`, `skills/feature-plan/SKILL.md:80,96`, `skills/feature-plan-handoff/SKILL.md:40`, `skills/feedback-loop/SKILL.md:129`, `skills/feature-populate-backlog/SKILL.md:11`, `AGENTS.md:12,14,20,33`, `templates/AGENTS.hivesmith.md:6,10,16,28`, `README.md:101`, `docs/exec-plans/_template.md:73` and `templates/docs/exec-plans/_template.md:73` (`## QA verdict` → `## Gate verdict`), `templates/features/templates/FEATURE.md:50`.

**Do not touch** `docs/exec-plans/active/016-*.md:34,102`, `020-*.md:33`, or the four existing `## QA verdict` sections in `docs/exec-plans/completed/` — historical record.

### New files

- `skills/merge-gate/SKILL.md` — via `git mv` from `skills/feature-qa/SKILL.md`, then rewritten.
- `.changesets/036-merge-gate.md` — `verify-generated` requires one. Do not edit `CHANGELOG.md` (generated).

### Tests

This repo's suite is shell-based; there is no unit-test harness for skill markdown. Coverage is by regenerator assertions plus the existing CI jobs:

- `scripts/regen-generated.sh` against the repo — exits 0 with the new `GATE` enum.
- Negative assertion: a scratch spec at `stage: QA` makes `regen-generated.sh` fail with `invalid stage 'QA'`.
- `scripts/brain/test/run-all.sh` — unchanged, expect 13/13.
- `ci.yml` "Subagents link, stay idempotent" job — must still pass with the edited `agents/hs-validator.md`.
- Grep assertion for stale `feature-qa` / `stage: QA` references outside the historical record.

## Verification

Run from the worktree root.

```bash
# 1. Regenerator accepts the new enum; only the blurb changes, no row churn.
scripts/regen-generated.sh && git diff --stat docs/product-specs/index.md

# 2. Old stage is rejected (revert the scratch edit afterwards).
sed -i '' 's/^stage: IMPLEMENT/stage: QA/' docs/product-specs/032-*.md
scripts/regen-generated.sh; echo "expect non-zero: $?"
git checkout -- docs/product-specs/032-*.md

# 3. AGENTS.md gates.
shellcheck $(git ls-files '*.sh')
scripts/brain/test/run-all.sh          # expect 13/13

# 4. Install renders the renamed skill and drops the old one.
./install.sh --prefix hs- && ls ~/.claude/skills | grep -E 'merge-gate|feature-qa'
./install.sh --prefix ""

# 5. No stale references outside the historical record.
grep -rn "feature-qa\|stage: QA\|/hs-feature-qa" skills/ templates/ scripts/ agents/ AGENTS.md README.md

# 6. Restore the generated index so it never enters the PR.
git checkout -- docs/product-specs/index.md CHANGELOG.md
```

End-to-end dogfood: `scripts/dev-link-local.sh`, then drive one small feature through
`/hs-feature-loop` from IMPLEMENT. Assert exactly **one** PR is created; its diff contains
the `completed/` plan rename plus spec `stage: DONE` and `shipped:`, and does **not**
contain `docs/product-specs/index.md`; `block-generated-edits` and `verify-generated` both
pass; after merge `regenerate-generated` moves the index row to the Completed table on its
own. Then break one spec success criterion and confirm the gate returns FAIL, leaves
`stage: GATE`, does not merge, and files no follow-up issue.

## Decision log

- **2026-08-30** — Renamed the step `merge-gate` and the stage `GATE`. Why: pre-merge it validates that a PR is ready to land, which is a merge gate, not QA; the old name described a position in the pipeline that no longer exists.
- **2026-08-30** — Dropped the `build/lint/test` and `regression` dimensions. Why: the first is run twice already (`feature-loop` step 40 and `ci.yml`), the second substantially overlaps `/review-pr`. Kept acceptance and non-goals (unique) and doc accuracy (produced the only real catch on record, issue #22).
- **2026-08-30** — `shipped:` = the date the gate runs, rather than teaching the regenerator to derive it from git. Why: the merge follows the gate within minutes, so drift is ~0 and never exceeds a day; the alternative makes `regen-generated.py` git-aware for no practical gain.
- **2026-08-30** — No `QA` → `GATE` compatibility alias. Why: zero specs are at `stage: QA`, and `regen-generated.py:247` already emits an error that names the fix.
- **2026-08-30** — Renamed the GitHub labels in place (`qa` → `gate`, `qa-passed` → `gate-passed`, `qa-followup` → `gate-followup`) and created the missing `gate-failed`. Why: renaming keeps the label attached to issues that already carry it; `qa-failed` never existed, so the old skill's FAIL label step was already broken and this closes that gap. Labels are not code in this repo, so this is a live-repo op recorded here rather than a diff.
- **2026-08-30** — The gate accepts a converged `COMMENT`, not only `APPROVE`. Why: `/review-loop` §2 step 5 stops on `APPROVE` with zero threads *or* `COMMENT` with strict off and zero threads. A gate demanding a stricter signal than the loop can emit would deadlock the normal path. `action: stop` plus `threads_open: 0` is the real convergence signal; the verdict alone is not.
- **2026-08-30** — Kept the `## QA verdict` legacy fallback rather than migrating the five in-flight plans' headings. Why: those sections are append-only historical record, and rewriting headings on active plans would churn files owned by other in-flight PRs. The cost is that every *reader* of the verdict must mirror the fallback — which is exactly the gap review iteration 2 caught in Gate 6.
- **2026-08-30** — Dropped the `done` GitHub label step invented for Gate 6. Why: no such label existed, `/merge-gate` step 6 already moves `gate` → `gate-passed`, so the step was both broken and redundant.

## Progress

- **2026-08-30** — Plan-first scaffold; stage = IMPLEMENT (set in spec frontmatter).
- **2026-08-30** — Implemented; PR #57 opened; stage = REVIEW. All AGENTS.md gates green locally and all 12 CI checks green.
- **2026-08-30** — Post-loop: aligned the gate's convergence guard with `/review-loop`'s actual stopping condition. The guard demanded `verdict: APPROVE`, but review-loop converges on `COMMENT` too (strict off, zero threads) — as this very PR's own loop did, five times. The gate would have refused the normal path every time. Both it and Gate 6 now accept `action: stop` with `APPROVE` or `COMMENT` and `threads_open: 0`, and still refuse on `REQUEST_CHANGES`, `escalated:*`, mid-flight `autofix+push`, or open threads.
- **2026-08-30** — review-loop iter 5 (final, budget 5/5): COMMENT, 0 threads, CI green, `blocks_merge: false`. Fixed the last IMPORTANT — `/merge-gate` was itself the one remaining reader that hardcoded `active/`, so a re-run after a crash between the plan move and the `stage: DONE` write could not find its own plan; the glob now covers `{active,completed}` and the move is a no-op when already done. Also corrected the now-stale cross-reference claiming step 46 performs the write. Findings per iteration: 5, 3, 3, 8, 1 — converged.
- **2026-08-30** — review-loop iter 4: COMMENT, 0 threads, CI green. Fixed 8 findings. Two clusters, both self-inflicted by iter 3: the summary prose still defined `DONE` as "and the PR merged" in five places (including both `regen-generated.py` copies, which bake it into every regenerated index), and step 46 had become a duplicate of the transition §4a now owns — its empty `git commit` would exit non-zero and halt the loop. Also fixed `templates/PLANS.md`, which is scaffolded into every consumer repo and still described the old ordering.
- **2026-08-30** — review-loop iter 3: COMMENT, 0 threads. Fixed 3 findings, all consequences of `DONE` now preceding the merge: `/review-loop`'s cold-start unconditionally demoted any stage to `REVIEW` (which would destroy a gate's terminal `DONE` write while `pr:`/`shipped:`/the `completed/` move stayed behind) and globbed only `active/` for the plan; `/feature-loop` Phase 0 treated `DONE` as terminal, stranding a gate-passed PR whose merge had not happened; and §4a omitted the label write it claimed to mirror.
- **2026-08-30** — review-loop iter 2: COMMENT, 0 threads. Fixed 3 more findings, all reader-side gaps from the rename: Gate 6 read only `## Gate verdict` while `/merge-gate` falls back to `## QA verdict` for the five in-flight plans; `/review-loop` §4a wrote `stage: GATE` without committing, which `/merge-gate`'s clean-tree guard would refuse on the standalone handoff; and `hs-validator`'s command-vetting whitelist still named only build/lint/test after that dimension was dropped.
- **2026-08-30** — review-loop iter 1: COMMENT, 0 unresolved threads. Fixed 3 confirmed findings — stale `QA` in both spec-template stage enums (missed because the success-criteria grep `stage: QA` cannot match `stage: TRIAGE  # … | QA | …`), the nonexistent `gate-*`/`done` labels, and Gate 6 reading the plan at its pre-move path.

## Open questions

Known limitation, accepted: a feature that has passed the gate but is not yet merged (`stage: DONE` with an open `pr:`) does not appear in `/feature-next`, whose active set stops at `GATE`. Including it would require a `gh pr view` per DONE spec on every `/feature-next` run. The exposure window is the minutes between gate PASS and merge, and `/feature-loop <N>` Phase 0 resumes such a feature correctly by number, so this is documented rather than fixed.

## Invariants this change breaks (for future readers)

Two invariants held before this PR and no longer do. Every *reader* of stage or of the exec-plan path must account for them — all three review iterations found violations of exactly this class:

1. **`DONE` no longer implies merged.** The gate writes `stage: DONE` on the branch, before Gate 6 merges. A spec can be `DONE` with its PR still `OPEN`. Anything that treats `DONE` as terminal, or that resets stage on an open PR, must special-case it.
2. **An open PR's plan is no longer necessarily in `active/`.** The gate `git mv`s it to `completed/` pre-merge, so any lookup keyed to an open PR must glob `{active,completed}`.

## PR convergence ledger

<Append-only. One entry per `/review-loop` iteration.>

- **2026-08-30 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 66044f33; threads_open: 0; action: fixed 3 findings + push; head_sha: 01c914c.
- **2026-08-30 iter 2** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: e7f40d71; threads_open: 0; action: fixed 3 findings + push; head_sha: 6315d1d.
- **2026-08-30 iter 3** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 5a909c25; threads_open: 0; action: fixed 3 findings + push; head_sha: a3b056a.
- **2026-08-30 iter 4** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 0f418bc9; threads_open: 0; action: fixed 8 findings + push; head_sha: ce5ea3b.
- **2026-08-30 iter 5** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: ea3d056b; threads_open: 0; action: stop; head_sha: 3b97161.

## Gate verdict

<Filled by `/merge-gate` before the PR merges. Append-only; one entry per gate run. Stage advances to DONE only when the latest entry is PASS.>

- **2026-08-30** — verdict: PASS; checks: 3 dimensions / 0 failed / 0 followups; followups: none; one-line: gate run pre-merge on the open PR #57 — this change validating itself, all nine success criteria met and every non-goal held.
  - 2026-08-30 dimensions:
    - acceptance — PASS — SC1: `skills/merge-gate/SKILL.md` carries `name: merge-gate`, `skills/feature-qa/` gone. SC2: exactly three dimensions listed; `build/lint/test` and `regression` absent from the dimension list. SC3-SC5: cold-start guard, PASS write order, and the no-follow-up-issues FAIL path verified clause-by-clause against the spec text (SKILL.md is an agent prompt, so text correspondence is the observable). SC6: both `regen-generated.py` copies list `GATE`; `regen-generated.sh` exits 0 on the repo and exits 1 with `invalid stage 'QA'` on a scratch spec. SC7: Phase 6 pushes without merging, Phase 7 gates, Gate 6 merges only after PASS. SC8: sweep returns only the four documented legacy `## QA verdict` mentions. SC9: PR diff carries no generated file and `block-generated-edits` + `verify-generated` pass; the terminal `stage: DONE` write is this very commit, so it was necessarily unobservable from inside the run.
    - non-goals — PASS — `regen-generated.py:251` (`stage=DONE requires shipped`) and the `_shipped_key` sort are outside the diff; no `subprocess`/`git` call exists in the regenerator, so it was not made git-aware; no `QA` → `GATE` alias; `docs/exec-plans/completed/` and active plans `016`/`020` show 0 changed lines; `changesets.yml` untouched and `ci.yml` not in the PR at all; the `review-loop` diff is stage/handoff plumbing only and leaves the review criteria and convergence mechanics untouched.
    - doc accuracy — PASS — changeset `046` is schema-valid and its prose matches the shipped diff; `CHANGELOG.md` unmodified (generated); README cites `/merge-gate`; `AGENTS.md`, `templates/AGENTS.hivesmith.md` and `templates/PLANS.md` all state that `DONE` does not imply merged; both exec-plan templates use `## Gate verdict` and both spec templates list `GATE`; no stale `feature-qa` reference outside the documented fallback.
  - Note: both validators independently flagged that this worktree's local `main` ref was stale at `2c83bfc` (origin/main is `df4aaf8`), so a `main...HEAD` range over-reported the diff. Re-checked against `origin/main...HEAD`: the real PR is 27 files and contains no `ci.yml` and no generated file.
