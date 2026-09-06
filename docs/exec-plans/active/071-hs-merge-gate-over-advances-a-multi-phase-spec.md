# /hs-merge-gate over-advances a multi-phase spec to DONE on its first phase's gate

- **Spec:** [docs/product-specs/071-hs-merge-gate-over-advances-a-multi-phase-spec.md](../../product-specs/071-hs-merge-gate-over-advances-a-multi-phase-spec.md)
- **Issue:** #71
- **Status:** active
- **PR:** #72
- **Branch:** `feature/71-merge-gate-phase-aware`

<!--
Stage is **not** carried here. The spec's YAML frontmatter `stage:` is the
sole source of truth. Skills read and write stage from the spec — never from
this file or from the generated `docs/product-specs/index.md`.
-->


## Summary

Three defects from issue #71, all in pipeline skill prose. The headline: `/merge-gate` has no way for a PR to legitimately claim a *subset* of its spec, so a deliberately phased feature must either lie (scope the validator prompts and get a wrong `DONE`) or fail. Fix by letting the exec plan declare `Phase: N of M` and refusing the DONE branch whenever `N < M`. Alongside it, two smaller contract fixes: `/review-loop` contradicts itself on when a `COMMENT` verdict may stop the loop, and its cold-start section never says how to resume after an iteration dies mid-flight.

## Research

### Sub-issue C — the headline: gate over-advances on a partial delivery

- `skills/merge-gate/SKILL.md:68-71` — verdict combination: "All dimensions PASS → `PASS`". No notion of *how much* of the spec the PR claims.
- `skills/merge-gate/SKILL.md:110-119` — the PASS branch, which is what over-advances: sets plan `Status: completed`, `git mv`s the plan to `docs/exec-plans/completed/`, rewrites the spec's `Exec plan:` link, writes `pr:` + `shipped:`, emits `stage_transition GATE→DONE`, sets `stage: DONE`, commits, pushes.
- `skills/merge-gate/SKILL.md:129-135` — `NEEDS_FOLLOWUP`. Its stated semantics are an *ocean* (`:18` — "requires production telemetry, end-user signal, or infrastructure not in this repo"). Its two options are "advance to DONE" or "hold at GATE"; the issue's complaint that holding records nothing is only half true — see below.
- `skills/merge-gate/SKILL.md:73-88` + `docs/exec-plans/_template.md` — the `## Gate verdict` section is append-only and *is* a durable per-run record. It has no field for which slice of the spec was gated, which is the actual missing piece.

**The issue's premise does not hold in this repo.** It states the phased shape is "what `/hs-feature-plan` itself produces via a `### Phasing` section". `grep -rni "phase" skills/feature-plan/SKILL.md docs/exec-plans/_template.md` returns nothing; `grep -rn "Phasing" skills/` returns nothing. There is no phasing convention anywhere in hivesmith. The reporter hit this on a different project ("hive spec 337").

Consequence: option 3 from the issue ("teach the gate to detect a `### Phasing` section") cannot be implemented as a pure guard — it would be dead code that never fires. Delivering the fix means *introducing* a phase declaration this repo does not yet have.

Second consequence: absent a declaration, the gate in this repo would have behaved **correctly** on the reported scenario. If a PR delivers 2.5 of 7 success criteria, the acceptance dimension's own job (`:62` — "confirm the code actually delivers the observable signal", per-criterion evidence) is to FAIL on the 4.5 it cannot observe. The silent PASS the reporter saw came from a human scoping the validator prompts to phase 1. So the defect is better stated as: **the gate has no way for a PR to legitimately claim a subset of the spec, so partial delivery must either lie (scope the prompt, get a wrong DONE) or fail.**

### Sub-issue A — `/hs-review-loop` self-contradiction on `COMMENT`

Confirmed, three call sites plus one restatement:

