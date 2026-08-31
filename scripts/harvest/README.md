# harvest

Two read-only tools that measure what hive's history already recorded, without
waiting for new telemetry.

Both print a `RESULT:` line, exit non-zero only on a usage or environment
error, and never write to the repo they measure.

## plan_citations.py — were the plans telling the truth?

An exec plan's authority comes from citing `internal/session/vt.go:35-52` rather
than "the VT wrapper". That specificity is the only part of a plan a machine can
check, which makes it the one quality signal available with no CI, no judge and
no waiting.

```
python3 scripts/harvest/plan_citations.py ~/checkout/hive             # accuracy
python3 scripts/harvest/plan_citations.py ~/checkout/hive --at head   # drift
python3 scripts/harvest/plan_citations.py ~/checkout/hive --verbose   # every finding
```

Two modes, two different questions:

| mode | reference tree | question |
|---|---|---|
| default | the commit that **wrote** each plan | was the citation true when made? |
| `--at head` | HEAD | how far has the code drifted from its own docs? |

On hive today: **94.1%** accurate when written (321 citations, 11 miss, 8 range),
**63.9%** against HEAD. The 30-point gap is doc staleness, not dishonesty.

Getting that number right took four corrections, each of which had inflated the
failure rate on its own:

1. **Resolving at the wrong tree.** One docs-hygiene commit rewrote 14 plans at
   once; "the commit that last touched the plan" dragged all 14 to a July tree
   where `main.js` had already been split up and deleted. Resolution follows
   renames back to the commit that *added* the plan.
2. **Reading shorthand as fabrication.** Plans cite `src/app/view.js:46` for
   `cmd/hivegui/frontend/src/app/view.js`. Demanding root-relative paths
   invented 45 phantom misses. Unique-suffix matches count; 167 of hive's 321
   resolved citations are this shape.
3. **Blaming a plan for a dependency.** A bare `state.go:477` is vt10x. A bare
   name that matches nothing is no evidence of anything, so it is excluded
   rather than counted wrong.
4. **Penalising a plan for proposing work.** `typescript-migration.md` cites
   `.ts` files that did not exist yet. A path absent then and present later is
   `planned`, not `miss`.

Uncorrected, those four put the number at 70.7%. The gap between that and 94.1%
is entirely the tool's own confusion.

## harvest_plans.py — what did each plan actually produce?

Joins `plan → PR → squash commit → models → files → churn`, so the questions can
be asked retrospectively.

```
python3 scripts/harvest/harvest_plans.py ~/checkout/hive
python3 scripts/harvest/harvest_plans.py ~/checkout/hive --csv out.csv --json out.json
python3 scripts/harvest/harvest_plans.py ~/checkout/hive --gh lucascaro/hive   # + CI
```

Joins 29 of 33 plans. The corpus is real, so the join is a fallback chain and
every row reports **how** it was joined — `pr-field` (19), `issue-ref` (9),
`spec-as-pr` (1), `unjoined` (4) — because a row joined by a weak fallback must
not look identical to one joined by a stated PR.

Three things that will silently corrupt this join if assumed away:

- The PR field is written five ways: `#242`, a bare pull URL, `[#179](url)`,
  prose about a PR closed unmerged, and absent (13 of 34 plans).
- The number in the filename is the **spec** number — not the PR number, and
  often not the issue number.
- The model is in `Co-Authored-By`, not a `Model:` trailer, and a squash-merge
  carries one per squashed commit. A PR has a *set* of models.

### The model comparison does not work, and the tool says so

`--gh` needs an authenticated `gh`; without it the git-derived columns still
stand and the CI columns are marked skipped rather than left blank.

The tool checks whether model identities worked in overlapping periods and
reports the verdict. On hive today it prints **NOT COMPARABLE**:

```
 20  2026-05-07 → 2026-05-31  Claude Opus 4.7
  4  2026-07-18 → 2026-07-19  Claude Opus 4.8
  3  2026-07-25 → 2026-08-28  Claude Opus 5
```

Zero overlap between any pair. Model is a proxy for calendar time here, so any
difference between them is indistinguishable from the repo maturing or the task
mix changing. Separately, the 11 PRs Fable 5 authored are improvement-plan work
that never became exec plans, so the plan corpus is not even a representative
sample of the repo. Use these rows to generate hypotheses and test them
prospectively; do not rank models with them.


## correction_episodes.py — how often does merged work come back?

Attributes corrections to the work that caused them by blaming the lines a fix
actually changes, not by looking for later commits that touch the same files.

```
python3 scripts/harvest/correction_episodes.py ~/checkout/hive
python3 scripts/harvest/correction_episodes.py ~/checkout/hive --by-model --verbose
python3 scripts/harvest/correction_episodes.py ~/checkout/hive --window 30 --min-lines 3
```

File-overlap attribution does not work on this corpus: hive averages 10.3 files
per commit and `CHANGELOG.md` appears in 131 of the last 300, so overlap
attributes nearly every fix to nearly every feature. A fix's diff has a
pre-image — the lines it deleted or replaced — and `git blame` on the parent,
restricted to those ranges, names who wrote them. Evidence rather than proximity.

On hive today: **98 corrections, 143 episodes across 87 originating commits,
median 10 days to correction, 40% of eligible commits attracting a correction
within 90 days.**

That number was 65% before three bugs came out of the tool, and the sequence is
worth keeping because each is a way this measurement lies by default:

1. **Code movement absorbing blame.** June's `main.js` modularization collected
   11 corrections it had no part in causing — it was merely the last commit to
   touch those lines. Blame now runs `-C -C -C` to follow lines back across the
   move. A refactor at the top of the table is the signature of this bug.
2. **A denominator that did not match the numerator.** Origins blamed from
   outside the scanned window were counted against a denominator drawn only from
   inside it. 65% → 49%.
3. **Incidental edits counted as corrections.** Blame is literal: a fix touching
   `import { scrollTrace } from './trace.js'` blames whoever wrote that import.
   The movement refactor's 11 "corrections" totalled 26 lines — 2.4 each, mostly
   imports and changed signatures — while genuine defect origins run 8 to 20
   lines per episode. `--min-lines` (default 2) drops those, and the ranking is
   by lines corrected rather than episode count. 49% → 40%.

Unattributable cases are reported, never guessed: `additive-only` (a fix that
only adds lines has no author to blame), `noise-only` (a fix confined to docs or
changelog), and `unresolved` (blamed to a commit outside the window or of an
ineligible type).

### The caveat is part of the output

These are defects **found**, not defects present. Detection tracks usage: on a
project with three users, code nobody exercises scores perfectly. The tool
prints this every run and the test suite asserts that it does. Read the number
alongside a usage signal or not at all.

`--by-model` additionally refuses to be read naively — it reports how many
eligible commits carry no model attribution at all, because that exclusion is
not random. It is whichever tool does not write a trailer, which biases exactly
the comparison the table invites. See `scripts/telemetry/prepare-commit-msg`.

## Tests

```
./scripts/harvest/plan-citations-test.sh   # RESULT: PASS checks=15
./scripts/harvest/harvest-plans-test.sh     # RESULT: PASS checks=19
./scripts/harvest/correction-episodes-test.sh # RESULT: PASS checks=14
```

Each builds a throwaway git repo whose history reproduces the specific ugliness
found in the real corpus — the bulk docs commit, the rename into `completed/`,
five PR spellings, a two-model squash, a commit with no co-author, a bot
co-author — and asserts the verdict that ugliness used to produce wrongly.
