---
type: changed
bump: minor
---
- **Installer gains local scope, cleanup, doctor/status, force, and colored output.** `install.sh` picks up several new capabilities:
  - **`--local`** installs into the current project (`./.claude/skills`, `./.claude/agents`, …) instead of the home dirs. It autodetects which harness directories exist in the project, prompts interactively on first install (or `--agents claude,codex` to select non-interactively), and remembers the choice in a project-local `./.hivesmith.toml` (override: `HIVESMITH_LOCAL_CONFIG`) that never reads or writes the global `~/.hivesmith.toml`.
  - **`--force`** overwrites a real file or foreign symlink that is blocking a skill link (scoped to the exact path, honored by `--dry-run`). Without it, blockers are skipped with a warning as before.
  - **`--status`** prints a read-only per-harness summary (link counts, prefix, brain-bin health, auto-upgrade state) for both global and local scopes; **`--doctor`** validates the installs, reports dangling links with a fix hint, and exits non-zero for CI.
  - **Scope-aware uninstall.** `--uninstall` now sweeps by ownership (any symlink into the clone), so it clears prefixed links without re-passing `--prefix`. Global-only side effects — the rendered-prefix tree, auto-upgrade cron, and `~/.hivesmith/bin` brain helpers — are gated to global scope, so `--uninstall --local` can't break a coexisting global install. (This also makes the brain-helper cleanup actually run on uninstall — it was previously unreachable dead code after an early `exit`.)
  - **Colored output**, auto-disabled when not a TTY, when `NO_COLOR` is set, or with `--no-color`.
- **Fix: only Claude was ever detected.** The agent registry was tab-delimited, but tab is IFS-whitespace, so the empty `agents_dir` field (present for every harness except Claude) collapsed two delimiters and blanked `detect_dir` — silently dropping Codex/Factory/Gemini/Copilot from detection. Switched the field separator to a non-whitespace unit separator; all detected harnesses now receive skills.
