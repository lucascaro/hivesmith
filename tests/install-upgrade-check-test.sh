#!/usr/bin/env bash
# Regression suite for install.sh's side of the entry-skill upgrade check:
# the --upgrade-check / --no-upgrade-check opt-out, the removal of the legacy
# auto-upgrade cron and flags, --status reporting, the hs-upgrade-check bin
# link, uninstall cleanup, and the post-pull re-exec in --update.
#
# Global installs reach outside HOME ($HIVESMITH_DIR/.rendered and the user's
# crontab), so every case runs install.sh from a scratch copy of the repo with
# a recording `crontab` stub first on PATH. The real checkout and crontab are
# never touched.
#
# Usage: bash tests/install-upgrade-check-test.sh
set -uo pipefail

HS="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILED=0
CASES=0
pass() { CASES=$((CASES + 1)); printf 'ok   %s\n' "$1"; }
fail() { CASES=$((CASES + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; FAILED=1; }

unset CI HIVESMITH_UPGRADE_CHECK HIVESMITH_UPDATE_REEXEC
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

LEGACY_CRON='17 4 * * * /somewhere/hivesmith/install.sh --update >/dev/null 2>&1'
FOREIGN_CRON='0 1 * * * /usr/local/bin/backup'

new_sandbox() {
    SB="$(mktemp -d)"; SB="$(cd -P "$SB" && pwd)"
    FAKE_HOME="$SB/home"; PROJ="$SB/proj"
    mkdir -p "$FAKE_HOME/.claude" "$PROJ" "$SB/hs" "$SB/bin"
    CFG="$FAKE_HOME/.hivesmith.toml"
    export HIVESMITH_DIR_CONFIG="$CFG"
    export HIVESMITH_LOCAL_CONFIG="$PROJ/.hivesmith.toml"
    cp -R "$HS/install.sh" "$HS/agents.json" "$HS/skills" "$HS/agents" "$HS/scripts" "$SB/hs/"
    HS_RUN="$SB/hs"
    CRONTAB="$SB/crontab.txt"
    cat > "$SB/bin/crontab" <<STUB
#!/bin/sh
case "\$1" in
  -l) [ -f "$CRONTAB" ] || exit 1; cat "$CRONTAB" ;;
  -)  cat > "$CRONTAB.new" && mv "$CRONTAB.new" "$CRONTAB" ;;  # like crontab(1): read all, then replace
  *)  exit 2 ;;
esac
STUB
    chmod +x "$SB/bin/crontab"
}

hs_install() {  # stdout+stderr -> $OUT, exit -> $RC
    OUT="$(cd "$PROJ" && HOME="$FAKE_HOME" PATH="$SB/bin:$PATH" bash "$HS_RUN/install.sh" "$@" </dev/null 2>&1)"
    RC=$?
}

# ---------------------------------------------------------------------------

default_install_links_helper_and_status_on() {
    local t=default_install_links_helper_and_status_on
    new_sandbox
    hs_install --global --agents claude
    local link="$FAKE_HOME/.hivesmith/bin/hs-upgrade-check"
    local target; target="$(readlink "$link" 2>/dev/null)"
    hs_install --status --global
    if [[ "$target" == "$HS_RUN/scripts/upgrade/check.sh" && "$OUT" == *"upgrade-check: on"* ]] \
       && ! grep -qs upgrade_check "$CFG"; then pass "$t"
    else fail "$t" "link='$target' status='$(grep upgrade-check <<< "$OUT")'"; fi
    rm -rf "$SB"
}