- `skills/review-loop/SKILL.md:16` (Philosophy) — "The loop ends when the review verdict is `APPROVE` (or `COMMENT` with only MINOR remaining)".
- `skills/review-loop/SKILL.md:144` (§2 step 5) — "`COMMENT` with strict off AND `unresolved_threads_post == 0` — done."
- `skills/review-loop/SKILL.md:75` (worker step 5, the operative rule) — "`COMMENT` → if strict mode is true OR there are unresolved threads, treat as `REQUEST_CHANGES`; otherwise stop."
- `skills/merge-gate/SKILL.md:35` restates it as the gate's own acceptance condition: "its §2 step 5 stops on `APPROVE` with zero threads, and on `COMMENT` with strict off and zero threads". A fix to review-loop that does not update this line makes the gate refuse every converged run.

A `COMMENT` verdict carrying IMPORTANT findings, strict off, zero open threads satisfies `:144`/`:75` and violates `:16`. The reporter followed `:16` and caught a real data-loss-adjacent bug.

**A clean fix already has its signal computed.** `findings_hash` (`:70`) is a SHA-256 over BLOCKING + IMPORTANT findings, followed by unresolved thread ids. With `threads_open == 0`, an empty `findings_hash` means exactly "no BLOCKING and no IMPORTANT remaining" — the Philosophy reading — and requires no new envelope field.

### Sub-issue B — ledger cold-start recovery after a mid-flight death

- `skills/review-loop/SKILL.md:107-113` — the orchestrator appends one ledger line per iteration; `action` is one of `stop | autofix+push | autofix+push (conflict) | escalated:<reason>`.
- `skills/merge-gate/SKILL.md:35` — the guard: refuses unless the latest entry is `action: stop` with `verdict: APPROVE|COMMENT` and `threads_open: 0`; explicitly refuses `escalated:` and "any form of `autofix+push` (the loop stopped mid-flight)".

The refusal message already names the recovery ("tell the user to drive convergence with `/review-loop <pr-number>` first"), so this is smaller than the issue suggests. What is genuinely missing is on the review-loop side: `## Cold-start` (`:23-31`) explains seeding `prev_findings_hash` from the ledger but never says that a trailing `autofix+push` means a prior run died after pushing, that re-running is the recovery, and that it is safe because the next iteration re-reviews the already-pushed head. A doc-only fix.

### Prior lessons

Not consulted — the two `Explore` workers that owned the `brain-search` lookup were killed when the previous session's process exited, and the research was redone in the main thread. No prior lessons were read for this feature.

### Constraints

- Skills are markdown; there is no unit test for skill *prose*. Verification for A and B is grep-shaped (assert the contradictory text is gone and the restatement matches) plus `shellcheck` / the script suites for anything touching bash.
- `AGENTS.md` requires a `.changesets/` entry for user-visible change; all three sub-issues change documented skill behavior.
- Any change to `skills/review-loop/SKILL.md` must keep `skills/merge-gate/SKILL.md:35` in sync — they are a contract pair.

## Approach

**Phase declaration lives in the exec plan header, not the spec.** The plan is the file that already knows *how* the work is sliced; the spec describes the finished feature and should not have to. One optional header field, `Phase:`, defaults to absent — every existing plan keeps today's behavior with no migration.

The gate's verdict logic (`skills/merge-gate/SKILL.md:68-71`) is left alone. Only the **PASS branch** forks: a final phase (`N == M`, or no `Phase:` at all) does exactly what it does today; a non-final phase records the verdict and stops there — no `Status: completed`, no `git mv` to `completed/`, no `pr:`/`shipped:`, no `stage_transition`, no `stage: DONE`. It **still commits and pushes** the `## Gate verdict` append (`chore: gate pass (phase N/M) for #<n>`), because `skills/merge-gate/SKILL.md:39` refuses a dirty tree and `skills/review-loop/SKILL.md:203` commits on the same branch — dropping the commit would break the next run of either. Stage stays `GATE`, and the verdict entry carries `phase: N/M`, which is the durable per-phase record the issue asks for. The PR is still reported mergeable, because a phase PR is meant to merge.

