#!/usr/bin/env bash
# decision.sh — manage per-repo decision records in docs/decisions/.
# Installed as ~/.hivesmith/bin/hs-decision.
#
# Usage:
#   hs-decision propose --title T --source plan|gate|operator|manual \
#       [--origin O] [--tags a,b] [--forbid ERE --paths spec,spec] <<'BODY'
#   ## Context ... ## Decision ... ## Consequences ...
#   BODY
#   hs-decision list [--status accepted|proposed|superseded|all]   (default: accepted)
#   hs-decision accept <slug>          operator only — never run by an agent unprompted
#   hs-decision supersede <old> <new>  operator only — also accepts <new>
#   hs-decision lint
#   hs-decision check                  fail if code matches an accepted record's forbid:
#   hs-decision prune [--apply]        superseded + proposals older than 30 days
#
# Records live at <repo root>/docs/decisions/YYYYMMDD-<slug>.md; the slug is
# the id and the date prefix only sorts. Only the FIRST `---` frontmatter block
# is ever parsed, so a body cannot override it. Proposing an identical title
# again is a no-op that prints the existing path.
# Exit codes: 0 ok, 1 lint problems / check hits, 2 usage / not in a git repo /
# not found / check could not run, 64 invalid input.
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
        inblk && $0 == "---" { if (!done) print (v == "" ? k ":" : k ": " v); inblk = 0; print; next }
        inblk && index($0, k ":") == 1 { print (v == "" ? k ":" : k ": " v); done = 1; next }
        { print }' "$1" > "$tmp"
    cat "$tmp" > "$1"
    rm -f "$tmp"
}

has_frontmatter() { [ "$(head -n 1 "$1")" = "---" ] && awk 'NR > 1 && $0 == "---" { f = 1; exit } END { exit !f }' "$1"; }

D8='[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]'

# records — every record file, including legacy 4-digit ones so that list and
# check never silently drop a record lint would ask to rename.
records() {
    local f
    [ -d "$DIR" ] || return 0
    for f in "$DIR"/[0-9][0-9][0-9][0-9]*-*.md; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    return 0
}

# file_slug <file> — the slug a record's filename carries.
file_slug() { local b; b="$(basename "$1" .md)"; printf '%s\n' "${b#*-}"; }

# with_slug <slug> — every dated record file carrying that slug.
with_slug() {
    local f
    # shellcheck disable=SC2086  # $D8 is a glob on purpose
    for f in "$DIR"/$D8-"$1".md; do
        [ -f "$f" ] && printf '%s\n' "$f"
    done
    return 0
}

# first_with_id <slug> — path of the first record carrying that slug, or empty.
first_with_id() { with_slug "$1" | head -n 1; }

# norm_slug <arg> — a slug from a slug, a basename, or a basename.md.
norm_slug() {
    local s="${1%.md}"
    case "$s" in $D8-*) s="${s#*-}" ;; esac
    case "$s" in
        ''|*[!a-z0-9-]*) die 64 "not a record slug: $1" ;;
    esac
    printf '%s\n' "$s"
}

find_record() {
    local slug hits
    slug="$(norm_slug "$1")" || exit $?
    hits="$(with_slug "$slug")"
    [ -n "$hits" ] || die 2 "no record with slug $slug in docs/decisions/"
    [ "$(printf '%s\n' "$hits" | wc -l | tr -d ' ')" -eq 1 ] \
        || die 64 "ambiguous slug $slug: $(printf '%s' "$hits" | tr '\n' ' ')"
    printf '%s\n' "$hits"
}

