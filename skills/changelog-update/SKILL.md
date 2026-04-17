---
name: changelog-update
description: "Add an entry under [Unreleased] in CHANGELOG.md for a user-visible change"
argument-hint: "[category] [short description]"
allowed-tools: Read Edit Bash
---

# Update CHANGELOG

Add an entry under `## [Unreleased]` in `CHANGELOG.md` for the current change. Use this whenever a PR introduces user-visible behavior.

## Steps

1. **Locate `CHANGELOG.md`** at the repo root. If missing, tell the user to run `/hivesmith-init` to scaffold it and stop.

2. **Verify Keep a Changelog format.** The file must have a `## [Unreleased]` heading. If not, warn the user and stop — do not silently rewrite.

3. **Determine the entry details.**
   - If `$ARGUMENTS` provides a category and description, use them.
   - Otherwise, inspect the current working tree (`git diff main...HEAD` or staged diff) and infer:
     - **Category** — one of: `Added`, `Changed`, `Deprecated`, `Removed`, `Fixed`, `Security`. Ask the user if ambiguous.
     - **Description** — one sentence, imperative mood ("Add X", "Fix Y"), focused on user-facing impact not implementation detail.
     - **Reference** — if a PR or issue number is known, append `(#NNN)`.

4. **Insert the entry.**
   - Find `## [Unreleased]` in `CHANGELOG.md`.
   - If a `### <Category>` subheading exists under it, append the bullet at the end of that subsection.
   - If not, create the subheading immediately after `## [Unreleased]` (ordered: Added, Changed, Deprecated, Removed, Fixed, Security).
   - Each entry is a single bullet: `- <description> (#NNN)`.

5. **Show the diff** (the inserted lines) and confirm with the user before saving. The Edit tool handles the write.

## Rules

- **One entry per user-visible change.** Internal refactors without observable impact do not belong here.
- **Imperative, present tense.** "Add dark mode" not "Added dark mode" or "Adds dark mode" in the bullet body — the `### Added` heading already supplies tense.
- **No category invention.** Only the six Keep a Changelog categories.
- **Never stamp a date or bump the version here.** That is `/release`'s job.
- **Do not touch released sections.** Only `[Unreleased]` is editable.
