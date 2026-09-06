# Plan approval gate + deterministic pipeline metrics

- **Spec:** [docs/product-specs/069-plan-approval-gate-and-pipeline-metrics.md](../../product-specs/069-plan-approval-gate-and-pipeline-metrics.md)
- **Issue:** #69
- **Status:** completed
- **PR:** #70
- **Branch:** feature/69-plan-approval-gate-and-pipeline-metrics

## Summary

Give the HTML plan review a real blocking approval gate (`wait.sh`), and give the whole pipeline a schema-validated event stream (`hs-metric`) plus declared regression attribution, so "are the skills getting better" and "is the second opinion worth its cost" become answerable from data instead of prose.

## Research

- `skills/plan-html/SKILL.md:36-47` — the canonical call sequence. Step 5 ("Poll `<plan>.approved.json`") is prose with no mechanism; `grep -rn Monitor skills/` returns zero and there is no wait script anywhere in the repo.
- `skills/plan-html/start.sh:46` clears only the port file; `:61` backgrounds with `nohup` and returns; `:64` overwrites the pid sidecar unconditionally, so `stop.sh:21` can never reap a predecessor.
- `skills/plan-html/server.py:112-118` writes `.approved.json`; `:119-122` writes `.feedback.json`. `template.html:265` autosaves on a 1.2s debounce; `:281` saves before POSTing `/approve`; `:286-288` disables the button and shows "✓ Approved".
- `scripts/telemetry/` — existing JSONL stream at `${HIVESMITH_HOME:-~/.hivesmith}/telemetry/agent-events.jsonl`; `log-agent.sh:12-13` must never fail a session; `prepare-commit-msg:40` scans that file for tool attribution.
- `scripts/harvest/harvest_plans.py:38` — the existing squash-commit PR regex to extend; `:26-31` argues against underpowered comparisons, the same argument that rules out a second-opinion holdout here.
- `scripts/release.sh:88` deletes all `.changesets/*.md`; `scripts/regen-generated.py:152` renders only the body. Declarations must be recovered from git history.
- `scripts/brain/append.sh:47-63` — the house arg-parsing shape for the emitter.
- 8 test suites under `scripts/telemetry/` and `scripts/harvest/` have no CI job.
- Prior lessons: `brain-search` returned no qualifying hits for these terms.

## Approach

**Approval gate.** A blocking `wait.sh` invoked as a foreground Bash call, not a runtime-specific primitive — portable across the five harnesses in `agents.json`, where a `Monitor`-style tool is Claude-Code-only. It returns distinct exit codes so the caller loops within the harness's bounded Bash timeout rather than depending on one long call. Stale-sidecar and orphaned-server cleanup goes in `start.sh`, not in an instruction telling the LLM to call `stop.sh` on every exit path: you cannot guarantee a cleanup step, but you can guarantee the next start reaps.

**Metrics.** A separate `pipeline-events.jsonl`, because `hs-metric` must fail loudly while the telemetry hooks must never fail a session — opposite contracts belong in opposite files. Validation rejects *unknown fields*, which is what stops the drift back to prose; a free-text escape hatch would absorb everything within a week.

**Regressions.** Declared in `.changesets/` frontmatter by the agent writing the fix, harvested from git history. Blame-based inference is explicitly rejected (a bug can live on lines the fix never touches; a refactor is not a defect), and the three states Regressed / Clean / Unobserved stay distinct so a young PR is never reported as clean.

### Files to change

