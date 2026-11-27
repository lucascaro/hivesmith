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
# Under a git hook these would point every command at the real repo.
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
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
printf '%s\n' "$(cat "$f3")" | sed "s/^status: proposed$/status: x$(printf '\033')[31my/" > "$SANDBOX/esc" && cp "$SANDBOX/esc" "$f3"
out="$(D lint 2>&1)"
nocheck lint_strips_control_chars "$(printf '\033')" "$out"
sed -i.bak 's/^status: .*$/status: proposed/' "$f3" && rm -f docs/decisions/*.bak

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
rc_is prune_apply_clears_supersedes_link "supersedes:" "$(grep '^supersedes:' docs/decisions/20200101-kept.md)"
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

echo "authorize"
# origin is a bare repo; records are read from what it holds right now, never
# from the worktree. Every negative case flips one condition of a passing
# fixture and asserts its own reason, so none can pass just because
# `authorize` is missing (that is exit 2, "unknown command").
O="$SANDBOX/o.git"
setup_auth() {
    rm -rf "$O" "$SANDBOX/c2"; git init -q --bare "$O"; git -C "$O" symbolic-ref HEAD refs/heads/main
    fresh; git checkout -q -b main; git remote add origin "$O"
    mkdir -p src docs/decisions; echo ok > src/a.txt; echo readme > docs/decisions/README.md
}
mkrec() {  # mkrec <slug> <status> [frontmatter line...]
    local slug="$1" st="$2" l; shift 2
    {
        printf -- '---\nid: %s\ntitle: "%s"\nstatus: %s\ndate: 2026-01-01\nsource: manual\norigin: ""\ntags:\nsupersedes:\nsuperseded_by:\n' "$slug" "$slug" "$st"
        [ "$st" = accepted ] && printf 'accepted: 2026-01-01\n'
        for l in "$@"; do printf '%s\n' "$l"; done
        printf -- '---\n\nbody\n'
    } > "docs/decisions/20260101-$slug.md"
}
push_base() { T base; git push -q origin main 2>/dev/null; }
pr_branch() { git checkout -q -b pr; }
pr_change() { pr_branch; echo change >> src/a.txt; T pr; }
AM() { D authorize merge --head "$(git rev-parse HEAD)" --pr-base main 2>&1; }
merge_fixture() { setup_auth; mkrec m accepted "authorizes: merge" "$@"; push_base; }

merge_fixture; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_accepted_on_origin_exit0 0 "$rc"
check authorize_merge_names_record "authorized: m (docs/decisions/20260101-m.md)" "$out"

setup_auth; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_no_record_escalates 1 "$rc"
check authorize_merge_no_record_says_why "escalate: no accepted record on origin/main authorizes merge" "$out"

setup_auth; mkrec m proposed "authorizes: merge"; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_proposed_record_escalates 1 "$rc"
check authorize_merge_proposed_says_why "no accepted record on origin/main authorizes merge" "$out"

setup_auth; mkrec m proposed "authorizes: merge"; push_base; pr_branch
mkrec m accepted "authorizes: merge"; echo change >> src/a.txt; T pr
out="$(AM)"; rc=$?
rc_is authorize_merge_branch_only_acceptance_escalates 1 "$rc"
check authorize_merge_branch_only_says_why "no accepted record on origin/main authorizes merge" "$out"

merge_fixture; pr_change
git clone -q "$O" "$SANDBOX/c2" 2>/dev/null
sed -i.bak 's/^status: accepted$/status: superseded/' "$SANDBOX/c2/docs/decisions/20260101-m.md" && rm -f "$SANDBOX/c2/docs/decisions/"*.bak
git -C "$SANDBOX/c2" -c user.name=t -c user.email=t@t commit -qam revoke && git -C "$SANDBOX/c2" push -q origin main 2>/dev/null
out="$(AM)"; rc=$?
rc_is authorize_merge_revoked_on_origin_escalates 1 "$rc"
check authorize_merge_revoked_says_why "no accepted record on origin/main authorizes merge" "$out"

setup_auth; push_base; pr_change
git clone -q "$O" "$SANDBOX/c2" 2>/dev/null
( cd "$SANDBOX/c2" && mkrec m accepted "authorizes: merge" && T accept && git push -q origin main 2>/dev/null )
out="$(AM)"; rc=$?
rc_is authorize_merge_stale_local_origin_ref_ignored 0 "$rc"

merge_fixture; pr_change; mkdir -p docs/decisions; echo x > docs/decisions/x.md; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_touching_decisions_escalates 1 "$rc"
check authorize_merge_touching_decisions_says_why "escalate: PR touches protected path docs/decisions/x.md" "$out"

merge_fixture; pr_change; mkdir -p scripts/decisions; echo x > scripts/decisions/y.sh; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_touching_decision_script_escalates 1 "$rc"
check authorize_merge_decision_script_says_why "protected path scripts/decisions/y.sh" "$out"

merge_fixture; pr_change; git mv docs/decisions/README.md docs/README2.md; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_move_out_of_decisions_escalates 1 "$rc"
check authorize_merge_move_says_why "protected path docs/decisions/README.md" "$out"

merge_fixture; pr_change; git rm -q docs/decisions/README.md; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_delete_in_decisions_escalates 1 "$rc"
check authorize_merge_delete_says_why "protected path docs/decisions/README.md" "$out"

merge_fixture; pr_change; mkdir -p SCRIPTS/Decisions; echo x > SCRIPTS/Decisions/z.sh; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_case_variant_protected_path_escalates 1 "$rc"
check authorize_merge_case_variant_says_why "protected path SCRIPTS/Decisions/z.sh" "$out"

merge_fixture; pr_change; printf 'x\n' > "docs/decisions/20260101-$(printf '\303\251').md"; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_non_ascii_decisions_path_escalates 1 "$rc"
check authorize_merge_non_ascii_says_why "escalate: PR touches protected path docs/decisions/" "$out"

merge_fixture; pr_change; echo dirty >> src/a.txt
out="$(AM)"; rc=$?
rc_is authorize_merge_dirty_worktree_escalates 1 "$rc"
check authorize_merge_dirty_says_why "escalate: worktree is not clean" "$out"

merge_fixture; pr_change; echo new > untracked.txt
out="$(AM)"; rc=$?
rc_is authorize_merge_untracked_file_escalates 1 "$rc"
check authorize_merge_untracked_says_why "escalate: worktree is not clean" "$out"

merge_fixture; pr_change
out="$(D authorize merge --head "$(git rev-parse main)" --pr-base main 2>&1)"; rc=$?
rc_is authorize_merge_head_mismatch_escalates 1 "$rc"
check authorize_merge_head_mismatch_says_why "escalate: HEAD is not the PR head" "$out"

merge_fixture; pr_change
out="$(D authorize merge --head "$(git rev-parse HEAD)" --pr-base dev 2>&1)"; rc=$?
rc_is authorize_merge_pr_base_not_default_escalates 1 "$rc"
check authorize_merge_pr_base_says_why "escalate: PR base dev is not the default branch main" "$out"

merge_fixture; mkrec f accepted 'forbid: "BADWORD"' 'paths: "src/"'; T rule; git push -q origin main 2>/dev/null
pr_branch; echo BADWORD >> src/a.txt; T pr
out="$(AM)"; rc=$?
rc_is authorize_merge_forbid_hit_escalates 1 "$rc"
check authorize_merge_forbid_hit_says_why "escalate: accepted record f forbid: check fails on the PR head" "$out"

# A committed forbidden pattern hidden from the worktree by index flags.
for flag in assume-unchanged skip-worktree; do
    merge_fixture; mkrec f accepted 'forbid: "BADWORD"' 'paths: "src/"'; T rule; git push -q origin main 2>/dev/null
    pr_branch; echo BADWORD >> src/a.txt; T pr
    git checkout -q HEAD~1 -- src/a.txt; git reset -q -- src/a.txt; git update-index --"$flag" src/a.txt
    out="$(AM)"; rc=$?
    rc_is "authorize_merge_forbid_hidden_by_${flag}_escalates" 1 "$rc"
    check "authorize_merge_forbid_hidden_by_${flag}_says_why" "src/a.txt:" "$out"
done

merge_fixture; mkrec f accepted 'forbid: "BADWORD"' 'paths: "nope/"'; T rule; git push -q origin main 2>/dev/null
pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_forbid_paths_match_nothing_exits_2 2 "$rc"
check authorize_merge_forbid_could_not_run_says_why "forbid: check of f could not run" "$out"

merge_fixture; pr_branch
out="$(AM)"; rc=$?
rc_is authorize_merge_empty_diff_exits_2 2 "$rc"
check authorize_merge_empty_diff_says_why "the PR changes no files" "$out"

merge_fixture; git checkout -q --orphan pr2; git rm -rqf . ; echo o > o.txt; T orphan
out="$(AM)"; rc=$?
rc_is authorize_merge_base_failure_exits_2 2 "$rc"
check authorize_merge_base_failure_says_why "no merge base with origin/main" "$out"

merge_fixture; pr_change; git remote set-url origin "$SANDBOX/missing.git"
out="$(AM)"; rc=$?
rc_is authorize_ls_remote_failure_exits_2 2 "$rc"
check authorize_ls_remote_failure_says_why "cannot resolve origin's default branch" "$out"

# ls-remote succeeds but the fetch itself dies: a pack-objects hook that fails
# (honoured only from protected config, hence GIT_CONFIG_GLOBAL for this call).
# origin must hold a commit the worktree lacks, or no pack is sent at all.
merge_fixture; pr_change
git clone -q "$O" "$SANDBOX/c2" 2>/dev/null
( cd "$SANDBOX/c2" && echo n > new.txt && T upstream && git push -q origin main 2>/dev/null )
printf '[uploadpack]\n\tpackObjectsHook = false\n' > "$SANDBOX/failpack.cfg"
out="$(GIT_CONFIG_GLOBAL="$SANDBOX/failpack.cfg" AM)"; rc=$?
rc_is authorize_fetch_failure_exits_2 2 "$rc"
check authorize_fetch_failure_says_why "fetch of origin/main failed" "$out"

# A concurrent fetch repoints FETCH_HEAD (here at the PR head) after ours.
mkdir -p "$SANDBOX/shim"
REAL_GIT="$(command -v git)"
cat > "$SANDBOX/shim/git" <<SHIM
#!/bin/bash
"$REAL_GIT" "\$@" || exit \$?
case " \$* " in *" fetch "*)
    printf '%s\\t\\tbranch pr\\n' "\$("$REAL_GIT" rev-parse HEAD)" > "\$("$REAL_GIT" rev-parse --git-path FETCH_HEAD)" ;;
esac
SHIM
chmod +x "$SANDBOX/shim/git"
merge_fixture; pr_change
out="$(PATH="$SANDBOX/shim:$PATH" AM)"; rc=$?
rc_is authorize_fetch_head_overwritten_escalates 1 "$rc"
check authorize_fetch_head_overwritten_says_why "FETCH_HEAD was overwritten" "$out"

merge_fixture; git push -q origin main:refs/heads/a+b 2>/dev/null; git -C "$O" symbolic-ref HEAD refs/heads/a+b; pr_change
out="$(AM)"; rc=$?
rc_is authorize_odd_default_branch_name_exits_2 2 "$rc"
check authorize_odd_default_branch_name_says_why "unexpected default branch name" "$out"

# base_records reads only regular, flat, dated record files from the base: a
# symlinked, nested or oddly named "accepted" record must not authorize.
setup_auth; mkdir -p notes; mkrec m accepted "authorizes: merge"; mv docs/decisions/20260101-m.md notes/rec.md
ln -s ../../notes/rec.md docs/decisions/20260101-s.md; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_symlinked_record_ignored 1 "$rc"
check authorize_merge_symlinked_record_says_why "no accepted record on origin/main authorizes merge" "$out"

setup_auth; mkrec m accepted "authorizes: merge"; mkdir -p docs/decisions/sub
mv docs/decisions/20260101-m.md docs/decisions/sub/20260101-m.md; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_nested_record_ignored 1 "$rc"

setup_auth; mkrec m accepted "authorizes: merge"; mv docs/decisions/20260101-m.md "docs/decisions/20260101-bad name.md"; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_odd_record_name_ignored 1 "$rc"

# origin/HEAD left pointing at a renamed-away master that still holds a merge
# record: authorize must follow the remote's real default (main), not the ref.
setup_auth; push_base
git checkout -q -b master; mkrec m accepted "authorizes: merge"; T old; git push -q origin master 2>/dev/null
git checkout -q main; git fetch -q origin; git symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/master
pr_change
out="$(AM)"; rc=$?
rc_is authorize_stale_origin_head_after_rename_uses_remote_default 1 "$rc"
check authorize_stale_origin_head_says_why "no accepted record on origin/main authorizes merge" "$out"

merge_fixture "merge_exclude: skills/"; pr_change; mkdir -p skills; echo x > skills/x.md; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_exclude_hit_escalates 1 "$rc"
check authorize_merge_exclude_says_why "protected path skills/x.md" "$out"

merge_fixture; mkrec e accepted "merge_exclude: skills/"; T rule; git push -q origin main 2>/dev/null
pr_change; mkdir -p skills; echo x > skills/x.md; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_exclude_from_other_record_applies 1 "$rc"
check authorize_merge_exclude_other_says_why "protected path skills/x.md" "$out"

setup_auth; mkrec m accepted "authorizes: plan, merge" "plan_paths: src/"; push_base; pr_change
rc_is authorize_tokens_plan_comma_space_merge_exit0 0 "$(AM >/dev/null; echo $?)"

setup_auth; mkrec m accepted "authorizes: nomerge"; push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_token_nomerge_escalates 1 "$rc"
check authorize_token_nomerge_says_why "no accepted record on origin/main authorizes merge" "$out"

setup_auth; mkrec m accepted "authorizes: merge"
LC_ALL=C sed -i.bak 's/$/'"$(printf '\r')"'/' docs/decisions/20260101-m.md && rm -f docs/decisions/*.bak
push_base; pr_change
out="$(AM)"; rc=$?
rc_is authorize_crlf_record_escalates 1 "$rc"
check authorize_crlf_says_why "no accepted record on origin/main authorizes merge" "$out"

# plan: passing fixture is S / approve / 8 / 0 / 0 / a file under plan_paths.
AP() {
    printf '%s\n' "$@" | D authorize plan --complexity "${CX:-S}" --verdict "${V:-approve}" \
        --confidence "${C:-8}" --must-fix "${MF:-0}" --conflicts "${CF:-0}" --files - 2>&1
}
plan_fixture() { setup_auth; mkrec p accepted "authorizes: plan" "plan_paths: src/, docs/notes.md"; push_base; }
plan_fixture
# Bad arguments are usage errors (64), never an escalation or an authorization.
sha="$(git rev-parse HEAD)"
rc_is authorize_merge_bad_head_exits_64 64 "$(D authorize merge --head XYZ --pr-base main >/dev/null 2>&1; echo $?)"
rc_is authorize_merge_missing_pr_base_exits_64 64 "$(D authorize merge --head "$sha" >/dev/null 2>&1; echo $?)"
rc_is authorize_merge_unknown_arg_exits_64 64 "$(D authorize merge --bogus >/dev/null 2>&1; echo $?)"
rc_is authorize_merge_head_without_value_exits_2 2 "$(D authorize merge --head >/dev/null 2>&1; echo $?)"
rc_is authorize_plan_bad_complexity_exits_64 64 "$(CX=X AP src/x.sh >/dev/null; echo $?)"
rc_is authorize_plan_bad_verdict_exits_64 64 "$(V=maybe AP src/x.sh >/dev/null; echo $?)"
rc_is authorize_plan_files_not_stdin_exits_64 64 "$(echo src/x.sh | D authorize plan --complexity S --verdict approve --confidence 8 --must-fix 0 --conflicts 0 --files foo >/dev/null 2>&1; echo $?)"
rc_is authorize_plan_unknown_arg_exits_64 64 "$(D authorize plan --bogus >/dev/null 2>&1; echo $?)"
out="$(AP src/x.sh docs/notes.md)"; rc=$?
rc_is authorize_plan_all_conditions_exit0 0 "$rc"
check authorize_plan_names_record "authorized: p (docs/decisions/20260101-p.md)" "$out"
rc_is authorize_plan_confidence_8_exit0 0 "$(C=8 AP src/x.sh >/dev/null; echo $?)"
out="$(CX=M AP src/x.sh)"; rc=$?
rc_is authorize_plan_complexity_m_escalates 1 "$rc"
check authorize_plan_complexity_says_why "escalate: complexity M; plan auto-approve covers S only" "$out"
out="$(V=revise AP src/x.sh)"; rc=$?
rc_is authorize_plan_verdict_revise_escalates 1 "$rc"
check authorize_plan_verdict_says_why "second opinion verdict is revise, not approve" "$out"
out="$(C=7 AP src/x.sh)"; rc=$?
rc_is authorize_plan_confidence_7_escalates 1 "$rc"
check authorize_plan_confidence_says_why "confidence 7 is below 8" "$out"
out="$(MF=1 AP src/x.sh)"; rc=$?
rc_is authorize_plan_must_fix_escalates 1 "$rc"
check authorize_plan_must_fix_says_why "has 1 must-fix item(s)" "$out"
out="$(CF=1 AP src/x.sh)"; rc=$?
rc_is authorize_plan_conflict_escalates 1 "$rc"
check authorize_plan_conflict_says_why "plan has 1 decision-record conflict(s)" "$out"
out="$(AP src/x.sh other/y.sh)"; rc=$?
rc_is authorize_plan_file_outside_scope_escalates 1 "$rc"
check authorize_plan_scope_says_why "first miss: other/y.sh" "$out"
out="$(AP src/x.sh docs/decisions/x.md)"; rc=$?
rc_is authorize_plan_touching_decisions_escalates 1 "$rc"
check authorize_plan_protected_says_why "escalate: plan touches protected path docs/decisions/x.md" "$out"
for d in docs/decisions docs/decisions/ docs Scripts; do
    out="$(AP src/x.sh "$d")"; rc=$?
    rc_is "authorize_plan_dir_or_parent_escalates[$d]" 1 "$rc"
    check "authorize_plan_dir_or_parent_says_why[$d]" "protected path $d" "$out"
done
out="$(AP src/x.sh ./scripts/decisions/x)"; rc=$?
rc_is authorize_dot_slash_protected_path_escalates 1 "$rc"
check authorize_dot_slash_says_why "protected path scripts/decisions/x" "$out"
out="$(D authorize plan --complexity S --verdict approve --confidence 9 --must-fix 0 --conflicts 0 --files - </dev/null 2>&1)"; rc=$?
rc_is authorize_plan_empty_files_exits_2 2 "$rc"
check authorize_plan_empty_files_says_why "empty file list" "$out"
out="$(D authorize plan --probe 2>&1)"; rc=$?
rc_is authorize_plan_probe_exit0_with_plan_record 0 "$rc"
check authorize_plan_probe_names_record "authorized: p" "$out"
rc_is authorize_rejects_dotdot_path_64 64 "$(AP src/../docs/decisions/x >/dev/null 2>&1; echo $?)"
rc_is authorize_rejects_absolute_path_64 64 "$(AP /etc/passwd >/dev/null 2>&1; echo $?)"
rc_is authorize_rejects_pathspec_magic_64 64 "$(AP ':(top)src/x' >/dev/null 2>&1; echo $?)"
out="$(C=abc AP src/x.sh)"; rc=$?
rc_is authorize_bad_number_exits_64 64 "$rc"
check authorize_bad_number_says_why "--confidence must be a non-negative integer" "$out"
out="$(D authorize deploy 2>&1)"; rc=$?
rc_is authorize_unknown_stop_exits_64 64 "$rc"
check authorize_unknown_stop_says_why "unknown stop: deploy" "$out"

merge_fixture
out="$(AP src/x.sh)"; rc=$?
rc_is authorize_plan_merge_only_record_escalates 1 "$rc"
check authorize_plan_merge_only_says_why "no accepted record on origin/main authorizes plan" "$out"
out="$(D authorize plan --probe 2>&1)"; rc=$?
rc_is authorize_plan_probe_escalates_without 1 "$rc"
check authorize_plan_probe_without_says_why "authorizes plan" "$out"

setup_auth; mkrec p accepted "authorizes: plan" "plan_paths: skills/"; mkrec e accepted "merge_exclude: skills/"; push_base
rc_is authorize_plan_merge_exclude_does_not_apply 0 "$(AP skills/x.md >/dev/null; echo $?)"

# Regressions from review pass 1 on PR #103.
setup_auth; mkrec p accepted "authorizes: plan,merge" "plan_paths: src/"; push_base
rc_is authorize_plan_comma_no_space_merge_exit0 0 "$(AP src/x.sh >/dev/null; echo $?)"
plan_fixture
out="$(printf 'src/x.sh\ndocs/decisions/x.md' | D authorize plan --complexity S --verdict approve \
    --confidence 9 --must-fix 0 --conflicts 0 --files - 2>&1)"; rc=$?
rc_is authorize_plan_unterminated_last_line_checked 1 "$rc"
check authorize_plan_unterminated_says_why "protected path docs/decisions/x.md" "$out"
merge_fixture "merge_exclude: svc/*/secrets/"; pr_change; mkdir -p svc/a/secrets; echo x > svc/a/secrets/k; T more
out="$(AM)"; rc=$?
rc_is authorize_merge_exclude_star_in_prefix_escalates 1 "$rc"
check authorize_merge_exclude_star_says_why "protected path svc/a/secrets/k" "$out"
merge_fixture "merge_exclude: src/$(printf '\r')"; pr_change
out="$(AM)"; rc=$?
rc_is authorize_merge_exclude_crlf_still_applies 1 "$rc"
check authorize_merge_exclude_crlf_says_why "protected path src/a.txt" "$out"

