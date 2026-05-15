#!/usr/bin/env bash
# Start the hs-plan-html feedback server for a given plan HTML.
#
# Usage: start.sh <plan.html>
#
# Behavior:
#   - Finds a free TCP port starting at PLAN_FEEDBACK_PORT (default 8765).
#   - Generates a random URL token (PLAN_TOKEN) — clients must send ?t=<token>.
#   - Launches server.py in the background, redirecting output to <plan>.server.log.
#   - Writes <plan>.server.pid and <plan>.server.port for stop.sh to read.
#   - Opens http://127.0.0.1:<port>/?t=<token> via `open` (macOS) / `xdg-open` (Linux),
#     unless PLAN_HTML_AUTO_OPEN=false.
#
# Env knobs:
#   PLAN_FEEDBACK_PORT   starting port (default 8765); auto-bumps on collision.
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

start_port="${PLAN_FEEDBACK_PORT:-8765}"
port="$start_port"
while lsof -ti :"$port" >/dev/null 2>&1; do
    port=$((port + 1))
    if [[ "$port" -gt $((start_port + 100)) ]]; then
        echo "could not find a free port within 100 of $start_port" >&2
        exit 1
    fi
done

# Random URL token (32 hex chars).
token=$(python3 -c 'import secrets; print(secrets.token_hex(16))')

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PLAN_HTML_PATH="$plan_html_abs" \
PLAN_FEEDBACK_PORT="$port" \
PLAN_TOKEN="$token" \
    nohup python3 "$script_dir/server.py" >"$log_file" 2>&1 &
server_pid=$!

echo "$server_pid" >"$pid_file"
echo "$port" >"$port_file"
echo "$token" >"$token_file"

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