- `skills/plan-html/start.sh` — reap predecessor, clear stale approval/feedback sidecars
- `skills/plan-html/SKILL.md` — rewrite canonical steps 5-6 as Wait / Never poll by hand / Stop; add `plan_rendered` + `plan_approved` emits
- `skills/plan-html/README.md` — "the agent watches for that file" becomes true
- `skills/feature-plan/SKILL.md` — step 9's HTML-path sentence
- `skills/feature-loop/SKILL.md` — wait.sh note + 9 `hs-metric` sites
- `skills/review-loop/SKILL.md` — `review_iteration` emit beside the ledger append
- `skills/merge-gate/SKILL.md` — `gate_verdict` emit; `regression_of: declared-absent` note
- `skills/autofix/SKILL.md` — `autofix_applied` emit
- `skills/changelog-update/SKILL.md` — step 2b (regression declaration) + frontmatter shape
- `skills/hivesmith-init/SKILL.md` — per-repo telemetry opt-in checklist item
- `.changesets/README.md`, `docs/exec-plans/_template.md` (+ templates mirror) — schema
- `install.sh` — `hs-metric` symlink, uninstall entry, telemetry doctor advisory
- `.github/workflows/{ci.yml,changesets.yml}`, `AGENTS.md`

### New files

- `skills/plan-html/wait.sh` — the blocking approval gate
- `skills/plan-html/wait-test.sh`
- `scripts/metrics/emit.sh` — validated JSONL emitter, symlinked as `hs-metric`
- `scripts/metrics/regressions.py` — declared-regression harvester
- `scripts/metrics/report.py` — two-tier report
- `scripts/metrics/backfill.py` — seed history from plan markdown
- `scripts/metrics/{README.md,emit-test.sh,regressions-test.sh}`

### Tests

- `skills/plan-html/wait-test.sh` — `test_stale_approval_is_cleared_by_start`, `test_predecessor_server_is_reaped`, `test_returns_0_on_approval`, `test_returns_10_on_quiesced_feedback`, `test_does_not_return_10_while_still_typing`, `test_identical_rewrite_is_not_feedback`, `test_returns_11_on_timeout`, `test_returns_3_when_server_dies`, `test_approval_beats_simultaneous_feedback`, `test_stop_flag_reaps_on_approval`, `test_bash32_compatible`
- `scripts/metrics/emit-test.sh` — valid append, five rejection modes, `test_failure_appends_nothing`, `HIVESMITH_HOME` respect, concurrent writers, never touches `agent-events.jsonl`
- `scripts/metrics/regressions-test.sh` — squash / merge-commit / truncated-subject PR recovery, deleted-changeset recovery, three-state split, `--validate-changed` rejections

## Verification

```bash
bash skills/plan-html/wait-test.sh
bash scripts/metrics/emit-test.sh
bash scripts/metrics/regressions-test.sh
python3 skills/plan-html/render_plan.py --self-test
python3 scripts/metrics/regressions.py . --soak-days 30
python3 scripts/metrics/backfill.py --emit --dry-run
python3 scripts/metrics/report.py --since 2026-01-01
scripts/brain/test/run-all.sh
tests/install-agent-scopes-test.sh
shellcheck $(git ls-files '*.sh' | grep -v -E '^(templates|\.rendered)/') skills/plan-html/wait.sh
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .
```

## Decision log

- **2026-09-05** — Sink is user-level `~/.hivesmith/telemetry/`, not committed. Why: operator's call; keeps PRs free of metric noise.
- **2026-09-05** — Regression attribution is declared, never blame-inferred. Why: operator — a bug can live on lines the fix does not touch, and a refactor is not a defect. All commits and PR titles are agent-written, so declaration is checkable.
- **2026-09-05** — No holdout arm for the second opinion. Why: ~3 samples/year cannot distinguish a 30% effect from noise, and each holdout ships a real feature unchecked. `harvest_plans.py:26-31` makes the same argument about model comparison. Measurement is correlational and says so in its own output.
- **2026-09-05** — No second-opinion backfill. Why: n=2, both `revise`; the parser would exceed the data.
- **2026-09-05** — Telemetry hooks stay opt-in; `install.sh` gets a doctor advisory and `/hivesmith-init` gets a per-repo checklist item targeting `.claude/settings.local.json`. Why: the hooks fire in every session on the machine, and the hook command embeds an absolute path to this clone, so a committed `settings.json` would break other contributors.
- **2026-09-05** — Separate `pipeline-events.jsonl` rather than extending `agent-events.jsonl`. Why: `prepare-commit-msg:40` reads that file for attribution, and the hooks must never fail a session while `hs-metric` must fail loudly.
- **2026-09-05** — `review-loop:76-77`'s prose parse stays. Why: already cross-checked against GraphQL; a new control-flow dependency buys no correctness.
- **2026-09-05** — Regression harvest walks `git log --diff-filter=A -- .changesets/`. Why: `release.sh:88` deletes the files and `regen-generated.py:152` drops frontmatter, so a working-tree scan zeroes out at the next release.

