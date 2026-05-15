# hs-autofix does not resolve merge conflicts

- **Spec:** [docs/product-specs/033-hs-autofix-does-not-resolve-merge-conflicts.md](../../product-specs/033-hs-autofix-does-not-resolve-merge-conflicts.md)
- **Issue:** —
- **Status:** active
- **PR:** —
- **Branch:** —

## Summary

The `/hs-autofix` skill documents merge-conflict handling but isn't resolving conflicts in practice when invoked on a PR with conflicts against the base branch. This plan investigates the gap between documented behavior and observed behavior and proposes targeted fixes.

## Research

### Relevant code

- `~/.claude/skills/hs-autofix/SKILL.md:46-52` — Phase 1 detects conflicts via `git status` for **existing** unmerged paths. No code path initiates a merge/rebase against base to *produce* conflicts.
- `~/.claude/skills/hs-autofix/SKILL.md:79-87` — SAFE/RISKY classification, only runs once conflicts surface locally.
- `~/.claude/skills/hs-autofix/SKILL.md:226-235` — Merge-conflict rules (verification, granularity, in-place edits). Assumes a merge/rebase is already in progress.
- `~/.claude/skills/hs-review-loop/SKILL.md:38` — Fetches PR `mergeable` flag from GitHub but never acts on it.
- `~/.claude/skills/hs-review-loop/SKILL.md:73-76` — Invokes autofix only on `REQUEST_CHANGES`; no pre-check of mergeable state.
- `AGENTS.md:44-49` — Build/lint/test commands present; verification prerequisite for autofix is satisfied.

### Likely root cause (ranked)

1. **Autofix never initiates the merge/rebase that would surface conflicts.** It only inspects pre-existing unmerged paths; on a freshly-checked-out PR branch that is conflicted vs. base, `git status` is clean and autofix reports "nothing actionable."
2. **Review-loop fetches `mergeable` but ignores it.** No guard wires the GitHub-reported conflict state into autofix invocation.
3. **Silent fallthrough on zero local conflicts.** Even after a successful merge, autofix sees no unmerged paths and proceeds to other sources or exits.

### Constraints / dependencies

- `AGENTS.md` verification commands exist — not a blocker.
- `mergeable` is already fetched in review-loop — partial infra exists.
- Conflict resolution must remain bounded by the existing SAFE/RISKY policy and verification gate; we are fixing detection + initiation, not loosening rules.

### Open conflict scenarios to handle

