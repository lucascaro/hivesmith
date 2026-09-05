#!/usr/bin/env bash
# Block until the operator approves the plan, leaves feedback, or the wait
# times out.
#
# Usage: wait.sh <plan.html> [--timeout N] [--quiet-for N] [--stop]
#
# Why this exists: start.sh is deliberately non-blocking, and "poll the
# approval file" is not something an agent can do between turns — it renders,
# serves, prints a URL, and its turn ends. The operator clicks Approve, the
# server writes <plan>.approved.json, and nobody is listening. Meanwhile the
# page disables the button and says "Approved", so the one signal is spent.
# This script is the missing wait: a foreground call the agent blocks on.
#
# It is bounded on purpose. A harness Bash call has its own timeout (Claude
# Code: 120s default, 600s max), so this returns a distinct "nothing happened
# yet" code and the calling skill loops it, printing progress between waits.
#
# Exit codes:
#   0   approved           — <plan>.approved.json appeared
#   10  feedback available — <plan>.feedback.json changed and has been stable
#                            for --quiet-for seconds
#   11  timeout            — no signal yet; caller should loop
#   3   server gone        — the server pid died; caller must restart or fall back
#   2   usage error
#
# Env knobs: none. Everything is a flag so the call site is self-documenting.
set -uo pipefail

timeout=90
quiet_for=8
do_stop=0
plan_html=""

# A value-taking flag MUST be checked before `shift 2`. Without `set -e`, a
# `shift 2` with one argument left fails silently and shifts NOTHING, so the
# loop re-processes the same flag forever. That turns the one call the plan
# gate blocks on into a busy loop that eats the whole harness Bash timeout —
# the exact silent stall wait.sh exists to prevent. `${2:-}` hides it.
need_value() {
    if [[ $2 -lt 2 ]]; then
        echo "wait.sh: $1 requires a value" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --timeout)   need_value "$1" $#; timeout="$2"; shift 2 ;;
        --quiet-for) need_value "$1" $#; quiet_for="$2"; shift 2 ;;
        --stop)      do_stop=1; shift ;;
        -h|--help)   sed -n '2,25p' "${BASH_SOURCE[0]}"; exit 0 ;;
        -*)          echo "wait.sh: unknown flag: $1" >&2; exit 2 ;;
        *)           if [[ -n "$plan_html" ]]; then
                         echo "wait.sh: unexpected argument: $1" >&2; exit 2
                     fi
                     plan_html="$1"; shift ;;
    esac
done

if [[ -z "$plan_html" ]]; then
    echo "usage: $0 <plan.html> [--timeout N] [--quiet-for N] [--stop]" >&2
    exit 2
fi
if [[ ! -f "$plan_html" ]]; then
    echo "wait.sh: plan file not found: $plan_html" >&2
    exit 2
fi
case "$timeout" in ''|*[!0-9]*) echo "wait.sh: --timeout must be a non-negative integer" >&2; exit 2 ;; esac
case "$quiet_for" in ''|*[!0-9]*) echo "wait.sh: --quiet-for must be a non-negative integer" >&2; exit 2 ;; esac

plan_html_abs="$(cd "$(dirname "$plan_html")" && pwd)/$(basename "$plan_html")"
plan_base="${plan_html_abs%.html}"
pid_file="${plan_base}.server.pid"
approved_file="${plan_base}.approved.json"
feedback_file="${plan_base}.feedback.json"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Snapshot the feedback file by CONTENT, not mtime. `stat` flags differ between
# BSD and GNU (`stat -f` means --file-system on coreutils and silently succeeds
# with garbage), and this repo has been burned by exactly that before. `cmp` is
# POSIX and correct everywhere. It also gets a free correctness win: an operator
# who types something and then reverts it reads as "no change", which is right.
snap="$(mktemp "${TMPDIR:-/tmp}/planwait.XXXXXX")"
qsnap="$(mktemp "${TMPDIR:-/tmp}/planwaitq.XXXXXX")"
trap 'rm -f "$snap" "$qsnap"' EXIT

if [[ -f "$feedback_file" ]]; then
    cp "$feedback_file" "$snap"
else
    : >"$snap"
fi
have_qsnap=0
quiet_since=0

finish() {
    # --stop reaps the server on the terminal outcomes only. Code 10 keeps it
    # alive for the revise round; code 11 keeps it alive for the caller's next
    # wait. Stopping on either would be a bug that looks like a cleanup.
    if [[ "$do_stop" -eq 1 && ( "$1" -eq 0 || "$1" -eq 3 ) ]]; then
        "$script_dir/stop.sh" "$plan_html_abs" >/dev/null 2>&1 || true
    fi
    exit "$1"
}

server_alive() {
    local pid
    [[ -f "$pid_file" ]] || return 1
    pid="$(cat "$pid_file" 2>/dev/null)"
    [[ -n "$pid" ]] || return 1
    kill -0 "$pid" 2>/dev/null
}

deadline=$(( $(date +%s) + timeout ))

while :; do
    # Approval wins outright, and is checked first: template.html saves the
    # feedback payload and only then POSTs /approve, so approved.json is always
    # the later write. Checking feedback first would report a revise round for
    # an operator who actually approved.
    if [[ -f "$approved_file" ]]; then
        echo "wait.sh: approved"
        finish 0
    fi

    if ! server_alive; then
        echo "wait.sh: server is gone (pid file: $pid_file)" >&2
        finish 3
    fi

    if [[ -f "$feedback_file" ]] && ! cmp -s "$feedback_file" "$snap"; then
        # The page autosaves on a 1.2s debounce, so this file mutates on every
        # keystroke burst. Returning as soon as it differs would yank the plan
        # out from under someone mid-sentence. Require it to also hold still.
        if [[ "$have_qsnap" -eq 1 ]] && cmp -s "$feedback_file" "$qsnap"; then
            if (( $(date +%s) - quiet_since >= quiet_for )); then
                echo "wait.sh: feedback available"
                finish 10
            fi
        else
            cp "$feedback_file" "$qsnap"
            have_qsnap=1
            quiet_since=$(date +%s)
        fi
    fi

    if (( $(date +%s) >= deadline )); then
        echo "wait.sh: timeout after ${timeout}s — no approval or settled feedback yet"
        finish 11
    fi
    sleep 1
done
