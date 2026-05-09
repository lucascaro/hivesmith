#!/usr/bin/env bash
# garden.sh — gardener pass over ~/.hivesmith/brain/.
#
# Usage:
#   garden.sh [--regen-index-only | --report | --apply]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../../scripts/brain/lib.sh"
[ -f "$LIB" ] || LIB="${HIVESMITH_DIR:-$HOME/.hivesmith}/scripts/brain/lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.hivesmith/bin/brain-lib.sh"
# shellcheck source=/dev/null disable=SC1091
. "$LIB"

MODE="default"
case "${1:-}" in
    --regen-index-only) MODE="regen" ;;
    --report)           MODE="report" ;;
    --apply)            MODE="apply" ;;
    "")                 MODE="default" ;;
    *) printf 'garden: unknown arg: %s\n' "$1" >&2; exit 64 ;;
esac

brain_lazy_init

INDEX_SH="$BRAIN_LIB_DIR/index.sh"
[ -x "$INDEX_SH" ] || { printf 'garden: index.sh not found at %s\n' "$INDEX_SH" >&2; exit 70; }

# Step 1 — regen index.
"$INDEX_SH" >/dev/null

if [ "$MODE" = "regen" ]; then
    exit 0
fi

PY="$(brain_yaml_py)"
today="$(date -u +%Y-%m-%d)"
month="$(date -u +%Y-%m)"

expired_count=0
stale_graph_count=0
promotion_candidates=()
dedupe_pairs=()
total=0
by_scope_universal=0
by_scope_ecosystem=0
by_scope_user=0
by_scope_project=0
by_scope_unverified=0

