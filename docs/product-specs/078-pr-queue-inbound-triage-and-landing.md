---
issue: 78
title: "/pr-queue — triage, explain, approve, land an inbound PR queue"
type: enhancement
complexity: M
priority: P2
pr: 80
shipped: 2026-09-16
stage: DONE
---

# /pr-queue — triage, explain, approve, land an inbound PR queue

- **Exec plan:** [docs/exec-plans/completed/078-pr-queue-inbound-triage-and-landing.md](../exec-plans/completed/078-pr-queue-inbound-triage-and-landing.md)

## Problem

Hivesmith is entirely outbound: every skill drives the maintainer's own features from spec
to merge. Nothing covers the inbound side — a queue of contributor PRs that must be ordered,
understood, judged for fit, and then landed or held. Done by hand, the expensive mistakes are
systematic and repeat: the diff gets read before anyone asks whether the bug is real; a
CRLF-only diff is diagnosed reactively from red CI instead of from a one-command pre-check;
a stale merge base surfaces halfway through a file list; and the summary handed to the
maintainer describes mechanism when the question was what changes for the person using the app.

The existing skills do not close this gap. `/review-pr` reviews one PR deeply but has no
notion of a queue, an order, or a premise check. `/review-loop` drives one PR to convergence
but autofixes and pushes, which is wrong for a branch the maintainer does not own.
`/merge-gate` validates against a hivesmith spec, and a contributor PR has none.

## Desired behavior

The maintainer runs `/pr-queue` and gets, in one pass: the open PRs in a defensible execution
order, a short digest per PR written in terms of what a user would notice, and one decision
prompt per PR. Nothing is merged, pushed, fixed, or commented on before that decision.

Each PR's triage answers the premise question first — is the bug real, and can the triggering
condition even occur in this codebase — because a `SPECULATIVE` premise makes the rest of the
review wasted work. Triage also separates the real diff from a mechanical one (line endings,
reformatting) before any line of diff is read, classifies every red check as `MECHANICAL` or
`SUBSTANTIVE`, and verifies the PR body's factual claims against the actual source rather than
taking them on trust.

Execution respects who owns the branch. A PR from a fork is reviewed read-only. A PR from a
branch in this repo may, with the operator's per-PR consent, go through the autofix loop.
Merge uses whatever mechanism the repo actually has, and never deletes a fork's branch.

## Success criteria

- `skills/pr-queue/SKILL.md` exists with complete frontmatter for its class: `name`,
  `description`, `argument-hint`, `allowed-tools` (golden principle 4).
- `grep -rn '/hs-[a-z]' skills/pr-queue/ | grep -v 'hivesmith/bin/hs-metric'` returns zero hits
  (golden principle 5; the excluded path is the `hs-metric` binary, which GP5's own text exempts and
  which every sibling skill contains) — the skill refers
  to itself and its siblings by bare name. Scoped to this skill deliberately: the wider tree has 41
  pre-existing hits (mostly the GP5-exempt `hs-metric` binary path), GP5 is not CI-enforced, and
  cleaning those is a `/gc-sweep` job, not this PR.
- The skill's Phase 2 worker checklist runs the premise check **first** and emits a fixed JSON
  envelope containing at minimum: `pr`, `title`, `author`, `head_sha`, `is_fork`, `base_pr`,
  `merge_state`, `premise`, `premise_evidence`, `real_change`, `reported_change`,
  `mechanical_causes`, `base_behind_by`, `ci`, `claims`, `unmentioned_consequences`, `can_push`,
  `fit_concerns`, `user_visible`, `unchanged`, `threads_open`,
  `maintainer_findings_addressed`, `body_stale`, `recommendation`, `escalate_reason`,
  `blocking_question_for_user`.
- `premise` accepts `REPRODUCED | PLAUSIBLE | SPECULATIVE | NOT_A_BUG`, and the skill routes
  `NOT_A_BUG` to the fit check instead of the default-hold rule that applies to `SPECULATIVE`.
