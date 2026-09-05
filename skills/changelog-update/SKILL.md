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

2b. **When `type: fixed`, decide whether this is a regression.** Read the recent merged PR subjects:

   ```bash
   git log --format='%h %ad %s' --date=short -20            # squash-merge repos (the default)
   git log --merges --format='%h %ad %s' --date=short -20   # merge-commit repos
   ```

   If the defect is in code one of those PRs introduced, set `regression_of: <N>` (comma-separate when a fix undoes two PRs' interaction). You wrote those PR titles, so the mapping is checkable — this is not guesswork.

   If the defect predates that window, or lives in code no recent PR touched, **omit the field.** Do not guess and do not write `unknown` or `n/a`: absence is a meaningful state, and a metric that cannot tell "no regression" from "nobody looked" is worse than no metric.

   **Never infer this from `git blame`.** A bug can live on lines the fix never touches — a missing guard, an unhandled case, an ordering assumption — and a refactor that rewrites a file is not a defect in what it rewrote. Both directions of error are silent, which is why the declaration is made by you, who knows what you are fixing, rather than derived after the fact.

3. **Allocate a filename.**
   - Format: `.changesets/<NNN>-<slug>.md`.
   - `<NNN>` — zero-padded sequential id. Always allocate `max(existing changeset IDs) + 1`. Never reuse an unused slot earlier in the sequence: rendering is filename-sorted and append-only, and reusing a slot would rewrite lines outside your own changeset's section, re-introducing the merge-conflict pattern. The GitHub issue number is acceptable as the id only when it is larger than every existing changeset id.
   - `<slug>` — kebab-case, ~3–6 words, from the description.

4. **Write the file** with this exact frontmatter shape:

   ```markdown
   ---
   issue: <number>          # optional; omit if no issue exists yet
   pr: <number>             # optional; fill when PR opens
   type: added | changed | fixed | removed | deprecated | security
   bump: major | minor | patch | none
   regression_of: <PR>      # only with type: fixed; omit when not a regression
   regression_of_issue: <n> # optional companion to regression_of
   ---
   - **Headline sentence.** Optional body bullets describing user-visible impact.
   ```

5. **Show the new file path and contents** to the user and confirm.

## Rules

- **One changeset per user-visible change.** Internal refactors without observable impact do not belong here — use the `no-changeset` PR label instead.
- **Imperative, present tense** in the body. The `### Added` (etc.) heading is supplied at render time.
- **Only the six Keep-a-Changelog categories** are valid `type:` values.
- **`regression_of` is only valid with `type: fixed`,** and only as an integer (or comma-separated integers). CI validates the format, never the absence. Omitting it is always allowed; guessing never is.
- **Never edit `CHANGELOG.md` directly** — it's generated. `block-generated-edits` CI will fail the PR if you do. Use the `regen-override` PR label only when intentionally bypassing this (migration / regenerator bug fixes / history imports).
- **Never stamp a date or bump VERSION here.** That is `/release`'s job; `release.sh` rolls all `.changesets/*.md` into a stamped section and deletes them.
- **Filenames are the sort key.** Within each `### <Type>` section, changesets render in filename order — monotonic `NNN-` prefixes ensure new entries always append.
