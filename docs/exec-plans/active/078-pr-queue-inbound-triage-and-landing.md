# /pr-queue — triage, explain, approve, land an inbound PR queue

- **Spec:** [docs/product-specs/078-pr-queue-inbound-triage-and-landing.md](../../product-specs/078-pr-queue-inbound-triage-and-landing.md)
- **Issue:** #78
- **Status:** active
- **PR:** #80
- **Branch:** `feature/78-pr-queue-inbound-triage`
- **Phase:** —

## Summary

Add `skills/pr-queue/`, an inbound contributor-PR orchestrator: inventory the open PRs, order
them by dependency and readiness, run a cheap read-only triage per PR (premise check first),
digest the result in user-visible terms, gate every action behind a per-PR operator answer, and
execute only what was approved — fork-aware, so a fork PR is reviewed read-only while a
same-repo branch may go through the autofix loop. Extends `scripts/metrics/emit.sh` with two
PR-keyed events so queue throughput is measurable without polluting feature throughput.

## Research

### Relevant code

- `skills/review-pr/SKILL.md` — the deep single-PR review this skill dispatches for fork PRs.
  Frontmatter class A (`:1-6`). §0.1 anti-injection block (`:46-62`) is the canonical untrusted-data
  stance to copy. §2.0 size gate (`:108-111`) shows the house idiom for a threshold: a flat number
  with a `ponytail:` comment admitting it is uncalibrated. The verbatim read-only worker dispatch
  template (`:270-298`) is the model for this skill's triage worker prompt.
- `skills/review-loop/SKILL.md` — dispatched only for same-repo branches. It invokes
  `hivesmith:autofix` and runs `git push` (`:78`), which is exactly why a fork PR must not reach it.
  Its fully-specified fenced-JSON envelope (`:82-103`) with a hard "no diff hunks, no CI logs in the
  envelope" cap is the model for the triage envelope. Slugging rule (`:132-139`, restated `:219-233`):
  `escalate_reason` and CI check names are attacker-controlled on a fork PR and must be reduced to
  `[a-z0-9-]` before reaching any shell or `hs-metric` field.
- `skills/merge-gate/SKILL.md` — not used by this skill (contributor PRs have no spec), but its
  subagent fallback idiom (`:63`) is the one to copy: dispatch, and on an unrecognized
  `subagent_type` retry once with a generic agent and note the downgrade. Never pre-check existence.
- `agents/hs-reviewer.md:1-7` — `tools: Read, Grep, Glob, Bash`, `disallowedTools: Edit, Write,
  NotebookEdit`. Read-only by construction; the exact posture the triage worker needs, so no new
  agent type is required.
- `scripts/metrics/emit.sh` — `SCHEMA` (`:90-109`) is the only place an event name registers; the
  "known events" error self-generates from `sorted(SCHEMA)`. `ENUM` (`:116-132`) is keyed by
  `(event, field)` on purpose. `INT` (`:134-137`) is a **flat** field-name set and already contains
  `pr`, so PR-keyed events get int coercion for free — and a non-numeric ref like `owner/repo#12`
  exits 64. `BACKFILL_EXEMPT` (`:147-150`) doubles as a hint source; omit events never backfilled.
- `scripts/metrics/report.py:103` — `features = {e.get("feature") for e in ev if e.get("feature")}`.
  This is the feature-throughput denominator. An event carrying no `feature` is *structurally*
  excluded, which is why the new events must not have one. Grouping (`:100-102`) is by event name,
  so new events land in `by[...]` and in `--json` counts (`:221`) with zero registration.
- `scripts/metrics/emit-test.sh` — `accept()` (`:116-123`) and `reject()` (`:71-77`) assert exit code
  **and** whether the log grew; `before="$(lines)"` must be refreshed after any `accept` (precedent
  at `:136`). Test counts are asserted nowhere, so adding cases needs no counter update.
- `install.sh:320-324`, `:677-682` — skills are auto-discovered by glob; `:782-786` is the prefix
  renderer's sed program, which rewrites `/<skill>` but **not** the plugin-qualified
  `"hivesmith:<skill>"` `Skill`-tool form. That is why the two reference mechanisms stay distinct.

### Constraints / dependencies

