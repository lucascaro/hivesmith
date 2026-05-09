# shellcheck shell=bash
# Shared helpers for the hivesmith brain.
#
# This file is sourced (not executed). All functions are namespaced `brain_*`.
# It assumes bash 4+ and the tools listed in scripts/brain/README expectations.

set -u

BRAIN_HOME="${BRAIN_HOME:-$HOME/.hivesmith/brain}"
BRAIN_BIN="${BRAIN_BIN:-$HOME/.hivesmith/bin}"
BRAIN_BUDGET_TOKENS="${BRAIN_BUDGET_TOKENS:-8000}"

# Resolve the directory that holds this lib.sh, so siblings (yaml.py, redact.sh)
# can be located even when the helpers are invoked through ~/.hivesmith/bin/ symlinks.
brain_self_dir() {
    local src="${BASH_SOURCE[0]:-${0}}"
    while [ -L "$src" ]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" && pwd)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && pwd
}

BRAIN_LIB_DIR="$(brain_self_dir 2>/dev/null || pwd)"
export BRAIN_LIB_DIR

brain_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        shasum -a 256 | awk '{print $1}'
    fi
}

# Canonicalize a git remote URL: lowercase host, drop user info, strip ".git".
# Maps these all to "github.com/lucascaro/hivesmith":
#   https://github.com/lucascaro/hivesmith.git
#   https://lucascaro@github.com/lucascaro/hivesmith
#   git@github.com:lucascaro/hivesmith.git
#   ssh://git@GitHub.com/lucascaro/hivesmith
brain_canonicalize_remote() {
    local url="$1"
    url="${url%.git}"
    # Convert SCP-style git@host:path to ssh://host/path
    if [[ "$url" =~ ^[^/:]+@[^/:]+: ]]; then
        local _slash="/"
        url="ssh://${url/:/$_slash}"
    fi
    # Strip scheme
    url="${url#*://}"
    # Strip user@
    url="${url#*@}"
    # Lowercase host portion only (path stays case-sensitive on most hosts but
    # we lowercase the whole thing for stability — git URLs are case-insensitive
    # on the dominant providers).
    printf '%s' "$url" | tr '[:upper:]' '[:lower:]'
}

# Print a 12-hex-char repo hash for the git repo at $PWD (or the given path).
# Falls back to the toplevel path if no remote is configured.
brain_repo_hash() {
    local cwd="${1:-$PWD}"
    local url
    if url="$(git -C "$cwd" config --get remote.origin.url 2>/dev/null)" && [ -n "$url" ]; then
        :
    elif url="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)"; then
        :
    else
        url="$cwd"
    fi
    local canon
    canon="$(brain_canonicalize_remote "$url")"
    printf '%s' "$canon" | brain_sha256 | cut -c1-12
}

