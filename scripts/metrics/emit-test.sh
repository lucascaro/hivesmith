#!/usr/bin/env bash
# Tests for emit.sh (hs-metric).
#
# The failure mode being guarded against is a metric stream you cannot trust:
# an event that was silently dropped, a field that drifted back into prose, or
# two concurrent worktrees interleaving halves of a line. A rejection that
# still appends is the worst of all, so every negative case also asserts the
# log did not grow.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/emit.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
eq()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "wanted $2, got $3"; fi; }

HIVESMITH_HOME="$(mktemp -d)"; export HIVESMITH_HOME
trap 'rm -rf "$HIVESMITH_HOME"' EXIT
LOG="$HIVESMITH_HOME/telemetry/pipeline-events.jsonl"
lines() { [[ -f "$LOG" ]] && wc -l < "$LOG" | tr -d ' ' || echo 0; }

VALID=(--event second_opinion --field feature=069 --field verdict=revise
       --field confidence=8 --field must_fix_count=5 --field applied_count=5
       --field round=1 --field duration_s=94)

"$TOOL" "${VALID[@]}" >/dev/null 2>&1; eq test_valid_event_exits_0 0 $?
eq test_valid_event_appends_one_line 1 "$(lines)"
if python3 -c 'import json,sys; json.loads(open(sys.argv[1]).readline())' "$LOG" 2>/dev/null; then
  ok test_line_is_valid_json
else
  bad test_line_is_valid_json "first line does not parse"
fi
if python3 -c '
import json,sys
r = json.loads(open(sys.argv[1]).readline())
assert r["event"] == "second_opinion", r
assert r["confidence"] == 8 and isinstance(r["confidence"], int), r
assert r["ts"].endswith("Z"), r
' "$LOG" 2>/dev/null; then
  ok test_ints_are_typed_not_strings
else
  bad test_ints_are_typed_not_strings "confidence not an int, or ts not UTC"
fi

# --- rejections. Each asserts exit 64 AND that the log did not grow. --------
before="$(lines)"
reject() { # name  expected_rc  args...
  local name="$1" want="$2"; shift 2
  "$TOOL" "$@" >/dev/null 2>&1; local rc=$?
  if [[ "$rc" != "$want" ]]; then bad "$name" "wanted exit $want, got $rc"; return; fi
  if [[ "$(lines)" != "$before" ]]; then bad "$name" "log grew on a rejected event"; return; fi
  ok "$name"
}

reject test_unknown_event_fails_64 64 --event second-opinion --field feature=1
reject test_missing_required_field_fails_64 64 --event second_opinion --field feature=069 --field verdict=revise
reject test_unknown_field_fails_64 64 --event stall --field feature=1 --field retry=gate-fail-rerun --field stage=GATE --field rationale=prose
reject test_non_integer_int_fails_64 64 --event second_opinion --field feature=1 --field verdict=approve --field confidence=high --field must_fix_count=1 --field applied_count=1 --field round=1 --field duration_s=1
reject test_bad_enum_fails_64 64 --event second_opinion --field feature=1 --field verdict=ok --field confidence=8 --field must_fix_count=1 --field applied_count=1 --field round=1 --field duration_s=1
reject test_out_of_range_confidence_fails_64 64 --event second_opinion --field feature=1 --field verdict=approve --field confidence=42 --field must_fix_count=1 --field applied_count=1 --field round=1 --field duration_s=1
reject test_malformed_field_fails_64 64 --event feature_done --field feature
reject test_duplicate_field_fails_64 64 --event feature_done --field feature=1 --field feature=2
reject test_backfill_source_without_flag_fails_64 64 --event feature_done --field feature=1 --backfill-source docs/x.md:1
reject test_backfilled_without_source_fails_64 64 --event feature_done --field feature=1 --backfilled
reject test_missing_event_is_usage_error 2 --field feature=1
reject test_unknown_argument_is_usage_error 2 --event feature_done --bogus

