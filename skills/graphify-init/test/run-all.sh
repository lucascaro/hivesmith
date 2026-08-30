#!/usr/bin/env bash
# skills/graphify-init/test/run-all.sh — graphify-init test runner (bash 3.2).
#
# Each test_* builds a throwaway git repo (plus a linked worktree where the
# behavior under test is worktree-specific) under a tempdir, runs the scripts,
# asserts, and cleans up.
#
# Tests that need `graphify` on PATH are skipped when it is absent, so the
# suite is runnable on a machine without it — except in CI, where GRAPHIFY_
# REQUIRED=1 turns a skip into a failure so a missing dependency cannot hide
# the guard-patch regression this suite exists to catch.
#
# All test_*, assert_*, setup_* functions are called by name through the
# run_test dispatcher — shellcheck cannot see those invocations and would
# warn SC2329 "never invoked"; suppressed below.
# shellcheck disable=SC2329
set -uo pipefail

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SETUP="$REPO/skills/graphify-init/graphify-setup.sh"
REFRESH="$REPO/skills/graphify-init/graphify-refresh.sh"

PASS=0
FAIL=0
SKIP=0
FAILED_TESTS=()

assert_eq() {
    if [ "$1" = "$2" ]; then return 0; fi
    printf '  ASSERT FAIL: expected [%s], got [%s]\n' "$2" "$1" >&2
    return 1
}

assert_file_contains() {
    if grep -qF "$2" "$1" 2>/dev/null; then return 0; fi
    printf '  ASSERT FAIL: %s did not contain [%s]\n' "$1" "$2" >&2
    return 1
}

assert_file_lacks() {
    if ! grep -qF "$2" "$1" 2>/dev/null; then return 0; fi
    printf '  ASSERT FAIL: %s unexpectedly contained [%s]\n' "$1" "$2" >&2
    return 1
}

run_test() {
    local name="$1"; shift
    printf '\n• %s\n' "$name"
    "$@"
    local rc=$?
    if [ "$rc" -eq 0 ]; then
        PASS=$((PASS + 1)); printf '  ok\n'
    elif [ "$rc" -eq 77 ]; then
        SKIP=$((SKIP + 1)); printf '  skipped (graphify not on PATH)\n'
    else
        FAIL=$((FAIL + 1)); FAILED_TESTS+=("$name"); printf '  FAIL\n'
    fi
}

need_graphify() {
    command -v graphify >/dev/null 2>&1 && return 0
    [ "${GRAPHIFY_REQUIRED:-0}" = "1" ] && {
        printf '  graphify is not on PATH and GRAPHIFY_REQUIRED=1\n' >&2
        return 1
    }
    return 77
}

# setup_repo <dir> [--worktree]
# Creates <dir>/main-repo and, with --worktree, <dir>/wt linked to it.
setup_repo() {
    local dir="$1" want_wt="${2:-}"
    mkdir -p "$dir"
    git -C "$dir" init -q main-repo
    git -C "$dir/main-repo" config user.email "test@example.com"
    git -C "$dir/main-repo" config user.name "test"
    printf '# AGENTS\n' > "$dir/main-repo/AGENTS.md"
    printf 'x = 1\n' > "$dir/main-repo/a.py"
    git -C "$dir/main-repo" add -A
    git -C "$dir/main-repo" commit -qm init
    if [ "$want_wt" = "--worktree" ]; then
        git -C "$dir/main-repo" worktree add -q "$dir/wt" -b feat
    fi
}

# pwd -P: on macOS `mktemp -d` hands back a /var path that is a symlink to
# /private/var, and the setup script records the resolved form. Comparing the
# logical path against the recorded one fails on the prefix alone.
common_dir() {
    (cd "$1" && cd "$(git rev-parse --git-common-dir)" && pwd -P)
}

# ---------------------------------------------------------------------------

