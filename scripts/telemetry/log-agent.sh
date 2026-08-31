#!/usr/bin/env bash
# hivesmith telemetry: record a SubagentStart event.
#
# hivesmith installs at USER level, not per project, so this hook fires in every
# Claude Code session on the machine. Two consequences shape the design:
#
#   1. The log does NOT go into whatever repo happens to be cwd. Scattering a
#      session log across every project you touch is how you end up unable to
#      answer "how much do I actually use this?" -- which is the question this
#      exists for. Everything lands in one file under $HIVESMITH_HOME, with the
#      project recorded as a FIELD.
#   2. It runs everywhere, so it must never fail a session. Every write is
#      best-effort and the script always exits 0.
#
# Input schema (SubagentStart) -- per Claude Code hooks reference:
#   { "session_id": "...", "agent_id": "agent-abc123", "agent_type": "Explore", ... }
# The agent name is in `agent_type`, NOT `agent_name`; the latter is null on
# every invocation. `agent_id` is what lets a start be PAIRED with its stop,
# which is the only way to get per-invocation duration.
#
# A SubagentStart with no agent_type is recorded with agent_type: null plus the payload's
# top-level keys, so the anomaly stays diagnosable instead of being dropped.

set -uo pipefail

HOME_DIR="${HIVESMITH_HOME:-$HOME/.hivesmith}"
LOG_DIR="$HOME_DIR/telemetry"
LOG="$LOG_DIR/agent-events.jsonl"
mkdir -p "$LOG_DIR" 2>/dev/null || exit 0

INPUT=$(cat)
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Project identity: git toplevel name if we are in a repo, else the directory.
PROJECT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT=""
[ -n "$PROJECT" ] && PROJECT=$(basename "$PROJECT") || PROJECT=$(basename "$PWD")

if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -c \
        --arg ts "$TS" --arg ev "subagent_start" --arg proj "$PROJECT" '{
        ts: $ts, event: $ev, project: $proj,
        tool: "claude-code", model: null,
        session_id: (.session_id // null),
        agent_id:   (.agent_id   // null),
        agent_type: (.agent_type // null),
        payload_keys: (keys | join(","))
    }' >> "$LOG" 2>/dev/null
else
    AT=$(printf '%s' "$INPUT" | grep -oE '"agent_type"[[:space:]]*:[[:space:]]*"[^"]*"' \
         | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
    AI=$(printf '%s' "$INPUT" | grep -oE '"agent_id"[[:space:]]*:[[:space:]]*"[^"]*"' \
         | head -1 | sed 's/.*:[[:space:]]*"//;s/"$//')
    printf '{"ts":"%s","event":"%s","project":"%s","agent_id":"%s","agent_type":"%s","jq":false}\n' \
        "$TS" "subagent_start" "$PROJECT" "${AI:-}" "${AT:-}" >> "$LOG" 2>/dev/null
fi

exit 0
