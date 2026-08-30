---
type: added
bump: minor
---
- **`/graphify-init` — graphify wiring that survives git worktrees.** graphify's own git hook contains an unconditional guard that exits in any linked worktree, and its extraction cache lives per-checkout — so for a worktree-based workflow the code knowledge graph never refreshed where the work happened, and every new worktree re-paid for semantic (LLM) extraction on byte-identical files. The new skill wires four things and is idempotent, reversible (`--uninstall`), and refuses to destroy a populated cache (`--migrate` required):

  1. **Shared extraction cache.** Each checkout's `graphify-out/cache` becomes a symlink into `$(git rev-parse --git-common-dir)/graphify-cache` — the one path every worktree resolves identically, never tracked, `git clean`-proof, and gone when the repo is. Cache keys are content hashes and graphify's writes are atomic, so sharing is safe without locking. Each worktree keeps its own `graph.json`, which stays correct per branch.
  2. **Worktree-aware git hooks.** Runs `graphify hook install` (one install covers every worktree, since hooks live in the common dir) and then lifts the worktree guard. If a future graphify reshapes its generated hook text the patch no longer matches and setup **fails loudly naming the version** — it never leaves worktree graphs silently stale. Set `HIVESMITH_GRAPHIFY_WORKTREE=0` to restore upstream behavior.
  3. **Debounced auto-refresh.** A Claude Code `PostToolUse` hook on `Edit|Write|MultiEdit` runs an AST-only incremental rebuild at most once per window. It never blocks a tool call, never exits non-zero, and never bootstraps a graph from scratch. Tunable with `HIVESMITH_GRAPHIFY_DEBOUNCE` (default 90s) and `HIVESMITH_GRAPHIFY_REFRESH=0`.
  4. **graphify's `PreToolUse` orientation hooks.** These *print agent-directing text* fed back as context on `Read`/`Glob`/`Grep`/`Bash` — that is their purpose (nudging the agent to consult the graph before grepping), and it is invasive. Because `.claude/settings.json` is committed, they reach everyone who clones a wired repo, not only whoever ran the skill. Opt out with `--no-nudges` or `HIVESMITH_GRAPHIFY_NUDGES=0`.

  No automatic path spends LLM tokens — semantic extraction stays an explicit `/graphify` run.

  `/hivesmith-init` now *offers* to run it rather than printing a passive "install graphify" tip; it is never run unprompted, since it installs git hooks and an editor hook.

  **Migration for existing hivesmith codebases.** Run `./install.sh --update` to pick up the new skill, then `/graphify-init` in each project you want wired. If `graphify-out/cache` already exists as a real directory, the setup will refuse and tell you to re-run with `--migrate`, which preserves every existing entry. Nothing changes for projects that do not run it.
