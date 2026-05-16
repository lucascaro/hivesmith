# Clarify GitHub issue policy wording in hivesmith init

- **Spec:** [docs/product-specs/034-clarify-github-issue-policy-wording.md](../../product-specs/034-clarify-github-issue-policy-wording.md)
- **Issue:** #34
- **Status:** completed
- **PR:** #38
- **Branch:** feature/34-clarify-github-issue-policy-wording

## Summary

Reword the user-facing prompt and config comment that `/hs-hivesmith-init` writes so the three GitHub-issue-policy choices are described by their behavior, not by the ambiguous "opt-in"/"opt-out" labels. Keep the underlying config values (`opt-out` / `opt-in` / `ask`) unchanged for backwards compatibility.

## Research

User-facing surfaces that show the confusing labels:

- `skills/hivesmith-init/SKILL.md:82–86` — the AskUserQuestion prompt the user sees during init. Options literally start with "Opt-out — …", "Opt-in — …".
- `skills/hivesmith-init/SKILL.md:88–92` — the `[github]` block written to `.hivesmith/config.toml`, including a comment that begins `# One of: "opt-out" (create by default), "opt-in" (skip by default), "ask" (no default).`
- `skills/hivesmith-init/SKILL.md:118` — closing tip lists the values bare: `(opt-out / opt-in / ask)`.
- `templates/AGENTS.hivesmith.md:8` — project-level doc snippet that explains the policy to other agents; uses the same pattern.

Internal references (NOT user-facing — leave alone, per Non-goals):

- `skills/feature-new/SKILL.md:19,26,27,99`, `skills/feature-loop/SKILL.md:30,100,106,107,149` — skill-author logic that reads the config and selects the recommended Gate 1 option. These read the raw string values; renaming would break read compatibility. Keep them.

No code reads `.hivesmith/config.toml`'s comment text — only humans do — so the comment is safe to rewrite freely.

## Approach

Rewrite the three user-facing labels around what the user gets, not the "opt" framing. The internal config values stay (`opt-out` / `opt-in` / `ask`); we only change descriptions and comments.

Proposed wording:

- **Create issues on GitHub by default** — `/feature-loop` and `/feature-new` open a GitHub issue when you start a feature; you can skip per-feature. (Maps to `opt-out`. Recommended.)
- **Keep specs local by default** — features live as files in `docs/product-specs/` only; no GitHub issue is created unless you ask. (Maps to `opt-in`.)
- **Ask every time** — no default; the prompt shows neutral options for each new feature. (Maps to `ask`.)

Each label is followed by a short "what you get" line: with GitHub → issue number, labels (`triaged`, `researching`, `planned`, `implementing`, `qa`), index row shows `#NN`. Without GitHub → no issue, no labels, index row shows `—` in the issue column, number is allocated locally.

### Files to change

- `skills/hivesmith-init/SKILL.md` — rewrite the AskUserQuestion prompt at lines 82–86, the `.hivesmith/config.toml` comment block at 88–92, and the closing tip at line 118. The closing tip should describe each value briefly rather than listing bare keys.
- `templates/AGENTS.hivesmith.md` — line 8: rewrite to match the new descriptions while still showing the raw config values agents will read.

### New files

None.

### Tests

This skill has no automated test harness — it's executed by Claude. Manual verification:

- Re-read the updated SKILL.md as if running init for the first time; the three options should be unambiguous about which one creates GitHub issues.
- Diff the proposed config.toml comment against the prompt wording; they should agree.

## Decision log

- **2026-05-15** — keep internal config values (`opt-out`/`opt-in`/`ask`) unchanged. Why: multiple skills read those strings; renaming is out of scope per spec Non-goals and would force a migration step.
- **2026-05-15** — add a new `always` value (per HTML-review feedback) rather than expanding `opt-out`. Why: keeps the "confirm at Gate 1" behavior intact for users who want it, and gives a clean knob for users who want zero prompting. Implementation is a single one-line branch at Gate 1 in both `feature-new` and `feature-loop`.

## Progress

- **2026-05-15** — spec + plan drafted, research complete.
- **2026-05-15** — plan revised after HTML review: added `always` policy value that skips Gate 1.
- **2026-05-15** — implementation complete. Edited `skills/hivesmith-init/SKILL.md`, `skills/feature-new/SKILL.md`, `skills/feature-loop/SKILL.md`, `templates/AGENTS.hivesmith.md`. Added changeset `.changesets/034-github-issue-policy-wording.md`. shellcheck + brain tests green.

## Open questions

None.

## PR convergence ledger

- **2026-05-15 iter 1** — verdict: APPROVE; findings_hash: empty; threads_open: 0; action: stop; head_sha: ac0d2ea.

## QA verdict

- **2026-05-16** — verdict: PASS; checks: 5 passed / 0 failed / 0 followups; followups: none; one-line: wording rewritten as planned, new `always` value wired through `feature-new` + `feature-loop`, defaults and config keys preserved.
  - 2026-05-16 dimensions:
    - build/lint/test — PASS — `shellcheck` clean across all listed scripts; `scripts/brain/test/run-all.sh` 13/13 pass.
    - acceptance — PASS — prompt no longer leads with bare "opt-out"/"opt-in" labels (each option is a behavior phrase); each option names the resulting outcome (issue number + lifecycle labels vs `—` index row); `.hivesmith/config.toml` comment block describes each of the four values inline.
    - non-goals — PASS — internal config keys (`opt-out`, `opt-in`, `ask`) unchanged; new `always` added alongside; default-when-missing remains `opt-out` per `feature-new` step 1 and `feature-loop` step 3a.
    - regression — PASS — diff is markdown-only across `skills/hivesmith-init/SKILL.md`, `skills/feature-new/SKILL.md`, `skills/feature-loop/SKILL.md`, `templates/AGENTS.hivesmith.md`; no code paths touched; `templates/AGENTS.hivesmith.md` description rewritten to match.
    - doc accuracy — PASS — `.changesets/034-github-issue-policy-wording.md` present (CHANGELOG regen on next push); README does not document the issue-policy surface, so no staleness introduced.
