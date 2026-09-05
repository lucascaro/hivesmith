#!/usr/bin/env bash
# Tests for wait.sh — the blocking plan-approval gate — and for start.sh's
# stale-sidecar and predecessor-reaping behavior.
#
# The bug these guard against is silent: the operator clicks Approve, the page
# says "✓ Approved", and the loop never advances because nothing was listening.
# Every check here is one of the ways that can happen.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAIT="$HERE/wait.sh"
START="$HERE/start.sh"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
eq()  { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "wanted exit $2, got $3"; fi; }

# `timeout` is GNU coreutils and is absent from stock macOS, where AGENTS.md
# still tells developers to run this suite. The checks that need a time bound
# are exactly the ones that catch an infinite argument-parsing loop, so they
# are not skippable. perl ships on both platforms and preserves the real exit
# code, unlike a background-and-kill shim (which reports the watchdog's status,
# not the command's).
if command -v timeout >/dev/null 2>&1; then
  tmo() { timeout "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  tmo() { gtimeout "$@"; }
else
  tmo() {
    local secs="$1"; shift
    # `exec` keeps the child's own exit status; SIGALRM surfaces as 142, which
    # is remapped to timeout's own 124 so callers need not care which ran.
    ( exec 2>/dev/null; perl -e 'alarm shift; exec @ARGV' "$secs" "$@" )
    local rc=$?
    [ "$rc" -eq 142 ] && return 124
    return "$rc"
  }
fi

WORK="$(mktemp -d)"
cleanup() {
  for p in "$WORK"/*.server.pid; do
    [[ -f "$p" ]] && kill "$(cat "$p")" 2>/dev/null
  done
  rm -rf "$WORK"
}
trap cleanup EXIT

# A minimal plan page. render_plan.py is not needed — the server only serves
# bytes, and nothing under test parses the HTML.
mkplan() {
  local p="$WORK/$1.html"
  printf '<div class="wrap"><h1>%s</h1></div>\n' "$1" > "$p"
  printf '%s' "$p"
}
serve() { PLAN_HTML_AUTO_OPEN=false "$START" "$1" >/dev/null 2>&1; }
base()  { printf '%s' "${1%.html}"; }

# ---------------------------------------------------------------- start.sh

plan="$(mkplan stale)"
echo '{"approved_at":"1999-01-01T00:00:00"}' > "$(base "$plan").approved.json"
echo '{"s1":"old note"}' > "$(base "$plan").feedback.json"
serve "$plan"
if [[ -f "$(base "$plan").approved.json" ]]; then
  bad test_stale_approval_is_cleared_by_start "approved.json survived start.sh"
else
  ok test_stale_approval_is_cleared_by_start
fi
if [[ -f "$(base "$plan").feedback.json" ]]; then
  bad test_stale_feedback_is_cleared_by_start "feedback.json survived start.sh"
else
  ok test_stale_feedback_is_cleared_by_start
fi
# The whole point of clearing it: wait.sh must not instantly approve.
"$WAIT" "$plan" --timeout 2 >/dev/null 2>&1; eq test_stale_approval_does_not_instant_approve 11 $?

first_pid="$(cat "$(base "$plan").server.pid")"
serve "$plan"
second_pid="$(cat "$(base "$plan").server.pid")"
sleep 1
if kill -0 "$first_pid" 2>/dev/null; then
  bad test_predecessor_server_is_reaped "pid $first_pid still alive after restart"
else
  ok test_predecessor_server_is_reaped
fi
if [[ "$first_pid" != "$second_pid" ]] && kill -0 "$second_pid" 2>/dev/null; then
  ok test_successor_server_is_running
else
  bad test_successor_server_is_running "second pid $second_pid not alive"
fi
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

# ---------------------------------------------------------------- wait.sh

plan="$(mkplan approve)"; serve "$plan"
( sleep 2; echo '{"approved_at":"now"}' > "$(base "$plan").approved.json" ) &
"$WAIT" "$plan" --timeout 20 >/dev/null 2>&1; eq test_returns_0_on_approval 0 $?
wait $! 2>/dev/null
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

plan="$(mkplan quiesced)"; serve "$plan"
( sleep 1; echo '{"s1":"please rename this"}' > "$(base "$plan").feedback.json" ) &
"$WAIT" "$plan" --timeout 20 --quiet-for 3 >/dev/null 2>&1; eq test_returns_10_on_quiesced_feedback 10 $?
wait $! 2>/dev/null
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

# The check that fails if the debounce is dropped: the page autosaves every
# ~1.2s while someone types, so a naive "file changed -> return" yanks the plan
# away mid-sentence.
plan="$(mkplan typing)"; serve "$plan"
( for i in 1 2 3 4 5 6; do echo "{\"s1\":\"still typing $i\"}" > "$(base "$plan").feedback.json"; sleep 1; done ) &
typer=$!
"$WAIT" "$plan" --timeout 6 --quiet-for 4 >/dev/null 2>&1; eq test_does_not_return_10_while_still_typing 11 $?
wait $typer 2>/dev/null
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

# Content comparison, not mtime: typing something and reverting it is not feedback.
plan="$(mkplan revert)"; serve "$plan"
echo '{"s1":"original"}' > "$(base "$plan").feedback.json"
( sleep 1; touch "$(base "$plan").feedback.json"; echo '{"s1":"original"}' > "$(base "$plan").feedback.json" ) &
"$WAIT" "$plan" --timeout 4 --quiet-for 1 >/dev/null 2>&1; eq test_identical_rewrite_is_not_feedback 11 $?
wait $! 2>/dev/null
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

plan="$(mkplan timeout)"; serve "$plan"
"$WAIT" "$plan" --timeout 2 >/dev/null 2>&1; eq test_returns_11_on_timeout 11 $?
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

plan="$(mkplan dead)"; serve "$plan"
( sleep 2; kill "$(cat "$(base "$plan").server.pid")" 2>/dev/null ) &
"$WAIT" "$plan" --timeout 20 >/dev/null 2>&1; eq test_returns_3_when_server_dies 3 $?
wait $! 2>/dev/null

# template.html saves feedback and only then POSTs /approve, so both files can
# be present at once. Approval must win.
plan="$(mkplan both)"; serve "$plan"
echo '{"s1":"a note"}' > "$(base "$plan").feedback.json"
echo '{"approved_at":"now"}' > "$(base "$plan").approved.json"
"$WAIT" "$plan" --timeout 5 --quiet-for 0 >/dev/null 2>&1; eq test_approval_beats_simultaneous_feedback 0 $?
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

plan="$(mkplan stopflag)"; serve "$plan"
pid="$(cat "$(base "$plan").server.pid")"
echo '{"approved_at":"now"}' > "$(base "$plan").approved.json"
"$WAIT" "$plan" --timeout 5 --stop >/dev/null 2>&1; rc=$?
sleep 1
if [[ "$rc" -eq 0 ]] && ! kill -0 "$pid" 2>/dev/null && [[ ! -f "$(base "$plan").server.pid" ]]; then
  ok test_stop_flag_reaps_on_approval
else
  bad test_stop_flag_reaps_on_approval "rc=$rc pid_alive=$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)"
fi

# --stop must NOT reap on 10 or 11 — the server is still needed for the revise
# round and for the caller's next wait.
plan="$(mkplan nostop)"; serve "$plan"
pid="$(cat "$(base "$plan").server.pid")"
"$WAIT" "$plan" --timeout 2 --stop >/dev/null 2>&1
if kill -0 "$pid" 2>/dev/null; then ok test_stop_flag_keeps_server_on_timeout
else bad test_stop_flag_keeps_server_on_timeout "server reaped on exit 11"; fi
"$HERE/stop.sh" "$plan" >/dev/null 2>&1

"$WAIT" >/dev/null 2>&1;                          eq test_no_args_is_usage_error 2 $?
"$WAIT" "$WORK/nope.html" >/dev/null 2>&1;        eq test_missing_plan_is_usage_error 2 $?
"$WAIT" "$plan" --timeout abc >/dev/null 2>&1;    eq test_non_numeric_timeout_is_usage_error 2 $?
"$WAIT" "$plan" --quiet-for abc >/dev/null 2>&1;  eq test_non_numeric_quiet_for_is_usage_error 2 $?
"$WAIT" "$plan" --bogus >/dev/null 2>&1;          eq test_unknown_flag_is_usage_error 2 $?

# A flag with NO value at all, which is a different branch from a flag with a
# WRONG value: `shift 2` on a one-argument tail shifts nothing, so an
# unguarded loop re-reads the same flag forever. `timeout` bounds the check so
# a regression fails the suite instead of hanging CI.
tmo 5 "$WAIT" "$plan" --timeout >/dev/null 2>&1
eq test_timeout_without_value_is_usage_error 2 $?
tmo 5 "$WAIT" "$plan" --quiet-for >/dev/null 2>&1
eq test_quiet_for_without_value_is_usage_error 2 $?

# bash 3.2 is the floor (stock macOS). These constructs are not available.
if grep -nE 'wait -n|mapfile|readarray|\$\{[a-zA-Z_]+,,\}|declare -A' "$WAIT" >/dev/null; then
  bad test_bash32_compatible "wait.sh uses a bash 4+ construct"
else
  ok test_bash32_compatible
fi

echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
  exit 1
fi
echo "RESULT: PASS checks=$PASS"