- **Golden principle 5 is NOT CI-enforced, and the tree is not at zero today.**
  `.github/workflows/ci.yml:82-95` (render-correctness) only asserts that specific rendered
  `feature-research` / `release` files got prefixed; it never runs GP5's detection grep.
  `grep -rn '/hs-[a-z]' skills/ templates/` returns **41 hits** on today's tree. Most are the
  `~/.hivesmith/bin/hs-metric` binary path and `HIVESMITH_SKILL=hs-<skill>` env assignments, which
  GP5 itself exempts ("genuinely an external command that happens to start with `hs-`"); the genuine
  slash-command deviations are pre-existing in `skills/brain-promote/`, `skills/brain-garden/`
  and `skills/hivesmith-init/`. **Scope for this feature: `skills/pr-queue/` must contribute zero
  new hits.** Cleaning the pre-existing ones is a `/gc-sweep` job, not this PR — and GP5's detection
  grep is itself over-broad against the `hs-metric` path, which is worth filing separately.
- **Golden principle 4** — this skill is class A (`name`, `description`, `argument-hint`,
  `allowed-tools`). `disable-model-invocation` is used by the 11 `feature-*` skills **only**;
  setting it here would be wrong.
- **Golden principle 6** — a new `.sh` must be added to `.github/workflows/ci.yml` shellcheck
  `additional_files` **and** the `Lint:` line in `AGENTS.md`. This change adds no shell script, so
  the invariant is untouched.
- `docs/product-specs/index.md` and `CHANGELOG.md` are generated; the `block-generated-edits` CI job
  (`.github/workflows/changesets.yml:67`) rejects a PR that touches them.
- A changeset is required by `scripts/hooks/pre-push` (advisory, prompts) and by
  `.github/workflows/changesets.yml:85-101` (hard failure, bypassable only with the `no-changeset`
  label). `.changesets/<NNN>-<slug>.md` ids are monotonic; current max is 076, so `078` is legal.
- `docs/design-docs/` has no real entry yet — only `index.md` and a stub `core-beliefs.md`.
  `docs/design-docs/pr-queue.md` would be the first, so its shape comes from `index.md`'s stated
  contract: decision, the constraints that drove it, alternatives considered. Flat `<slug>.md`, no
  number prefix, plus a row in `index.md`'s `## Active`.
- **No wall-clock budgets exist anywhere in this toolbox.** Bounding is expressed as iteration caps,
  size thresholds, and a propagated `escalate_reason`. The source spec's "hard time budget" language
  has no precedent to build on and must be re-expressed in those terms.
- ~~`report.py` has **no CI coverage**~~ — **wrong, corrected during review.** The `metrics` job
  (`ci.yml:198-213`) indeed runs only `regressions.py` + harvest, which is where this claim came
  from, but `scripts/metrics/backfill-test.sh` exercises `report.py` directly (`:24`, `:176`) and
  runs in the `script-suites` job (`ci.yml:191`). `report.py` **is** covered in CI, and the new
  `PR QUEUE` block belongs in that suite.

### Prior lessons

- Emit commands written inside SKILL.md prose are unvalidated code — nothing type-checks them
  against the emitter schema and CI never executes them. Three defect classes ship green: a typo'd
  binary path that fails silently under the "missing emitter is not a failure" rule; a placeholder
  whose shape disagrees with sibling call sites (a slug where the stream carries an integer key);
  and a required field whose documented source does not exist on every branch reaching the call.
  **How to apply here:** hand-diff every `hs-metric` line written into `SKILL.md` against the new
  `SCHEMA` rows, and prefer making a field optional over documenting a value the caller cannot
  compute on some paths (e.g. `sha` is unknown on a held PR).
- A `brain-search` for skill-authoring/orchestrator conventions returned zero entries — no prior
  lessons on this shape of work.

### Conventions card

