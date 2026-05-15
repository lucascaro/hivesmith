#!/usr/bin/env bash
# Stop the hs-plan-html feedback server for a given plan HTML.
#
# Usage: stop.sh <plan.html>
#
# Reads <plan>.server.pid, kills the process, removes pid/port/token files.
# Leaves the .server.log file in place for inspection.
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <plan.html>" >&2
    exit 2
fi

plan_html="$1"
plan_base="${plan_html%.html}"
pid_file="${plan_base}.server.pid"
port_file="${plan_base}.server.port"
token_file="${plan_base}.server.token"

if [[ ! -f "$pid_file" ]]; then
    echo "no pid file at $pid_file; nothing to stop"
    exit 0
fi

pid=$(cat "$pid_file")
if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    # Give it a moment to exit cleanly.
    for _ in 1 2 3 4 5; do
        kill -0 "$pid" 2>/dev/null || break
        sleep 0.2
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
    fi
    echo "hs-plan-html: killed pid=$pid"
else
    echo "hs-plan-html: pid=$pid not running"
fi

rm -f "$pid_file" "$port_file" "$token_file"
