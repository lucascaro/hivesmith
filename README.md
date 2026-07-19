# hivesmith

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A multi-agent dev workflow bundle for Claude Code, Codex, Gemini, Copilot, and Factory. Gives every AI agent in your toolkit a shared harness — a structured `docs/` system of record, a feature pipeline that drives PRs to convergence, and recurring background workflows that keep the codebase legible — installable into any project in one command.

Extracted from the [claude-mux](https://github.com/lucascaro/claude-mux) development process. Layout and loop primitives follow the pattern documented in OpenAI's [*Harness engineering*](https://openai.com/index/harness-engineering/) post.

## Why

Most AI coding agents have no persistent memory of what's being worked on and no coordination with each other. Hivesmith gives them a shared structure:

- **A repo-as-system-of-record layout** — product specs (the *what/why*) in `docs/product-specs/`, exec plans (the *how*, with append-only Decision log + Progress) in `docs/exec-plans/{active,completed}/`, plus stubs for `DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `golden-principles.md`. `AGENTS.md` is a short table of contents that points into the tree.
- **A feature pipeline** — ingest a GitHub issue, triage it, research the codebase, plan, implement, and ship. Each step is a single slash command writing to `docs/`. Any agent — Claude, Codex, Gemini — can pick up where another left off.
- **PR convergence** — `/review-loop` drives any PR through review → autofix → re-review until findings clear or escalation criteria hit. `feature-implement` calls it after opening the PR; you can also run it on hand-authored PRs.
- **Recurring sweeps** — `/doc-garden` watches `docs/` for staleness and opens scoped fix-up PRs; `/gc-sweep` reads `golden-principles.md`, finds deviations in the codebase, and opens small refactor PRs.
- **A cross-project second brain** — `~/.hivesmith/brain/` is a git-tracked, scope-tagged store of durable lessons (gotchas, conventions, decisions) that hivesmith skills accumulate across every project. Read at the start of `feature-research` / `feature-plan` / `review-pr`; appended at convergence by `feature-implement` / `review-pr` / `review-loop`. Promotion across projects is gated by `/brain-promote`; tidying happens via `/brain-garden`.
- **A size-adaptive PR review** — `/review-pr` reviews the diff against four dimensions (correctness, safety, security, performance/UX/consistency) and then investigates what the diff reaches outside itself. It runs as one linear pass on an ordinary PR and splits the diff review across parallel agents only on a large one, where a single reader measurably degrades.
- **A release workflow** — changelog, version bump, and release script scaffolded once and invocable from any supported agent.

## What you get

### Skills

Invokable as `/feature-*`, `/review-loop`, etc.:

**Feature pipeline**

| Skill | What it does |
|---|---|
| `/feature-next` | Show pipeline status and recommend the next action |
| `/feature-ingest <#>` | Ingest a GitHub issue into `docs/product-specs/` |
| `/feature-triage [#]` | Classify type, complexity, and priority |
| `/feature-research [#]` | Explore the codebase, create the exec plan |
| `/feature-plan [#]` | Fill the exec plan's Approach, Files, and Tests sections |
| `/feature-implement [#]` | Code, test, commit, open a PR, drive convergence via `/review-loop` |
| `/feature-new [description]` | Create a GitHub issue then run ingest + triage |
| `/feature-loop [# \| description]` | Drive one feature through TRIAGE → RESEARCH → PLAN → IMPLEMENT → DONE with confirmation gates |
| `/plan-html <task>` | Render a plan as self-contained HTML with per-section feedback textareas + ✓ Approve button, backed by a localhost feedback server. Used by `feature-loop plan ...` by default; set `HIVESMITH_PLAN_HTML=0` to opt out. |

**Loop primitives**

| Skill | What it does |
|---|---|
| `/review-loop [#]` | Drive a PR through review → autofix → re-review until findings clear or escalation criteria hit |
| `/doc-garden` | Recurring sweep over `docs/` — detect stale docs, broken cross-links, drifted generated content; open one scoped fix-up PR per doc |
| `/gc-sweep` | Read `golden-principles.md`, scan the codebase for deviations, open small targeted refactor PRs (one principle per PR) |
| `/brain-ask <question>` | Search the brain and answer with citations |
| `/brain-garden` | Tend `~/.hivesmith/brain/`: regenerate the index, archive expired entries, surface promotion + dedupe candidates |
| `/brain-promote [<slug>]` | Broaden a brain entry's scope (project → user / ecosystem / universal). The only path that broadens scope. With no slug, presents a picker. |

**Review and release**

| Skill | What it does |
|---|---|
| `/review-pr <#>` | Deep PR review — linear two-pass, fans out only on large diffs (used by `/review-loop`) |
| `/autofix [#]` | Apply safe fixes from review findings, CI failures, or PR comments (used by `/review-loop`) |
| `/changelog-update` | Add an `[Unreleased]` entry to `CHANGELOG.md` |
| `/release <version>` | Pre-flight checks, version-bump suggestion, runs `scripts/release.sh` |

**Setup**

| Skill | What it does |
|---|---|
| `/hivesmith-init` | Scaffold the harness layout into a project (see below). `--migrate` splits an existing `features/` layout into `docs/`. |
| `/namecheck` | Check name availability on npm, GitHub, and popular TLDs |

### Templates

One-time scaffolding copied into your project by `/hivesmith-init`:

- `docs/product-specs/`, `docs/exec-plans/{active,completed}/`, `docs/design-docs/`, `docs/references/`, `docs/generated/` — the system-of-record tree
- `docs/product-specs/_template.md`, `docs/exec-plans/_template.md` — file shapes the pipeline writes to
- `docs/exec-plans/tech-debt-tracker.md`, `docs/design-docs/core-beliefs.md`
- `AGENTS.md` table of contents — or `AGENTS.hivesmith.md` appended to an existing `AGENTS.md`
- `DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `FRONTEND.md` — top-level stubs
- `golden-principles.md` — mechanical rules `/gc-sweep` enforces
- `CHANGELOG.md` (Keep a Changelog format, `[Unreleased]` section ready)
- `scripts/release.sh` (stack-agnostic scaffold)
- `CONTRIBUTING.md` skeleton
- `features/BACKLOG.md`, `features/templates/FEATURE.md`, `features/ingest.sh` — legacy layout, only scaffolded when explicitly requested or migrating an existing project

## Requirements

- `bash` 4+
- `git`
- `python3` (installer uses it to parse `agents.json`)

## Install

```bash
git clone https://github.com/lucascaro/hivesmith ~/.hivesmith
~/.hivesmith/install.sh
```

This symlinks each skill into every detected agent's skills directory (`~/.claude/skills/`, `~/.codex/skills/`, `~/.factory/skills/`, `~/.gemini/skills/`, `~/.copilot/skills/`). Agents whose parent directory does not exist are skipped automatically.

It also symlinks the bundled **subagent definitions** (`agents/*.md`) into any harness that declares an `agents_dir` in `agents.json`. Today only `claude` does, so subagents land in `~/.claude/agents/` and other harnesses are unaffected. `/feature-qa` uses `hs-validator` for its parallel validator fan-out; `/review-pr` uses `hs-reviewer` for its two fan-out paths — splitting the diff review on a large PR, and escalating a single oversized out-of-diff investigation — and reviews everything else inline. Both fall back to built-in agent types when the definitions aren't installed. Subagent filenames are **not** affected by `--prefix` — they always install as `hs-reviewer.md` / `hs-validator.md`.

### Namespaced install (`--prefix`)

To avoid name collisions with other skills, install under a prefix:

```bash
~/.hivesmith/install.sh --prefix hs-
```

Skills install as `/hs-feature-plan`, `/hs-release`, etc. Cross-skill references inside each `SKILL.md` are rewritten so the pipeline still works end-to-end. The prefix is persisted to `~/.hivesmith.toml`, so `--update` and `--uninstall` don't need it re-passed. Pass `--prefix ""` to clear it on a later run.

## Update

```bash
~/.hivesmith/install.sh --update
```

Runs `git pull --ff-only` in `~/.hivesmith`, then re-runs symlink reconciliation. Auto-upgrade is **opt-in** — pass `--auto-upgrade` to install a daily cron; the choice is remembered in `~/.hivesmith.toml` so subsequent runs honor it without re-passing the flag. `--no-auto-upgrade` opts back out (and removes any existing cron). `--no-auto-update` is a deprecated alias.

## Per-skill opt-out

Create `~/.hivesmith.toml` to skip skills globally or restrict an agent to a subset:

```toml
# skip a skill for all agents
disable = ["review-pr"]

# restrict one agent to specific skills
[agents.gemini]
only = ["feature-next", "feature-ingest"]
```

Re-run `install.sh` to apply. Removed skills are unlinked cleanly.

## Claude plugin install (Claude Code only)

If you only use Claude Code and prefer the native plugin flow:

```
/plugin marketplace add lucascaro/hivesmith
/plugin install hivesmith@hivesmith
```

Skills are invokable as `/hivesmith:feature-next`, etc.

## Per-project scaffolding

Inside any repo, run `/hivesmith-init`. It will:

1. Ask which pieces to scaffold (`docs/` system-of-record tree, top-level stubs, `AGENTS.md`, `scripts/release.sh`, `CONTRIBUTING.md`, optional legacy `features/` layout)
2. Copy them in with safe defaults
3. Refuse to overwrite existing files without `--force`

After scaffolding:

1. Edit `AGENTS.md` to fill in the module map and build/test commands.
2. Edit `golden-principles.md` to define the rules `/gc-sweep` will enforce (start with 5–10 principles).
3. Edit `DESIGN.md` to document domains and layers.
4. Run `/feature-next` to see the pipeline status and get your first recommended action.

### Migrating an existing project

If you already have the legacy `features/` layout, run:

```
/hivesmith-init --migrate
```

This splits each `features/<state>/<NNN>-*.md` file into a product spec (`docs/product-specs/`) and an exec plan (`docs/exec-plans/{active,completed}/`), preserving the Decision log and Progress sections verbatim. The legacy `features/` directory is left untouched as a fallback; the pipeline reads `docs/` first and falls back to `features/` for one release.

## Uninstall

```bash
~/.hivesmith/install.sh --uninstall
```

Removes all symlinks from every agent's skills directory. The `~/.hivesmith` clone is preserved; `rm -rf ~/.hivesmith` to remove it entirely.

## Contributing

PRs welcome. See [CONTRIBUTING.md](./CONTRIBUTING.md) for development setup, skill authoring conventions, and the PR process.

Security issues: please use [GitHub's private vulnerability reporting](https://github.com/lucascaro/hivesmith/security/advisories/new) — see [SECURITY.md](./SECURITY.md).

## License

MIT — see [LICENSE](./LICENSE).
