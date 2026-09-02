#!/usr/bin/env bash
# Regression suite for per-scope agent target resolution in install.sh.
#
# The interesting case is a harness whose project layout is NOT the home layout
# re-rooted at $PWD. pi is that harness: `~/.pi/agent/skills` globally but
# `.pi/skills` in a project. `scope_path()` derives local paths mechanically, so
# without the `local_skills_dir` override a --local install would link into
# `./.pi/agent/skills` — a directory pi never reads, with no visible error.
#
# Runs real (non-dry-run) installs inside a scratch HOME and a scratch project;
# the real global install and crontab are never touched.
#
# Usage: bash tests/install-agent-scopes-test.sh
set -uo pipefail

HS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILL_COUNT="$(find "$HS/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"

FAILED=0
pass() { printf 'ok   %s\n' "$1"; }
fail() { printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }

# Each case gets a pristine sandbox: fake HOME, fake project, isolated configs.
new_sandbox() {
    SB="$(mktemp -d)"
    FAKE_HOME="$SB/home"; PROJ="$SB/proj"
    mkdir -p "$FAKE_HOME" "$PROJ"
    export HIVESMITH_DIR_CONFIG="$FAKE_HOME/.hivesmith.toml"
    export HIVESMITH_LOCAL_CONFIG="$PROJ/.hivesmith.toml"
}

# Non-interactive by construction: </dev/null so the local-selection prompt
# takes its default instead of hanging.
hs_install() { (cd "$PROJ" && HOME="$FAKE_HOME" bash "$HS/install.sh" "$@" </dev/null >/dev/null 2>&1); }

count_links() {  # $1 = dir; counts symlinks, 0 when the dir is absent
    [ -d "$1" ] || { echo 0; return; }
    find "$1" -mindepth 1 -maxdepth 1 -type l | wc -l | tr -d ' '
}

# --- local_target_uses_override -------------------------------------------
# A --local install for pi must land in ./.pi/skills, and must NOT create the
# re-rooted ./.pi/agent path that scope_path would otherwise produce.
local_target_uses_override() {
    local t=local_target_uses_override
    new_sandbox
    hs_install --local --agents pi
    local n; n="$(count_links "$PROJ/.pi/skills")"
    [ "$n" = "$SKILL_COUNT" ] || fail "$t" "expected $SKILL_COUNT links in ./.pi/skills, got $n"
    [ ! -e "$PROJ/.pi/agent" ] || fail "$t" "./.pi/agent was created — local override not applied"
    [ "$n" = "$SKILL_COUNT" ] && [ ! -e "$PROJ/.pi/agent" ] && pass "$t"
    rm -rf "$SB"
}

# --- global_target_uses_skills_dir ----------------------------------------
# The override is local-only: a --global install still uses skills_dir.
global_target_uses_skills_dir() {
    local t=global_target_uses_skills_dir
    new_sandbox
    mkdir -p "$FAKE_HOME/.pi"          # detect_dir must exist for global detection
    hs_install --global --agents pi --no-auto-upgrade
    local n; n="$(count_links "$FAKE_HOME/.pi/agent/skills")"
    if [ "$n" = "$SKILL_COUNT" ] && [ ! -e "$FAKE_HOME/.pi/skills" ]; then
        pass "$t"
    else
        fail "$t" "expected $SKILL_COUNT links in ~/.pi/agent/skills, got $n (and ~/.pi/skills must not exist)"
    fi
    rm -rf "$SB"
}

# --- override_absent_is_unchanged -----------------------------------------
# Harnesses without local_skills_dir keep the old mechanical resolution.
override_absent_is_unchanged() {
    local t=override_absent_is_unchanged
    new_sandbox
    hs_install --local --agents claude
    local n; n="$(count_links "$PROJ/.claude/skills")"
    if [ "$n" = "$SKILL_COUNT" ]; then pass "$t"; else
        fail "$t" "expected $SKILL_COUNT links in ./.claude/skills, got $n"
    fi
    rm -rf "$SB"
}

# --- local_uninstall_sweeps_override_dir ----------------------------------
# Uninstall resolves targets through the same code path, so the sweep must
# follow the override rather than the re-rooted default.
local_uninstall_sweeps_override_dir() {
    local t=local_uninstall_sweeps_override_dir
    new_sandbox
    hs_install --local --agents pi
    [ "$(count_links "$PROJ/.pi/skills")" = "$SKILL_COUNT" ] || { fail "$t" "setup install did not link"; rm -rf "$SB"; return; }
    hs_install --uninstall --local --agents pi
    local n; n="$(count_links "$PROJ/.pi/skills")"
    if [ "$n" = "0" ]; then pass "$t"; else fail "$t" "expected 0 links after uninstall, got $n"; fi
    rm -rf "$SB"
}

[ "$SKILL_COUNT" -gt 0 ] || { echo "FAIL: no skills found under $HS/skills"; exit 1; }

local_target_uses_override
global_target_uses_skills_dir
override_absent_is_unchanged
local_uninstall_sweeps_override_dir

if [ "$FAILED" = "0" ]; then
    echo "RESULT: PASS suite=install-agent-scopes cases=4"
else
    echo "RESULT: FAIL suite=install-agent-scopes"
fi
exit "$FAILED"
