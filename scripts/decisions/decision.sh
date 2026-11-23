#!/usr/bin/env bash
# decision.sh — manage per-repo decision records in docs/decisions/.
# Installed as ~/.hivesmith/bin/hs-decision.
#
# Usage:
#   hs-decision propose --title T --source plan|gate|operator|manual \
#       [--origin O] [--tags a,b] <<'BODY'
#   ## Context ... ## Decision ... ## Consequences ...
#   BODY
#   hs-decision list [--status accepted|proposed|superseded|all]   (default: accepted)
#   hs-decision accept <id>          operator only — never run by an agent unprompted
#   hs-decision supersede <old> <new>  operator only — also accepts <new>
#   hs-decision lint
#
# Records live at <repo root>/docs/decisions/NNNN-<slug>.md. Only the FIRST
# `---` frontmatter block is ever parsed, so a body cannot override it.
# Exit codes: 0 ok, 1 lint problems, 2 usage / not in a git repo / not found,
# 64 invalid input.
set -euo pipefail

die() { local code="$1"; shift; printf 'hs-decision: %s\n' "$*" >&2; exit "$code"; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die 2 "not inside a git repository"
DIR="$ROOT/docs/decisions"

# fm_get <file> <key> — value of <key> in the first frontmatter block, unquoted.
fm_get() {
    awk -v k="$2" '
        NR == 1 { if ($0 != "---") exit; next }
        $0 == "---" { exit }
        index($0, k ":") == 1 {
            v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v); sub(/[ \t]+$/, "", v)
            if (v ~ /^".*"$/) {
                v = substr(v, 2, length(v) - 2)
                out = ""
                for (i = 1; i <= length(v); i++) {
                    c = substr(v, i, 1)
                    if (c == "\\" && i < length(v)) { i++; c = substr(v, i, 1) }
                    out = out c
                }
                v = out
            }
            print v; exit
        }' "$1"
}

# fm_set <file> <key> <raw value> — replace or add <key> inside the first block.
fm_set() {
    local tmp
    tmp="$(mktemp)"
    awk -v k="$2" -v v="$3" '
        NR == 1 { print; inblk = ($0 == "---"); next }
        inblk && $0 == "---" { if (!done) print k ": " v; inblk = 0; print; next }
        inblk && index($0, k ":") == 1 { print k ": " v; done = 1; next }
        { print }' "$1" > "$tmp"
    cat "$tmp" > "$1"
    rm -f "$tmp"
}

has_frontmatter() { [ "$(head -n 1 "$1")" = "---" ] && awk 'NR > 1 && $0 == "---" { f = 1; exit } END { exit !f }' "$1"; }

records() {
    local f
    [ -d "$DIR" ] || return 0
    for f in "$DIR"/[0-9][0-9][0-9][0-9]-*.md; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    return 0
}

# first_with_id <id> — path of the record carrying that id prefix, or empty.
first_with_id() {
    local f
    for f in "$DIR/$1"-*.md; do
        [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    return 0
}

norm_id() {
    case "$1" in
        ''|*[!0-9]*) die 64 "id must be numeric: $1" ;;
    esac
    printf '%04d' "$((10#$1))"
}

find_record() {
    local id f
    id="$(norm_id "$1")" || exit $?
    for f in "$DIR/$id"-*.md; do
        [ -f "$f" ] && { printf '%s\n' "$f"; return 0; }
    done
    die 2 "no record with id $id in docs/decisions/"
}

# Strip control characters and cap length — list output enters agent context.
clean() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' | cut -c1-120; }

quote() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    printf '"%s"' "$s"
}

# need <flag> <argc> — a flag that takes a value must have one.
need() { [ "$2" -ge 2 ] || die 2 "$1 needs a value"; }

reject_ctrl() {
    case "$2" in
        *[[:cntrl:]]*) die 64 "$1 must not contain newlines or control characters" ;;
    esac
}