# Walk entries.
declare -a all_entries=()
while IFS= read -r -d '' f; do
    rel="${f#"$BRAIN_HOME"/}"
    case "$rel" in
        INDEX.md|README.md|SCHEMA.md|.gitignore|archive/*) continue ;;
    esac
    all_entries+=("$f")
done < <(find "$BRAIN_HOME" -type f -name '*.md' -print0)

# Step 2 — archive expired (--apply only).
if [ "$MODE" = "apply" ] || [ "$MODE" = "default" ]; then
    for f in "${all_entries[@]}"; do
        valid_until="$(python3 "$PY" get "$f" valid_until 2>/dev/null || true)"
        [ -z "$valid_until" ] && continue
        if [[ "$valid_until" < "$today" ]]; then
            slug="$(python3 "$PY" get "$f" slug 2>/dev/null || basename "$f" .md)"
            if [ "$MODE" = "apply" ]; then
                target_dir="$BRAIN_HOME/archive/$month"
                mkdir -p "$target_dir"
                git -C "$BRAIN_HOME" mv "${f#"$BRAIN_HOME"/}" "archive/$month/$(basename "$f")" 2>/dev/null || mv "$f" "$target_dir/"
                git -C "$BRAIN_HOME" commit -q -m "brain: archive $slug (expired $valid_until)" >/dev/null 2>&1 || true
            fi
            expired_count=$((expired_count + 1))
        fi
    done
    # Refresh list after archival.
    all_entries=()
    while IFS= read -r -d '' f; do
        rel="${f#"$BRAIN_HOME"/}"
        case "$rel" in
            INDEX.md|README.md|SCHEMA.md|.gitignore|archive/*) continue ;;
        esac
        all_entries+=("$f")
    done < <(find "$BRAIN_HOME" -type f -name '*.md' -print0)
fi

# Step 3 — validate graph_nodes against graphify-out/graph.json under PWD.
graph_json=""
if [ -f "$PWD/graphify-out/graph.json" ]; then
    graph_json="$PWD/graphify-out/graph.json"
fi

# Tally and surface candidates.
for f in "${all_entries[@]}"; do
    total=$((total + 1))
    rel="${f#"$BRAIN_HOME"/}"
    case "$rel" in
        universal/*)        by_scope_universal=$((by_scope_universal + 1)) ;;
        ecosystem/*)        by_scope_ecosystem=$((by_scope_ecosystem + 1)) ;;
        user/*)             by_scope_user=$((by_scope_user + 1)) ;;
        project/*)          by_scope_project=$((by_scope_project + 1)) ;;
        unverified/*)       by_scope_unverified=$((by_scope_unverified + 1)) ;;
    esac

    if [ -n "$graph_json" ]; then
        nodes="$(python3 "$PY" get "$f" graph_nodes 2>/dev/null || true)"
        if [ -n "$nodes" ]; then
            IFS=',' read -ra _nodes <<< "$nodes"
            for n in "${_nodes[@]}"; do
                n="${n# }"; n="${n% }"
                [ -z "$n" ] && continue
                if ! grep -q "\"$n\"" "$graph_json" 2>/dev/null; then
                    stale_graph_count=$((stale_graph_count + 1))
                    printf 'stale graph_node "%s" in %s\n' "$n" "$rel"
                fi
            done
        fi
    fi

    # Step 4 — promotion candidates.
    if [[ "$rel" == project/* ]]; then
        confidence="$(python3 "$PY" get "$f" confidence 2>/dev/null || echo 0)"
        # bash arithmetic doesn't do floats; use awk.
        if awk -v c="$confidence" 'BEGIN{exit !(c+0 >= 0.7)}'; then
            slug="$(python3 "$PY" get "$f" slug 2>/dev/null || basename "$f" .md)"
            promotion_candidates+=("$slug ($rel)")
        fi
    fi
done

# Step 5 — dedupe candidates: same-scope, slug Levenshtein ≤3.
lev() {
    python3 - "$1" "$2" <<'PY'
import sys
a,b=sys.argv[1],sys.argv[2]
if a==b: print(0); raise SystemExit
m,n=len(a),len(b)
if abs(m-n)>3: print(99); raise SystemExit
prev=list(range(n+1))
for i,ca in enumerate(a,1):
    cur=[i]+[0]*n
    for j,cb in enumerate(b,1):
        cur[j]=min(cur[j-1]+1, prev[j]+1, prev[j-1]+(ca!=cb))
    prev=cur
print(prev[n])
PY
}

# Group by scope dir, compare pairs (bash 3.2 compatible — no associative arrays).
for bucket in universal user unverified ecosystem project; do
    bucket_files=()
    for f in "${all_entries[@]}"; do
        rel="${f#"$BRAIN_HOME"/}"
        if [[ "$rel" == "$bucket"/* ]]; then
            bucket_files+=("$rel")
        fi
    done
    n=${#bucket_files[@]}
    (( n < 2 )) && continue
    for ((i=0; i<n; i++)); do
        for ((j=i+1; j<n; j++)); do
            a_slug="$(basename "${bucket_files[i]}" .md)"
            b_slug="$(basename "${bucket_files[j]}" .md)"
            d="$(lev "$a_slug" "$b_slug")"
            if [ "$d" -le 3 ]; then
                dedupe_pairs+=("${bucket_files[i]} ↔ ${bucket_files[j]} (lev=$d)")
            fi
        done
    done
done

# Report.
printf '\n=== brain garden report (%s) ===\n' "$today"
printf 'Mode: %s\n' "$MODE"
printf 'Entries: %d total — universal=%d ecosystem=%d user=%d project=%d unverified=%d\n' \
    "$total" "$by_scope_universal" "$by_scope_ecosystem" "$by_scope_user" "$by_scope_project" "$by_scope_unverified"
if (( expired_count > 0 )); then
    if [ "$MODE" = "apply" ]; then
        printf 'Archived expired: %d\n' "$expired_count"
    else
        printf 'Would archive expired: %d (run --apply to archive)\n' "$expired_count"
    fi
fi
if (( stale_graph_count > 0 )); then
    printf 'Stale graph_nodes: %d\n' "$stale_graph_count"
fi
if [ "${#promotion_candidates[@]}" -gt 0 ]; then
    printf 'Promotion candidates (consider /hs-brain-promote <slug>):\n'
    for c in "${promotion_candidates[@]}"; do printf '  - %s\n' "$c"; done
fi
if [ "${#dedupe_pairs[@]}" -gt 0 ]; then
    printf 'Dedupe candidates (review by hand):\n'
    for p in "${dedupe_pairs[@]}"; do printf '  - %s\n' "$p"; done
fi

INDEX_SIZE_LINES="$(wc -l < "$BRAIN_HOME/INDEX.md" 2>/dev/null || echo 0)"
INDEX_SIZE_CHARS="$(wc -c < "$BRAIN_HOME/INDEX.md" 2>/dev/null || echo 0)"
printf 'INDEX.md: %d lines, ~%d tokens\n' "$INDEX_SIZE_LINES" $(( INDEX_SIZE_CHARS / 4 ))
printf '=== end ===\n'
