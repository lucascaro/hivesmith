#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required (used to parse agents.json)." >&2
    exit 1
fi

# install.sh — fan-out symlinks from hivesmith/skills/* (and agents/*) into each
# detected AI agent's config dir (Claude, Codex, Factory, Gemini, Copilot, pi).
# Run with --help for the full flag list; usage() below is the canonical doc.

HIVESMITH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RENDER_ROOT="$HIVESMITH_DIR/.rendered"
# CONFIG is resolved by scope after arg parsing (global: ~/.hivesmith.toml,
# local: ./.hivesmith.toml).

MODE="install"
AUTO_UPGRADE_CLI=""   # "" | "1" | "0" — set only when the user passed a flag
DRY_RUN=0
PREFIX_CLI=""
PREFIX_CLI_SET=0
SCOPE="global"        # global | local
SCOPE_SET=0           # 1 if --global/--local was passed explicitly
FORCE=0
NO_COLOR_CLI=0
AGENTS_CLI=""         # comma-separated harness names; empty = all detected
AGENTS_CLI_SET=0

# ---- Colored output ------------------------------------------------------
# Colour only when stdout is a TTY, NO_COLOR is unset, and --no-color absent.
# Functions reference the C_* vars at call time, so they stay plain until
# setup_colors() fills them in after arg parsing.
C_RESET=""; C_RED=""; C_YELLOW=""; C_GREEN=""; C_BOLD=""; C_CYAN=""
setup_colors() {
    [[ "$NO_COLOR_CLI" == "1" || -n "${NO_COLOR:-}" || ! -t 1 ]] && return
    C_RESET=$'\033[0m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
    C_GREEN=$'\033[32m'; C_BOLD=$'\033[1m'; C_CYAN=$'\033[36m'
}
say()     { printf '%s\n' "$*"; }
ok()      { printf '%s%s%s\n' "$C_GREEN" "$*" "$C_RESET"; }
# warn goes to stdout: these are part of the reconcile report stream (callers
# and CI grep them from stdout). err goes to stderr for fatal, aborting errors.
warn()    { printf '%sWARN:%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
err()     { printf '%sError:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
heading() { printf '%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }
tag()     { printf '%s[%s]%s' "$C_CYAN" "$1" "$C_RESET"; }   # colored [name]
run() {
    if [[ "$DRY_RUN" == "1" ]]; then say "DRY: $*"; else "$@"; fi
}

# A non-hivesmith path ($1) is blocking a link. With --force, remove it (scoped
# to that exact path) and return 0 so the caller proceeds; otherwise warn and
# return 1 so the caller skips it.
force_or_skip() {
    if [[ "$FORCE" == "1" ]]; then
        warn "$1 is not a hivesmith symlink — overwriting (--force)"
        run rm -rf "$1"
        return 0
    fi
    warn "$1 exists and is not a hivesmith symlink — skipping (use --force to overwrite)"
    return 1
}

usage() {
    cat <<'EOF'
install.sh — fan-out symlinks from hivesmith/skills/* (and agents/*) into each
detected AI agent's config dir (Claude, Codex, Factory, Gemini, Copilot, pi).

Modes (default: install):
  ./install.sh                   install / reconcile symlinks (idempotent)
  ./install.sh --update          git pull then reconcile symlinks
  ./install.sh --uninstall       remove all hivesmith symlinks (this scope)
  ./install.sh --status          show what is installed (global + local)
  ./install.sh --doctor          validate installs; non-zero exit on problems

Scope (default: global):
  --global                       install into ~/.<agent>/ (home dirs)
  --local                        install into ./.<agent>/ (current project),
                                 using per-project config ./.hivesmith.toml
  --agents claude,codex          restrict/select target harnesses
                                 (local: also remembered in ./.hivesmith.toml)

Modifiers:
  --force                        overwrite non-hivesmith files/symlinks that
                                 block a skill (e.g. a real dir where a symlink
                                 should go). Only deletes inside the target dir.
  --prefix hs-                   namespace every skill (e.g. /hs-release).
  --prefix ""                    clear a stored prefix.
  --auto-upgrade                 opt in to a daily auto-upgrade cron (global only)
  --no-auto-upgrade              opt out (also removes an existing cron entry)
  --dry-run                      print what would happen, change nothing
  --no-color                     disable ANSI color (also off when not a TTY
                                 or when NO_COLOR is set)
  -h, --help                     show this help

Config:
  Global scope reads/writes ~/.hivesmith.toml (override: HIVESMITH_DIR_CONFIG).
  Local scope reads/writes ./.hivesmith.toml (override: HIVESMITH_LOCAL_CONFIG)
  and never touches the global config. Keys: prefix, disable = [...],
  agents = [...], auto_upgrade (global only), and [agents.<name>] only = [...].
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update) MODE="update"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --status) MODE="status"; shift ;;
        --doctor) MODE="doctor"; shift ;;
        --global) SCOPE="global"; SCOPE_SET=1; shift ;;
        --local) SCOPE="local"; SCOPE_SET=1; shift ;;
        --force) FORCE=1; shift ;;
        --no-color) NO_COLOR_CLI=1; shift ;;
        --agents)
            [[ $# -ge 2 && -n "$2" ]] || { echo "Error: --agents requires a non-empty value (e.g. --agents claude,codex)" >&2; exit 1; }
            AGENTS_CLI="$2"; AGENTS_CLI_SET=1; shift 2 ;;
        --agents=*)
            AGENTS_CLI="${1#--agents=}"; AGENTS_CLI_SET=1
            [[ -n "$AGENTS_CLI" ]] || { echo "Error: --agents requires a non-empty value (e.g. --agents=claude,codex)" >&2; exit 1; }
            shift ;;
        --auto-upgrade) AUTO_UPGRADE_CLI=1; shift ;;
        --no-auto-upgrade) AUTO_UPGRADE_CLI=0; shift ;;
        --no-auto-update)
            printf 'install: --no-auto-update is deprecated; use --no-auto-upgrade. Persisting auto_upgrade=false.\n' >&2
            AUTO_UPGRADE_CLI=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --prefix) PREFIX_CLI="${2-}"; PREFIX_CLI_SET=1; shift 2 ;;
        --prefix=*) PREFIX_CLI="${1#--prefix=}"; PREFIX_CLI_SET=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

setup_colors

# ---- Scope + config resolution -------------------------------------------
# Scope decides target dirs (home vs cwd) and which config file we read/write.
if [[ "$SCOPE" == "local" ]]; then
    CONFIG="${HIVESMITH_LOCAL_CONFIG:-$PWD/.hivesmith.toml}"
    if [[ -n "$AUTO_UPGRADE_CLI" ]]; then
        err "--auto-upgrade/--no-auto-upgrade is global-only (cron is a global side effect); not valid with --local."
        exit 1
    fi
else
    CONFIG="${HIVESMITH_DIR_CONFIG:-$HOME/.hivesmith.toml}"
fi

# ---- Parse config (very small TOML subset) -------------------------------
# Supports:
#   prefix = "hs-"
#   disable = ["a", "b"]        # skill names and/or subagent names
#   agents = ["claude", ...]    # local scope: remembered harness selection
#   auto_upgrade = true         # global scope only
#   [agents.<name>]
#   only = ["x", "y"]           # skills only — does not apply to subagents
#
# Exposes:
#   DISABLE_GLOBAL   — space-separated list
#   PREFIX_CONFIG    — value of top-level prefix, or empty
#   AGENTS_CONFIG    — space-separated harness names (AGENTS_CONFIG_SET=1 if present)
#   agent_only_<name> — space-separated list, set only if "only" present

DISABLE_GLOBAL=""
PREFIX_CONFIG=""
AUTO_UPGRADE_CONFIG=""   # "" | "1" | "0" — only set if the key is present
AGENTS_CONFIG=""         # space-separated harness names (local scope selection)
AGENTS_CONFIG_SET=0      # 1 if an `agents = [...]` key was present
AGENT_ONLY_TABLE=""  # pipe-delimited records: "|name:val1 val2|name:val3|"

agent_only_for() {
    local name="$1"
    if [[ "$AGENT_ONLY_TABLE" =~ \|"${name}":([^\|]*) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

if [[ -f "$CONFIG" ]]; then
    current_agent=""
    while IFS= read -r line; do
        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        [[ -z "$line" ]] && continue
        if [[ "$line" =~ ^\[agents\.([a-zA-Z0-9_-]+)\] ]]; then
            current_agent="${BASH_REMATCH[1]}"; continue
        fi
        if [[ "$line" =~ ^\[ ]]; then current_agent=""; continue; fi
        if [[ -z "$current_agent" && "$line" =~ ^disable[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
            DISABLE_GLOBAL="$(echo "${BASH_REMATCH[1]}" | tr -d '",' )"
        fi
        if [[ -z "$current_agent" && "$line" =~ ^prefix[[:space:]]*=[[:space:]]*\"([^\"]*)\" ]]; then
            PREFIX_CONFIG="${BASH_REMATCH[1]}"
        fi
        if [[ -z "$current_agent" && "$line" =~ ^auto_upgrade[[:space:]]*=[[:space:]]*(true|false) ]]; then
            case "${BASH_REMATCH[1]}" in
                true)  AUTO_UPGRADE_CONFIG=1 ;;
                false) AUTO_UPGRADE_CONFIG=0 ;;
            esac
        fi
        if [[ -z "$current_agent" && "$line" =~ ^agents[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
            AGENTS_CONFIG="$(echo "${BASH_REMATCH[1]}" | tr -d '",' )"
            AGENTS_CONFIG_SET=1
        fi
        if [[ -n "$current_agent" && "$line" =~ ^only[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
            vals="$(echo "${BASH_REMATCH[1]}" | tr -d '",' )"
            AGENT_ONLY_TABLE="${AGENT_ONLY_TABLE}|${current_agent}:${vals}"
        fi
    done < "$CONFIG"
    AGENT_ONLY_TABLE="${AGENT_ONLY_TABLE}|"
fi

# Upsert or remove a top-level key in $CONFIG.
#   $1 = bare key name (e.g. "prefix")
#   $2 = full rendered line (e.g. 'prefix = "hs-"'), or "" to remove the key
# Honors --dry-run. Inserts before the first [section] header, else appends.
upsert_config_key() {
    local key="$1" rendered="$2" line
    if [[ "$DRY_RUN" == "1" ]]; then
        if [[ -z "$rendered" ]]; then say "DRY: would remove $key from $CONFIG"
        else say "DRY: would write $rendered to $CONFIG"; fi
        return 0
    fi
    touch "$CONFIG"
    local tmp_cfg found=0; tmp_cfg="$(mktemp)"
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*"$key"[[:space:]]*= ]]; then
            [[ -n "$rendered" ]] && echo "$rendered" >> "$tmp_cfg"
            found=1
        else
            echo "$line" >> "$tmp_cfg"
        fi
    done < "$CONFIG"
    if [[ "$found" == "0" && -n "$rendered" ]]; then
        if grep -q '^\[' "$tmp_cfg" 2>/dev/null; then
            local tmp_cfg2; tmp_cfg2="$(mktemp)"
            awk -v line="$rendered" '!d && /^\[/ { print line; print ""; d=1 } { print }' "$tmp_cfg" > "$tmp_cfg2"
            mv "$tmp_cfg2" "$tmp_cfg"
        else
            echo "$rendered" >> "$tmp_cfg"
        fi
    fi
    mv "$tmp_cfg" "$CONFIG"
    return 0
}

# ---- Resolve effective prefix --------------------------------------------

if [[ "$PREFIX_CLI_SET" == "1" ]]; then
    PREFIX="$PREFIX_CLI"
else
    PREFIX="$PREFIX_CONFIG"
fi

# Validate: empty OR [a-z0-9][a-z0-9-]* (reject leading dash, uppercase, spaces)
if [[ -n "$PREFIX" && ! "$PREFIX" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    echo "Invalid --prefix '$PREFIX' (allowed: [a-z0-9][a-z0-9-]*)" >&2
    exit 1
fi

# Writeback: upsert prefix line in config when CLI set it (and not uninstall).
# Empty prefix removes the key.
if [[ "$PREFIX_CLI_SET" == "1" && "$MODE" != "uninstall" ]]; then
    if [[ -n "$PREFIX" ]]; then
        upsert_config_key prefix "prefix = \"$PREFIX\""
    else
        upsert_config_key prefix ""
    fi
fi

# ---- Resolve effective auto-upgrade --------------------------------------
# Tri-state resolution (first match wins):
#   1. --auto-upgrade / --no-auto-upgrade on this run
#   2. auto_upgrade key in ~/.hivesmith.toml
#   3. Implicit opt-in migration: existing cron already installed
#   4. Default: off (opt-in)
# $AUTO_UPGRADE is the resolved 0/1 flag. $AUTO_UPGRADE_PERSIST, if set,
# is what to write back to the config this run.

CRON_GREP='hivesmith/install.sh --update\|hivesmith .*install.sh.* --update'
has_hivesmith_cron() { crontab -l 2>/dev/null | grep -q "$CRON_GREP"; }

AUTO_UPGRADE=0
AUTO_UPGRADE_PERSIST=""
if [[ -n "$AUTO_UPGRADE_CLI" ]]; then
    AUTO_UPGRADE="$AUTO_UPGRADE_CLI"
    AUTO_UPGRADE_PERSIST="$AUTO_UPGRADE_CLI"
elif [[ -n "$AUTO_UPGRADE_CONFIG" ]]; then
    AUTO_UPGRADE="$AUTO_UPGRADE_CONFIG"
elif has_hivesmith_cron; then
    AUTO_UPGRADE=1
    AUTO_UPGRADE_PERSIST=1
fi

write_config_auto_upgrade() {
    # Upsert or remove the top-level auto_upgrade key in $CONFIG.
    # Arg: "true" | "false" | "" (remove).
    local value="$1"
    if [[ -n "$value" ]]; then upsert_config_key auto_upgrade "auto_upgrade = $value"
    else upsert_config_key auto_upgrade ""; fi
}

if [[ -n "$AUTO_UPGRADE_PERSIST" && "$MODE" != "uninstall" ]]; then
    if [[ "$AUTO_UPGRADE_PERSIST" == "1" ]]; then
        write_config_auto_upgrade "true"
    else
        write_config_auto_upgrade "false"
    fi
fi

in_list() {
    local needle="$1"; shift
    local hay=" $* "
    [[ "$hay" == *" $needle "* ]]
}

# ---- Enumerate skills ----------------------------------------------------

SKILLS=()
for dir in "$HIVESMITH_DIR"/skills/*/; do
    [[ -d "$dir" ]] || continue
    SKILLS+=("$(basename "$dir")")
done

# ---- Agent registry + scope resolution -----------------------------------
# Read agents.json once into a raw registry (unexpanded ~ paths). Target dirs
# are then resolved per scope: global -> $HOME/.<agent>, local -> $PWD/.<agent>.
# A harness whose project layout is not just the home layout re-rooted at $PWD
# (pi: ~/.pi/agent/skills globally, .pi/skills in a project) declares the
# optional `local_skills_dir`, which wins for the local scope only.

AGENTS_JSON="$HIVESMITH_DIR/agents.json"
# Fields are joined with US (\x1f), NOT tab: tab is IFS-whitespace, so an empty
# agents_dir (every harness but claude) or local_skills_dir (every harness but
# pi) would collapse two tabs into one and shift the following field left,
# leaving the last one empty. US is non-whitespace, so `read` preserves empty
# fields.
US=$'\x1f'
# entries: name<US>skills_raw<US>agents_raw<US>detect_raw<US>local_skills_raw
AGENT_REGISTRY=()
while IFS= read -r rec; do
    [[ -n "$rec" ]] && AGENT_REGISTRY+=("$rec")
done < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for a in json.load(f)['agents']:
        print('\x1f'.join([a['name'], a['skills_dir'], a.get('agents_dir', ''),
                           a['detect_dir'], a.get('local_skills_dir', '')]))
" "$AGENTS_JSON")

# An empty registry means the load itself failed (unreadable/malformed
# agents.json) — surface that instead of the misleading "no installations" later.
if [[ ${#AGENT_REGISTRY[@]} -eq 0 ]]; then
    err "Could not load agent registry from $AGENTS_JSON (unreadable or malformed?)"
    exit 1
fi

ALL_AGENT_NAMES=""
for rec in "${AGENT_REGISTRY[@]}"; do
    ALL_AGENT_NAMES="$ALL_AGENT_NAMES ${rec%%"$US"*}"
done
ALL_AGENT_NAMES="${ALL_AGENT_NAMES# }"

# Expand a raw ~ path for a scope (global -> $HOME, local -> $PWD/cwd).
scope_path() {  # $1=raw path, $2=scope
    local raw="$1" scope="$2"
    [[ -z "$raw" ]] && { printf ''; return; }
    if [[ "$scope" == "local" ]]; then printf '%s' "$PWD/${raw#\~/}"
    else printf '%s' "${raw/#\~/$HOME}"; fi
}

# SELECT_AGENTS: space-separated allow-list; empty means "all detected" (global).
SELECT_AGENTS=""
validate_agents() {  # $1 = comma/space list; echoes normalized space list
    local raw="${1//,/ }" out="" a
    # shellcheck disable=SC2086  # intentional word-split of space-separated lists
    for a in $raw; do
        # shellcheck disable=SC2086  # intentional word-split of space-separated lists
        in_list "$a" $ALL_AGENT_NAMES || { err "Unknown agent '$a' (known: ${ALL_AGENT_NAMES})"; exit 1; }
        out="$out $a"
    done
    printf '%s' "${out# }"
}

detected_local_agents() {
    local rec name detect out=""
    for rec in "${AGENT_REGISTRY[@]}"; do
        IFS="$US" read -r name _s _a detect _l <<< "$rec"
        [[ -d "$(scope_path "$detect" local)" ]] && out="$out $name"
    done
    printf '%s' "${out# }"
}

prompt_local_selection() {  # $1 = space list of detected agents
    local detected="$1" reply default="${1:-claude}"
    printf 'Local install — known harnesses: %s\n' "$ALL_AGENT_NAMES" >&2
    printf 'Detected in this project: %s\n' "${detected:-<none>}" >&2
    printf 'Install into which? [%s] (comma/space list, Enter to accept): ' "$default" >&2
    IFS= read -r reply || reply=""
    reply="${reply//,/ }"
    [[ -z "${reply// }" ]] && reply="$default"
    validate_agents "$reply"
}

write_config_agents() {  # $1 = space list; upsert `agents = [...]` in $CONFIG
    local list="$1" quoted="" a
    for a in $list; do quoted="$quoted, \"$a\""; done
    quoted="[${quoted#, }]"
    upsert_config_key agents "agents = $quoted"
}

# For local install/uninstall, decide which harnesses to target and remember it.
resolve_local_selection() {
    if [[ "$AGENTS_CLI_SET" == "1" ]]; then
        SELECT_AGENTS="$(validate_agents "$AGENTS_CLI")"
    elif [[ "$AGENTS_CONFIG_SET" == "1" ]]; then
        SELECT_AGENTS="$(validate_agents "$AGENTS_CONFIG")"
    else
        local detected; detected="$(detected_local_agents)"
        if [[ -t 0 && "$MODE" == "install" ]]; then
            SELECT_AGENTS="$(prompt_local_selection "$detected")"
        else
            SELECT_AGENTS="${detected:-claude}"
        fi
    fi
    [[ -z "$SELECT_AGENTS" ]] && SELECT_AGENTS="claude"
    if [[ "$MODE" == "install" ]]; then write_config_agents "$SELECT_AGENTS"; fi
    return 0
}

# Build TARGETS / AGENT_TARGETS for a scope.
#   global: detection-based (dir must exist), SELECT_AGENTS is an optional filter.
#   local:  SELECT_AGENTS is authoritative (dirs are created as needed).
build_targets() {  # $1 = scope
    local scope="$1" rec name skills_raw agents_raw detect_raw local_skills_raw
    local skills_dir agents_dir detect_dir
    TARGETS=(); AGENT_TARGETS=()
    for rec in "${AGENT_REGISTRY[@]}"; do
        IFS="$US" read -r name skills_raw agents_raw detect_raw local_skills_raw <<< "$rec"
        if [[ "$scope" == "local" ]]; then
            # shellcheck disable=SC2086  # intentional word-split of space-separated lists
            in_list "$name" $SELECT_AGENTS || continue
        else
            detect_dir="$(scope_path "$detect_raw" global)"
            [[ -d "$detect_dir" ]] || continue
            # shellcheck disable=SC2086  # intentional word-split of space-separated lists
            [[ -n "$SELECT_AGENTS" ]] && { in_list "$name" $SELECT_AGENTS || continue; }
        fi
        # A local-only override exists because some harnesses do not put their
        # project config where re-rooting the home path would predict.
        if [[ "$scope" == "local" && -n "$local_skills_raw" ]]; then
            skills_dir="$(scope_path "$local_skills_raw" "$scope")"
        else
            skills_dir="$(scope_path "$skills_raw" "$scope")"
        fi
        agents_dir="$(scope_path "$agents_raw" "$scope")"
        TARGETS+=("$name"$'\t'"$skills_dir")
        [[ -n "$agents_dir" ]] && AGENT_TARGETS+=("$name"$'\t'"$agents_dir")
    done
    return 0   # guard: last loop iteration's `&&` must not leak a nonzero exit
}

# Subagent definitions are shipped verbatim (no prefix rendering — the `name:`
# frontmatter is the dispatch key and filenames are already hs-prefixed).
# Enumerated via a function so `update` mode can re-run it after `git pull`,
# the same way SKILLS is re-enumerated.
enumerate_subagents() {
    SUBAGENTS=()
    for f in "$HIVESMITH_DIR"/agents/*.md; do
        [[ -f "$f" ]] || continue
        SUBAGENTS+=("$(basename "$f")")
    done
}
enumerate_subagents

# Resolve selection + build targets for the active scope (status/doctor build
# their own targets per-scope below, so skip here).
if [[ "$MODE" != "status" && "$MODE" != "doctor" ]]; then
    if [[ "$SCOPE" == "local" ]]; then
        resolve_local_selection
    elif [[ "$AGENTS_CLI_SET" == "1" ]]; then
        SELECT_AGENTS="$(validate_agents "$AGENTS_CLI")"
    fi
    build_targets "$SCOPE"
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        if [[ "$SCOPE" == "local" ]]; then
            err "No local target harnesses resolved. Pass --agents claude (or a comma list)."
        else
            err "No supported AI agent installations detected."
            say "Expected one of these as a ~/.<name> directory: $ALL_AGENT_NAMES"
        fi
        exit 1
    fi
fi

# ---- Modes: status / doctor ----------------------------------------------
# Read-only. Both inspect the same on-disk state; status reports counts,
# doctor reports problems and exits non-zero if any are found. Every check is
# contained so `set -euo pipefail` cannot abort mid-scan.

# Read a single quoted `prefix = "..."` from a config file (empty if absent).
cfg_prefix() {  # $1 = config file
    local v=""
    [[ -f "$1" ]] || { printf ''; return 0; }
    v="$(grep -E '^[[:space:]]*prefix[[:space:]]*=' "$1" 2>/dev/null | head -1)" || true
    [[ "$v" =~ \"([^\"]*)\" ]] && printf '%s' "${BASH_REMATCH[1]}" || printf ''
    return 0
}
# Read a `KEY = [ ... ]` array from a config file as a space list (empty if absent).
cfg_list() {  # $1 = key, $2 = config file
    local v=""
    [[ -f "$2" ]] || { printf ''; return 0; }
    v="$(grep -E "^[[:space:]]*$1[[:space:]]*=[[:space:]]*\[" "$2" 2>/dev/null | head -1)" || true
    if [[ "$v" =~ \[(.*)\] ]]; then echo "${BASH_REMATCH[1]}" | tr -d '",'; else printf ''; fi
    return 0
}
# Emit "state<TAB>name" (state: ok|broken) for each hivesmith-owned symlink in a dir.
scan_dir_links() {  # $1 = dir
    local dir="$1" existing tgt
    [[ -d "$dir" ]] || return 0
    for existing in "$dir"/*; do
        [[ -L "$existing" ]] || continue
        tgt="$(readlink "$existing")"
        case "$tgt" in "$HIVESMITH_DIR/"*) ;; *) continue ;; esac
        if [[ -e "$existing" ]]; then printf 'ok\t%s\n' "$(basename "$existing")"
        else printf 'broken\t%s\n' "$(basename "$existing")"; fi
    done
    return 0
}

DOCTOR_PROBLEMS=0

inspect_scope() {  # $1 = scope
    local scope="$1" cfg prefix saved_select detected line st nm
    if [[ "$scope" == "local" ]]; then cfg="${HIVESMITH_LOCAL_CONFIG:-$PWD/.hivesmith.toml}"
    else cfg="${HIVESMITH_DIR_CONFIG:-$HOME/.hivesmith.toml}"; fi

    # When --agents was passed, it narrows what status/doctor inspect.
    local cli_filter=""
    [[ "$AGENTS_CLI_SET" == "1" ]] && cli_filter="$(validate_agents "$AGENTS_CLI")"

    saved_select="$SELECT_AGENTS"
    if [[ "$scope" == "local" ]]; then
        SELECT_AGENTS="$(printf '%s %s' "$(detected_local_agents)" "$(cfg_list agents "$cfg")" \
            | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ')"
        # Intersect with the --agents filter, if any.
        if [[ -n "$cli_filter" ]]; then
            local kept="" a
            # shellcheck disable=SC2086  # intentional word-split of space-separated lists
            for a in $SELECT_AGENTS; do in_list "$a" $cli_filter && kept="$kept $a"; done
            SELECT_AGENTS="${kept# }"
        fi
        if [[ -z "${SELECT_AGENTS// }" ]]; then
            SELECT_AGENTS="$saved_select"
            heading "local ($PWD)"
            say "  no local install detected$([[ -n "$cli_filter" ]] && printf ' for --agents %s' "$cli_filter")"
            return 0
        fi
    else
        # Global: empty = all detected; --agents narrows via build_targets' filter.
        SELECT_AGENTS="$cli_filter"
    fi
    build_targets "$scope"
    SELECT_AGENTS="$saved_select"

    prefix="$(cfg_prefix "$cfg")"
    heading "$scope$([[ "$scope" == "local" ]] && printf ' (%s)' "$PWD")"
    [[ -n "$prefix" ]] && say "  prefix: \"$prefix\"   (config: $cfg)"

    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        say "  no target harnesses"
    fi
    local entry name dir n_ok n_broken
    for entry in ${TARGETS[@]+"${TARGETS[@]}"}; do
        IFS=$'\t' read -r name dir <<< "$entry"
        n_ok=0; n_broken=0
        while IFS=$'\t' read -r st nm; do
            [[ -z "$st" ]] && continue
            if [[ "$st" == "broken" ]]; then
                n_broken=$((n_broken + 1))
                DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
                say "  $(tag "$name") $(printf '%sbroken%s' "$C_RED" "$C_RESET") $nm — $dir/$nm → dangling (fix: install.sh --update$([[ "$scope" == "local" ]] && printf ' --local'))"
            else
                n_ok=$((n_ok + 1))
            fi
        done < <(scan_dir_links "$dir")
        printf '  %s %s skills linked' "$(tag "$name")" "$n_ok"
        (( n_broken > 0 )) && printf ', %d broken' "$n_broken"
        printf '   %s\n' "$dir"
    done
    # Subagents
    for entry in ${AGENT_TARGETS[@]+"${AGENT_TARGETS[@]}"}; do
        IFS=$'\t' read -r name dir <<< "$entry"
        n_ok=0; n_broken=0
        while IFS=$'\t' read -r st nm; do
            [[ -z "$st" ]] && continue
            if [[ "$st" == "broken" ]]; then
                n_broken=$((n_broken + 1)); DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
                say "  $(tag "$name") $(printf '%sbroken%s' "$C_RED" "$C_RESET") $nm (subagent) — $dir/$nm → dangling"
            else n_ok=$((n_ok + 1)); fi
        done < <(scan_dir_links "$dir")
        (( n_ok > 0 || n_broken > 0 )) && {
            printf '  %s %s subagents linked' "$(tag "$name")" "$n_ok"
            (( n_broken > 0 )) && printf ', %d broken' "$n_broken"
            printf '   %s\n' "$dir"
        }
    done

    # Global-only extras: brain-bin health + auto-upgrade/cron state.
    if [[ "$scope" == "global" ]]; then
        local bin="$HOME/.hivesmith/bin" bok=0 bbroken=0
        if [[ -d "$bin" ]]; then
            while IFS=$'\t' read -r st nm; do
                [[ -z "$st" ]] && continue
                if [[ "$st" == "broken" ]]; then
                    bbroken=$((bbroken + 1)); DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
                    say "  brain-bin $(printf '%sbroken%s' "$C_RED" "$C_RESET") $nm — $bin/$nm → dangling"
                else bok=$((bok + 1)); fi
            done < <(scan_dir_links "$bin")
            say "  brain-bin: $bok linked$( (( bbroken > 0 )) && printf ', %d broken' "$bbroken")   $bin"
        else
            say "  brain-bin: not present ($bin)"
        fi
        if has_hivesmith_cron; then say "  auto-upgrade: cron installed"
        else say "  auto-upgrade: off"; fi
        # Telemetry is reported, never installed here. These hooks fire in every
        # Claude Code session on the machine, including repos that have nothing
        # to do with hivesmith, so wiring them as a side effect of installing a
        # skill pack would turn an informed opt-in into a surprise.
        if [[ -f "$HOME/.claude/settings.json" ]] \
           && grep -q 'scripts/telemetry/' "$HOME/.claude/settings.json" 2>/dev/null; then
            say "  telemetry: wired (user-level, all sessions on this machine)"
        elif grep -qs 'scripts/telemetry/' .claude/settings.local.json 2>/dev/null; then
            # /hivesmith-init writes the per-repo opt-in here. Reporting "not
            # wired" for a project that deliberately opted in reads as a broken
            # install and invites a second, machine-wide install.
            say "  telemetry: wired for this repo only (.claude/settings.local.json)"
        else
            say "  telemetry: not wired — subagent durations are not being recorded."
            say "             Machine-wide:  scripts/telemetry/install-hooks.sh"
            say "             This repo only: run /hivesmith-init and check \"Agent telemetry\""
        fi
    fi
}

if [[ "$MODE" == "status" || "$MODE" == "doctor" ]]; then
    # Default to both scopes; --global/--local narrows.
    scopes=(global local)
    if [[ "$SCOPE_SET" == "1" ]]; then scopes=("$SCOPE"); fi
    heading "hivesmith $MODE — clone: $HIVESMITH_DIR"
    if ! git -C "$HIVESMITH_DIR" rev-parse --git-dir >/dev/null 2>&1; then
        warn "clone is not a git repo — --update will not work"
        [[ "$MODE" == "doctor" ]] && DOCTOR_PROBLEMS=$((DOCTOR_PROBLEMS + 1))
    fi
    for sc in "${scopes[@]}"; do
        say ""
        inspect_scope "$sc"
    done
    say ""
    if [[ "$MODE" == "doctor" ]]; then
        if (( DOCTOR_PROBLEMS > 0 )); then
            err "$DOCTOR_PROBLEMS problem(s) found."
            exit 1
        fi
        ok "No problems found."
    fi
    exit 0
fi

# ---- Mode: update --------------------------------------------------------

if [[ "$MODE" == "update" ]]; then
    say "Updating hivesmith at $HIVESMITH_DIR..."
    run git -C "$HIVESMITH_DIR" pull --ff-only
    # Re-enumerate skills in case git pull added/removed some
    SKILLS=()
    for dir in "$HIVESMITH_DIR"/skills/*/; do
        [[ -d "$dir" ]] || continue
        SKILLS+=("$(basename "$dir")")
    done
    # Same for subagents — a pull may have added, renamed, or removed one.
    enumerate_subagents
fi

# ---- Mode: uninstall -----------------------------------------------------

if [[ "$MODE" == "uninstall" ]]; then
    GONE=()
    # Ownership sweep: remove any symlink in a target skills dir that points into
    # this hivesmith clone (source skills/* OR the rendered prefix tree). This is
    # prefix-independent, so `--uninstall` clears prefixed links without needing
    # --prefix re-passed.
    for entry in "${TARGETS[@]}"; do
        IFS=$'\t' read -r name skills_dir <<< "$entry"
        [[ -d "$skills_dir" ]] || continue
        say "Removing hivesmith symlinks from $skills_dir..."
        for existing in "$skills_dir"/*; do
            [[ -L "$existing" ]] || continue
            case "$(readlink "$existing")" in
                "$HIVESMITH_DIR/"*)
                    run rm "$existing"
                    GONE+=("$name"$'\t'"$(basename "$existing")"$'\t'"uninstall")
                    ;;
            esac
        done
    done
    for entry in ${AGENT_TARGETS[@]+"${AGENT_TARGETS[@]}"}; do
        IFS=$'\t' read -r name agents_dir <<< "$entry"
        [[ -d "$agents_dir" ]] || continue
        # Sweep by target, not by current SUBAGENTS: an agent file renamed or
        # removed upstream still has a link here, and uninstall must clear it.
        for existing in "$agents_dir"/*; do
            [[ -L "$existing" ]] || continue
            case "$(readlink "$existing")" in
                "$HIVESMITH_DIR/agents/"*)
                    run rm "$existing"
                    GONE+=("$name"$'\t'"$(basename "$existing")"$'\t'"uninstall")
                    ;;
            esac
        done
    done
    # Global-only side effects: the rendered tree, auto-upgrade cron, and the
    # auto_upgrade config key all belong to the global install. A local uninstall
    # must not touch them (it would break a coexisting global install).
    if [[ "$SCOPE" == "global" ]]; then
        if [[ -d "$RENDER_ROOT" ]]; then
            run rm -rf "$RENDER_ROOT"
        fi
        if has_hivesmith_cron; then
            if [[ "$DRY_RUN" == "1" ]]; then
                say "DRY: remove hivesmith crontab entry"
            else
                (crontab -l | grep -v "$CRON_GREP") | crontab -
            fi
        fi
        if [[ -f "$CONFIG" ]] && grep -q '^[[:space:]]*auto_upgrade[[:space:]]*=' "$CONFIG"; then
            write_config_auto_upgrade ""
        fi
        # Brain helper symlinks live under ~/.hivesmith/bin (global, absolute-path
        # referenced by skills). Remove the ones we own; drop the dir if empty.
        BRAIN_BIN_DIR="$HOME/.hivesmith/bin"
        if [[ -d "$BRAIN_BIN_DIR" ]]; then
            for link_name in brain-read brain-append brain-index brain-redact brain-list brain-search brain-lib.sh brain-yaml.py brain-promote brain-garden hs-metric; do
                link="$BRAIN_BIN_DIR/$link_name"
                if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$HIVESMITH_DIR/"* ]]; then
                    run rm -f "$link"
                fi
            done
            if [[ "$DRY_RUN" == "1" ]]; then
                say "DRY: rmdir $BRAIN_BIN_DIR (if empty)"
            else
                rmdir "$BRAIN_BIN_DIR" 2>/dev/null || true
            fi
        fi
    fi
    if (( ${#GONE[@]} > 0 )); then
        say ""
        heading "Removed:"
        printf '%s\n' "${GONE[@]}" | sort | while IFS=$'\t' read -r a n _r; do
            printf '  %s  %s\n' "$(tag "$a")" "$n"
        done
    fi
    ok "Uninstalled."
    exit 0
fi

# ---- Render prefixed skill tree -----------------------------------------
# Builds $RENDER_ROOT/$PREFIX/skills/${PREFIX}${skill}/ with SKILL.md
# cross-references rewritten. Only runs when PREFIX is non-empty.

render_tree() {
    local prefix="$1"
    local root="$RENDER_ROOT/$prefix"

    # Wipe and recreate so it's always in sync with source.
    run rm -rf "$root"
    run mkdir -p "$root/skills"

    # Build sed program (ERE): rewrite `name:` frontmatter and /skill-name
    # slash-commands, being careful NOT to rewrite path segments like
    # `scripts/release.sh`. The `/` must be preceded by start-of-line or a
    # non-path character (whitespace, backtick, paren, bracket), and the
    # skill name must be followed by end-of-line or a non-identifier char.
    local sed_args=()
    for s in "${SKILLS[@]}"; do
        sed_args+=(-e "s#^name: ${s}\$#name: ${prefix}${s}#")
        sed_args+=(-e "s#(^|[^[:alnum:]_./-])/${s}([^[:alnum:]_-]|\$)#\\1/${prefix}${s}\\2#g")
    done

    for s in "${SKILLS[@]}"; do
        local src_dir="$HIVESMITH_DIR/skills/$s"
        local dst_dir="$root/skills/${prefix}${s}"
        run mkdir -p "$dst_dir"
        # Copy everything, then rewrite SKILL.md in place.
        if [[ "$DRY_RUN" == "1" ]]; then
            say "DRY: cp -R $src_dir/. $dst_dir/"
            say "DRY: sed rewrite $dst_dir/SKILL.md"
        else
            cp -R "$src_dir/." "$dst_dir/"
            if [[ -f "$dst_dir/SKILL.md" ]]; then
                tmp_sk="$(mktemp)"
                sed -E "${sed_args[@]}" "$dst_dir/SKILL.md" > "$tmp_sk"
                mv "$tmp_sk" "$dst_dir/SKILL.md"
            fi
        fi
    done
}

if [[ -n "$PREFIX" ]]; then
    say "Rendering prefixed skills (prefix=\"$PREFIX\") into $RENDER_ROOT/$PREFIX..."
    render_tree "$PREFIX"
elif [[ "$SCOPE" == "global" ]]; then
    # Clean up any stale rendered tree when running a global install without a
    # prefix. Gated to global: $RENDER_ROOT is shared repo state, and a local
    # no-prefix install links directly at source skills (never the rendered
    # tree), so it must not wipe a coexisting global --prefix install's tree.
    if [[ -d "$RENDER_ROOT" ]]; then
        run rm -rf "$RENDER_ROOT"
    fi
fi

# ---- Mode: install / update → reconcile symlinks -------------------------

created=0; skipped=0; removed=0
ADDED=()    # entries: "agent\tlink_name"
GONE=()     # entries: "agent\tlink_name\treason"  (reason: stale|opt-out|renamed)

for entry in "${TARGETS[@]}"; do
    IFS=$'\t' read -r name skills_dir <<< "$entry"
    run mkdir -p "$skills_dir"

    only="$(agent_only_for "$name")"

    # Sweep stale hivesmith symlinks (e.g. prefix changed, skill renamed).
    # Any symlink in $skills_dir pointing into $HIVESMITH_DIR that isn't the
    # current expected link for some enabled skill is removed.
    if [[ -d "$skills_dir" ]]; then
        for existing in "$skills_dir"/*; do
            [[ -L "$existing" ]] || continue
            target="$(readlink "$existing")"
            case "$target" in
                "$HIVESMITH_DIR/"*) ;;
                *) continue ;;
            esac
            base="$(basename "$existing")"
            keep=0
            for s in "${SKILLS[@]}"; do
                if [[ "$base" == "${PREFIX}${s}" ]]; then
                    keep=1; break
                fi
            done
            if [[ "$keep" == "0" ]]; then
                run rm "$existing"
                removed=$((removed + 1))
                GONE+=("$name"$'\t'"$base"$'\t'"stale")
            fi
        done
    fi

    for skill in "${SKILLS[@]}"; do
        if [[ -n "$PREFIX" ]]; then
            src="$RENDER_ROOT/$PREFIX/skills/${PREFIX}${skill}"
        else
            src="$HIVESMITH_DIR/skills/$skill"
        fi
        link_name="${PREFIX}${skill}"
        link="$skills_dir/$link_name"

        # Opt-out: globally disabled or not in this agent's "only" list.
        # Config values are un-prefixed (they refer to skill identity, not link name).
        disabled=0
        # shellcheck disable=SC2086  # intentional word-split of space-separated lists
        if in_list "$skill" $DISABLE_GLOBAL; then disabled=1; fi
        # shellcheck disable=SC2086  # intentional word-split of space-separated lists
        if [[ -n "$only" ]] && ! in_list "$skill" $only; then disabled=1; fi

        if [[ "$disabled" == "1" ]]; then
            if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$src" ]]; then
                run rm "$link"
                removed=$((removed + 1))
                GONE+=("$name"$'\t'"$link_name"$'\t'"opt-out")
            fi
            continue
        fi

        if [[ -L "$link" ]]; then
            cur_target="$(readlink "$link")"
            if [[ "$cur_target" == "$src" ]]; then
                skipped=$((skipped + 1)); continue
            fi
            # Stale hivesmith link (e.g. prefix changed, or render-root moved).
            if [[ "$cur_target" == "$HIVESMITH_DIR/skills/$skill" \
               || "$cur_target" == "$RENDER_ROOT/"*"/skills/${PREFIX}${skill}" ]]; then
                run rm "$link"
                GONE+=("$name"$'\t'"$link_name"$'\t'"renamed")
            fi
        fi
        # A non-hivesmith path is in the way (real file/dir, or a foreign
        # symlink — including a dangling one, hence the -L).
        if [[ -e "$link" || -L "$link" ]]; then
            force_or_skip "$link" || continue
        fi
        run ln -s "$src" "$link"
        created=$((created + 1))
        ADDED+=("$name"$'\t'"$link_name")
    done
    printf '  %s %s — linked\n' "$(tag "$name")" "$skills_dir"
done

# ---- Subagents (harnesses that declare agents_dir) -----------------------

for entry in ${AGENT_TARGETS[@]+"${AGENT_TARGETS[@]}"}; do
    IFS=$'\t' read -r name agents_dir <<< "$entry"
    [[ ${#SUBAGENTS[@]} -eq 0 ]] && continue
    run mkdir -p "$agents_dir"
    # Sweep stale hivesmith agent symlinks (renamed or removed upstream).
    # Mirrors the skills sweep: only links pointing into $HIVESMITH_DIR/agents
    # are candidates, and only those with no matching current SUBAGENTS entry.
    if [[ -d "$agents_dir" ]]; then
        for existing in "$agents_dir"/*; do
            [[ -L "$existing" ]] || continue
            case "$(readlink "$existing")" in
                "$HIVESMITH_DIR/agents/"*) ;;
                *) continue ;;
            esac
            base="$(basename "$existing")"
            keep=0
            for a in ${SUBAGENTS[@]+"${SUBAGENTS[@]}"}; do
                if [[ "$base" == "$a" ]]; then keep=1; break; fi
            done
            if [[ "$keep" == "0" ]]; then
                run rm "$existing"
                removed=$((removed + 1))
                GONE+=("$name"$'\t'"$base"$'\t'"stale")
            fi
        done
    fi

    for a in "${SUBAGENTS[@]}"; do
        src="$HIVESMITH_DIR/agents/$a"
        link="$agents_dir/$a"

        # Opt-out: `disable = [...]` matches an agent by its bare name
        # (e.g. "hs-reviewer"). The per-harness `only` list is NOT consulted —
        # it enumerates skill identities, so a user restricting their skills
        # would otherwise silently lose their subagents too.
        # shellcheck disable=SC2086  # intentional word-split of a space-separated list
        if in_list "${a%.md}" $DISABLE_GLOBAL; then
            if [[ -L "$link" ]] && [[ "$(readlink "$link")" == "$src" ]]; then
                run rm "$link"
                removed=$((removed + 1))
                GONE+=("$name"$'\t'"$a"$'\t'"opt-out")
            fi
            continue
        fi

        if [[ -L "$link" ]]; then
            cur_target="$(readlink "$link")"
            if [[ "$cur_target" == "$src" ]]; then
                skipped=$((skipped + 1)); continue
            fi
            # Only reclaim a link we own. Anything else (a user's own symlink,
            # a dotfiles-managed link) is left alone — same rule as skills.
            if [[ "$cur_target" == "$HIVESMITH_DIR/agents/"* ]]; then
                run rm "$link"
                GONE+=("$name"$'\t'"$a"$'\t'"renamed")
            else
                force_or_skip "$link" || continue
            fi
        elif [[ -e "$link" ]]; then
            force_or_skip "$link" || continue
        fi
        run ln -s "$src" "$link"
        created=$((created + 1))
        ADDED+=("$name"$'\t'"$a")
    done
    printf '  %s %s — linked\n' "$(tag "$name")" "$agents_dir"
done

say ""
ok "Linked: $created new, $skipped already present, $removed removed (opt-outs/stale)."

# Detect "moved" entries: same agent+link_name appears in both ADDED and GONE
# (with reason=renamed). Collapse those into a single "Moved:" section.
MOVED_KEYS=""
if (( ${#GONE[@]} > 0 )) && (( ${#ADDED[@]} > 0 )); then
    for g in "${GONE[@]}"; do
        IFS=$'\t' read -r ga gn gr <<< "$g"
        [[ "$gr" == "renamed" ]] || continue
        for a in "${ADDED[@]}"; do
            IFS=$'\t' read -r aa an <<< "$a"
            if [[ "$ga" == "$aa" && "$gn" == "$an" ]]; then
                MOVED_KEYS="${MOVED_KEYS}|${ga}"$'\t'"${gn}|"
            fi
        done
    done
fi

is_moved() {
    local key="|$1"$'\t'"$2|"
    [[ "$MOVED_KEYS" == *"$key"* ]]
}

added_filtered=()
if (( ${#ADDED[@]} > 0 )); then
    for a in "${ADDED[@]}"; do
        IFS=$'\t' read -r aa an <<< "$a"
        if ! is_moved "$aa" "$an"; then
            added_filtered+=("$a")
        fi
    done
fi

gone_filtered=()
if (( ${#GONE[@]} > 0 )); then
    for g in "${GONE[@]}"; do
        IFS=$'\t' read -r ga gn gr <<< "$g"
        if ! is_moved "$ga" "$gn"; then
            gone_filtered+=("$g")
        fi
    done
fi

if (( ${#added_filtered[@]} > 0 )); then
    say ""
    heading "Added:"
    printf '%s\n' "${added_filtered[@]}" | sort | while IFS=$'\t' read -r a n; do
        printf '  %s  %s\n' "$(tag "$a")" "$n"
    done
fi

if (( ${#gone_filtered[@]} > 0 )); then
    say ""
    heading "Removed:"
    printf '%s\n' "${gone_filtered[@]}" | sort | while IFS=$'\t' read -r a n r; do
        printf '  %s  %s  (%s)\n' "$(tag "$a")" "$n" "$r"
    done
fi

if [[ -n "$MOVED_KEYS" ]]; then
    say ""
    heading "Moved (relinked due to prefix/render-root change):"
    # Print unique entries from MOVED_KEYS
    printf '%s' "$MOVED_KEYS" | tr '|' '\n' | grep -v '^$' | sort -u \
      | while IFS=$'\t' read -r a n; do
            printf '  %s  %s\n' "$(tag "$a")" "$n"
        done
fi

if (( ${#added_filtered[@]} == 0 )) && (( ${#gone_filtered[@]} == 0 )) && [[ -z "$MOVED_KEYS" ]]; then
    say "No skill changes."
fi

if [[ -n "$PREFIX" ]]; then
    say "Prefix: \"$PREFIX\" (stored in $CONFIG)"
fi

# ---- Brain helpers -------------------------------------------------------
# Symlink scripts/brain/{lib.sh,read.sh,append.sh,redact.sh,index.sh,yaml.py}
# into ~/.hivesmith/bin/ so skills can invoke them by stable absolute path
# regardless of $PREFIX or where the hivesmith repo is cloned.

if [[ "$MODE" == "install" || "$MODE" == "update" ]]; then
    BRAIN_BIN_DIR="$HOME/.hivesmith/bin"
    run mkdir -p "$BRAIN_BIN_DIR"
    declare -a brain_links=(
        "scripts/brain/read.sh:brain-read"
        "scripts/brain/append.sh:brain-append"
        "scripts/brain/index.sh:brain-index"
        "scripts/brain/redact.sh:brain-redact"
        "scripts/brain/list.sh:brain-list"
        "scripts/brain/search.sh:brain-search"
        "scripts/brain/lib.sh:brain-lib.sh"
        "scripts/brain/yaml.py:brain-yaml.py"
        "skills/brain-promote/promote.sh:brain-promote"
        "skills/brain-garden/garden.sh:brain-garden"
        # Not a hook: hs-metric only runs when a skill the operator started
        # calls it, so it carries the same consent posture as brain-append.
        # The name is prefix-independent because the bin dir is.
        "scripts/metrics/emit.sh:hs-metric"
    )
    for pair in "${brain_links[@]}"; do
        src_rel="${pair%%:*}"
        link_name="${pair##*:}"
        src="$HIVESMITH_DIR/$src_rel"
        [[ -f "$src" ]] || continue
        link="$BRAIN_BIN_DIR/$link_name"
        if [[ -L "$link" ]]; then
            existing="$(readlink "$link")"
            [[ "$existing" == "$src" ]] && continue
            run rm -f "$link"
        elif [[ -e "$link" ]]; then
            force_or_skip "$link" || continue  # real file: keep unless --force
        fi
        run ln -s "$src" "$link"
    done
fi

# ---- Auto-upgrade --------------------------------------------------------
# Global-only: the daily cron runs the global install. Local scope never
# manages cron (and rejects --auto-upgrade at parse time).

if [[ "$MODE" == "install" && "$SCOPE" == "global" ]]; then
    if [[ "$AUTO_UPGRADE" == "1" ]]; then
        if has_hivesmith_cron; then
            :  # already present — nothing to do
        else
            say "Installing daily auto-upgrade cron..."
            tmp="$(mktemp)"
            crontab -l 2>/dev/null > "$tmp" || true
            # Prefix is persisted in config so we don't need it on the cron line,
            # but being explicit guards against config drift.
            if [[ -n "$PREFIX" ]]; then
                echo "17 4 * * * $HIVESMITH_DIR/install.sh --update --prefix \"$PREFIX\" >/dev/null 2>&1" >> "$tmp"
            else
                echo "17 4 * * * $HIVESMITH_DIR/install.sh --update >/dev/null 2>&1" >> "$tmp"
            fi
            run crontab "$tmp"
            rm -f "$tmp"
        fi
    else
        # Opted out (or default). Remove any existing cron entry.
        if has_hivesmith_cron; then
            say "Removing existing auto-upgrade cron (opted out)."
            if [[ "$DRY_RUN" == "1" ]]; then
                say "DRY: remove hivesmith crontab entry"
            else
                (crontab -l | grep -v "$CRON_GREP") | crontab -
            fi
        elif [[ -z "$AUTO_UPGRADE_CLI" && -z "$AUTO_UPGRADE_CONFIG" ]]; then
            say "Auto-upgrade is opt-in. Pass --auto-upgrade to enable a daily cron."
        fi
    fi
fi

ok "Done."