migration_removes_cron_entry_and_auto_upgrade_key() {
    local t=migration_removes_cron_entry_and_auto_upgrade_key
    new_sandbox
    printf '%s\n%s\n' "$FOREIGN_CRON" "$LEGACY_CRON" > "$CRONTAB"
    printf 'prefix = "hs-"\nauto_upgrade = true\n' > "$CFG"
    hs_install --global --agents claude
    if [[ "$RC" == 0 ]] && ! grep -q hivesmith "$CRONTAB" && grep -qF "$FOREIGN_CRON" "$CRONTAB" \
       && ! grep -q auto_upgrade "$CFG" && grep -q '^prefix = "hs-"$' "$CFG"; then pass "$t"
    else fail "$t" "rc=$RC crontab='$(cat "$CRONTAB")' cfg='$(cat "$CFG")'"; fi
    rm -rf "$SB"
}

migration_handles_cron_with_only_our_line() {
    # grep -v exits 1 when nothing survives; under pipefail that used to abort
    # install.sh after the crontab had already been emptied.
    local t=migration_handles_cron_with_only_our_line
    new_sandbox
    printf '%s\n' "$LEGACY_CRON" > "$CRONTAB"
    hs_install --global --agents claude
    if [[ "$RC" == 0 && "$OUT" == *"Done."* ]] && ! grep -q hivesmith "$CRONTAB"; then pass "$t"
    else fail "$t" "rc=$RC tail='$(tail -3 <<< "$OUT")'"; fi
    rm -rf "$SB"
}

removed_flags_exit_nonzero_with_pointer() {
    local t=removed_flags_exit_nonzero_with_pointer
    new_sandbox
    local bad="" flag
    for flag in --auto-upgrade --no-auto-upgrade --no-auto-update; do
        hs_install --global --agents claude "$flag"
        [[ "$RC" != 0 && "$OUT" == *"$flag was removed"* && "$OUT" == *"--no-upgrade-check"* ]] || bad+=" $flag(rc=$RC)"
    done
    [[ -e "$CRONTAB" ]] && bad+=" crontab-written"
    if [[ -z "$bad" ]]; then pass "$t"; else fail "$t" "$bad"; fi
    rm -rf "$SB"
}

no_upgrade_check_persists_across_reinstall() {
    local t=no_upgrade_check_persists_across_reinstall
    new_sandbox
    local bad=""
    hs_install --global --agents claude --no-upgrade-check
    grep -qx 'upgrade_check = false' "$CFG" || bad+=" not-written"
    hs_install --global --agents claude
    grep -qx 'upgrade_check = false' "$CFG" || bad+=" lost-on-reinstall"
    hs_install --status --global
    [[ "$OUT" == *"upgrade-check: off"*"install.sh --upgrade-check"* ]] || bad+=" status-off"
    hs_install --global --agents claude --upgrade-check
    ! grep -q upgrade_check "$CFG" || bad+=" not-removed"
    hs_install --status --global
    [[ "$OUT" == *"upgrade-check: on"* ]] || bad+=" status-on"
    HIVESMITH_UPGRADE_CHECK=0 hs_install --status --global
    [[ "$OUT" == *"upgrade-check: disabled in this shell"* ]] || bad+=" status-env"
    if [[ -z "$bad" ]]; then pass "$t"; else fail "$t" "$bad"; fi
    rm -rf "$SB"
}

status_warns_and_doctor_fails_on_legacy_cron() {
    local t=status_warns_and_doctor_fails_on_legacy_cron
    new_sandbox
    hs_install --global --agents claude
    printf '%s\n' "$LEGACY_CRON" > "$CRONTAB"
    hs_install --doctor --global
    if [[ "$RC" != 0 && "$OUT" == *"legacy auto-upgrade cron is still installed"* ]]; then pass "$t"
    else fail "$t" "rc=$RC"; fi
    rm -rf "$SB"
}

local_scope_rejects_upgrade_check_flags() {
    local t=local_scope_rejects_upgrade_check_flags
    new_sandbox
    local bad="" flag
    for flag in --upgrade-check --no-upgrade-check; do
        hs_install --local --agents claude "$flag"
        [[ "$RC" != 0 && "$OUT" == *"global-only"* ]] || bad+=" $flag(rc=$RC)"
    done
    [[ ! -e "$CFG" && ! -e "$PROJ/.hivesmith.toml" ]] || bad+=" config-written"
    if [[ -z "$bad" ]]; then pass "$t"; else fail "$t" "$bad"; fi
    rm -rf "$SB"
}

