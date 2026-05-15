# <Title>

- **Spec:** [docs/product-specs/<slug>.md](../../product-specs/<slug>.md)
- **Issue:** #<number>
- **Status:** active | completed
- **PR:** —
- **Branch:** —

<!--
Stage is **not** carried here. The spec's YAML frontmatter `stage:` is the
sole source of truth. Skills read and write stage from the spec — never from
this file or from the generated `docs/product-specs/index.md`.
-->


## Summary

<2–4 sentences. What is being built and why this exec plan exists. The full *why* lives in the spec; this file is about the *how*.>

## Research

<Files, modules, and existing patterns the work touches. Cite paths.>

## Approach

<The chosen design. Include the reason it was chosen over the obvious alternative.>

### Files to change

- `path/to/file` — what changes
- `path/to/other` — what changes

### New files

- `path/to/new` — purpose

### Tests

- <named test functions or files that will be added/changed>

## Decision log

<Append-only. One entry per non-trivial decision made during implementation. Keep entries short.>

- **<date>** — <decision>. Why: <reason>.

## Progress

<Append-only. One entry per meaningful state change.>

- **<date>** — <state change>.

## Open questions

<Anything that needs human judgment before this plan can land. Empty when complete.>

## PR convergence ledger

<Append-only. One entry per `/review-loop` iteration so a fresh harness run can pick up where the previous one left off without rereading PR comments. Keep entries one line each.>

- **<date> iter <N>** — verdict: <APPROVE|COMMENT|REQUEST_CHANGES>; mergeable: <MERGEABLE|CONFLICTING|UNKNOWN>; findings_hash: <hex|empty>; action: <stop|autofix+push|autofix+push (conflict)|escalated:<reason>>; head_sha: <short-sha>.

## QA verdict

<Filled by `/feature-qa` after the PR merges. Append-only; one entry per QA run. Stage advances to DONE only when the latest entry is PASS.>

- **<date>** — verdict: <PASS|FAIL|NEEDS_FOLLOWUP>; checks: <bullet summary>; followups: <issue numbers or "none">; one-line: <summary>.
