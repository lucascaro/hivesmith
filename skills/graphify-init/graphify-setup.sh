#!/usr/bin/env bash
# graphify-setup.sh — wire graphify into a project so its knowledge graph stays
# fresh inside git worktrees, without re-paying for semantic extraction in each.
#
# Three moving parts:
#   1. Shared extraction cache. Each checkout's <out>/cache becomes a symlink
#      into $(git rev-parse --git-common-dir)/graphify-cache — the one path every
#      worktree resolves identically, never tracked, `git clean`-proof, and gone
#      when the repo is. Cache keys are content hashes and writes are atomic, so
#      sharing is safe by construction rather than by locking.
#   2. Git hooks. `graphify hook install` writes post-commit/post-checkout into
#      the common hooks dir (so one install covers every worktree), then we lift
#      its unconditional worktree guard — see patch_worktree_guard.
#   3. A Claude Code PostToolUse hook running graphify-refresh.sh after edits.
#
# Idempotent. Reversible with --uninstall. Never destroys a populated cache.
#
# Usage:
#   graphify-setup.sh [--migrate] [--uninstall] [--quiet] [project-dir]
#
#   --migrate    move an existing real <out>/cache into the shared dir instead
#                of refusing. Required whenever a real cache dir is in the way.
#   --uninstall  reverse everything: restore a real cache dir, strip hook
#                blocks, remove the settings entry.
#
# Env: GRAPHIFY_OUT (default graphify-out).

set -euo pipefail

MODE="install"
MIGRATE=0
QUIET=0
PROJECT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --migrate)   MIGRATE=1; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --quiet)     QUIET=1; shift ;;
        -h|--help)   sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*)          echo "Unknown arg: $1" >&2; exit 2 ;;
        *)           PROJECT_DIR="$1"; shift ;;
    esac
done

say() { [ "$QUIET" = "1" ] || echo "$@"; }
die() { echo "graphify-setup: $*" >&2; exit 1; }

cd "${PROJECT_DIR:-.}" || die "no such directory: $PROJECT_DIR"

git rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $(pwd)"

OUT="${GRAPHIFY_OUT:-graphify-out}"
# pwd -P: the symlink we create must point at a physical path, so the target
# is stable no matter which symlinked route a given worktree was reached by.
COMMON="$(cd "$(git rev-parse --git-common-dir)" && pwd -P)"
SHARED="$COMMON/graphify-cache"
HOOKS_DIR="$COMMON/hooks"
CACHE_LINK="$OUT/cache"

# Where this script lives, so we can copy its sibling refresh script.
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# tail -n 1: graphify prints a skill-version-drift warning ahead of the version.
GRAPHIFY_VERSION="$(graphify --version 2>/dev/null | tail -n 1 | awk '{print $NF}' || true)"
[ -n "$GRAPHIFY_VERSION" ] || GRAPHIFY_VERSION="unknown"

# ---------------------------------------------------------------------------
# 1. Shared extraction cache
# ---------------------------------------------------------------------------

link_cache() {
    mkdir -p "$SHARED" "$OUT"

    if [ -L "$CACHE_LINK" ]; then
        # Already a symlink. We always create it with an absolute target, so a
        # plain readlink compare is enough.
        if [ "$(readlink "$CACHE_LINK")" = "$SHARED" ]; then
            say "  cache        already shared -> $SHARED"
            return 0
        fi
        rm "$CACHE_LINK"
    elif [ -d "$CACHE_LINK" ]; then
        # A real directory. Its semantic entries cost LLM calls to produce, so
        # never delete one silently.
        if [ "$MIGRATE" != "1" ]; then
            die "$CACHE_LINK is a real directory with existing cache entries.
  Re-run with --migrate to move them into $SHARED, or remove it yourself first.
  Refusing to delete it: semantic cache entries cost real money to rebuild."
        fi
        # -n: never overwrite a newer shared entry with an older local one.
        # Entries are content-hash keyed, so same name means same bytes anyway.
        (cd "$CACHE_LINK" && find . -type f -print0 2>/dev/null || true) \
            | while IFS= read -r -d '' rel; do
                mkdir -p "$SHARED/$(dirname "$rel")"
                cp -n "$CACHE_LINK/$rel" "$SHARED/$rel" 2>/dev/null || true
            done
        rm -rf "$CACHE_LINK"
        say "  cache        migrated existing entries into $SHARED"
    elif [ -e "$CACHE_LINK" ]; then
        die "$CACHE_LINK exists and is neither a directory nor a symlink."
    fi

    ln -s "$SHARED" "$CACHE_LINK"
    say "  cache        $CACHE_LINK -> $SHARED"
}

