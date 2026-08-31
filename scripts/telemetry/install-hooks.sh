#!/usr/bin/env bash
# Install hivesmith's agent telemetry hooks into Claude Code's user settings.
#
# Deliberately separate from install.sh. That installer manages skills, subagents
# and brain helpers across five harnesses with global/local scopes and a doctor;
# telemetry is opt-in, has a different blast radius (these hooks fire in EVERY
# Claude Code session on the machine, in every repo), and should be removable
# without touching any of that. Keeping it separate also means a bug here cannot
# break a skill install.
#
# Usage:
#   scripts/telemetry/install-hooks.sh              install (idempotent)
#   scripts/telemetry/install-hooks.sh --status     report what is wired
#   scripts/telemetry/install-hooks.sh --uninstall  remove only our entries
#   scripts/telemetry/install-hooks.sh --settings PATH   target a different file
#
# Writes to ~/.claude/settings.json, backing it up first. Only entries whose
# command contains scripts/telemetry/ are ever added or removed, so hooks you
# installed by other means are left alone.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETTINGS="${HOME}/.claude/settings.json"
MODE="install"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --uninstall) MODE="uninstall"; shift ;;
    --status)    MODE="status"; shift ;;
    --settings)  SETTINGS="$2"; shift 2 ;;
    -h|--help)   sed -n '2,20p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "RESULT: FAIL reason=bad-arg arg=$1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "RESULT: FAIL reason=no-python3"; exit 1; }
for f in log-agent.sh log-agent-stop.sh; do
  [[ -x "$HERE/$f" ]] || { echo "RESULT: FAIL reason=hook-missing path=$HERE/$f"; exit 1; }
done

MODE="$MODE" SETTINGS="$SETTINGS" HERE="$HERE" python3 - <<'PY'
import json, os, shutil, sys
from pathlib import Path

mode = os.environ["MODE"]
path = Path(os.environ["SETTINGS"]).expanduser()
here = Path(os.environ["HERE"]).resolve()
MARK = "scripts/telemetry/"
PAIRS = [("SubagentStart", "log-agent.sh"), ("SubagentStop", "log-agent-stop.sh")]

data = {}
if path.is_file():
    try:
        data = json.loads(path.read_text() or "{}")
    except ValueError:
        print("RESULT: FAIL reason=settings-not-json path=%s" % path)
        sys.exit(1)
if not isinstance(data, dict):
    print("RESULT: FAIL reason=settings-not-object")
    sys.exit(1)

hooks = data.setdefault("hooks", {}) if mode != "status" else data.get("hooks", {})
if not isinstance(hooks, dict):
    print("RESULT: FAIL reason=hooks-not-object")
    sys.exit(1)

def ours(entry):
    for h in entry.get("hooks", []) if isinstance(entry, dict) else []:
        if MARK in str(h.get("command", "")):
            return True
    return False

if mode == "status":
    found = {ev: sum(1 for e in hooks.get(ev, []) if ours(e)) for ev, _ in PAIRS}
    for ev, n in found.items():
        print("  %-14s %s" % (ev, "wired" if n else "not wired"))
    log = Path(os.environ.get("HIVESMITH_HOME", Path.home() / ".hivesmith")) / "telemetry" / "agent-events.jsonl"
    n = sum(1 for _ in log.open()) if log.is_file() else 0
    print("  events logged  %d  (%s)" % (n, log))
    print("RESULT: PASS wired=%d of %d" % (sum(1 for v in found.values() if v), len(PAIRS)))
    sys.exit(0)

changed = 0
for ev, script in PAIRS:
    lst = hooks.setdefault(ev, [])
    if not isinstance(lst, list):
        print("RESULT: FAIL reason=event-not-list event=%s" % ev)
        sys.exit(1)
    before = len(lst)
    lst[:] = [e for e in lst if not ours(e)]          # drop ours, keep everyone else's
    changed += before - len(lst)
    if mode == "install":
        lst.append({"matcher": "", "hooks": [
            {"type": "command", "command": 'bash "%s/%s"' % (here, script), "timeout": 5}
        ]})
        changed += 1
    if not lst:
        hooks.pop(ev, None)
if mode == "uninstall" and not hooks:
    data.pop("hooks", None)

path.parent.mkdir(parents=True, exist_ok=True)
if path.is_file():
    shutil.copy2(path, str(path) + ".bak")
path.write_text(json.dumps(data, indent=2) + "\n")
print("RESULT: PASS mode=%s changed=%d settings=%s" % (mode, changed, path))
PY
