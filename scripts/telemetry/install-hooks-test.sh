#!/usr/bin/env bash
# Tests for scripts/telemetry/install-hooks.sh.
#
# The cases that matter are the ones where a settings-file writer usually goes
# wrong, because ~/.claude/settings.json is a file the user owns and may already
# have things in:
#   - a foreign hook on the same event must survive install AND uninstall;
#   - unrelated top-level keys must survive;
#   - re-running install must not duplicate our entry;
#   - uninstall must remove ours and nothing else;
#   - a settings file that is not JSON must fail cleanly, never be overwritten.
#
# Usage: scripts/telemetry/install-hooks-test.sh
# Ends in RESULT: PASS checks=<n> / RESULT: FAIL reason=assertions failed=<n>
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$HERE/install-hooks.sh"
[[ -x "$SUT" ]] || { echo "RESULT: FAIL reason=sut-missing"; exit 1; }

checks=0; failed=0
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

check() { # check <label> <expected> <actual>
  checks=$((checks+1))
  if [[ "$2" == "$3" ]]; then printf '  ok   %s\n' "$1"
  else printf '  FAIL %s -- expected [%s] got [%s]\n' "$1" "$2" "$3"; failed=$((failed+1)); fi
}
q() { python3 -c "import json,sys;d=json.load(open('$1'));print($2)" 2>/dev/null || echo ERR; }

# 1. install into a file that does not exist yet
S="$TMP/fresh.json"
"$SUT" --settings "$S" >/dev/null 2>&1
check "creates settings when absent" "1" "$(q "$S" "len(d['hooks']['SubagentStart'])")"
check "wires both events"           "1" "$(q "$S" "len(d['hooks']['SubagentStop'])")"

# 2. foreign hooks and unrelated keys survive install
S="$TMP/mixed.json"
cat > "$S" <<'JSON'
{"hooks":{"SubagentStart":[{"matcher":"","hooks":[{"type":"command","command":"bash /foreign.sh"}]}],
 "Stop":[{"matcher":"","hooks":[{"type":"command","command":"bash /other.sh"}]}]},"editor":"vim"}
JSON
"$SUT" --settings "$S" >/dev/null 2>&1
check "foreign hook survives install" "True" "$(q "$S" "any('foreign' in str(h) for h in d['hooks']['SubagentStart'])")"
check "unrelated event untouched"     "1"    "$(q "$S" "len(d['hooks']['Stop'])")"
check "unrelated key untouched"       "vim"  "$(q "$S" "d['editor']")"

# 3. idempotent
"$SUT" --settings "$S" >/dev/null 2>&1
"$SUT" --settings "$S" >/dev/null 2>&1
check "no duplicate on re-run" "2" "$(q "$S" "len(d['hooks']['SubagentStart'])")"

# 4. uninstall removes ours only
"$SUT" --uninstall --settings "$S" >/dev/null 2>&1
check "ours removed"              "0"    "$(q "$S" "sum(1 for e in d['hooks']['SubagentStart'] if 'telemetry' in str(e))")"
check "foreign survives uninstall" "True" "$(q "$S" "any('foreign' in str(h) for h in d['hooks']['SubagentStart'])")"
check "empty event pruned"        "False" "$(q "$S" "'SubagentStop' in d['hooks']")"

# 5. malformed settings fails clean and is not overwritten
S="$TMP/bad.json"; printf 'not json{' > "$S"
out=$("$SUT" --settings "$S" 2>&1); rc=$?
check "non-JSON exits non-zero" "1" "$rc"
check "non-JSON reports reason" "1" "$(grep -c 'reason=settings-not-json' <<<"$out")"
check "non-JSON left untouched" "not json{" "$(cat "$S")"

# 6. status is read-only and reports
S="$TMP/fresh.json"; before=$(md5 -q "$S" 2>/dev/null || md5sum "$S" | cut -d' ' -f1)
out=$("$SUT" --status --settings "$S" 2>&1)
after=$(md5 -q "$S" 2>/dev/null || md5sum "$S" | cut -d' ' -f1)
check "status does not modify" "$before" "$after"
check "status reports wired"   "1" "$(grep -c 'wired=2 of 2' <<<"$out")"

echo
if [[ $failed -eq 0 ]]; then echo "RESULT: PASS checks=$checks"; exit 0; fi
echo "RESULT: FAIL reason=assertions failed=$failed checks=$checks"; exit 1
