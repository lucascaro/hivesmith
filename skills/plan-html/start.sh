#!/usr/bin/env bash
# Start the hs-plan-html feedback server for a given plan HTML.
#
# Usage: start.sh <plan.html>
#
# Behavior:
#   - Generates a random URL token (PLAN_TOKEN) — clients must send ?t=<token>.
#   - Launches server.py in the background. The server itself binds (port=0
#     by default; the OS picks any free port) and writes the actual port to
#     <plan>.server.port atomically *before* serve_forever(). start.sh polls
#     that file (with a timeout) and prints/opens the URL once it appears.
#     This eliminates the lsof-probe-then-bind TOCTOU race that the previous
#     implementation had.
#   - Writes <plan>.server.{pid,token,log}; the port file is written by server.py.
#   - Opens http://127.0.0.1:<port>/?t=<token> via `open` (macOS) / `xdg-open` (Linux),
#     unless PLAN_HTML_AUTO_OPEN=false.
#
# Env knobs:
#   PLAN_FEEDBACK_PORT   preferred port (default 0 = OS picks any free port).
#                        Set to e.g. 8765 to request a specific port; the server
#                        falls back to OS-picked if it's taken.
#   PLAN_HTML_AUTO_OPEN  set to "false" to skip the open call (headless / SSH).
set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "usage: $0 <plan.html>" >&2
    exit 2
fi

plan_html="$1"
if [[ ! -f "$plan_html" ]]; then
    echo "plan file not found: $plan_html" >&2
    exit 1
fi

# Absolute path for the server (it must not depend on cwd).
plan_html_abs="$(cd "$(dirname "$plan_html")" && pwd)/$(basename "$plan_html")"
plan_base="${plan_html_abs%.html}"
pid_file="${plan_base}.server.pid"
port_file="${plan_base}.server.port"
log_file="${plan_base}.server.log"
token_file="${plan_base}.server.token"
approved_file="${plan_base}.approved.json"
feedback_file="${plan_base}.feedback.json"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Reap a predecessor server for THIS plan before overwriting its pid sidecar.
# Orphans accumulate otherwise: stop.sh can only kill a pid it can still read,
# and the write below would lose it. Fixing it here rather than asking the
# caller to always call stop.sh is deliberate — you cannot guarantee a cleanup
# step runs on every exit path, but you can guarantee the next start reaps.
if [[ -f "$pid_file" ]]; then
    "$script_dir/stop.sh" "$plan_html_abs" >/dev/null 2>&1 || true
fi

# Clear stale sidecars from a previous run on this same plan path. The port
# file matters because start.sh polls for a freshly-written port and must not
# pick up a corpse. The approval file matters more: leaving it would make
# wait.sh return "approved" instantly, before the operator has even seen the
# page. Feedback is cleared with it — start.sh runs once per plan (the revise
# loop re-renders to the same path without restarting, and server.py re-reads
# the HTML on every GET), so no in-round note is ever lost here.
rm -f "$port_file" "$approved_file" "$feedback_file"

# Random URL token (32 hex chars).
token=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

# Preferred port; server.py treats 0 as "OS picks any free port" and falls
# back to OS-picked if the requested port is taken. No TOCTOU window.
preferred_port="${PLAN_FEEDBACK_PORT:-0}"

PLAN_HTML_PATH="$plan_html_abs" \
PLAN_FEEDBACK_PORT="$preferred_port" \
PLAN_PORT_FILE="$port_file" \
PLAN_TOKEN="$token" \
    nohup python3 "$script_dir/server.py" >"$log_file" 2>&1 &
server_pid=$!

echo "$server_pid" >"$pid_file"
echo "$token" >"$token_file"

# Wait for the server to bind and write the port file (~5s timeout).
for _ in $(seq 1 50); do
    if [[ -s "$port_file" ]]; then
        break
    fi
    if ! kill -0 "$server_pid" 2>/dev/null; then
        echo "server.py exited before binding; see $log_file" >&2
        rm -f "$pid_file" "$token_file"
        exit 1
    fi
    sleep 0.1
done

if [[ ! -s "$port_file" ]]; then
    echo "timed out waiting for server.py to bind; see $log_file" >&2
    kill "$server_pid" 2>/dev/null || true
    rm -f "$pid_file" "$token_file"
    exit 1
fi

port=$(cat "$port_file")
url="http://127.0.0.1:$port/?t=$token"
echo "hs-plan-html: server pid=$server_pid port=$port log=$log_file"
echo "hs-plan-html: open $url"

if [[ "${PLAN_HTML_AUTO_OPEN:-true}" != "false" ]]; then
    if command -v open >/dev/null 2>&1; then
        open "$url" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$url" >/dev/null 2>&1 || true
    fi
fi