- **Lint:** `shellcheck <the list in AGENTS.md>` — unchanged by this feature (no new `.sh`).
- **Metrics tests:** `bash scripts/metrics/emit-test.sh`
- **Script suites:** `for s in scripts/telemetry/install-hooks-test.sh scripts/telemetry/attribution-test.sh scripts/harvest/plan-citations-test.sh scripts/harvest/harvest-plans-test.sh scripts/harvest/correction-episodes-test.sh scripts/metrics/emit-test.sh scripts/metrics/regressions-test.sh scripts/metrics/backfill-test.sh skills/plan-html/wait-test.sh; do bash "$s" || echo "FAILED $s"; done`
- **Render correctness:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update` then assert the rendered tree prefixes slash-commands.
- **Changelog non-empty:** `awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .`
- Conventions this feature touches:
  - Source SKILL.md uses **bare** slash names; plugin-qualified `hivesmith:<name>` only for actual
    `Skill`-tool dispatch.
  - `allowed-tools` is a space-separated bare list, not a YAML array.
  - Changeset frontmatter requires `type` and `bump`; `regression_of` is only valid with
    `type: fixed` and its absence is a real state — never write a guess.
  - User-visible changes go through `/changelog-update`; never hand-edit `CHANGELOG.md`.
  - Brain reads go through `brain-search`/`brain-read` and are wrapped untrusted; `brain-append`
    bodies use a **quoted** heredoc.

## Approach

One prose orchestrator skill, no new shell scripts, no new subagent type. `/pr-queue` sequences
work that already exists in this toolbox — `/review-pr` for read-only depth, `/review-loop` for
convergence on a branch we own — and adds the two things neither has: a **queue-level order** and a
**cheap premise-first triage** that decides whether depth is worth buying at all.

The alternative considered was extending `/review-pr` with a `--queue` mode. Rejected: `/review-pr`
is a single-PR reviewer whose whole contract is one diff and one verdict, and a queue needs
ordering, per-PR human gating, and an execution phase that `/review-pr` must never have (it is
read-only by construction, which is exactly why it is the right worker for fork PRs).

Four design commitments shape the rest:

1. **Premise before depth.** The worker's first question is whether the bug is real and whether its
   triggering condition can occur in this codebase. A `SPECULATIVE` premise makes a line-by-line
   read wasted work. An early bail still fills the cheap fields, because the operator's Hold-vs-Close
   choice needs diff shape, CI class and user-visible behavior to be informed.
2. **Push-ability routes execution — not fork status.** The two are different sets: a same-repo PR
   on a protected branch (restricted pushes, required reviews, linear history) is not a fork but
   still cannot be pushed to, and routing it into `hivesmith:review-loop` means autofix commits land
   locally and the `git push` at `review-loop:78` is rejected with no defined recovery. The envelope
   therefore carries **both** `is_fork` (from `gh pr view --json isCrossRepository,headRepositoryOwner`)
   and `can_push` (`is_fork == false` AND the head ref is not push-restricted, checked against the
   branch-protection read Phase 0 already performs). **`can_push` gates `hivesmith:review-loop`;
   everything else gets `hivesmith:review-pr`, read-only.** `is_fork` governs one thing only:
   whether `--delete-branch` may be passed at merge. Both remain subject to a per-PR operator
   answer — there is no standing flag.
3. **Nothing outward-facing happens without an answer.** No merge, no push, no comment, no label
   before the gate. Held-PR comments are drafted into the digest and posted only after one batch
   confirmation.
4. **Queue metrics never touch feature metrics.** `pr_triaged` / `pr_landed` carry `pr` and
   deliberately carry no `feature`, which makes their exclusion from `report.py`'s feature
   denominator structural rather than defensive.

**Bounding.** This toolbox has no wall-clock budgets anywhere; it bounds work with size thresholds,
iteration caps and a propagated `escalate_reason`. The source spec's "hard time budget" is
re-expressed the same way: a `--max-parallel` cap on concurrent workers, a file/line threshold above
which the worker reports shape instead of reading, and `escalate_reason` returned rather than
waiting. Thresholds carry a `ponytail:` comment admitting they are uncalibrated, matching
`review-pr:110`.

### Files to change

1. `scripts/metrics/emit.sh` — add two `SCHEMA` rows and their `ENUM` entries:
   - `"pr_triaged": ({"pr", "premise", "recommendation"}, {"real_lines", "reported_lines",
     "mechanical", "ci_class", "base_behind", "is_fork"})`
   - `"pr_landed": ({"pr", "disposition"}, {"hold_reason", "sha", "autofix"})`
   - `ENUM`: `("pr_triaged","premise")` = `{REPRODUCED, PLAUSIBLE, SPECULATIVE, NOT_A_BUG}`;
     `("pr_triaged","recommendation")` = `{MERGE, FIX_THEN_MERGE, HOLD_FOR_AUTHOR, CLOSE}`;
     `("pr_triaged","ci_class")` = `{GREEN, MECHANICAL, SUBSTANTIVE}`;
     `("pr_triaged","mechanical")` = `{none, crlf-conversion, reformat, generated-file, mixed}` —
     a single dominant-cause slug, enumerated rather than left a free string, so the field is
     groupable in `report.py`. The full list stays in the envelope's `mechanical_causes`, which
     never reaches the metrics stream;
     `("pr_triaged","is_fork")` and `("pr_landed","autofix")` = `{true, false}`;
     `("pr_landed","disposition")` = `{merged, enqueued, held, closed, skipped}` — `enqueued` is the
     merge-queue path, where no merge has happened and there is no SHA to record.
   - `INT`: add `real_lines`, `reported_lines`, `base_behind`. (`pr` is already there.)
   - No `BACKFILL_EXEMPT` entries — these events are never backfilled.
   - Neither event takes `feature`. That is the whole isolation mechanism; do not add it "for
     symmetry".
2. `scripts/metrics/emit-test.sh` — new cases (§Tests below). Refresh `before="$(lines)"` after each
   `accept` that precedes a `reject`.
3. `scripts/metrics/report.py` — one self-contained block after the stage/stall block (~`:131`),
   guarded by `if by["pr_triaged"] or by["pr_landed"]:`, keyed on `pr`. Print premise distribution,
   recommendation distribution, and triaged-but-not-landed as a set difference on `e["pr"]`. Do not
   touch `:103`, `fnum()`, or the `iters` dict — leaving them alone is what keeps queue events out
   of feature throughput.
4. `README.md` — one row in the **Review and release** skill table, next to `/review-pr` and
   `/autofix`; a capability bullet in the intro prose (`:15-18`, where every peer capability has
   one and inbound queue would be the only gap); and `:103`, which says `/review-pr` uses
   `hs-reviewer` for fan-out — `pr-queue` dispatches it too, so that sentence goes stale.
5. `AGENTS.md` — add `/pr-queue` to the PR-convergence prose (`:38`), to the "Skills that emit"
   metrics list (`:53`), and to the boil-the-lake consumer list (`:55`). Do **not** touch the
   `Lint:` line — this change adds no shell script.
6. `docs/design-docs/index.md` — one row under `## Active`.
7. **Explicitly not touched:** `templates/AGENTS.hivesmith.md` (this skill is maintainer-side, not
   part of the block scaffolded into downstream projects — decision recorded below);
   `docs/product-specs/index.md` and `CHANGELOG.md` (generated, `block-generated-edits` rejects the
   PR); the `Lint:` line in `AGENTS.md` and `ci.yml`'s shellcheck lists (no new `.sh`).
