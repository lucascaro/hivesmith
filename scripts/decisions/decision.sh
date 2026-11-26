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
#   hs-decision authorize merge --head <sha> --pr-base <branch>
#   hs-decision authorize plan --complexity S|M|L --verdict V --confidence N \
#       --must-fix N --conflicts N --files - < paths
#   hs-decision authorize plan --probe
#                                      exit 0 = an accepted record stands in for
#                                      the operator; any other exit = escalate
#
# Records live at <repo root>/docs/decisions/YYYYMMDD-<slug>.md; the slug is
# the id and the date prefix only sorts. Only the FIRST `---` frontmatter block
# is ever parsed, so a body cannot override it. Proposing an identical title
# again is a no-op that prints the existing path.
# Exit codes: 0 ok, 1 lint problems / check hits / authorize escalates,
# 2 usage / not in a git repo / not found / check or authorize could not run,
# 64 invalid input. For authorize, every non-zero exit means "ask the operator".
set -euo pipefail

# Messages interpolate record values, which are untrusted: strip control bytes.
die() { local code="$1"; shift; printf 'hs-decision: %s\n' "$(printf '%s' "$*" | LC_ALL=C tr -d '\000-\037\177')" >&2; exit "$code"; }

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
    p() { problems=$((problems + 1)); printf 'lint: %s: %s\n' "$(strip_ctrl "$base")" "$(strip_ctrl "$1")"; }
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
        while IFS= read -r k; do
            case "$k" in plan|merge) ;; *) p "unknown authorizes token '$k' (want plan, merge)" ;; esac
        done < <(csv_items "$(fm_get "$f" authorizes)")
        if has_token "$f" authorizes plan && [ -z "$(csv_items "$(fm_get "$f" plan_paths)")" ]; then
            p "authorizes: plan without plan_paths:"
        fi
        for k in authorizes plan_paths merge_exclude; do
            case "$(fm_get "$f" "$k")" in *$'\r'*) p "$k: carriage return in value (save the record with LF line endings)" ;; esac
        done
        for k in plan_paths merge_exclude; do
            while IFS= read -r other; do
                case "$other" in
                    :*|/*|*..*) p "$k: entry '$other' must be a repo-relative glob (no leading : or /, no ..)" ;;
                esac
                if [ "$k" = plan_paths ]; then
                    case "$other" in '*'|'**'|.|./|'*/'|'**/') p "plan_paths: '$other' covers the whole repo" ;; esac
                fi
            done < <(csv_items "$(fm_get "$f" "$k")")
        done
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

# ---------------------------------------------------------------------------
# authorize — the only way a record stands in for an operator stop.
#
# Trust anchor: records accepted on origin's default branch, fetched now. The
# worktree's own records are never read, so a PR cannot authorize itself, and
# a supersede or delete upstream takes effect at the next call.
# ---------------------------------------------------------------------------

# Changing these changes the rules a PR is judged by.
BUILTIN_PROTECTED="docs/decisions/,scripts/decisions/"
AUTH_TMP=""
BASE_SHA=""
BASE_NAME=""
cleanup_auth() { [ -z "$AUTH_TMP" ] || rm -rf "$AUTH_TMP"; }

# csv_items <value> — one entry per line, trimmed of spaces and tabs only (a CR
# is kept, so a CRLF value never equals its LF twin), empty entries dropped.
csv_items() {
    local IFS=, e CR=$'\r'
    set -f
    for e in $1; do
        e="${e//"$CR"/}"  # lint flags a CR; never let one silently defeat a match
        e="${e#"${e%%[! 	]*}"}"; e="${e%"${e##*[! 	]}"}"
        [ -n "$e" ] && printf '%s\n' "$e"
    done
    set +f
}

# has_token <file> <key> <token> — exact match against a comma list.
# No pipe into `grep -q`: under pipefail its early exit SIGPIPEs the writer.
has_token() {
    local NL=$'\n'
    case "$NL$(csv_items "$(fm_get "$1" "$2")")$NL" in *"$NL$3$NL"*) return 0 ;; esac
    return 1
}

