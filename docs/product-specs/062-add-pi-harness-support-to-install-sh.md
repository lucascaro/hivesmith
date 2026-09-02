---
issue: 62
title: Add pi harness support to install.sh
type: enhancement
complexity: S
priority: P2
stage: GATE
pr: 63
# shipped: 2026-MM-DD  # uncomment on DONE
---

# Add pi harness support to install.sh

- **Exec plan:** [docs/exec-plans/active/062-add-pi-harness-support-to-install-sh.md](../exec-plans/active/062-add-pi-harness-support-to-install-sh.md)

## Problem

`install.sh` fans skill symlinks out to every harness listed in `agents.json` — `claude`, `codex`, `factory`, `gemini`, `copilot`. The pi coding agent (`@earendil-works/pi-coding-agent`) is missing, even though this repo already treats pi as a first-class harness elsewhere: `scripts/telemetry/install-pi.sh` installs a pi extension and is in the shellcheck list. pi users have to link hivesmith skills by hand or point pi's `settings.json` at another harness's directory.

Registering pi is not a one-line registry addition. pi's skill directories are asymmetric — `~/.pi/agent/skills/` globally but `.pi/skills/` in a project — while `scope_path()` (`install.sh:360-365`) assumes `~/.foo/x` maps to `./.foo/x`. A naive entry would make `--local` installs link into a directory pi never reads.

## Desired behavior

`install.sh` detects pi like any other harness and links skills into the directory pi actually loads them from, in both scopes: `~/.pi/agent/skills/` for `--global` and `./.pi/skills/` for `--local`. `--agents pi`, `--status`, `--doctor`, and `--uninstall` all work against pi with no pi-specific flags.

## Success criteria

- `agents.json` declares a `pi` entry, and `install.sh --agents pi` is accepted (no "Unknown agent" error).
- A `--global` install with `~/.pi` present populates `~/.pi/agent/skills/` with the same skill count as the other harnesses.
- A `--local --agents pi` install creates symlinks under `./.pi/skills/` and does **not** create `./.pi/agent/`.
- Harnesses without the new registry key resolve their local target exactly as before.
- `--uninstall --local --agents pi` removes every link under `./.pi/skills/`.
- A runnable test covering the above lands in `tests/` and runs in CI.
- `README.md` documents pi's fan-out target, the divergent local path, and pi's project-trust requirement for project skills.

## Non-goals

- Declaring an `agents_dir` for pi — pi core ships no subagent directory (subagents come from the optional `pi-subagents` package).
- Registering hivesmith skills at pi's harness-agnostic `~/.agents/skills/` location.
- Changing how skills are rendered, prefixed, or authored for pi. pi implements the Agent Skills standard, so hivesmith skills work unmodified.
- Any change to `scripts/telemetry/install-pi.sh`.

## Notes

pi's discovery rules are documented in the installed pi package (`docs/skills.md`, pi 0.84.4). The `~/.pi/agent/` vs `.pi/` split is already hand-handled in `scripts/telemetry/install-pi.sh:26,33`.