unlink_cache() {
    [ -L "$CACHE_LINK" ] || { say "  cache        not linked, nothing to do"; return 0; }
    rm "$CACHE_LINK"
    mkdir -p "$CACHE_LINK"
    if [ -d "$SHARED" ]; then
        (cd "$SHARED" && find . -type f -print0 2>/dev/null || true) \
            | while IFS= read -r -d '' rel; do
                mkdir -p "$CACHE_LINK/$(dirname "$rel")"
                cp -n "$SHARED/$rel" "$CACHE_LINK/$rel" 2>/dev/null || true
            done
    fi
    say "  cache        restored as a real directory (shared copy left intact)"
}

# ---------------------------------------------------------------------------
# 2. Git hooks, with the worktree guard lifted
# ---------------------------------------------------------------------------

# graphify splices this guard into both generated hooks (graphify/hooks.py,
# _WORKTREE_GUARD) and bails out of any linked worktree. That is the right
# default for upstream — the canonical graph belongs to the primary checkout —
# and exactly wrong for hivesmith, whose whole pipeline runs in .worktrees/*.
#
# We rewrite only the guard's terminal `exit 0` into a conditional one. Matching
# is on the exact upstream text; if a future graphify reshapes the block the
# patch does NOT apply and we fail loudly, because the alternative is a user
# who thinks their worktree graphs are fresh when they are not.
# Literal text to match/emit — the $-expressions belong to the generated hook,
# not to this script.
# shellcheck disable=SC2016
GUARD_IF='if [ -n "$_GFY_COMMONDIR" ] && [ "$_GFY_GITDIR" != "$_GFY_COMMONDIR" ]; then'
# shellcheck disable=SC2016
GUARD_REPLACEMENT='    [ "${HIVESMITH_GRAPHIFY_WORKTREE:-1}" = "1" ] || exit 0'

patch_worktree_guard() {
    hook="$1"
    [ -f "$hook" ] || return 0

    if grep -q 'HIVESMITH_GRAPHIFY_WORKTREE' "$hook"; then
        return 0   # already patched (e.g. hook install left it in place)
    fi

    tmp="$hook.hivesmith.tmp"
    countfile="$hook.hivesmith.count"
    awk -v guard="$GUARD_IF" -v repl="$GUARD_REPLACEMENT" -v cf="$countfile" '
        seen && $0 == "    exit 0" { print repl; n++; seen=0; next }
        { seen = ($0 == guard); print }
        END { print n+0 > cf }
    ' "$hook" >"$tmp"
    count="$(cat "$countfile")"
    rm -f "$countfile"

    if [ "$count" != "1" ]; then
        rm -f "$tmp"
        die "could not lift the worktree guard in $hook (matched $count times, expected 1).
  Installed graphify version: $GRAPHIFY_VERSION
  Its hook text has probably changed shape. Refusing to continue rather than
  leave worktree graphs silently stale. Check graphify/hooks.py _WORKTREE_GUARD."
    fi

    # Preserve the executable bit git requires on hooks.
    cat "$tmp" >"$hook"
    rm -f "$tmp"
    chmod +x "$hook"
}

install_hooks() {
    command -v graphify >/dev/null 2>&1 || die "graphify is not on PATH. Install it first: pip install graphifyy"
    # Test seam: lets the suite hand patch_worktree_guard a hand-written hook
    # standing in for a future graphify whose guard has changed shape. Not a
    # supported knob for users.
    if [ "${HIVESMITH_GRAPHIFY_SKIP_HOOK_INSTALL:-0}" != "1" ]; then
        graphify hook install >/dev/null 2>&1 \
            || die "graphify hook install failed. Run it by hand to see why."
    fi
    patch_worktree_guard "$HOOKS_DIR/post-commit"
    patch_worktree_guard "$HOOKS_DIR/post-checkout"
    say "  git hooks    post-commit + post-checkout installed, worktree guard lifted"
}

uninstall_hooks() {
    if command -v graphify >/dev/null 2>&1; then
        graphify hook uninstall >/dev/null 2>&1 || true
    fi
    say "  git hooks    removed"
}

# ---------------------------------------------------------------------------
# 3. Claude Code PostToolUse hook
# ---------------------------------------------------------------------------

REFRESH_REL="scripts/graphify-refresh.sh"
# $CLAUDE_PROJECT_DIR is expanded by Claude Code at hook time, not here.
# shellcheck disable=SC2016
HOOK_COMMAND='"$CLAUDE_PROJECT_DIR"/scripts/graphify-refresh.sh'

copy_refresh_script() {
    src="$SELF_DIR/graphify-refresh.sh"
    [ -f "$src" ] || die "missing $src"
    mkdir -p "$(dirname "$REFRESH_REL")"
    # Skip the copy when the destination IS the source (hivesmith dogfooding
    # from a checkout where both paths resolve to the same file).
    if [ ! -e "$REFRESH_REL" ] || ! cmp -s "$src" "$REFRESH_REL"; then
        cp "$src" "$REFRESH_REL"
    fi
    chmod +x "$REFRESH_REL"
    say "  refresh      $REFRESH_REL"
}