uninstall_removes_helper_and_state_keeps_optout() {
    local t=uninstall_removes_helper_and_state_keeps_optout
    new_sandbox
    hs_install --global --agents claude --no-upgrade-check
    mkdir -p "$FAKE_HOME/.hivesmith/upgrade-check" && date +%s > "$FAKE_HOME/.hivesmith/upgrade-check/last-fetch"
    printf '%s\n' "$LEGACY_CRON" > "$CRONTAB"
    hs_install --uninstall --global --agents claude
    local bad=""
    [[ "$RC" == 0 ]] || bad+=" rc=$RC"
    [[ ! -e "$FAKE_HOME/.hivesmith/bin/hs-upgrade-check" && ! -L "$FAKE_HOME/.hivesmith/bin/hs-upgrade-check" ]] || bad+=" link-left"
    [[ ! -e "$FAKE_HOME/.hivesmith/upgrade-check" ]] || bad+=" state-left"
    grep -qx 'upgrade_check = false' "$CFG" || bad+=" optout-lost"
    ! grep -q hivesmith "$CRONTAB" || bad+=" cron-left"
    if [[ -z "$bad" ]]; then pass "$t"; else fail "$t" "$bad"; fi
    rm -rf "$SB"
}

update_reexecs_new_install_sh_after_pull() {
    local t=update_reexecs_new_install_sh_after_pull
    new_sandbox
    # Turn the scratch copy into origin + clone so --update has something to pull.
    git -C "$SB/hs" init -q -b main && git -C "$SB/hs" add -A && git -C "$SB/hs" commit -qm base
    git clone -q --bare "$SB/hs" "$SB/origin.git"
    git clone -q "$SB/origin.git" "$SB/clone"
    HS_RUN="$SB/clone"
    hs_install --global --agents claude
    [[ "$RC" == 0 ]] || { fail "$t" "setup install rc=$RC"; rm -rf "$SB"; return; }
    # Upstream: a marker printed early by the NEW install.sh only.
    git clone -q "$SB/origin.git" "$SB/pusher"
    perl -0pi -e 's/\nsetup_colors\n/\nsetup_colors\nsay "REEXEC-MARKER"\n/' "$SB/pusher/install.sh"
    git -C "$SB/pusher" commit -qam marker && git -C "$SB/pusher" push -q origin HEAD:main 2>/dev/null
    printf '%s\n' "$LEGACY_CRON" > "$CRONTAB"
    printf 'auto_upgrade = true\n' >> "$CFG"
    hs_install --global --update
    local n; n="$(grep -c REEXEC-MARKER <<< "$OUT")"
    if [[ "$RC" == 0 && "$n" == 1 && "$OUT" == *"Done."* ]] && ! grep -q hivesmith "$CRONTAB" && ! grep -q auto_upgrade "$CFG"; then pass "$t"
    else fail "$t" "rc=$RC markers=$n tail='$(tail -3 <<< "$OUT")'"; fi
    rm -rf "$SB"
}

# ---------------------------------------------------------------------------

default_install_links_helper_and_status_on
migration_removes_cron_entry_and_auto_upgrade_key
migration_handles_cron_with_only_our_line
removed_flags_exit_nonzero_with_pointer
no_upgrade_check_persists_across_reinstall
status_warns_and_doctor_fails_on_legacy_cron
local_scope_rejects_upgrade_check_flags
uninstall_removes_helper_and_state_keeps_optout
update_reexecs_new_install_sh_after_pull

if [[ "$FAILED" == 0 ]]; then
    echo "RESULT: PASS suite=install-upgrade-check cases=$CASES"
else
    echo "RESULT: FAIL suite=install-upgrade-check"
fi
exit "$FAILED"