test_shared_cache_symlink() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t" --worktree
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }
    (cd "$t/wt" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }

    local shared primary wt rc=0
    shared="$(common_dir "$t/main-repo")/graphify-cache"
    primary="$(readlink "$t/main-repo/graphify-out/cache")"
    wt="$(readlink "$t/wt/graphify-out/cache")"
    assert_eq "$primary" "$shared" || rc=1
    assert_eq "$wt" "$shared" || rc=1
    rm -rf "$t"; return "$rc"
}

test_migrate_preserves_entries() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    mkdir -p "$t/main-repo/graphify-out/cache/semantic"
    printf '{"cached":true}\n' > "$t/main-repo/graphify-out/cache/semantic/deadbeef.json"
    (cd "$t/main-repo" && "$SETUP" --migrate --quiet) || { rm -rf "$t"; return 1; }

    local rc=0
    [ -L "$t/main-repo/graphify-out/cache" ] || { printf '  ASSERT FAIL: cache is not a symlink\n' >&2; rc=1; }
    assert_file_contains "$t/main-repo/graphify-out/cache/semantic/deadbeef.json" '"cached":true' || rc=1
    rm -rf "$t"; return "$rc"
}

test_refuses_to_clobber_cache() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    mkdir -p "$t/main-repo/graphify-out/cache/semantic"
    printf '{"cached":true}\n' > "$t/main-repo/graphify-out/cache/semantic/deadbeef.json"

    local rc=0 out
    out="$(cd "$t/main-repo" && "$SETUP" --quiet 2>&1)"
    # shellcheck disable=SC2181  # want the subshell's status, not a direct if
    if [ $? -eq 0 ]; then
        printf '  ASSERT FAIL: setup succeeded; it must refuse a populated cache dir\n' >&2
        rc=1
    fi
    case "$out" in *"--migrate"*) ;; *) printf '  ASSERT FAIL: message does not mention --migrate\n' >&2; rc=1 ;; esac
    [ -f "$t/main-repo/graphify-out/cache/semantic/deadbeef.json" ] \
        || { printf '  ASSERT FAIL: existing cache entry was destroyed\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_worktree_guard_lifted() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t" --worktree
    (cd "$t/wt" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }

    local rc=0 hooks guard
    hooks="$(common_dir "$t/main-repo")/hooks"
    for h in post-commit post-checkout; do
        assert_file_contains "$hooks/$h" 'HIVESMITH_GRAPHIFY_WORKTREE' || rc=1
        # The guard block must no longer contain a bare `exit 0`.
        guard="$(sed -n '/_GFY_GITDIR=/,/^fi$/p' "$hooks/$h")"
        case "$guard" in
            *"
    exit 0"*) printf '  ASSERT FAIL: %s guard still exits unconditionally\n' "$h" >&2; rc=1 ;;
        esac
    done
    rm -rf "$t"; return "$rc"
}

test_guard_patch_fails_loudly() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local hooks; hooks="$(common_dir "$t/main-repo")/hooks"
    mkdir -p "$hooks"
    # A post-commit carrying graphify's markers but a reshaped guard, standing
    # in for a future graphify release. `graphify hook install` rewrites only
    # between its own markers, so the mangled guard survives into the patch.
    cat > "$hooks/post-commit" <<'HOOK'
#!/bin/sh
# graphify-hook-start
_GFY_GITDIR=$(git rev-parse --git-dir)
if [ "$_GFY_GITDIR" != "$_GFY_COMMONDIR" ]; then
    return 0
fi
# graphify-hook-end
HOOK
    chmod +x "$hooks/post-commit"

    local rc=0 out
    out="$(cd "$t/main-repo" && HIVESMITH_GRAPHIFY_SKIP_HOOK_INSTALL=1 "$SETUP" --quiet 2>&1)"
    case "$out" in
        *"worktree guard"*) ;;
        *) printf '  ASSERT FAIL: no loud failure about the guard; got: %s\n' "$out" >&2; rc=1 ;;
    esac
    rm -rf "$t"; return "$rc"
}

