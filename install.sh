#!/usr/bin/env bash
set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
    echo "Error: python3 is required (used to parse agents.json)." >&2
    exit 1
fi

# install.sh — fan-out symlinks from hivesmith/skills/* into each detected
# agent's skills dir (Claude, Codex, Factory, Gemini, Copilot).
#
# Usage:
#   ./install.sh                   # install (idempotent)
#   ./install.sh --update          # git pull then reconcile symlinks
#   ./install.sh --uninstall       # remove all hivesmith symlinks everywhere
#   ./install.sh --prefix hs-      # install with a name prefix (see below)
#   ./install.sh --prefix ""       # clear any stored prefix
#   ./install.sh --no-auto-update  # skip installing daily auto-update
#   ./install.sh --dry-run         # print what would happen
#
# --prefix namespaces every skill on disk and in cross-skill references.
# With --prefix hs-, skills install as /hs-feature-plan, /hs-release, etc.
# The prefix is persisted to ~/.hivesmith.toml so update/uninstall don't
# need it re-passed. Pass --prefix "" to clear it.
#
# Per-skill opt-out lives in ~/.hivesmith.toml:
#
#   prefix = "hs-"
#   disable = ["review-pr"]
#   [agents.gemini]
#   only = ["feature-next", "feature-ingest"]

HIVESMITH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="${HIVESMITH_DIR_CONFIG:-$HOME/.hivesmith.toml}"
RENDER_ROOT="$HIVESMITH_DIR/.rendered"

MODE="install"
AUTO_UPDATE=1
DRY_RUN=0
PREFIX_CLI=""
PREFIX_CLI_SET=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --update) MODE="update"; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --no-auto-update) AUTO_UPDATE=0; shift ;;
        --dry-run) DRY_RUN=1; shift ;;
        --prefix) PREFIX_CLI="${2-}"; PREFIX_CLI_SET=1; shift 2 ;;
        --prefix=*) PREFIX_CLI="${1#--prefix=}"; PREFIX_CLI_SET=1; shift ;;
        -h|--help)
            sed -n '3,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown arg: $1" >&2; exit 1 ;;
    esac
done

say() { printf '%s\n' "$*"; }
run() {
    if [[ "$DRY_RUN" == "1" ]]; then say "DRY: $*"; else "$@"; fi
}

# ---- Parse config (very small TOML subset) -------------------------------
# Supports:
#   prefix = "hs-"
#   disable = ["a", "b"]
#   [agents.<name>]
#   only = ["x", "y"]
#
# Exposes:
#   DISABLE_GLOBAL   — space-separated list
#   PREFIX_CONFIG    — value of top-level prefix, or empty
#   agent_only_<name> — space-separated list, set only if "only" present

DISABLE_GLOBAL=""
PREFIX_CONFIG=""
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
        if [[ -n "$current_agent" && "$line" =~ ^only[[:space:]]*=[[:space:]]*\[(.*)\] ]]; then
            vals="$(echo "${BASH_REMATCH[1]}" | tr -d '",' )"
            AGENT_ONLY_TABLE="${AGENT_ONLY_TABLE}|${current_agent}:${vals}"
        fi
    done < "$CONFIG"
    AGENT_ONLY_TABLE="${AGENT_ONLY_TABLE}|"
fi

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

