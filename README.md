# hivesmith

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A multi-agent dev workflow bundle for Claude Code, Codex, Gemini, Copilot, and Factory. Gives every AI agent in your toolkit a shared feature pipeline, PR review workflow, and release scaffolding — installable into any project in one command.

Extracted from the [claude-mux](https://github.com/lucascaro/claude-mux) development process.

## Why

Most AI coding agents have no persistent memory of what's being worked on and no coordination with each other. Hivesmith gives them a shared structure:

- **A feature pipeline** — ingest a GitHub issue, triage it, research the codebase, plan, implement, and ship. Each step is a single slash command; each result is written to `features/` so any agent — Claude, Codex, Gemini — can pick up where another left off.
- **A parallel PR review** — three independent review agents (correctness & logic, safety & test isolation, performance & UX consistency) run in parallel and synthesize a single structured verdict.
- **A release workflow** — changelog, version bump, and release script scaffolded once and invocable from any supported agent.

## What you get

### Skills

Invokable as `/feature-*`, `/review-pr`, etc.:

| Skill | What it does |
|---|---|
| `/feature-next` | Show pipeline status and recommend the next action |
| `/feature-ingest <#>` | Ingest a GitHub issue into the local pipeline |
| `/feature-triage [#]` | Classify type, complexity, and priority |
| `/feature-research [#]` | Explore the codebase and document findings |
| `/feature-plan [#]` | Write a concrete implementation plan |
| `/feature-implement [#]` | Code, test, commit, and open a PR |
| `/feature-new [description]` | Create a GitHub issue then run ingest + triage |
| `/review-pr <#>` | Parallel-agent deep PR review |
| `/changelog-update` | Add an `[Unreleased]` entry to `CHANGELOG.md` |
| `/release <version>` | Pre-flight checks, version-bump suggestion, runs `scripts/release.sh` |
| `/hivesmith-init` | Scaffold the pipeline into a project (see below) |

### Templates

One-time scaffolding copied into your project by `/hivesmith-init`:

- `features/BACKLOG.md`, `features/templates/FEATURE.md`, `features/ingest.sh` — pipeline tracking
- `AGENTS.md` skeleton (module map, conventions, test strategy) — or `AGENTS.hivesmith.md` appended to an existing `AGENTS.md`
- `CHANGELOG.md` (Keep a Changelog format, `[Unreleased]` section ready)
- `scripts/release.sh` (stack-agnostic scaffold)
- `CONTRIBUTING.md` skeleton

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

1. Ask which templates to scaffold (features pipeline, `AGENTS.md`, `scripts/release.sh`, `CONTRIBUTING.md`)
2. Copy them in with safe defaults
3. Refuse to overwrite existing files without `--force`

After scaffolding, run `/feature-next` to see the pipeline status and get your first recommended action.

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