test_setup_idempotent() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }
    cp "$t/main-repo/.claude/settings.json" "$t/settings.first"
    cp "$t/main-repo/AGENTS.md" "$t/agents.first"
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }

    local rc=0 hooks n
    cmp -s "$t/settings.first" "$t/main-repo/.claude/settings.json" \
        || { printf '  ASSERT FAIL: settings.json changed on re-run\n' >&2; rc=1; }
    cmp -s "$t/agents.first" "$t/main-repo/AGENTS.md" \
        || { printf '  ASSERT FAIL: AGENTS.md changed on re-run\n' >&2; rc=1; }
    hooks="$(common_dir "$t/main-repo")/hooks"
    n="$(grep -c 'HIVESMITH_GRAPHIFY_WORKTREE' "$hooks/post-commit")"
    assert_eq "$n" "1" || rc=1
    n="$(grep -c 'BEGIN HIVESMITH GRAPHIFY' "$t/main-repo/AGENTS.md")"
    assert_eq "$n" "1" || rc=1
    rm -rf "$t"; return "$rc"
}

test_uninstall_reverses() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    mkdir -p "$t/main-repo/graphify-out/cache/semantic"
    printf '{"cached":true}\n' > "$t/main-repo/graphify-out/cache/semantic/deadbeef.json"
    (cd "$t/main-repo" && "$SETUP" --migrate --quiet) || { rm -rf "$t"; return 1; }
    (cd "$t/main-repo" && "$SETUP" --uninstall --quiet) || { rm -rf "$t"; return 1; }

    local rc=0 hooks
    [ -L "$t/main-repo/graphify-out/cache" ] \
        && { printf '  ASSERT FAIL: cache is still a symlink\n' >&2; rc=1; }
    assert_file_contains "$t/main-repo/graphify-out/cache/semantic/deadbeef.json" '"cached":true' || rc=1
    hooks="$(common_dir "$t/main-repo")/hooks"
    if [ -f "$hooks/post-commit" ]; then
        assert_file_lacks "$hooks/post-commit" 'graphify-hook-start' || rc=1
    fi
    [ -f "$t/main-repo/.claude/settings.json" ] \
        && { assert_file_lacks "$t/main-repo/.claude/settings.json" 'graphify-refresh.sh' || rc=1; }
    assert_file_lacks "$t/main-repo/AGENTS.md" 'BEGIN HIVESMITH GRAPHIFY' || rc=1
    rm -rf "$t"; return "$rc"
}

test_settings_merge_preserves_others() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    mkdir -p "$t/main-repo/.claude"
    cat > "$t/main-repo/.claude/settings.json" <<'JSON'
{
  "hooks": {
    "PostToolUse": [
      {"matcher": "Edit|Write", "hooks": [{"type": "command", "command": "somebody-elses-hook"}]}
    ]
  }
}
JSON
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }

    local rc=0 s="$t/main-repo/.claude/settings.json"
    assert_file_contains "$s" 'somebody-elses-hook' || rc=1
    assert_file_contains "$s" 'graphify-refresh.sh' || rc=1
    (cd "$t/main-repo" && "$SETUP" --uninstall --quiet) || rc=1
    assert_file_contains "$s" 'somebody-elses-hook' || rc=1
    assert_file_lacks "$s" 'graphify-refresh.sh' || rc=1
    rm -rf "$t"; return "$rc"
}

test_refresh_noop_without_graph() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    local rc=0
    "$REFRESH" "$t" || rc=1
    [ -f "$t/graphify-out/.graphify_refresh_stamp" ] \
        && { printf '  ASSERT FAIL: stamped despite no graph.json\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_refresh_never_fails() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    local rc=0
    # No graphify on PATH: a broken graph must never fail an agent's edit.
    env PATH=/usr/bin:/bin "$REFRESH" "$t" || rc=1
    rm -rf "$t"; return "$rc"
}