# Merge semantics mirror graphify's own installer (graphify/install.py):
# read, drop any prior entry of ours, append, write. Re-running never
# duplicates and never touches unrelated hooks.
settings_merge() {
    action="$1"   # install | uninstall
    python3 - "$action" "$HOOK_COMMAND" <<'PY'
import json, sys
from pathlib import Path

action, command = sys.argv[1], sys.argv[2]
path = Path(".claude/settings.json")
path.parent.mkdir(parents=True, exist_ok=True)

settings = {}
if path.exists():
    try:
        settings = json.loads(path.read_text(encoding="utf-8")) or {}
    except json.JSONDecodeError:
        print(f"graphify-setup: {path} is not valid JSON; refusing to touch it", file=sys.stderr)
        raise SystemExit(1)

hooks = settings.setdefault("hooks", {})
entries = hooks.setdefault("PostToolUse", [])
if not isinstance(entries, list):
    print(f"graphify-setup: {path} hooks.PostToolUse is not a list; refusing to touch it", file=sys.stderr)
    raise SystemExit(1)

# Ours is identified by the refresh script name, so an unrelated
# Edit|Write|MultiEdit hook belonging to someone else survives both paths.
kept = [e for e in entries if "graphify-refresh.sh" not in json.dumps(e)]

if action == "install":
    kept.append({
        "matcher": "Edit|Write|MultiEdit",
        "hooks": [{"type": "command", "command": command}],
    })

if kept:
    hooks["PostToolUse"] = kept
else:
    hooks.pop("PostToolUse", None)
if not hooks:
    settings.pop("hooks", None)

if not settings:
    path.unlink(missing_ok=True)
else:
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
PY
}

# ---------------------------------------------------------------------------
# 4. AGENTS.md block
# ---------------------------------------------------------------------------

AGENTS_BEGIN="<!-- BEGIN HIVESMITH GRAPHIFY -->"
AGENTS_END="<!-- END HIVESMITH GRAPHIFY -->"

agents_block() {
    cat <<EOF
$AGENTS_BEGIN
## Knowledge graph (graphify)

This project keeps a structural map of its own code in \`$OUT/\`. It refreshes
automatically — after agent edits (debounced) and on commit/checkout, in every
worktree. Do not run a rebuild by hand as part of ordinary work.

- **Orient** before a repo-wide change: read \`$OUT/GRAPH_REPORT.md\`.
- **Trace a connection:** \`graphify query "how does X reach Y"\`.
- **Blast radius** before editing a shared symbol: \`graphify affected "SymbolName"\`.
- **Rebuild concepts** (costs LLM tokens, so only when the *meaning* of the code
  moved, not its structure): \`/graphify\`.

Automatic refreshes are AST-only and never spend tokens. Set
\`HIVESMITH_GRAPHIFY_REFRESH=0\` to silence them for a session.
$AGENTS_END
EOF
}

# write_agents_block <install|uninstall> [block-text]
# The block is passed as an argument, not on stdin: stdin is already taken by
# the heredoc carrying the Python script.
write_agents_block() {
    [ -f AGENTS.md ] || { say "  AGENTS.md    not present, skipped"; return 0; }
    python3 - "$AGENTS_BEGIN" "$AGENTS_END" "$1" "${2:-}" <<'PY'
import sys, re
from pathlib import Path

begin, end, action, block = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
block = block.rstrip("\n") if action == "install" else ""
p = Path("AGENTS.md")
text = p.read_text(encoding="utf-8")

pattern = re.compile(re.escape(begin) + r".*?" + re.escape(end) + r"\n?", re.DOTALL)
if pattern.search(text):
    text = pattern.sub(block + ("\n" if block else ""), text)
elif block:
    text = block + "\n\n" + text
p.write_text(text, encoding="utf-8")
PY
}

# ---------------------------------------------------------------------------
# Drive
# ---------------------------------------------------------------------------

if [ "$MODE" = "uninstall" ]; then
    say "graphify-setup: removing (graphify $GRAPHIFY_VERSION)"
    unlink_cache
    uninstall_hooks
    settings_merge uninstall
    say "  settings     PostToolUse entry removed"
    write_agents_block uninstall
    say "  AGENTS.md    block removed"
    exit 0
fi

say "graphify-setup: wiring $(pwd) (graphify $GRAPHIFY_VERSION)"
link_cache
install_hooks
copy_refresh_script
settings_merge install
say "  settings     .claude/settings.json PostToolUse -> $REFRESH_REL"
write_agents_block install "$(agents_block)"
say "  AGENTS.md    knowledge-graph block written"
say ""
say "Done. Run /graphify once to build the initial graph if $OUT/graph.json is missing."
