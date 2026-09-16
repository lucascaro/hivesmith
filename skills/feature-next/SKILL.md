---
name: feature-next
description: Show feature pipeline status and recommend the next action
disable-model-invocation: true
allowed-tools: Read Glob Grep Bash AskUserQuestion
---

# Feature Pipeline Status

Show the current state of the feature pipeline and recommend the next action.

<!-- BEGIN hivesmith upgrade-check (generated from scripts/upgrade/preamble.md; edit there, then run scripts/upgrade/sync-preamble.sh) -->
## Before you start: upgrade check

Do this before anything else in this skill, then carry on with the rest of it.

**Skip this section entirely** — go straight to the skill's own work and say nothing about it — when any of these hold:

- You cannot ask the operator a question and wait for the answer: non-interactive or print mode, a CI run, no live operator.
- This skill was invoked by another skill or by a subagent, or reached through a chained handoff in the same session (for example brainstorm handing off to feature-new, then feature-loop). The operator is asked at most once per chain.
- The run is unattended: scheduled, looped, or started by cron.
- `~/.hivesmith/bin/hs-upgrade-check` does not exist.

Otherwise run:

```bash
~/.hivesmith/bin/hs-upgrade-check
```

It returns immediately: it answers from cached state and refreshes that state in the background. If it prints nothing, continue silently.

If it prints `BEHIND <n> <sha> <dir>`, ask the operator one question — with AskUserQuestion where the harness has it — "hivesmith (`<dir>`) is `<n>` commits behind upstream. Upgrade now?", offering exactly these options, then run the matching command:

| Option | Command |
|---|---|
| Upgrade now | `~/.hivesmith/bin/hs-upgrade-check upgrade` |
| Ask me later (tomorrow) | `~/.hivesmith/bin/hs-upgrade-check snooze-day` |
| Not until the next upstream change | `~/.hivesmith/bin/hs-upgrade-check snooze-until-change <sha>` |
| Never ask again (re-enable: `install.sh --upgrade-check`) | `~/.hivesmith/bin/hs-upgrade-check never` |

After **Upgrade now**, stop this skill whatever the result:

- **Success:** relay the reload message it prints. The instructions you loaded are now older than the code on disk, so the operator reloads or restarts the session and invokes this skill again.
- **Failure:** show its output, and tell the operator to fix the problem, reload, and invoke this skill again — the pull may have landed before a later step failed.

After any other option, continue with this skill.
<!-- END hivesmith upgrade-check -->

## Steps

1. **Locate the source of truth**, in this order:
   - `docs/product-specs/<NNN>-*.md` files with YAML frontmatter (current layout). The frontmatter `stage:` field is canonical; **do not** read from the generated `docs/product-specs/index.md` (it's a regenerated view, not a source).
   - `features/BACKLOG.md` (legacy fallback — one release only)
   If neither exists, suggest the user run `/hivesmith-init` first.
2. **Current layout:** scan each `docs/product-specs/<NNN>-*.md`, parse YAML frontmatter, collect `issue`, `title`, `stage`, `complexity`, `priority`, `pr`, `shipped`. Active items are those with `stage` in {TRIAGE, RESEARCH, PLAN, IMPLEMENT, REVIEW, GATE}. **Legacy layout:** read the BACKLOG row for each active feature, then read its exec plan for the current stage.
3. For each active item, optionally read its exec plan (`docs/exec-plans/active/<NNN>-<slug>.md`) to surface the PR field for REVIEW-stage items.
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
6. Recommend the next action based on priority. Stages later in the pipeline take precedence — work in flight clears first:
   - If there are GATE-stage items → "Run `/merge-gate <number>` to validate the open PR before merging"
   - If there are REVIEW-stage items → "Run `/review-loop <pr-number>` to drive PR convergence (or `/feature-loop <number>` to resume from REVIEW with merge gate)"
   - If there are IMPLEMENT-stage items → "Run `/feature-implement <number>` to implement"
   - If there are PLAN-stage items → "Run `/feature-plan <number>` to create implementation plan"
   - If there are RESEARCH-stage items → "Run `/feature-research <number>` to research"
   - If there are TRIAGE-stage items → "Run `/feature-triage <number>` to triage"
   - If there are un-ingested issues → "Run `/feature-ingest <number>` to ingest"
   - Otherwise → "Pipeline is clear. Run `/brainstorm` to develop the next idea, or `/feature-new` if you already know what to build."

   For REVIEW-stage items, also surface the PR number (from the plan header's `PR:` field) so the user can act on it directly.

## Rules
- Always show the full table, even if empty
- List un-ingested issues separately below the table
- Recommend only ONE next action (the highest-priority, most-advanced stage)
- Prefer the current layout (`docs/`) over the legacy layout (`features/`); only fall back to legacy when `docs/product-specs/` does not exist or no spec files are present. The current-layout SoR is each spec's YAML frontmatter, not the generated `index.md`.
- If both layouts have entries, only the current layout is authoritative — note this in the output and suggest `/hivesmith-init --migrate`
