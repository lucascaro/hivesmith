# Inbound PR queue

Why `/pr-queue` exists, why it triages before it reviews, and why it routes on push-ability rather
than fork status. Distilled from one real maintainer run and its retrospective, so a future agent
run does not re-derive it.

## The decision

Hivesmith was entirely outbound. Every skill drives the maintainer's own features from spec to
merge, and each one assumes a spec exists: `/merge-gate` validates against `## Success criteria`,
`/review-loop` looks for an exec plan to write its ledger into. A contributor's PR has none of that.
Worked by hand, the same expensive mistakes repeat.

`/pr-queue` is the inbound counterpart. It deliberately does **not** re-implement review —
`/review-pr` owns depth, `/review-loop` owns convergence — and owns only what neither has: an order
for the queue, and a cheap triage that decides whether depth is worth buying.

## The constraints that drove it

**A patch for a bug that cannot occur is not a small problem.** In the source run, two PRs hardened
the case "`localStorage` refuses the write." Nothing in that repo showed it happening: the origin
was a defensive test copied from a pre-existing private-mode idiom, and enumerating every `setItem`
call ruled out a quota-filling leak (largest write: one key capped at 400 entries). Both diffs had
already been read line by line by the time that question was asked. The cost was not one wasted
read — it was that a full review had been spent deciding *how well* something was fixed before
anyone asked whether it was broken. **The premise check therefore runs first, in cheap triage,
ahead of any line-by-line work.**

**Reported diff size is not change size.** One PR reported +7631/−7590 across 13 files. Diffing
whitespace-insensitively from the merge base showed 50 real lines; the rest was a CRLF conversion of
whole files, including files the PR never meant to touch. That single command decided the handling
of two PRs. It surfaced reactively, from red CI, when it is a one-command pre-check. **Raw `--stat`
versus `-w --ignore-cr-at-eol --stat` runs for every PR, in triage.**

**Mechanism is the answer to a question the maintainer did not ask.** The first summary in the
source run described what the code did. The follow-up — "does this still let me pick a dark theme
when my OS is light?" — revealed that the maintainer wanted to know what changes for the person
using the software. **Every summary carries a user-visible line, and "nothing visible" is a valid
answer that must be stated rather than omitted.**

**Fork status is not push-ability.** `/review-loop` invokes autofix and then `git push`
(`skills/review-loop/SKILL.md:78`). On a fork without maintainer-can-modify that push fails; worse,
where it succeeds it silently rewrites a contributor's branch. But the failing set is larger than
the fork set: a *same-repo* branch under branch protection is not a fork and still cannot be pushed
to, and there autofix has already committed by the time the push is rejected, with no defined
recovery. **Execution routes on `can_push`. `is_fork` governs exactly one thing: whether the branch
may be deleted at merge.**

**A merge queue inverts the pre-merge checklist.** With a queue enabled, required checks run inside
the queue *after* enqueue, so `mergeStateStatus == CLEAN` is never reachable and a checklist that
waits for it deadlocks. `gh pr merge` enqueues rather than merges, so there is also no SHA to
report. **The queue path records `disposition=enqueued`, waits for nothing, and does not delete the
branch.**

**"Cascade" must not mean "write."** A held or closed base PR leaves its stacked dependents
unmergeable, but auto-closing a contributor's PR is an outward-facing act. **The cascade is a skip;
the retarget-or-close choice goes to the operator.**

**Questions cost more than they look.** Four simultaneous decisions was already one too many, and
one of them could not be answered without an investigation that had not run yet. **Ask at most three
PR questions plus one systemic question per call, and never ask a question whose inputs are
incomplete.**

## Alternatives considered

**Extend `/review-pr` with a `--queue` flag.** Rejected. `/review-pr`'s entire contract is one diff,
one verdict, and read-only by construction — which is exactly why it is the right worker for a fork
PR. A queue needs ordering, per-PR human gating, and an execution phase that writes. Bolting those
onto a read-only reviewer would have compromised the property that makes it safe to point at
untrusted branches.

**Reuse `feature_done` / `gate_verdict` with `feature=<pr>` for metrics.** Rejected. It needs no
schema change, which is its only merit. Every existing event requires `feature`, a spec number; a
contributor PR has none, so the value would be a lie that `report.py` cannot detect. Contributor PRs
would enter this project's feature-throughput counts permanently and nothing downstream could
separate them again. The chosen design gives the queue its own `pr_triaged` / `pr_landed` events
carrying **no** `feature` field, which makes the isolation structural: `report.py`'s denominator is
built from rows that *have* a `feature`, so a feature-less row is excluded by construction rather
than by a filter someone must remember to maintain. `emit.sh` rejects a `feature` field on these
events outright, and a test asserts it.

**A `--yes-to-mechanical` flag pre-authorizing repairs.** Rejected by the maintainer. A standing
pre-authorization is the kind of flag whose blast radius is discovered later; whether to run autofix
is a per-PR question, every run.

**Open the systemic-fix PR automatically.** Deferred out of v1. In the source run that path is
precisely where `--no-verify` got normalized: the pre-push hook demanded a changeset, the hook's own
message documented the bypass, and the bypass became the route. v1 surfaces the cause and the exact
fix and lets the operator open it.

## Known ceilings

- `timeout 900` bounds this skill's own CI wait, but the delegated `hivesmith:review-loop` runs its
  own unwrapped `gh pr checks --watch` (`skills/review-loop/SKILL.md:78`). The `can_push` path
  inherits an unbounded wait. Filed against `review-loop` rather than patched from a caller —
  wrapping another skill's internals from outside is the wrong seam.
- Golden principle 5's detection grep matches the `~/.hivesmith/bin/hs-metric` binary path, which
  the principle's own text exempts. Every skill that emits metrics trips it. Worth either amending
  the principle or narrowing the grep; out of scope here.
- This skill ships with no graded fixture harness of the kind `skills/review-pr/fixtures/` provides.
  Its mechanical parts (schema, frontmatter, routing predicates) are covered by the exec plan's
  verification block; its judgment is not.
