#!/usr/bin/env bash
# scripts/brain/test/run-all.sh — brain test runner (bash 3.2 compatible).
#
# Each test_* function is self-contained: it sets up its own BRAIN_HOME under
# a tempdir, runs the helpers, asserts, and cleans up. Reports pass/fail per
# test and exits non-zero if any fails.
#
# All test_*, assert_*, setup_* functions are called by name through the
# run_test dispatcher — shellcheck cannot see those invocations and would
# warn SC2329 "never invoked"; suppressed below.
# shellcheck disable=SC2329
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
BRAIN_DIR="$REPO/scripts/brain"
PROMOTE="$REPO/skills/brain-promote/promote.sh"
GARDEN="$REPO/skills/brain-garden/garden.sh"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    if [ "$1" = "$2" ]; then return 0; fi
    printf '  ASSERT FAIL: expected [%s], got [%s]\n' "$2" "$1" >&2
    return 1
}

assert_contains() {
    if printf '%s' "$1" | grep -qF "$2"; then return 0; fi
    printf '  ASSERT FAIL: output did not contain [%s]\n' "$2" >&2
    return 1
}

assert_not_contains() {
    if ! printf '%s' "$1" | grep -qF "$2"; then return 0; fi
    printf '  ASSERT FAIL: output unexpectedly contained [%s]\n' "$2" >&2
    return 1
}

run_test() {
    local name="$1"; shift
    printf '\n• %s\n' "$name"
    if "$@"; then
        PASS=$((PASS + 1))
        printf '  ok\n'
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$name")
        printf '  FAIL\n'
    fi
}

setup_fakeproj() {
    local dir="$1" url="$2" lockfile="${3:-}"
    mkdir -p "$dir"
    git -C "$dir" init -q
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "test"
    git -C "$dir" remote add origin "$url" 2>/dev/null || git -C "$dir" remote set-url origin "$url"
    [ -n "$lockfile" ] && touch "$dir/$lockfile"
}

# ---------------------------------------------------------------------------
# 1. repo_hash canonicalization
test_repo_hash() {
    local tmp; tmp="$(mktemp -d)"
    local urls=(
        "https://github.com/Acme/Foo.git"
        "https://acme@github.com/acme/foo.git"
        "git@github.com:acme/foo.git"
        "ssh://git@GitHub.com/acme/foo"
    )
    local hashes=()
    local u d h
    for u in "${urls[@]}"; do
        d="$tmp/$(echo "$u" | tr -c 'A-Za-z0-9' '_')"
        setup_fakeproj "$d" "$u"
        h="$(cd "$d" && bash -c ". \"$BRAIN_DIR/lib.sh\"; brain_repo_hash")"
        hashes+=("$h")
    done
    rm -rf "$tmp"
    # All four URLs should canonicalize to the same hash.
    for i in 1 2 3; do
        assert_eq "${hashes[$i]}" "${hashes[0]}" || return 1
    done
}

# 2. ecosystem detection
test_ecosystem_detect() {
    local tmp; tmp="$(mktemp -d)"
    declare -a cases
    cases=(
        "bun:package.json,bun.lockb"
        "node:package.json"
        "python+poetry:pyproject.toml,poetry.lock"
        "rust:Cargo.toml"
        "go:go.mod"
        "unknown:"
    )
    for c in "${cases[@]}"; do
        expected="${c%%:*}"
        files="${c#*:}"
        d="$tmp/$expected"
        mkdir -p "$d"
        if [ -n "$files" ]; then
            IFS=',' read -ra _files <<< "$files"
            for f in "${_files[@]}"; do touch "$d/$f"; done
        fi
        actual="$(cd "$d" && bash -c '. '"$BRAIN_DIR/lib.sh"'; brain_detect_ecosystem')"
        assert_eq "$actual" "$expected" || { rm -rf "$tmp"; return 1; }
    done
    rm -rf "$tmp"
}

# 3. redaction
test_redact() {
    # AWS key
    out="$(printf 'lesson AKIAIOSFODNN7EXAMPLE done' | "$BRAIN_DIR/redact.sh")" || return 1
    assert_contains "$out" "[redacted-aws-key]" || return 1
    assert_not_contains "$out" "AKIAIOSFODNN7EXAMPLE" || return 1
    # GH PAT
    out="$(printf 'lesson ghp_%s done' "$(printf 'a%.0s' $(seq 1 40))" | "$BRAIN_DIR/redact.sh")" || return 1
    assert_contains "$out" "[redacted-gh-pat]" || return 1
    # Oversize fence -> abort
    big_fence="$(printf 'L\n%.0s' $(seq 1 30))"
    if printf "lesson\n%s\n%s%s\n" '```python' "$big_fence" '```' | "$BRAIN_DIR/redact.sh" >/dev/null 2>&1; then
        printf '  ASSERT FAIL: oversize fence should have been rejected\n' >&2
        return 1
    fi
}