echo "lint (authorize keys)"
setup_auth; mkrec a accepted "authorizes: nomerge"
check lint_rejects_bad_authorizes "unknown authorizes token 'nomerge'" "$(D lint 2>&1)"
setup_auth; mkrec a accepted "authorizes: plan"
check lint_requires_plan_paths "authorizes: plan without plan_paths:" "$(D lint 2>&1)"
setup_auth; mkrec a accepted "authorizes: plan" "plan_paths: *"
check lint_rejects_whole_repo_plan_paths "covers the whole repo" "$(D lint 2>&1)"
setup_auth; mkrec a accepted "merge_exclude: :(top)x"
check lint_rejects_magic_in_merge_exclude "merge_exclude: entry ':(top)x' must be a repo-relative glob" "$(D lint 2>&1)"
setup_auth; mkrec a accepted "merge_exclude: skills/$(printf '\r')"
check lint_rejects_cr_in_merge_exclude "merge_exclude: carriage return in value" "$(D lint 2>&1)"
setup_auth; mkrec a accepted "authorizes: plan, merge" "plan_paths: src/" "merge_exclude: skills/"
rc_is lint_accepts_authorize_keys 0 "$(D lint >/dev/null 2>&1; echo $?)"

cd "$REPO_ROOT" || exit 1
rc_is lint_template_dir_clean 0 "$(bash "$TOOL" lint >/dev/null 2>&1; echo $?)"

echo
if [ "$FAIL" -eq 0 ]; then
    echo "RESULT: PASS checks=$PASS"
else
    echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
    exit 1
fi