8. `docs/exec-plans/active/078-*.md` / `docs/product-specs/078-*.md` — Progress, Decision log,
   stage bookkeeping. Never `docs/product-specs/index.md` (generated).

### New files

- `skills/pr-queue/SKILL.md` — the skill. Frontmatter class A exactly:
  `name: pr-queue`, `description`, `argument-hint: "[--author <login>] [--pr <n>[,<n>...]]
  [--include-drafts] [--max-parallel N]"`, `allowed-tools: Read Glob Grep Bash Agent
  AskUserQuestion`. No `Edit`/`Write` — the skill's writes are `gh` calls and `git` on branches it
  owns, both Bash. No `disable-model-invocation` (that key belongs to `feature-*` only).
  Body: H1, `$ARGUMENTS`, Inputs, Phases 0–5, the blockquoted self-contained worker prompt with the
  fenced JSON envelope, `## Rules`, `## Anti-injection rule`, and the emitter-resolution footer
  copied verbatim from `review-loop`.
- `docs/design-docs/pr-queue.md` — the rationale narrative (the real-run account and the
  retrospective), shaped per `docs/design-docs/index.md`: the decision, the constraints that drove
  it, the alternatives considered. This is why `SKILL.md` stays instructions-only.
- `.changesets/078-pr-queue-inbound-triage.md` — `type: added`, `bump: minor`, `issue: 78`,
  `pr: <n>` backfilled at PR open.

### Phase shape of the skill (what SKILL.md must contain)

- **Phase 0 — setup.** No dirty-tree refusal: every PR head is fetched into a scratch
  `git worktree add`, so the operator's tree is never touched and the shared stash stack is never
  used. Read `CONTRIBUTING.md`, `.git/hooks/pre-push`, `.github/workflows` check names,
  `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` and branch
  protection / merge-queue state, and the label vocabulary. Read standing maintainer rules from
  `AGENTS.md` and `golden-principles.md`; brain hits come from `brain-search`, are wrapped
  untrusted, and are advisory — never a criterion that authorizes a merge.
