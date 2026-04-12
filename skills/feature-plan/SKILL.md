---
name: feature-plan
description: Create implementation plan for a researched feature
disable-model-invocation: true
argument-hint: [issue-number]
allowed-tools: Read Glob Grep Edit Bash Agent
---

# Plan Feature Implementation

Create an implementation plan for feature **#$ARGUMENTS** (or the next feature in PLAN stage if no argument given).

## Steps

1. **Find the feature:** If `$ARGUMENTS` is provided, find the matching file in `features/active/`. If not, read `features/BACKLOG.md` and pick the first feature with Stage = PLAN.
2. **Read the feature file** — verify the Research section is filled in. If not, tell the user to run `/feature-research` first.
3. **Read `AGENTS.md`** for project conventions — especially the Testing and Documentation Maintenance sections. The plan MUST conform to the test strategy documented there.
4. **Read referenced files:** Open the relevant code files identified during research to understand the current implementation.
5. **For complex features (M/L):** Use Plan agents to design the approach, considering trade-offs.
6. **Write the Plan section** in the feature file:
   - **Files to Change:** Numbered list with file paths and what to change in each
   - **Test Strategy:** Concrete, named test functions for every behavioral change — unit tests and integration/functional tests per the conventions in `AGENTS.md`. List each test with its file path, function name, and what it verifies. Follow existing patterns in the project. Do not leave this section vague.
   - **Risks:** What could go wrong, edge cases to watch for
7. **Present the plan to the user.** Walk through the key decisions and ask for approval before advancing.
8. **On approval:**
   - Update Stage to IMPLEMENT in the feature file
   - Update Stage to IMPLEMENT in `features/BACKLOG.md`
   - Update GitHub labels: `gh issue edit <number> --remove-label researching --add-label planned`
9. **Report:** Confirm plan is locked in, remind user to run `/feature-implement <number>` next

## Rules
- The plan must be specific enough that someone (human or AI) could implement it without re-reading the research
- Include file paths for every file that will be changed
- **Tests are mandatory.** If `AGENTS.md` specifies test requirements (unit, functional, integration), the Test Strategy must list concrete test function names that satisfy them, not vague descriptions.
- **Keep the codebase clean.** Reuse existing functions, patterns, and helpers — do not duplicate logic. If a new abstraction is needed, check whether an existing one can be extended. Prefer small, focused changes over sprawling ones. Flag any dead code or unused imports the plan would introduce.
- Always get user approval before advancing to IMPLEMENT
- Follow the project's existing patterns — check `AGENTS.md` for conventions
