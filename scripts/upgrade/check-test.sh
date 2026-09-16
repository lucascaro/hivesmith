#!/usr/bin/env bash
# Regression suite for scripts/upgrade/check.sh (hs-upgrade-check) and
# scripts/upgrade/sync-preamble.sh.
#
# Each case builds a scratch HOME, a bare "origin", and a clone of it that
# holds a copy of check.sh plus a stub install.sh recording its argv. The
# helper is always invoked through a symlink, as installed. Fetches are
# observed through remote.origin.uploadpack, a wrapper that logs the
# environment git hands it and can be told to sleep.
#
# Every "silent" assertion checks exit 0, empty stdout AND empty stderr: entry
# skills treat any output as a signal.
#
# Usage: bash scripts/upgrade/check-test.sh
set -uo pipefail

HS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FAILED=0
CASES=0
pass() { CASES=$((CASES + 1)); printf 'ok   %s\n' "$1"; }
fail() { CASES=$((CASES + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CI HIVESMITH_UPGRADE_CHECK HIVESMITH_UPGRADE_CHECK_TODAY HIVESMITH_UPGRADE_CHECK_INTERVAL

commit_origin() {  # $1 = message; commits in a scratch pusher clone and pushes
    local pusher="$SB/pusher"
    [[ -d "$pusher" ]] || git clone -q "$SB/origin.git" "$pusher" 2>/dev/null
    git -C "$pusher" pull -q --ff-only 2>/dev/null || true
    printf '%s\n' "$1" >> "$pusher/log.txt"
    git -C "$pusher" add log.txt
    git -C "$pusher" commit -qm "$1"
    git -C "$pusher" push -q origin HEAD:main 2>/dev/null
}

new_sandbox() {
    SB="$(mktemp -d)"
    SB="$(cd -P "$SB" && pwd)"
    export HOME="$SB/home"
    export HIVESMITH_DIR_CONFIG="$HOME/.hivesmith.toml"
    mkdir -p "$HOME/.hivesmith/bin"
    git init -q --bare -b main "$SB/origin.git"
    local seed="$SB/seed"
    git init -q -b main "$seed"
    mkdir -p "$seed/scripts/upgrade"
    cp "$HS/scripts/upgrade/check.sh" "$seed/scripts/upgrade/check.sh"
    cat > "$seed/install.sh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
printf '%s\n' "$*" >> "$HOME/install-calls.log"
if [[ -n "${STUB_INSTALL_FAIL:-}" ]]; then echo "stub: simulated failure" >&2; exit 7; fi
for a in "$@"; do
    if [[ "$a" == "--update" ]]; then
        # git pull writes new inodes, which a running bash never notices. Write
        # the incoming helper IN PLACE first (same inode) — the case where the
        # running helper would read shifted bytes — then fast-forward.
        git -C "$here" show '@{u}:scripts/upgrade/check.sh' > "$here/scripts/upgrade/check.sh"
        git -C "$here" reset -q --hard '@{u}'
    fi
done
exit 0
STUB
    chmod +x "$seed/install.sh" "$seed/scripts/upgrade/check.sh"
    printf 'seed\n' > "$seed/log.txt"
    git -C "$seed" add -A && git -C "$seed" commit -qm seed
    git -C "$seed" push -q "$SB/origin.git" HEAD:main 2>/dev/null
    CLONE="$SB/clone"
    git clone -q "$SB/origin.git" "$CLONE" 2>/dev/null
    # Log every fetch; sleep when asked.
    cat > "$SB/uploadpack" <<WRAP
#!/bin/sh
printf 'fetch prompt=%s ssh=%s\n' "\${GIT_TERMINAL_PROMPT:-}" "\${GIT_SSH_COMMAND:-}" >> "$SB/fetch.log"
[ -f "$SB/slow" ] && sleep 5
exec git-upload-pack "\$@"
WRAP
    chmod +x "$SB/uploadpack"
    git -C "$CLONE" config remote.origin.uploadpack "$SB/uploadpack"
    ln -s "$CLONE/scripts/upgrade/check.sh" "$HOME/.hivesmith/bin/hs-upgrade-check"
    HELPER="$HOME/.hivesmith/bin/hs-upgrade-check"
    STATE="$HOME/.hivesmith/upgrade-check"
}

# Mark the last fetch as recent so status does not start a background fetch.
fresh() { mkdir -p "$STATE"; date +%s > "$STATE/last-fetch"; }

run_helper() {  # captures OUT, ERR, RC
    local o e
    o="$(mktemp)"; e="$(mktemp)"
    "$HELPER" "$@" >"$o" 2>"$e"; RC=$?
    OUT="$(cat "$o")"; ERR="$(cat "$e")"
    rm -f "$o" "$e"
}

assert_silent() {  # $1 = case name
    if [[ "$RC" == 0 && -z "$OUT" && -z "$ERR" ]]; then pass "$1"
    else fail "$1" "rc=$RC out='$OUT' err='$ERR'"; fi
}

make_behind() {  # two upstream commits, fetched into the clone
    commit_origin one; commit_origin two
    git -C "$CLONE" fetch -q 2>/dev/null
    fresh
}

wait_for() {  # $1 = file; waits up to ~10s for it to exist
    local i=0
    while [[ ! -e "$1" && $i -lt 100 ]]; do sleep 0.1; i=$((i + 1)); done
    [[ -e "$1" ]]
}

# ---------------------------------------------------------------------------

current_clone_is_silent() {
    new_sandbox; fresh
    run_helper; assert_silent current_clone_is_silent
    rm -rf "$SB"
}

behind_prints_count_sha_and_dir() {
    local t=behind_prints_count_sha_and_dir
    new_sandbox; make_behind
    local sha; sha="$(git -C "$CLONE" rev-parse '@{u}')"
    run_helper
    if [[ "$RC" == 0 && "$OUT" == "BEHIND 2 $sha $CLONE" && -z "$ERR" ]]; then pass "$t"
    else fail "$t" "rc=$RC out='$OUT' err='$ERR'"; fi
    rm -rf "$SB"
}

resolves_clone_through_symlink() {
    local t=resolves_clone_through_symlink
    new_sandbox; make_behind
    # Relative chain: bin/rel -> ../link-dir/abs -> clone script.
    mkdir -p "$SB/link-dir" "$SB/bin"
    ln -s "$CLONE/scripts/upgrade/check.sh" "$SB/link-dir/abs"
    ln -s ../link-dir/abs "$SB/bin/rel"
    local out; out="$("$SB/bin/rel" 2>&1)"
    if [[ "$out" == "BEHIND 2 "*" $CLONE" ]]; then pass "$t"; else fail "$t" "got '$out'"; fi
    rm -rf "$SB"
}

no_upstream_is_silent() {
    new_sandbox; make_behind
    git -C "$CLONE" checkout -q -b local-only
    git -C "$CLONE" branch -q --unset-upstream 2>/dev/null || true
    rm -f "$SB/fetch.log" "$STATE/last-fetch"   # stale, so only the missing upstream stops a fetch
    run_helper; assert_silent no_upstream_is_silent
    sleep 1
    [[ ! -e "$SB/fetch.log" ]] || fail no_upstream_is_silent "fetched without an upstream"
    rm -rf "$SB"
}

not_a_git_repo_is_silent() {
    new_sandbox
    rm -rf "$CLONE/.git"
    run_helper; assert_silent not_a_git_repo_is_silent
    rm -rf "$SB"
}

offline_is_silent_and_exits_zero() {
    new_sandbox
    git -C "$CLONE" remote set-url origin "$SB/does-not-exist.git"
    run_helper  # stale last-fetch: triggers a background fetch that will fail
    assert_silent offline_is_silent_and_exits_zero
    sleep 1
    rm -rf "$SB"
}

stale_status_fetches_in_background_without_blocking() {
    local t=stale_status_fetches_in_background_without_blocking
    new_sandbox
    commit_origin one
    touch "$SB/slow"
    local start end; start="$(date +%s)"
    run_helper
    end="$(date +%s)"
    if (( end - start >= 3 )); then fail "$t" "status blocked for $((end - start))s"; rm -rf "$SB"; return; fi
    [[ -z "$OUT" && -z "$ERR" && "$RC" == 0 ]] || { fail "$t" "first call not silent: rc=$RC out='$OUT' err='$ERR'"; rm -rf "$SB"; return; }
    # The fetch finishes in the background; the lock is released afterwards.
    local i=0
    while [[ -d "$STATE/fetch.lock" && $i -lt 150 ]]; do sleep 0.1; i=$((i + 1)); done
    run_helper
    if [[ "$OUT" == "BEHIND 1 "* ]] && grep -q '^fetch' "$SB/fetch.log"; then pass "$t"
    else fail "$t" "after background fetch: out='$OUT' lock=$( [[ -d $STATE/fetch.lock ]] && echo held || echo free)"; fi
    rm -rf "$SB"
}

fresh_status_skips_fetch() {
    local t=fresh_status_skips_fetch
    new_sandbox; fresh
    run_helper; sleep 1
    if [[ ! -e "$SB/fetch.log" ]]; then pass "$t"; else fail "$t" "fetched despite fresh last-fetch"; fi
    rm -rf "$SB"
}

concurrent_calls_fetch_once() {
    local t=concurrent_calls_fetch_once
    new_sandbox
    touch "$SB/slow"
    "$HELPER" >/dev/null 2>&1; "$HELPER" >/dev/null 2>&1
    rm -f "$STATE/last-fetch"   # second call is stale again, but the lock is held
    "$HELPER" >/dev/null 2>&1
    wait_for "$SB/fetch.log" || { fail "$t" "no fetch at all"; rm -rf "$SB"; return; }
    sleep 6
    local n; n="$(grep -c '^fetch' "$SB/fetch.log")"
    if [[ "$n" == 1 ]]; then pass "$t"; else fail "$t" "expected 1 fetch, got $n"; fi
    rm -rf "$SB"
}

fetch_runs_non_interactive() {
    local t=fetch_runs_non_interactive
    new_sandbox
    run_helper
    wait_for "$SB/fetch.log" || { fail "$t" "no fetch"; rm -rf "$SB"; return; }
    if grep -q 'prompt=0 ' "$SB/fetch.log" && grep -q 'BatchMode=yes' "$SB/fetch.log"; then pass "$t"
    else fail "$t" "$(cat "$SB/fetch.log")"; fi
    sleep 0.5; rm -rf "$SB"
}

stale_lock_is_reclaimed() {
    local t=stale_lock_is_reclaimed
    new_sandbox
    mkdir -p "$STATE/fetch.lock"
    run_helper; sleep 1
    if [[ -e "$SB/fetch.log" ]]; then fail "$t" "fetched while a fresh lock was held"; rm -rf "$SB"; return; fi
    rm -f "$STATE/last-fetch"
    touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$STATE/fetch.lock"
    run_helper
    if wait_for "$SB/fetch.log"; then pass "$t"; else fail "$t" "stale lock not reclaimed"; fi
    sleep 0.5; rm -rf "$SB"
}

ci_env_is_silent() {
    new_sandbox; make_behind
    CI=true run_helper; assert_silent ci_env_is_silent
    rm -rf "$SB"
}

env_opt_out_is_silent() {
    new_sandbox; make_behind
    HIVESMITH_UPGRADE_CHECK=0 run_helper; assert_silent env_opt_out_is_silent
    rm -rf "$SB"
}

config_opt_out_is_silent() {
    new_sandbox; make_behind
    printf 'prefix = "hs-"\nupgrade_check = false\n' > "$HIVESMITH_DIR_CONFIG"
    run_helper; assert_silent config_opt_out_is_silent
    rm -rf "$SB"
}

snooze_day_suppresses_until_next_day() {
    local t=snooze_day_suppresses_until_next_day
    new_sandbox; make_behind
    HIVESMITH_UPGRADE_CHECK_TODAY=2026-01-01 "$HELPER" snooze-day
    local same next
    same="$(HIVESMITH_UPGRADE_CHECK_TODAY=2026-01-01 "$HELPER" 2>&1)"
    next="$(HIVESMITH_UPGRADE_CHECK_TODAY=2026-01-02 "$HELPER" 2>&1)"
    if [[ -z "$same" && "$next" == "BEHIND 2 "* ]]; then pass "$t"
    else fail "$t" "same-day='$same' next-day='$next'"; fi
    rm -rf "$SB"
}

snooze_until_change_suppresses_until_new_commit() {
    local t=snooze_until_change_suppresses_until_new_commit
    new_sandbox; make_behind
    local short; short="$("$HELPER" | awk '{print substr($3,1,12)}')"
    "$HELPER" snooze-until-change "$short"
    local quiet; quiet="$("$HELPER" 2>&1)"
    commit_origin three
    git -C "$CLONE" fetch -q 2>/dev/null
    local loud; loud="$("$HELPER" 2>&1)"
    if [[ -z "$quiet" && "$loud" == "BEHIND 3 "* ]]; then pass "$t"
    else fail "$t" "after snooze='$quiet' after new commit='$loud'"; fi
    rm -rf "$SB"
}

snooze_until_change_rejects_non_sha() {
    local t=snooze_until_change_rejects_non_sha
    new_sandbox
    run_helper snooze-until-change 'main; rm -rf /'
    if [[ "$RC" == 2 && ! -e "$STATE/snooze-sha" ]]; then pass "$t"; else fail "$t" "rc=$RC"; fi
    rm -rf "$SB"
}

never_invokes_install_no_upgrade_check() {
    local t=never_invokes_install_no_upgrade_check
    new_sandbox
    run_helper never
    if [[ "$RC" == 0 ]] && grep -qx -- '--global --no-upgrade-check' "$HOME/install-calls.log" && [[ "$OUT" == *"--upgrade-check"* ]]; then pass "$t"
    else fail "$t" "rc=$RC out='$OUT' calls='$(cat "$HOME/install-calls.log" 2>/dev/null)'"; fi
    rm -rf "$SB"
}

upgrade_success_clears_snoozes_and_prints_reload() {
    local t=upgrade_success_clears_snoozes_and_prints_reload
    new_sandbox; make_behind
    "$HELPER" snooze-day
    run_helper upgrade
    local behind; behind="$(git -C "$CLONE" rev-list --count 'HEAD..@{u}')"
    if [[ "$RC" == 0 && "$OUT" == *"Reload or restart"* && ! -e "$STATE/snooze-day" && "$behind" == 0 ]] \
       && grep -qx -- '--global --update' "$HOME/install-calls.log"; then pass "$t"
    else fail "$t" "rc=$RC out='$OUT' behind=$behind"; fi
    rm -rf "$SB"
}

upgrade_failure_propagates_exit_and_message() {
    local t=upgrade_failure_propagates_exit_and_message
    new_sandbox; make_behind
    STUB_INSTALL_FAIL=1 run_helper upgrade
    if [[ "$RC" == 7 && "$ERR" == *"simulated failure"* && "$ERR" == *"upgrade failed (exit 7)"* && "$OUT" != *"Reload"* ]]; then pass "$t"
    else fail "$t" "rc=$RC out='$OUT' err='$ERR'"; fi
    rm -rf "$SB"
}

upgrade_survives_self_rewrite() {
    local t=upgrade_survives_self_rewrite
    new_sandbox; make_behind
    # Upstream rewrites the helper: a long header shifts every byte offset, and
    # the new tail would print a different message if it were ever executed.
    local pusher="$SB/pusher"
    git -C "$pusher" pull -q --ff-only 2>/dev/null
    { printf '#!/usr/bin/env bash\n'; for _ in $(seq 1 200); do printf '# padding padding padding padding\n'; done
      printf 'echo SHIFTED-NEW-CODE; exit 0\n'; } > "$pusher/scripts/upgrade/check.sh"
    git -C "$pusher" commit -qam rewrite && git -C "$pusher" push -q origin HEAD:main 2>/dev/null
    git -C "$CLONE" fetch -q 2>/dev/null
    run_helper upgrade
    if [[ "$RC" == 0 && "$OUT" == *"hivesmith upgraded."* && "$OUT$ERR" != *SHIFTED* ]] \
       && grep -q SHIFTED "$CLONE/scripts/upgrade/check.sh"; then pass "$t"
    else fail "$t" "rc=$RC out='$OUT' err='$ERR'"; fi
    rm -rf "$SB"
}

# --- sync-preamble.sh ------------------------------------------------------

entry_skills_carry_canonical_preamble() {
    local t=entry_skills_carry_canonical_preamble
    local listed; listed="$(head -n1 "$HS/scripts/upgrade/preamble.md" | sed -E 's/^<!-- entry-skills: (.*) -->$/\1/')"
    local problems=""
    bash "$HS/scripts/upgrade/sync-preamble.sh" --check >/dev/null 2>&1 || problems+=" drift"
    local f name
    for f in "$HS"/skills/*/SKILL.md; do
        name="$(basename "$(dirname "$f")")"
        if grep -qF '<!-- BEGIN hivesmith upgrade-check' "$f"; then
            [[ " $listed " == *" $name "* ]] || problems+=" unlisted-marker:$name"
        fi
    done
    for name in $listed; do
        grep -qE '^allowed-tools:.*AskUserQuestion' "$HS/skills/$name/SKILL.md" || problems+=" no-AskUserQuestion:$name"
    done
    if [[ -z "$problems" ]]; then pass "$t"; else fail "$t" "$problems"; fi
}

sync_fixture() {  # scratch repo with two skills and a two-skill preamble
    SB="$(mktemp -d)"
    mkdir -p "$SB/scripts/upgrade" "$SB/skills/alpha" "$SB/skills/beta"
    cp "$HS/scripts/upgrade/sync-preamble.sh" "$SB/scripts/upgrade/"
    { printf '<!-- entry-skills: alpha beta -->\n'; printf '## Before you start: upgrade check\n\nBody line.\n'; } > "$SB/scripts/upgrade/preamble.md"
    for s in alpha beta; do
        printf -- '---\nname: %s\n---\n\n# %s\n\nIntro.\n\n## Steps\n\n1. Work.\n' "$s" "$s" > "$SB/skills/$s/SKILL.md"
    done
}

sync_inserts_block_when_markers_missing() {
    local t=sync_inserts_block_when_markers_missing
    sync_fixture
    bash "$SB/scripts/upgrade/sync-preamble.sh" --root "$SB" >/dev/null
    local f="$SB/skills/alpha/SKILL.md"
    # Block must land after the intro and before "## Steps".
    local begin steps intro
    begin="$(grep -n 'BEGIN hivesmith upgrade-check' "$f" | cut -d: -f1)"
    steps="$(grep -n '^## Steps' "$f" | cut -d: -f1)"
    intro="$(grep -n '^Intro\.' "$f" | cut -d: -f1)"
    if [[ -n "$begin" && "$intro" -lt "$begin" && "$begin" -lt "$steps" ]] && grep -q '^name: alpha$' "$f"; then pass "$t"
    else fail "$t" "begin=$begin intro=$intro steps=$steps"; fi
    rm -rf "$SB"
}

sync_rewrites_drifted_block_and_is_idempotent() {
    local t=sync_rewrites_drifted_block_and_is_idempotent
    sync_fixture
    local sync="$SB/scripts/upgrade/sync-preamble.sh"
    bash "$sync" --root "$SB" >/dev/null
    local good; good="$(cat "$SB/skills/beta/SKILL.md")"
    sed -i.bak 's/^Body line\.$/Hand edited./' "$SB/skills/beta/SKILL.md" && rm -f "$SB/skills/beta/SKILL.md.bak"
    local check_out check_rc
    check_out="$(bash "$sync" --root "$SB" --check 2>&1)"; check_rc=$?
    local edited; edited="$(cat "$SB/skills/beta/SKILL.md")"
    bash "$sync" --root "$SB" >/dev/null
    local restored; restored="$(cat "$SB/skills/beta/SKILL.md")"
    local second; second="$(bash "$sync" --root "$SB")"
    if [[ "$check_rc" == 1 && "$check_out" == *"drift: skills/beta/SKILL.md"* && "$check_out" != *alpha* \
          && "$edited" == *"Hand edited."* && "$restored" == "$good" && -z "$second" ]]; then pass "$t"
    else fail "$t" "check_rc=$check_rc check='$check_out' second='$second'"; fi
    rm -rf "$SB"
}

sync_refuses_missing_end_marker() {
    local t=sync_refuses_missing_end_marker
    sync_fixture
    local f="$SB/skills/alpha/SKILL.md"
    printf -- '---\nname: alpha\n---\n\n<!-- BEGIN hivesmith upgrade-check -->\nold\n\n## Steps\n\n1. Work.\n' > "$f"
    local before; before="$(cat "$f")"
    local rc=0 err
    err="$(bash "$SB/scripts/upgrade/sync-preamble.sh" --root "$SB" 2>&1 >/dev/null)" || rc=$?
    if [[ "$rc" == 2 && "$err" == *"without a matching END marker"* && "$(cat "$f")" == "$before" ]]; then pass "$t"
    else fail "$t" "rc=$rc err='$err'"; fi
    rm -rf "$SB"
}

# ---------------------------------------------------------------------------

current_clone_is_silent
behind_prints_count_sha_and_dir
resolves_clone_through_symlink
no_upstream_is_silent
not_a_git_repo_is_silent
offline_is_silent_and_exits_zero
stale_status_fetches_in_background_without_blocking
fresh_status_skips_fetch
concurrent_calls_fetch_once
fetch_runs_non_interactive
stale_lock_is_reclaimed
ci_env_is_silent
env_opt_out_is_silent
config_opt_out_is_silent
snooze_day_suppresses_until_next_day
snooze_until_change_suppresses_until_new_commit
snooze_until_change_rejects_non_sha
never_invokes_install_no_upgrade_check
upgrade_success_clears_snoozes_and_prints_reload
upgrade_failure_propagates_exit_and_message
upgrade_survives_self_rewrite
entry_skills_carry_canonical_preamble
sync_inserts_block_when_markers_missing
sync_rewrites_drifted_block_and_is_idempotent
sync_refuses_missing_end_marker

if [[ "$FAILED" == 0 ]]; then
    echo "RESULT: PASS suite=upgrade-check cases=$CASES"
else
    echo "RESULT: FAIL suite=upgrade-check"
fi
exit "$FAILED"
