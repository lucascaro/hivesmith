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
#   graphify-setup.sh [--migrate] [--uninstall] [--no-nudges] [--quiet] [project-dir]
#
#   --migrate    move an existing real <out>/cache into the shared dir instead
#                of refusing. Required whenever a real cache dir is in the way.
#   --uninstall  reverse everything: restore a real cache dir, strip hook
#                blocks, remove the settings entry.
#   --no-nudges  skip graphify's PreToolUse orientation hooks. They print
#                agent-directing text on Read/Glob/Grep/Bash; useful, but
#                invasive. Also settable as HIVESMITH_GRAPHIFY_NUDGES=0.
#
# Env: GRAPHIFY_OUT (default graphify-out), HIVESMITH_GRAPHIFY_NUDGES (default 1).

set -euo pipefail

MODE="install"
MIGRATE=0
QUIET=0
NUDGES="${HIVESMITH_GRAPHIFY_NUDGES:-1}"
PROJECT_DIR=""

while [ $# -gt 0 ]; do
    case "$1" in
        --migrate)   MIGRATE=1; shift ;;
        --uninstall) MODE="uninstall"; shift ;;
        --quiet)     QUIET=1; shift ;;
        --no-nudges) NUDGES=0; shift ;;
        -h|--help)   sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
# `git rev-parse --git-path hooks` resolves core.hooksPath (Husky, lefthook, a
# global ~/.githooks), which graphify itself honors. Hardcoding $COMMON/hooks
# meant patch_worktree_guard silently found no file and we still claimed the
# guard was lifted — the exact silent-staleness the loud drift check exists to
# prevent.
HOOKS_DIR="$(cd "$(dirname "$(git rev-parse --git-path hooks)")" && pwd)/$(basename "$(git rev-parse --git-path hooks)")"
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
        # A single cp that fails loudly, NOT a find|while pipeline: the loop
        # body runs in a subshell on the right of a pipe, so a failure flag set
        # inside it never reaches the `rm` below — and an unconditional rm after
        # a swallowed copy error destroys exactly the cache the die above
        # exists to protect. Entries are content-hash keyed, so overwriting a
        # same-named entry writes identical bytes.
        cp -R "$CACHE_LINK/." "$SHARED/" \
            || die "failed to copy $CACHE_LINK into $SHARED. Nothing was deleted; your cache is intact."
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
    # Same reasoning as link_cache: fail loudly rather than report a successful
    # restore over a copy that silently did nothing. The shared copy is left in
    # place either way, so a failure here is recoverable.
    if [ -d "$SHARED" ]; then
        cp -R "$SHARED/." "$CACHE_LINK/" \
            || die "failed to restore $CACHE_LINK from $SHARED. The shared copy is still intact at $SHARED."
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

# require=1 means "this hook must exist" — used after `graphify hook install`
# reported success, where a missing file means we are patching the wrong dir.
patch_worktree_guard() {
    hook="$1"
    require="${2:-0}"
    if [ ! -f "$hook" ]; then
        [ "$require" = "1" ] && die "$hook does not exist after 'graphify hook install' succeeded.
  Looked in: $HOOKS_DIR
  If this repo sets core.hooksPath, graphify and this script disagree about where
  hooks live. Refusing to report a lifted guard that was never applied."
        return 0
    fi

    if grep -q 'HIVESMITH_GRAPHIFY_WORKTREE' "$hook"; then
        return 0   # already patched (e.g. hook install left it in place)
    fi

    # mktemp, not fixed names: $hook lives in the git COMMON hooks dir, so every
    # worktree derives the identical path. Two concurrent graphify-init runs —
    # the exact scenario this script exists for — would otherwise interleave on
    # one temp file and cat a corrupted hook into place.
    tmp="$(mktemp "$hook.hivesmith.XXXXXX")" || die "could not create a temp file beside $hook"
    countfile="$(mktemp "$hook.hivesmith.XXXXXX")" || { rm -f "$tmp"; die "could not create a temp file beside $hook"; }
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
    # require=1 unless the install was skipped for the test seam.
    _req=1
    [ "${HIVESMITH_GRAPHIFY_SKIP_HOOK_INSTALL:-0}" = "1" ] && _req=0
    patch_worktree_guard "$HOOKS_DIR/post-commit" "$_req"
    patch_worktree_guard "$HOOKS_DIR/post-checkout" "$_req"
    say "  git hooks    post-commit + post-checkout installed, worktree guard lifted"
}