# 4. append cross-project isolation
test_append_isolation() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    setup_fakeproj "$tmp/B" "https://github.com/x/B.git"
    (cd "$tmp/A" && echo "lesson A" | HIVESMITH_SKILL=hs-test "$BRAIN_DIR/append.sh" --slug isolate-a --scope project --confidence 0.5 >/dev/null) || { rm -rf "$tmp"; return 1; }
    (cd "$tmp/B" && echo "lesson B" | HIVESMITH_SKILL=hs-test "$BRAIN_DIR/append.sh" --slug isolate-b --scope project --confidence 0.5 >/dev/null) || { rm -rf "$tmp"; return 1; }
    a_count=$(find "$BRAIN_HOME/project" -name 'isolate-a.md' | wc -l | tr -d ' ')
    b_count=$(find "$BRAIN_HOME/project" -name 'isolate-b.md' | wc -l | tr -d ' ')
    assert_eq "$a_count" "1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_eq "$b_count" "1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    # Files should be in different repo-hash subdirs.
    a_dir="$(dirname "$(find "$BRAIN_HOME/project" -name 'isolate-a.md')")"
    b_dir="$(dirname "$(find "$BRAIN_HOME/project" -name 'isolate-b.md')")"
    if [ "$a_dir" = "$b_dir" ]; then
        printf '  ASSERT FAIL: A and B landed in same dir\n' >&2
        rm -rf "$tmp"; unset BRAIN_HOME; return 1
    fi
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 5. read filtering
test_read_filter() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git" "Cargo.toml"
    # Seed: universal, user, ecosystem-rust, ecosystem-bun, project-A, project-B.
    (cd "$tmp/A" && echo "u" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug u --scope universal >/dev/null)
    (cd "$tmp/A" && echo "me" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug me --scope user >/dev/null)
    (cd "$tmp/A" && echo "rs" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug rs --scope ecosystem --ecosystem rust >/dev/null)
    (cd "$tmp/A" && echo "bn" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug bn --scope ecosystem --ecosystem bun >/dev/null)
    (cd "$tmp/A" && echo "pa" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug pa --scope project >/dev/null)
    setup_fakeproj "$tmp/B" "https://github.com/x/B.git"
    (cd "$tmp/B" && echo "pb" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug pb --scope project >/dev/null)
    "$BRAIN_DIR/index.sh" >/dev/null
    out="$(cd "$tmp/A" && "$BRAIN_DIR/read.sh")"
    assert_contains "$out" "universal/u" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_contains "$out" "user/me" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_contains "$out" "ecosystem/rust/rs" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_not_contains "$out" "ecosystem/bun/bn" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_contains "$out" "/pa" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    # B's project entry must NOT surface in A's read.
    if printf '%s' "$out" | grep -q "/pb"; then
        printf '  ASSERT FAIL: project=B entry leaked into project=A read\n' >&2
        rm -rf "$tmp"; unset BRAIN_HOME; return 1
    fi
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 6. index regen byte-stable
test_index_regen() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    for i in 1 2 3; do
        (cd "$tmp/A" && echo "L$i" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug "ent$i" --scope project --confidence 0.5 >/dev/null)
    done
    "$BRAIN_DIR/index.sh" >/dev/null
    h1="$(shasum "$BRAIN_HOME/INDEX.md" | awk '{print $1}')"
    "$BRAIN_DIR/index.sh" >/dev/null
    h2="$(shasum "$BRAIN_HOME/INDEX.md" | awk '{print $1}')"
    assert_eq "$h2" "$h1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 7. promote moves entry + updates scope
test_promote() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    (cd "$tmp/A" && echo "lesson" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug widget --scope project --confidence 0.8 >/dev/null)
    bash "$PROMOTE" widget --to universal >/dev/null || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    if [ ! -f "$BRAIN_HOME/universal/widget.md" ]; then
        printf '  ASSERT FAIL: promoted file not found at universal/widget.md\n' >&2
        rm -rf "$tmp"; unset BRAIN_HOME; return 1
    fi
    new_scope="$(python3 "$BRAIN_DIR/yaml.py" get "$BRAIN_HOME/universal/widget.md" scope)"
    assert_eq "$new_scope" "universal" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 8. lazy-init creates layout in fresh HOME
