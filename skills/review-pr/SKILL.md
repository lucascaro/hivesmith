---
name: review-pr
description: Deep PR review — correctness, safety, performance, UX, consistency
argument-hint: [pr-number]
allowed-tools: Read Glob Grep Bash Agent
---

# Review Pull Request

Perform a thorough review of PR **#$ARGUMENTS**.

## Setup

1. Read `AGENTS.md` (if present) to internalize project conventions, module map, key types, and data flows. Use it to calibrate every finding — "follows conventions" and "violates conventions" are the two most load-bearing judgments in this review.
2. Fetch the PR diff: `gh pr diff $ARGUMENTS`
3. Read the PR description: `gh pr view $ARGUMENTS`
4. Identify every file changed and categorize them (production code, tests, config, CI, docs).

## Review Passes

Launch **3 parallel Agent** reviews, each focused on a different dimension. Each agent must read the full diff AND the surrounding context of changed files (not just the diff lines — read the full functions/methods being modified).

### Agent 1: Correctness & Logic

Check every changed function for:
- **Logic errors** — wrong conditions, off-by-one, missing cases, unreachable code
- **Type / API misuse** — calling methods with wrong argument types or the wrong constructor/enum for an API. `grep` the API's declaration and compare.
- **Interface / contract compliance** — if a type implements an interface or extends a class, verify ALL methods are present and signatures match. Find the interface definition and compare.
- **Control-flow integrity** — for event-driven / message-passing code (reducers, handlers, state machines), trace the full chain: does the event/command produce the expected next state? Does the next handler actually handle it?
- **Error handling** — are errors silently swallowed? Are nil / null / None / undefined checks missing where the value could be absent? Are exceptions caught too broadly?
- **Concurrency** — data races on shared state, missing locks, goroutine/thread leaks, async ordering assumptions
- **Edge cases** — empty inputs, zero values, nil/null collections, boundary conditions, unicode, very large inputs

### Agent 2: Safety & Test Isolation

Check for:
- **Filesystem safety in tests** — does ANY code path during tests touch real user files (config dirs, state files, logs, cache, history)? Trace every read/write — including `init()` / module-level code that runs before test setup. Suggest a temp dir + env override if a leak is possible.
- **Global / module-level mutable state** — identify package-level mutable variables. Are they safe in tests? Could parallel test runs corrupt them? Is cleanup happening in the right order (defer ordering, teardown hooks)?
- **Environment leaks** — do tests set every env var that affects behavior? Could a missing override cause real-world side effects (e.g. actually hitting an API, touching prod config)?
- **Golden file / snapshot determinism** — scan every golden/snapshot for: absolute paths, temp dir paths, timestamps, random IDs, ANSI/color codes, platform-specific rendering, CWD-dependent content. Any non-deterministic content = flaky CI.
- **Test assertions** — are tests actually asserting what they claim? Watch for `t.Skip` / `xit` / `@Ignore` hiding failures, bifurcated assertions that pass on both branches, assertions on unrelated fields.
- **Dependency safety** — new dependencies: are they maintained? Known vulnerabilities? Pinned to a specific version? License compatible?
- **Secrets / tokens** — anything hardcoded or accidentally committed? Env-var names that hint at secret material printed to logs?

### Agent 3: Performance, UX & Consistency

Check for:
- **Performance** — O(n²) loops where n is user-scaled, unnecessary allocations in hot paths, blocking operations on UI / request-handling threads, unbounded growth of caches/maps/slices, N+1 queries
- **UX correctness** (for anything user-facing — CLI, TUI, web UI, API):
  - Output stays within its allocated space (no over-long lines in TUIs, no layout breaks in web UIs, no truncated CLI output)
  - Input / key / focus isolation — when a modal/overlay/dialog is active, background handlers must not fire
  - Focus / selection management — does opening/closing overlays correctly save and restore focus?
  - Status / feedback — does the UI show accurate state? Loading, error, empty, and success states all handled?
  - Accessibility basics — keyboard reachable, labeled controls, sufficient contrast (if web/TUI colors changed)
- **Consistency with codebase:**
  - Read existing code patterns in the same module. Does the new code follow them?
  - Are existing helpers/utilities reused instead of reinvented? `grep` for similar functions before concluding "new helper needed."
  - Naming follows the project's conventions (and language idioms)
  - Comments: accurate? Describe WHY not WHAT? No dead / stale comments left behind?
  - Does the code match the patterns documented in `AGENTS.md`?
- **CI / build / packaging changes** — are they correct across all supported platforms? Do they introduce new toolchain dependencies that need documenting or installing?

## Output Format

After all 3 agents complete, synthesize their findings into a single structured review. Deduplicate overlapping findings.

### Structure

```
## BLOCKING (must fix before merge)
1. [File:line] Description — why it matters, suggested fix

## IMPORTANT (should fix, could be fast follow-up)
1. [File:line] Description — why it matters, suggested fix

## MINOR (nice to have)
1. [File:line] Description

## Verdict
APPROVE / REQUEST_CHANGES / COMMENT
One-sentence summary of overall assessment.
```

### Rules

- Cite **specific file paths and line numbers** from the diff for every finding.
- For each finding, explain **why** it's a problem (not just what's wrong).
- Include a **suggested fix** for BLOCKING and IMPORTANT items — be concrete, show code if helpful.
- Don't flag style-only issues unless they violate patterns established in `AGENTS.md`.
- Don't flag missing tests for code that is itself test infrastructure (test helpers, mocks, fixtures).
- Do flag tests that don't actually test what they claim to test.
- If golden / snapshot files are present, spot-check 2-3 for determinism issues.
- If the diff touches an interface or abstract type, verify ALL implementations are updated.
- Limit to 15 findings max. Prioritize impact over quantity.