lc() { printf '%s' "$1" | LC_ALL=C tr '[:upper:]' '[:lower:]'; }

# norm_path <path> — a repo-relative path, or exit 64 for anything that could
# dodge a prefix test: empty, absolute, pathspec magic, control bytes, `..`.
norm_path() {
    local p="$1"
    case "$p" in ''|/*|:*|*[[:cntrl:]]*) die 64 "authorize: not a repo-relative path: $p" ;; esac
    while case "$p" in ./*) true ;; *) false ;; esac; do p="${p#./}"; done
    while case "$p" in *//*) true ;; *) false ;; esac; do p="${p//\/\//\/}"; done
    case "/$p/" in */../*|*/./*|//) die 64 "authorize: not a repo-relative path: $1" ;; esac
    printf '%s\n' "$p"
}

# glob_match <path> <glob> — a trailing / is a directory prefix; otherwise a
# shell pattern in which * also crosses /.
# Both patterns are left unquoted on purpose: a `*` inside a prefix must glob.
# shellcheck disable=SC2254
glob_match() {
    case "$2" in
        */) case "$1" in $2*) return 0 ;; esac; return 1 ;;
    esac
    case "$1" in $2) return 0 ;; esac
    return 1
}

# fetch_base — resolve origin's default branch from the remote itself (a local
# origin/HEAD goes stale after a rename and is one command away from being
# re-pointed), fetch it, and pin it to a commit so later reads agree.
fetch_base() {
    local out line name want
    # No `| head`: under pipefail a SIGPIPE would read as a failed ls-remote.
    out="$(git -C "$ROOT" ls-remote --symref origin HEAD 2>/dev/null)" || out=""
    line="${out%%$'\n'*}"
    want="${out#*$'\n'}"; want="${want%%	*}"
    case "$line" in
        "ref: refs/heads/"*) name="${line#ref: refs/heads/}"; name="${name%%	*}" ;;
        *) die 2 "authorize: cannot resolve origin's default branch" ;;
    esac
    case "$name" in ''|*[!A-Za-z0-9._/-]*) die 2 "authorize: unexpected default branch name: $name" ;; esac
    git -C "$ROOT" fetch --quiet --no-tags origin "refs/heads/$name" 2>/dev/null \
        || die 2 "authorize: fetch of origin/$name failed"
    BASE_SHA="$(git -C "$ROOT" rev-parse --verify --quiet 'FETCH_HEAD^{commit}')" \
        || die 2 "authorize: no FETCH_HEAD after fetching origin/$name"
    # FETCH_HEAD is shared with any concurrent fetch in this repo: trust it only
    # when it is the commit ls-remote just reported for the default branch.
    [ "$BASE_SHA" = "$want" ] \
        || escalate "origin/$name moved or FETCH_HEAD was overwritten during authorize ($want vs $BASE_SHA)"
    BASE_NAME="$name"
}

