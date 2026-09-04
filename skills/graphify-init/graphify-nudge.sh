#!/usr/bin/env bash
# graphify-nudge.sh — PreToolUse wrapper around `graphify hook-guard`.
#
# graphify's own nudge has three problems this wrapper fixes without forking its
# gating logic:
#
#   1. Tone. It injects "MANDATORY: ... You MUST run graphify query ..." into the
#      tool-result stream. An imperative arriving through a tool-result channel is
#      the shape agents are instructed to distrust, so security-instructed
#      subagents refuse it — the nudge is anti-effective on exactly the agents
#      that follow their instructions. We re-emit the same information as advice.
#   2. Repetition. Upstream has no per-session throttle, so the identical line is
#      re-emitted on every matching tool call. We emit once per (session, kind).
#   3. Self-defeat. `graphify query` records orientation in
#      cache/last_query_stamp, but only upstream's strict path reads it, so an
#      agent that complies is nudged again seconds later. We honour the stamp.
#
# We delegate everything about WHETHER a call is in scope (in-project, source
# extension, indexed, stale) and everything about BLOCKING (strict mode) to
# graphify. We own only how often, in what tone, and whether graphify needs to
# run at all.
#
# Invariants:
#   1. Never blocks a tool call. Every exit is 0 and every failure is silent.
#   2. Never matches on graphify's nudge TEXT. Upstream rewrites those strings
#      freely while the payload shapes stay stable; we branch on the presence of
#      the `permissionDecision` key, which is Claude Code's contract, not
#      graphify's.
#
# Usage: graphify-nudge.sh <search|read>     (tool payload JSON on stdin)

# set -u only, deliberately — same exception graphify-refresh.sh takes and for
# the same reason. Under `set -e` any unexpected non-zero (a missing `stat`, an
# unwritable cache dir) aborts before the fail-open `exit 0` below, and a
# PreToolUse hook that exits non-zero is the one outcome we must never produce.
set -u

kind="${1:-}"
case "$kind" in
    search|read) ;;
    *) exit 0 ;;
esac

root="${CLAUDE_PROJECT_DIR:-.}"
cd "$root" 2>/dev/null || exit 0

OUT="${GRAPHIFY_OUT:-graphify-out}"
CACHE="$OUT/cache"
CLAIMS="$CACHE/hook_nudges"
TTL="${GRAPHIFY_HOOK_STRICT_TTL:-1800}"

# stdin can only be consumed once: read it into a variable and replay it to
# graphify with printf. $(cat) strips the trailing newline, which json.loads
# does not care about — so this forwards the payload, not the bytes.
payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

# Session key. Anchored to the FIRST "session_id" and stopped at the next quote.
# The sanitisation is load-bearing, not cosmetic: this becomes a filename, a
# Bash payload can carry the literal "session_id": inside the command being
# nudged, JSON key order is not contractual, and `/` or `..` in the value would
# write outside the cache dir. Same treatment upstream gives it before using a
# session id as a path component.
sid="$(printf '%s' "$payload" \
    | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1 \
    | tr -c 'A-Za-z0-9_-' '_' \
    | cut -c1-64)"
[ -n "$sid" ] || sid="unknown"
claim="$CLAIMS/$sid.$kind"

# Fresh orientation stamp means the agent already did what the nudge asks.
stamp_fresh() {
    [ -f "$CACHE/last_query_stamp" ] || return 1
    now="$(date +%s 2>/dev/null)" || return 1
    # -f is BSD, -c is GNU; try both rather than depending on one.
    mt="$(stat -f %m "$CACHE/last_query_stamp" 2>/dev/null \
        || stat -c %Y "$CACHE/last_query_stamp" 2>/dev/null)" || return 1
    case "$now$mt$TTL" in *[!0-9]*) return 1 ;; esac
    [ "$((now - mt))" -lt "$TTL" ]
}

strict_enabled() {
    case "${GRAPHIFY_HOOK_STRICT:-}" in
        1|true|TRUE|yes|YES|on|ON) return 0 ;;
        0|false|FALSE|no|NO|off|OFF) return 1 ;;
    esac
    # Unset defers to the flag baked into the installed command; we never
    # install --strict, so absent an explicit opt-in, strict is off.
    return 1
}

# Skip the fork when nothing graphify could return would be used. With strict
# off, every payload hook-guard can produce is a soft nudge — so once this
# (session, kind) is claimed or the stamp is fresh, the answer is "emit nothing"
# regardless, and forking costs ~100ms of Python startup on every Bash, Grep,
# Read and Glob for the rest of the session. Under strict mode a deny is still
# possible, so we always ask.
if ! strict_enabled; then
    [ -e "$claim" ] && exit 0
    stamp_fresh && exit 0
fi

command -v graphify >/dev/null 2>&1 || exit 0

out="$(printf '%s' "$payload" | graphify hook-guard "$kind" 2>/dev/null)" || exit 0
[ -n "$out" ] || exit 0

# A blocking decision is graphify's to own — pass it through untouched.
case "$out" in
    *'"permissionDecision"'*) printf '%s' "$out"; exit 0 ;;
esac

# Soft nudge. Re-check under strict mode (the pre-fork shortcut was skipped) and
# claim the slot.
stamp_fresh && exit 0
mkdir -p "$CLAIMS" 2>/dev/null || exit 0
# Bash noclobber opens with O_EXCL, so the claim is atomic. The subshell keeps a
# redirection failure on the `:` special builtin from exiting this shell in POSIX
# mode, and keeps noclobber from leaking into later redirections.
( set -C; : > "$claim" ) 2>/dev/null || exit 0

# Sweep stale claims, as upstream does for its own session files.
find "$CLAIMS" -type f -mtime +1 -delete 2>/dev/null

# shellcheck disable=SC2016  # the backticks are literal text in the message, not a command substitution
advice='graphify: this project has a knowledge graph at graphify-out/. For structural questions — where something is defined, what calls it, how two things connect — `graphify query "<question>"` returns a scoped subgraph and is usually cheaper than grepping. Reading or grepping files directly is fine.'
if [ -e "$OUT/needs_update" ]; then
    advice="$advice The graph may be out of date for recent edits; \`graphify update\` refreshes it."
fi

printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"%s"}}\n' \
    "$(printf '%s' "$advice" | sed 's/\\/\\\\/g; s/"/\\"/g')"