**The exit path is documented, not automated.** Parking at `GATE` is only safe if there is a way out. There is not one today: `skills/review-loop/SKILL.md:28` refuses to demote `GATE`, and `skills/feature-loop/SKILL.md:99` maps `GATE` → Phase 7 unconditionally (`:247` even force-advances a merged-PR plan back to `GATE`), so after phase 1 merges, `/feature-loop 71` would re-gate forever through the degraded `MERGED` path and never re-enter IMPLEMENT. The spec's Non-goals rule out an automatic backwards stage write, so the non-final branch's report and `/feature-loop`'s stage-dispatch table both state the manual step: to start phase N+1, reset the spec's `stage:` to `IMPLEMENT`, bump the plan's `Phase:` to `N+1 of M`, and **clear the plan's `PR:` and `Branch:` fields**.

Clearing those two fields is not cosmetic — without it the documented reset silently undoes itself. `skills/feature-loop/SKILL.md:247` (Phase 5 step 37) reads the plan's still-populated `PR:`, sees the merged phase-1 PR, and force-writes `stage: GATE` straight back; `skills/merge-gate/SKILL.md:33` would likewise resolve the old PR and take its degraded `MERGED` path. So step 37 is itself a file to change: it must skip the force-advance when the plan declares a non-final phase.

Chosen over the issue's option 2 (per-phase `stage:` in spec frontmatter): every stage skill reads `stage:`, so that reshapes the whole pipeline to fix one branch of one skill. Chosen over a pure defensive guard (refuse DONE when fewer criteria verify than the spec lists) because that conflates deliberate phasing with a genuinely failing gate, and gives the operator no way to say which is which.

**Known ceiling, accepted.** With the declaration in the plan header only, the gate cannot mechanically map a success criterion to a phase — the acceptance worker assigns a per-criterion `DEFERRED (phase > N)` from the plan's Approach text, which is judgment, not mechanism. The safety property that matters still holds unconditionally: `N < M` blocks the DONE branch outright, so a mis-labelled criterion produces a wrong *evidence line*, never a wrong `DONE`. Per-criterion `(phase N)` tags in the spec (the issue's option 1) are what would close this; deferred deliberately.

**Sub-issue A** resolves the contradiction toward the Philosophy reading (`skills/review-loop/SKILL.md:16`), which is the one that catches real bugs. No new envelope field is needed: `findings_hash` (`:70`) is already computed over BLOCKING + IMPORTANT findings followed by unresolved thread ids, so with zero unresolved threads, an empty `findings_hash` means exactly "no BLOCKING and no IMPORTANT remaining".

Two scoping constraints on that fix, both load-bearing:

- **The clause belongs to the worker's stop decision (`:75`), not to a post-autofix re-check.** `findings_hash` is computed at worker step 4 from the *pre*-autofix review, while `unresolved_threads_post` (`:144`) is post-autofix. Conjoining a pre-autofix hash with a post-autofix thread count on an iteration that autofixed can never fire, burning iterations toward max-iterations escalation. The worker decides to stop before it autofixes, so at `:75` both values are from the same snapshot; `:144` is restated to defer to that decision rather than recompute it.
- **The gate's cold-start guard is *not* tightened.** `skills/merge-gate/SKILL.md:35` keeps accepting `action: stop` + `verdict: APPROVE|COMMENT` + `threads_open: 0`; only its *description* of the loop's rule is corrected. Requiring an empty `findings_hash` there would retroactively refuse ledgers written under the old rule — `docs/exec-plans/completed/067-wrap-graphify-pretooluse-nudge.md:200` and `docs/exec-plans/completed/036-convert-feature-qa-into-a-pre-merge-merge-gate.md:181` are both real `action: stop` entries carrying a non-empty hash.

**Sub-issue B** is doc-only. The recovery already exists and is already named in the gate's refusal message; what is missing is a sentence on the review-loop side saying a trailing `autofix+push` means a prior run died after pushing, and that re-running is both the recovery and safe (the next iteration re-reviews the already-pushed head).

### Files to change

