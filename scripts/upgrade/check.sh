#!/usr/bin/env bash
# hivesmith upgrade check: is this clone behind upstream, and what did the
# operator say last time we asked?
#
# Installed as ~/.hivesmith/bin/hs-upgrade-check. Entry skills run it before
# their work (see scripts/upgrade/preamble.md); nothing runs it on a schedule.
#
# WHY IT NEVER TOUCHES THE NETWORK ON THE CALLER'S PATH
#
# It runs at the start of an interactive skill. A fetch there would put a
# network round-trip (or an ssh passphrase prompt) in front of every
# invocation. `status` answers from local refs only and, when the last fetch is
# older than the interval, starts a detached, non-interactive fetch whose
# result the *next* invocation sees.
#
# WHY THE WHOLE BODY IS INSIDE main()
#
# `upgrade` runs install.sh --update, which replaces this very file. Bash reads
# a script incrementally from its open file descriptor. `git pull` writes a new
# inode, so the old descriptor keeps seeing the old bytes — but an in-place
# rewrite (a dev `cp` over the checkout, an editor) would not. With every
# statement inside functions and `main "$@"; exit` on one final line, nothing
# is read from the file after main starts.
#
# Usage:
#   hs-upgrade-check [status]                  print "BEHIND <n> <sha> <dir>" or nothing
#   hs-upgrade-check upgrade                   run install.sh --update
#   hs-upgrade-check snooze-day                don't ask again today
#   hs-upgrade-check snooze-until-change <sha> don't ask until upstream moves past <sha>
#   hs-upgrade-check never                     persist upgrade_check = false
#
# `status` always exits 0 and is silent unless there is something to ask.
# Env: HIVESMITH_UPGRADE_CHECK=0 or CI set -> silent.
#      HIVESMITH_UPGRADE_CHECK_INTERVAL      seconds between fetches (default 21600)
#      HIVESMITH_UPGRADE_CHECK_TODAY         YYYY-MM-DD override (tests)
#      HIVESMITH_DIR_CONFIG                  config path (default ~/.hivesmith.toml)
set -euo pipefail

usage() {
    sed -n '/^# Usage:/,/^# Env:/p' "$SELF" | sed '$d; s/^# \{0,1\}//'
}

