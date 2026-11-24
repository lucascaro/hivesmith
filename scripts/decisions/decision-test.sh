#!/usr/bin/env bash
# Tests for decision.sh (hs-decision) in a throwaway git repo.
#
# The failures guarded against: a proposal that smuggles `status: accepted`
# into its own frontmatter (via an argument or the body), slug clashes, a lint
# that passes a broken supersede chain, and a regression check that silently
# skips. Records can later stand in for
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
R() { ls docs/decisions/[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-"$1".md; }   # dated path of a slug
T() { git add -A >/dev/null && git -c user.name=t -c user.email=t@t commit -qm "$1" >/dev/null; }

echo "propose"
fresh
out="$(printf '## Context\nc\n## Decision\nd\n' | D propose --title "First rule" --source plan --origin "#1 plan" --tags a,b)"
rc_is propose_creates_missing_dir 0 $?
if printf '%s' "$out" | grep -qE 'docs/decisions/[0-9]{8}-first-rule\.md$'; then ok propose_names_file_by_date_and_slug; else bad propose_names_file_by_date_and_slug "$out"; fi
check propose_id_is_slug "id: first-rule" "$(cat "$(R first-rule)")"
printf 'body\n' | D propose --title "Second rule" --source gate >/dev/null
rc_is distinct_slugs_both_succeed 0 $?
check propose_writes_proposed "status: proposed" "$(cat "$(R first-rule)")"
check propose_body_from_stdin "## Decision" "$(cat "$(R first-rule)")"
sum="$(cksum < "$(R first-rule)")"
again="$(D propose --title "First rule" --source plan </dev/null)"; rc=$?
rc_is propose_same_title_is_idempotent 0 "$rc"
check propose_same_title_prints_existing "first-rule.md" "$again"
rc_is propose_same_title_leaves_file "$sum" "$(cksum < "$(R first-rule)")"
D propose --title "First  RULE!" --source plan </dev/null >/dev/null 2>&1
rc_is propose_slug_clash_different_title_exits_64 64 $?
D propose --title "!!!" --source plan </dev/null >/dev/null 2>&1
rc_is propose_rejects_title_without_alnum 64 $?
D propose --title "12345678 foo" --source plan </dev/null >/dev/null 2>&1
rc_is propose_rejects_8_digit_leading_slug 64 $?
D propose --title "1234567 foo" --source plan </dev/null >/dev/null 2>&1
rc_is propose_allows_7_digit_leading_slug 0 $?
rm -f docs/decisions/*-1234567-foo.md

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
D propose --title ok --forbid "$(printf 'a\nstatus: accepted')" --paths src --source plan </dev/null >/dev/null 2>&1
rc_is propose_rejects_newline_in_forbid 64 $?
D propose --title ok --forbid foo --source plan </dev/null >/dev/null 2>&1
rc_is propose_forbid_requires_paths 64 $?
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
# A hand-written record may have a filename longer than the display cap; its
# path must still name the file.
lslug="$(printf 'p%.0s' $(seq 1 150))"; longf="20260101-$lslug.md"
printf -- '---\nid: %s\ntitle: Long path\nstatus: proposed\ndate: 2026-01-01\nsource: manual\n---\n' "$lslug" > "docs/decisions/$longf"
check list_keeps_long_path_intact "docs/decisions/$longf" "$(D list --status all | grep 'Long path' | cut -f5)"
rm -f "docs/decisions/$longf"
printf -- '---\nid: 0007\ntitle: Legacy one\nstatus: accepted\naccepted: 2026-01-01\ndate: 2026-01-01\nsource: manual\n---\n' > docs/decisions/0007-legacy-one.md
check list_includes_legacy_numeric_record "Legacy one" "$(D list)"
out="$(D lint 2>&1)"
check lint_flags_legacy_numeric_file "legacy numeric id" "$out"
rm -f docs/decisions/0007-legacy-one.md

echo "accept / supersede"
D accept first-rule >/dev/null
check accept_sets_status_and_date "status: accepted" "$(cat "$(R first-rule)")"
check accept_sets_date "accepted: " "$(cat "$(R first-rule)")"
check list_shows_accepted "First rule" "$(D list)"
D accept first-rule >/dev/null 2>&1
rc_is accept_twice_refused 64 $?
D accept "$(basename "$(R shell-body)")" >/dev/null
rc_is accept_by_basename 0 $?
D accept rule >/dev/null 2>&1
rc_is slug_lookup_is_anchored 2 $?
D accept ../x >/dev/null 2>&1
rc_is find_rejects_path_traversal 64 $?
D supersede first-rule second-rule >/dev/null
check supersede_marks_old "superseded_by: second-rule" "$(cat "$(R first-rule)")"
check supersede_marks_old_status "status: superseded" "$(cat "$(R first-rule)")"
check supersede_links_by_slug "supersedes: first-rule" "$(cat "$(R second-rule)")"
check supersede_accepts_replacement "status: accepted" "$(cat "$(R second-rule)")"
check supersede_dates_replacement "accepted: " "$(cat "$(R second-rule)")"
check list_shows_replacement "Second rule" "$(D list)"
D supersede first-rule second-rule >/dev/null 2>&1
rc_is supersede_identical_repeat_is_noop 0 $?
D supersede first-rule body-override >/dev/null 2>&1
rc_is supersede_twice_refused 64 $?
check supersede_twice_keeps_link "superseded_by: second-rule" "$(cat "$(R first-rule)")"
D supersede second-rule first-rule >/dev/null 2>&1
rc_is supersede_cycle_refused 64 $?
D supersede body-override from-subdir >/dev/null 2>&1
rc_is supersede_proposed_old_refused 64 $?
D accept no-such-rule >/dev/null 2>&1
rc_is accept_missing_slug 2 $?
D accept 'Bad Slug' >/dev/null 2>&1
rc_is accept_bad_slug_exits_64 64 $?
cp "$(R from-subdir)" docs/decisions/20200101-from-subdir.md
D accept from-subdir >/dev/null 2>&1
rc_is find_refuses_ambiguous_slug 64 $?
out="$(D lint 2>&1)"
check lint_flags_duplicate_slug_across_dates "duplicate id from-subdir" "$out"
rm -f docs/decisions/20200101-from-subdir.md

# Interrupted accept: only the date landed. A re-run must finish it.
printf 'b\n' | D propose --title "Half accepted" --source plan >/dev/null
ha="$(R half-accepted)"
printf '%s\n' "$(awk 'NR>1 && $0=="---" && !d {print "accepted: 2026-01-01"; d=1} {print}' "$ha")" > "$ha"
D accept half-accepted >/dev/null 2>&1
rc_is accept_resumes_after_date_only 0 $?
check accept_resume_sets_status "status: accepted" "$(cat "$ha")"
rc_is accept_resume_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"

# Interrupted supersede: each partial state must be finishable by re-running.
for partial in links_only new_link_only old_link_only; do
    oi="old-${partial//_/-}"; ni="new-${partial//_/-}"
    printf 'b\n' | D propose --title "Old $partial" --source plan >/dev/null
    printf 'b\n' | D propose --title "New $partial" --source plan >/dev/null
    po="$(R "$oi")"; pn="$(R "$ni")"
    D accept "$oi" >/dev/null
    # new_link_only is where supersede stops if interrupted after its first link write.
    [ "$partial" = new_link_only ] || sed -i.bak "s/^superseded_by:\$/superseded_by: $ni/" "$po"
    [ "$partial" = old_link_only ] || sed -i.bak "s/^supersedes:\$/supersedes: $oi/" "$pn"
    rm -f docs/decisions/*.bak
    D supersede "$oi" "$ni" >/dev/null 2>&1
    rc_is "supersede_resumes_$partial" 0 $?
    check "supersede_resume_${partial}_status" "status: superseded" "$(cat "$po")"
    check "supersede_resume_${partial}_link" "supersedes: $oi" "$(cat "$pn")"
done

# A record replaces at most one other: a replacement that already supersedes
# something cannot take on a second.
for t in Guard-A Guard-B Guard-C; do printf 'b\n' | D propose --title "$t" --source plan >/dev/null; done
D accept guard-a >/dev/null; D accept guard-b >/dev/null
D supersede guard-b guard-c >/dev/null
D supersede guard-a guard-c >/dev/null 2>&1
rc_is supersede_replacement_already_linked_refused 64 $?
check supersede_replacement_already_linked_keeps_old "status: accepted" "$(cat "$(R guard-a)")"
check supersede_replacement_already_linked_keeps_link "supersedes: guard-b" "$(cat "$(R guard-c)")"
rc_is supersede_resumes_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"
err="$(D propose --title 2>&1 </dev/null)"; rc=$?
rc_is flag_without_value_exits_2 2 "$rc"
check flag_without_value_says_why "needs a value" "$err"

echo "lint"
out="$(D lint 2>&1)"; rc=$?
rc_is lint_passes_clean_set 0 "$rc"
check lint_counts "record(s) ok" "$out"

s2="$(R second-rule)"; cp "$s2" "$SANDBOX/keep"
sed -i.bak 's/^supersedes: first-rule$/supersedes:/' "$s2" && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_one_sided_supersede 1 "$rc"
check lint_one_sided_names_file "first-rule.md" "$out"
cp "$SANDBOX/keep" "$s2"

f3="$(R body-override)"
sed -i.bak 's/^status: proposed$/status: maybe/' "$f3" && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_bad_status 1 "$rc"
check lint_bad_status_names_file "$(basename "$f3")" "$out"
sed -i.bak 's/^status: maybe$/status: proposed/' "$f3" && rm -f docs/decisions/*.bak

sed -i.bak 's/^status: proposed$/status: accepted/' "$f3" && rm -f docs/decisions/*.bak
rc_is lint_rejects_accepted_without_date 1 "$(D lint >/dev/null 2>&1; echo $?)"
sed -i.bak 's/^status: accepted$/status: proposed/' "$f3" && rm -f docs/decisions/*.bak

cp "$s2" "$SANDBOX/keep"
sed -i.bak -e 's/^status: accepted$/status: proposed/' -e '/^accepted: /d' "$s2" && rm -f docs/decisions/*.bak
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_proposed_replacement 1 "$rc"
check lint_proposed_replacement_message "which is only proposed" "$out"
cp "$SANDBOX/keep" "$s2"

cp "$f3" docs/decisions/20260101-mismatch.md
out="$(D lint 2>&1)"; rc=$?
rc_is lint_flags_id_filename_mismatch 1 "$rc"
check lint_mismatch_names_file "20260101-mismatch.md" "$out"
rm -f docs/decisions/20260101-mismatch.md

f1="$(R first-rule)"; cp "$f1" "$SANDBOX/keep1"; rm -f "$f1"
out="$(D lint 2>&1)"; rc=$?
rc_is lint_rejects_dangling_supersedes 1 "$rc"
check lint_dangling_supersedes_message "which does not exist" "$out"
cp "$SANDBOX/keep1" "$f1"

fresh
mkdir -p docs/decisions
printf '# Decisions\n' > docs/decisions/README.md
printf -- '---\nid: <slug>\nstatus: proposed\n---\n' > docs/decisions/_template.md
rc_is lint_skips_readme_and_template 0 "$(D lint >/dev/null 2>&1; echo $?)"
rc_is list_skips_readme_and_template 0 "$(D list --status all | wc -l | tr -d ' ')"

echo "prune"
fresh
mk() { printf -- '---\nid: %s\ntitle: %s\nstatus: %s\ndate: %s\nsource: manual\n%s---\n' "$2" "$2" "$3" "$4" "$5" > "docs/decisions/$1-$2.md"; }
mkdir -p docs/decisions
today="$(date +%Y-%m-%d)"; td="$(date +%Y%m%d)"
mk 20200101 old-prop proposed 2020-01-01 ''
mk "$td" fresh-prop proposed "$today" ''
mk 20200101 gone superseded 2020-01-01 $'accepted: 2020-01-01\nsuperseded_by: kept\n'
mk 20200101 kept accepted 2020-01-01 $'accepted: 2020-01-01\nsupersedes: gone\n'
mk 20200101 bad-date proposed 'last year' ''
out="$(D prune 2>/dev/null)"
check prune_lists_stale "stale-proposal	docs/decisions/20200101-old-prop.md" "$out"
check prune_lists_superseded "superseded	docs/decisions/20200101-gone.md" "$out"
nocheck prune_keeps_fresh_proposal "fresh-prop" "$out"
nocheck prune_keeps_accepted "kept" "$out"
nocheck prune_skips_malformed_date "bad-date" "$out"
rc_is prune_dry_run_deletes_nothing 5 "$(find docs/decisions -name '*.md' | wc -l | tr -d ' ')"
D prune --apply >/dev/null 2>&1
if [ ! -e docs/decisions/20200101-old-prop.md ] && [ ! -e docs/decisions/20200101-gone.md ] \
    && [ -e docs/decisions/20200101-kept.md ] && [ -e "docs/decisions/$td-fresh-prop.md" ] \
    && [ -e docs/decisions/20200101-bad-date.md ]; then ok prune_apply_deletes_candidates_only
else bad prune_apply_deletes_candidates_only "$(find docs/decisions -name '*.md' | tr '\n' ' ')"; fi
check prune_apply_clears_supersedes_link "supersedes:" "$(grep '^supersedes:' docs/decisions/20200101-kept.md)"
nocheck prune_apply_leaves_no_dangling_link "gone" "$(cat docs/decisions/20200101-kept.md)"
rc_is prune_apply_keeps_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"
# The reviewer's repro: re-proposing a pruned title must not inherit its links.
D propose --title gone --source plan </dev/null >/dev/null
rc_is reproposed_pruned_title_lint_clean 0 "$(D lint >/dev/null 2>&1; echo $?)"

echo "check"
fresh
mkdir -p src docs/exec-plans
printf 'fine\n' > src/a.sh
T base
D propose --title "No eval" --source operator --forbid 'eval[[:space:]]+"\$' --paths 'src, ,lib' </dev/null >/dev/null
# shellcheck disable=SC2016  # literal "$x" is the planted mistake
printf 'eval "$x"\n' > src/b.sh
# shellcheck disable=SC2016  # literal "$x" is the planted mistake
printf 'never write eval "$x"\n' > docs/exec-plans/p.md
T plant
out="$(D check 2>&1)"; rc=$?
rc_is check_ignores_proposed_record 0 "$rc"
D accept no-eval >/dev/null
out="$(D check 2>&1)"; rc=$?
rc_is check_fails_after_accept 1 "$rc"
# The pattern holds a quote and a backslash; a hit proves it round-tripped.
check forbid_roundtrips_and_check_names_file "check: no-eval: src/b.sh:1" "$out"
nocheck check_ignores_docs_quoting_pattern "docs/exec-plans" "$out"
nocheck check_does_not_scan_decisions_dir "docs/decisions" "$out"
printf 'fine\n' > src/b.sh
rc_is check_passes_after_fix 0 "$(D check >/dev/null 2>&1; echo $?)"
# shellcheck disable=SC2016  # literal "$x" is the planted mistake
printf 'eval "$y"\n' > src/new-untracked.sh
out="$(D check 2>&1)"; rc=$?
rc_is check_catches_untracked_file 1 "$rc"
check check_untracked_names_file "src/new-untracked.sh" "$out"
rm -f src/new-untracked.sh
D propose --title "No todo" --source operator --forbid 'TODO' --paths src </dev/null >/dev/null
D accept no-todo >/dev/null
# shellcheck disable=SC2016  # literal "$x" is the planted mistake
printf 'TODO\neval "$z"\n' > src/c.sh
out="$(D check 2>&1)"
check check_reports_all_failures_first "check: no-eval:" "$out"
check check_reports_all_failures_second "check: no-todo:" "$out"
rm -f src/c.sh
D propose --title "Nowhere" --source operator --forbid x --paths 'nope/' </dev/null >/dev/null
D accept nowhere >/dev/null
rc_is check_paths_matching_nothing_exits_2 2 "$(D check >/dev/null 2>&1; echo $?)"
sed -i.bak 's/^paths: .*/paths: " , "/' "$(R nowhere)" && rm -f docs/decisions/*.bak
rc_is check_empty_paths_entries_exits_2 2 "$(/bin/bash "$TOOL" check >/dev/null 2>&1; echo $?)"
sed -i.bak -e 's/^paths: .*/paths: src/' -e 's/^forbid: .*/forbid: "a(("/' "$(R nowhere)" && rm -f docs/decisions/*.bak
rc_is check_bad_regex_exits_2 2 "$(D check >/dev/null 2>&1; echo $?)"
# shellcheck disable=SC2016  # the pattern must stay literal: that is the point of the test
sed -i.bak 's/^forbid: .*/forbid: "$(touch pwned)"/' "$(R nowhere)" && rm -f docs/decisions/*.bak
D check >/dev/null 2>&1
if [ ! -e pwned ] && [ ! -e src/pwned ]; then ok check_pattern_is_not_shell_evaluated; else bad check_pattern_is_not_shell_evaluated "pattern was executed"; fi

echo "paths"
rm -rf "$SANDBOX/it's here"; mkdir -p "$SANDBOX/it's here"; cd "$SANDBOX/it's here" || exit 1; git init -q .
D propose --title "Quote path" --source plan </dev/null >/dev/null
rc_is propose_in_quoted_path 0 $?

cd "$REPO_ROOT" || exit 1
rc_is lint_template_dir_clean 0 "$(bash "$TOOL" lint >/dev/null 2>&1; echo $?)"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: PASS checks=$PASS"
else
    echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
    exit 1
fi
