#!/usr/bin/env bash
# append.sh — append a new entry to the hive brain.
#
# Usage:
#   echo "lesson body" | append.sh \
#       --slug "tests-flaky-on-macos-network" \
#       --scope project \
#       [--ecosystem bun] \
#       [--repo <hash>]      # default: detected from $PWD
#       [--applies-to "**/*.ts,test/**/*.ts"] \
#       [--tags "testing,ci,flake"] \
#       [--graph-nodes "review_pr_skill,ci_workflow"] \
#       [--valid-until 2026-08-09] \
#       [--confidence 0.7] \
#       [--from-untrusted-source] \
#       [--source <skill-name>] \
#       [--pr <number>]
#
# On success: writes "<absolute path to entry>" on stdout, exits 0.
# On redaction failure: exits with redact.sh's exit code.
# On schema failure: exits 64.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh disable=SC1091
. "$DIR/lib.sh"

SLUG=""
SCOPE=""
ECOSYSTEM=""
REPO=""
APPLIES_TO=""
TAGS=""
GRAPH_NODES=""
VALID_UNTIL=""
CONFIDENCE="0.5"
UNTRUSTED=0
SOURCE_SKILL="${HIVESMITH_SKILL:-unknown}"
PR_NUMBER=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --slug)            SLUG="$2"; shift 2 ;;
        --scope)           SCOPE="$2"; shift 2 ;;
        --ecosystem)       ECOSYSTEM="$2"; shift 2 ;;
        --repo)            REPO="$2"; shift 2 ;;
        --applies-to)      APPLIES_TO="$2"; shift 2 ;;
        --tags)            TAGS="$2"; shift 2 ;;
        --graph-nodes)     GRAPH_NODES="$2"; shift 2 ;;
        --valid-until)     VALID_UNTIL="$2"; shift 2 ;;
        --confidence)      CONFIDENCE="$2"; shift 2 ;;
        --from-untrusted-source) UNTRUSTED=1; shift ;;
        --source)          SOURCE_SKILL="$2"; shift 2 ;;
        --pr)              PR_NUMBER="$2"; shift 2 ;;
        *) printf 'append: unknown arg: %s\n' "$1" >&2; exit 64 ;;
    esac
done

[ -n "$SLUG" ]  || { printf 'append: --slug required\n' >&2; exit 64; }
[ -n "$SCOPE" ] || { printf 'append: --scope required\n' >&2; exit 64; }
brain_validate_slug "$SLUG"  || { printf 'append: invalid slug "%s"\n' "$SLUG" >&2; exit 64; }
brain_validate_scope "$SCOPE" >/dev/null || exit 64

if [ "$SCOPE" = "ecosystem" ] && [ -z "$ECOSYSTEM" ]; then
    printf 'append: --ecosystem required when scope=ecosystem\n' >&2; exit 64
fi
if [ "$SCOPE" = "project" ]; then
    [ -n "$REPO" ] || REPO="$(brain_repo_hash)"
fi

brain_lazy_init

# Read body from stdin and redact it.
body_raw="$(cat)"
if ! body_redacted="$(printf '%s' "$body_raw" | "$DIR/redact.sh")"; then
    rc=$?
    printf 'append: redaction failed (exit %d), entry not written\n' "$rc" >&2
    exit "$rc"
fi

# Determine target path.
if (( UNTRUSTED == 1 )); then
    target_dir="$BRAIN_HOME/unverified"
else
    case "$SCOPE" in
        universal) target_dir="$BRAIN_HOME/universal" ;;
        ecosystem) target_dir="$BRAIN_HOME/ecosystem/$ECOSYSTEM" ;;
        user)      target_dir="$BRAIN_HOME/user" ;;
        project)   target_dir="$BRAIN_HOME/project/$REPO" ;;
    esac
fi
mkdir -p "$target_dir"
target="$target_dir/$SLUG.md"
if [ -e "$target" ]; then
    printf 'append: entry already exists at %s — pick a different slug or edit by hand\n' "$target" >&2
    exit 65
fi

# Build front-matter.
created="$(date -u +%Y-%m-%d)"
session="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trusted="true"
if (( UNTRUSTED == 1 )); then trusted="false"; fi

{
    printf -- '---\n'
    printf 'slug: %s\n' "$SLUG"
    printf 'scope: %s\n' "$SCOPE"
    [ -n "$ECOSYSTEM" ]   && printf 'ecosystem: %s\n' "$ECOSYSTEM"
    [ -n "$REPO" ]        && printf 'repo: %s\n' "$REPO"
    if [ -n "$APPLIES_TO" ]; then
        printf 'applies_to: ['
        IFS=',' read -ra _arr <<< "$APPLIES_TO"
        for i in "${!_arr[@]}"; do
            [ "$i" -gt 0 ] && printf ', '
            printf '"%s"' "${_arr[i]}"
        done
        printf ']\n'
    fi
    if [ -n "$TAGS" ]; then
        printf 'tags: [%s]\n' "$TAGS"
    fi
    if [ -n "$GRAPH_NODES" ]; then
        printf 'graph_nodes: [%s]\n' "$GRAPH_NODES"
    fi
    [ -n "$VALID_UNTIL" ] && printf 'valid_until: %s\n' "$VALID_UNTIL"
    printf 'provenance:\n'
    printf '  source: %s\n' "$SOURCE_SKILL"
    printf '  session: %s\n' "$session"
    [ -n "$PR_NUMBER" ] && printf '  pr: %s\n' "$PR_NUMBER"
    printf '  trusted: %s\n' "$trusted"
    printf 'confidence: %s\n' "$CONFIDENCE"
    printf 'created: %s\n' "$created"
    printf 'backlinks: 0\n'
    printf -- '---\n\n'
    printf '%s' "$body_redacted"
    [[ "$body_redacted" == *$'\n' ]] || printf '\n'
} > "$target"

# Validate the file we just wrote.
if ! python3 "$(brain_yaml_py)" validate "$target" >/dev/null 2>&1; then
    rm -f "$target"
    printf 'append: schema validation failed for %s\n' "$target" >&2
    exit 66
fi

# Commit.
git -C "$BRAIN_HOME" add "$target" >/dev/null 2>&1 || true
git -C "$BRAIN_HOME" commit -q -m "brain: add $SLUG ($SCOPE)" >/dev/null 2>&1 || true

printf '%s\n' "$target"
