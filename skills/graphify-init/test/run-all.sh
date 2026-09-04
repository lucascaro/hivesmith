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

# Isolate every `git init` below from the developer's ambient config. A global
# core.hooksPath would make `graphify hook install` write OUTSIDE the mktemp
# sandbox, and commit.gpgsign=true would break the fixture commits.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
SETUP="$REPO/skills/graphify-init/graphify-setup.sh"
REFRESH="$REPO/skills/graphify-init/graphify-refresh.sh"
NUDGE="$REPO/skills/graphify-init/graphify-nudge.sh"

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
    git -C "$dir/main-repo" commit -qm init \
        || { printf '  SETUP FAIL: fixture commit failed\n' >&2; return 1; }
    if [ "$want_wt" = "--worktree" ]; then
        git -C "$dir/main-repo" worktree add -q "$dir/wt" -b feat
    fi
}

# pwd -P: on macOS `mktemp -d` hands back a /var path that is a symlink to
# /private/var, and the setup script records the resolved form. Comparing the
# logical path against the recorded one fails on the prefix alone.
stamp_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

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

    local rc=0 out setup_rc before
    before="$(cat "$hooks/post-commit")"
    out="$(cd "$t/main-repo" && HIVESMITH_GRAPHIFY_SKIP_HOOK_INSTALL=1 "$SETUP" --quiet 2>&1)"
    setup_rc=$?
    [ "$setup_rc" -eq 0 ] && { printf '  ASSERT FAIL: setup exited 0 on an unpatchable guard\n' >&2; rc=1; }
    case "$out" in
        *"worktree guard"*) ;;
        *) printf '  ASSERT FAIL: no loud failure about the guard; got: %s\n' "$out" >&2; rc=1 ;;
    esac
    [ "$(cat "$hooks/post-commit")" = "$before" ] \
        || { printf '  ASSERT FAIL: hook was modified despite the refusal\n' >&2; rc=1; }
    if ls "$hooks"/*.hivesmith.* >/dev/null 2>&1; then
        printf '  ASSERT FAIL: temp files left behind in the hooks dir\n' >&2; rc=1
    fi
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
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    local stamp="$t/graphify-out/.graphify_refresh_stamp" rc=0 first second

    # Assert the script's own exit status every time: it promises never to
    # exit non-zero, and a crash that skips the stamp used to read as a pass.
    HIVESMITH_GRAPHIFY_DEBOUNCE=3600 "$REFRESH" "$t" || { printf '  ASSERT FAIL: refresh exited non-zero\n' >&2; rc=1; }
    [ -f "$stamp" ] || { printf '  ASSERT FAIL: first call did not stamp\n' >&2; rm -rf "$t"; return 1; }
    first="$(stamp_mtime "$stamp")"

    HIVESMITH_GRAPHIFY_DEBOUNCE=3600 "$REFRESH" "$t" || { printf '  ASSERT FAIL: refresh exited non-zero\n' >&2; rc=1; }
    second="$(stamp_mtime "$stamp")"
    assert_eq "$second" "$first" || rc=1

    # Zero debounce: window is always expired, so it must re-stamp.
    sleep 1
    HIVESMITH_GRAPHIFY_DEBOUNCE=0 "$REFRESH" "$t" || { printf '  ASSERT FAIL: refresh exited non-zero\n' >&2; rc=1; }
    second="$(stamp_mtime "$stamp")"
    [ "$second" -gt "$first" ] || { printf '  ASSERT FAIL: zero debounce did not re-stamp (%s -> %s)\n' "$first" "$second" >&2; rc=1; }

    rm -rf "$t"; return "$rc"
}

test_refresh_survives_gnu_stat() {
    # Regression guard for the BSD-first `stat` probe that died on every Linux
    # host: GNU's `-f` is --file-system, so it printed a filesystem block to
    # stdout AND exited 1, the `||` fallback appended the real mtime to that
    # garbage, and the arithmetic then killed the script under `set -u` —
    # before it could stamp or launch. Shims a GNU-like stat to prove the
    # probe order handles it, since CI is the only place it reproduces.
    local t shim rc=0
    t="$(mktemp -d)"; shim="$(mktemp -d)"
    mkdir -p "$t/graphify-out"
    printf '{}\n' > "$t/graphify-out/graph.json"
    cat > "$shim/stat" <<'SHIM'
#!/bin/sh
case "$1" in
  -c) shift; case "$1" in %Y) shift; echo 1700000000; exit 0;; esac; exit 1 ;;
  -f) shift; echo "  File: \"$2\""; echo "    ID: 0 Namelen: 255"; exit 1 ;;
esac
exit 1
SHIM
    chmod +x "$shim/stat"

    PATH="$shim:$PATH" HIVESMITH_GRAPHIFY_DEBOUNCE=3600 "$REFRESH" "$t" \
        || { printf '  ASSERT FAIL: refresh exited non-zero under a GNU-like stat\n' >&2; rc=1; }
    [ -f "$t/graphify-out/.graphify_refresh_stamp" ] \
        || { printf '  ASSERT FAIL: no stamp written under a GNU-like stat\n' >&2; rc=1; }

    rm -rf "$t" "$shim"; return "$rc"
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
    assert_file_lacks "$s" 'graphify-nudge.sh' || rc=1

    # And the env form, on a second repo so the first is not already wired.
    local t2; t2="$(mktemp -d)"
    setup_repo "$t2"
    (cd "$t2/main-repo" && HIVESMITH_GRAPHIFY_NUDGES=0 "$SETUP" --quiet) || rc=1
    assert_file_lacks "$t2/main-repo/.claude/settings.json" 'hook-guard' || rc=1
    assert_file_lacks "$t2/main-repo/.claude/settings.json" 'graphify-nudge.sh' || rc=1
    rm -rf "$t2"

    rm -rf "$t"; return "$rc"
}

test_nudges_on_by_default() {
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }
    # The entries point at the wrapper, and graphify's bare command is gone.
    assert_file_contains "$t/main-repo/.claude/settings.json" 'graphify-nudge.sh' || rc=1
    assert_file_lacks "$t/main-repo/.claude/settings.json" 'hook-guard' || rc=1
    # The CLI would also write a CLAUDE.md section duplicating our AGENTS.md
    # block; calling install.py directly must not.
    [ -f "$t/main-repo/CLAUDE.md" ] \
        && { printf '  ASSERT FAIL: a CLAUDE.md was written\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_hook_target_is_untracked_and_guarded() {
    # The committed settings.json must never point the PostToolUse hook at a
    # TRACKED path: a contributor PR editing that file's body would then run on
    # any maintainer who checks the branch out, while the reviewed command
    # string stays identical. It must also degrade to a no-op when the script
    # is absent, rather than 127 on every tool call.
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0 s="$t/main-repo/.claude/settings.json"
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }

    assert_file_contains "$s" 'graphify-out/graphify-refresh.sh' || rc=1
    assert_file_lacks "$s" 'scripts/graphify-refresh.sh' || rc=1
    # -x guard present, so a wiped output dir is a no-op not a failure.
    assert_file_contains "$s" '|| exit 0' || rc=1
    # The target must be ignored by git in the wired project.
    if ! (cd "$t/main-repo" && git check-ignore -q graphify-out/graphify-refresh.sh); then
        printf '  ASSERT FAIL: hook target is not gitignored\n' >&2; rc=1
    fi
    # graphify's own nudges must be guarded too — and now replaced outright by
    # the wrapper, whose target is subject to the same untracked invariant.
    assert_file_lacks "$s" '"command": "graphify hook-guard' || rc=1
    assert_file_contains "$s" 'graphify-out/graphify-nudge.sh' || rc=1
    if ! (cd "$t/main-repo" && git check-ignore -q graphify-out/graphify-nudge.sh); then
        printf '  ASSERT FAIL: nudge wrapper target is not gitignored\n' >&2; rc=1
    fi
    rm -rf "$t"; return "$rc"
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


# --- graphify-nudge.sh (the PreToolUse wrapper) ------------------------------
#
# Most cases drive the wrapper directly with a synthetic payload and a `graphify`
# shim on PATH, so they need neither a real graphify nor a built graph. Only the
# install-path cases call need_graphify.

# Scratch project with an out dir and a shim graphify whose canned stdout is
# whatever $2 contains. Echoes the project dir.
nudge_fixture() {
    local dir="$1" canned="$2"
    mkdir -p "$dir/graphify-out/cache" "$dir/bin"
    cat > "$dir/bin/graphify" <<SHIM
#!/bin/sh
echo "invoked" >> "$dir/graphify-out/shim-invocations"
printf '%s' '$canned'
SHIM
    chmod +x "$dir/bin/graphify"
}

NUDGE_PAYLOAD='{"session_id":"sess-a","tool_input":{"pattern":"foo"}}'
NUDGE_SOFT='{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"MANDATORY: you MUST run graphify"}}'
NUDGE_DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"graphify strict mode"}}'

# Run the wrapper inside $1 with the shim on PATH. Payload on stdin from $2.
run_nudge() {
    local dir="$1" payload="$2" kind="${3:-search}"
    (cd "$dir" && PATH="$dir/bin:$PATH" CLAUDE_PROJECT_DIR="$dir" \
        sh -c "printf '%s' '$payload' | '$NUDGE' $kind")
}

test_nudge_text_is_advisory() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    local out; out="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    case "$out" in
        *MANDATORY*|*"You MUST"*|*subagent*)
            printf '  ASSERT FAIL: emitted text is not advisory: %s\n' "$out" >&2; rc=1 ;;
    esac
    case "$out" in
        *"graphify query"*) ;;
        *) printf '  ASSERT FAIL: advisory text missing the query hint\n' >&2; rc=1 ;;
    esac
    rm -rf "$t"; return "$rc"
}

test_nudge_throttles_per_session() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    local first second other
    first="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    second="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    other="$(run_nudge "$t" '{"session_id":"sess-b","tool_input":{"pattern":"foo"}}')"
    [ -n "$first" ]  || { printf '  ASSERT FAIL: first call emitted nothing\n' >&2; rc=1; }
    [ -z "$second" ] || { printf '  ASSERT FAIL: second call in same session emitted\n' >&2; rc=1; }
    [ -n "$other" ]  || { printf '  ASSERT FAIL: a different session was suppressed\n' >&2; rc=1; }
    # Kinds are throttled independently.
    local readkind; readkind="$(run_nudge "$t" "$NUDGE_PAYLOAD" read)"
    [ -n "$readkind" ] || { printf '  ASSERT FAIL: read kind suppressed by a search claim\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_nudge_passes_through_deny() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_DENY"
    local out; out="$(GRAPHIFY_HOOK_STRICT=1 run_nudge "$t" "$NUDGE_PAYLOAD")"
    assert_eq "$NUDGE_DENY" "$out" "deny payload forwarded verbatim" || rc=1
    # A deny is graphify's decision, not our nudge — it must not burn the slot.
    if [ -e "$t/graphify-out/cache/hook_nudges/sess-a.search" ]; then
        printf '  ASSERT FAIL: deny consumed the session claim\n' >&2; rc=1
    fi
    rm -rf "$t"; return "$rc"
}

test_nudge_respects_query_stamp() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    : > "$t/graphify-out/cache/last_query_stamp"
    local out; out="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    [ -z "$out" ] || { printf '  ASSERT FAIL: emitted despite a fresh stamp\n' >&2; rc=1; }
    # Backdate past the TTL: it should speak again.
    local out2; out2="$(cd "$t" && PATH="$t/bin:$PATH" CLAUDE_PROJECT_DIR="$t" \
        GRAPHIFY_HOOK_STRICT_TTL=0 sh -c "printf '%s' '$NUDGE_PAYLOAD' | '$NUDGE' search")"
    [ -n "$out2" ] || { printf '  ASSERT FAIL: stale stamp still suppressed\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_nudge_stale_variant() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    : > "$t/graphify-out/needs_update"
    local out; out="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    case "$out" in
        *"graphify update"*) ;;
        *) printf '  ASSERT FAIL: stale variant missing the update hint\n' >&2; rc=1 ;;
    esac
    rm -rf "$t"; return "$rc"
}

test_nudge_sanitizes_session_id() {
    # The session id becomes a filename. A Bash payload can carry the literal
    # "session_id": inside the command being nudged, and key order is not
    # contractual, so a traversal-shaped value must never escape the cache dir.
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    run_nudge "$t" '{"session_id":"../../escape","tool_input":{"pattern":"x"}}' >/dev/null
    if [ -e "$t/escape.search" ] || [ -e "$t/graphify-out/escape.search" ]; then
        printf '  ASSERT FAIL: claim file escaped the cache dir\n' >&2; rc=1
    fi
    local claims; claims="$(find "$t/graphify-out/cache/hook_nudges" -type f 2>/dev/null | wc -l | tr -d ' ')"
    assert_eq "1" "$claims" "exactly one claim file, inside the cache dir" || rc=1
    local name; name="$(find "$t/graphify-out/cache/hook_nudges" -type f -exec basename {} \; 2>/dev/null)"
    case "$name" in
        *..*) printf '  ASSERT FAIL: unsanitised claim filename: %s\n' "$name" >&2; rc=1 ;;
    esac
    rm -rf "$t"; return "$rc"
}

test_nudge_skips_fork_when_satisfied() {
    # The point of the wrapper is not only fewer tokens: once nothing graphify
    # can return would be used, it must not pay the process spawn either.
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    run_nudge "$t" "$NUDGE_PAYLOAD" >/dev/null          # claims the slot, forks once
    rm -f "$t/graphify-out/shim-invocations"
    run_nudge "$t" "$NUDGE_PAYLOAD" >/dev/null          # already claimed
    if [ -e "$t/graphify-out/shim-invocations" ]; then
        printf '  ASSERT FAIL: forked graphify despite a claimed slot\n' >&2; rc=1
    fi
    # Under strict mode a deny is still possible, so the shortcut must not apply.
    rm -f "$t/graphify-out/shim-invocations"
    (cd "$t" && PATH="$t/bin:$PATH" CLAUDE_PROJECT_DIR="$t" GRAPHIFY_HOOK_STRICT=1 \
        sh -c "printf '%s' '$NUDGE_PAYLOAD' | '$NUDGE' search") >/dev/null
    if [ ! -e "$t/graphify-out/shim-invocations" ]; then
        printf '  ASSERT FAIL: strict mode skipped the graphify call\n' >&2; rc=1
    fi
    rm -rf "$t"; return "$rc"
}

test_nudge_fails_open() {
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"

    # 1. graphify absent from PATH.
    local out
    out="$(cd "$t" && PATH=/usr/bin:/bin CLAUDE_PROJECT_DIR="$t" \
        sh -c "printf '%s' '$NUDGE_PAYLOAD' | '$NUDGE' search")"
    local r=$?
    [ "$r" = "0" ] && [ -z "$out" ] || { printf '  ASSERT FAIL: no-graphify path\n' >&2; rc=1; }

    # 2. stdin is not JSON at all.
    nudge_fixture "$t" ""
    out="$(run_nudge "$t" 'not json at all')"; r=$?
    [ "$r" = "0" ] && [ -z "$out" ] || { printf '  ASSERT FAIL: non-JSON stdin\n' >&2; rc=1; }

    # 3. graphify emits nothing.
    out="$(run_nudge "$t" "$NUDGE_PAYLOAD")"; r=$?
    [ "$r" = "0" ] && [ -z "$out" ] || { printf '  ASSERT FAIL: empty graphify output\n' >&2; rc=1; }

    # 4. graphify emits malformed JSON.
    nudge_fixture "$t" 'not-json'
    out="$(run_nudge "$t" '{"session_id":"sess-malformed","tool_input":{"pattern":"x"}}')"; r=$?
    [ "$r" = "0" ] || { printf '  ASSERT FAIL: malformed graphify output exited non-zero\n' >&2; rc=1; }

    # 5. unwritable cache dir.
    nudge_fixture "$t" "$NUDGE_SOFT"
    chmod a-w "$t/graphify-out/cache" 2>/dev/null
    out="$(run_nudge "$t" '{"session_id":"sess-ro","tool_input":{"pattern":"x"}}')"; r=$?
    chmod u+w "$t/graphify-out/cache" 2>/dev/null
    [ "$r" = "0" ] || { printf '  ASSERT FAIL: unwritable cache exited non-zero\n' >&2; rc=1; }

    # 6. no kind argument.
    out="$(printf '%s' "$NUDGE_PAYLOAD" | "$NUDGE")"; r=$?
    [ "$r" = "0" ] && [ -z "$out" ] || { printf '  ASSERT FAIL: missing kind arg\n' >&2; rc=1; }

    rm -rf "$t"; return "$rc"
}

test_nudge_survives_gnu_stat() {
    # CI (Linux) caught what macOS could not: `stat -f` is --file-system on GNU
    # coreutils, so a BSD-first probe succeeds with garbage instead of falling
    # through, and the stamp check silently never fires. Shim a GNU-only stat so
    # this fails on either platform.
    local t; t="$(mktemp -d)"; local rc=0
    nudge_fixture "$t" "$NUDGE_SOFT"
    cat > "$t/bin/stat" <<'SHIM'
#!/bin/sh
# Models GNU coreutils and defers to no real stat, so it behaves the same on
# macOS and Linux: -c %Y answers, and -f succeeds with a filesystem block
# instead of failing — the trap a BSD-first probe falls into.
case "$1" in
    -c) date +%s; exit 0 ;;
    -f) echo "  File: \"/\"  ID: 0 Namelen: 255  Type: ext2/ext3"; exit 0 ;;
esac
exit 1
SHIM
    chmod +x "$t/bin/stat"
    : > "$t/graphify-out/cache/last_query_stamp"
    local out; out="$(run_nudge "$t" "$NUDGE_PAYLOAD")"
    [ -z "$out" ] || { printf '  ASSERT FAIL: fresh stamp ignored under a GNU-style stat\n' >&2; rc=1; }
    rm -rf "$t"; return "$rc"
}

test_setup_migrates_guarded_command() {
    # Repos wired before the wrapper existed carry the ALREADY-GUARDED form.
    # A `startswith("graphify ")` predicate skips it, which would leave them
    # unmigrated and then trip the post-install verification.
    need_graphify || return $?
    local t; t="$(mktemp -d)"
    setup_repo "$t"
    local rc=0 s="$t/main-repo/.claude/settings.json"
    mkdir -p "$t/main-repo/.claude"
    cat > "$s" <<'PRE'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash|Grep",
        "hooks": [
          {
            "type": "command",
            "command": "command -v graphify >/dev/null 2>&1 && graphify hook-guard search || exit 0"
          }
        ]
      }
    ]
  }
}
PRE
    (cd "$t/main-repo" && "$SETUP" --quiet) || { rm -rf "$t"; return 1; }
    assert_file_contains "$s" 'graphify-nudge.sh' || rc=1
    assert_file_lacks "$s" '&& graphify hook-guard' || rc=1
    rm -rf "$t"; return "$rc"
}

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
run_test "refresh survives a GNU-style stat"     test_refresh_survives_gnu_stat
run_test "refresh honors disable env"            test_refresh_disabled_by_env
run_test "setup fails clearly without graphify"  test_setup_without_graphify_fails_clearly
run_test "failed migrate preserves the cache"    test_migrate_failure_preserves_cache
run_test "refresh caps its log"                  test_refresh_caps_log
run_test "nudges can be opted out"               test_nudges_opt_out
run_test "nudges on by default, no CLAUDE.md"    test_nudges_on_by_default
run_test "hook target untracked and guarded"      test_hook_target_is_untracked_and_guarded
run_test "nudge text is advisory"                test_nudge_text_is_advisory
run_test "nudge throttles per session and kind"  test_nudge_throttles_per_session
run_test "nudge passes a deny through verbatim"  test_nudge_passes_through_deny
run_test "nudge respects the query stamp"        test_nudge_respects_query_stamp
run_test "nudge survives a GNU-style stat"       test_nudge_survives_gnu_stat
run_test "nudge has a stale-graph variant"       test_nudge_stale_variant
run_test "nudge sanitizes the session id"        test_nudge_sanitizes_session_id
run_test "nudge skips the fork when satisfied"   test_nudge_skips_fork_when_satisfied
run_test "nudge fails open"                      test_nudge_fails_open
run_test "setup migrates a guarded command"      test_setup_migrates_guarded_command

printf '\n%d passed, %d failed, %d skipped.\n' "$PASS" "$FAIL" "$SKIP"
if [ "$FAIL" -gt 0 ]; then
    printf 'failed tests:\n'
    for t in "${FAILED_TESTS[@]}"; do printf '  - %s\n' "$t"; done
    exit 1
fi
exit 0
