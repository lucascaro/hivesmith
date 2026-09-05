# Plan approval gate + deterministic pipeline metrics

- **Spec:** [docs/product-specs/069-plan-approval-gate-and-pipeline-metrics.md](../../product-specs/069-plan-approval-gate-and-pipeline-metrics.md)
- **Issue:** #69
- **Status:** active
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
- **2026-09-05** — Implemented all five sequenced parts. All AGENTS.md checks green; 8 previously-orphaned suites verified passing before being gated in CI. PR #70 opened. Stage REVIEW.

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

## PR convergence ledger

- **2026-09-05 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: c44967da371358972530fc7447f7b33c30346aa302cc0a5f4faa01f8fb32ef8e; threads_open: 0; action: autofix+push; head_sha: fa90d8d. Six IMPORTANT findings stood, so the loop continued rather than stopping on COMMENT — convergence is "only MINOR remaining", not "no blockers".

## Gate verdict
