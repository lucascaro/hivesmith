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
   - [ ] `AGENTS.md` — if missing, scaffold the full skeleton; if present without a hivesmith block, offer to *append* one (see step 5a)
   - [ ] `CONTRIBUTING.md` (contributor guide skeleton)
   - [ ] `CHANGELOG.md` (Keep a Changelog seed with `[Unreleased]` section)
   - [ ] `scripts/release.sh` (generic release scaffold)
   Default-check anything not already present. For `AGENTS.md`, default-check when the file is missing OR exists without the `<!-- BEGIN HIVESMITH -->` marker. For the other files, un-check anything already present (would require `--force`).

4. **If `--force` is passed**, offer to overwrite existing files — show a diff preview before each overwrite and get confirmation.

5. **Copy selected files** from `<hivesmith>/templates/` into the project, creating directories as needed:
   - `templates/features/` → `features/` (preserves `BACKLOG.md`, `templates/FEATURE.md`, and creates empty `active/`, `completed/`, `rejected/` dirs)
   - `templates/features/ingest.sh` → `features/ingest.sh` (chmod +x)
   - `templates/CONTRIBUTING.md` → `CONTRIBUTING.md`
   - `templates/CHANGELOG.md` → `CHANGELOG.md` (replace `OWNER/REPO` in compare link with the actual GitHub slug if known; otherwise leave as-is for the user to fix)
   - `templates/scripts/release.sh` → `scripts/release.sh` (chmod +x)

   **AGENTS.md is handled specially** (see step 5a).

5a. **AGENTS.md — append-or-create.** Do NOT clobber a user's existing `AGENTS.md`.
   - If `AGENTS.md` does NOT exist in the project: copy `templates/AGENTS.md` → `AGENTS.md` as a full skeleton.
   - If `AGENTS.md` exists AND already contains `<!-- BEGIN HIVESMITH -->`: do nothing (the block is already present; the user can edit it by hand).
   - If `AGENTS.md` exists and does NOT contain that marker: **ask the user first** — show them the content of `templates/AGENTS.hivesmith.md` and confirm "Append the hivesmith instructions block to your existing AGENTS.md? [Y/n]". If they decline, skip. If they accept, append the block verbatim (with a preceding blank line if the file doesn't already end in one) so it lands as a clearly-delimited section between `<!-- BEGIN HIVESMITH -->` and `<!-- END HIVESMITH -->` markers.
   - The same marker-based append/skip rule applies on re-runs — never append a duplicate hivesmith block.

6. **Apply the installed skill prefix to scaffolded/appended content** so documented slash-commands match what the user actually has installed:
   - Read `prefix = "..."` from `~/.hivesmith.toml` (fall back to `$HIVESMITH_DIR_CONFIG` if set). If the file is absent or has no `prefix` line, the prefix is empty and this step is a no-op.
   - When the prefix is non-empty (e.g. `hs-`), rewrite every `/skill-name` reference to `/prefix-skill-name` in:
     - the full `AGENTS.md` (if the skeleton was freshly scaffolded in step 5a), OR
     - just the appended hivesmith block (if step 5a appended to an existing `AGENTS.md`) — do NOT touch the user's pre-existing content above the `<!-- BEGIN HIVESMITH -->` marker.
     - the scaffolded `CONTRIBUTING.md`.
   - Known skill names: `feature-triage feature-ingest feature-research feature-plan feature-implement feature-new feature-next changelog-update release review-pr hivesmith-init`.
   - Use the same careful match as the installer: only rewrite `/<skill>` when preceded by start-of-line or a non-path character (whitespace, backtick, paren, bracket) and followed by end-of-line or a non-identifier character. Never rewrite `scripts/release.sh` (it's a path, not a slash-command).
   - Do NOT rewrite `CHANGELOG.md`, `features/**`, or `scripts/release.sh` — they don't reference slash-commands.

7. **Report what was created.** List each file with its size. Tell the user:
   - Edit `AGENTS.md` to fill in project-specific module map, build/test commands, and conventions — many other skills read it.
   - Edit `scripts/release.sh` to set `PROJECT`, `REPO`, and `BUILD_CMD` at the top.
   - Run `/feature-next` to verify the pipeline is wired up.

## Rules
- Never overwrite without `--force` + per-file user confirmation
- Never modify a user's existing `AGENTS.md` without an explicit yes to the append prompt in step 5a
- The hivesmith block in `AGENTS.md` is always bracketed by `<!-- BEGIN HIVESMITH -->` / `<!-- END HIVESMITH -->` so it can be identified, updated, or removed cleanly
- Preserve any existing content in directories being created (e.g. don't wipe a user's `features/active/` if it's already populated)
- Create `features/active/`, `features/completed/`, `features/rejected/` as empty dirs with `.gitkeep` if none exist
