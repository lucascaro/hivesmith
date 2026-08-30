#!/usr/bin/env bash
# graphify-refresh.sh — debounced, AST-only graphify refresh for agent edits.
#
# Installed by `/hs-graphify-init` as a Claude Code PostToolUse hook on
# Edit|Write|MultiEdit. Three invariants, in priority order:
#
#   1. Never blocks.       The rebuild is detached; this script returns at once.
#   2. Never fails.        Always exits 0 — a stale graph must not fail an edit.
#   3. Never bootstraps.   No graph.json means the user has not run /graphify
#                          yet, and a tool hook is the wrong place to start a
#                          multi-minute build.
#
# It is also AST-only (`graphify update`), so no automatic path ever spends
# LLM tokens.
#
# Env:
#   HIVESMITH_GRAPHIFY_REFRESH   0 disables entirely (default 1)
#   HIVESMITH_GRAPHIFY_DEBOUNCE  seconds between rebuilds (default 90)
#   GRAPHIFY_OUT                 output dir name (default graphify-out)
#
# Usage: graphify-refresh.sh [project-dir]   (default: $CLAUDE_PROJECT_DIR or .)

set -u

# Every exit below is 0 on purpose; see invariant 2.
[ "${HIVESMITH_GRAPHIFY_REFRESH:-1}" = "1" ] || exit 0

root="${1:-${CLAUDE_PROJECT_DIR:-.}}"
cd "$root" 2>/dev/null || exit 0

out="${GRAPHIFY_OUT:-graphify-out}"

# Invariant 3: only ever refresh a graph that already exists.
[ -f "$out/graph.json" ] || exit 0

stamp="$out/.graphify_refresh_stamp"
debounce="${HIVESMITH_GRAPHIFY_DEBOUNCE:-90}"

# BSD (macOS) and GNU stat disagree on flags, and the probe order matters:
# on GNU coreutils `-f` means --file-system, so `stat -f %m` PRINTS a
# filesystem block to stdout and exits 1 — a BSD-first probe therefore emits
# garbage that the `||` fallback appends its real answer to, and the caller's
# arithmetic then dies under `set -u`. GNU's `-c` is rejected outright by BSD
# stat with no stdout, so probing GNU first is the order that fails cleanly on
# both. The numeric guard is the backstop: anything not a plain integer
# becomes 0, which reads as "old" and simply allows a refresh.
mtime_of() {
    m="$(stat -c %Y "$1" 2>/dev/null)" || m="$(stat -f %m "$1" 2>/dev/null)" || m=0
    case "$m" in
        ''|*[!0-9]*) m=0 ;;
    esac
    printf '%s\n' "$m"
}

# This is a check-then-touch, not a lock: two hooks firing in the same instant
# can both pass. That is deliberate and safe — graphify.watch._rebuild_code
# takes a NON-BLOCKING per-repo flock (watch.py:1327), so the loser exits
# immediately rather than running a second concurrent rebuild. The debounce
# exists to avoid the cost of spawning that process, not to provide mutual
# exclusion, which already lives downstream. Do not add a second lock here.
if [ -f "$stamp" ]; then
    age=$(( $(date +%s) - $(mtime_of "$stamp") ))
    [ "$age" -lt "$debounce" ] && exit 0
fi

command -v graphify >/dev/null 2>&1 || exit 0

# Claim the window before launching so a burst of edits collapses into one
# rebuild even if the rebuild itself is slow to start.
touch "$stamp" 2>/dev/null || exit 0

# Truncate a log that has grown past the cap before appending. A hook running
# after every edit burst would otherwise grow this file without bound, and
# nothing ever reads more than its tail.
log="$out/.refresh.log"
cap="${HIVESMITH_GRAPHIFY_LOG_CAP:-1048576}"
if [ -f "$log" ]; then
    size=$(wc -c <"$log" 2>/dev/null || echo 0)
    [ "$size" -gt "$cap" ] && : >"$log"
fi

# --no-cluster: clustering is for human-facing reports, not for keeping the
# structural map current, and it is the slow half of the rebuild.
# Subshell + background rather than `nohup`: Git for Windows' bundled shell
# ships no nohup, and the hook must not depend on it (graphify #1161).
( graphify update . --no-cluster >>"$log" 2>&1 & ) &

exit 0
