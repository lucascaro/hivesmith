#!/usr/bin/env bash
# read.sh — emit the brain context to inject into a skill prompt.
#
# Output is wrapped in <project-memory untrusted="true">...</project-memory>
# delimiters and starts with the HOT tier of INDEX.md, followed by the
# project-context-filtered ALL tier. Capped at $BRAIN_BUDGET_TOKENS.
#
# Usage:
#   read.sh [--cwd PATH] [--budget N] [--files "a.ts,b.ts,..."]
#
# Environment overrides:
#   BRAIN_BUDGET_TOKENS  cap on emitted tokens (default 8000, ~32K chars)
#   BRAIN_FILES          comma-separated file list for applies_to glob match
#                        (overridden by --files if passed)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

CWD="$PWD"
BUDGET="${BRAIN_BUDGET_TOKENS:-8000}"
FILES_LIST="${BRAIN_FILES:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cwd)    CWD="$2"; shift 2 ;;
        --budget) BUDGET="$2"; shift 2 ;;
        --files)  FILES_LIST="$2"; shift 2 ;;
        *) printf 'read: unknown arg: %s\n' "$1" >&2; exit 64 ;;
    esac
done

brain_lazy_init

repo_hash="$(brain_repo_hash "$CWD")"
ecosystem="$(brain_detect_ecosystem "$CWD")"

# Expand BUDGET tokens to a char budget (~4 chars/token).
char_budget=$(( BUDGET * 4 ))

INDEX="$BRAIN_HOME/INDEX.md"

# If the index is missing, generate it lazily.
if [ ! -f "$INDEX" ] || ! grep -q '<!-- HOT -->' "$INDEX" 2>/dev/null; then
    "$DIR/index.sh" >/dev/null 2>&1 || true
fi

# Match a comma-separated glob list against the file list. Returns 0 if any glob hits.
applies_match() {
    local globs="$1" files="$2"
    [ -z "$globs" ] && return 0  # no applies_to → always include
    [ -z "$files" ] && return 0  # no file context → permissive
    local glob f
    IFS=',' read -ra _globs <<< "$globs"
    IFS=',' read -ra _files <<< "$files"
    for glob in "${_globs[@]}"; do
        glob="${glob//\"/}"
        glob="${glob# }"; glob="${glob% }"
        [ -z "$glob" ] && continue
        for f in "${_files[@]}"; do
            f="${f# }"; f="${f% }"
            # shellcheck disable=SC2053
            if [[ "$f" == $glob ]]; then return 0; fi
        done
    done
    return 1
}

# Emit a filtered slice. Stops when char_budget is exhausted.
# Scope filtering applies to BOTH tiers: a project=X entry never surfaces to a project=Y session.
emit_slice() {
    local section="$1"  # HOT or ALL
    local in_section=0 char_count=0 line stripped
    local begin="<!-- $section -->"
    local end="<!-- $section END -->"
    while IFS= read -r line; do
        if [ "$line" = "$begin" ]; then in_section=1; continue; fi
        if [ "$line" = "$end" ]; then break; fi
        (( in_section == 0 )) && continue
        [ -z "$line" ] && continue

        # Scope filter (applied to both HOT and ALL).
        stripped=$(printf '%s' "$line" | awk -F' · ' '{print $2}')
        local include=0
        case "$stripped" in
            universal)        include=1 ;;
            user)             include=1 ;;
            "ecosystem:$ecosystem") include=1 ;;
            "ecosystem:"*)    include=0 ;;
            project:*) [[ "$stripped" == "project:${repo_hash:0:6}" ]] && include=1 ;;
            *)                include=0 ;;
        esac
        (( include == 0 )) && continue

        # applies_to filtering when present.
        if [[ "$line" == *applies_to=* ]]; then
            local globs
            globs="$(printf '%s' "$line" | sed -n 's/.*applies_to=\([^·]*\).*/\1/p' | sed 's/[[:space:]]*$//')"
            if ! applies_match "$globs" "$FILES_LIST"; then
                continue
            fi
        fi

        local len=${#line}
        if (( char_count + len > char_budget )); then
            printf -- '- [[budget exhausted; more entries elided]]\n'
            break
        fi
        printf '%s\n' "$line"
        char_count=$(( char_count + len + 1 ))
    done < "$INDEX"
}

{
    printf 'project: %s\n' "${repo_hash:0:12}"
    printf 'ecosystem: %s\n' "$ecosystem"
    printf 'budget_tokens: %s\n\n' "$BUDGET"
    printf '<!-- HOT (always-injected) -->\n'
    emit_slice HOT
    printf '\n<!-- FILTERED (universal + user + ecosystem=%s + project=%s) -->\n' "$ecosystem" "${repo_hash:0:6}"
    emit_slice ALL
} | brain_untrusted_wrap
