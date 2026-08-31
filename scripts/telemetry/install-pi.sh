#!/usr/bin/env bash
# Install the pi telemetry extension, and optionally the commit-attribution hook.
#
# Separate from install-hooks.sh because pi's extension surface is nothing like
# Claude Code's: extensions are TypeScript modules dropped in a directory and
# loaded by the agent, not JSON entries merged into a settings file. Sharing one
# installer would mean one script that understands two unrelated mechanisms and
# is dangerous to change for either.
#
# Usage:
#   scripts/telemetry/install-pi.sh                    install globally (~/.pi/agent/extensions)
#   scripts/telemetry/install-pi.sh --local            install into ./.pi/extensions
#   scripts/telemetry/install-pi.sh --status           report what is installed
#   scripts/telemetry/install-pi.sh --uninstall        remove only our extension
#   scripts/telemetry/install-pi.sh --commit-trailer REPO [REPO...]
#                                                      install prepare-commit-msg into each repo
#
# The commit-trailer hook is opt-in per repository and never installed by
# default: it appends a trailer to every commit message in that repo, which is a
# change to the repository's history format and should be a deliberate choice.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$HERE/pi-extension.ts"
DEST_DIR="${PI_EXTENSIONS_DIR:-$HOME/.pi/agent/extensions}"
NAME="hivesmith-telemetry.ts"
MODE="install"
declare -a REPOS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --local)          DEST_DIR="$(pwd)/.pi/extensions"; shift ;;
    --status)         MODE="status"; shift ;;
    --uninstall)      MODE="uninstall"; shift ;;
    --commit-trailer) MODE="commit-trailer"; shift; while [[ $# -gt 0 && "$1" != --* ]]; do REPOS+=("$1"); shift; done ;;
    --dest)           DEST_DIR="$2"; shift 2 ;;
    -h|--help)        sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "RESULT: FAIL reason=unknown-argument arg=$1"; exit 1 ;;
  esac
done

DEST="$DEST_DIR/$NAME"

case "$MODE" in
  status)
    if [ -f "$DEST" ]; then
      echo "pi extension: installed at $DEST"
      cmp -s "$SRC" "$DEST" && echo "  content: current" || echo "  content: DIFFERS from source — re-run to update"
    else
      echo "pi extension: not installed (looked in $DEST_DIR)"
    fi
    n=0
    for r in $(git config --global --get-all safe.directory 2>/dev/null) .; do
      [ -f "$r/.git/hooks/prepare-commit-msg" ] && n=$((n+1))
    done
    echo "commit-trailer hook: present in $n inspected repo(s) (pass repos to --commit-trailer to add)"
    echo "RESULT: PASS mode=status installed=$([ -f "$DEST" ] && echo yes || echo no)"
    ;;

  uninstall)
    # Only ever remove a file we recognise as ours. A same-named extension the
    # user wrote themselves must survive an uninstall.
    if [ -f "$DEST" ] && grep -q 'hivesmith' "$DEST" 2>/dev/null; then
      rm -f "$DEST" && echo "removed $DEST"
    elif [ -f "$DEST" ]; then
      echo "refusing to remove $DEST — it does not look like ours"
      echo "RESULT: FAIL reason=foreign-file-at-destination"
      exit 1
    else
      echo "nothing to remove at $DEST"
    fi
    echo "RESULT: PASS mode=uninstall"
    ;;

  commit-trailer)
    [ "${#REPOS[@]}" -gt 0 ] || { echo "RESULT: FAIL reason=no-repos-given"; exit 1; }
    installed=0
    for repo in "${REPOS[@]}"; do
      if [ ! -d "$repo/.git" ]; then
        echo "skip $repo — not a git repository"
        continue
      fi
      hookdir="$repo/.git/hooks"
      mkdir -p "$hookdir"
      target="$hookdir/prepare-commit-msg"
      if [ -e "$target" ] && ! grep -q 'hivesmith' "$target" 2>/dev/null; then
        # Chaining hooks correctly is repo-specific; guessing would silently
        # disable whatever is there. Say so and let the user compose them.
        echo "skip $repo — a foreign prepare-commit-msg is already installed"
        continue
      fi
      cp "$SRC/../prepare-commit-msg" "$target" 2>/dev/null || cp "$HERE/prepare-commit-msg" "$target"
      chmod +x "$target"
      echo "installed prepare-commit-msg into $repo"
      installed=$((installed+1))
    done
    echo "RESULT: PASS mode=commit-trailer installed=$installed of ${#REPOS[@]}"
    ;;

  install)
    [ -f "$SRC" ] || { echo "RESULT: FAIL reason=source-missing path=$SRC"; exit 1; }
    mkdir -p "$DEST_DIR" || { echo "RESULT: FAIL reason=cannot-create-dest dir=$DEST_DIR"; exit 1; }
    if [ -e "$DEST" ] && ! grep -q 'hivesmith' "$DEST" 2>/dev/null; then
      echo "RESULT: FAIL reason=foreign-file-at-destination path=$DEST"
      exit 1
    fi
    cp "$SRC" "$DEST" || { echo "RESULT: FAIL reason=copy-failed"; exit 1; }
    echo "installed $DEST"
    echo "  events: session_start, agent_start, agent_stop, session_shutdown"
    echo "  log:    ${HIVESMITH_TELEMETRY_LOG:-${HIVESMITH_HOME:-$HOME/.hivesmith}/telemetry/agent-events.jsonl}"
    echo "RESULT: PASS mode=install dest=$DEST"
    ;;
esac
