# `scripts/metrics/`

Deterministic answers to three questions: **are the skills getting better over time**, **is the second opinion worth its cost**, and **which shipped features later needed fixing**.

## Why this exists

The pipeline already produced well-shaped structured data at four points — the second-opinion block, review-loop's per-iteration envelope, merge-gate's per-dimension envelope, review-pr's findings JSON — and dissolved every one of them into append-only markdown prose. The loss was already load-bearing: `review-loop` regex-parses `autofix`'s human-readable summary to make a control-flow decision, then cross-checks it against GraphQL because it does not trust its own parse.

Nothing recorded what the second opinion cost, what it found, or whether a feature shipped a bug.

## Two tiers, and why they are separate

| | git-derived | locally emitted |
|---|---|---|
| Lives in | the repo's own history | `${HIVESMITH_HOME:-~/.hivesmith}/telemetry/pipeline-events.jsonl` |
| Computable in CI | yes | **no** |
| Backfillable | yes | no |
| Carries | gate verdicts, ledger entries, regression declarations, PR dates | durations, `must_fix`/`applied` counts, seconds-to-approval, which retry fired |

CI cannot read `~/.hivesmith`, so the CI job computes only the git-derived half and **prints it to the job log** — it commits nothing. Writing a metrics artifact to `main` would need `contents: write` (held only by `regenerate-generated`) and would then be a generated file that `block-generated-edits` fails on every PR that touches it.

## Tools

| Tool | What it does |
|---|---|
| `emit.sh` (installed as `~/.hivesmith/bin/hs-metric`) | Appends one validated JSON line per pipeline event. **Fails loudly** — unknown event, missing required field, unknown field, wrong type, or out-of-enum value all exit `64` and append nothing. |
| `regressions.py` | Reports which merged PRs were declared as regressed, from `.changesets/` frontmatter recovered out of git history. |
| `report.py` | Merges both tiers. Prints pipeline counts, trend lines, the second-opinion block, and the regression split. |
| `backfill.py` | Seeds the stream from existing plan markdown (`## Gate verdict`, `## QA verdict`, `## PR convergence ledger`). |

## Design decisions worth not undoing

**Unknown fields are rejected.** The problem being solved is structured data decaying into prose. A free-text escape hatch would absorb everything within a week. If a field is needed, it goes in `SCHEMA` in `emit.sh`.

**`hs-metric` fails loudly; the telemetry hooks fail silently.** Opposite contracts, which is why they are in different directories writing to different files. A hook that fails a session is a bug; a metric that vanishes without a trace is a worse one, because the gap is invisible.

**Regressions are declared, never inferred.** Blame-based attribution does not survive a real repo: a bug frequently lives on lines the fix never touches, and a refactor is not a defect in what it rewrote. Both errors are silent. Declaration works here because every commit and PR title in this corpus is agent-written, so the agent fixing a defect can read the recent merged PR subjects and know which one it is undoing. `scripts/harvest/correction_episodes.py` still does the blame pass — as a detector for regressions nobody declared, reported as candidates and never counted.

**Three states, never a bare rate.** A merged PR is Regressed, Clean (survived the soak window), or Unobserved (too new to say). Reporting "clean" for something merged yesterday is the failure mode this prevents.

**The second-opinion number is correlational, and the disclaimer prints beside it.** There is no holdout arm: at this repo's cadence a hold-one-in-five design yields ~3 samples a year — not enough to separate a 30% effect from noise — and every holdout ships a real feature unreviewed. The useful ratio is `applied_count / must_fix_count`, because rejecting an item is itself a recorded outcome.

**Backfilled rows are marked and quarantined.** Every one carries `backfilled: true` and a `backfill_source: <file:line>`, is counted separately, and never enters a duration statistic — the markdown it came from has dates, not clocks. `emit.sh` allows a `--backfilled` row to omit an enumerated set of fields (`BACKFILL_EXEMPT`) that the historical record genuinely never contained, rather than inventing values for them.

## Usage

```bash
# Seed history (dry-run first — it prints every row it would write)
python3 scripts/metrics/backfill.py --emit --dry-run
python3 scripts/metrics/backfill.py --emit

# Read
python3 scripts/metrics/report.py --since 2026-01-01
python3 scripts/metrics/regressions.py . --soak-days 30

# CI format gate for regression declarations (never fails on absence)
python3 scripts/metrics/regressions.py . --validate-changed origin/main HEAD
```

## Tests

`emit-test.sh` (23 checks) and `regressions-test.sh` (15 checks). Both build throwaway repos and print `RESULT: PASS checks=<n>`. They run in the `script-suites` CI job alongside the telemetry and harvest suites.
