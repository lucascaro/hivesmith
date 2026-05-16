---
type: changed
bump: minor
---
- **Clearer GitHub issue policy wording in `/hivesmith-init`, plus a new `always` value.** The three opt-in/opt-out labels users picked from during init were routinely misread (opt-out reading as "don't use GitHub"). The prompt now describes each choice by behavior — *Create issues on GitHub by default* / *Always create, never ask* / *Keep specs local by default* / *Ask every time* — and each option spells out what the user gets (issue number, lifecycle labels, PR link vs local-only spec). The `.hivesmith/config.toml` comment and the post-init tip were rewritten to match.

  The new **`always`** policy value skips Gate 1 in `/feature-new` and `/feature-loop` entirely: when set, the issue is opened as soon as a feature is described, without the confirmation prompt. Other gates (triage, plan approval, push, merge) are untouched. `always` is independent of `--full-auto` — both can be combined.

  Existing config values (`opt-out`, `opt-in`, `ask`) are unchanged, so previously-initialized projects keep working without migration. Default policy remains `opt-out`.
