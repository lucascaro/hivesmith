---
issue: 58
title: Wire graphify into hivesmith with shared cache and auto-refresh hooks
type: enhancement
complexity: M
priority: P2
pr: 59
shipped: 2026-08-30
stage: DONE
---

# Wire graphify into hivesmith with shared cache and auto-refresh hooks

- **Exec plan:** [docs/exec-plans/completed/058-wire-graphify-into-hivesmith-with-shared-cache.md](../exec-plans/completed/058-wire-graphify-into-hivesmith-with-shared-cache.md)

## Problem

Hivesmith's feature pipeline runs almost entirely inside git worktrees, but graphify's installed git hook contains an unconditional worktree guard (`graphify/hooks.py:295`) that exits 0 in any linked worktree — so the knowledge graph never refreshes where the work actually happens. Separately, graphify's extraction cache resolves to `<root>/graphify-out/cache/` per checkout, so every new worktree starts cold and re-pays for semantic (LLM) extraction on byte-identical files whose cache keys are already content hashes. Finally, nothing refreshes the graph mid-session: `AGENTS.md` only *asks* the agent to run `graphify . --update`, and prose is not a mechanism.

## Desired behavior

A project runs `/hs-graphify-init` once and thereafter its graphify knowledge graph stays current without anyone thinking about it — in the primary checkout and in every worktree. Semantic extraction is paid for once per unique file content across the whole repo, not once per worktree. Each worktree's `graph.json` reflects its own branch. Every automatic refresh is AST-only, so no automatic path spends tokens.

## Success criteria

- `/hs-graphify-init` exists as a hivesmith skill and is installed by `install.sh`'s existing skill auto-discovery. (Amended at gate: the original wording also required `templates/scripts/` copies. Implementation dropped those deliberately — the setup copies its own refresh script, so a template copy would be a third source of the same file to keep in sync, and `/hs-hivesmith-init` now offers to run the skill instead of scaffolding scripts it cannot keep current. See the exec plan's decision log.)
- After setup, `graphify-out/cache` in both the primary checkout and any linked worktree is a symlink resolving to the same shared directory under `$(git rev-parse --git-common-dir)`.
- A `git commit` inside a linked worktree triggers a graph rebuild (the upstream worktree guard is lifted).
- If the upstream hook text no longer matches the expected guard, setup exits non-zero naming the graphify version — it never silently leaves worktrees stale.
- An agent `Edit`/`Write`/`MultiEdit` triggers a debounced, detached, AST-only `graphify update`; the hook never blocks the tool call, never exits non-zero, and never bootstraps a graph from scratch.
- Setup is idempotent (two runs produce one hook block, byte-identical settings) and `--uninstall` fully reverses it, preserving cache contents.
- A populated real `graphify-out/cache` directory is never destroyed: setup refuses without `--migrate`.
- `skills/graphify-init/test/run-all.sh` passes and runs in CI; both new scripts pass `shellcheck`.

## Non-goals

- Any change to the graphify package itself. This is configuration and wiring only.
- Semantic (LLM) re-extraction on any automatic path.
- Building graphs in CI, or committing `graphify-out/`.
- Cross-repo/global graphs (`graphify global add`) and MCP server wiring.
- A pre-push gate or a skill-lifecycle refresh step (both considered and not selected).
- Upgrading the user's stale `~/.claude/skills/graphify` (0.4.23 vs package 0.9.53) — setup warns; the upgrade stays the user's call.

## Notes

- Approved via plan-first mode; the approved plan is reproduced verbatim in the exec plan's Approach section.
- Installed graphify at plan time: **0.9.53**.
- Two open questions were raised at plan review and left at their stated defaults on approval: (1) `.claude/settings.json` gets committed via a narrow `.gitignore` negation; (2) `/hs-graphify-init` stays an explicit offer inside `/hs-hivesmith-init` rather than running automatically.
- Follow-up worth filing upstream regardless of this work: ask graphify for a `GRAPHIFY_ALLOW_WORKTREE=1` escape hatch so the guard patch can be dropped.
