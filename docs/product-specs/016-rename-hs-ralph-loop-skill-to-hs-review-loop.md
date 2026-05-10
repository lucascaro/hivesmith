# Rename hs-ralph-loop skill to hs-review-loop

- **Issue:** #16
- **Type:** enhancement
- **Complexity:** S
- **Priority:** P2
- **Exec plan:** [docs/exec-plans/active/016-rename-hs-ralph-loop-skill-to-hs-review-loop.md](../exec-plans/active/016-rename-hs-ralph-loop-skill-to-hs-review-loop.md)

## Problem

The `hs-ralph-loop` skill drives a PR through review → autofix → re-review until findings clear or escalation criteria hit. The "ralph-loop" name is internal jargon that doesn't communicate what the skill does. New users and agents reading the skill list can't tell what it's for from the name alone, and the inconsistency with sibling skills (`hs-review-pr`, `hs-autofix`, `hs-feedback-loop`) adds friction.

## Desired behavior

The skill is named `hs-review-loop` everywhere — directory name, SKILL.md frontmatter, and every reference across other skills, templates, docs, and changelog. Invoking `/hs-review-loop` works; invoking the old name does not. Documentation (README, AGENTS.md templates, product-specs index, exec-plan templates, related skills) consistently uses the new name.

## Success criteria

- `skills/ralph-loop/` no longer exists; `skills/review-loop/` exists with identical content modulo name fields.
- `grep -rn "ralph-loop\|ralph_loop\|hs-ralph"` across the repo returns no hits (except possibly historical CHANGELOG entries describing the rename itself).
- Sibling skills (`feature-implement`, `feature-qa`, `feature-loop`, `feature-next`, `feature-plan`, `feature-triage`, `autofix`, `feedback-loop`) reference `/hs-review-loop` instead of `/hs-ralph-loop`.
- `templates/AGENTS.hivesmith.md`, `templates/AGENTS.md`, AGENTS.md, README.md, and `docs/product-specs/index.md` all use the new name.
- CHANGELOG.md has an `[Unreleased]` entry documenting the rename.

## Non-goals

- Changing the skill's behavior or scope.
- Renaming other skills (e.g. `feedback-loop`, `feature-loop`).
- Backwards-compatible alias for the old name.

## Notes

Affected files identified during triage:
CHANGELOG.md, README.md, AGENTS.md, docs/exec-plans/_template.md, docs/exec-plans/active/011-*.md, docs/product-specs/index.md, templates/AGENTS.hivesmith.md, templates/AGENTS.md, templates/features/templates/FEATURE.md, skills/{feature-implement,autofix,feature-qa,feature-loop,feature-next,feedback-loop,feature-plan,ralph-loop,feature-triage}/SKILL.md.
