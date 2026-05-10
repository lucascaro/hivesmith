#!/usr/bin/env bash
# list.sh — list hive brain entries with optional filters.
#
# Output: one line per entry, TSV-friendly:
#   <slug>\t<scope-label>\t<rel-path>\t<first-non-empty-body-line>
#
# Where <scope-label> is one of:
#   universal | user | ecosystem:<lang> | project:<hash6> | unverified
#
# Usage:
#   list.sh [--scope universal|user|ecosystem|project|unverified|all]
#           [--ecosystem <lang>]
#           [--tag <tag>]
#           [--project]            # restrict to current repo's project entries
#           [--cwd PATH]           # override $PWD for --project detection
#           [--paths-only]         # emit only relative paths
#           [--null]               # NUL-separate fields (for xargs -0 etc.)
#
# Defaults: --scope all, no tag/ecosystem filter, all projects.
set -euo pipefail

# Resolve through symlinks so `~/.hivesmith/bin/brain-list` finds lib.sh next to
# the real script, not next to the symlink.
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

SCOPE_FILTER="all"
ECO_FILTER=""
TAG_FILTER=""
PROJECT_ONLY=0
CWD="$PWD"
PATHS_ONLY=0
NULL_SEP=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope)      SCOPE_FILTER="$2"; shift 2 ;;
        --ecosystem)  ECO_FILTER="$2"; shift 2 ;;
        --tag)        TAG_FILTER="$2"; shift 2 ;;
        --project)    PROJECT_ONLY=1; shift ;;
        --cwd)        CWD="$2"; shift 2 ;;
        --paths-only) PATHS_ONLY=1; shift ;;
        --null)       NULL_SEP=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) printf 'list: unknown arg: %s\n' "$1" >&2; exit 64 ;;
    esac
done

case "$SCOPE_FILTER" in
    all|universal|user|ecosystem|project|unverified) ;;
    *) printf 'list: invalid --scope: %s\n' "$SCOPE_FILTER" >&2; exit 64 ;;
esac

brain_lazy_init
PY="$(brain_yaml_py)"

if (( PROJECT_ONLY == 1 )); then
    REPO_HASH="$(brain_repo_hash "$CWD")"
    REPO_HASH6="${REPO_HASH:0:6}"
else
    REPO_HASH=""
    REPO_HASH6=""
fi

# Pick a field separator the entries themselves can't legally contain.
# Slugs are kebab-case; paths can contain '/', so use TAB.
FS=$'\t'
SEP="$FS"
EOL=$'\n'
if (( NULL_SEP == 1 )); then
    SEP=$'\0'
    EOL=$'\0'
fi

first_body_line() {
    # Skip front-matter, then print the first non-empty, non-heading line, truncated.
    awk '
        BEGIN { in_fm = 0; past_fm = 0 }
        NR == 1 && /^---$/ { in_fm = 1; next }
        in_fm && /^---$/ { in_fm = 0; past_fm = 1; next }
        in_fm { next }
        past_fm {
            line = $0
            sub(/^[[:space:]]+/, "", line)
            if (line == "") next
            if (line ~ /^#/) next
            if (length(line) > 100) line = substr(line, 1, 97) "..."
            print line
            exit
        }
    ' "$1"
}

emit_entry() {
    local f="$1"
    local rel="${f#"$BRAIN_HOME"/}"

    case "$rel" in
        INDEX.md|README.md|SCHEMA.md|.gitignore) return 0 ;;
        archive/*) return 0 ;;
    esac

    local fm
    fm="$(python3 "$PY" read "$f" 2>/dev/null || true)"
    [ -z "$fm" ] && return 0

    local scope ecosystem repo slug tags
    scope="$(printf '%s' "$fm" | awk -F= '$1=="scope"{print $2; exit}')"
    ecosystem="$(printf '%s' "$fm" | awk -F= '$1=="ecosystem"{print $2; exit}')"
    repo="$(printf '%s' "$fm" | awk -F= '$1=="repo"{print $2; exit}')"
    slug="$(printf '%s' "$fm" | awk -F= '$1=="slug"{print $2; exit}')"
    tags="$(printf '%s' "$fm" | awk -F= '$1=="tags"{print $2; exit}')"
    [ -z "$slug" ] && slug="$(basename "$f" .md)"

    # unverified entries live under unverified/ regardless of declared scope.
    case "$rel" in
        unverified/*) scope="unverified" ;;
    esac

    # Scope filter.
    case "$SCOPE_FILTER" in
        all) ;;
        *)   [ "$scope" = "$SCOPE_FILTER" ] || return 0 ;;
    esac

    # Ecosystem filter (only meaningful for ecosystem scope).
    if [ -n "$ECO_FILTER" ]; then
        if [ "$scope" != "ecosystem" ] || [ "$ecosystem" != "$ECO_FILTER" ]; then
            return 0
        fi
    fi

    # Project-only filter: keep universal/user/ecosystem (cross-cutting) PLUS
    # project entries whose repo matches. The intent is "things I'd see in this
    # repo" — same surface as brain-read.
    if (( PROJECT_ONLY == 1 )); then
        case "$scope" in
            universal|user) ;;
            ecosystem) ;;
            project)
                [ "${repo:0:6}" = "$REPO_HASH6" ] || return 0
                ;;
            unverified) return 0 ;;
        esac
    fi

    # Tag filter: comma-separated list in front-matter. Match on whole-word.
    if [ -n "$TAG_FILTER" ]; then
        local norm
        norm=",$(printf '%s' "$tags" | tr -d ' '),"
        case "$norm" in
            *",$TAG_FILTER,"*) ;;
            *) return 0 ;;
        esac
    fi

    # Build the scope label.
    local label="$scope"
    case "$scope" in
        ecosystem) [ -n "$ecosystem" ] && label="ecosystem:$ecosystem" ;;
        project)   [ -n "$repo" ] && label="project:${repo:0:6}" ;;
    esac

    if (( PATHS_ONLY == 1 )); then
        printf '%s%s' "$rel" "$EOL"
        return
    fi

    local body1
    body1="$(first_body_line "$f")"
    printf '%s%s%s%s%s%s%s%s' "$slug" "$SEP" "$label" "$SEP" "$rel" "$SEP" "$body1" "$EOL"
}

# Walk and emit, sorted by scope then slug for stable output.
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT

while IFS= read -r -d '' f; do
    emit_entry "$f" >> "$tmp"
done < <(find "$BRAIN_HOME" -type f -name '*.md' -print0)

if (( NULL_SEP == 1 )); then
    # Caller wants raw NUL stream; sorting is awkward and rarely useful here.
    cat "$tmp"
else
    LC_ALL=C sort "$tmp"
fi
