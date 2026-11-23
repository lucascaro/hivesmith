#!/usr/bin/env bash
# Tests for decision.sh (hs-decision) in a throwaway git repo.
#
# The failures guarded against: a proposal that smuggles `status: accepted`
# into its own frontmatter (via an argument or the body), id collisions, and a
# lint that passes a broken supersede chain. Records can later stand in for
# operator approval (Phase 2 of #99), so a forged acceptance is the bug that
# matters most here.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/decision.sh"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 300)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }
rc_is(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "exit $3, wanted $2"; fi; }

SANDBOX="$(mktemp -d)"; trap 'rm -rf "$SANDBOX"' EXIT
fresh() { rm -rf "$SANDBOX/r"; mkdir -p "$SANDBOX/r"; cd "$SANDBOX/r" || exit 1; git init -q .; }
D() { bash "$TOOL" "$@"; }

echo "propose"
fresh
out="$(printf '## Context\nc\n## Decision\nd\n' | D propose --title "First rule" --source plan --origin "#1 plan" --tags a,b)"
rc_is propose_creates_missing_dir 0 $?
check propose_creates_missing_dir_path "docs/decisions/0001-first-rule.md" "$out"
out2="$(printf 'body\n' | D propose --title "Second rule" --source gate)"
check propose_allocates_sequential_ids "docs/decisions/0002-second-rule.md" "$out2"
check propose_writes_proposed "status: proposed" "$(cat docs/decisions/0001-first-rule.md)"
check propose_body_from_stdin "## Decision" "$(cat docs/decisions/0001-first-rule.md)"

# shellcheck disable=SC2016  # the body must stay literal: that is the point of the test
printf '$(touch pwned) `touch pwned2`\n' | D propose --title "Shell body" --source manual >/dev/null
if [ ! -e pwned ] && [ ! -e pwned2 ]; then ok propose_body_not_shell_expanded; else bad propose_body_not_shell_expanded "body was executed"; fi

before="$(find docs/decisions -type f | wc -l)"
D propose --title "$(printf 'x\nstatus: accepted')" --source plan </dev/null >/dev/null 2>&1
rc_is propose_title_cannot_inject_status 64 $?
D propose --title ok --tags "$(printf 'a\nstatus: accepted')" --source plan </dev/null >/dev/null 2>&1
rc_is propose_rejects_newline_in_tags 64 $?
D propose --title ok --origin "$(printf 'a\nstatus: accepted')" --source plan </dev/null >/dev/null 2>&1
rc_is propose_rejects_newline_in_origin 64 $?
after="$(find docs/decisions -type f | wc -l)"
rc_is rejected_proposals_write_nothing "$before" "$after"
D propose --title ok --source bogus </dev/null >/dev/null 2>&1
rc_is propose_rejects_bad_source 64 $?

printf -- '---\nstatus: accepted\naccepted: 2026-01-01\n---\nbody\n' | D propose --title "Body override" --source plan >/dev/null
check body_frontmatter_block_ignored "proposed" "$(D list --status all | grep 'Body override')"

D propose --title 'Merge: never # "really"' --source plan </dev/null >/dev/null
check title_with_colon_roundtrips 'Merge: never # "really"' "$(D list --status all)"

mkdir -p src && (cd src && D propose --title "From subdir" --source plan </dev/null >/dev/null)
if [ -n "$(ls docs/decisions/*-from-subdir.md 2>/dev/null)" ] && [ ! -d src/docs ]; then ok works_from_subdirectory; else bad works_from_subdirectory "record not at repo root"; fi

echo "list"
nocheck list_defaults_to_accepted "First rule" "$(D list)"
check list_all_shows_proposed "First rule" "$(D list --status all)"
long="$(printf 'L%.0s' $(seq 1 200))"
D propose --title "$long" --source plan </dev/null >/dev/null
line="$(D list --status all | grep 'LLLL' | cut -f3)"
if [ "${#line}" -le 120 ]; then ok list_sanitizes_fields; else bad list_sanitizes_fields "title length ${#line}"; fi

