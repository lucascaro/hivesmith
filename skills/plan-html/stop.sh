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

# Verify the PID is actually OUR server before signalling it. A sidecar can
# outlive its process (a crash, a reboot, a `kill -9` from elsewhere) and PIDs
# are recycled, so an unverified kill can hit an unrelated process. This used
# to require a deliberate `stop.sh` call; start.sh's predecessor reap and
# wait.sh --stop now fire it automatically on every plan render, which is what
# makes the check worth having.
if [[ ! "$pid" =~ ^[0-9]+$ ]]; then
    echo "hs-plan-html: pid file does not contain a pid; refusing to signal" >&2
    rm -f "$pid_file" "$port_file" "$token_file"
    exit 0
fi
if kill -0 "$pid" 2>/dev/null && ! ps -o command= -p "$pid" 2>/dev/null | grep -q "server.py"; then
    echo "hs-plan-html: pid=$pid is not a plan-html server (recycled pid); not killing it"
    rm -f "$pid_file" "$port_file" "$token_file"
    exit 0
fi

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
