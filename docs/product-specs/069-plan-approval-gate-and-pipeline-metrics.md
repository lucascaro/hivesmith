---
issue: 69
title: Plan approval gate + deterministic pipeline metrics
type: enhancement
complexity: L
priority: P1
stage: REVIEW
pr: 70
---

# Plan approval gate + deterministic pipeline metrics

- **Exec plan:** [docs/exec-plans/active/069-plan-approval-gate-and-pipeline-metrics.md](../exec-plans/active/069-plan-approval-gate-and-pipeline-metrics.md)

## Problem

**Approve does nothing.** `skills/plan-html/start.sh` is deliberately non-blocking and `skills/plan-html/SKILL.md:44` says only "Poll `<plan>.approved.json`" — prose with no mechanism behind it (`grep -rn Monitor skills/` returns zero; there is no wait script and no loop). The agent renders, serves, prints the URL, and its turn ends. The operator clicks Approve, `server.py:112-118` writes the file, and nothing reads it — while `template.html:286-288` disables the button and shows "✓ Approved", so the UI lies and the operator's one signal is spent. Two aggravators: `start.sh:46` clears only the port file, so a re-run on the same slug hits a stale `.approved.json` and instantly false-approves; and `start.sh:64` overwrites the pid sidecar unconditionally, so `stop.sh:21` can never reap a predecessor and `nohup` servers accumulate.

**Nothing measures whether the skills are improving.** The pipeline produces well-shaped structured data at four points — the second-opinion block (`feature-loop/SKILL.md:178-186`), review-loop's per-iteration envelope (`review-loop/SKILL.md:82-100`), merge-gate's per-dimension envelope, and review-pr's findings JSON — and discards every one into append-only markdown prose. The loss is already load-bearing: `review-loop/SKILL.md:76-77` regex-parses autofix's human-readable summary for a control-flow decision, then cross-checks it against GraphQL because it does not trust its own parse. Nothing records what the second opinion costs, what it found, or whether a shipped feature later needed fixing.

## Desired behavior

Clicking Approve advances the loop within seconds, every time, with no operator action in chat. Leaving per-section feedback advances the loop to a revise round once typing has settled.

Every pipeline run leaves behind schema-validated events that answer three questions: are the skills getting better over time, is the second opinion worth its cost, and which shipped features later needed fixing. Regressions are **declared** by the agent that fixes them, never inferred from `git blame`.

## Success criteria

- `skills/plan-html/wait.sh` blocks until approval (exit 0), quiesced feedback (exit 10), timeout (exit 11), or a dead server (exit 3), and the canonical call sequence drives iteration through it.
- A stale `.approved.json` from a prior run on the same plan slug never produces an instant approve.
- Starting a server for a plan reaps any predecessor server for that same plan.
- `hs-metric` appends one JSON line per event and **exits 64 without appending** on an unknown event, a missing required field, an unknown field, a non-integer where an integer is required, or an out-of-enum value.
- `.changesets/*.md` accepts `regression_of:` on `type: fixed`, CI validates its format (never its absence), and `scripts/metrics/regressions.py` recovers declarations from git history after `release.sh` has deleted the files.
- `regressions.py` reports Regressed / Clean / Unobserved as three distinct counts and never prints a bare regression rate.
- `scripts/metrics/report.py` prints the second-opinion block with its correlational disclaimer inline, and counts backfilled rows separately from live ones.
- The 8 currently-orphaned test suites plus the 3 new ones run in CI.

## Non-goals

- **A holdout arm for the second opinion.** At this repo's cadence it yields ~3 samples/year — not enough to distinguish a 30% effect from noise — and each holdout ships a real feature unchecked. Measurement is correlational and says so in its own output.
- **Backfilling second-opinion history.** Only 2 plans carry the section, both `revise`. A prose parser for 2 rows is more code than data.
- **Auto-installing telemetry hooks from `install.sh`.** They fire in every Claude Code session on the machine; a doctor advisory plus a per-repo opt-in in `/hivesmith-init` gets discoverability without the consent problem.
- **Rewiring `review-loop:76-77` to read `autofix_applied`.** That path is already cross-checked against GraphQL. Emit for measurement; leave control flow alone.
- A dashboard, a database, or any committed metrics artifact.

## Notes

Changeset `049` documents a deliberate prior decision to use blame over file-overlap in `correction_episodes.py`. That decision stands for what that tool does; this spec adds **declared** attribution as ground truth and demotes blame to an undeclared-candidate detector, so a forgotten declaration still surfaces — flagged as unconfirmed rather than counted.

`scripts/release.sh:88` deletes all `.changesets/*.md` at release and `regen-generated.py:152` drops frontmatter, so any harvester must walk `git log --diff-filter=A -- .changesets/` rather than the working tree.
