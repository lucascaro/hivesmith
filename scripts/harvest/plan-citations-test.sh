#!/usr/bin/env bash
# Tests for plan_citations.py, built on a throwaway git repo with a known answer.
#
# The checker's every historical bug was a false FINDING -- blaming a plan for
# the tool's own confusion about which tree to read. So most of these fix a
# specific wrong verdict, and each names the failure it prevents.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$HERE/plan_citations.py"
PASS=0; FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ # name  expected-substring  actual
  if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 200)"; fi
}

REPO="$(mktemp -d)"; trap 'rm -rf "$REPO"' EXIT
cd "$REPO" || exit 1
git init -q . && git config user.email t@t && git config user.name t

mkdir -p deep/nested/src docs/exec-plans/active docs/exec-plans/completed
seq 1 50 | sed 's/^/line /' > deep/nested/src/view.js
seq 1 10 | sed 's/^/line /' > short.go
git add -A && git commit -qm "base"

# Plan A: written now. One exact hit, one suffix-only hit, one over-range,
# one path that names a directory and does not exist, one bare dependency name.
cat > docs/exec-plans/active/1-a.md <<'MD'
# Plan A
- `deep/nested/src/view.js:10` exact and in range
- `src/view.js:20` cited relative to a section; unique suffix
- `short.go:900` past the end of the file
- `pkg/gone/absent.go:3` names a directory, exists nowhere
- `state.go:477` a dependency's file, quoted in prose
- `future/added-later.go:2` does not exist yet, but will
MD
git add -A && git commit -qm "write plan A"
PLAN_A_COMMIT=$(git rev-parse --short HEAD)

# The code moves on: view.js is deleted, and the plan's future file arrives.
mkdir -p future && seq 1 5 | sed 's/^/line /' > future/added-later.go
git rm -q -r deep && git add -A && git commit -qm "refactor: delete view.js, add future file"

# A bulk docs edit touches plan A long after it was written. This is the commit
# that broke 14 real plans: last-touch resolution would measure plan A here.
printf '\n<!-- hygiene pass -->\n' >> docs/exec-plans/active/1-a.md
git add -A && git commit -qm "docs: hygiene across plans"

# Moving a plan to completed/ is a rename; --follow must see through it.
git mv -f docs/exec-plans/active/1-a.md docs/exec-plans/completed/1-a.md
git commit -qm "docs: complete plan A"

OUT="$(python3 "$CHECKER" "$REPO" --verbose 2>&1)"
RESULT="$(printf '%s' "$OUT" | grep '^RESULT:')"

echo "$OUT" | sed 's/^/    | /'
echo

# 1-2. The core arithmetic. Four citations resolve to a file that existed when
#      the plan was written: view.js twice (exact, suffix), short.go, and the
#      absent path. Two are ok. The dependency name and the future file are
#      excluded, so they never touch the denominator.
check "counts only citations that were checkable claims" "citations=4" "$RESULT"
check "accuracy is over that denominator (2 of 4)"       "accuracy=50.0" "$RESULT"

# 3. Bug 1: resolving at the bulk-edit commit would find view.js deleted and
#    report two phantom misses.
check "survives a docs-hygiene commit that rewrote the plan later" "miss=1" "$RESULT"

# 4. ...and a rename into completed/ must not reset the authoring date either.
#    Asserted against the helper directly: it must return the commit that wrote
#    the plan, not the hygiene commit and not the move.
AUTHORED="$(python3 -c "
import sys; sys.path.insert(0, '$HERE')
from pathlib import Path
import importlib.util
spec = importlib.util.spec_from_file_location('pc', '$CHECKER')
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
print(m.authoring_commit(Path('$REPO'), 'docs/exec-plans/completed/1-a.md')[:7])
" 2>&1)"
check "follows the rename into completed/ back to the authoring commit" \
      "$PLAN_A_COMMIT" "$AUTHORED"

# 5. Bug 2: a section-relative path is shorthand, not a fabrication.
check "resolves a section-relative path by unique suffix" "1 matched by unique suffix" "$OUT"

# 6. Bug 3: a bare dependency filename is not evidence of anything.
check "excludes a bare unresolvable name instead of blaming it" "unresolvable 1" "$OUT"
check "and does not report it as a miss" "no-miss" \
      "$(printf '%s' "$OUT" | grep -q 'miss.*state\.go' && echo blamed || echo no-miss)"

# 7. Bug 4: citing a file the plan intends to create is the plan working.
check "reports a not-yet-created file as planned, not missing" "planned=1" "$RESULT"

# 8. A range past the end of a real file is a genuine finding.
check "catches an out-of-bounds line range" "range=1" "$RESULT"

# 9. A path naming a directory that never existed is a genuine finding.
check "catches a path that exists at no point in history" "pkg/gone/absent.go" "$OUT"

# 10. Drift mode measures the other thing and must disagree here. At HEAD both
#     view.js citations are gone (2 misses) on top of the absent path, while the
#     planned file now exists and counts as ok -- the two modes answering two
#     different questions about one plan.
DRIFT="$(python3 "$CHECKER" "$REPO" --at head 2>&1 | grep '^RESULT:')"
check "drift mode reads HEAD and finds the deleted file" "miss=3" "$DRIFT"
check "drift mode has nothing left to call planned"      "planned=0" "$DRIFT"

# 11-12. Refuses to invent a number when there is nothing to measure.
check "fails cleanly outside a git repo" "reason=not-a-git-repo" \
      "$(python3 "$CHECKER" "$(mktemp -d)" 2>&1)"
check "fails cleanly when no plans exist" "reason=no-plans" \
      "$(python3 "$CHECKER" "$REPO" --plans-dir docs/nothing-here 2>&1)"

# 13. Never mutates the repo it measures.
check "leaves the measured repo untouched" "clean" \
      "$(cd "$REPO" && [ -z "$(git status --porcelain)" ] && echo clean || echo DIRTY)"

echo
if [ "$FAIL" -eq 0 ]; then echo "RESULT: PASS checks=$PASS"; exit 0; fi
echo "RESULT: FAIL reason=assertions-failed passed=$PASS failed=$FAIL"; exit 1