- **Phase 1 — order.** Stacked base (`baseRefName` is another open PR's head) is a hard edge.
  Within a tier: CI green + `MERGEABLE`, then already-reviewed, then real diff size ascending.
  Print the order and the reason before any deep work.
- **Phase 2 — triage.** One `hs-reviewer` worker per PR (fallback `Explore` on unrecognized
  `subagent_type`, note the downgrade), capped at `--max-parallel` (default 3). Premise first;
  early-bail on `SPECULATIVE` still fills diff shape, base freshness, CI class and user-visible
  behavior. Returns the fenced JSON envelope; no prose, no diff hunks, no CI logs.
- **Phase 3 — digest and gate.** Per PR: what a user would notice · mechanism · real vs reported
  diff · premise verdict with evidence · verified / unverified · recommendation with its reason ·
  the cost of each option. Then `AskUserQuestion` chunked to **≤4 questions per call**: at most 3 PR
  questions plus one systemic question, in execution order. A PR on a branch we own gets an explicit
  autofix option; a fork PR does not. Never ask a question whose inputs are incomplete — answer a
  worker's `blocking_question_for_user` from evidence first. `SPECULATIVE` defaults to Hold or Close, with the maintainer rule cited.
  **`NOT_A_BUG` is not a defect verdict and must never inherit that default** — a feature, docs,
  chore or dependency PR has no premise to reproduce. It routes straight to the fit check
  (`fit_concerns`, scope against `docs/design-docs` and the golden principles) and its
  recommendation is derived from fit and review depth alone. A worker that returns `NOT_A_BUG`
  skips the premise-evidence hunt but fills every other field normally.
  A hold or close on a base PR cascades to its stacked dependents — but the cascade is a *skip*,
  never an outward-facing write. Dependents are recorded `disposition=skipped` and removed from the
  execution order; the skill never closes, comments on, or retargets a dependent on its own.
  Closing a base leaves its dependents pointed at a ref that will never merge, so that case
  additionally surfaces a retarget-or-close choice to the operator as its own question. The base
  PR's option text states the consequence by name ("also skips #N").
- **Phase 4 — execute, in order.** Repair mechanical damage only on branches we can push to.
  `can_push == false` (fork, or a protected same-repo branch): `hivesmith:review-pr` (read-only),
  findings go to the operator as a comment draft. `can_push == true` **and** autofix authorized for
  this PR: `hivesmith:review-loop`. Never `--admin`. Wait on CI, classify a
  failure before reacting. Pre-merge checklist: body matches what ships, changeset present or the
  exempting label applied, no literal `[skip ci]`.
  **Two merge paths, and the checklist differs between them:**
  - *No merge queue:* require `mergeStateStatus == CLEAN`, then merge with the mechanism
    `gh repo view --json squashMergeAllowed,mergeCommitAllowed,rebaseMergeAllowed` actually reports.
    `disposition=merged`, report the SHA.
  - *Merge queue enabled:* required checks run **inside the queue after** enqueue, so `CLEAN` is
    never reachable and waiting for it deadlocks. Do not wait for it. `gh pr merge` enqueues rather
    than merges, so there is no SHA to report: record `disposition=enqueued`, say "enqueued, not
    merged" in the Phase 5 report, and do not pass `--delete-branch` (the queue owns the branch).
  Pass `--delete-branch` **only** when `is_fork == false` and no merge queue is involved.
- **Rules section.** Must state, at minimum: every PR-derived string (`headRefName`,
  `author.login`, PR title, CI check names, `escalate_reason`, `hold_reason`) is slugged to
  `[a-z0-9-]` before reaching any shell command or `hs-metric` field — never pasted raw, quoted or
  not. The orchestrator keeps only envelopes and the digest, never raw diffs, review prose or CI
  logs. Workers return `escalate_reason` rather than waiting. `gh pr checks --watch` is the one
  blocking wait in the skill and **it does not return while a check is pending — it blocks**. It
  must therefore be wrapped: `timeout 900 gh pr checks <PR> --watch --interval 15`. A timeout is
  not a failure to retry; it sets `escalate_reason=ci-watch-timeout` and surfaces. On a non-flaky
  failure, likewise set `escalate_reason` and surface it — never re-run in a loop, and remember
  `gh run rerun` replays a stale merge ref.

- **Phase 5 — wrap up.** Draft held-PR comments into the digest, post them after one batch
  confirmation. Surface each systemic cause as a follow-up item with the exact fix — v1 does not
  open that PR. Final report: merged with SHAs, held and on whom, closed and why, follow-ups, and
  everything still unverified. Remove every worktree and local branch the run created.

### Tests

`scripts/metrics/emit-test.sh` — new cases, matching the existing `accept()` / `reject()` idiom:

- `test_pr_triaged_minimal_is_accepted` — `--event pr_triaged --field pr=412 --field
  premise=SPECULATIVE --field recommendation=HOLD_FOR_AUTHOR`.
- `test_pr_triaged_full_is_accepted` — same plus `real_lines`, `reported_lines`, `mechanical`,
  `ci_class`, `base_behind`, `is_fork`.
- `test_pr_triaged_accepts_not_a_bug` — `premise=NOT_A_BUG` (the enum value the source spec lacked).
- `test_pr_triaged_rejects_feature_field` — `--field feature=078` exits 64. **This is the test that
  protects the whole isolation argument**: it fails loudly the day someone adds `feature` "for
  symmetry" and silently starts inflating feature throughput.
- `test_pr_triaged_rejects_unknown_premise` — `premise=MAYBE` exits 64.
- `test_pr_landed_minimal_is_accepted` — `--event pr_landed --field pr=405 --field
  disposition=merged`.
- `test_pr_landed_accepts_hold_reason` — `disposition=held --field hold_reason=speculative-premise`.
- `test_pr_landed_accepts_enqueued` — `disposition=enqueued` with no `sha` (the merge-queue path
  has no SHA; `sha` is optional precisely so this call site does not have to invent one).
- `test_pr_landed_accepts_skipped` — `disposition=skipped --field hold_reason=base-pr-held`, the
  stacked-cascade path.
- `test_pr_landed_rejects_unknown_disposition` — `disposition=landed` exits 64.

No test framework beyond the file's own helpers.

`scripts/metrics/backfill-test.sh` — **10 cases for the `PR QUEUE` block**, added during review after
the premise behind "verify it manually" turned out to be false (see Research). They assert the block
renders, reports premise / disposition / hold reason / triaged-but-not-landed, is absent on a stream
with no queue rows, and — load-bearing — that four queue rows leave `features=0` while
`queue=4`, in **both** stdout and the `--json` payload. Mutation-tested: folding queue rows back
into the JSON `live` count fails `test_pr_queue_json_live_excludes_queue`, and drifting the header
string fails `test_pr_queue_block_renders`.

## Verification

```bash
# 1. Metrics schema: the only automated gate on this change.
bash scripts/metrics/emit-test.sh

# 2. The isolation invariant, asserted against the in-repo source (NOT ~/.hivesmith/bin/hs-metric,
#    which is a stale install artifact absent from a fresh worktree). Must exit 64.
bash scripts/metrics/emit.sh --event pr_triaged \
  --field pr=1 --field premise=PLAUSIBLE --field recommendation=MERGE --field feature=078 \
  >/dev/null 2>&1
[ $? -eq 64 ] || { echo "FAIL: pr_triaged must reject a feature field"; exit 1; }
# ...and the same call WITHOUT `feature` must SUCCEED. Without this second half the check passes
# today for the wrong reason: an unknown event also exits 64, so rejection alone proves nothing.
bash scripts/metrics/emit.sh --event pr_triaged \
  --field pr=1 --field premise=PLAUSIBLE --field recommendation=MERGE >/dev/null 2>&1 \
  || { echo "FAIL: pr_triaged must be a known event"; exit 1; }

# 3. Golden principle 5, scoped to this feature — must print nothing.
#    (The wider tree has 41 pre-existing hits, mostly the exempt `hs-metric` binary path; GP5 is
#    not CI-enforced and cleaning those is a /gc-sweep job. This PR must add none.)
# GP5's literal detection grep also matches the `~/.hivesmith/bin/hs-metric` binary path, which
#    GP5's own text exempts ("genuinely an external command that happens to start with hs-") and
#    which every sibling skill contains. The real invariant is: no /hs-<skill> slash-commands.
! grep -rn '/hs-[a-z]' skills/pr-queue/ | grep -v 'hivesmith/bin/hs-metric' \
  || { echo "FAIL: GP5 violation in pr-queue"; exit 1; }

# 4. Frontmatter class A: all four keys present, and the key that must NOT be there absent.
for k in name description argument-hint allowed-tools; do
  awk 'NR>1 && /^---$/{exit} {print}' skills/pr-queue/SKILL.md | grep -q "^$k:" \
    || { echo "MISSING frontmatter key: $k"; exit 1; }
done
grep -q '^disable-model-invocation' skills/pr-queue/SKILL.md \
  && { echo "FAIL: disable-model-invocation must not be set on a class-A skill"; exit 1; } \
  || echo "ok: disable-model-invocation correctly absent"

# 4b. The skill is discovered and prefix-rendered like its siblings (not just present on disk).
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update \
  && grep -q '^name: hs-pr-queue' .rendered/hs-/skills/hs-pr-queue/SKILL.md \
  && grep -q '/hs-review-pr' .rendered/hs-/skills/hs-pr-queue/SKILL.md \
  && echo "render ok"

# 5. The skill dispatches review-pr read-only and review-loop only for same-repo branches.
grep -q 'can_push' skills/pr-queue/SKILL.md || { echo "FAIL: push-ability routing absent"; exit 1; }
grep -n 'hivesmith:review-pr\|hivesmith:review-loop\|is_fork\|can_push' skills/pr-queue/SKILL.md

# 5b. The deadlock guard is actually written into the skill, not just into this plan.
grep -q 'timeout 900 gh pr checks' skills/pr-queue/SKILL.md \
  || { echo "FAIL: unbounded CI watch"; exit 1; }
grep -q 'ci-watch-timeout' skills/pr-queue/SKILL.md || { echo "FAIL: no escalate on watch timeout"; exit 1; }

# 6. Every envelope field the spec's success criteria names is present in SKILL.md.
for f in pr title author head_sha is_fork base_pr merge_state premise premise_evidence          real_change reported_change mechanical_causes base_behind_by ci claims          unmentioned_consequences fit_concerns user_visible unchanged threads_open          maintainer_findings_addressed body_stale recommendation escalate_reason          blocking_question_for_user; do
  grep -q '"'"$f"'"' skills/pr-queue/SKILL.md || echo "MISSING envelope field: $f"
done

# 7. Rest of the suite plus render correctness.
for s in scripts/metrics/emit-test.sh scripts/metrics/regressions-test.sh          scripts/metrics/backfill-test.sh; do bash "$s" || echo "FAILED $s"; done
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run

# 8. The real changeset gate (CHANGELOG.md is generated; its [Unreleased] section already passes
#    today and cannot fail as a result of this PR, so asserting on it proves nothing).
ls .changesets/078-*.md >/dev/null 2>&1 || { echo "FAIL: no changeset for 078"; exit 1; }
grep -q '^type: added' .changesets/078-*.md || { echo "FAIL: changeset type"; exit 1; }
grep -q '^bump: minor' .changesets/078-*.md || { echo "FAIL: changeset bump"; exit 1; }

# 9. report.py actually renders the new block — seeded, because the block is guarded by
#    `if by["pr_triaged"] or by["pr_landed"]` and a machine with no queue events renders nothing.
#    This is the ONLY gate on the report.py change (ci.yml:198-213 never runs report.py).
TMPH=$(mktemp -d); export HIVESMITH_HOME="$TMPH"; mkdir -p "$TMPH/telemetry"
bash scripts/metrics/emit.sh --event pr_triaged --field pr=412 --field premise=SPECULATIVE \
  --field recommendation=HOLD_FOR_AUTHOR
bash scripts/metrics/emit.sh --event pr_triaged --field pr=405 --field premise=REPRODUCED \
  --field recommendation=MERGE
bash scripts/metrics/emit.sh --event pr_landed --field pr=405 --field disposition=merged
python3 scripts/metrics/report.py --events "$TMPH/telemetry/pipeline-events.jsonl" \
  | tee /dev/stderr | grep -q 'PR QUEUE' \
  || { echo "FAIL: report.py renders no PR-queue block"; exit 1; }
# and the queue events must NOT have inflated the feature denominator:
python3 scripts/metrics/report.py --events "$TMPH/telemetry/pipeline-events.jsonl" \
  | grep -q 'features=0' || echo "FAIL: queue events leaked into feature throughput"
```

## Second opinion

Two rounds, `general-purpose` reviewer, both `revise` at confidence 8.

**Round 1 — 7 must-fix, all 7 applied**, plus one item promoted from `nice_to_have`:

1. The plan's GP5 claim was wrong twice over — `grep -rn '/hs-[a-z]' skills/ templates/` returns 41
   hits today (not zero), and `ci.yml:82-95` never runs that grep. Criterion and check rescoped to
   `skills/pr-queue/`; the pre-existing deviations are a `/gc-sweep` job.
2. Verification check 2 read the install artifact and only `echo`'d the exit code — the check
   guarding the entire feature-isolation argument could not fail.
3. Verification check 9 rendered nothing on an unseeded machine, and it is the only gate on the
   `report.py` change (CI never runs `report.py`).
4. `NOT_A_BUG` existed in the enum but its routing to the fit check was written nowhere.
5. Fork status is not push-ability. A protected same-repo branch would have been routed into
   `review-loop`, whose `git push` fails *after* autofix has already committed, with no recovery.
   `can_push` added and made the routing predicate.
6. With a merge queue enabled, `mergeStateStatus == CLEAN` is unreachable before enqueue, so the
   pre-merge checklist deadlocked and the report would have claimed a merge that never happened.
   `disposition=enqueued` added.
7. "Cascade a close" read as auto-closing contributor PRs — an outward-facing write the design
   forbids. Redefined as a skip plus an operator question.
- Promoted: `gh pr checks --watch` blocks while a check is pending; it is now `timeout 900` with
  `escalate_reason=ci-watch-timeout`. That was the only place the run could hang indefinitely.

**Round 2 — 2 must-fix, both applied.** The reviewer verified 6 of the 8 fixes landed and caught
that fix #2 had silently failed to apply (the string it matched had been reflowed by the previous
edit), and that `can_push` had landed in the design but in no verification check — leaving the one
field that decides read-only-vs-push routing unasserted. Also taken from `nice_to_have`: the
`PR QUEUE` header string is now pinned so check 9 cannot fail spuriously, check 3 inverted to
`! grep` so it does not abort under `set -e`, a `disposition=skipped` test case added, and the
delegated-wait ceiling in `review-loop` recorded in the Decision log as a follow-up rather than
patched from a caller.