# Follow the symlink chain to the real script, resolving relative link targets
# against the link's own directory. No `readlink -f`: BSD readlink lacks it.
resolve_self() {
    local path="$1" dir target
    while [[ -L "$path" ]]; do
        dir="$(cd -P "$(dirname "$path")" && pwd)"
        target="$(readlink "$path")"
        if [[ "$target" == /* ]]; then path="$target"; else path="$dir/$target"; fi
    done
    printf '%s/%s\n' "$(cd -P "$(dirname "$path")" && pwd)" "$(basename "$path")"
}

today() { printf '%s\n' "${HIVESMITH_UPGRADE_CHECK_TODAY:-$(date +%F)}"; }

read_state() { cat "$STATE_DIR/$1" 2>/dev/null || true; }

opted_out() {
    [[ -f "$CONFIG" ]] && grep -Eq '^[[:space:]]*upgrade_check[[:space:]]*=[[:space:]]*false' "$CONFIG"
}

# Start a detached fetch when the last one is older than the interval. Never
# blocks, never prompts, never fails the caller.
maybe_refresh() {
    local interval="${HIVESMITH_UPGRADE_CHECK_INTERVAL:-21600}" now last lock
    [[ "$interval" =~ ^[0-9]+$ ]] || interval=21600
    now="$(date +%s)"
    last="$(read_state last-fetch)"
    [[ "$last" =~ ^[0-9]+$ ]] || last=0
    (( now - last >= interval )) || return 0

    lock="$STATE_DIR/fetch.lock"
    # A fetch killed before it could release the lock would otherwise switch
    # the check off for good. `find -mmin` is the portable (BSD/GNU) age test.
    if [[ -d "$lock" && -n "$(find "$lock" -maxdepth 0 -mmin +60 2>/dev/null)" ]]; then
        rmdir "$lock" 2>/dev/null || true
    fi
    mkdir "$lock" 2>/dev/null || return 0
    printf '%s\n' "$now" > "$STATE_DIR/last-fetch" || true

    # BatchMode: ssh must not ask for a passphrase or host key via /dev/tty.
    # Keepalive and low-speed caps stop a stalled fetch from outliving the lock
    # reclaim above. nohup + closed fds let it survive the caller's tool call.
    # shellcheck disable=SC2016  # $1/$2 are expanded by the inner sh, on purpose
    GIT_TERMINAL_PROMPT=0 \
    GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2" \
        nohup sh -c 'git -C "$1" -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 fetch --quiet; rmdir "$2"' \
        _ "$CLONE" "$lock" </dev/null >/dev/null 2>&1 &
    return 0
}

cmd_status() {
    [[ -z "${CI:-}" ]] || return 0
    [[ "${HIVESMITH_UPGRADE_CHECK:-1}" != "0" ]] || return 0
    ! opted_out || return 0
    git -C "$CLONE" rev-parse --git-dir >/dev/null 2>&1 || return 0
    git -C "$CLONE" rev-parse --verify --quiet '@{u}' >/dev/null 2>&1 || return 0
    mkdir -p "$STATE_DIR" 2>/dev/null || return 0

    maybe_refresh

    local upstream behind
    upstream="$(git -C "$CLONE" rev-parse '@{u}' 2>/dev/null)" || return 0
    behind="$(git -C "$CLONE" rev-list --count 'HEAD..@{u}' 2>/dev/null)" || return 0
    [[ "$behind" =~ ^[0-9]+$ ]] && (( behind > 0 )) || return 0
    [[ "$(read_state snooze-day)" != "$(today)" ]] || return 0
    [[ "$(read_state snooze-sha)" != "$upstream" ]] || return 0
    printf 'BEHIND %s %s %s\n' "$behind" "$upstream" "$CLONE"
}

cmd_upgrade() {
    local rc=0
    bash "$CLONE/install.sh" --global --update || rc=$?
    if (( rc != 0 )); then
        printf 'hs-upgrade-check: upgrade failed (exit %s) — see output above\n' "$rc" >&2
        return "$rc"
    fi
    rm -f "$STATE_DIR/snooze-day" "$STATE_DIR/snooze-sha"
    printf 'hivesmith upgraded. Reload or restart this session so the new skills take effect.\n'
}

cmd_never() {
    local out rc=0
    out="$(bash "$CLONE/install.sh" --global --no-upgrade-check 2>&1)" || rc=$?
    if (( rc != 0 )); then
        printf '%s\n' "$out" >&2
        printf 'hs-upgrade-check: could not record the opt-out (exit %s)\n' "$rc" >&2
        return "$rc"
    fi
    printf 'Upgrade check disabled. Re-enable with: %s/install.sh --upgrade-check\n' "$CLONE"
}

main() {
    SELF="$(resolve_self "${BASH_SOURCE[0]}")"
    CLONE="$(cd "$(dirname "$SELF")/../.." && pwd)"
    STATE_DIR="$HOME/.hivesmith/upgrade-check"
    CONFIG="${HIVESMITH_DIR_CONFIG:-$HOME/.hivesmith.toml}"

    case "${1:-status}" in
        status) cmd_status ;;
        upgrade) cmd_upgrade ;;
        snooze-day)
            mkdir -p "$STATE_DIR"
            today > "$STATE_DIR/snooze-day" ;;
        snooze-until-change)
            if [[ ! "${2:-}" =~ ^[0-9a-f]{7,40}$ ]]; then
                printf 'hs-upgrade-check: snooze-until-change needs the upstream sha from BEHIND\n' >&2
                return 2
            fi
            mkdir -p "$STATE_DIR"
            local full
            full="$(git -C "$CLONE" rev-parse --verify --quiet "$2^{commit}" 2>/dev/null)" || full="$2"
            printf '%s\n' "$full" > "$STATE_DIR/snooze-sha" ;;
        never) cmd_never ;;
        -h|--help) usage ;;
        *) usage >&2; return 2 ;;
    esac
}

main "$@"; exit