# base_records — copy the base commit's regular record files into a temp dir
# and point DIR at it, so records() and check_one see only base records.
base_records() {
    local entry meta path name
    AUTH_TMP="$(mktemp -d)"
    trap cleanup_auth EXIT
    mkdir -p "$AUTH_TMP/d"
    while IFS= read -r -d '' entry; do
        meta="${entry%%	*}"; path="${entry#*	}"
        case "${meta%% *}" in 100644|100755) ;; *) continue ;; esac
        name="${path#docs/decisions/}"
        case "$name" in */*|*[!A-Za-z0-9._-]*) continue ;; esac
        case "$name" in [0-9][0-9][0-9][0-9]*-*.md) ;; *) continue ;; esac
        git -C "$ROOT" cat-file blob "${meta##* }" > "$AUTH_TMP/d/$name"
    done < <(git -C "$ROOT" ls-tree -z "$BASE_SHA" docs/decisions/)
    DIR="$AUTH_TMP/d"
}

# accepted_with <token> — base records that are accepted and authorize <token>.
accepted_with() {
    local f
    while IFS= read -r f; do
        [ "$(fm_get "$f" status)" = accepted ] || continue
        has_token "$f" authorizes "$1" && printf '%s\n' "$f"
    done < <(records)
    return 0
}

escalate() { printf 'escalate: %s\n' "$(strip_ctrl "$*")"; exit 1; }
authorized() {
    printf 'authorized: %s (docs/decisions/%s)\n' "$(clean "$(fm_get "$1" id)")" "$(strip_ctrl "$(basename "$1")")"
    exit 0
}

uint() { case "$2" in ''|*[!0-9]*) die 64 "authorize: $1 must be a non-negative integer" ;; esac; }

auth_plan() {
    local probe=0 cx="" verdict="" conf="" mustfix="" conflicts="" files=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --probe)      probe=1; shift ;;
            --complexity) need "$1" $#; cx="${2-}"; shift 2 ;;
            --verdict)    need "$1" $#; verdict="${2-}"; shift 2 ;;
            --confidence) need "$1" $#; conf="${2-}"; shift 2 ;;
            --must-fix)   need "$1" $#; mustfix="${2-}"; shift 2 ;;
            --conflicts)  need "$1" $#; conflicts="${2-}"; shift 2 ;;
            --files)      need "$1" $#; files="${2-}"; shift 2 ;;
            *) die 64 "authorize plan: unknown argument: $1" ;;
        esac
    done
    local rec
    if [ "$probe" -eq 1 ]; then
        fetch_base; base_records
        rec="$(accepted_with plan)"; rec="${rec%%$'\n'*}"
        [ -n "$rec" ] || escalate "no accepted record on origin/$BASE_NAME authorizes plan"
        authorized "$rec"
    fi
    case "$cx" in S|M|L) ;; *) die 64 "authorize plan: --complexity must be S|M|L" ;; esac
    case "$verdict" in approve|revise|block) ;; *) die 64 "authorize plan: --verdict must be approve|revise|block" ;; esac
    uint --confidence "$conf"; uint --must-fix "$mustfix"; uint --conflicts "$conflicts"
    [ "$files" = - ] || die 64 "authorize plan: --files - (read paths from stdin) is required"
    local line list=() n=0
    while IFS= read -r line || [ -n "$line" ]; do
        list[n]="$(norm_path "$line")" || exit $?
        n=$((n + 1))
    done
    [ "$n" -gt 0 ] || die 2 "authorize plan: empty file list"

    fetch_base; base_records
    [ -n "$(accepted_with plan)" ] || escalate "no accepted record on origin/$BASE_NAME authorizes plan"
    [ "$cx" = S ] || escalate "complexity $cx; plan auto-approve covers S only"
    [ "$verdict" = approve ] || escalate "second opinion verdict is $verdict, not approve"
    [ "$conf" -ge 8 ] || escalate "second opinion confidence $conf is below 8"
    [ "$mustfix" -eq 0 ] || escalate "second opinion has $mustfix must-fix item(s)"
    [ "$conflicts" -eq 0 ] || escalate "plan has $conflicts decision-record conflict(s)"
    local p g ok lp
    for p in "${list[@]}"; do
        lp="$(lc "$p")"; lp="${lp%/}/"
        while IFS= read -r g; do
            glob_match "$(lc "$p")" "$(lc "$g")" && escalate "plan touches protected path $p"
            # A bare directory or a parent of one would cover the protected tree.
            case "$(lc "$g")" in "$lp"*) escalate "plan touches protected path $p (contains $g)" ;; esac
        done < <(csv_items "$BUILTIN_PROTECTED")
    done
    while IFS= read -r rec; do
        ok=1
        for p in "${list[@]}"; do
            g=""
            while IFS= read -r g; do glob_match "$p" "$g" && { g=MATCH; break; }; done < <(csv_items "$(fm_get "$rec" plan_paths)")
            [ "$g" = MATCH ] || { ok=0; break; }
        done
        [ "$ok" -eq 1 ] && authorized "$rec"
    done < <(accepted_with plan)
    escalate "no single accepted plan record's plan_paths covers every file (first miss: $p)"
}

auth_merge() {
    local head="" prbase=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --head)    need "$1" $#; head="${2-}"; shift 2 ;;
            --pr-base) need "$1" $#; prbase="${2-}"; shift 2 ;;
            *) die 64 "authorize merge: unknown argument: $1" ;;
        esac
    done
    case "$head" in ''|*[!0-9a-f]*) die 64 "authorize merge: --head must be a commit sha" ;; esac
    [ -n "$prbase" ] || die 64 "authorize merge: --pr-base is required"

    fetch_base
    [ "$prbase" = "$BASE_NAME" ] || escalate "PR base $prbase is not the default branch $BASE_NAME"
    [ -z "$(git -C "$ROOT" status --porcelain 2>/dev/null)" ] || escalate "worktree is not clean (uncommitted or untracked files)"
    local cur want
    cur="$(git -C "$ROOT" rev-parse --verify HEAD)"
    want="$(git -C "$ROOT" rev-parse --verify --quiet "$head^{commit}")" || escalate "HEAD is not the PR head $head"
    [ "$cur" = "$want" ] || escalate "HEAD is not the PR head $head"

    base_records
    local rec
    rec="$(accepted_with merge)"; rec="${rec%%$'\n'*}"
    [ -n "$rec" ] || escalate "no accepted record on origin/$BASE_NAME authorizes merge"

    local mb
    mb="$(git -C "$ROOT" merge-base "$BASE_SHA" HEAD 2>/dev/null)" || die 2 "authorize merge: no merge base with origin/$BASE_NAME"
    local excl f path g n=0
    excl="$BUILTIN_PROTECTED"
    while IFS= read -r f; do
        [ "$(fm_get "$f" status)" = accepted ] || continue
        excl="$excl,$(fm_get "$f" merge_exclude)"
    done < <(records)
    while IFS= read -r -d '' path; do
        n=$((n + 1))
        while IFS= read -r g; do
            glob_match "$(lc "$path")" "$(lc "$g")" && escalate "PR touches protected path $(strip_ctrl "$path")"
        done < <(csv_items "$excl")
    done < <(git -C "$ROOT" diff -z --name-only --no-renames "$mb" HEAD)
    [ "$n" -gt 0 ] || die 2 "authorize merge: the PR changes no files"

    local rc
    while IFS= read -r f; do
        [ "$(fm_get "$f" status)" = accepted ] || continue
        [ -n "$(fm_get "$f" forbid)" ] || continue
        rc=0; check_one "$f" || rc=$?
        case "$rc" in
            0) ;;
            1) escalate "accepted record $(clean "$(fm_get "$f" id)") forbid: check fails on the PR head" ;;
            *) die 2 "authorize merge: forbid: check of $(clean "$(fm_get "$f" id)") could not run" ;;
        esac
    done < <(records)
    authorized "$rec"
}

cmd_authorize() {
    [ $# -ge 1 ] || die 2 "usage: authorize plan|merge ..."
    local stop="$1"; shift
    case "$stop" in
        plan)  auth_plan "$@" ;;
        merge) auth_merge "$@" ;;
        *) die 64 "authorize: unknown stop: $stop (want plan|merge)" ;;
    esac
}

[ $# -ge 1 ] || die 2 "usage: hs-decision propose|list|accept|supersede|lint|check|prune|authorize"
cmd="$1"; shift
case "$cmd" in
    propose)   cmd_propose "$@" ;;
    list)      cmd_list "$@" ;;
    accept)    cmd_accept "$@" ;;
    supersede) cmd_supersede "$@" ;;
    lint)      cmd_lint "$@" ;;
    check)     cmd_check "$@" ;;
    prune)     cmd_prune "$@" ;;
    authorize) cmd_authorize "$@" ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { print; next } { exit }' "$0" ;;
    *) die 2 "unknown command: $cmd" ;;
esac