test_refresh_debounces() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    local stamp="$t/graphify-out/.graphify_refresh_stamp" rc=0 first second

    HIVESMITH_GRAPHIFY_DEBOUNCE=3600 "$REFRESH" "$t"
    [ -f "$stamp" ] || { printf '  ASSERT FAIL: first call did not stamp\n' >&2; rm -rf "$t"; return 1; }
    first="$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp")"

    # Backdate so the second call is provably inside the window regardless of
    # clock granularity, then confirm the stamp is untouched.
    HIVESMITH_GRAPHIFY_DEBOUNCE=3600 "$REFRESH" "$t"
    second="$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp")"
    assert_eq "$second" "$first" || rc=1

    # Zero debounce: the window is always expired, so it must re-stamp.
    sleep 1
    HIVESMITH_GRAPHIFY_DEBOUNCE=0 "$REFRESH" "$t"
    second="$(stat -f %m "$stamp" 2>/dev/null || stat -c %Y "$stamp")"
    [ "$second" = "$first" ] && { printf '  ASSERT FAIL: zero debounce did not re-stamp\n' >&2; rc=1; }

    rm -rf "$t"; return "$rc"
}

test_refresh_disabled_by_env() {
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    local rc=0
    HIVESMITH_GRAPHIFY_REFRESH=0 "$REFRESH" "$t" || rc=1
    [ -f "$t/graphify-out/.graphify_refresh_stamp" ] \
        && { printf '  ASSERT FAIL: ran despite HIVESMITH_GRAPHIFY_REFRESH=0\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_nudges_opt_out() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0 s="$t/main-repo/.claude/settings.json"

    (cd "$t/main-repo" && "$SETUP" --no-nudges --quiet) || { rm -rf "$t"; return 1; }
    assert_file_contains "$s" 'graphify-refresh.sh' || rc=1
    assert_file_lacks "$s" 'hook-guard' || rc=1

    # And the env form, on a second repo so the first is not already wired.
    local t2; t2="$(mktemp -d)"
    setup_repo "$t2"
    (cd "$t2/main-repo" && HIVESMITH_GRAPHIFY_NUDGES=0 "$SETUP" --quiet) || rc=1
    assert_file_lacks "$t2/main-repo/.claude/settings.json" 'hook-guard' || rc=1
    rm -rf "$t2"

    rm -rf "$t"; return "$rc"
}

test_nudges_on_by_default() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }
    assert_file_contains "$t/main-repo/.claude/settings.json" 'hook-guard' || rc=1
    # The CLI would also write a CLAUDE.md section duplicating our AGENTS.md
    # block; calling install.py directly must not.
    [ -f "$t/main-repo/CLAUDE.md" ] \
        && { printf '  ASSERT FAIL: a CLAUDE.md was written\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_refresh_copy_in_sync() {
    # graphify-setup.sh copies the refresh script into <project>/scripts/. This
    # repo dogfoods the setup, so the committed copy must not drift.
    [ -f "$REPO/scripts/graphify-refresh.sh" ] || return 0
    cmp -s "$REFRESH" "$REPO/scripts/graphify-refresh.sh" && return 0
    printf '  ASSERT FAIL: scripts/graphify-refresh.sh has drifted from the skill copy.\n' >&2
    printf '  Re-run skills/graphify-init/graphify-setup.sh to refresh it.\n' >&2
    return 1
}


test_setup_without_graphify_fails_clearly() {
    # setup NEEDS graphify (unlike refresh, which must degrade silently). It
    # must say so rather than dying somewhere confusing downstream.
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0 out
    out="$(cd "$t/main-repo" && env PATH=/usr/bin:/bin "$SETUP" --quiet 2>&1)"
    # shellcheck disable=SC2181  # want the subshell's status
    if [ $? -eq 0 ]; then
        printf '  ASSERT FAIL: setup succeeded with no graphify on PATH\n' >&2
        rc=1
    fi
    case "$out" in
        *"not on PATH"*) ;;
        *) printf '  ASSERT FAIL: message does not name the missing dependency: %s\n' "$out" >&2; rc=1 ;;
    esac
    rm -rf "$t"; return "$rc"
}

