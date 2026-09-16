#!/usr/bin/env bash
# Write the canonical upgrade-check preamble into every entry skill.
#
# scripts/upgrade/preamble.md is the only place the preamble is edited. Its
# first line lists the entry skills; the rest is the block body. Each listed
# skills/<name>/SKILL.md carries that body between BEGIN/END markers. A skill
# without markers gets the block inserted before its first `## ` heading.
#
# Usage:
#   scripts/upgrade/sync-preamble.sh            rewrite drifted blocks
#   scripts/upgrade/sync-preamble.sh --check    exit 1 naming drifted skills, write nothing
#   scripts/upgrade/sync-preamble.sh --root DIR operate on another checkout (tests)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) CHECK=1; shift ;;
        --root) ROOT="$(cd "${2:?--root needs a directory}" && pwd)"; shift 2 ;;
        -h|--help) sed -n '/^# Usage:/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
        *) echo "sync-preamble: unknown arg: $1" >&2; exit 2 ;;
    esac
done

PREAMBLE="$ROOT/scripts/upgrade/preamble.md"
BEGIN='<!-- BEGIN hivesmith upgrade-check (generated from scripts/upgrade/preamble.md; edit there, then run scripts/upgrade/sync-preamble.sh) -->'
END='<!-- END hivesmith upgrade-check -->'

header="$(head -n 1 "$PREAMBLE")"
if [[ ! "$header" =~ ^\<!--\ entry-skills:\ ([a-z0-9\ -]+)\ --\>$ ]]; then
    echo "sync-preamble: $PREAMBLE line 1 must be '<!-- entry-skills: name ... -->'" >&2
    exit 2
fi
read -r -a ENTRY_SKILLS <<< "${BASH_REMATCH[1]}"

block="$(mktemp)"; expected="$(mktemp)"
trap 'rm -f "$block" "$expected"' EXIT
{ printf '%s\n' "$BEGIN"; tail -n +2 "$PREAMBLE"; printf '%s\n' "$END"; } > "$block"

drift=0
for name in "${ENTRY_SKILLS[@]}"; do
    skill="$ROOT/skills/$name/SKILL.md"
    if [[ ! -f "$skill" ]]; then
        echo "sync-preamble: listed entry skill has no SKILL.md: $skill" >&2
        exit 2
    fi
    if grep -qF '<!-- BEGIN hivesmith upgrade-check' "$skill"; then
        # Replace everything from the BEGIN line through the END line.
        awk -v blockfile="$block" '
            /^<!-- BEGIN hivesmith upgrade-check/ { while ((getline l < blockfile) > 0) print l; skip = 1; next }
            skip && /^<!-- END hivesmith upgrade-check -->$/ { skip = 0; next }
            !skip { print }
            END { if (skip) exit 3 }
        ' "$skill" > "$expected" || {
            # No END marker: writing would drop everything after BEGIN.
            echo "sync-preamble: ${skill#"$ROOT"/} has a BEGIN marker without a matching END marker — fix it by hand" >&2
            exit 2
        }
    else
        # Insert before the first level-2 heading that follows the frontmatter.
        awk -v blockfile="$block" '
            NR == 1 && /^---$/ { fm = 1; print; next }
            fm && /^---$/ { fm = 0; print; next }
            !fm && !done && /^## / { while ((getline l < blockfile) > 0) print l; print ""; done = 1 }
            { print }
        ' "$skill" > "$expected"
    fi
    if ! cmp -s "$skill" "$expected"; then
        drift=1
        if [[ "$CHECK" == "1" ]]; then
            echo "drift: ${skill#"$ROOT"/}"
        else
            cp "$expected" "$skill"
            echo "synced: ${skill#"$ROOT"/}"
        fi
    fi
done

if [[ "$CHECK" == "1" && "$drift" == "1" ]]; then
    echo "sync-preamble: entry-skill preambles differ from scripts/upgrade/preamble.md — run scripts/upgrade/sync-preamble.sh" >&2
    exit 1
fi
exit 0
