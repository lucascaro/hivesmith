---
name: feature-implement
description: Implement a planned feature — code, test, open PR
disable-model-invocation: true
argument-hint: [issue-number]
---

# Implement Feature

Implement feature **#$ARGUMENTS** (or the next feature in IMPLEMENT stage if no argument given).

## Steps

1. **Find the feature:** If `$ARGUMENTS` is provided, find the matching file in `features/active/`. If not, read `features/BACKLOG.md` and pick the first feature with Stage = IMPLEMENT.
2. **Read the feature file** — verify the Plan section is filled and actionable. If not, tell the user to run `/feature-plan` first.
3. **Read `AGENTS.md`** for project conventions — build commands, test commands, lint commands, documentation rules. All build/test invocations below come from there, not from assumptions.
4. **Create a feature branch:** `git checkout -b feature/<issue-number>-<slug>`
5. **Implement the plan:**
   - Follow the steps in the Plan section
   - Follow all conventions in `AGENTS.md`
   - If the change is user-visible, run `/changelog-update` to add an `[Unreleased]` entry in `CHANGELOG.md`
   - Update any relevant docs (README, docs/, etc.) if the feature adds user-visible behavior
6. **Run checks** as defined in `AGENTS.md` (typically build + lint + test). All must pass before committing.
7. **Fill in Implementation Notes** in the feature file:
   - Any deviations from the plan and why
   - Decisions made during coding
8. **Commit** the implementation with a descriptive message referencing `Fixes #<issue-number>`. Do not touch `features/BACKLOG.md` or move the feature file yet.
9. **Offer to open a PR:** Ask the user if they want to push and create a PR. If yes:
    - `git push -u origin <branch>`
    - Create PR with `gh pr create` referencing the issue — capture the PR number from the output
    - Update GitHub labels: `gh issue edit <number> --remove-label planned --add-label implementing`
10. **Update the backlog** (only if a PR was opened):
    - Fill in the PR link in the feature file's Implementation Notes
    - Set Stage to `DONE` in the feature file
    - Move the feature file from `features/active/` to `features/completed/`
    - Update `features/BACKLOG.md`: remove the feature row from the Active table, renumber remaining rows sequentially, and add it to the Completed table with the real PR number and today's date as the merge-date placeholder
    - Commit these changes: `git commit -m "chore: mark #<issue-number> complete, update backlog"`
    - Push: `git push`

    If the user declined to open a PR, skip this step — leave the feature file at IMPLEMENT stage and BACKLOG unchanged.

## Already-Merged Detection

Before starting implementation, check if the feature already has a PR link in its file. If it does, check if that PR is merged (`gh pr view <number> --json state`). If merged, run step 10 (backlog update) on the current branch (main) and skip the rest.

## Rules
- Do not skip tests — all checks defined in `AGENTS.md` must pass before committing
- Follow `AGENTS.md` conventions exactly
- Ask before pushing or creating PRs
- One feature at a time — finish this before starting the next
