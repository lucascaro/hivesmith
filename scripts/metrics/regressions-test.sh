#!/usr/bin/env bash
# Tests for regressions.py against a synthetic repo built to contain the two
# things that break a naive implementation: changesets that have been DELETED
# by a release (the declaration survives only in history), and PR numbers that
# arrive in three different commit shapes.
#
# The failure being guarded against is a report that says "0 regressions" and
# is believed. Zero-because-nobody-declared and zero-because-none-happened must
# never look the same.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/regressions.py"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 300)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p .changesets
echo "# changesets" > .changesets/README.md
git add -A && git commit -qm "base" --date "2026-01-01T00:00:00"

# cs <id> <type> <subject> [regression_of]
cs() {
  local id="$1" type="$2" subject="$3" reg="${4:-}"
  { echo "---"
    echo "issue: $id"
    echo "type: $type"
    echo "bump: patch"
    [[ -n "$reg" ]] && echo "regression_of: $reg"
    echo "---"
    echo "- **Change $id.**"
  } > ".changesets/0$id-c$id.md"
  git add -A
  GIT_AUTHOR_DATE="$5" GIT_COMMITTER_DATE="$5" git commit -q -m "$subject"
}

# A squash merge: PR number at the end of the subject.
cs 10 added "feat: the feature that broke (#10)"                    ""   "2026-01-02T00:00:00"
# A merge commit: PR number at the front. This repo is squash-only, but
# hivesmith scaffolds projects that are not.
cs 11 added "Merge pull request #11 from x/y"                       ""   "2026-01-03T00:00:00"
# A squash whose long conventional-commit subject pushed "(#12)" to the body.
{ echo "---"; echo "issue: 12"; echo "type: added"; echo "bump: patch"; echo "---"; echo "- **c12.**"; } > .changesets/012-c12.md
git add -A
GIT_AUTHOR_DATE="2026-01-04T00:00:00" GIT_COMMITTER_DATE="2026-01-04T00:00:00" \
  git commit -q -m "feat(a-very-long-scope-name): a subject long enough that the number wrapped" -m "(#12)"
# The fix, declaring what it undoes.
cs 13 fixed "fix: undo the damage (#13)"                            10   "2026-01-09T00:00:00"
# A recent merge — too new to call clean.
cs 14 added "feat: shipped moments ago (#14)"                       ""   "$(date -u +%Y-%m-%dT%H:%M:%S)"

out="$(python3 "$TOOL" . --soak-days 30 2>&1)"
check test_squash_pr_recovered            "#10 <- #13" "$out"
check test_regressed_count_is_1           "regressed 1" "$out"
check test_time_to_detect_is_7_days       "(7d)"        "$out"
check test_recent_merge_is_unobserved     "unobserved 1" "$out"
check test_result_line_present            "RESULT: PASS" "$out"
# 10, 11, 12, 13 are old enough to have been judged; 14 is not.
check test_all_three_pr_shapes_recovered  "merged PRs 5" "$out"

# Delete every changeset the way release.sh does. The declarations must survive.
find .changesets -name '*.md' ! -name 'README.md' -delete
git add -A && git commit -qm "chore: release 1.0.0"
out2="$(python3 "$TOOL" . --soak-days 30 2>&1)"
check test_survives_release_deletion      "#10 <- #13" "$out2"
check test_merged_count_survives_deletion "merged PRs 5" "$out2"
git revert -q --no-edit HEAD >/dev/null 2>&1

# A repo where nobody declares anything must not read as "all clean".
out3="$(python3 "$TOOL" . --soak-days 3650 2>&1)"
check test_long_soak_makes_everything_unobserved "clean 0" "$out3"

# A repo where nobody ever declared anything must say so out loud, rather than
# printing a reassuring "0 regressions". This needs its own corpus: the repo
# above has a real declaration in it.
BARE="$(mktemp -d)"
(
  cd "$BARE" || exit 1
  git init -q . && git config user.email t@t && git config user.name t
  mkdir -p .changesets && echo "# c" > .changesets/README.md
  git add -A && git commit -qm base
  printf -- '---\nissue: 1\ntype: added\nbump: patch\n---\n- x\n' > .changesets/001-a.md
  git add -A
  GIT_AUTHOR_DATE="2026-01-02T00:00:00" GIT_COMMITTER_DATE="2026-01-02T00:00:00" \
    git commit -q -m "feat: something (#1)"
)
out4="$(python3 "$TOOL" "$BARE" --soak-days 30 2>&1)"
check test_zero_declared_says_so    "it means none were declared" "$out4"
nocheck test_zero_declared_is_not_called_clean_only "regressed 1" "$out4"
rm -rf "$BARE"

# --- validate-changed: FORMAT only, never absence ---------------------------
# Do NOT hardcode "main": git's default branch name differs by version and by
# config, and a wrong base ref used to make validate-changed report PASS on an
# empty diff. That is now a hard failure in the tool, and this captures the
# real name so the suite exercises the intended path.
BASE_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
git checkout -qb topic
v() { python3 "$TOOL" . --validate-changed "$BASE_BRANCH" topic 2>&1; }

cs 20 fixed "fix: no declaration at all (#20)" "" "2026-02-01T00:00:00"
out="$(v)"; rc=$?
if [[ $rc -eq 0 ]]; then ok test_absence_is_never_a_failure
else bad test_absence_is_never_a_failure "exit $rc: $out"; fi

printf -- '---\nissue: 21\ntype: added\nbump: patch\nregression_of: 10\n---\n- x\n' > .changesets/021-c21.md
git add -A && git commit -qm "chore: bad type"
out="$(v)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q "requires type: fixed"; then
  ok test_regression_of_on_non_fixed_is_rejected
else bad test_regression_of_on_non_fixed_is_rejected "exit $rc: $out"; fi
git rm -q .changesets/021-c21.md && git commit -qm "chore: drop"

printf -- '---\nissue: 22\ntype: fixed\nbump: patch\nregression_of: unknown\n---\n- x\n' > .changesets/022-c22.md
git add -A && git commit -qm "chore: prose declaration"
out="$(v)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q "omit the field rather than guessing"; then
  ok test_prose_declaration_is_rejected
else bad test_prose_declaration_is_rejected "exit $rc: $out"; fi
git rm -q .changesets/022-c22.md && git commit -qm "chore: drop"

printf -- '---\nissue: 23\ntype: fixed\nbump: patch\nregression_of: 10, 11\n---\n- x\n' > .changesets/023-c23.md
git add -A && git commit -qm "chore: list declaration"
out="$(v)"; rc=$?
if [[ $rc -eq 0 ]]; then ok test_comma_list_is_accepted
else bad test_comma_list_is_accepted "exit $rc: $out"; fi

out="$(python3 "$TOOL" . --validate-changed no-such-ref topic 2>&1)"; rc=$?
if [[ $rc -ne 0 ]] && printf '%s' "$out" | grep -q "unresolvable-ref"; then
  ok test_unresolvable_ref_fails_loudly
else
  bad test_unresolvable_ref_fails_loudly "a bad base ref must not report PASS (exit $rc: $out)"
fi

echo
if [[ "$FAIL" -gt 0 ]]; then
  echo "RESULT: FAIL reason=checks-failed failed=$FAIL passed=$PASS"
  exit 1
fi
echo "RESULT: PASS checks=$PASS"
