---
name: hivesmith-init
description: Scaffold hivesmith templates (docs/, features/, AGENTS.md, release.sh) into a project
argument-hint: "[--force] [--migrate]"
allowed-tools: Read Glob Write Bash
---

# Initialize hivesmith in a project

Scaffold the hivesmith templates into the current project so the feature-pipeline skills, loop primitives, and gardening skills have the files they expect.

The hivesmith repo lives at `~/.hivesmith` (or wherever the user cloned it). Templates are under `<hivesmith>/templates/`.

## Steps

1. **Locate the hivesmith clone.** Try in order:
   - `$HIVESMITH_DIR` env var
   - `~/.hivesmith`
   - Resolve this skill's symlink target and walk up to the repo root
   If not found, tell the user to set `HIVESMITH_DIR` or reinstall.

2. **Detect what's already present** in the current working directory:
   - `features/BACKLOG.md` (legacy layout)
   - `features/templates/FEATURE.md` (legacy layout)
   - `features/ingest.sh`
   - `docs/product-specs/index.md`
   - `docs/exec-plans/active/`, `docs/exec-plans/completed/`
   - `docs/design-docs/`, `docs/references/`, `docs/generated/`
   - `AGENTS.md`
   - `DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `FRONTEND.md`, `golden-principles.md`
   - `CONTRIBUTING.md`
   - `CHANGELOG.md`
   - `scripts/release.sh`

3. **Ask the user which pieces to scaffold.** Present a checklist:
   - [ ] Repository-as-system-of-record layout (`docs/` tree + top-level stubs) — REQUIRED for the new feature pipeline, doc-garden, and gc-sweep
   - [ ] Feature pipeline legacy directory (`features/` tree + `ingest.sh`) — only needed if migrating an existing project; new projects can skip it
   - [ ] `AGENTS.md` — if missing, scaffold the full table-of-contents skeleton; if present without a hivesmith block, offer to *append* one (see step 5a)
   - [ ] `CONTRIBUTING.md` (contributor guide skeleton)
   - [ ] `CHANGELOG.md` (Keep a Changelog seed with `[Unreleased]` section)
   - [ ] `scripts/release.sh` (generic release scaffold)
   Default-check anything not already present. For `AGENTS.md`, default-check when the file is missing OR exists without the `<!-- BEGIN HIVESMITH -->` marker. For everything else, un-check anything already present (would require `--force`).

4. **If `--force` is passed**, offer to overwrite existing files — show a diff preview before each overwrite and get confirmation.

5. **Copy selected files** from `<hivesmith>/templates/` into the project, creating directories as needed:
   - `templates/docs/` → `docs/` (creates `design-docs/`, `exec-plans/{active,completed}/`, `product-specs/`, `references/`, `generated/`; copies `index.md`, `_template.md`, `core-beliefs.md`, `tech-debt-tracker.md`, `README.md` files). Skip any individual destination file that already exists unless `--force` is passed; in that case follow step 4.
   - `templates/{DESIGN,RELIABILITY,SECURITY,QUALITY_SCORE,PRODUCT_SENSE,PLANS,FRONTEND,golden-principles}.md` → project root. Skip any that already exist (require `--force` to overwrite).
   - `templates/features/` → `features/` (legacy; only when the user keeps the box checked in step 3). Preserves `BACKLOG.md`, `templates/FEATURE.md`, and creates empty `active/`, `completed/`, `rejected/` dirs.
   - `templates/features/ingest.sh` → `features/ingest.sh` (chmod +x; legacy)
   - `templates/CONTRIBUTING.md` → `CONTRIBUTING.md`
   - `templates/CHANGELOG.md` → `CHANGELOG.md` (replace `OWNER/REPO` in compare link with the actual GitHub slug if known; otherwise leave as-is for the user to fix)
   - `templates/scripts/release.sh` → `scripts/release.sh` (chmod +x)

   **AGENTS.md is handled specially** (see step 5a).

5a. **AGENTS.md — append-create-or-refresh.** Do NOT clobber a user's hand-written content outside the hivesmith block, but DO keep the block in sync with the current template.
   - If `AGENTS.md` does NOT exist in the project: copy `templates/AGENTS.md` → `AGENTS.md` as a full skeleton.
   - If `AGENTS.md` exists and does NOT contain `<!-- BEGIN HIVESMITH -->`: **ask the user first** — show them the content of `templates/AGENTS.hivesmith.md` and confirm "Append the hivesmith instructions block to your existing AGENTS.md? [Y/n]". If they decline, skip. If they accept, append the block verbatim (with a preceding blank line if the file doesn't already end in one) so it lands as a clearly-delimited section between `<!-- BEGIN HIVESMITH -->` and `<!-- END HIVESMITH -->` markers.
   - If `AGENTS.md` exists AND already contains `<!-- BEGIN HIVESMITH -->`: **refresh the block in place.** Compare the current bracketed content (everything from `<!-- BEGIN HIVESMITH -->` through `<!-- END HIVESMITH -->`, inclusive) against the rendered `templates/AGENTS.hivesmith.md` (after applying the prefix rewrite from step 6). If they're byte-identical, skip silently. Otherwise, show a unified diff and ask "The hivesmith block in your AGENTS.md is out of date — replace it with the latest template? [Y/n]". On Y, splice the new block in (preserve everything before `<!-- BEGIN HIVESMITH -->` and everything after `<!-- END HIVESMITH -->` exactly). On n, skip and warn the user that some skills may reference docs that don't match.
   - The block is the source of truth — users should not hand-edit between the markers; if they need to, they should edit `templates/AGENTS.hivesmith.md` upstream instead. State this in the Rules section.
   - Never append a duplicate hivesmith block on re-runs.

6. **Apply the installed skill prefix to scaffolded/appended content** so documented slash-commands match what the user actually has installed:
   - Read `prefix = "..."` from `~/.hivesmith.toml` (fall back to `$HIVESMITH_DIR_CONFIG` if set). If the file is absent or has no `prefix` line, the prefix is empty and this step is a no-op.
   - When the prefix is non-empty (e.g. `hs-`), rewrite every `/skill-name` reference to `/prefix-skill-name` in:
     - the full `AGENTS.md` (if the skeleton was freshly scaffolded in step 5a), OR
     - just the hivesmith block (when step 5a appended or refreshed it) — do NOT touch the user's content outside the `<!-- BEGIN HIVESMITH -->` / `<!-- END HIVESMITH -->` markers. The diff comparison in step 5a must run **after** this prefix rewrite so it doesn't false-positive on prefix differences.
     - the scaffolded `CONTRIBUTING.md`.
   - Known skill names: `feature-triage feature-ingest feature-research feature-plan feature-implement feature-new feature-next feature-loop changelog-update release review-pr autofix ralph-loop doc-garden gc-sweep hivesmith-init namecheck`.
   - Use the same careful match as the installer: only rewrite `/<skill>` when preceded by start-of-line or a non-path character (whitespace, backtick, paren, bracket) and followed by end-of-line or a non-identifier character. Never rewrite `scripts/release.sh` (it's a path, not a slash-command).
   - Do NOT rewrite `CHANGELOG.md`, `features/**`, or `scripts/release.sh` — they don't reference slash-commands.

7. **Initialize the hive brain (cross-project, lazy)** by sourcing the brain lib and calling `brain_lazy_init`:
   ```
   if [ -f "$HIVESMITH_DIR/scripts/brain/lib.sh" ]; then
       (. "$HIVESMITH_DIR/scripts/brain/lib.sh" && brain_lazy_init)
   fi
   ```
   This creates `~/.hivesmith/brain/` (a git repo), seeded from `templates/brain/`. It's idempotent — safe to call on re-runs and existing brains.

8. **Suggest installing graphify** if the user hasn't already. Brain entries can `[[wikilink]]` graphify nodes for code-structure context, and brain references stay rot-free when graphify auto-updates the per-project graph. Print:
   ```
   Tip: install graphify alongside hivesmith for per-project code-structure memory.
        Brain entries can reference graphify nodes via [[wikilinks]]; the gardener
        validates these references on each run.
        See: https://github.com/lucascaro/graphify
   ```
   (Print only the text — do not run an install command without confirmation.)

9. **Report what was created.** List each file with its size. Tell the user:
   - Edit `AGENTS.md` to fill in project-specific module map, build/test commands, and conventions — many other skills read it.
   - Edit `golden-principles.md` to define the rules `/gc-sweep` will enforce. Keep it short (5–10 principles).
   - Edit `DESIGN.md` to document domains, layers, and cross-cutting concerns.
   - Edit `scripts/release.sh` to set `PROJECT`, `REPO`, and `BUILD_CMD` at the top.
   - The hive brain at `~/.hivesmith/brain/` will accumulate cross-project lessons. Use `/hs-brain-promote` to broaden a project lesson, `/hs-brain-garden` to tidy.
   - Run `/feature-next` to verify the pipeline is wired up.

10. **Migration mode (`--migrate`).** If invoked with `--migrate`, AND `features/active/` or `features/completed/` exists with at least one `*.md` file:
   - For each existing feature file `features/<state>/<NNN>-<slug>.md`:
     - Parse out the front-matter, Description, and Triage sections → write to `docs/product-specs/<NNN>-<slug>.md` using the product-spec template shape (preserving Type, Complexity, Priority, and the Description as the Problem section).
     - Take the Research, Plan, Implement (decision log + progress) sections → write to `docs/exec-plans/active/<NNN>-<slug>.md` if state is `active`, or `docs/exec-plans/completed/<NNN>-<slug>.md` if state is `completed`. Use the exec-plan template shape; preserve the Decision log and Progress sections verbatim (append-only history).
     - Cross-link: spec links to plan, plan links to spec.
   - Append a row to `docs/product-specs/index.md` for each migrated spec.
   - Do NOT delete the original `features/<state>/*.md` files — leave them in place. Print a final note: "Legacy `features/` directory left untouched as fallback. Delete it once you've verified the migration."
   - If `--migrate` is invoked but no legacy files are found, report nothing to migrate and stop.

## Rules
- Never overwrite without `--force` + per-file user confirmation
- Never modify a user's existing `AGENTS.md` without an explicit yes to the append prompt in step 5a
- The hivesmith block in `AGENTS.md` is always bracketed by `<!-- BEGIN HIVESMITH -->` / `<!-- END HIVESMITH -->` so it can be identified, updated, or removed cleanly
- The bracketed block is **owned by init** — users should not hand-edit between the markers, since re-running init will offer to overwrite drift. To change what lives there, edit `templates/AGENTS.hivesmith.md` upstream and re-run init
- Preserve any existing content in directories being created (e.g. don't wipe a user's `features/active/` if it's already populated, don't wipe a user's `docs/design-docs/` if it has files)
- Create `features/active/`, `features/completed/`, `features/rejected/` as empty dirs with `.gitkeep` if none exist (legacy)
- Create `docs/exec-plans/active/`, `docs/exec-plans/completed/`, `docs/references/`, `docs/generated/` as empty dirs with `.gitkeep` if none exist
- `--migrate` is a one-shot operation — it only writes to `docs/`, never deletes from `features/`