uninstall_hooks() {
    if ! command -v graphify >/dev/null 2>&1; then
        echo "graphify-setup: graphify is not on PATH; hooks in $HOOKS_DIR were left in place." >&2
        return 0
    fi
    if graphify hook uninstall >/dev/null 2>&1; then
        say "  git hooks    removed"
    else
        echo "graphify-setup: 'graphify hook uninstall' failed; post-commit and post-checkout may remain in $HOOKS_DIR." >&2
    fi
}

# ---------------------------------------------------------------------------
# 3. Claude Code PostToolUse hook
# ---------------------------------------------------------------------------

# The refresh script lives in the OUTPUT dir, which is gitignored — never in a
# tracked path. A committed hook pointing at a tracked script is a
# branch-controlled payload: a contributor PR editing that script's body gets
# code execution on any maintainer who checks the branch out and makes one
# edit, because what a reviewer sees is the unchanging command string, not the
# file it points at. Gitignored means a PR cannot change what runs.
REFRESH_REL="$OUT/graphify-refresh.sh"
# $CLAUDE_PROJECT_DIR is expanded by Claude Code at hook time, not here. The
# guard makes a missing script a no-op rather than a 127 on every tool call —
# the output dir can be wiped (`graphify uninstall --purge`, a stray clean)
# while the committed settings.json still names the hook.
# shellcheck disable=SC2016
HOOK_COMMAND='sh -c '"'"'[ -x "$CLAUDE_PROJECT_DIR/graphify-out/graphify-refresh.sh" ] || exit 0; exec "$CLAUDE_PROJECT_DIR/graphify-out/graphify-refresh.sh"'"'"''

# The committed hook's safety rests on its target being untracked, so ensure
# the output dir is actually ignored rather than assuming it. Without this, a
# project that has not ignored graphify-out/ could commit the refresh script
# and reopen the branch-controlled-payload path the hook was moved to avoid.
ensure_out_ignored() {
    git check-ignore -q "$OUT" 2>/dev/null && return 0
    printf '\n# graphify build artifacts (added by /graphify-init). The PostToolUse hook\n# in .claude/settings.json executes %s/graphify-refresh.sh, so this\n# directory MUST stay untracked — a tracked hook target is a payload any PR\n# could change.\n%s/\n' "$OUT" "$OUT" >> .gitignore
    say "  gitignore    added $OUT/ (the hook target must stay untracked)"
}

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

