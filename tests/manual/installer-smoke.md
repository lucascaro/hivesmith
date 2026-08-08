# Installer smoke test

Manual checklist for `install.sh`. Run in an **isolated scratch environment** so
the real global install and crontab are never touched.

```bash
SB=$(mktemp -d)
HS=$(git rev-parse --show-toplevel)          # this hivesmith clone
FAKE_HOME="$SB/home"; mkdir -p "$FAKE_HOME/.claude"   # fake global claude harness
PROJ="$SB/proj";      mkdir -p "$PROJ/.claude"        # fake local claude harness
export HIVESMITH_DIR_CONFIG="$FAKE_HOME/.hivesmith.toml"
run() { HOME="$FAKE_HOME" bash "$HS/install.sh" "$@" < /dev/null; }   # </dev/null = non-interactive
cd "$PROJ"
```

Each step lists the command and what to confirm.

1. **Local install** — `run --local`
   - `./.claude/skills/*` are symlinks into the clone; `./.claude/agents/*` too.
   - `./.hivesmith.toml` contains `agents = ["claude"]`.
   - `$FAKE_HOME/.claude/skills` was **not** created (global untouched).

2. **Selection remembered / idempotent** — `run --local`
   - Reports `already present`, no new links, reads selection from `./.hivesmith.toml`.

3. **`--agents` parameter** — `run --local --agents claude`
   - Only `claude` targeted. Bad value: `run --local --agents bogus` → `Error: Unknown agent 'bogus'`, exit 1.

4. **`--force`**
   - `printf REAL > ./.claude/skills/release` then `run --local` → WARN "skipping (use --force…)", file untouched.
   - `run --local --force` → WARN "overwriting (--force)", `release` is now a symlink.

5. **`--status`** — `run --status`
   - Shows both `global` and `local` sections with per-harness counts, prefix (if set), brain-bin, auto-upgrade. Exit 0.

6. **`--doctor` detects breakage** — narrow to local
   - Break a link: `rm ./.claude/skills/release && ln -s "$HS/skills/NOPE" ./.claude/skills/release` (dangling, owned).
   - `run --doctor --local` → reports `broken release … → dangling (fix: install.sh --update --local)`, exits **non-zero**.
   - Repair: `run --local --force`; `run --doctor --local` → `No problems found`, exit 0.

7. **Local uninstall isolation** — `run --uninstall --local`
   - All local links removed; `$FAKE_HOME/.hivesmith/bin` (brain helpers) still present. Note step 1's local install already created this global brain-bin (skills reference it by absolute path), so this assertion is live — a local uninstall must not touch it.

8. **Prefix-independent uninstall**
   - `run --local --prefix hs-` → links install as `hs-*`, `./.hivesmith.toml` has `prefix = "hs-"`.
   - `run --uninstall --local` (no `--prefix`) → all `hs-*` links removed (ownership sweep).

9. **Global round-trip** — `run --global`
   - `$FAKE_HOME/.claude/skills` populated. (Skip `--uninstall --global` unless you want the cron/brain-bin paths exercised — it reads the real crontab.)

10. **Color + help**
    - Piped output (as above) has no ANSI. In a real terminal, headings/tags are colored; `--no-color` or `NO_COLOR=1` disables it.
    - `bash "$HS/install.sh" --help` lists `--local`, `--global`, `--force`, `--status`, `--doctor`, `--agents`, `--no-color`.

11. **Multi-harness detection** — `mkdir -p "$FAKE_HOME/.gemini" "$FAKE_HOME/.copilot"` then `run --global`
    - claude/gemini/copilot each get the **same non-zero** skill count (matching `ls "$HS/skills" | wc -l`); only claude gets subagents. (Regression guard: these harnesses have an empty `agents_dir`, which a tab-delimited registry would mis-parse — the fix uses a non-whitespace separator.)

## Known limitation

`--doctor` reports **broken** (dangling) hivesmith symlinks, but does not flag a
foreign file/symlink *blocking* a skill that should be linked — that skill is
simply absent, and `--force` on the next install is the remedy. Reporting
"blocked" reliably would require reconciling per-scope prefix/`disable`/`only`,
which is intentionally out of scope here.

Cleanup: `rm -rf "$SB"`.