1. `docs/exec-plans/_template.md` — add optional `- **Phase:** —` header field with a comment explaining `N of M` and that absent means single-phase; extend the `## Gate verdict` example line with `phase: <N/M|—>`.
2. `templates/docs/exec-plans/_template.md` — the byte-identical copy `/hivesmith-init` scaffolds into consumer projects. Same edit, or the field never reaches any consumer.
3. `skills/merge-gate/SKILL.md` — cold-start: parse the plan header's optional `Phase:`. Step 5: add `phase:` to the verdict line format and to the `hs-metric` call. Step 7: fork the PASS branch into final / non-final, with the non-final branch still committing and pushing, and its report naming the manual `stage: IMPLEMENT` + `Phase:` bump needed for phase N+1. Step 6: on a non-final PASS keep the `gate` label. Rules: add "never write `DONE` while the plan declares a non-final phase". Line 35: correct the restated loop rule *without* tightening the guard's own acceptance.
4. `skills/review-loop/SKILL.md` — worker step 5 (`:75`): `COMMENT` stops only with strict off AND zero unresolved threads AND empty `findings_hash`. §2 step 5 (`:144`): restate to defer to the worker's stop decision rather than recompute across snapshots. Philosophy (`:16`): restate "only MINOR remaining" as "no BLOCKING or IMPORTANT findings" so all three agree. Cold-start (`:23-31`): add the mid-flight recovery sentence.
5. `skills/feature-loop/SKILL.md` — stage dispatch (`:99`): note that a `GATE` spec whose plan declares a non-final phase needs the manual reset before it can advance, and spell the reset out. **Phase 5 step 37 (`:247`)**: do not force-write `stage: GATE` on a merged `PR:` when the plan declares a non-final phase — that is what silently undoes the reset. Phase 7 step 46: a non-final-phase PASS does not reach `DONE`. Phase 8 step 49: emit `feature_done` only on a final-phase PASS. Header (`:13`): add the non-final exception to the `DONE` definition.
6. `AGENTS.md:34,40` — the two restatements of the gate contract ("PASS advances Stage → DONE, moves the plan to `completed/`"; "`DONE` = gate PASS recorded and the plan moved to …"). Add the non-final-phase exception.
7. `templates/AGENTS.hivesmith.md:10,16` — the same two restatements in the shipped template.
7b. Four further restatements of the same contract, all currently exception-free: `PLANS.md:21` ("on merge, the file moves to `completed/`"), `templates/PLANS.md:22` ("on gate PASS the file moves to `completed/`"), `skills/feature-loop/SKILL.md:13`, and `templates/docs/product-specs/index.md:26` ("The exec plan moves to `exec-plans/completed/` on merge").
8. `scripts/metrics/emit.sh` — add `phase` to `gate_verdict`'s optional field set (`:103-104`).
9. `scripts/metrics/emit-test.sh` — a case accepting `gate_verdict` with `phase`, and one confirming an unknown field still exits 64.
10. `CHANGELOG.md` — `## [Unreleased]` entry via `/hs-changelog-update`.

### New files

- `.changesets/071-merge-gate-phase-aware-and-review-loop-comment-fix.md` — user-visible behavior change across three skills.

### Tests

Skill files are prose; there is no unit-test harness for them. Verification is grep-shaped assertions on the contract text plus the existing bash suites for the one script that changes. **Every grep below was checked against the current files and fails today**, with two deliberate exceptions marked inline: the `threads_open: 0` line is a negative control (it must keep passing — it asserts the guard was *not* tightened), and `diff` on the two template copies passes today because they are currently identical and must stay so.

- `scripts/metrics/emit-test.sh` — add `gate_verdict` + `phase=1/3` accepted (exit 0); `gate_verdict` + `phaze=1/3` rejected (exit 64).
- Contract-sync greps: the two template copies stay in sync; the `COMMENT` stop condition names BLOCKING/IMPORTANT at all three review-loop sites; `merge-gate` documents the non-final fork and the manual reset.

## Verification