## Progress

- **2026-09-05** — Spec and exec plan created; branch `feature/69-plan-approval-gate-and-pipeline-metrics` opened. Stage IMPLEMENT.
- **2026-09-05** — Implemented all five sequenced parts. All AGENTS.md checks green; the 5 previously-orphaned suites verified passing before being gated in CI. PR #70 opened. Stage REVIEW.

## Open questions

None.

## Review findings addressed (iter 1)

Six IMPORTANT findings from `/hs-review-pr`, all fixed:

1. **`regressions.py` merged-PR universe was built only from changeset-adding commits.** PRs merged under the `no-changeset` label never entered the set, so a legitimate `regression_of:` naming one was reported as a dangling reference to a PR that never existed, and the denominator undercounted. Now derived from full history via `commit_prs()` — the real count is 52, not 21.
2. **`ITER` regex captured `3` from `iter 3c`.** Those rows happened to be dropped by the enum check, not the regex, so a future sub-iteration with valid enum values would have backfilled under a colliding iteration number. Tightened with a `(?![\w.])` lookahead.
3. **`backfill.py` had no tests and was absent from CI** — added `backfill-test.sh` (26 checks).
4. **`report.py` had no tests** — covered by the same suite, including that the second-opinion disclaimer prints inline with the number.
5. **`changeset_history()` spawned 2 git subprocesses per changeset**, on a path the `metrics` CI job runs every push. Restructured to 3 total calls via one bulk `git log` plus `git cat-file --batch` (measured 43 → 3). The batch reader is byte-framed, not text-framed: changeset bodies contain em dashes, and slicing a decoded string by git's byte length silently shifts every later file's content onto the wrong changeset.
6. **Dangling `/hs-metrics` reference** in `hivesmith-init` — no such skill exists; points at `scripts/metrics/report.py`.

Two MINOR findings were deliberately not acted on: `templates/scripts/regressions.py` being a byte-identical copy matches the existing convention for `regen-generated.sh` and `migrate-to-changesets.sh` (the absent drift-check is pre-existing and out of scope), and `pipeline-events.jsonl` having no rotation matches the existing `agent-events.jsonl` pattern.

## Decision log (operator, post iter 2)

- **2026-09-05** — Added top-level `permissions: contents: read` to `.github/workflows/changesets.yml`. Why: operator decision on the RISKY item surfaced by review iteration 2. This PR introduced the divergence from the workflow's own template, which already declared it. `regenerate-generated` re-grants `contents: write` at job level, so only the two read-only PR gate jobs are narrowed.
- **2026-09-05** — Declined charset validation on `emit.sh` free-text fields. Why: operator decision. The injection vector is closed at the source — `review-loop/SKILL.md` requires those values be slugged to `[a-z0-9-]` before reaching a command line — and there is no single obviously-correct charset, so a gate here would risk rejecting legitimate values for defense that is already in place.

## Review findings addressed (iter 3)

Eight IMPORTANT findings, all fixed. Two were gaps in this feature's own design, and one was a bug the test suite actively asserted as correct:

