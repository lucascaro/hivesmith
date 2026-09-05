#!/usr/bin/env bash
# Tests for backfill.py and report.py against a synthetic plan corpus that
# reproduces the real one's ugliness: the legacy `## QA verdict` heading with a
# retired `build/lint/test` dimension, ledger lines whose field set differs
# entry to entry, prose sitting in enum positions, and sub-iteration numbering.
#
# The failure guarded against is a backfill that looks complete: a row invented
# to fill a required field, or a pre-enum entry quietly mapped onto the nearest
# valid value, is indistinguishable from real measurement once it is in the
# stream.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail

# Isolate every `git init` below from the developer's ambient config. A global
# core.hooksPath would run the developer's real hooks inside this throwaway
# repo, writing outside the mktemp sandbox, and commit.gpgsign=true would
# break every fixture commit.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKFILL="$HERE/backfill.py"
REPORT="$HERE/report.py"
EMIT="$HERE/emit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 300)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }

REPO="$(mktemp -d)"; HIVESMITH_HOME="$(mktemp -d)"; export HIVESMITH_HOME
trap 'rm -rf "$REPO" "$HIVESMITH_HOME"' EXIT
LOG="$HIVESMITH_HOME/telemetry/pipeline-events.jsonl"

cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p docs/exec-plans/active docs/exec-plans/completed .changesets
echo "# c" > .changesets/README.md

# A modern plan: current heading, three dimensions, well-formed ledger.
cat > docs/exec-plans/completed/101-modern.md <<'P'
# Modern

- **PR:** #201

## PR convergence ledger

- **2026-03-01 iter 1** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: 66044f33aa; threads_open: 2; action: autofix+push; head_sha: abc1234.
- **2026-03-02 iter 2** — verdict: APPROVE; findings_hash: empty; threads_open: 0; action: stop; head_sha: def5678.

## Gate verdict

- **2026-03-03** — verdict: PASS; checks: 3 dimensions passed / 0 failed / 0 followups; followups: none; one-line: ok.
  - 2026-03-03 dimensions:
    - acceptance — PASS — fine
    - non-goals — PASS
    - doc accuracy — PASS — fine
P

# A legacy plan: the retired heading, the retired dimension, prose in enum
# positions, and a sub-iteration.
cat > docs/exec-plans/completed/102-legacy.md <<'P'
# Legacy

- **PR:** #202

## PR convergence ledger

- **2026-01-05 iter 1** — verdict: REQUEST_CHANGES (Copilot thread on a duplicate heading); mergeable: MERGEABLE; findings_hash: <unrecorded — worker returned summary without envelope>; threads_open: 0; action: autofix+push; head_sha: 287257e.
- **2026-01-05 iter 1.5** — out-of-loop human fix, no envelope
- **2026-01-06 iter 2** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: (empty); threads_open: 0; action: fixed 3 findings + push; head_sha: 999aaaa.

## QA verdict

- **2026-01-07** — verdict: PASS; checks: 5 passed / 0 failed / 0 followups; followups: none; one-line: legacy.
  - 2026-01-07 dimensions:
    - build/lint/test — PASS — shellcheck ok
    - regression — PASS — nothing regressed
    - acceptance — PASS — ok
    - non-goals — PASS
    - doc accuracy — PASS — ok
P
git add -A && git commit -qm "plans"

out="$(python3 "$BACKFILL" . --emit --dry-run --tool "$EMIT" 2>&1)"

check test_modern_gate_verdict_backfilled   '"event": "gate_verdict"' "$out"
check test_legacy_qa_verdict_heading_parsed '"feature": "102"'        "$out"
check test_retired_dimension_preserved      '"legacy_dimension": "build/lint/test' "$out"
# Legacy entries carry BOTH retired dimensions; keeping only the first loses data.
check test_all_retired_dimensions_kept      'build/lint/test,regression' "$out"
check test_ledger_backfilled                '"event": "review_iteration"' "$out"
check test_pr_recovered_from_plan_header    '"pr": 201'               "$out"
check test_every_row_is_marked_backfilled   '"backfilled": true'      "$out"
check test_backfill_source_carries_line     '102-legacy.md:'          "$out"

# Prose in an enum position must be dropped, never coerced to the nearest value.
nocheck test_prose_action_not_mapped_to_enum '"action": "autofix+push", "head_sha": "999aaaa"' "$out"
check test_prose_entry_names_failing_field  "action='fixed 3 findings + push'" "$out"
check test_skips_are_reported               'pre-enum ledger entries not backfilled' "$out"

# `iter 1.5` must not be recorded as iteration 1 — that would collide with the
# real iteration 1 five lines above it.
if [ "$(printf '%s' "$out" | grep -c '"feature": "102".*"iter": 1,')" -le 1 ]; then
  ok test_sub_iteration_does_not_collide
else
  bad test_sub_iteration_does_not_collide "iter 1.5 was recorded as iter 1"
fi

# No duration is recoverable from dated markdown; inventing one is the failure.
nocheck test_no_duration_is_invented        '"duration_s"' "$out"
nocheck test_no_seconds_is_invented         '"seconds_to_approval"' "$out"

# Dry run must not write.
if [ ! -f "$LOG" ]; then ok test_dry_run_writes_nothing
else bad test_dry_run_writes_nothing "log created during --dry-run"; fi

python3 "$BACKFILL" . --emit --tool "$EMIT" >/dev/null 2>&1
if [ -f "$LOG" ] && [ "$(wc -l < "$LOG" | tr -d ' ')" -gt 0 ]; then
  ok test_emit_writes_the_stream
else
  bad test_emit_writes_the_stream "no events written"
