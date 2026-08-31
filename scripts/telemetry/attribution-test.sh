#!/usr/bin/env bash
# Tests for prepare-commit-msg and pi-extension.ts.
#
# This hook runs on every commit in every repo it is installed into, so the
# governing requirement is not "does it attribute correctly" but "can it ever
# stop a commit". Most checks below are about staying out of the way.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/prepare-commit-msg"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 200)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }

W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
REPO="$W/proj"; mkdir -p "$REPO"; cd "$REPO" || exit 1
git init -q .; git config user.email t@t; git config user.name t
LOG="$W/events.jsonl"
export HIVESMITH_TELEMETRY_LOG="$LOG"

now(){ python3 -c "import datetime as d;print((d.datetime.now(d.timezone.utc)-d.timedelta(seconds=int($1))).isoformat().replace('+00:00','Z'))"; }
event(){ printf '{"ts":"%s","event":"agent_stop","project":"%s","tool":"%s","model":"%s","session_id":"s-1"}\n' \
         "$(now "$1")" "$2" "$3" "$4" >> "$LOG"; }
run(){ printf '%s\n' "$1" > "$W/msg"; "$HOOK" "$W/msg" "${2:-}"; echo "exit=$?"; cat "$W/msg"; }

# 1. No log at all: silence, and never a failure.
rm -f "$LOG"
OUT="$(run 'feat: something')"
check "exits 0 with no telemetry log"        "exit=0" "$OUT"
nocheck "adds no trailer with no telemetry"  "Agent-Tool" "$OUT"

# 2. A recent event for this project: stamp it, with the evidence attached.
event 30 proj pi "claude-opus-4.7"
OUT="$(run 'feat: something')"
check "stamps the producing tool"            "Agent-Tool: pi" "$OUT"
check "stamps the model"                     "Agent-Model: claude-opus-4.7" "$OUT"
check "records the inference, not a claim"   "Agent-Attribution: inferred" "$OUT"
check "carries the age as evidence"          "before commit" "$OUT"
check "still exits 0"                        "exit=0" "$OUT"

# 3. Existing attribution wins: never double-attribute or overwrite.
OUT="$(run 'feat: x

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>')"
nocheck "leaves a Co-Authored-By commit alone" "Agent-Tool" "$OUT"
OUT="$(run 'feat: x

Agent-Tool: codex')"
nocheck "leaves an already-stamped commit alone" "Agent-Tool: pi" "$OUT"

# 4. Window discipline: an event from two hours ago is not this commit.
rm -f "$LOG"; event 7200 proj pi "m"
OUT="$(run 'feat: something')"
nocheck "ignores an event outside the window" "Agent-Tool" "$OUT"
OUT="$(HIVESMITH_ATTRIBUTION_WINDOW_S=99999 run 'feat: something')"
check "honours a widened window"             "Agent-Tool: pi" "$OUT"

# 5. Cross-project bleed: another repo's session must not attribute this commit.
rm -f "$LOG"; event 30 other-project pi "m"
OUT="$(run 'feat: something')"
nocheck "ignores events from another project" "Agent-Tool" "$OUT"

# 6. Commit sources that already have settled attribution.
rm -f "$LOG"; event 30 proj pi "m"
for src in merge squash commit; do
  OUT="$(run 'feat: x' "$src")"
  nocheck "skips a '$src' commit"            "Agent-Tool" "$OUT"
done

# 7. Hostile input: the log is append-only from several writers and WILL be
#    torn mid-line at some point. That must cost an attribution, never a commit.
rm -f "$LOG"; printf 'not json at all\n{"ts":"broken\n' > "$LOG"; event 30 proj pi "m"
OUT="$(run 'feat: something')"
check "survives malformed lines in the log"  "exit=0" "$OUT"
check "and still finds the valid event"      "Agent-Tool: pi" "$OUT"
printf '{"ts":"not-a-timestamp","project":"proj","tool":"pi"}\n' > "$LOG"
OUT="$(run 'feat: something')"
check "survives an unparseable timestamp"    "exit=0" "$OUT"

# 8. Missing or unreadable message file: exit 0, touch nothing.
echo "exit=$("$HOOK" "$W/does-not-exist" >/dev/null 2>&1; echo $?)" > "$W/r"
check "exits 0 when the message file is absent" "exit=0" "$(cat "$W/r")"
echo "exit=$("$HOOK" >/dev/null 2>&1; echo $?)" > "$W/r"
check "exits 0 with no arguments at all"     "exit=0" "$(cat "$W/r")"

# 9. End to end: a real commit in a real repo must carry the trailer and be
#    readable by git's own trailer parser, not just by grep.
rm -f "$LOG"; event 10 proj pi "claude-opus-4.7"
mkdir -p "$REPO/.git/hooks"; cp "$HOOK" "$REPO/.git/hooks/prepare-commit-msg"
cd "$REPO" || exit 1; echo hi > f.txt; git add -A
HIVESMITH_TELEMETRY_LOG="$LOG" git commit -q -m "feat: real commit"
TRAILERS="$(git log -1 --format='%(trailers:key=Agent-Tool,valueonly=true)')"
check "git parses the trailer it wrote"      "pi" "$TRAILERS"

# 10. The pi extension must be valid TypeScript-shaped JS and never throw on
#     a context missing the fields it wants.
if node --experimental-strip-types -e '1' >/dev/null 2>&1; then
  cat > "$W/smoke.ts" <<'SMOKE'
import ext from "./pi-extension.ts";
const handlers: Record<string, Function> = {};
ext({ on: (e: string, h: Function) => { handlers[e] = h; } } as never);
for (const name of ["session_start", "agent_start", "agent_end", "session_shutdown"]) {
  if (!handlers[name]) { console.log("MISSING " + name); process.exit(1); }
}
handlers["agent_start"](undefined, {});                       // no model, no sessionManager
handlers["agent_end"]({ messages: [1, 2] }, { model: { id: "m-1" },
  sessionManager: { getSessionId: () => "sid" } });
handlers["session_start"]({ reason: "resume" }, { model: "plain-string" });
console.log("SMOKE-OK");
SMOKE
  cp "$HERE/pi-extension.ts" "$W/pi-extension.ts"
  SMOKE_OUT="$(cd "$W" && HIVESMITH_TELEMETRY_LOG="$W/pi.jsonl" node --experimental-strip-types smoke.ts 2>&1)"
  check "pi extension registers all four events and survives a bare context" "SMOKE-OK" "$SMOKE_OUT"
  check "pi extension writes the shared schema" '"tool":"pi"' "$(cat "$W/pi.jsonl" 2>/dev/null)"
  check "pi extension resolves a model object"  '"model":"m-1"' "$(cat "$W/pi.jsonl" 2>/dev/null)"
  check "pi extension records message count, not bodies" '"messages":2' "$(cat "$W/pi.jsonl" 2>/dev/null)"
else
  ok "pi extension smoke test skipped (node type-stripping unavailable)"
fi

echo
if [ "$FAIL" -eq 0 ]; then echo "RESULT: PASS checks=$PASS"; exit 0; fi
echo "RESULT: FAIL reason=assertions-failed passed=$PASS failed=$FAIL"; exit 1