1. **`regression_of: #42` produced no declaration at all.** The iter-2 fix made `parse_regression_of` tolerant by filtering non-digits, which meant a malformed target vanished instead of surfacing — contradicting the function's own comment, and making the PR read as clean while a human had explicitly declared a regression against it. Now returns both halves; malformed targets are reported as malformed.
2. **`REVIEW→GATE` and `GATE→DONE` emitted no `stage_transition`.** `/review-loop` §4a and `/merge-gate` are the declared single owners of those writes and neither carried the event, so `report.py` could never render a GATE or DONE row. Directly contradicted "metrics are unconditional".
3. **`backfill.py --emit` doubled every row on a rerun, and `backfill-test.sh` asserted the doubling** (`n2 == 2 * n1`) — the test cemented the bug. Now idempotent by `(event, backfill_source)`, with `--force` as the documented escape hatch.
4. **`stop.sh` SIGKILLed an unverified PID.** Pre-existing, but this feature added two automatic callers (`start.sh`'s reap, `wait.sh --stop`), so what needed a deliberate call now fires on every plan render — with recycled PIDs that is someone else's process. Verifies the PID is a plan-html server first.
5. **`install.sh --doctor` reported "telemetry: not wired"** even for a project that took the per-repo opt-in, which reads as a broken install and invites a second machine-wide one.
6. **A missing `hs-metric` binary halted the pipeline.** Install lag is not a metrics failure; the emitter now resolves `~/.hivesmith/bin/hs-metric` → `scripts/metrics/emit.sh`, and if neither exists prints one visible "NOT being recorded" line and continues. A schema rejection still fails loudly — `|| true` is explicitly forbidden.
7. **`validate_changed` re-walked full base history once per declaration**, inside the CI gate. Hoisted.
8. **`ci.yml` piped `harvest_plans.py` into `tail`,** so a crash reported the pipeline's status and passed silently.
9. **Only the first retired gate dimension survived backfill** — legacy entries carry both `build/lint/test` and `regression`.
10. **The suites required `timeout`,** absent on stock macOS where `AGENTS.md` tells developers to run them. A `perl -e alarm` fallback preserves real exit codes; a background-and-kill shim was tried first and reported the watchdog's status instead of the command's, so it silently passed everything.

## Review findings addressed (iter 4)

Seven IMPORTANT findings. The first is the most serious defect found in the whole run.

1. **Feedback that settled across a timeout boundary was silently discarded.** `wait.sh` snapshotted the *live* feedback file at each startup, but the caller loops it up to 8 times on exit `11`. Feedback still inside its quiet period when a window closed became the next window's baseline, so `cmp` never differed again, exit `10` was unreachable, and the note was lost. Autosave is the only path feedback takes — the page has no explicit submit — so this defeated the revise round of this PR's headline feature. Reproduced before the fix (round 2 returned `11` with the operator's note sitting on disk) and verified after across all four states: late feedback recovered, not re-reported once delivered, and a genuinely new edit still reported. The baseline is now what the agent has *been told*, persisted in `<plan>.feedback.seen.json`.
2. **The backfill dedup key was not stable.** `<path>:<line>` carries `active/` vs `completed/`, and `/merge-gate` git-mv's every plan on PASS; line numbers also shift as the append-only sections above the ledger grow. Either one re-emits and doubles every backfilled statistic — the exact failure the dedup was added to prevent. Identity is now feature number plus a within-feature discriminator (`iter`, or a new `seq` for gate rows); verified stable across a simulated plan move.
3. **`test_prose_action_not_mapped_to_enum` was vacuous** — it asserted the absence of a JSON fragment whose key order made it unmatchable, so it passed regardless. Now asserts the offending row produced no event at all.
4-6. **Bare `hs-metric` invocations** in `/review-loop` and `/merge-gate` are not on `PATH`, so the two stage events added in iter 3 could never have fired; and the missing-emitter fallback was documented only in `/feature-loop` while four other skills invoke it. Absolute path everywhere, and each emitting skill now carries the resolution rule.
7. **`plan-html`'s overview still said the caller "detects `<plan>.approved.json`"** — the description of the bug this PR fixes.

## Review findings addressed (iter 5)

Five IMPORTANT plus four MINOR, all in the metrics-instrumentation surface — none touched the two shipped mechanisms. Iteration 5 explicitly reported the PR as merge-ready before these were applied; they were fixed because they were cheap and real, not because they blocked.

1. **`~~/.hivesmith/bin/hs-metric` — a double tilde** introduced by iteration 4's own path fix. Bash does not expand `~~/`, so the GATE→DONE call failed, the missing-emitter rule swallowed it, and the DONE row that fix existed to enable still never appeared. Sole occurrence in the repo.
2. **`plan_rendered`'s `round` could never exceed 1** — the emit was bundled into the serve step, and the revise branch must not re-run `start.sh`, so it never re-emitted. Split into 4a (emit) and 4b (serve); the revise branch re-runs 4a only.
3. **`plan-html` emitted `feature=<NNN-or-slug>`** while every other skill emits `feature=<NNN>`. A slug joins to nothing and sorts to the end of `report.py`'s trend ordering. Now `<NNN>`, with "omit the metric" as the documented answer for a standalone plan.
4. **`seconds_to_approval` was required but unobtainable** on the native-plan-mode and chat paths, which never run `start.sh` — the schema was pushing the agent to invent a duration, the one thing this stream forbids. Now optional.
5. **The malformed and dangling `regression_of` WARN paths had no full-report test.** The existing fixture only reached `--validate-changed` before being removed, so the iteration-3 crash (a bare `int()` killing the report and the CI metrics job) was re-introducible with the suite green. Now covered with a committed fixture — using `twelve` rather than `#42`, because `#` after a colon is a comment in both YAML and this parser and would not exercise the path at all.

Minor: the recycled-PID guard was an unanchored `grep server.py` (now matches the skill's own path); a PR named by two fix changesets was counted twice in the regressed total; `backfill.py`'s docstring RESULT contract omitted `already_present=`.

## Review findings addressed (iter 6)

Operator-requested extra round, past the 5-iteration budget, to cover iteration 5's own diff — which no review had seen. Nine of its ten hunks were verified correct and introduced nothing. One IMPORTANT:

1. **A vacuous assertion in the test iteration 5 added to close a coverage hole.** `nocheck ... "regressed 0   clean 0"` asserted the absence of a string this corpus never prints (it prints `regressed 1   clean 3`), so it passed no matter what the tool did — it would have passed with the original silent-drop bug restored. Replaced with per-kind WARN counts (2 malformed + 1 dangling), and **mutation-tested**: reintroducing the silent-drop behaviour makes it fail, along with two neighbouring checks. This is the third round in which a fix introduced the next defect, though the weakest instance — it weakened a new test rather than shipped behaviour.

## PR convergence ledger

- **2026-09-05 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: c44967da371358972530fc7447f7b33c30346aa302cc0a5f4faa01f8fb32ef8e; threads_open: 0; action: autofix+push; head_sha: fa90d8d. Six IMPORTANT findings stood, so the loop continued rather than stopping on COMMENT — convergence is "only MINOR remaining", not "no blockers".
- **2026-09-05 iter 2** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: b0a9c689b412f4ee6e16a26bf4e2b6d94f58a538fa4840b95bf3f56dd37d75b8; threads_open: 0; action: escalated:risky fix needs human decision; head_sha: c4a7d33. 12 safe fixes applied and pushed, CI green; 2 RISKY items surfaced for the operator.
- **2026-09-05 iter 3** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 774dc1abc62b4ece81e953703fc7ad8a2440a1f4f839391e8c0266b41cd657af; threads_open: 0; action: autofix+push; head_sha: 30c0114. 8 IMPORTANT stood (zero recurrence from iter 2), so the loop continued rather than stopping on COMMENT.

- **2026-09-05 iter 4** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: aae4bdf03ac17ca9243ac3e5201eeb3ac81b3881b970c25f49c682284801098a; threads_open: 0; action: autofix+push; head_sha: bcde37e. 7 IMPORTANT stood, including a confirmed silent-feedback-loss defect in wait.sh; loop continued.
- **2026-09-05 iter 5** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: cd55ad2f406d6183a35ff6105c98eefaf844616cee5e37449c71240026667245; threads_open: 0; action: stop; head_sha: 382f1cd. Reviewer's explicit merge-readiness call: nothing blocking; 5 IMPORTANT confined to telemetry fidelity, fixed anyway. Loop reached its 5-iteration budget.
- **2026-09-05 iter 6** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 3dbe5731dc16a75550e6615b60518e21d2bfd101059ddec7191e678cf59560dc; threads_open: 0; action: stop; head_sha: 2142243. Operator-requested round past budget to review iter 5's diff; 9 of 10 hunks verified clean, 1 vacuous test assertion fixed and mutation-tested. **Ledger correction:** this line first read `action: autofix+push`, which recorded the orchestrator's follow-up fix rather than the loop's terminal decision — the worker's own decision was `stop` (COMMENT, strict off, zero threads). The head did advance afterwards to `3e0051a` (the test-assertion fix) and `1ca015a` (the GATE bookkeeping), so those two commits were not themselves reviewed; the gate below records that as an explicit exception rather than treating the ledger as clean.

## Gate verdict

- **2026-09-05** — verdict: PASS; checks: 3 dimensions passed / 0 failed / 0 followups; followups: none; one-line: all 8 success criteria exercised live (not read), all 5 non-goals held, docs accurate after correcting an inflated suite count found by the gate itself.
  - 2026-09-05 dimensions:
    - acceptance — PASS — all 8 criteria exercised by execution, not inspection: wait-test 27/27, emit-test 27/27, regressions-test 21/21, backfill-test 34/34; predecessor reaping reproduced live (first pid killed, second alive); all five `hs-metric` rejection modes confirmed to exit 64 with no file ever created; `regressions.py` printed three distinct counts (merged 52 / regressed 0 / clean 31 / unobserved 21) and no bare rate; `report.py` counted live and backfilled rows separately.
    - non-goals — PASS — no holdout arm (reviewer dispatched unconditionally; `report.py` explicitly disclaims one); `backfill.py` parses no `## Second opinion` section; `install.sh`'s telemetry block is report-only with no write to any settings file; `review-loop`'s prose parse and GraphQL cross-check are unchanged and `autofix_applied` is measurement-only; no committed metrics artifact (`git ls-files` shows no tracked `.jsonl`). No scope bleed beyond the plan's stated blast radius.
    - doc accuracy — PASS — changeset frontmatter valid and `CHANGELOG.md` untouched; the `AGENTS.md` ↔ `ci.yml` shellcheck invariant holds at 45/45 with an empty symmetric difference; `templates/scripts/regressions.py` byte-identical to source; every documented `hs-metric` invocation resolves and uses only fields in `emit.sh`'s SCHEMA; no live `/hs-metrics` or `~~/` reference remains.
  - 2026-09-05 correction applied during the gate: the spec, changeset and plan claimed **8** orphaned test suites; only **5** were actually unexecuted on `main` (`scripts/brain/test/run-all.sh` and `skills/graphify-init/test/run-all.sh` already had CI jobs). The `script-suites` job runs 9 suites: those 5 plus 4 new. Corrected in all three files before the verdict was recorded — the changeset text renders into `CHANGELOG.md`, so this would otherwise have shipped a wrong number to users.
  - **Ledger exception (operator-approved):** the gate's cold-start guard requires the latest ledger entry to read `action: stop`. Iteration 6's entry was first written as `autofix+push`, which recorded the orchestrator's follow-up fix rather than the loop's terminal decision (the worker decided `stop` on COMMENT with zero threads). It was corrected, and the head did advance afterwards to `3e0051a` and `1ca015a` — a mutation-verified test-assertion fix and the GATE bookkeeping, no production code — which no review covered. The operator elected to proceed with the exception recorded rather than spend a seventh review round on 22 lines of test file.
