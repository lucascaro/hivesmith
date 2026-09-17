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

git -C "$tmp" init -q
git -C "$tmp" config user.email t@example.com
git -C "$tmp" config user.name test
commit() { git -C "$tmp" add -A; git -C "$tmp" commit -qm "$1"; }
touch_file() { mkdir -p "$tmp/$(dirname "$1")"; echo "$RANDOM" >> "$tmp/$1"; }

touch_file README.md
commit base
base="$(git -C "$tmp" rev-parse HEAD)"

expect() { # expect <want-exit> <description> <path>...
  local want="$1" desc="$2" got=0
  shift 2
  git -C "$tmp" reset -q --hard "$base"
  for p in "$@"; do touch_file "$p"; done
  commit "$desc"
  ( cd "$tmp" && "$GATE" "$base" HEAD >/dev/null 2>&1 ) || got=$?
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $desc (exit $got, want $want)" >&2
    exit 1
  fi
  echo "ok: $desc"
}

expect 1 "app code without a changeset is refused" src/app.ts
expect 0 "app code with a changeset passes" src/app.ts .changesets/001-x.md
expect 1 "changesets README alone is not a changeset" src/app.ts .changesets/README.md
expect 0 "specs and exec plans are exempt" docs/product-specs/1.md docs/exec-plans/active/1.md
expect 0 "feature files are exempt" features/BACKLOG.md features/active/1.md
expect 0 "root markdown is exempt" AGENTS.md CONTRIBUTING.md
expect 0 "CI and tooling are exempt" .github/workflows/ci.yml scripts/release.sh
expect 0 "tests are exempt" pkg/x_test.go pkg/testdata/a.json tests/a.sh \
  src/__tests__/a.ts src/a.spec.ts test_a.py lib/a_test.py
expect 1 "nested markdown outside docs is not exempt" site/content/page.md
expect 1 "a docs change mixed with app code is refused" docs/x.md src/app.ts
expect 1 "a path merely containing 'test' is not exempt" src/contest/x.go