test_migrate_failure_preserves_cache() {
    # The load-bearing safety property: if the copy into the shared dir fails,
    # the source cache must survive. Made to fail by pointing the shared path
    # at a location that cannot be written.
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    mkdir -p "$t/main-repo/graphify-out/cache/semantic"
    printf '{"cached":true}\n' > "$t/main-repo/graphify-out/cache/semantic/deadbeef.json"

    # Make the git common dir read-only so `mkdir -p $SHARED` / the copy fails.
    local common; common="$(common_dir "$t/main-repo")"
    chmod a-w "$common"

    local rc=0
    (cd "$t/main-repo" && "$SETUP" --migrate --quiet >/dev/null 2>&1)
    local setup_rc=$?

    # Assert the setup ACTUALLY failed first. Without this the test passes
    # vacuously the day chmod stops blocking the write (running as root, an
    # ACL, or a refactor that copies before it checks) — it would silently
    # stop covering the data-loss path it exists for.
    if [ "$setup_rc" -eq 0 ]; then
        printf '  ASSERT FAIL: setup succeeded; the failure this test needs did not occur\n' >&2
        rc=1
    fi
    # The invariant, whether it failed at mkdir or at cp:
    [ -f "$t/main-repo/graphify-out/cache/semantic/deadbeef.json" ] \
        || { printf '  ASSERT FAIL: cache entry destroyed after a failed migrate\n' >&2; rc=1; }

    chmod u+w "$common"
    rm -rf "$t"; return "$rc"
}

test_refresh_caps_log() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    local log="$t/graphify-out/.refresh.log" rc=0 size
    # ~4 KiB of junk against a 1 KiB cap.
    for _ in $(seq 1 64); do printf '%064d\n' 0; done > "$log"
    HIVESMITH_GRAPHIFY_LOG_CAP=1024 HIVESMITH_GRAPHIFY_DEBOUNCE=0 "$REFRESH" "$t"
    size="$(wc -c <"$log" | tr -d ' ')"
    # The rebuild appends asynchronously, so assert it shrank well below the
    # pre-truncate size rather than pinning an exact byte count.
    [ "$size" -ge 4160 ] && { printf '  ASSERT FAIL: log not truncated (%s bytes)\n' "$size" >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

# ---------------------------------------------------------------------------

run_test "shared cache symlink across worktrees" test_shared_cache_symlink
run_test "--migrate preserves cache entries"     test_migrate_preserves_entries
run_test "refuses to clobber a populated cache"  test_refuses_to_clobber_cache
run_test "worktree guard lifted in both hooks"   test_worktree_guard_lifted
run_test "guard patch fails loudly on drift"     test_guard_patch_fails_loudly
run_test "setup is idempotent"                   test_setup_idempotent
run_test "uninstall reverses everything"         test_uninstall_reverses
run_test "settings merge preserves other hooks"  test_settings_merge_preserves_others
run_test "refresh no-ops without graph.json"     test_refresh_noop_without_graph
run_test "refresh never exits non-zero"          test_refresh_never_fails
run_test "refresh debounces"                     test_refresh_debounces
run_test "refresh honors disable env"            test_refresh_disabled_by_env
run_test "setup fails clearly without graphify"  test_setup_without_graphify_fails_clearly
run_test "failed migrate preserves the cache"    test_migrate_failure_preserves_cache
run_test "refresh caps its log"                  test_refresh_caps_log
run_test "nudges can be opted out"               test_nudges_opt_out
run_test "nudges on by default, no CLAUDE.md"    test_nudges_on_by_default
run_test "committed refresh copy is in sync"     test_refresh_copy_in_sync

printf '\n%d passed, %d failed, %d skipped.\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed tests:\n'
    for t in "${FAILED_TESTS[@]}"; do printf '  - %s\n' "$t"; done
    exit 1
fi
exit 0