```bash
set -e

# 1. Metrics schema — the only executable change.
bash scripts/metrics/emit-test.sh

# 2. Sub-issue A: the stale phrasing is gone. NOTE the backticks in the real text
#    (merge-gate:35 reads "on `COMMENT` with strict off and zero threads"), so the
#    pattern must tolerate them. This currently MATCHES, i.e. the check fails today.
! grep -rn 'COMMENT.\{0,2\} with strict off and zero threads' skills/
! grep -rn 'COMMENT.\{0,2\} with only MINOR remaining' skills/
# ...and the new wording is present at all three review-loop sites (currently 0):
# Every restatement of the stop condition, in any phrasing. The earlier `-ge 3`
# floor let a fourth site (§3.5, hyphenated "COMMENT-with-strict-off") survive.
! grep -rn 'COMMENT-with-strict-off' skills/
[ "$(grep -c 'BLOCKING or IMPORTANT' skills/review-loop/SKILL.md)" -ge 4 ]
# merge-gate must now reference the hash rule in its restatement (currently 0 hits):
grep -q 'findings_hash' skills/merge-gate/SKILL.md
# ...but its own guard must NOT have been tightened — legacy ledgers still gate:
grep -q 'threads_open: 0' skills/merge-gate/SKILL.md

# 3. Phase declaration wired end to end, in BOTH template copies (anchored, so a
#    stray "Phasing:" cannot satisfy it; currently 0 hits in both).
grep -q '^- \*\*Phase:\*\*' docs/exec-plans/_template.md
grep -q '^- \*\*Phase:\*\*' templates/docs/exec-plans/_template.md
cmp -s docs/exec-plans/_template.md templates/docs/exec-plans/_template.md
grep -q 'non-final' skills/merge-gate/SKILL.md
grep -q 'non-final' skills/feature-loop/SKILL.md
# The strand-prevention exit path must be documented in both skills:
grep -qi 'reset .*stage.*IMPLEMENT\|stage: IMPLEMENT' skills/merge-gate/SKILL.md
grep -q 'Exception — a non-final phase' skills/feature-loop/SKILL.md   # step 37 fix
# The four newly-found restatements must all carry the exception:
for f in PLANS.md templates/PLANS.md templates/docs/product-specs/index.md; do
  grep -qi 'phase' "$f"; done
# Shipped docs must carry the exception too — anchored to the DONE restatement
# line, not merely the word "phase" appearing anywhere in the file:
grep -q 'completed/`.*non-final\|non-final.*completed/`' AGENTS.md
grep -q 'completed/`.*non-final\|non-final.*completed/`' templates/AGENTS.hivesmith.md

# 4. Sub-issue B: assert the new recovery sentence, not the pre-existing enum
#    value (the bare string "autofix+push" already appears 3x today).
grep -qi 'died\|mid-flight' skills/review-loop/SKILL.md

# 5. Lint + the full script suites from AGENTS.md.
shellcheck scripts/metrics/emit.sh scripts/metrics/emit-test.sh
for s in scripts/telemetry/install-hooks-test.sh scripts/telemetry/attribution-test.sh \
         scripts/harvest/plan-citations-test.sh scripts/harvest/harvest-plans-test.sh \
         scripts/harvest/correction-episodes-test.sh scripts/metrics/emit-test.sh \
         scripts/metrics/regressions-test.sh scripts/metrics/backfill-test.sh \
         skills/plan-html/wait-test.sh; do bash "$s"; done   # no `|| echo`: it would defeat set -e

# 6. Render correctness, WITH the two assertions AGENTS.md pairs with the install
#    (bare install exits 0 even if a new cross-reference failed to get prefixed).
H=$(mktemp -d) && mkdir -p "$H/.claude" && HOME=$H ./install.sh --prefix hs- --no-auto-update
grep -q '/hs-feature-plan' .rendered/hs-/skills/hs-feature-research/SKILL.md
! grep -q '/feature-plan\b' .rendered/hs-/skills/hs-feature-research/SKILL.md

# 7. Doc accuracy. The AGENTS.md changelog gate (`[Unreleased]` non-empty) already
#    passes today with ~104 lines, so it cannot detect a missing entry for THIS
#    feature. Assert the changeset the plan actually promises:
ls .changesets/071-*.md
```

## Second opinion

**Round 1 — verdict `revise`, confidence 8.** The reviewer accepted the approach and criteria coverage but found three vacuous verification greps (patterns that already pass today, so the plan could be "verified" on a broken implementation), two missed blast-radius files (the shipped template copy and both `AGENTS.md` restatements), and three behavioral holes: the non-final PASS never said whether it commits (leaving a dirty tree that the next gate run refuses), no exit path from a non-final `GATE` (stranding the feature — the exact failure this spec exists to prevent), and a tightened cold-start guard that would retroactively refuse already-recorded converged ledgers.