echo "accept / supersede"
D accept 1 >/dev/null
check accept_sets_status_and_date "status: accepted" "$(cat docs/decisions/0001-first-rule.md)"
check accept_sets_date "accepted: " "$(cat docs/decisions/0001-first-rule.md)"
check list_shows_accepted "First rule" "$(D list)"
D accept 1 >/dev/null 2>&1
rc_is accept_twice_refused 64 $?
D supersede 1 2 >/dev/null
check supersede_marks_old "superseded_by: 0002" "$(cat docs/decisions/0001-first-rule.md)"
check supersede_marks_old_status "status: superseded" "$(cat docs/decisions/0001-first-rule.md)"
check supersede_links_new "supersedes: 0001" "$(cat docs/decisions/0002-second-rule.md)"
check supersede_accepts_replacement "status: accepted" "$(cat docs/decisions/0002-second-rule.md)"
check supersede_dates_replacement "accepted: " "$(cat docs/decisions/0002-second-rule.md)"
check list_shows_replacement "Second rule" "$(D list)"
D supersede 1 2 >/dev/null 2>&1
rc_is supersede_identical_repeat_is_noop 0 $?
D supersede 1 3 >/dev/null 2>&1
rc_is supersede_twice_refused 64 $?
check supersede_twice_keeps_link "superseded_by: 0002" "$(cat docs/decisions/0001-first-rule.md)"
D supersede 2 1 >/dev/null 2>&1
rc_is supersede_cycle_refused 64 $?
D supersede 3 4 >/dev/null 2>&1
rc_is supersede_proposed_old_refused 64 $?
D accept 99 >/dev/null 2>&1
rc_is accept_missing_id 2 $?
D accept abc >/dev/null 2>&1
rc_is accept_bad_id_exits_64 64 $?

# Interrupted accept: only the date landed. A re-run must finish it.
printf 'b\n' | D propose --title "Half accepted" --source plan >/dev/null
ha="$(ls docs/decisions/*-half-accepted.md)"; hi="$(basename "$ha" | cut -c1-4)"
printf '%s\n' "$(awk 'NR>1 && $0=="---" && !d {print "accepted: 2026-01-01"; d=1} {print}' "$ha")" > "$ha"
D accept "$hi" >/dev/null 2>&1
rc_is accept_resumes_after_date_only 0 $?
check accept_resume_sets_status "status: accepted" "$(cat "$ha")"
rc_is accept_resume_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"