# Strip control characters — list output enters agent context. clean() also
# caps length; paths are only stripped, so they still name the file.
strip_ctrl() { printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177'; }
clean() { strip_ctrl "$1" | cut -c1-120; }

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
    local title="" source="" origin="" tags="" forbid="" paths=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --title)  need "$1" $#; title="${2-}"; shift 2 ;;
            --source) need "$1" $#; source="${2-}"; shift 2 ;;
            --origin) need "$1" $#; origin="${2-}"; shift 2 ;;
            --tags)   need "$1" $#; tags="${2-}"; shift 2 ;;
            --forbid) need "$1" $#; forbid="${2-}"; shift 2 ;;
            --paths)  need "$1" $#; paths="${2-}"; shift 2 ;;
            *) die 2 "propose: unknown argument: $1" ;;
        esac
    done
    [ -n "$title" ] || die 64 "propose: --title is required"
    case "$source" in plan|gate|operator|manual) ;; *) die 64 "propose: --source must be plan|gate|operator|manual" ;; esac
    reject_ctrl --title "$title"
    reject_ctrl --origin "$origin"
    reject_ctrl --tags "$tags"
    reject_ctrl --forbid "$forbid"
    reject_ctrl --paths "$paths"
    # A repo-wide default would match the plans and changelogs that quote the
    # mistake, so a check always names where it applies.
    [ -z "$forbid" ] || [ -n "$paths" ] || die 64 "propose: --forbid needs --paths"

    local body=""
    [ -t 0 ] || body="$(cat)"
    [ -n "$body" ] || body="$(printf '## Context\n\n## Decision\n\n## Consequences\n')"

    local slug
    slug="$(printf '%s' "$title" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C sed -e 's/[^a-z0-9]\{1,\}/-/g' -e 's/^-//' -e 's/-$//' | cut -c1-50 | sed 's/-$//')"
    [ -n "$slug" ] || die 64 "propose: --title needs at least one ASCII letter or digit"
    # An 8-digit lead would read as the filename's date prefix on lookup.
    # shellcheck disable=SC2254  # $D8 is a glob on purpose
    case "$slug" in $D8-*|$D8) die 64 "propose: a title must not start with an 8-digit number: $title" ;; esac

    mkdir -p "$DIR"
    # The slug is the id. Re-proposing the same title (a resumed or re-run
    # pipeline step) is a no-op; a different title with the same slug is a
    # real clash and must be loud.
    local existing
    existing="$(first_with_id "$slug")"
    if [ -n "$existing" ]; then
        [ "$(fm_get "$existing" title)" = "$title" ] \
            || die 64 "propose: slug $slug already used by docs/decisions/$(basename "$existing")"
        printf '%s\n' "$existing"
        return 0
    fi
    local path
    path="$DIR/$(date +%Y%m%d)-$slug.md"
    # noclobber: a concurrent proposer of the same slug loses instead of
    # overwriting.
    ( set -C; : > "$path" ) 2>/dev/null || die 64 "propose: $(basename "$path") already exists"

    {
        printf -- '---\n'
        printf 'id: %s\n' "$slug"
        printf 'title: %s\n' "$(quote "$title")"
        printf 'status: proposed\n'
        printf 'date: %s\n' "$(date +%Y-%m-%d)"
        printf 'source: %s\n' "$source"
        printf 'origin: %s\n' "$(quote "$origin")"
        printf 'tags: %s\n' "$tags"
        printf 'supersedes:\n'
        printf 'superseded_by:\n'
        if [ -n "$forbid" ]; then
            printf 'forbid: %s\n' "$(quote "$forbid")"
            printf 'paths: %s\n' "$(quote "$paths")"
        fi
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
            "docs/decisions/$(strip_ctrl "$(basename "$f")")"
    done < <(records)
}

cmd_accept() {
    [ $# -eq 1 ] || die 2 "usage: accept <slug>"
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
    [ $# -eq 2 ] || die 2 "usage: supersede <old-slug> <new-slug>"
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
        case "$(basename "$f")" in
            $D8-*) ;;
            [0-9][0-9][0-9][0-9]-*) p "legacy numeric id; rename to YYYYMMDD-<slug>.md and set id: <slug>"; continue ;;
            *) p "filename must be YYYYMMDD-<slug>.md"; continue ;;
        esac
        id="$(fm_get "$f" id)"
        [ "$id" = "$(file_slug "$f")" ] || p "id '$id' does not match the filename slug"
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
        if [ -n "$(fm_get "$f" forbid)" ] && [ -z "$(fm_get "$f" paths)" ]; then
            p "forbid: without paths:"
        fi
    done < <(records)
    if [ "$problems" -gt 0 ]; then
        printf 'lint: %d problem(s) in %d record(s)\n' "$problems" "$count" >&2
        exit 1
    fi
    printf 'lint: %d record(s) ok\n' "$count"
}