**Disposition: all 8 must-fix items applied**, plus all 3 nice-to-haves (the pre/post-autofix `findings_hash` snapshot mismatch, the anchored `Phase:` grep, and the two missing render assertions). Every claim was verified against the files first — the byte-identical `templates/docs/exec-plans/_template.md`, the `AGENTS.md:34,40` and `templates/AGENTS.hivesmith.md:10,16` restatements, and two real legacy ledger entries carrying `action: stop` with a non-empty hash (`067:200`, `036:181`) all check out. The strand hole and the ledger back-compat hole in particular changed the design, not just the prose: the gate's guard is now explicitly *not* tightened, and the manual `GATE → IMPLEMENT` reset is a documented deliverable.

**Round 2 — verdict `revise`, confidence 8.** The re-review confirmed the round-1 disposition against the files and found every substantive grep now failing as claimed, but blocked on three things. The documented exit path did not actually work: `skills/feature-loop/SKILL.md:247` reads the plan's still-populated `PR:`, sees the merged phase-1 PR, and force-writes `stage: GATE` back, stranding the feature exactly as before. Blast radius was still four restatements short (`PLANS.md:21`, `templates/PLANS.md:22`, `skills/feature-loop/SKILL.md:13`, `templates/docs/product-specs/index.md:26`). And the spec file itself was malformed — an earlier scripted edit had matched `## Success criteria` *inside the quoted issue body* and truncated everything after it, including the `<!-- END EXTERNAL CONTENT -->` marker and the real `## Success criteria` heading, which would have made `/merge-gate` refuse this feature's own gate.

**Disposition: all 4 must-fix items applied**, plus all 4 nice-to-haves (the `|| echo` that defeated `set -e`, the overstated "every grep fails today" claim, the missing feature-loop-side reset assertion, and the unanchored `AGENTS.md` phase grep). The spec was rebuilt from the issue body and verified intact. Two of the four changed the deliverable rather than the wording: step 37 is now a file to change, and the phase-N+1 reset must clear the plan's `PR:`/`Branch:` fields or it silently undoes itself.

Per the loop's rules the reviewer is not run a third time; the remaining judgment is the operator's.

## Decision log

- **2026-09-05** — Build all three sub-issues from #71 in one spec. Why: operator choice at the clarifying round; A and B are small and share contract text with C (`merge-gate:35`), so splitting would mean two PRs touching the same lines.
- **2026-09-05** — Declare phases via an optional `Phase: N of M` field in the exec-plan header, not per-phase `stage:` in spec frontmatter. Why: operator choice; every stage skill reads `stage:`, so the frontmatter option reshapes the whole pipeline to fix one branch of one skill.
- **2026-09-05** — On a non-final phase PASS the spec stays at `GATE`; the operator drives phase N+1 manually. Why: operator choice; a backwards stage write (`GATE → IMPLEMENT`) would be a new pattern in this pipeline and is not needed to fix the reported defect.
- **2026-09-05** — Resolve the `COMMENT` contradiction toward the Philosophy reading using the existing `findings_hash`. Why: it is the reading that caught a real bug in the reporter's run, and `findings_hash` already encodes "no BLOCKING or IMPORTANT", so no envelope change is needed.
- **2026-09-06** — Corrected two verification assertions during implementation. `diff` is shadowed by a broken shell function in this environment (`diff: function definition file not found`), so the template-sync check uses `cmp -s`; and `grep -qi 'stage: IMPLEMENT' skills/feature-loop/SKILL.md` turned out to be vacuous — the string already existed in Phase 4 — so it now asserts the step-37 exception text instead.
- **2026-09-06** — Verified the new `emit-test.sh` accept case against the pre-change schema: it fails without the `phase` addition. A schema test that passes either way would assert nothing.
- **2026-09-06** — The phase-N+1 reset must clear the plan's `PR:`/`Branch:` fields, and `/feature-loop` step 37 must skip its force-advance on a non-final phase. Why: reviewer round 2 showed the documented reset undoes itself otherwise — step 37 reads the merged phase-1 PR and writes `stage: GATE` straight back.
- **2026-09-06** — Rebuilt `docs/product-specs/071-*.md` from the issue body. Why: an earlier scripted edit matched `## Success criteria` inside the quoted issue text and truncated the file, dropping the END EXTERNAL CONTENT marker and the real criteria heading. Lesson for implementation: never anchor a scripted edit on a heading string that also appears inside quoted external content.
- **2026-09-06** — Do not tighten `/merge-gate`'s cold-start guard to require an empty `findings_hash`; correct only its description of the loop's rule. Why: reviewer round 1 found real ledgers recorded under the old rule (`067:200`, `036:181`) carrying `action: stop` with a non-empty hash — tightening would retroactively refuse them.
- **2026-09-06** — Scope the `findings_hash` clause to the worker's own stop decision (`:75`), not the orchestrator's post-autofix check (`:144`). Why: the hash is computed pre-autofix and `unresolved_threads_post` is post-autofix; conjoining them across snapshots can never fire on an iteration that autofixed, burning iterations toward escalation.
- **2026-09-06** — A non-final phase PASS still commits and pushes its verdict append. Why: `merge-gate:39` refuses a dirty tree and `review-loop:203` commits on the same branch, so dropping the commit breaks the next run of either.
- **2026-09-06** — Document a manual `stage: IMPLEMENT` + `Phase:` bump as the exit from a non-final `GATE`. Why: `review-loop:28` never demotes `GATE` and `feature-loop:99` maps `GATE` back to the gate phase unconditionally, so parking at `GATE` without a documented exit strands the feature — the very failure this spec exists to prevent. An automatic backwards stage write is a stated Non-goal.
- **2026-09-05** — Research ran in the main thread, not `Explore` workers. Why: the two dispatched workers were killed when the previous session's process exited, and the two target files are 153 and 234 lines — cheaper to read directly than to respawn. Consequence: the hive-brain lookup those workers owned did not run.

