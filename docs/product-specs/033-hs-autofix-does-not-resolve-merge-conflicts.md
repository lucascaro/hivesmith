---
issue: —
title: hs-autofix does not resolve merge conflicts
type: bug
complexity: M
priority: P2
stage: IMPLEMENT
---

# hs-autofix does not resolve merge conflicts

- **Issue:** —
- **Exec plan:** _to be created in PLAN phase_

## Problem

The `/hs-autofix` skill is not fixing merge conflicts when a PR branch develops conflicts against the base branch. When `/hs-review-loop` (or a user) invokes autofix on a conflicted PR, autofix should detect the conflict, merge/rebase against the base, resolve trivial conflicts where possible, and surface non-trivial ones. Currently it skips or fails silently, leaving the PR stuck and forcing manual intervention.

## Desired behavior

When autofix runs on a PR with merge conflicts against the base branch, it attempts the merge/rebase, resolves conflicts it can safely handle (e.g. decentralized index/changelog rows, additive-only sections), commits the resolution, and pushes. Non-resolvable conflicts are reported back with the affected files so the human (or review-loop) can escalate.

## Success criteria

- Autofix detects conflicts on the PR branch before attempting other fixes.
- Trivial conflicts (additive, non-overlapping) are resolved and pushed automatically.
- Non-trivial conflicts are surfaced with a clear summary of affected files instead of being silently skipped.

## Non-goals

- Resolving semantic conflicts that require code understanding beyond merge metadata.
- Replacing human review for ambiguous conflict resolutions.

## Notes

Related: #32 (decentralized indices/changelog) reduces conflict surface area but does not eliminate it.
