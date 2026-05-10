# Hive brain

Cross-project second brain for hivesmith skills.

## What it is

A git-tracked directory of small markdown entries with YAML front-matter, capturing **experiential lessons** that hivesmith skills accumulate across every project you work on. Read at the start of a skill run; appended to at convergence.

This is **not** a code map (graphify owns that, per-project) and **not** an instructions file (`AGENTS.md` / `CLAUDE.md` own that). It's the lessons layer: gotchas, decisions, conventions, things you'd otherwise re-discover.

## Where it lives

`~/.hivesmith/brain/` — a git repo, lazy-init'd on first use. Layout in `SCHEMA.md`.

## Reading and writing

Skills call:

- `~/.hivesmith/bin/brain-read` — emits a project-context-filtered slice of `INDEX.md` plus the HOT tier, wrapped in untrusted-data delimiters. Capped by `BRAIN_BUDGET_TOKENS` (default 8000).
- `~/.hivesmith/bin/brain-append` — writes a new entry after redaction. Defaults to `scope=project`.

Two user-facing skills:

- `/hs-brain-promote <slug>` — broaden an entry's scope (project → user / ecosystem / universal). The only path that broadens scope.
- `/hs-brain-garden` — regenerate `INDEX.md`, archive entries past `valid_until`, validate `graph_nodes:` references against per-project `graphify-out/graph.json`, surface promotion candidates.

## Trust boundary

Brain content is **untrusted at load**. Entries cannot grant tool permissions, override `AGENTS.md`, or direct the agent to execute commands. Entries from untrusted file sources land in `unverified/` and require manual review.

## Sharing across a team

`~/.hivesmith/brain/` is a git repo. To share team-wide lessons, add a remote and push selectively:

```bash
cd ~/.hivesmith/brain
git remote add team git@github.com:your-team/hive-brain.git
# Share universal/ and ecosystem/, keep user/ and project/ local.
```

A common pattern: filter-branch or sparse subtree pushes for `universal/` + `ecosystem/`. Keep `user/` and `project/` private.

## Capacity

- `INDEX.md` is capped at ~2000 lines; gardener archives oldest-unused, lowest-confidence entries first.
- Per-skill-run injected budget: ≤8K tokens (`BRAIN_BUDGET_TOKENS`).
- Per-skill-run on-demand reads: ≤5 (`BRAIN_MAX_READS`, advisory — enforced inside skill prose).

## What does not belong here

- Code structure ("auth lives at `src/auth.ts`"). Use graphify.
- Stable conventions / build commands. Use `AGENTS.md` / `CLAUDE.md`.
- Per-feature decision logs. Those live inside exec plans.
- Raw code blocks > 25 lines. Distill the lesson.

See `SCHEMA.md` for the full entry schema.