# Interrupted supersede: each partial state must be finishable by re-running.
for partial in links_only old_link_only; do
    printf 'b\n' | D propose --title "Old $partial" --source plan >/dev/null
    printf 'b\n' | D propose --title "New $partial" --source plan >/dev/null
    po="$(ls docs/decisions/*-old-"${partial//_/-}".md)"; pn="$(ls docs/decisions/*-new-"${partial//_/-}".md)"
    oi="$(basename "$po" | cut -c1-4)"; ni="$(basename "$pn" | cut -c1-4)"
    D accept "$oi" >/dev/null
    sed -i.bak "s/^superseded_by:\$/superseded_by: $ni/" "$po"
    [ "$partial" = links_only ] && sed -i.bak "s/^supersedes:\$/supersedes: $oi/" "$pn"
    rm -f docs/decisions/*.bak
    D supersede "$oi" "$ni" >/dev/null 2>&1
    rc_is "supersede_resumes_$partial" 0 $?
    check "supersede_resume_${partial}_status" "status: superseded" "$(cat "$po")"
    check "supersede_resume_${partial}_link" "supersedes: $oi" "$(cat "$pn")"
done

# A record replaces at most one other: a replacement that already supersedes
# something cannot take on a second.
for t in Guard-A Guard-B Guard-C; do printf 'b\n' | D propose --title "$t" --source plan >/dev/null; done
ga="$(ls docs/decisions/*-guard-a.md)"; gb="$(ls docs/decisions/*-guard-b.md)"; gc="$(ls docs/decisions/*-guard-c.md)"
ia="$(basename "$ga" | cut -c1-4)"; ib="$(basename "$gb" | cut -c1-4)"; ic="$(basename "$gc" | cut -c1-4)"
D accept "$ia" >/dev/null; D accept "$ib" >/dev/null
D supersede "$ib" "$ic" >/dev/null
D supersede "$ia" "$ic" >/dev/null 2>&1
rc_is supersede_replacement_already_linked_refused 64 $?
check supersede_replacement_already_linked_keeps_old "status: accepted" "$(cat "$ga")"
check supersede_replacement_already_linked_keeps_link "supersedes: $ib" "$(cat "$gc")"
rc_is supersede_resumes_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"
err="$(D propose --title 2>&1 </dev/null)"; rc=$?
rc_is flag_without_value_exits_2 2 "$rc"
check flag_without_value_says_why "needs a value" "$err"

echo "lint"
out="$(D lint 2>&1)"; rc=$?
rc_is lint_passes_clean_set 0 "$rc"
check lint_counts "record(s) ok" "$out"

cp docs/decisions/0002-second-rule.md "$SANDBOX/keep"
sed -i.bak 's/^supersedes: 0001$/supersedes:/' docs/decisions/0002-second-rule.md && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_one_sided_supersede 1 "$rc"
check lint_one_sided_names_file "0001-first-rule.md" "$out"
cp "$SANDBOX/keep" docs/decisions/0002-second-rule.md

f3="$(ls docs/decisions/0003-*.md)"
sed -i.bak 's/^status: proposed$/status: maybe/' "$f3" && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_bad_status 1 "$rc"
check lint_bad_status_names_file "$(basename "$f3")" "$out"
sed -i.bak 's/^status: maybe$/status: proposed/' "$f3" && rm -f docs/decisions/*.bak

sed -i.bak 's/^status: proposed$/status: accepted/' "$f3" && rm -f docs/decisions/*.bak
rc_is lint_rejects_accepted_without_date 1 "$(D lint >/dev/null 2>&1; echo $?)"
sed -i.bak 's/^status: accepted$/status: proposed/' "$f3" && rm -f docs/decisions/*.bak

cp docs/decisions/0002-second-rule.md "$SANDBOX/keep"
sed -i.bak -e 's/^status: accepted$/status: proposed/' -e '/^accepted: /d' docs/decisions/0002-second-rule.md && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_proposed_replacement 1 "$rc"
check lint_proposed_replacement_message "which is only proposed" "$out"
cp "$SANDBOX/keep" docs/decisions/0002-second-rule.md

cp "$f3" docs/decisions/0042-mismatch.md
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_id_filename_mismatch 1 "$rc"
check lint_mismatch_names_file "0042-mismatch.md" "$out"
rm -f docs/decisions/0042-mismatch.md

cp "$f3" "docs/decisions/0003-duplicate.md"
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_duplicate_id 1 "$rc"
check lint_duplicate_message "duplicate id 0003" "$out"
rm -f docs/decisions/0003-duplicate.md

fresh
mkdir -p docs/decisions
printf '# Decisions\n' > docs/decisions/README.md
printf -- '---\nid: NNNN\nstatus: proposed\n---\n' > docs/decisions/_template.md
rc_is lint_skips_readme_and_template 0 "$(D lint >/dev/null 2>&1; echo $?)"
rc_is list_skips_readme_and_template 0 "$(D list --status all | wc -l | tr -d ' ')"

echo "paths"
rm -rf "$SANDBOX/it's here"; mkdir -p "$SANDBOX/it's here"; cd "$SANDBOX/it's here" || exit 1; git init -q .
D propose --title "Quote path" --source plan </dev/null >/dev/null
rc_is propose_in_quoted_path 0 $?
if [ ! -d docs/decisions/.propose.lock ]; then ok lock_released_in_quoted_path; else bad lock_released_in_quoted_path "lock left behind"; fi

cd "$REPO_ROOT" || exit 1
rc_is lint_template_dir_clean 0 "$(bash "$TOOL" lint >/dev/null 2>&1; echo $?)"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: PASS checks=$PASS"
else
    echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
    exit 1
fi