cmd_propose() {
    local title="" source="" origin="" tags=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --title)  need "$1" $#; title="${2-}"; shift 2 ;;
            --source) need "$1" $#; source="${2-}"; shift 2 ;;
            --origin) need "$1" $#; origin="${2-}"; shift 2 ;;
            --tags)   need "$1" $#; tags="${2-}"; shift 2 ;;
            *) die 2 "propose: unknown argument: $1" ;;
        esac
    done
    [ -n "$title" ] || die 64 "propose: --title is required"
    case "$source" in plan|gate|operator|manual) ;; *) die 64 "propose: --source must be plan|gate|operator|manual" ;; esac
    reject_ctrl --title "$title"
    reject_ctrl --origin "$origin"
    reject_ctrl --tags "$tags"

    local body=""
    [ -t 0 ] || body="$(cat)"
    [ -n "$body" ] || body="$(printf '## Context\n\n## Decision\n\n## Consequences\n')"

    local slug
    slug="$(printf '%s' "$title" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-50 | sed 's/-$//')"
    [ -n "$slug" ] || slug="decision"

    mkdir -p "$DIR"
    # Serialize id allocation across concurrent proposers in this checkout.
    local lock="$DIR/.propose.lock" tries=0
    until mkdir "$lock" 2>/dev/null; do
        tries=$((tries + 1))
        [ "$tries" -lt 50 ] || die 2 "propose: lock held ($lock); remove it if no other propose is running"
        sleep 0.1
    done
    LOCK="$lock"
    trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

    local max=0 f n
    while IFS= read -r f; do
        n="$(basename "$f")"; n="${n%%-*}"; n=$((10#$n))
        [ "$n" -gt "$max" ] && max="$n"
    done < <(records)
    local id path
    id="$(printf '%04d' "$((max + 1))")"
    path="$DIR/$id-$slug.md"

    {
        printf -- '---\n'
        printf 'id: %s\n' "$id"
        printf 'title: %s\n' "$(quote "$title")"
        printf 'status: proposed\n'
        printf 'date: %s\n' "$(date +%Y-%m-%d)"
        printf 'source: %s\n' "$source"
        printf 'origin: %s\n' "$(quote "$origin")"
        printf 'tags: %s\n' "$tags"
        printf 'supersedes:\n'
        printf 'superseded_by:\n'
        printf -- '---\n\n'
        printf '%s\n' "$body"
    } > "$path"
    printf '%s\n' "$path"
}

cmd_list() {
    local want="accepted"
    while [ $# -gt 0 ]; do
        case "$1" in
            --status) need "$1" $#; want="${2-}"; shift 2 ;;
            *) die 2 "list: unknown argument: $1" ;;
        esac
    done
    case "$want" in accepted|proposed|superseded|all) ;; *) die 64 "list: --status must be accepted|proposed|superseded|all" ;; esac
    local f st
    while IFS= read -r f; do
        st="$(fm_get "$f" status)"
        [ "$want" = all ] || [ "$st" = "$want" ] || continue
        printf '%s\t%s\t%s\t%s\t%s\n' \
            "$(clean "$(fm_get "$f" id)")" "$(clean "$st")" \
            "$(clean "$(fm_get "$f" title)")" "$(clean "$(fm_get "$f" tags)")" \
            "docs/decisions/$(clean "$(basename "$f")")"
    done < <(records)
}

