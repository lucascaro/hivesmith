<!--
Standalone plan schema. Written by `/feature-plan`, edited by
`/feature-plan-review`, gated by `/feature-plan-handoff`.

Lives at `~/.hivesmith/plans/<slug>.md`. Used only for plans with no product
spec behind them — spec-driven plans use `docs/exec-plans/_template.md` and
carry their status in the spec's `stage:` frontmatter instead.

The contract: a fresh agent, in another worktree, on another harness, reads
this file and executes it without asking anything that was already settled.
No "as discussed above". No pronouns pointing at a conversation that is gone.
-->
---
slug: <yyyy-mm-dd-kebab-title>
title: <one line>
status: DRAFT
created: <yyyy-mm-dd>
source: free-form
repo: <absolute path to the repo this applies to; omit the key if none>
---

# <Title>

## Summary

<2–4 sentences. What is being built and why. Enough that someone who has never
seen the original request understands the job.>

## Context

<The original ask, verbatim or close to it, plus what was ambiguous about it
and how that ambiguity was resolved. This is what stops the executing agent
from re-opening settled ground.>

## Non-goals

<Explicit list. What this change deliberately does not do. Prevents scope
creep by an executor trying to be helpful.>

- <non-goal>

## Decisions

<Append-only. One entry per non-trivial choice, each with the alternative that
was rejected and why. Every answer the user gave during planning lands here.>

- **<decision>** — why: <reason>. Rejected: <alternative> because <reason>.

## Approach

<The chosen design and why it beats the obvious alternative. Name the existing
functions, helpers, and patterns being reused, with their paths.>

### Files to change

- `path/to/file` — what changes, and why

### New files

- `path/to/new` — purpose

### Tests

<Concrete and named. File path, test function name, what it verifies. Follow
the project's conventions from `AGENTS.md`. Never vague.>

- `path/to/test` :: `test_name` — verifies <behavior>

## Verification

<Exact commands a fresh agent can paste. Not "run the tests".>

```bash
<command>
```

## Open questions

<Must be empty before handoff. `/feature-plan-handoff` refuses otherwise.>

## Review log

<Append-only. Written by `/feature-plan-review`.>

- **<date>** — <what changed in the plan and why>.

## Progress

<Append-only. Written by the executing agent.>

- **<date>** — <state change>.
