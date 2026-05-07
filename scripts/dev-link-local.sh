#!/usr/bin/env bash
# dev-link-local.sh — symlink every skill in ./skills/ into a project-local
# skills directory (default .claude/skills/) so Claude Code (or another agent
# runtime that respects project-scoped skills) picks up the worktree's
# versions without needing a global install or a session restart.
#
# Idempotent. Designed for hivesmith contributors dogfooding their own changes.
# Skills land under their bare name (no prefix); project-local skills override
# user-scoped skills of the same name.
#
# Usage:
#   scripts/dev-link-local.sh                       # link skills/* into .claude/skills/
#   scripts/dev-link-local.sh --target .codex/skills
#   scripts/dev-link-local.sh --uninstall           # remove every link this script created
#   scripts/dev-link-local.sh --uninstall --target .codex/skills
#
# Reports a one-line summary: "linked: N, replaced: N, skipped: N, unlinked: N".

set -euo pipefail
shopt -s nullglob

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_SRC="$REPO_ROOT/skills"
TARGET="$REPO_ROOT/.claude/skills"
MODE="link"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) MODE="uninstall"; shift ;;
        --target) TARGET="$REPO_ROOT/${2#./}"; shift 2 ;;
        --target=*) arg="${1#--target=}"; TARGET="$REPO_ROOT/${arg#./}"; shift ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 2 ;;
    esac
done

[[ -d "$SKILLS_SRC" ]] || { echo "ABORT: $SKILLS_SRC does not exist" >&2; exit 1; }

linked=0; replaced=0; skipped=0; unlinked=0; warned=0

if [[ "$MODE" == "uninstall" ]]; then
    if [[ ! -d "$TARGET" ]]; then
        echo "Nothing to uninstall ($TARGET does not exist)."
        exit 0
    fi
    for entry in "$TARGET"/*; do
        [[ -L "$entry" ]] || continue
        link_target="$(readlink "$entry")"
        # Only remove links that point back into our skills/ tree
        case "$link_target" in
            "$SKILLS_SRC"/*|"../../skills/"*)
                rm "$entry"
                unlinked=$((unlinked+1))
                ;;
        esac
    done
    # Remove the directory if it's now empty
    rmdir "$TARGET" 2>/dev/null || true
    echo "linked: 0, replaced: 0, skipped: 0, unlinked: $unlinked"
    exit 0
fi

mkdir -p "$TARGET"

for src_dir in "$SKILLS_SRC"/*/; do
    name="$(basename "$src_dir")"
    src_dir="${src_dir%/}"
    dst="$TARGET/$name"

    if [[ -L "$dst" ]]; then
        existing="$(readlink "$dst")"
        if [[ "$existing" == "$src_dir" ]]; then
            skipped=$((skipped+1))
            continue
        fi
        rm "$dst"
        ln -s "$src_dir" "$dst"
        replaced=$((replaced+1))
    elif [[ -e "$dst" ]]; then
        echo "WARN: $dst exists and is not a symlink — skipping" >&2
        warned=$((warned+1))
    else
        ln -s "$src_dir" "$dst"
        linked=$((linked+1))
    fi
done

echo "linked: $linked, replaced: $replaced, skipped: $skipped, unlinked: 0"
[[ $warned -gt 0 ]] && exit 1 || exit 0