cmd_accept() {
    [ $# -eq 1 ] || die 2 "usage: accept <id>"
    local f
    f="$(find_record "$1")"
    [ "$(fm_get "$f" status)" = proposed ] || die 64 "accept: $(basename "$f") is not proposed"
    # Date before status: an interrupted run leaves the record proposed, so a
    # re-run of accept repairs it.
    fm_set "$f" accepted "$(date +%Y-%m-%d)"
    fm_set "$f" status accepted
    printf '%s\n' "$f"
}

cmd_supersede() {
    [ $# -eq 2 ] || die 2 "usage: supersede <old-id> <new-id>"
    local old new
    old="$(find_record "$1")" || exit $?; new="$(find_record "$2")" || exit $?
    [ "$old" != "$new" ] || die 64 "supersede: a record cannot supersede itself"
    local oid nid ost nst
    oid="$(fm_get "$old" id)"; nid="$(fm_get "$new" id)"
    ost="$(fm_get "$old" status)"; nst="$(fm_get "$new" status)"
    local osb nsup
    osb="$(fm_get "$old" superseded_by)"; nsup="$(fm_get "$new" supersedes)"
    # A link already pointing at this pair means an earlier run of this same
    # command was interrupted (or finished): skip the guards and complete the
    # writes, which are idempotent. Any other link is a conflict for the guards.
    if { [ "$osb" = "$nid" ] || [ "$nsup" = "$oid" ]; } \
        && { [ -z "$osb" ] || [ "$osb" = "$nid" ]; } \
        && { [ -z "$nsup" ] || [ "$nsup" = "$oid" ]; }; then
        :
    else
        # Guards keep the chain linear: an accepted rule is only ever replaced
        # by a rule in force, each record is replaced at most once, and a
        # record replaces at most one other. That also rules out cycles.
        [ "$ost" = accepted ] || die 64 "supersede: $(basename "$old") is $ost; only an accepted record can be superseded"
        case "$nst" in proposed|accepted) ;; *) die 64 "supersede: $(basename "$new") is $nst; the replacement must be proposed or accepted" ;; esac
        [ -z "$nsup" ] || die 64 "supersede: $(basename "$new") already supersedes $nsup"
    fi
    # Superseding is an operator act, so it also puts the replacement in force:
    # an accepted rule never drops out of `list` with nothing taking its place.
    # Write order: replacement first, links next, the old status last, so every
    # interrupted state is one the resume check above recognizes.
    if [ "$nst" = proposed ]; then
        fm_set "$new" accepted "$(date +%Y-%m-%d)"
        fm_set "$new" status accepted
    fi
    fm_set "$new" supersedes "$oid"
    fm_set "$old" superseded_by "$nid"
    fm_set "$old" status superseded
    printf '%s\n' "$old"
}

cmd_lint() {
    local problems=0 count=0 f base id st k seen="" other back
    p() { problems=$((problems + 1)); printf 'lint: %s: %s\n' "$base" "$1"; }
    while IFS= read -r f; do
        count=$((count + 1)); base="docs/decisions/$(basename "$f")"
        if ! has_frontmatter "$f"; then p "missing --- frontmatter block"; continue; fi
        for k in id title status date source; do
            [ -n "$(fm_get "$f" "$k")" ] || p "missing required key: $k"
        done
        id="$(fm_get "$f" id)"
        [ "$id" = "$(basename "$f" | cut -c1-4)" ] || p "id '$id' does not match filename prefix"
        case " $seen " in *" $id "*) p "duplicate id $id" ;; esac
        seen="$seen $id"
        st="$(fm_get "$f" status)"
        case "$st" in
            proposed) ;;
            accepted) [ -n "$(fm_get "$f" accepted)" ] || p "status accepted without an accepted: date" ;;
            superseded) [ -n "$(fm_get "$f" superseded_by)" ] || p "status superseded without superseded_by" ;;
            *) p "invalid status '$st' (want proposed|accepted|superseded)" ;;
        esac
        other="$(fm_get "$f" superseded_by)"
        if [ -n "$other" ]; then
            back="$(first_with_id "$other")"
            if [ -z "$back" ]; then p "superseded_by $other does not exist"
            elif [ "$(fm_get "$back" status)" = proposed ]; then p "superseded_by $other, which is only proposed"
            elif [ "$(fm_get "$back" supersedes)" != "$id" ]; then p "superseded_by $other, but $other does not list supersedes: $id"; fi
        fi
        other="$(fm_get "$f" supersedes)"
        if [ -n "$other" ]; then
            back="$(first_with_id "$other")"
            if [ -z "$back" ]; then p "supersedes $other, which does not exist"
            elif [ "$(fm_get "$back" superseded_by)" != "$id" ]; then p "supersedes $other, but $other does not list superseded_by: $id"; fi
        fi
    done < <(records)
    if [ "$problems" -gt 0 ]; then
        printf 'lint: %d problem(s) in %d record(s)\n' "$problems" "$count" >&2
        exit 1
    fi
    printf 'lint: %d record(s) ok\n' "$count"
}

[ $# -ge 1 ] || die 2 "usage: hs-decision propose|list|accept|supersede|lint"
cmd="$1"; shift
case "$cmd" in
    propose)   cmd_propose "$@" ;;
    list)      cmd_list "$@" ;;
    accept)    cmd_accept "$@" ;;
    supersede) cmd_supersede "$@" ;;
    lint)      cmd_lint "$@" ;;
    -h|--help) sed -n '2,18p' "$0" ;;
    *) die 2 "unknown command: $cmd" ;;
esac
