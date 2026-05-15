---
issue: 34
title: Clarify GitHub issue policy wording in hivesmith init
type: bug
complexity: S
priority: P3
stage: REVIEW
pr: 38
---

# Clarify GitHub issue policy wording in hivesmith init

- **Exec plan:** [docs/exec-plans/active/034-clarify-github-issue-policy-wording.md](../exec-plans/active/034-clarify-github-issue-policy-wording.md)

## Problem

During `/hs-hivesmith-init`, users pick a GitHub issue creation policy from three options labeled "Opt-out", "Opt-in", and "Always ask". The "opt-out" / "opt-in" terminology refers to opting out/in of being prompted to skip creation — not opting out/in of using GitHub issues themselves. Users misread "opt-out" as "don't use GitHub" and "opt-in" as "use GitHub", which is the opposite of the actual behavior.

## Desired behavior

The init prompt, the `.hivesmith/config.toml` comment, and any related docs describe each choice in plain language — e.g. "Create issues by default", "Skip GitHub by default", "Ask every time" — and spell out what the user gets with each choice (where the issue lives, what labels apply, how index rows differ).

## Success criteria

- The init prompt no longer uses the bare terms "opt-out" / "opt-in" as user-facing labels.
- Each option's description in the prompt names the resulting behavior and the visible difference (GitHub issue vs local-only spec).
- `.hivesmith/config.toml`'s comment explains each value's behavior without requiring outside context.

## Non-goals

- Changing the underlying config key names (`opt-out` / `opt-in` / `ask`) — those remain for backwards compatibility.
- Changing the default policy.

## Notes

Reported via `/hs-feature-loop`.