Not applied, with reason: the reviewer's observation that check 2 "passes today for the wrong
reason" was correct and is addressed by asserting **both** halves — rejection with `feature`, and
success without it — since an unknown event also exits 64.

## Decision log

- **2026-09-15** — Metrics get their own `pr_triaged` / `pr_landed` events keyed by `pr` rather
  than reusing `feature_done` with `feature=<pr>`. Why: reusing them mixes contributor PRs into
  feature counts irreversibly, and `report.py` could not separate them afterward.
- **2026-09-15** — v1 surfaces systemic-cause fixes as follow-up items instead of opening the PR
  itself. Why: it keeps the skill's write surface to repair-then-merge and held-PR comments, and
  the self-opened-PR path is exactly where `--no-verify` got normalized in the source run.
- **2026-09-15** — No `--yes-to-mechanical` flag. The autofix decision is a per-PR question every
  run. Why: operator's call; a standing pre-authorization is the kind of flag that surprises.
- **2026-09-15** — `timeout 900` bounds only *this* skill's CI watch. The delegated
  `hivesmith:review-loop` runs its own unwrapped `gh pr checks --watch`
  (`skills/review-loop/SKILL.md:78`), so the `can_push` path inherits an unbounded wait this plan
  does not fix. Accepted as a known ceiling for v1 and filed as a follow-up against `review-loop`
  rather than patched from here — wrapping another skill's internals from a caller is the wrong
  seam.
