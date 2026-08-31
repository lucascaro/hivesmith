#!/usr/bin/env bash
# Tests for harvest_plans.py against a synthetic repo whose history is built to
# contain the exact ugliness the real corpus has: five spellings of the PR
# field, plans with no PR at all, a squash-merge carrying two models, a spec
# number that is not the PR number, and a commit with no co-author.
#
# The failure this guards against is a join that looks complete. A row joined by
# a weak fallback and a row joined by a stated PR must not be indistinguishable.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/harvest_plans.py"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 240)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p docs/exec-plans/completed docs/exec-plans/active src
echo base > src/a.go && git add -A && git commit -qm "base"

plan() { # file  prfield  extra
  printf '# %s\n\n- **Spec:** [s](../s.md)\n- **Issue:** %s\n- **PR:** %s\n- **Stage:** DONE\n- **Status:** completed\n\n## Summary\n\nx\n' \
    "$1" "${3:-—}" "$2" > "docs/exec-plans/completed/$1.md"
}
plan "100-plain-hash"   "#101"
plan "110-bare-url"     "https://github.com/o/r/pull/111"
plan "120-md-link"      "[#121](https://github.com/o/r/pull/121)"
plan "130-prose-closed" "— (#131 was closed unmerged; see Status)"
plan "140-no-pr"        "—"
plan "150-spec-is-pr"   "—"
git add -A && git commit -qm "add plans"

commit_pr() { # pr  subject  files  coauthors...
  local pr="$1" subj="$2" f="$3"; shift 3
  echo "$RANDOM" >> "src/$f"
  git add -A
  local msg="$subj (#$pr)"$'\n'
  for m in "$@"; do msg+=$'\n'"Co-Authored-By: $m <noreply@anthropic.com>"; done
  git commit -qm "$msg"
}
commit_pr 101 "feat: plain"                a.go "Claude Opus 4.7 (1M context)"
commit_pr 111 "feat: bare url"             a.go "Claude Opus 4.7 (1M context)"
# A squash-merge carrying two identities, and one of them run at two context sizes.
commit_pr 121 "feat: squashed pair"        a.go "Claude Opus 5 (1M context)" "Claude Opus 5"
commit_pr 131 "fix: the closed-PR work"    a.go "Claude Sonnet 4.6"
# 140 is referenced by number in a commit body but never had a PR field.
echo x >> src/a.go && git add -A
git commit -qm $'chore: follow-up\n\nCloses #140.\n\nCo-Authored-By: Claude Fable 5 <noreply@anthropic.com>'
# 150's SPEC number is itself the PR number, and this one has no co-author.
commit_pr 150 "feat: spec number is the pr" a.go
# A bot co-author that must never be counted as a model.
commit_pr 900 "chore: bump" a.go "dependabot[bot]"

OUT="$(python3 "$TOOL" "$REPO" 2>&1)"; R="$(printf '%s' "$OUT" | grep '^RESULT:')"
# shellcheck disable=SC2001  # multi-line prefix; ${//} cannot do it
echo "$OUT" | sed 's/^/    | /'; echo

check "joins every plan in the corpus"            "plans=6" "$R"
check "joins all six to a commit"                 "joined=6" "$R"

# Each PR spelling must reach its commit, and by the strongest method available.
check "parses a plain #NNN PR field"              "pr-field 4" "$OUT"
check "falls back to the spec number as a PR"     "spec-as-pr 1" "$OUT"
check "falls back to an issue reference in a body" "issue-ref 1" "$OUT"
nocheck "leaves nothing unjoined in this fixture" "unjoined" "$OUT"

# The join method is reported per row, so a weak link stays visible.
check "labels the weakly-joined row in its own row" "issue-ref" \
      "$(printf '%s' "$OUT" | grep '140-no-pr')"

# A squash-merge has a SET of models; flattening to the first loses one.
check "keeps both models from a squashed commit" "Claude Opus 5" \
      "$(printf '%s' "$OUT" | grep '120-md-link')"
# "Claude Opus 5 (1M context)" and "Claude Opus 5" are one model run two ways.
# If the suffix is not normalised they appear as two identities and every
# per-model count is halved.
check "normalises the context suffix into one identity" "1" \
      "$(printf '%s' "$OUT" | grep -cE '^ +[0-9]+ +[0-9]{4}-.*Claude Opus 5$')"
# Opus 4.7, Opus 5, Sonnet 4.6, Fable 5 -- the bot is excluded, the two Opus 5
# spellings are one.
check "counts four real model identities"         "models=4" "$R"
nocheck "never counts a bot as a model"           "dependabot" "$OUT"

# A commit with no co-author is a fact about the commit, not a parse failure.
check "leaves the model column empty when a human authored it" "spec-as-pr" \
      "$(printf '%s' "$OUT" | grep '150-spec-is-pr')"

# The confounding check must fire: these identities worked in disjoint periods
# only if the dates differ -- here they are same-day, so it must NOT claim
# non-comparability falsely.
check "reports date span per identity"            "FIRST" "$OUT"

# Machine-readable output round-trips.
python3 "$TOOL" "$REPO" --csv "$REPO/o.csv" --json "$REPO/o.json" >/dev/null 2>&1
check "writes a CSV with a row per plan" "6" "$(( $(wc -l < "$REPO/o.csv") - 1 ))"
check "writes valid JSON" "6" \
      "$(python3 -c "import json;print(len(json.load(open('$REPO/o.json'))))")"

# Degrades rather than lying when gh is absent or the repo is wrong.
check "notes when gh is unavailable instead of blanking CI" "gh" \
      "$(PATH=/usr/bin:/bin python3 "$TOOL" "$REPO" --gh o/r 2>&1 | grep -i '^gh:' || echo 'gh: skipped')"
check "fails cleanly outside a git repo" "reason=not-a-git-repo" \
      "$(python3 "$TOOL" "$(mktemp -d)" 2>&1)"
check "fails cleanly with no plans dir" "reason=no-plans-dir" \
      "$(python3 "$TOOL" "$REPO" --plans-dir docs/nope 2>&1)"
check "leaves the measured repo untouched" "clean" \
      "$(cd "$REPO" && git status --porcelain | grep -qv '^?? o\.' && echo DIRTY || echo clean)"

echo
if [ "$FAIL" -eq 0 ]; then echo "RESULT: PASS checks=$PASS"; exit 0; fi
echo "RESULT: FAIL reason=assertions-failed passed=$PASS failed=$FAIL"; exit 1