# Detect the primary ecosystem of a project at $PWD (or given path).
# Emits one of: bun, node, deno, python+poetry, python+uv, python, rust, go,
# ruby, php, java+maven, java+gradle, dotnet, swift, mixed, unknown.
brain_detect_ecosystem() {
    local cwd="${1:-$PWD}"
    local out=""
    if [ -f "$cwd/bun.lockb" ] || [ -f "$cwd/bun.lock" ]; then out="bun"
    elif [ -f "$cwd/deno.json" ] || [ -f "$cwd/deno.jsonc" ]; then out="deno"
    elif [ -f "$cwd/package.json" ]; then out="node"
    elif [ -f "$cwd/poetry.lock" ] || { [ -f "$cwd/pyproject.toml" ] && grep -q '\[tool\.poetry\]' "$cwd/pyproject.toml" 2>/dev/null; }; then out="python+poetry"
    elif [ -f "$cwd/uv.lock" ] || { [ -f "$cwd/pyproject.toml" ] && grep -q '\[tool\.uv\]' "$cwd/pyproject.toml" 2>/dev/null; }; then out="python+uv"
    elif [ -f "$cwd/pyproject.toml" ] || [ -f "$cwd/setup.py" ] || [ -f "$cwd/requirements.txt" ]; then out="python"
    elif [ -f "$cwd/Cargo.toml" ]; then out="rust"
    elif [ -f "$cwd/go.mod" ]; then out="go"
    elif [ -f "$cwd/Gemfile" ]; then out="ruby"
    elif [ -f "$cwd/composer.json" ]; then out="php"
    elif [ -f "$cwd/pom.xml" ]; then out="java+maven"
    elif [ -f "$cwd/build.gradle" ] || [ -f "$cwd/build.gradle.kts" ]; then out="java+gradle"
    elif compgen -G "$cwd"/*.csproj >/dev/null 2>&1 || [ -f "$cwd/global.json" ]; then out="dotnet"
    elif [ -f "$cwd/Package.swift" ]; then out="swift"
    else out="unknown"
    fi
    printf '%s' "$out"
}

# Validate a slug: lowercase letters, digits, hyphens; 1–80 chars; no leading/trailing hyphen.
brain_validate_slug() {
    local s="$1"
    if [[ "$s" =~ ^[a-z0-9]([a-z0-9-]{0,78}[a-z0-9])?$ ]]; then return 0; fi
    return 1
}

# Validate a scope. Echoes the scope on stdout, exits non-zero on invalid.
brain_validate_scope() {
    case "$1" in
        universal|ecosystem|user|project) printf '%s' "$1" ;;
        *) printf 'invalid scope: %s\n' "$1" >&2; return 1 ;;
    esac
}

# Lazy-init: ensure ~/.hivesmith/brain/ exists with the expected layout and
# is a git repo. Idempotent. Templates are copied from $HIVESMITH_DIR/templates/brain
# if available; otherwise minimal stubs are written.
brain_lazy_init() {
    [ -d "$BRAIN_HOME" ] && [ -d "$BRAIN_HOME/.git" ] && return 0
    mkdir -p "$BRAIN_HOME"/{universal,ecosystem,user,project,unverified,archive}
    if [ ! -d "$BRAIN_HOME/.git" ]; then
        git -C "$BRAIN_HOME" init -q -b main 2>/dev/null || git -C "$BRAIN_HOME" init -q
        git -C "$BRAIN_HOME" commit -q --allow-empty -m "brain: init" 2>/dev/null || true
    fi
    local tmpl="${HIVESMITH_DIR:-}"
    if [ -z "$tmpl" ] || [ ! -d "$tmpl/templates/brain" ]; then
        # Try to locate templates relative to lib.sh location.
        if [ -d "$BRAIN_LIB_DIR/../../templates/brain" ]; then
            tmpl="$(cd "$BRAIN_LIB_DIR/../.." && pwd)"
        fi
    fi
    if [ -n "$tmpl" ] && [ -d "$tmpl/templates/brain" ]; then
        for f in SCHEMA.md README.md INDEX.md .gitignore; do
            [ -f "$BRAIN_HOME/$f" ] && continue
            [ -f "$tmpl/templates/brain/$f" ] && cp "$tmpl/templates/brain/$f" "$BRAIN_HOME/$f"
        done
    else
        [ -f "$BRAIN_HOME/INDEX.md" ] || printf '<!-- HOT -->\n\n<!-- HOT END -->\n\n<!-- ALL -->\n\n<!-- ALL END -->\n' >"$BRAIN_HOME/INDEX.md"
    fi
    git -C "$BRAIN_HOME" add -A 2>/dev/null || true
    if ! git -C "$BRAIN_HOME" diff --cached --quiet 2>/dev/null; then
        git -C "$BRAIN_HOME" commit -q -m "brain: lazy-init layout" 2>/dev/null || true
    fi
}

# Wrap stdin in an untrusted-data delimiter for safe injection into agent prompts.
brain_untrusted_wrap() {
    printf '<project-memory untrusted="true">\n'
    cat
    printf '\n</project-memory>\n'
}

# Return the path to the brain yaml.py helper.
brain_yaml_py() { printf '%s' "$BRAIN_LIB_DIR/yaml.py"; }

# Read YAML front-matter from a file; emit "key=value" pairs on stdout.
brain_read_frontmatter() {
    python3 "$(brain_yaml_py)" read "$1"
}

# Estimate tokens from a byte/char count (~4 chars per token, conservative).
brain_estimate_tokens() {
    local chars="$1"
    echo $(( chars / 4 ))
}