- **2026-09-15** — Fork PRs get `/review-pr` (read-only); only same-repo branches get
  `/review-loop`. Why: `/review-loop` invokes autofix and `git push`, which on a fork either
  fails or silently rewrites a contributor's branch.

## Progress

- **2026-09-15** — Spec written, issue #78 opened, stage advanced to RESEARCH.
- **2026-09-15** — Two second-opinion rounds (revise/8, revise/8); 9 must-fix items applied. Plan
  approved via chat after the HTML review page timed out unopened.
- **2026-09-16** — Implemented: `skills/pr-queue/SKILL.md` (303 lines), `docs/design-docs/pr-queue.md`,
  `.changesets/078-*`, metrics schema + 11 test cases + `report.py` PR QUEUE block, README/AGENTS.md
  cross-references. All 9 AGENTS.md script suites pass; prefix render verified.
- **2026-09-16** — Reversed the plan's "report.py has no CI coverage by design" decision. Its
  premise was false: I read only `ci.yml:198-213` (the `metrics` job, which genuinely never runs
  `report.py`) and generalized, missing that `backfill-test.sh` tests `report.py` and runs in the
  `script-suites` job. The review found its one real defect in exactly that unguarded block, so the
  manual verification step became 10 CI cases instead. Operator approved the reversal.
- **2026-09-16** — Verification check 3 corrected during implementation: GP5's literal grep matches
  the `~/.hivesmith/bin/hs-metric` binary path, which GP5's own text exempts and which every
  metrics-emitting skill contains. The check now excludes it; the real invariant is no
  `/hs-<skill>` slash-command references.

## Open questions

<pending>

- **2026-09-16 iter 1** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: a68003e5; threads_open: 0; action: escalated:risky-fix-needs-human-decision; head_sha: 0d35cb1.
