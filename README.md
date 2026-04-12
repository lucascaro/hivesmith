# hivesmith

A multi-agent dev workflow bundle: feature pipeline, PR review, release scaffolding — installable into any project and usable from Claude Code, Codex, Gemini, Copilot, and Factory.

Extracted from the [claude-mux](https://github.com/lucascaro/claude-mux) development process.

## What you get

**Skills** (live, invokable as `/feature-*` etc.):

| Skill | What it does |
|---|---|
| `/feature-next` | Show pipeline status and recommend the next action |
| `/feature-ingest <#>` | Ingest a GitHub issue into the local pipeline |
| `/feature-triage [#]` | Classify type, complexity, priority |
| `/feature-research [#]` | Explore codebase, document findings |
| `/feature-plan [#]` | Write a concrete implementation plan |
| `/feature-implement [#]` | Code, test, commit, open PR |
| `/feature-new [description]` | Create an issue and run ingest + triage |
| `/review-pr <#>` | Parallel-agent deep PR review |
| `/hivesmith-init` | Scaffold `features/`, `AGENTS.md`, `scripts/release.sh` into a project |

**Templates** (one-time scaffolding, copied in via `/hivesmith-init`):

- `features/BACKLOG.md`, `features/templates/FEATURE.md`, `features/ingest.sh`
- `AGENTS.md` skeleton (module map, conventions, test strategy)
- `scripts/release.sh` (stack-agnostic scaffold)
- `CONTRIBUTING.md` skeleton

## Install

```
git clone https://github.com/lucascaro/hivesmith ~/.hivesmith
~/.hivesmith/install.sh
```

This symlinks each skill directory into every detected agent's skills dir (`~/.claude/skills/`, `~/.codex/skills/`, `~/.factory/skills/`, `~/.gemini/skills/`, `~/.copilot/skills/`). Agents whose parent dir does not exist are skipped.

## Update

```
~/.hivesmith/install.sh --update
```

Does `git pull --ff-only` in `~/.hivesmith`, then re-runs symlink reconciliation. A daily auto-update cron is installed on first run (disable with `--no-auto-update`).

## Per-skill opt-out

Create `~/.hivesmith.toml`:

```toml
# skip skills globally
disable = ["review-pr"]

# restrict an agent to a subset
[agents.gemini]
only = ["feature-next", "feature-ingest"]
```

Re-run `install.sh` to apply. Removed skills are unlinked cleanly.

## Claude plugin install (Claude-only alternative)

If you only use Claude Code and prefer the native `/plugin` flow:

```
/plugin marketplace add lucascaro/hivesmith
/plugin install hivesmith@hivesmith
```

Skills are invokable as `/hivesmith:feature-next` etc.

## Per-project scaffolding

Inside a repo, run `/hivesmith-init`. It will:

1. Ask which templates to scaffold (features pipeline, AGENTS.md, release.sh, CONTRIBUTING.md)
2. Copy them in with safe defaults
3. Refuse to overwrite existing files without `--force`

## Uninstall

```
~/.hivesmith/install.sh --uninstall
```

Removes all symlinks from every agent's skills dir. The `~/.hivesmith` clone is preserved; `rm -rf ~/.hivesmith` to remove entirely.
