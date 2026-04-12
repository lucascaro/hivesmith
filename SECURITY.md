# Security Policy

## Supported versions

Only the current `main` branch is supported. Tagged releases are snapshots — fixes go into `main` first.

## Reporting a vulnerability

**Please do not open public issues for security problems.**

Use GitHub's private vulnerability reporting:

1. Go to the repository's **Security** tab → **Report a vulnerability**.
2. Describe the issue with reproduction steps and the impact you believe it has.
3. We'll respond within a reasonable timeframe (best-effort — this is a solo-maintained project).

## Scope

In scope:

- `install.sh` — arbitrary command execution, symlink escape, TOML parser issues, path traversal.
- Skills under `skills/` — if a SKILL.md instructs an agent to take a clearly-unsafe action without user confirmation, that's a bug.
- Templates under `templates/` — seed files scaffolded into user projects.

Out of scope:

- Behavior of AI agents (Claude, Codex, etc.) themselves.
- Content a user writes in their own project's files after scaffolding.
- Third-party tools the installer invokes (`git`, `python3`, `crontab`).
