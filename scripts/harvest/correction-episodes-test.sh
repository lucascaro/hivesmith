#!/usr/bin/env bash
# Tests for correction_episodes.py on a synthetic history with a known answer.
#
# Every check here corresponds to a wrong verdict this tool actually produced
# against hive before it was fixed. The escaped-defect rate read 65%, then 49%,
# then 40% as each was corrected -- so the tests are the record of why the
# number is what it is.
#
# RESULT: PASS checks=<n>  /  RESULT: FAIL reason=<slug>
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$HERE/correction_episodes.py"
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  ok    %s\n' "$1"; }
bad(){ FAIL=$((FAIL+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
check(){ if printf '%s' "$3" | grep -qF -- "$2"; then ok "$1"; else bad "$1" "wanted '$2' in: $(printf '%s' "$3" | tr '\n' '|' | tail -c 260)"; fi; }
nocheck(){ if printf '%s' "$3" | grep -qF -- "$2"; then bad "$1" "did not want '$2'"; else ok "$1"; fi; }

R="$(mktemp -d)"; trap 'rm -rf "$R"' EXIT
cd "$R" || exit 1
git init -q . && git config user.email t@t && git config user.name t
mkdir -p src docs
D() { git commit -q --date="$1T12:00:00" -m "$2"; }

# --- the origin: a feature with a real defect in it, plus an import line ---
printf 'import { helper } from "./helper.js";\n' > src/feature.js
for i in $(seq 1 20); do echo "  const v$i = compute($i);" >> src/feature.js; done
printf 'v1 released\nv2 pending\n' > docs/CHANGELOG.md
git add -A; D 2026-01-05 "feat: the feature that carries the defect"
ORIGIN=$(git rev-parse --short HEAD)

# --- a substantive correction: rewrites 10 of the feature's own lines ---
python3 - <<'PY'
p='src/feature.js'; L=open(p).read().splitlines()
for i in range(1,11): L[i]=f"  const v{i} = computeFixed({i});"
open(p,'w').write("\n".join(L)+"\n")
PY
git add -A; D 2026-01-15 "fix: correct the computation the feature got wrong"

# --- incidental churn: touches ONE line, and it is an import ---
sed -i.bak '1s|.*|import { helper, other } from "./helper.js";|' src/feature.js && rm -f src/feature.js.bak
git add -A; D 2026-01-16 "fix: widen an import while fixing something else"

# --- additive-only fix: adds a guard, deletes nothing ---
printf 'if (!v1) return;\n' >> src/feature.js
git add -A; D 2026-01-17 "fix: add a missing guard"

# --- a fix landing outside the window ---
python3 - <<'PY'
p='src/feature.js'; L=open(p).read().splitlines()
for i in range(11,16): L[i]=f"  const v{i} = computeLate({i});"
open(p,'w').write("\n".join(L)+"\n")
PY
git add -A; D 2026-09-20 "fix: a correction long after the window closed"

# --- noise-only fix: REPLACES a changelog line, so it does have a pre-image.
#     It must still never open an episode: the path is stripped before blame.
#     (An append would land in additive-only instead and prove nothing.)
sed -i.bak '2s|.*|v2 shipped|' docs/CHANGELOG.md && rm -f docs/CHANGELOG.md.bak
git add -A; D 2026-01-18 "fix: changelog wording"

OUT="$(python3 "$TOOL" "$R" --window 90 2>&1)"; RES="$(printf '%s' "$OUT" | grep '^RESULT:')"
# shellcheck disable=SC2001  # multi-line prefix; ${//} cannot do it
echo "$OUT" | sed 's/^/    | /'; echo

check "counts every correction-typed commit"        "fixes=5" "$RES"
check "attributes the substantive fix to its origin" "$ORIGIN" "$OUT"

# The bug that ranked a code-movement refactor first on hive.
check "drops the one-line import edit as churn"      "incidental=1" "$RES"

# A fix that only adds lines has no author to blame and must not be guessed at.
check "reports an additive-only fix as unattributable" "additive-only 1" "$OUT"
# A docs-only fix is not a code correction and must not share a bucket with one.
check "separates a noise-only fix from an additive one" "noise-only 1" "$OUT"

# Noise paths are excluded before blame runs, so a CHANGELOG-only fix is additive-only too.
nocheck "never opens an episode from a noise-only path" "changelog wording" \
        "$(printf '%s' "$OUT" | grep -A30 'ORIGIN')"

# Window discipline: a correction nine months later is not this feature's fault.
check "ignores a correction outside --window"        "episodes=1" "$RES"
WIDE="$(python3 "$TOOL" "$R" --window 400 2>&1 | grep '^RESULT:')"
check "and counts it once the window is widened"     "episodes=2" "$WIDE"

# The rate's denominator must be commits the scan actually considered.
check "reports the rate against scanned commits"     "in the scanned window" "$OUT"

# min-lines is a real lever, not a constant.
STRICT="$(python3 "$TOOL" "$R" --window 90 --min-lines 20 2>&1 | grep '^RESULT:')"
check "a higher --min-lines drops the substantive one too" "episodes=0" "$STRICT"

# The caveat is load-bearing and must survive refactors of the output.
check "always prints the detection-bias caveat"      "defects FOUND" "$OUT"

check "fails cleanly outside a git repo"             "reason=not-a-git-repo" \
      "$(python3 "$TOOL" "$(mktemp -d)" 2>&1)"
check "fails cleanly when nothing matches --fix-types" "reason=no-fix-commits" \
      "$(python3 "$TOOL" "$R" --fix-types nosuchtype 2>&1)"
check "leaves the measured repo untouched"           "clean" \
      "$(cd "$R" && [ -z "$(git status --porcelain)" ] && echo clean || echo DIRTY)"

echo
if [ "$FAIL" -eq 0 ]; then echo "RESULT: PASS checks=$PASS"; exit 0; fi
echo "RESULT: FAIL reason=assertions-failed passed=$PASS failed=$FAIL"; exit 1