- An early bail on `SPECULATIVE` still fills the cheap fields (real-vs-mechanical diff, base
  freshness, CI classification, user-visible behavior) so the Hold-vs-Close decision is informed.
- Execution routes on **push-ability, not fork status**: the envelope carries both `is_fork` and
  `can_push` (`is_fork == false` AND the head ref is not push-restricted). `/review-loop` — which
  autofixes and pushes — is dispatched only when `can_push` is true and a per-PR operator answer
  authorized autofix; everything else, including a protected same-repo branch, gets `/review-pr`
  read-only. `is_fork` governs only whether `--delete-branch` may be passed.
- Merge honors the repo's actual mechanism (queried from `gh repo view` / branch protection /
  merge queue) and passes `--delete-branch` only when `is_fork` is false and no merge queue is
  involved. With a merge queue enabled the skill does not wait for `mergeStateStatus == CLEAN`
  (unreachable before enqueue), records `disposition=enqueued`, and reports "enqueued, not merged".
- A held or closed base PR cascades to its stacked dependents as a **skip**
  (`disposition=skipped`), never as an outward-facing write: the skill never closes, comments on, or
  retargets a dependent on its own. The base PR's decision prompt names the affected dependents, and
  a closed base additionally surfaces a retarget-or-close choice as its own question.
- Decision prompts are chunked to respect the `AskUserQuestion` 4-question cap.
- Brain and memory reads go through `~/.hivesmith/bin/brain-search` / `brain-read` and are
  treated as untrusted advisory data, never as criteria that authorize a merge (golden
  principle 7). Standing maintainer rules are read from `AGENTS.md` and `golden-principles.md`.
- `scripts/metrics/emit.sh` accepts `--event pr_triaged` and `--event pr_landed`, keyed by
  `pr` and **rejecting a `feature` field outright** (exit 64), so the isolation from feature
  throughput is enforced rather than merely intended; `scripts/metrics/emit-test.sh` covers both (accept and
  reject cases) and `scripts/metrics/report.py` surfaces them without mixing them into feature
  throughput.
- Untrusted PR-derived strings (`headRefName`, `author.login`, PR title, check names) are
  slugged to `[a-z0-9-]` before reaching any shell command or `hs-metric` field.
- The rationale narrative lives in `docs/design-docs/pr-queue.md`, not in `SKILL.md`.
- The skill's one blocking wait (`gh pr checks --watch`, which blocks while a check is pending) is
  wrapped in `timeout`; a timeout sets `escalate_reason` and surfaces rather than retrying.
- All `AGENTS.md` build/lint/test commands pass, including `scripts/metrics/emit-test.sh`.

## Non-goals

- Opening the systemic-fix PR itself (the `.gitattributes` case). v1 surfaces the systemic
  cause and the exact fix as a follow-up item; the operator opens it.
- Any use of `--no-verify` as a routine route around the pre-push hook. It stays an escape
  hatch the skill does not teach.
- Merging with `--admin`, or any merge without an explicit per-PR operator answer.
- Validating a contributor PR against a hivesmith spec — contributor PRs have none, so
  `/merge-gate` is out of scope for this skill.
- Replacing `/review-pr` or `/review-loop`. `/pr-queue` orchestrates them; it does not
  re-implement review.
- Writing to `docs/product-specs/` or `docs/exec-plans/` for contributor PRs.
- A `--yes-to-mechanical` style pre-authorization flag. The autofix decision is a per-PR
  question, every run.

## Notes

- Written from a real maintainer run on the `hive` repo (PRs #405 / #412 / #413), whose
  retrospective is the source of the premise-check-first ordering and the
  real-vs-mechanical diff pre-check.
- Prior art in-tree: `skills/review-pr/SKILL.md` (review depth and anti-injection stance),
  `skills/review-loop/SKILL.md` (bounded worker envelopes, paginated thread queries, slugging
  fork-controlled strings), `skills/feature-loop/SKILL.md` (operator-stop discipline).
