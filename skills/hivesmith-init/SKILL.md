---
name: hivesmith-init
description: Scaffold hivesmith templates (features/, AGENTS.md, release.sh) into a project
argument-hint: [--force]
allowed-tools: Read Glob Write Bash
---

# Initialize hivesmith in a project

Scaffold the hivesmith templates into the current project so the feature-pipeline skills have the files they expect.

The hivesmith repo lives at `~/.hivesmith` (or wherever the user cloned it). Templates are under `<hivesmith>/templates/`.

## Steps

1. **Locate the hivesmith clone.** Try in order:
   - `$HIVESMITH_DIR` env var
   - `~/.hivesmith`
   - Resolve this skill's symlink target and walk up to the repo root
   If not found, tell the user to set `HIVESMITH_DIR` or reinstall.

2. **Detect what's already present** in the current working directory:
   - `features/BACKLOG.md`
   - `features/templates/FEATURE.md`
   - `features/ingest.sh`
   - `AGENTS.md`
   - `CONTRIBUTING.md`
   - `CHANGELOG.md`
   - `scripts/release.sh`

3. **Ask the user which pieces to scaffold.** Present a checklist:
   - [ ] Feature pipeline (`features/` tree + `ingest.sh`) — REQUIRED for feature-* skills to work
   - [ ] `AGENTS.md` (project conventions skeleton)
   - [ ] `CONTRIBUTING.md` (contributor guide skeleton)
   - [ ] `CHANGELOG.md` (Keep a Changelog seed with `[Unreleased]` section)
   - [ ] `scripts/release.sh` (generic release scaffold)
   Default-check anything not already present. Un-check anything already present (would require `--force`).

4. **If `--force` is passed**, offer to overwrite existing files — show a diff preview before each overwrite and get confirmation.

5. **Copy selected files** from `<hivesmith>/templates/` into the project, creating directories as needed:
   - `templates/features/` → `features/` (preserves `BACKLOG.md`, `templates/FEATURE.md`, and creates empty `active/`, `completed/`, `rejected/` dirs)
   - `templates/features/ingest.sh` → `features/ingest.sh` (chmod +x)
   - `templates/AGENTS.md` → `AGENTS.md`
   - `templates/CONTRIBUTING.md` → `CONTRIBUTING.md`
   - `templates/CHANGELOG.md` → `CHANGELOG.md` (replace `OWNER/REPO` in compare link with the actual GitHub slug if known; otherwise leave as-is for the user to fix)
   - `templates/scripts/release.sh` → `scripts/release.sh` (chmod +x)

6. **Apply the installed skill prefix to scaffolded files** so documented slash-commands match what the user actually has installed:
   - Read `prefix = "..."` from `~/.hivesmith.toml` (fall back to `$HIVESMITH_DIR_CONFIG` if set). If the file is absent or has no `prefix` line, the prefix is empty and this step is a no-op.
   - When the prefix is non-empty (e.g. `hs-`), rewrite every `/skill-name` reference inside the *just-scaffolded* `AGENTS.md` and `CONTRIBUTING.md` to `/prefix-skill-name`. The known skill names are: `feature-triage feature-ingest feature-research feature-plan feature-implement feature-new feature-next changelog-update release review-pr hivesmith-init`.
   - Use the same careful match as the installer: only rewrite `/<skill>` when preceded by start-of-line or a non-path character (whitespace, backtick, paren, bracket) and followed by end-of-line or a non-identifier character. Never rewrite `scripts/release.sh` (it's a path, not a slash-command).
   - Do NOT rewrite `CHANGELOG.md`, `features/**`, or `scripts/release.sh` — they don't reference slash-commands.

7. **Report what was created.** List each file with its size. Tell the user:
   - Edit `AGENTS.md` to fill in project-specific module map, build/test commands, and conventions — many other skills read it.
   - Edit `scripts/release.sh` to set `PROJECT`, `REPO`, and `BUILD_CMD` at the top.
   - Run `/feature-next` to verify the pipeline is wired up.

## Rules
- Never overwrite without `--force` + per-file user confirmation
- Preserve any existing content in directories being created (e.g. don't wipe a user's `features/active/` if it's already populated)
- Create `features/active/`, `features/completed/`, `features/rejected/` as empty dirs with `.gitkeep` if none exist
