---
name: feature-next
description: Show feature pipeline status and recommend the next action
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash
---

# Feature Pipeline Status

Show the current state of the feature pipeline and recommend the next action.

## Steps

1. **Locate the source of truth**, in this order:
   - `docs/product-specs/index.md` (current layout)
   - `features/BACKLOG.md` (legacy fallback — one release only)
   If neither exists, suggest the user run `/hivesmith-init` first.
2. Read the index/backlog to get all active items.
3. For each active item, read its exec plan to get the current stage:
   - Current layout: `docs/exec-plans/active/<NNN>-<slug>.md`
   - Legacy fallback: `features/active/<NNN>-<slug>.md`
4. Display a summary table:

```
Feature Pipeline Status
=======================
#  | Issue | Title                  | Stage    | Complexity
---|-------|------------------------|----------|----------
1  | #16   | Stale preview on exit  | RESEARCH | M
2  | #13   | Fix mouse support      | TRIAGE   | —
```

5. Check for un-ingested GitHub issues: run `gh issue list --state open --json number,title` and compare against existing spec/plan files (current layout: `docs/product-specs/`, `docs/exec-plans/{active,completed}/`; legacy: `features/active/` and `features/completed/`).
6. Recommend the next action based on priority:
   - If there are IMPLEMENT-stage items → "Run `/feature-implement <number>` to implement"
   - If there are PLAN-stage items → "Run `/feature-plan <number>` to create implementation plan"
   - If there are RESEARCH-stage items → "Run `/feature-research <number>` to research"
   - If there are TRIAGE-stage items → "Run `/feature-triage <number>` to triage"
   - If there are un-ingested issues → "Run `/feature-ingest <number>` to ingest"
   - Otherwise → "Pipeline is clear. No pending work."

## Rules
- Always show the full table, even if empty
- List un-ingested issues separately below the table
- Recommend only ONE next action (the highest-priority, most-advanced stage)
- Prefer the current layout (`docs/`) over the legacy layout (`features/`); only fall back when `docs/product-specs/index.md` does not exist
- If both layouts have entries, only the current layout is authoritative — note this in the output and suggest `/hivesmith-init --migrate`
