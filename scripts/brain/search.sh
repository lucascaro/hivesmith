#!/usr/bin/env bash
# search.sh — keyword search across hive brain entries.
#
# Matches case-insensitively against slug, tags, and body. All --query terms
# must hit somewhere in the same entry (AND semantics). Pass multiple --query
# flags or a single space-separated string.
#
# Output: same format as list.sh — slug\tscope-label\trel-path\tfirst-body-line
# plus an optional ranking column when --rank is set.
#
# Usage:
#   search.sh <query...> [--scope ...] [--ecosystem ...] [--project] [--cwd PATH]
#                        [--limit N] [--paths-only] [--rank]
#
# Filters mirror list.sh; --limit caps results; --rank prepends a hit count.
set -euo pipefail

_src="${BASH_SOURCE[0]}"
while [ -L "$_src" ]; do
    _d="$(cd -P "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    [[ "$_src" != /* ]] && _src="$_d/$_src"
done
DIR="$(cd -P "$(dirname "$_src")" && pwd)"
unset _src _d
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

QUERY=""
SCOPE_FILTER="all"
ECO_FILTER=""
PROJECT_ONLY=0
CWD="$PWD"
LIMIT=0
PATHS_ONLY=0
RANK=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)      SCOPE_FILTER="$2"; shift 2 ;;
        --ecosystem)  ECO_FILTER="$2"; shift 2 ;;
        --project)    PROJECT_ONLY=1; shift ;;
        --cwd)        CWD="$2"; shift 2 ;;
        --limit)      LIMIT="$2"; shift 2 ;;
        --paths-only) PATHS_ONLY=1; shift ;;
        --rank)       RANK=1; shift ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        --*)          printf 'search: unknown arg: %s\n' "$1" >&2; exit 64 ;;
        *)            QUERY="$QUERY $1"; shift ;;
    esac
done

QUERY="$(printf '%s' "$QUERY" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
[ -n "$QUERY" ] || { printf 'search: query required\n' >&2; exit 64; }

# Reuse list.sh for the candidate set + filter logic, then grep each path.
LIST="$DIR/list.sh"
[ -x "$LIST" ] || { printf 'search: %s not executable\n' "$LIST" >&2; exit 70; }

list_args=(--scope "$SCOPE_FILTER")
[ -n "$ECO_FILTER" ] && list_args+=(--ecosystem "$ECO_FILTER")
(( PROJECT_ONLY == 1 )) && list_args+=(--project --cwd "$CWD")

# Split QUERY into terms.
read -ra TERMS <<< "$QUERY"

score_file() {
    # Total case-insensitive *literal* occurrence count across all terms.
    # Returns non-zero (skipping output) if any term has zero hits — AND semantics.
    # Single awk pass per file regardless of term count, and counts occurrences
    # not lines, so ranking reflects density.
    local f="$1"
    local out
    # Pack TERMS into a control-char-separated string awk can split safely.
    out="$(awk -v terms="$(IFS=$'\x1f'; printf '%s' "${TERMS[*]}")" '
        BEGIN {
            n = split(terms, t, "\x1f")
            for (i = 1; i <= n; i++) {
                tlow[i] = tolower(t[i])
                hits[i] = 0
                tlen[i] = length(tlow[i])
            }
        }
        {
            line = tolower($0)
            for (i = 1; i <= n; i++) {
                if (tlen[i] == 0) continue
                p = 1
                while ((j = index(substr(line, p), tlow[i])) > 0) {
                    hits[i]++
                    p = p + j  # advance past this match
                }
            }
        }
        END {
            total = 0
            for (i = 1; i <= n; i++) {
                if (tlen[i] > 0 && hits[i] == 0) exit 1
                total += hits[i]
            }
            print total
        }
    ' "$f")" || return 1
    [ -n "$out" ] || return 1
    printf '%s' "$out"
}

tmp_results="$(mktemp)"
trap 'rm -f "$tmp_results"' EXIT

# Iterate the list and score each path.
"$LIST" "${list_args[@]}" | while IFS=$'\t' read -r slug label rel body1; do
    [ -z "$rel" ] && continue
    full="$BRAIN_HOME/$rel"
    [ -f "$full" ] || continue
    if score="$(score_file "$full")"; then
        if (( PATHS_ONLY == 1 )); then
            printf '%010d\t%s\n' "$score" "$rel"
        elif (( RANK == 1 )); then
            printf '%010d\t%s\t%s\t%s\t%s\n' "$score" "$slug" "$label" "$rel" "$body1"
        else
            printf '%010d\t%s\t%s\t%s\t%s\n' "$score" "$slug" "$label" "$rel" "$body1"
        fi
    fi
done > "$tmp_results"

# Sort by score desc, strip the score prefix unless --rank was set.
apply_limit() {
    if [ "$LIMIT" -gt 0 ]; then
        head -n "$LIMIT"
    else
        cat
    fi
}

if (( PATHS_ONLY == 1 )); then
    LC_ALL=C sort -r "$tmp_results" | awk -F'\t' '{print $2}' | apply_limit
elif (( RANK == 1 )); then
    LC_ALL=C sort -r "$tmp_results" | awk -F'\t' 'BEGIN{OFS="\t"}{ sub(/^0+/, "", $1); if($1=="") $1="0"; print }' | apply_limit
else
    LC_ALL=C sort -r "$tmp_results" | awk -F'\t' 'BEGIN{OFS="\t"}{print $2,$3,$4,$5}' | apply_limit
fi