fi
if python3 -c 'import json,sys
for ln in open(sys.argv[1]): json.loads(ln)' "$LOG" 2>/dev/null; then
  ok test_written_stream_is_valid_jsonl
else
  bad test_written_stream_is_valid_jsonl "a written line does not parse"
fi

# Re-running --emit after adding a plan is the natural operation, so it must be
# idempotent. An earlier version of this suite asserted the row count DOUBLED,
# which encoded the bug as intent: every backfilled statistic downstream would
# silently double on a rerun and the test would have gone on passing.
n1="$(wc -l < "$LOG" | tr -d ' ')"
python3 "$BACKFILL" . --emit --tool "$EMIT" >/dev/null 2>&1
rerun_rc=$?
n2="$(wc -l < "$LOG" | tr -d ' ')"
if [ $rerun_rc -ne 0 ]; then
  bad test_backfill_rerun_exits_clean "second run exited $rerun_rc"
else
  ok test_backfill_rerun_exits_clean
fi
if [ "$n2" -ne "$n1" ]; then
  bad test_backfill_is_idempotent "rerun appended $((n2 - n1)) duplicate rows"
else
  ok test_backfill_is_idempotent
fi

out="$(python3 "$BACKFILL" . --emit --tool "$EMIT" 2>&1)"
check test_backfill_reports_already_present "already_present=$n1" "$out"

# --force is the documented escape hatch, and must still duplicate.
python3 "$BACKFILL" . --emit --force --tool "$EMIT" >/dev/null 2>&1
n3="$(wc -l < "$LOG" | tr -d ' ')"
if [ "$n3" -eq $((2 * n1)) ]; then
  ok test_force_re_emits
else
  bad test_force_re_emits "wanted $((2 * n1)) lines after --force, got $n3"
fi

out="$(python3 "$BACKFILL" . 2>&1)"; rc=$?
if [ $rc -ne 0 ]; then ok test_requires_emit_flag
else bad test_requires_emit_flag "ran without --emit"; fi

# ---- report.py ------------------------------------------------------------
out="$(python3 "$REPORT" --repo . --events "$LOG" 2>&1)"
check test_report_runs                      "RESULT: PASS"            "$out"
check test_report_counts_backfilled_apart   "backfilled="             "$out"
check test_report_includes_regressions      "REGRESSIONS — declared"  "$out"
check test_report_trend_carries_caveat      "directional only"        "$out"

# The disclaimer must travel with the number, in the same block.
so_out="$("$EMIT" --event second_opinion --field feature=101 --field verdict=revise \
  --field confidence=8 --field must_fix_count=4 --field applied_count=3 \
  --field round=1 --field duration_s=90 >/dev/null 2>&1; \
  python3 "$REPORT" --repo . --events "$LOG" 2>&1)"
check test_second_opinion_block_appears     "SECOND OPINION"          "$so_out"
check test_second_opinion_disclaimer_inline "PREVENTED anything"      "$so_out"
check test_second_opinion_reports_yield     "must_fix 4 raised, 3 applied" "$so_out"

# ---- report.py stage/stall attribution ------------------------------------
# The bug this guards: attributing a stall by matching the stage name against
# the retry slug counted a PLAN stall ("plan-revise-rerun") under REVIEW too,
# because REVIEW's first four letters are a substring of it.
ATTR="$HIVESMITH_HOME/attr.jsonl"
: > "$ATTR"
for st in PLAN IMPLEMENT REVIEW GATE; do
  HIVESMITH_HOME="$HIVESMITH_HOME" "$EMIT" --event stage_transition \
    --field feature=101 --field from=PLAN --field "to=$st" --dry-run >> "$ATTR" 2>/dev/null
done
HIVESMITH_HOME="$HIVESMITH_HOME" "$EMIT" --event stall --field feature=101 \
  --field stage=PLAN --field retry=plan-revise-rerun --dry-run >> "$ATTR" 2>/dev/null

attr_out="$(python3 "$REPORT" --repo . --events "$ATTR" 2>&1)"
if printf '%s' "$attr_out" | grep -qE '^ PLAN +[0-9]+ +1'; then
  ok test_stall_counted_under_its_own_stage
else
  bad test_stall_counted_under_its_own_stage "PLAN row missing its stall: $(printf '%s' "$attr_out" | tr '\n' '|' | tail -c 200)"
fi
if printf '%s' "$attr_out" | grep -qE '^ REVIEW +[0-9]+ +[0-9]'; then
  bad test_stall_not_double_counted_under_review "a PLAN stall was also counted under REVIEW"
else
  ok test_stall_not_double_counted_under_review
fi
check test_stall_retry_slug_is_listed "stall: plan-revise-rerun" "$attr_out"

# regressions.py crashing must not be swallowed into a PASS.
BROKEN="$(mktemp -d)"
cd "$BROKEN" || exit 1
out="$(python3 "$REPORT" --repo . --events "$ATTR" 2>&1)"; rc=$?
cd "$REPO" || exit 1
if printf '%s' "$out" | grep -q "RESULT: PASS" && [ $rc -eq 0 ]; then
  bad test_regressions_failure_is_not_swallowed "reported PASS with a non-repo target"
else
  ok test_regressions_failure_is_not_swallowed
fi
rm -rf "$BROKEN"

# A missing local stream must degrade, not crash.
out="$(python3 "$REPORT" --repo . --events "$HIVESMITH_HOME/nope.jsonl" 2>&1)"; rc=$?
if [ $rc -eq 0 ] && printf '%s' "$out" | grep -q "no events at"; then
  ok test_missing_event_stream_degrades
else
  bad test_missing_event_stream_degrades "exit $rc: $out"
fi

echo
if [ "$FAIL" -gt 0 ]; then
  echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
  exit 1
fi
echo "RESULT: PASS checks=$PASS"