# A value-taking flag with NO value is a different branch from one with a WRONG
# value: `shift 2` on a one-argument tail shifts nothing, so an unguarded loop
# re-reads the same flag forever (and `--field` grows FIELDS until the process
# dies). `timeout` bounds it so a regression fails the suite instead of hanging
# CI. Reachable in practice: an empty shell variable collapses
# `--field "$X"` into a trailing `--field`.
no_value() { # name  args...
  local name="$1"; shift
  timeout 5 "$TOOL" "$@" >/dev/null 2>&1; local rc=$?
  if [[ "$rc" == 124 ]]; then bad "$name" "hung instead of exiting 2"; return; fi
  if [[ "$rc" != 2 ]]; then bad "$name" "wanted exit 2, got $rc"; return; fi
  if [[ "$(lines)" != "$before" ]]; then bad "$name" "log grew on a rejected event"; return; fi
  ok "$name"
}
no_value test_event_without_value_is_usage_error --event
no_value test_field_without_value_is_usage_error --event feature_done --field
no_value test_backfill_source_without_value_is_usage_error --event feature_done --field feature=1 --backfilled --backfill-source

# The one enum value that carries a space. It is documented in
# skills/review-loop/SKILL.md, so it must actually be emittable — a value that
# only survives when the caller quotes it is a trap the schema should catch.
accept() { # name  args...
  local name="$1"; shift
  local n0; n0="$(lines)"
  "$TOOL" "$@" >/dev/null 2>&1; local rc=$?
  if [[ "$rc" != 0 ]]; then bad "$name" "wanted exit 0, got $rc"; return; fi
  if [[ "$(lines)" == "$n0" ]]; then bad "$name" "accepted but appended nothing"; return; fi
  ok "$name"
}
accept test_action_enum_with_a_space_is_accepted \
  --event review_iteration --field feature=069 --field pr=70 --field iter=1 \
  --field verdict=REQUEST_CHANGES --field findings_count=3 --field threads_open=0 \
  --field 'action=autofix+push (conflict)'
before="$(lines)"

# Each event's verdict enum is distinct — review_iteration must not accept the
# second-opinion vocabulary just because the field has the same name.
reject test_enums_are_per_event 64 --event review_iteration --field feature=1 --field pr=2 --field iter=1 --field verdict=approve --field findings_count=0 --field threads_open=0 --field action=stop

# --- backfill marking -------------------------------------------------------
out="$("$TOOL" --event gate_verdict --field feature=011 --field verdict=PASS \
        --field acceptance=PASS --field non_goals=PASS --field doc_accuracy=PASS \
        --backfilled --backfill-source 'docs/exec-plans/completed/011-x.md:461' --dry-run 2>&1)"
if printf '%s' "$out" | grep -q '"backfilled": true' && printf '%s' "$out" | grep -q '011-x.md:461'; then
  ok test_backfilled_rows_are_marked
else
  bad test_backfilled_rows_are_marked "$out"
fi
eq test_dry_run_writes_nothing "$before" "$(lines)"

# --- isolation --------------------------------------------------------------
if [[ -f "$HIVESMITH_HOME/telemetry/agent-events.jsonl" ]]; then
  bad test_does_not_write_agent_events_jsonl "hs-metric wrote to the hook stream"
else
  ok test_does_not_write_agent_events_jsonl
fi

ALT="$(mktemp -d)"
HIVESMITH_HOME="$ALT" "$TOOL" --event feature_done --field feature=1 >/dev/null 2>&1
if [[ -f "$ALT/telemetry/pipeline-events.jsonl" ]]; then
  ok test_respects_hivesmith_home
else
  bad test_respects_hivesmith_home "no log under the overridden home"
fi
rm -rf "$ALT"

# --- concurrency ------------------------------------------------------------
: > "$LOG"
for i in $(seq 1 20); do
  "$TOOL" --event stage_transition --field "feature=$i" --field from=PLAN --field to=IMPLEMENT >/dev/null 2>&1 &
done
wait
eq test_concurrent_writers_produce_20_lines 20 "$(lines)"
if python3 -c '
import json,sys
for ln in open(sys.argv[1]):
    json.loads(ln)
' "$LOG" 2>/dev/null; then
  ok test_concurrent_lines_are_all_intact
else
  bad test_concurrent_lines_are_all_intact "interleaved write corrupted a line"
fi

echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
  exit 1
fi
echo "RESULT: PASS checks=$PASS"