## Progress

- **2026-09-06** — Spec ingested, triaged (bug / M / P1), researched, planned. Two reviewer rounds (`revise`/8 both times), 12 must-fix items applied.
- **2026-09-06** — Plan approved via chat fallback; the HTML review page timed out after ~12 min (8 `wait.sh` rounds) and its server was stopped per the skill's loop cap.
- **2026-09-06** — Implemented on `feature/71-merge-gate-phase-aware`: `Phase:` field in both template copies, merge-gate PASS fork + `Phase:` parse + acceptance `DEFERRED` handling + Rules entry, review-loop COMMENT fix across 3 sites + mid-flight recovery note, feature-loop step 37 exception + dispatch + steps 46/49, six shipped-doc restatements, `phase` in the `gate_verdict` schema with 2 new tests, changeset.
- **2026-09-06** — All checks pass: `emit-test.sh` 29/29, shellcheck clean, 9/9 script suites, install smoke + both render assertions, every verification grep.

## Open questions

- Per-criterion `(phase N)` tags in the spec (issue option 1) are deliberately deferred. Until they exist, which criteria belong to phase N is the acceptance worker's judgment call, read from the plan's Approach. Revisit if a phase PASS ever mislabels a criterion in practice.
- A non-final phase PASS keeps the `gate` label rather than introducing a `gate-phase-passed` label. If phased features become common, a distinct label may be worth the addition to the scheme.

## PR convergence ledger

<Append-only. One entry per `/review-loop` iteration so a fresh harness run can pick up where the previous one left off without rereading PR comments. Keep entries one line each.>

- **2026-09-06 iter 2** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: 3bce8ebf336fecbed0c09b65808aba137f465ea68794c4ddb98939a96f7d1521; threads_open: 0; action: autofix+push; head_sha: a3a991a.
- **2026-09-06 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: bf98334832cc3f0f4439ac469c65b440c24f430cf5ee70757b011314f404fa37; threads_open: 0; action: autofix+push; head_sha: 43bf2aa.

## Gate verdict

<Filled by `/merge-gate` before the PR merges. Append-only; one entry per gate run. Stage advances to DONE only when the latest entry is PASS.>

- **<date>** — verdict: <PASS|FAIL|NEEDS_FOLLOWUP>; checks: <bullet summary>; followups: <issue numbers or "none">; one-line: <summary>.
