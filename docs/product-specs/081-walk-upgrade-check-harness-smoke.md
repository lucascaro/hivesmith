---
title: Verify the entry-skill upgrade check in a live harness
stage: TRIAGE
---

# Verify the entry-skill upgrade check in a live harness

- **Exec plan:** [docs/exec-plans/active/081-walk-upgrade-check-harness-smoke.md](../exec-plans/active/081-walk-upgrade-check-harness-smoke.md) (or completed/)

## Problem

Spec 080 shipped with its merge gate at NEEDS_FOLLOWUP: two success criteria describe model behavior in a real harness — an entry skill asks before doing any work, and callee skills, subagents, unattended runs and print mode never ask — and no automated test can observe that. `tests/manual/upgrade-check-smoke.md` covers it but was not walked before merge. Two MINOR review findings were also left open: `hs-upgrade-check`'s opt-out grep ignores TOML table context that `install.sh` honours, and `concurrent_calls_fetch_once` waits a fixed 6s.

## Desired behavior

The manual smoke has been walked in Claude Code (and pi/codex where used), any behavior that diverges from the 080 spec is fixed, and the two MINOR findings are resolved.

## Success criteria

- Every step of `tests/manual/upgrade-check-smoke.md` has a recorded outcome in this spec's exec plan, including the background-fetch step in each harness used.
- Any step that fails has a fix merged, or a documented reason it cannot be fixed.
- `scripts/upgrade/check.sh`'s opt-out detection agrees with `install.sh` for a key nested under a `[table]`, with a test.
- `concurrent_calls_fetch_once` no longer relies on a fixed sleep.

## Non-goals

- Changing the entry-skill list or the four prompt options.
- Adding harness hooks.

## Notes

- Follow-up from the 080 merge gate (PR #83).