test_lazy_init() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    bash -c '. '"$BRAIN_DIR/lib.sh"'; brain_lazy_init' || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    for d in universal ecosystem user project unverified archive; do
        if [ ! -d "$BRAIN_HOME/$d" ]; then
            printf '  ASSERT FAIL: missing dir %s\n' "$d" >&2
            rm -rf "$tmp"; unset BRAIN_HOME; return 1
        fi
    done
    if [ ! -d "$BRAIN_HOME/.git" ]; then
        printf '  ASSERT FAIL: brain not git-initialized\n' >&2
        rm -rf "$tmp"; unset BRAIN_HOME; return 1
    fi
    [ -f "$BRAIN_HOME/SCHEMA.md" ] || { printf '  ASSERT FAIL: SCHEMA.md not copied\n' >&2; rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 9. garden flags stale graph_nodes
test_garden_stale_graph_nodes() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    # Seed graph.json with only "foo" — entry references "foo,bar" so "bar" should be flagged.
    mkdir -p "$tmp/A/graphify-out"
    cat > "$tmp/A/graphify-out/graph.json" <<'JSON'
{ "nodes": [ { "id": "foo", "label": "Foo" } ] }
JSON
    (cd "$tmp/A" && echo "lesson" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug stale --scope project --graph-nodes "foo,bar" --confidence 0.5 >/dev/null)
    out="$(cd "$tmp/A" && bash "$GARDEN" --report 2>&1)"
    assert_contains "$out" "stale graph_node \"bar\"" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    if printf '%s' "$out" | grep -q "stale graph_node \"foo\""; then
        printf '  ASSERT FAIL: foo should not be flagged stale\n' >&2
        rm -rf "$tmp"; unset BRAIN_HOME; return 1
    fi
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 10. budget cap on read
test_read_budget() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    # Seed many universal entries.
    for i in $(seq 1 20); do
        (cd "$tmp/A" && echo "lesson$i" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug "ent$i" --scope universal --confidence 0.5 >/dev/null)
    done
    "$BRAIN_DIR/index.sh" >/dev/null
    out="$(cd "$tmp/A" && BRAIN_BUDGET_TOKENS=200 "$BRAIN_DIR/read.sh")"
    assert_contains "$out" "budget exhausted" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 11. list filters by scope and tag
test_list_filters() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    (cd "$tmp/A" && echo "u1" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug u1 --scope universal --tags "a,b" >/dev/null)
    (cd "$tmp/A" && echo "p1" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug p1 --scope project --tags "b,c" >/dev/null)
    out="$("$BRAIN_DIR/list.sh")"
    assert_contains "$out" "u1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_contains "$out" "p1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    out="$("$BRAIN_DIR/list.sh" --scope universal)"
    assert_contains "$out" "u1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_not_contains "$out" "p1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    out="$("$BRAIN_DIR/list.sh" --tag c)"
    assert_contains "$out" "p1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_not_contains "$out" "u1" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    out="$("$BRAIN_DIR/list.sh" --paths-only)"
    assert_contains "$out" "universal/u1.md" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 12. search returns AND-matching entries ranked by hit count
test_search_and_rank() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    (cd "$tmp/A" && echo "flaky timezone tests fail in CI" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug tz-flake --scope universal >/dev/null)
    (cd "$tmp/A" && echo "bash quoting matters" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug bash-quoting --scope universal >/dev/null)
    out="$("$BRAIN_DIR/search.sh" flaky)"
    assert_contains "$out" "tz-flake" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    assert_not_contains "$out" "bash-quoting" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    # AND semantics: both terms must hit
    out="$("$BRAIN_DIR/search.sh" flaky bash)"
    assert_eq "$out" "" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    # paths-only mode
    out="$("$BRAIN_DIR/search.sh" timezone --paths-only)"
    assert_contains "$out" "universal/tz-flake.md" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# 13. helpers work when invoked through a symlink (the `~/.hivesmith/bin/` install path)
test_symlink_invocation() {
    local tmp; tmp="$(mktemp -d)"
    export BRAIN_HOME="$tmp/brain"
    setup_fakeproj "$tmp/A" "https://github.com/x/A.git"
    (cd "$tmp/A" && echo "x" | HIVESMITH_SKILL=t "$BRAIN_DIR/append.sh" --slug sym-x --scope universal >/dev/null)
    local linkdir="$tmp/bin"
    mkdir -p "$linkdir"
    ln -s "$BRAIN_DIR/list.sh" "$linkdir/brain-list"
    ln -s "$BRAIN_DIR/search.sh" "$linkdir/brain-search"
    ln -s "$BRAIN_DIR/read.sh" "$linkdir/brain-read"
    out="$("$linkdir/brain-list")"
    assert_contains "$out" "sym-x" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    out="$("$linkdir/brain-search" sym-x)"
    assert_contains "$out" "sym-x" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    out="$(cd "$tmp/A" && "$linkdir/brain-read")"
    assert_contains "$out" "project-memory" || { rm -rf "$tmp"; unset BRAIN_HOME; return 1; }
    rm -rf "$tmp"; unset BRAIN_HOME
}

# ---------------------------------------------------------------------------

run_test "repo_hash canonicalization"           test_repo_hash
run_test "ecosystem detection"                  test_ecosystem_detect
run_test "redaction (AWS / GH PAT / fence cap)" test_redact
run_test "append cross-project isolation"       test_append_isolation
run_test "read filtering by active project"     test_read_filter
run_test "index regen byte-stable"              test_index_regen
run_test "promote moves entry + updates scope"  test_promote
run_test "lazy-init creates layout"             test_lazy_init
run_test "garden flags stale graph_nodes"       test_garden_stale_graph_nodes
run_test "read budget cap"                      test_read_budget
run_test "list filters by scope and tag"        test_list_filters
run_test "search AND-matches and ranks"         test_search_and_rank
run_test "helpers work via symlink invocation"  test_symlink_invocation

printf '\n%d passed, %d failed.\n' "$PASS" "$FAIL"
if (( FAIL > 0 )); then
    printf 'failed tests:\n'
    for t in "${FAILED_TESTS[@]}"; do printf '  - %s\n' "$t"; done
    exit 1
fi
exit 0
