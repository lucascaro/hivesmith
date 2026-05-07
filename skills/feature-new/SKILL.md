---
name: feature-new
description: Create a GitHub issue and run it through ingest + triage
disable-model-invocation: true
argument-hint: "[description]"
allowed-tools: Read Glob Grep Edit Write Bash
---

# Create New Feature

Create a new GitHub issue from a description and run it through the feature pipeline (ingest + triage).

If `$ARGUMENTS` is provided, use it as the feature description. Otherwise, ask the user what feature they want.

## Steps

### Phase 1: Draft the issue

1. Based on the description in `$ARGUMENTS`, draft a GitHub issue:
   - **Title:** concise, imperative (e.g. "Add dark mode toggle")
   - **Body:** a `## Description` section explaining the problem and desired behavior (2-4 sentences)
2. Present the proposed title and body to the user. Wait for confirmation or edits before proceeding.

### Phase 2: Create the issue on GitHub

3. Run `gh issue create --title "..." --body "..."` and capture the new issue number from the output.

### Phase 3: Ingest into feature pipeline

**Layout resolution** — prefer the current layout, fall back to legacy for one release:
- **Current:** spec at `docs/product-specs/<NNN>-<slug>.md`, index at `docs/product-specs/index.md`, template at `docs/product-specs/_template.md`.
- **Legacy fallback:** file at `features/active/<NNN>-<slug>.md`, index at `features/BACKLOG.md`, template at `features/templates/FEATURE.md`. Only when `docs/product-specs/` does not exist.

4. Run `gh issue view <number> --json number,title,body,labels` to fetch the issue.
5. Check for duplicates by zero-padded prefix:
   - Current: any `<NNN>-*.md` in `docs/product-specs/` or `docs/exec-plans/{active,completed}/`.
   - Legacy: any `<NNN>-*.md` in `features/active/` or `features/completed/`.
   If found, warn and stop.
6. Generate filename: zero-pad the issue number to 3 digits, slugify the title (lowercase, hyphens, max 50 chars). Example: `069-add-dark-mode-toggle.md`.
7. Read the spec template (current: `docs/product-specs/_template.md`; legacy: `features/templates/FEATURE.md`).
8. **Current layout:** Create the spec at `docs/product-specs/<filename>` filling in title, issue number, Problem section from the issue body. Type/Complexity/Priority left blank for triage. Append a row to the Active table in `docs/product-specs/index.md`:
   `| — | #<number> | <title> | TRIAGE | [<NNN>-<slug>](<NNN>-<slug>.md) |`
   **Legacy layout:** Create the feature file at `features/active/<filename>` and append to `features/BACKLOG.md` Active table.

### Phase 4: Triage

10. **Classify** the feature:
    - Type: `bug` or `enhancement`
    - Complexity: `S` (< 1 day, few files), `M` (1-3 days, moderate scope), `L` (3+ days, significant changes)
11. **Quick codebase scan:** Do a brief Glob/Grep search related to the feature to inform the complexity estimate. Don't do deep research — that's the RESEARCH stage.
12. **Recommend priority:** Based on impact and complexity, suggest where this should sit in the backlog (P1 = top, higher number = lower priority). Consider existing items in the index when choosing.
13. **Present findings to user:** Show type, complexity, and priority recommendation. Wait for confirmation or adjustment.
14. **Update the spec file** (current) or feature file (legacy):
    - Set Type, Complexity, Priority fields.
15. **Update the index** (`docs/product-specs/index.md` or legacy `features/BACKLOG.md`):
    - Set the priority number and complexity in the Active table row.
    - Reorder rows by priority (P1 at top).
    - Update Stage to RESEARCH.
16. **Update GitHub label:** `gh issue edit <number> --add-label triaged`.

### Phase 5: Report

17. Summarize what was created:
    - GitHub issue number and URL.
    - Spec / feature file path.
    - Type, complexity, priority.
    - Current stage (RESEARCH).
18. Remind user to run `/feature-research <number>` next.

## Rules
- Always show the proposed issue contents and get user confirmation before creating on GitHub.
- Always show triage classification and get user confirmation before writing changes.
- Single feature at a time.
- Follow existing filename conventions (3-digit zero-pad, slugified title, max 50 chars).
- If no argument is provided, ask the user to describe the feature before proceeding.
- If neither `docs/product-specs/` nor `features/` exist, tell the user to run `/hivesmith-init` first.
