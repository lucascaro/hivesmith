#!/usr/bin/env bash
# Self-test for check-changeset.sh, run in CI before the gate judges a PR.
#
# The exempt list is the part that can quietly go wrong: too narrow and
# docs PRs need a bypass again, too wide and a user-visible change ships
# with no changelog entry. Builds a throwaway repo because the gate reads `git diff`.
set -euo pipefail
cd "$(dirname "$0")/.."
GATE="$PWD/scripts/check-changeset.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

git -C "$tmp" init -q -b trunk
git -C "$tmp" config user.email t@example.com
git -C "$tmp" config user.name test
git -C "$tmp" config commit.gpgsign false
g() { git -C "$tmp" "$@"; }
edit() { for p in "$@"; do mkdir -p "$tmp/$(dirname "$p")"; echo "$RANDOM" >> "$tmp/$p"; done; }

edit README.md src/app.ts .changesets/old.md
g add -A; g commit -qm base
base="$(g rev-parse HEAD)"

start() { g reset -q --hard "$base"; }
# check <want-exit> <description> [BASE HEAD args; default: base HEAD]
check() {
  local want="$1" desc="$2" got=0
  shift 2
  g add -A; g commit -qm "$desc" --allow-empty
  [[ $# -gt 0 ]] || set -- "$base" HEAD
  ( cd "$tmp" && "$GATE" "$@" >/dev/null 2>&1 ) || got=$?
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $desc (exit $got, want $want)" >&2
    exit 1
  fi
  echo "ok: $desc"
}

# --- Mechanics: hold for any EXEMPT list. ---
start; edit src/app.ts;                  check 1 "app code without a changeset is refused"
start; edit src/app.ts .changesets/x.md; check 0 "app code with a changeset passes"
start; edit src/app.ts .changesets/README.md
check 1 "changesets README alone is not a changeset"
start; edit src/app.ts; g rm -q .changesets/old.md
check 1 "deleting a changeset is not adding one"
start; edit src/app.ts .changesets/sub/x.md
check 1 "a nested changeset is not read by the changelog, so it does not count"
start; mkdir -p "$tmp/docs"; g mv src/app.ts docs/app.ts
check 1 "moving app code into an exempt directory is refused"
start; edit src/app.ts; g add -A; g commit -qm x
( cd "$tmp" && "$GATE" "$base" 0000000000000000000000000000000000000000 >/dev/null 2>&1 ) && rc=0 || rc=$?
if [[ "$rc" == 0 || "$rc" == 1 ]]; then echo "FAIL: unknown revision must be a gate error, got exit $rc" >&2; exit 1; fi
echo "ok: an unknown revision is a gate error, not a missing changeset"
start; edit docs/x.md src/app.ts;        check 1 "a docs change mixed with app code is refused"
start; g checkout -q -b feature; edit src/app.ts; g add -A; g commit -qm f
( cd "$tmp" && "$GATE" >/dev/null 2>&1 ) && rc=0 || rc=$?
g checkout -q trunk
if [[ "$rc" != 0 ]]; then echo "FAIL: no default branch must warn and pass, got exit $rc" >&2; exit 1; fi
g branch -q -m trunk master
g checkout -q feature
( cd "$tmp" && "$GATE" >/dev/null 2>&1 ) && rc=0 || rc=$?
g checkout -q master; g branch -q -D feature
if [[ "$rc" != 1 ]]; then echo "FAIL: hook mode must find master as the default branch, got exit $rc" >&2; exit 1; fi
echo "ok: hook mode warns without a default branch and gates against master"

# --- EXEMPT list: these cases mirror the default EXEMPT list in
# check-changeset.sh. When you tune that list for your project, edit the
# matching cases here too, or CI fails on every PR. ---
start; edit docs/product-specs/1.md docs/exec-plans/active/1.md; check 0 "specs and exec plans are exempt"
start; edit features/BACKLOG.md features/active/1.md;           check 0 "feature files are exempt"
start; edit AGENTS.md CONTRIBUTING.md;                          check 0 "root markdown is exempt"
start; edit .github/workflows/ci.yml;                           check 0 "CI config is exempt"
start; edit scripts/release.sh;                                 check 0 "scripts/ is exempt (drop if your scripts ship)"
start; edit "docs/café.md";                                     check 0 "non-ASCII paths still match the list"
start; edit pkg/x_test.go pkg/testdata/a.json tests/a.sh src/__tests__/a.ts src/a.spec.ts test_a.py lib/a_test.py
check 0 "tests are exempt"
start; edit site/content/page.md;                               check 1 "nested markdown outside docs is not exempt"
start; edit src/contest/x.go;                                   check 1 "a path merely containing 'test' is not exempt"