- PR behind base (no overlapping edits) — fast-forward / clean merge possible.
- PR with mechanical conflicts (e.g. independent rows in decentralized index after #32 lands).
- PR with overlapping logic conflicts — must surface as RISKY/escalate.

## Approach

**Two-part fix. Reuse existing conflict-resolution machinery; close the detection + initiation gap.**

A. **Autofix proactively initiates the merge against base when GitHub reports the PR as `CONFLICTING`.** Today, Phase 1 Source (c) only triggers when `git status` already shows unmerged paths. Add a pre-flight step that, when a PR is in scope, queries `gh pr view --json mergeable,baseRefName`; if `CONFLICTING`, runs `git fetch origin <baseRef>` then `git merge --no-commit --no-ff origin/<baseRef>`. The merge surfaces conflicts locally, after which the existing Source (c) flow takes over unchanged. If the merge completes cleanly (branch was just behind), commit the merge and treat it as a single "branch updated" finding.

B. **Review-loop passes the `mergeable` signal into autofix invocation.** The `mergeable` field is already fetched on line 38 of `skills/review-loop/SKILL.md` but unused. Wire it: a `CONFLICTING` PR triggers autofix regardless of reviewer verdict (conflicts are blocking even when reviewers say LGTM). Add `mergeable: <state>` to the per-iteration ledger line.

**Why merge, not rebase.** The existing Source (c) and Phase 5 commit/verification rules handle both, but merge produces a single MERGE_HEAD state — flat, easy to reason about, easy to abort. Rebase replays N commits with N intermediate conflict states; recoverability and verification cost compound. The project squash-merges at land time (per CHANGELOG flow), so the extra merge commit on the feature branch is absorbed.

**Why not a separate `/conflict-resolver` skill.** Autofix already encodes `AGENTS.md` verification, SAFE/RISKY classification, in-place marker editing, and commit granularity for conflicts. A new skill would duplicate all of that. Reuse > new surface.

### Files to change

1. `skills/autofix/SKILL.md` — insert a new step **2.5** in Phase 1 between current step 2 (Determine the finding source) and step 3 (Normalize findings), gated on a PR being in scope:
   - Pre-flight checks: working tree clean (`git diff-index --quiet HEAD`), no existing `MERGE_HEAD`, no `.git/rebase-merge`/`.git/rebase-apply`. If any fails, skip with a one-line reason logged for Phase 5 output.
   - `gh pr view "$PR" --json mergeable,baseRefName,headRefName`. On `mergeable: UNKNOWN`, sleep 2s and retry once; if still `UNKNOWN`, skip pre-flight.
   - On `CONFLICTING`: `git fetch origin "$BASE"` then `git merge --no-commit --no-ff "origin/$BASE"`. Conflicts: fall through to Source (c) (no behavioral change to existing flow). Clean merge: stage with `git commit -m "merge: bring branch up to date with $BASE"`, queue a synthetic finding `{source: preflight-merge, severity: INFO, description: "Branch was behind base; merged cleanly"}` so Phase 5 reports it.
   - On `MERGEABLE` / `MERGEABLE_AND_UP_TO_DATE`: skip pre-flight silently.
   - Update Source (c) prose to note it is now reachable from both natural conflict state *and* the pre-flight initiator.

2. `skills/review-loop/SKILL.md` — at the autofix invocation site (currently gated on `REQUEST_CHANGES` around lines 73–76):
   - Add an OR condition: invoke autofix when verdict is `REQUEST_CHANGES` **or** `mergeable == CONFLICTING`.
   - Extend the ledger entry format (around line 61 of the plan template, mirrored in review-loop) to include `mergeable: <state>` alongside `verdict`/`findings_hash`/`action`/`head_sha`.
   - Document the new invocation reason in the action vocabulary (e.g. `action: autofix+push (conflict)`).

### New files

None.

### Tests

The autofix/review-loop skills are markdown specifications consumed by an LLM; the project has no unit test harness for them (review-pr uses an LLM judge in `skills/review-pr/fixtures/`). Verification strategy:

- **Render correctness gate** (already in `AGENTS.md`): `./install.sh` then `grep -q '/hs-autofix' .rendered/...` must stay green. Re-run after edits.
- **Changelog gate:** add a `[Unreleased]` entry under `## Skills` describing the fix; CI's changelog non-empty gate enforces presence.
- **Manual verification recipe** (recorded in this plan's Progress section after implementation):
  1. Branch off main, make a trivial commit, push.
  2. On main, push a conflicting commit to the same file/line.
  3. Open a PR; wait for GitHub to mark it `CONFLICTING`.
  4. Run `/hs-autofix <PR#>` from a fresh agent. Verify it initiates `git merge`, surfaces the conflict, classifies SAFE/RISKY correctly, resolves SAFE, and pushes.
  5. Repeat with a clean-merge scenario (PR behind but no overlapping edits) — verify "branch updated, no resolution needed" finding.
  6. Repeat invoking via `/hs-review-loop <PR#>` with an LGTM review already on the PR — verify autofix still fires due to the conflict.
- **`shellcheck` + brain tests:** no shell changes, but run the full `AGENTS.md` lint/test set to confirm no regressions.

## Open questions

- **Squash assumption.** If a future contributor uses merge-commit landing, the pre-flight merge commit will persist on main. Mitigation: explicit commit subject prefix `merge:` so it's filterable; document the assumption in `skills/autofix/SKILL.md`.
- **`UNKNOWN` mergeable state.** GitHub computes `mergeable` lazily. We retry once after 2s; if still unknown, we skip pre-flight rather than block. Acceptable degradation — the next review-loop iteration will retry.
- **Review threads vs conflicts ordering.** Source (c) currently runs alongside (a)/(b). With the pre-flight, conflicts effectively run first. Confirm this matches the "boil the lake" stance: yes, resolving conflicts before applying review fixes prevents wasted work on a soon-to-be-rewritten file.



## Decision log

- **2026-05-15** — Use `git merge`, not `git rebase`, for the pre-flight initiator. Why: flat MERGE_HEAD state is easier to reason about and abort than N replayed commits; project squash-merges absorb the extra merge commit at land time.
- **2026-05-15** — `mergeable == CONFLICTING` always routes to autofix in review-loop, regardless of verdict. Why: conflicts block merge even on LGTM; without this, an LGTM'd-but-conflicted PR stalls indefinitely.
- **2026-05-15** — `mergeable: UNKNOWN` degrades gracefully (single retry, then skip). Why: GitHub computes mergeability lazily; blocking on UNKNOWN would either stall the loop or require unbounded retries. Next iteration retries naturally.

## Progress

- **2026-05-15** — Spec triaged (bug / M / P2); exec plan created at RESEARCH.
- **2026-05-15** — Plan approved via `/hs-plan-html` (no edits); advanced to IMPLEMENT.
- **2026-05-15** — Implemented in `skills/autofix/SKILL.md` (Phase 1 step 2.5 + Source-list extension), `skills/review-loop/SKILL.md` (worker prompt step 1 + step 5 routing + envelope + ledger format), three plan/feature templates synced for ledger row format, CHANGELOG `[Unreleased]` entry under `### Fixed`, `.gitignore` excludes `.plans/`.

## Open questions

## PR convergence ledger

## QA verdict
