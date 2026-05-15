---
name: changelog-update
description: "Add a per-PR changeset under .changesets/ for a user-visible change"
argument-hint: "[category] [short description]"
allowed-tools: Read Write Bash
---

# Update CHANGELOG (via .changesets/)

Add a per-PR changeset file under `.changesets/` for the current change. Use this whenever a PR introduces user-visible behavior.

`CHANGELOG.md` is **generated** from `.changesets/*.md` by `scripts/regen-generated.sh` (a post-merge GitHub Action runs the regenerator on `main`). You never edit `CHANGELOG.md` directly — CI will reject PRs that do.

## Steps

1. **Locate `.changesets/`** at the repo root. If missing, tell the user to run `/hivesmith-init` to scaffold it and stop. If `.changesets/README.md` is absent, also stop — the project has not adopted the new layout yet.

2. **Determine the entry details.**
   - If `$ARGUMENTS` provides a category and description, use them.
   - Otherwise, inspect the current working tree (`git diff main...HEAD` or staged diff) and infer:
     - **Category (`type:`)** — one of `added`, `changed`, `deprecated`, `removed`, `fixed`, `security`. Ask the user if ambiguous.
     - **Bump (`bump:`)** — `major` / `minor` / `patch` / `none`. Default: `patch` for `fixed` / `security` / `deprecated`; `minor` for `added` / `changed`; `major` for `removed` or any breaking change. Ask if uncertain.
     - **Description** — one bold headline sentence ("**Add X.**") plus optional body bullets. Imperative, user-facing.
     - **Issue reference** — if a GitHub issue exists, record it in the `issue:` frontmatter field. If a PR is open, record it in `pr:`.

3. **Allocate a filename.**
   - Format: `.changesets/<NNN>-<slug>.md`.
   - `<NNN>` — zero-padded sequential id, smallest unused integer not present in any existing `.changesets/*.md`. Use the GitHub issue number when one exists and is not already used.
   - `<slug>` — kebab-case, ~3–6 words, from the description.

4. **Write the file** with this exact frontmatter shape:

   ```markdown
   ---
   issue: <number>          # optional; omit if no issue exists yet
   pr: <number>             # optional; fill when PR opens
   type: added | changed | fixed | removed | deprecated | security
   bump: major | minor | patch | none
   ---
   - **Headline sentence.** Optional body bullets describing user-visible impact.
   ```

5. **Show the new file path and contents** to the user and confirm.

## Rules

- **One changeset per user-visible change.** Internal refactors without observable impact do not belong here — use the `no-changeset` PR label instead.
- **Imperative, present tense** in the body. The `### Added` (etc.) heading is supplied at render time.
- **Only the six Keep-a-Changelog categories** are valid `type:` values.
- **Never edit `CHANGELOG.md` directly** — it's generated. `block-generated-edits` CI will fail the PR if you do. Use the `regen-override` PR label only when intentionally bypassing this (migration / regenerator bug fixes / history imports).
- **Never stamp a date or bump VERSION here.** That is `/release`'s job; `release.sh` rolls all `.changesets/*.md` into a stamped section and deletes them.
- **Filenames are the sort key.** Within each `### <Type>` section, changesets render in filename order — monotonic `NNN-` prefixes ensure new entries always append.
