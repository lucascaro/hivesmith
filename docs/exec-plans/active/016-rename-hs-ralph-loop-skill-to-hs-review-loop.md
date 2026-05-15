# Rename hs-ralph-loop skill to hs-review-loop

- **Spec:** [docs/product-specs/016-rename-hs-ralph-loop-skill-to-hs-review-loop.md](../../product-specs/016-rename-hs-ralph-loop-skill-to-hs-review-loop.md)
- **Issue:** #16
- **Status:** active
- **PR:** [#18](https://github.com/lucascaro/hivesmith/pull/18)
- **Branch:** feature/16-rename-ralph-loop-to-review-loop

## Summary

Rename the `ralph-loop` skill to `review-loop` so its purpose is legible from the name. Skill behavior is unchanged; this is a directory rename plus a coordinated find/replace across docs, templates, sibling skills, and the changelog. The on-disk skill name changes from `skills/ralph-loop/` to `skills/review-loop/`; with the standard `hs-` prefix from `install.sh`, the slash-command becomes `/hs-review-loop`.

## Research

### How the prefix works

`install.sh` symlinks each `skills/<name>/` into agent skill dirs and rewrites cross-skill references to use the configured prefix (default `hs-`) when rendering. There is no hardcoded list of skill names — the rendered output for skill X picks up `/hs-X` automatically. Verified: `grep -n "ralph"` in `install.sh`, `scripts/`, `.github/workflows/`, and `skills/hivesmith-init/SKILL.md` returns nothing. So the rename is purely:

1. `git mv skills/ralph-loop skills/review-loop`
2. Update `name:` in the moved SKILL.md frontmatter.
3. Update every prose reference to `ralph-loop` / `/ralph-loop` / `hs-ralph-loop` everywhere else.

### Files that reference the old name (verified by grep)

**Skill being renamed (self-references inside file):**
- `skills/ralph-loop/SKILL.md` — frontmatter `name: ralph-loop` (line 2); H1 `# Ralph Wiggum Loop` (line 8); body refers to "ralph-loop harness" (line 53), `/tmp/ralph-pr-$PR.json` temp filename (line 38), `HIVESMITH_SKILL=hs-ralph-loop` brain-append env var (line 126).

**Sibling skills (slash-command references):**
- `skills/feature-implement/SKILL.md` — lines 3, 19, 60, 61, 71 (description, refusal pointer, "drive PR convergence" step, ralph-loop APPROVE handling, rule).
- `skills/feature-loop/SKILL.md` — lines 13, 150, 164, 165, 196 (lifecycle prose, Gate 5 option text, Phase 6 invocation, Gate 6 trigger, rules).
- `skills/feature-plan/SKILL.md` — line 19 (refusal pointer for REVIEW stage).
- `skills/feature-triage/SKILL.md` — line 21 (refusal pointer for REVIEW stage).
- `skills/feature-next/SKILL.md` — line 36 (next-step suggestion).
- `skills/feature-qa/SKILL.md` — lines 13, 17, 26 (ownership note, "last chance" prose, OPEN-PR refusal text).
- `skills/autofix/SKILL.md` — lines 208, 213 (autofix output mentions ralph-loop convergence; load-bearing `Threads:` line annotation).
- `skills/feedback-loop/SKILL.md` — line 133 (mentions ralph-loop in a parenthetical about pipeline collisions).

**Project-root docs:**
- `AGENTS.md` — lines 12, 14, 16, 28, 30 (Hivesmith block; the block is rewritten by `/hs-hivesmith-init` from `templates/AGENTS.hivesmith.md`, so source-of-truth is the template — but our own AGENTS.md is also a rendered copy and must stay in sync).
- `README.md` — lines 15, 17, 25, 36, 44, 55, 56 (feature list, skill table).
- `CHANGELOG.md` — lines 9, 12, 13, 16, 22, 24, 26, 27 (multiple historical entries). **These are historical: do NOT rewrite them.** Add a new `[Unreleased]` entry documenting the rename.

**Templates (consumed by `/hs-hivesmith-init`):**
- `templates/AGENTS.hivesmith.md` — lines 6, 8, 10, 21, 23 (the canonical Hivesmith AGENTS block).
- `templates/AGENTS.md` — lines 49, 50.
- `templates/features/templates/FEATURE.md` — line 44 (legacy feature template).

**Plan / spec scaffolding:**
- `docs/exec-plans/_template.md` — line 53 (PR convergence ledger header).
- `docs/product-specs/index.md` — line 27 (lifecycle conventions footer).
- `docs/exec-plans/active/011-add-hive-brain-second-brain-for-hivesmith.md` — lines 29, 30, 191, 216, 362, 365, 373, 442. **Historical execution log; do NOT rewrite.**
- `docs/product-specs/016-…` and `docs/exec-plans/active/016-…` (this rename's own files) — references are intentional.

**External-reference doc (do NOT change):**
- `references/openai-harness-engineering.md:26` — quotes the original "Ralph Wiggum Loop" name from OpenAI's post. This is a citation of external content; preserve verbatim.

### Constraints / dependencies

- **CI changelog gate:** AGENTS.md line 51 requires `[Unreleased]` to be non-empty. Adding the rename entry satisfies this.
- **Brain append env var:** `skills/ralph-loop/SKILL.md:126` uses `HIVESMITH_SKILL=hs-ralph-loop` when appending to the hive brain. This needs to become `hs-review-loop`. The brain index is downstream and will accumulate the new tag from this PR onward; old entries with `hs-ralph-loop` stay as historical record (no need to migrate).
- **Re-rendered AGENTS.md:** Commit 8719dce added re-render-on-rerun to `hivesmith-init`. The next `/hs-hivesmith-init` invocation in this repo will refresh `AGENTS.md` from `templates/AGENTS.hivesmith.md`. Keep the two in sync so re-rendering is a no-op.
- **`graphify-out/`:** AGENTS.md line 5 says to run `graphify . --update` after significant file changes. We should run it post-implementation if the tool is available.

### Naming check on review-loop / hs-review-loop

- `skills/review-pr/` exists (different skill — deep PR review). `review-loop` is a distinct, non-conflicting name.
- `skills/feedback-loop/`, `skills/feature-loop/` exist — `review-loop` fits the `*-loop` pattern.
- No directory or skill named `review-loop` anywhere in the repo (verified).

### Things specifically NOT in scope

- The "Ralph Wiggum Loop" reference in `references/openai-harness-engineering.md` is an external citation and stays.
- Historical CHANGELOG and `docs/exec-plans/active/011-*.md` entries are append-only history and stay.
- No backwards-compat alias / shim for the old slash-command — spec non-goals call this out.

## Approach

A coordinated rename in five steps. The mechanic is mostly `git mv` + targeted `sed`-style edits in a known set of files. Order matters only at the boundary between the directory rename and edits inside the moved file — do the `git mv` first so the moved SKILL.md is at its new path before further edits.

Chosen over the alternative ("leave a stub `ralph-loop/` symlink for back-compat") because the spec explicitly rules out a back-compat alias, and the prefix system means there is no on-disk slash-command file to clean up — the rename is purely conceptual once render runs.

### Files to change

**1. Rename the skill directory.**
- `git mv skills/ralph-loop skills/review-loop`.

**2. Edit `skills/review-loop/SKILL.md` (the moved file).**
- Frontmatter: `name: ralph-loop` → `name: review-loop` (line 2).
- Frontmatter description: keep as is — it already describes behavior, not the name.
- H1: `# Ralph Wiggum Loop` → `# Review Loop` (line 8). Add a one-line note under the H1: "Originally called the *Ralph Wiggum Loop* after OpenAI's 'Harness engineering' post (`docs/references/openai-harness-engineering.md`)." to preserve attribution without keeping the jargon in the name.
- Body prose: `ralph-loop harness` → `review-loop harness` (line 53).
- Temp filename: `/tmp/ralph-pr-$PR.json` → `/tmp/review-loop-pr-$PR.json` (line 38). Reason: keeps the temp file self-identifying.
- Brain env var: `HIVESMITH_SKILL=hs-ralph-loop` → `HIVESMITH_SKILL=hs-review-loop` (line 126).
- Any other self-reference inside this file: replace `ralph-loop` → `review-loop` and `/ralph-loop` → `/review-loop`.

**3. Edit sibling skills — replace `/ralph-loop` → `/review-loop` and `ralph-loop` → `review-loop` (prose only, no shell-script content):**
- `skills/feature-implement/SKILL.md` (lines 3, 19, 60, 61, 71).
- `skills/feature-loop/SKILL.md` (lines 13, 150, 164, 165, 196).
- `skills/feature-plan/SKILL.md` (line 19).
- `skills/feature-triage/SKILL.md` (line 21).
- `skills/feature-next/SKILL.md` (line 36).
- `skills/feature-qa/SKILL.md` (lines 13, 17, 26).
- `skills/autofix/SKILL.md` (lines 208, 213).
- `skills/feedback-loop/SKILL.md` (line 133).

**4. Edit root docs (live, not historical):**
- `AGENTS.md` lines 12, 14, 16, 28, 30 — replace `ralph-loop` / `/ralph-loop`.
- `README.md` lines 15, 17, 25, 36, 44, 55, 56 — replace `ralph-loop` / `/ralph-loop`.
- `CHANGELOG.md` — add a new `[Unreleased]` bullet via `/hs-changelog-update`. Do NOT edit lines 9, 12, 13, 16, 22, 24, 26, 27 (historical release entries).

**5. Edit templates:**
- `templates/AGENTS.hivesmith.md` lines 6, 8, 10, 21, 23 — replace `ralph-loop` / `/ralph-loop`. Must mirror the same edits applied to `AGENTS.md` so re-running `/hs-hivesmith-init` is a no-op.
- `templates/AGENTS.md` lines 49, 50.
- `templates/features/templates/FEATURE.md` line 44.

**6. Edit plan/spec scaffolding:**
- `docs/exec-plans/_template.md` line 53 — replace `/ralph-loop` → `/review-loop`.
- `docs/product-specs/index.md` line 27 — replace `/ralph-loop` → `/review-loop`.
- Do NOT edit `docs/exec-plans/active/011-add-hive-brain-second-brain-for-hivesmith.md` (historical execution log of a different feature).
- Do NOT edit `references/openai-harness-engineering.md` (external citation).

**7. Self-references in this exec plan / spec.**
- After implementation, the strings `ralph-loop` and `hs-ralph-loop` in `docs/product-specs/016-...md` and `docs/exec-plans/active/016-...md` are intentional (they describe the rename). Leave them.

### New files

None.

### Tests

This is a documentation/rename change with no code logic. Validation is mechanical:

1. **Grep allowlist check** — after edits, run:
   ```
   grep -rn "ralph-loop\|hs-ralph\|ralph_loop" --include="*.md" --include="*.sh" --include="*.json" --include="*.yml" .
   ```
   Allowed hits:
   - `CHANGELOG.md` historical release entries (pre-Unreleased section).
   - `docs/exec-plans/active/011-add-hive-brain-second-brain-for-hivesmith.md`.
   - `references/openai-harness-engineering.md` (the "Ralph Wiggum Loop" citation).
   - `docs/product-specs/016-...md` and `docs/exec-plans/active/016-...md` (this rename's own paper trail).
   - The new `[Unreleased]` CHANGELOG entry (it must name the old skill to describe the rename).
   Any other hit is a miss; fix and re-run.

2. **Render correctness** (from AGENTS.md line 49 pattern, adapted):
   ```
   HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update
   test -f .rendered/hs-/skills/hs-review-loop/SKILL.md
   ! test -e .rendered/hs-/skills/hs-ralph-loop
   grep -q '/hs-review-loop' .rendered/hs-/skills/hs-feature-implement/SKILL.md
   ! grep -q '/hs-ralph-loop\b' .rendered/hs-/skills/hs-feature-implement/SKILL.md
   ```

3. **Install smoke** (from AGENTS.md line 48):
   ```
   HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run
   ./install.sh --prefix "" --no-auto-update --dry-run
   ```

4. **Shellcheck** (from AGENTS.md line 46) — unchanged set of shell scripts; should pass without modification but run to confirm no incidental breakage.

5. **Brain test suite** (from AGENTS.md line 47): `scripts/brain/test/run-all.sh` — unchanged; run to confirm.

6. **Changelog non-empty** (from AGENTS.md line 51): `awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .` — satisfied by adding the rename entry.

7. **`review-pr` regression suite:** not run; `skills/review-pr/` is not modified.

8. **graphify sync** (AGENTS.md line 5): `graphify . --update` after edits, if the tool is available locally. Not gating.

## Decision log

- **2026-05-10** — Treat references/ citation and historical CHANGELOG/exec-plan entries as immutable. Why: they are historical record, not live config; rewriting them rewrites history.
- **2026-05-10** — Rename the H1 "Ralph Wiggum Loop" inside the skill itself; the new name is descriptive and the citation lives in references/. Why: keeping a "Ralph Wiggum Loop" H1 inside a file named `review-loop/SKILL.md` is precisely the inconsistency this rename is meant to remove.
- **2026-05-10** — Updated pre-existing `[Unreleased]` CHANGELOG entries that mentioned `ralph-loop` (in addition to adding a new rename bullet). Why: `[Unreleased]` is mutable until cut; the next release shouldn't ship history entries referencing a skill name that no longer exists. Versioned (already-released) sections were left untouched. Verified zero `ralph` hits in sections at or after `## [0.3.0]`.

## Progress

- **2026-05-10** — Spec + exec plan created; research complete; 18 files cataloged.
- **2026-05-10** — Implementation complete. `git mv skills/ralph-loop skills/review-loop`; SKILL.md updated (name, H1 with attribution, temp filename, brain env var, prose self-refs); 8 sibling skills + 3 root docs + 3 templates + 2 scaffolding files sed-rewritten; `[Unreleased]` CHANGELOG entry added under Changed; pre-existing `[Unreleased]` `ralph-loop` mentions also updated. All checks pass: grep allowlist clean (only paper-trail/historical/index-row hits), install dry-run OK, render correctness OK (`.rendered/hs-/skills/hs-review-loop/SKILL.md` exists, `hs-ralph-loop` not rendered, `feature-implement` references `/hs-review-loop` only), shellcheck clean, brain tests 13/13.

## Open questions

- None at RESEARCH gate.

## PR convergence ledger

- **2026-05-10 iter 1** — verdict: REQUEST_CHANGES; findings_hash: 1b73c0e2a0c8c1f8f2b5d1f0a6e8b9d5c4a7e1d4f6c9b2e5a8d1c4f7b0e3a6d9; threads_open: 0; action: autofix+push; head_sha: 8a0ac90.
- **2026-05-10 iter 2** — verdict: APPROVE; findings_hash: (empty); threads_open: 0; action: stop; head_sha: 5e06acb.

## QA verdict

(populated by `/hs-feature-qa` post-merge.)