# Writeback: upsert prefix line in config when CLI set it (and not uninstall)
if [[ "$PREFIX_CLI_SET" == "1" && "$MODE" != "uninstall" ]]; then
    if [[ "$DRY_RUN" == "1" ]]; then
        say "DRY: would write prefix = \"$PREFIX\" to $CONFIG"
    else
        touch "$CONFIG"
        tmp_cfg="$(mktemp)"
        found=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ "$line" =~ ^[[:space:]]*prefix[[:space:]]*= ]]; then
                if [[ -n "$PREFIX" ]]; then
                    echo "prefix = \"$PREFIX\"" >> "$tmp_cfg"
                fi
                found=1
            else
                echo "$line" >> "$tmp_cfg"
            fi
        done < "$CONFIG"
        if [[ "$found" == "0" && -n "$PREFIX" ]]; then
            # Insert before first [section] header, else append
            if grep -q '^\[' "$tmp_cfg" 2>/dev/null; then
                tmp_cfg2="$(mktemp)"
                awk -v line="prefix = \"$PREFIX\"" '
                    !done && /^\[/ { print line; print ""; done=1 }
                    { print }
                ' "$tmp_cfg" > "$tmp_cfg2"
                mv "$tmp_cfg2" "$tmp_cfg"
            else
                echo "prefix = \"$PREFIX\"" >> "$tmp_cfg"
            fi
        fi
        mv "$tmp_cfg" "$CONFIG"
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

# ---- Enumerate target agents (detect + filter) ---------------------------

AGENTS_JSON="$HIVESMITH_DIR/agents.json"
TARGETS=()
while IFS=$'\t' read -r name skills_dir detect_dir; do
    skills_dir="${skills_dir/#~/$HOME}"
    detect_dir="${detect_dir/#~/$HOME}"
    if [[ -d "$detect_dir" ]]; then
        TARGETS+=("$name"$'\t'"$skills_dir")
    fi
done < <(python3 -c "
import json, sys
with open(sys.argv[1]) as f:
    for a in json.load(f)['agents']:
        print(a['name'] + '\t' + a['skills_dir'] + '\t' + a['detect_dir'])
" "$AGENTS_JSON")

if [[ ${#TARGETS[@]} -eq 0 ]]; then
    say "No supported AI agent installations detected."
    say "Expected one of: ~/.claude, ~/.codex, ~/.factory, ~/.gemini, ~/.copilot"
    exit 1
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
fi

# ---- Mode: uninstall -----------------------------------------------------

if [[ "$MODE" == "uninstall" ]]; then
    for entry in "${TARGETS[@]}"; do
        IFS=$'\t' read -r name skills_dir <<< "$entry"
        say "Removing hivesmith symlinks from $skills_dir..."
        for skill in "${SKILLS[@]}"; do
            link_name="${PREFIX}${skill}"
            link="$skills_dir/$link_name"
            if [[ -L "$link" ]]; then
                target="$(readlink "$link")"
                if [[ "$target" == "$HIVESMITH_DIR/skills/$skill" \
                   || "$target" == "$RENDER_ROOT/"*"/skills/$link_name" ]]; then
                    run rm "$link"
                fi
            fi
            # Also clean up an un-prefixed link if it happens to exist (migration)
            if [[ -n "$PREFIX" && -L "$skills_dir/$skill" ]]; then
                t2="$(readlink "$skills_dir/$skill")"
                if [[ "$t2" == "$HIVESMITH_DIR/skills/$skill" ]]; then
                    run rm "$skills_dir/$skill"
                fi
            fi
        done
    done
    # Remove rendered tree
    if [[ -d "$RENDER_ROOT" ]]; then
        run rm -rf "$RENDER_ROOT"
    fi
    # Remove auto-update cron if any
    if crontab -l 2>/dev/null | grep -q "hivesmith .*install.sh.* --update\|hivesmith/install.sh --update"; then
        if [[ "$DRY_RUN" == "1" ]]; then
            say "DRY: remove hivesmith crontab entry"
        else
            (crontab -l | grep -v 'hivesmith/install.sh --update\|hivesmith .*install.sh.* --update') | crontab -
        fi
    fi
    say "Uninstalled."
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
else
    # Clean up any stale rendered tree when running without prefix.
    if [[ -d "$RENDER_ROOT" ]]; then
        run rm -rf "$RENDER_ROOT"
    fi
fi

# ---- Mode: install / update → reconcile symlinks -------------------------

created=0; skipped=0; removed=0

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
            fi
        fi
        if [[ -e "$link" ]]; then
            say "WARN: $link exists and is not a hivesmith symlink — skipping"
            continue
        fi
        run ln -s "$src" "$link"
        created=$((created + 1))
    done
    say "  [$name] $skills_dir — linked"
done

say ""
say "Linked: $created new, $skipped already present, $removed removed (opt-outs/stale)."
if [[ -n "$PREFIX" ]]; then
    say "Prefix: \"$PREFIX\" (stored in $CONFIG)"
fi

# ---- Auto-update ---------------------------------------------------------

if [[ "$AUTO_UPDATE" == "1" && "$MODE" == "install" ]]; then
    if ! crontab -l 2>/dev/null | grep -q "hivesmith/install.sh --update\|hivesmith .*install.sh.* --update"; then
        say "Installing daily auto-update cron..."
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
fi

say "Done."