# check_one <file> — run one accepted record's forbid: check. Prints hits.
# Returns 0 clean, 1 hits, 2 could not run.
check_one() {
    local f="$1" slug forbid paths e n=0 out rc
    slug="$(clean "$(fm_get "$f" id)")"
    forbid="$(fm_get "$f" forbid)"
    paths="$(fm_get "$f" paths)"
    local specs=()
    local IFS=,
    set -f
    for e in $paths; do
        e="${e#"${e%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
        [ -n "$e" ] && { specs[n]="$e"; n=$((n + 1)); }
    done
    set +f
    unset IFS
    if [ "$n" -eq 0 ]; then
        printf 'check: %s: forbid: has no paths:\n' "$slug"; return 2
    fi
    if [ -z "$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "${specs[@]}" | head -n 1)" ]; then
        printf 'check: %s: paths: match no files\n' "$slug"; return 2
    fi
    rc=0
    out="$(git -C "$ROOT" grep -nIE --untracked -e "$forbid" -- "${specs[@]}" ':!docs/decisions' 2>/dev/null)" || rc=$?
    case "$rc" in
        0) printf '%s\n' "$out" | while IFS= read -r e; do
               printf 'check: %s: %s\n' "$slug" "$(clean "$(printf '%s' "$e" | cut -d: -f1,2)")"
           done
           return 1 ;;
        1) return 0 ;;
        *) printf 'check: %s: could not run (git grep exit %s)\n' "$slug" "$rc"; return 2 ;;
    esac
}

cmd_check() {
    [ $# -eq 0 ] || die 2 "usage: check"
    local f n=0 worst=0 rc
    while IFS= read -r f; do
        [ "$(fm_get "$f" status)" = accepted ] || continue
        [ -n "$(fm_get "$f" forbid)" ] || continue
        n=$((n + 1)); rc=0
        check_one "$f" || rc=$?
        [ "$rc" -gt "$worst" ] && worst="$rc"
    done < <(records)
    [ "$worst" -eq 0 ] && printf 'check: %d rule(s) ok\n' "$n"
    return "$worst"
}

# unlink_record <slug> — blank every supersedes:/superseded_by: naming <slug>.
unlink_record() {
    local g k
    [ -n "$1" ] || return 0
    while IFS= read -r g; do
        for k in supersedes superseded_by; do
            [ "$(fm_get "$g" "$k")" = "$1" ] && fm_set "$g" "$k" ""
        done
    done < <(records)
    return 0
}

cmd_prune() {
    local apply=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --apply) apply=1; shift ;;
            *) die 2 "prune: unknown argument: $1" ;;
        esac
    done
    local cutoff
    cutoff="$(date -d '30 days ago' +%Y%m%d 2>/dev/null || date -v-30d +%Y%m%d)"
    local f st d reason n=0
    while IFS= read -r f; do
        st="$(fm_get "$f" status)"; reason=""
        case "$st" in
            superseded) reason=superseded ;;
            proposed)
                d="$(fm_get "$f" date)"
                # A missing or malformed date is never a reason to delete.
                case "$d" in
                    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9])
                        [ "$(printf '%s' "$d" | tr -d -)" \< "$cutoff" ] && reason=stale-proposal ;;
                esac ;;
        esac
        [ -n "$reason" ] || continue
        n=$((n + 1))
        printf '%s\tdocs/decisions/%s\n' "$reason" "$(strip_ctrl "$(basename "$f")")"
        [ "$apply" -eq 1 ] || continue
        # Clear every link to the record before deleting it, so lint stays
        # strict and a later record can never inherit the slug's old links.
        # Links first, file last: an interrupted run leaves the record in place
        # and a re-run finishes it.
        unlink_record "$(fm_get "$f" id)"
        rm -f "$f"
    done < <(records)
    if [ "$apply" -eq 1 ]; then
        printf 'prune: deleted %d record(s); commit the result\n' "$n" >&2
    else
        printf 'prune: %d candidate(s); dry run, pass --apply to delete\n' "$n" >&2
    fi
}

[ $# -ge 1 ] || die 2 "usage: hs-decision propose|list|accept|supersede|lint|check|prune"
cmd="$1"; shift
case "$cmd" in
    propose)   cmd_propose "$@" ;;
    list)      cmd_list "$@" ;;
    accept)    cmd_accept "$@" ;;
    supersede) cmd_supersede "$@" ;;
    lint)      cmd_lint "$@" ;;
    check)     cmd_check "$@" ;;
    prune)     cmd_prune "$@" ;;
    -h|--help) sed -n '2,23p' "$0" ;;
    *) die 2 "unknown command: $cmd" ;;
esac