# graphify's own PreToolUse orientation nudges — the "consult the graph before
# reading files" half of the setup, and part of the approved plan.
#
# We call install.py's function directly instead of `graphify claude install`
# because the CLI also writes a graphify section into CLAUDE.md, which would
# duplicate the AGENTS.md block this script already maintains. `project=True`
# emits a bare command rather than an installing-machine-specific absolute path
# (graphify #3129) — correct for a committed settings.json.
#
# Best-effort: it reaches into a private function, so a future graphify that
# renames it degrades to a warning rather than failing the whole setup. The
# nudges are an enhancement; the cache and hooks are the load-bearing parts.
# Find a python that can `import graphify`. Deliberately tries several
# candidates: the package may live in a pipx/uv-tool venv that no ambient
# python can see, and the launcher's shebang may be a bare `#!/usr/bin/env
# python` rather than an absolute interpreter path — in which case the last
# field is the word "python", not something executable. Mirrors the probe
# chain graphify uses in its own git hooks.
graphify_python() {
    _cands="python3 python"
    launcher="$(command -v graphify 2>/dev/null || true)"
    if [ -n "$launcher" ]; then
        _shebang="$(head -n 1 "$launcher" 2>/dev/null | sed 's|^#!||')"
        case "$_shebang" in
            */env\ *) _cands="${_shebang#*/env } $_cands" ;;
            /*)        _cands="$(printf '%s' "$_shebang" | awk '{print $1}') $_cands" ;;
        esac
        _bindir="$(dirname "$launcher")"
        _cands="$_cands $_bindir/python3 $_bindir/python $_bindir/../bin/python3"
    fi
    for _c in $_cands; do
        case "$_c" in
            *[!a-zA-Z0-9/_.@:-]*) continue ;;   # path allowlist
        esac
        if command -v "$_c" >/dev/null 2>&1 && "$_c" -c 'import graphify' 2>/dev/null; then
            command -v "$_c"
            return 0
        fi
    done
    return 1
}

claude_nudges() {
    action="$1"   # install | uninstall
    # Opt-out. Unlike the PostToolUse refresh hook — which runs a script and
    # says nothing — these PreToolUse hooks print agent-directing text that is
    # fed back as context on Read/Glob/Grep/Bash, i.e. on an agent's most
    # frequent tool calls. That is the point of them, but it is invasive enough
    # that a project (or a contributor who merely cloned a repo where they are
    # committed) must be able to turn them off without hand-editing JSON.
    if [ "$NUDGES" != "1" ] && [ "$action" = "install" ]; then
        say "  nudges       skipped (--no-nudges / HIVESMITH_GRAPHIFY_NUDGES=0)"
        return 0
    fi
    py="$(graphify_python)" || {
        say "  nudges       skipped (no python with graphify importable)"
        return 0
    }
    fn="_install_claude_hook"
    [ "$action" = "install" ] || fn="_uninstall_claude_hook"
    # Keep stderr: a swallowed failure here let setup exit 0 reporting success
    # while the default-on hooks were never registered — and under --quiet
    # (the documented invocation) `say` printed nothing at all. stdout is still
    # dropped because graphify prints its own multi-line banner.
    nudge_err="$(mktemp)"
    if "$py" - "$fn" >/dev/null 2>"$nudge_err" <<'PYEOF'
import sys
from pathlib import Path
import graphify.install as gi
fn = getattr(gi, sys.argv[1], None)
if fn is None:
    print(f"graphify.install.{sys.argv[1]} does not exist in this graphify", file=sys.stderr)
    raise SystemExit(1)
if sys.argv[1] == "_install_claude_hook":
    fn(Path("."), project=True)
else:
    fn(Path("."))
PYEOF
    then
        rm -f "$nudge_err"
        [ "$action" = "install" ] && guard_nudge_commands
        say "  nudges       graphify PreToolUse orientation hooks ${action}ed"
        return 0
    fi

    # Always on stderr, bypassing say(), so --quiet cannot hide it.
    {
        echo "graphify-setup: could not $action graphify's PreToolUse orientation hooks."
        echo "  interpreter: $py"
        sed 's/^/  /' "$nudge_err"
    } >&2
    rm -f "$nudge_err"

    # An uninstall that cannot reach graphify is a warning: settings_merge
    # still runs and the user can drop the entry by hand. A default-on INSTALL
    # that fails is an error — the caller asked for these hooks, and
    # --no-nudges exists for anyone who does not want them.
    [ "$action" = "install" ] && die "refusing to report a successful setup with the nudges missing. Re-run with --no-nudges to proceed without them."
    return 0
}

# graphify registers its nudges as a bare `graphify hook-guard ...`. Since this
# settings.json is COMMITTED, anyone who clones without graphify installed would
# get exit 127 on every Bash/Grep/Read/Glob call. Wrap each command so a missing
# graphify is a silent no-op — the same degradation the refresh hook already has.
guard_nudge_commands() {
    python3 - <<'PYEOF'
import json
from pathlib import Path

path = Path(".claude/settings.json")
if not path.exists():
    raise SystemExit(0)
settings = json.loads(path.read_text(encoding="utf-8"))
changed = False
for entry in settings.get("hooks", {}).get("PreToolUse", []):
    for hook in entry.get("hooks", []):
        cmd = hook.get("command", "")
        if cmd.startswith("graphify ") and "command -v graphify" not in cmd:
            hook["command"] = f"command -v graphify >/dev/null 2>&1 && {cmd} || exit 0"
            changed = True
if changed:
    path.write_text(json.dumps(settings, indent=2) + "\n", encoding="utf-8")
PYEOF
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

This project also registers graphify's \`PreToolUse\` orientation hooks, which
print a reminder to consult the graph before \`Read\`/\`Glob\`/\`Grep\`/\`Bash\`.
Re-run the setup with \`--no-nudges\` (or \`HIVESMITH_GRAPHIFY_NUDGES=0\`) to drop
them while keeping everything else.
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
    claude_nudges uninstall
    settings_merge uninstall
    say "  settings     PostToolUse entry removed"
    write_agents_block uninstall
    say "  AGENTS.md    block removed"
    exit 0
fi

say "graphify-setup: wiring $(pwd) (graphify $GRAPHIFY_VERSION)"
link_cache
install_hooks
ensure_out_ignored
copy_refresh_script
settings_merge install
claude_nudges install
say "  settings     .claude/settings.json PostToolUse -> $REFRESH_REL"
write_agents_block install "$(agents_block)"
say "  AGENTS.md    knowledge-graph block written"
say ""
say "Done. Run /graphify once to build the initial graph if $OUT/graph.json is missing."
