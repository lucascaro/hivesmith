# Make feature-loop autonomous by default

- **Spec:** [docs/product-specs/064-make-feature-loop-autonomous-by-default.md](../../product-specs/064-make-feature-loop-autonomous-by-default.md)
- **Issue:** #64
- **Status:** active
- **PR:** #65
- **Branch:** feature/64-autonomous-feature-loop

## Summary

Rewrite `skills/feature-loop/SKILL.md` so the autonomous path is the only path: `--full-auto` and the `plan` keyword are removed, triage stops being a gate, clarifying questions bracket the research phase, the plan draft carries a reviewer-subagent second opinion, and the run continues unattended from plan approval through `/merge-gate`, stopping only at the merge. Add hive-brain read (before planning) and write (after gate PASS). Also retire the now-obsolete spec/plan #20.

## Research

### Relevant code

- `skills/feature-loop/SKILL.md` (329 lines) — the entire artifact. Structure: frontmatter, intro, Input list, GitHub-issue gating rule, `## Full-auto mode` (lines 24–67), Layout resolution, Phase 0 (identify), Phase 1 (new issue), Phase 1P (plan-first), Phases 2–8, Rules, Anti-injection rule. Gate numbering 1–6 is referenced from the Rules section and from `docs/product-specs/036`.
- `skills/review-loop/SKILL.md:116-135` — the existing brain-append call site and its `~/.hivesmith/bin/brain-append` invocation shape, including the "do not append on escalation" rule. This is the pattern to copy for Phase 8.
- `templates/brain/SCHEMA.md` — brain entry front-matter contract: `slug`, `scope`, `repo`, `tags`, `provenance.{source,session,pr,trusted}`, `confidence`, `created`. Body is `Lesson / Why / How to apply`, no code dumps.
- `skills/plan-html/SKILL.md` — the canonical call sequence Phase 4 already delegates to for plan rendering + approval. Unchanged by this work; the loop keeps calling it.
- `AGENTS.md` — pipeline description names the stage skills and the canonical lifecycle; the feature-loop entry in the skill list needs no change, but the CHANGELOG/changeset does.
- `docs/product-specs/020-*.md` + `docs/exec-plans/active/020-*.md` — stale at `stage: IMPLEMENT` even though PR #21 is MERGED. Their subject (`--full-auto`) is deleted by this change.
- `.changesets/` — per-PR changelog fragments; CI fails when `[Unreleased]` is empty, and `scripts/regen-generated.sh` aggregates changesets + spec frontmatter on push to `main`.

### Constraints / dependencies

- The skill is pure prompt text — there is no runtime to unit-test. Verification is grep-shaped assertions over the source and the rendered install output (`.rendered/hs-/skills/hs-feature-loop/SKILL.md`), matching how spec #20 verified the same file.
- Skill sources must reference sibling skills **unprefixed** (`/review-loop`, `/merge-gate`); `install.sh` rewrites them per-prefix at render time. The render-correctness check in `AGENTS.md` guards this.
- `docs/product-specs/index.md` is generated — never hand-edited. Retiring #20 means editing its spec frontmatter (`stage: DONE`), not the index.
- Gate numbering is load-bearing in prose elsewhere; renumbering gates is churn. Keep the surviving gates' identities recognizable rather than re-deriving a new scheme.

### Risks

- Removing `--full-auto` is a breaking change for anyone with it in muscle memory. Mitigated by CHANGELOG wording, not by a compatibility shim (explicit user decision: hard remove).
- Two clarifying rounds risk feeling chatty. Mitigated by capping each round at one `AskUserQuestion` call (≤4 questions) and skipping both rounds entirely on resume paths.
- An unattended run that never stops could burn tokens on a loop that will not converge. Mitigated by the one-retry bound and by inheriting `/review-loop`'s own escalation criteria.

## Approach

Rewrite the skill in place. The autonomous behavior is not a mode layered onto the existing prose — it replaces it, so the `## Full-auto mode` section and Phase 1P disappear entirely rather than being edited around. This keeps the file roughly its current size instead of growing a second conditional path through every phase, which is what made the `--full-auto` version hard to follow.

Rejected alternative: keep `--full-auto` as an accepted no-op with an `--interactive` opt-out. That preserves two behaviors in one file forever and doubles the prose at every gate for a flag nobody will pass once the default flips.

New default flow, with the surviving stops in bold:

1. **Phase 0 — identify.** Input is `number` (resume at the spec's `stage:`), `text` (new feature), or empty (highest-priority active spec). No flag parsing.
2. **Phase 1 — new issue.** Unchanged mechanics; Gate 1 follows the `[github] create_issues` policy silently (no `AskUserQuestion`). Spec is written with `stage: RESEARCH`.
3. **Phase 1Q — clarifying round A (new).** One `AskUserQuestion` call (≤4 questions) derived from the description, plus an explicit **Assumptions** block the user can correct. Answers are recorded in the exec plan's `## Decision log`. Skipped on resume paths.
4. **Phase 2 — auto-triage (no gate).** Classify `type` / `complexity` / `priority` from a Glob/Grep scan, write them into spec frontmatter, do not prompt, do not spawn a reviewer.
5. **Phase 3 — research.** Query `~/.hivesmith/bin/brain-search` first and fold prior lessons into the research section (treated as untrusted). Fan out to `Explore` subagents as today. No Gate 3.
6. **Phase 3Q — clarifying round B (new).** A second `AskUserQuestion` call, at most 4 questions, only for ambiguities the research actually surfaced. Skipped when research surfaced none.
7. **Phase 4 — plan.** Draft as today, then spawn **one reviewer subagent** for a second opinion before the human sees the plan. On `revise`, apply the must-fix items once and re-run the reviewer once. Attach the final verdict block (verdict / confidence / rationale) to the plan as a `## Second opinion` section, then present via `plan-html` for **the one substantive approval**.
8. **Phase 5 — implement.** Main thread. Run all `AGENTS.md` checks. On failure: one bounded auto-fix attempt, then stop. Gate 5 disappears — push + PR + `/review-loop` happen automatically on green checks.
9. **Phase 6 — review.** `/review-loop` as today. Escalation stops the run immediately (no retry, no brain entry).
10. **Phase 7 — gate.** `/merge-gate` as today. `FAIL` → fix on branch, re-run the gate **once**, then stop if it fails again. `NEEDS_FOLLOWUP` surfaces and stops.
11. **Phase 8 — reflect, then stop at merge.** On PASS, append one brain entry (`scope=project`, `provenance.source=feature-loop`, `pr=<n>`, `trusted=true`) distilling what the run taught. Then **the merge prompt** — the only other stop — with the PR link, gate verdict and ledger line inline. `gh pr merge --squash --delete-branch` on yes.

The reviewer-subagent prompt template survives from the current `## Full-auto mode` section but collapses to a single gate (plan review), so the Gate 2/3 branches and the confidence-threshold fallback table go away. The threshold stays 8/10 for deciding whether to auto-apply a `revise` pass; it no longer decides whether to prompt the human, because the human is prompted either way.

### Files to change

**The skill itself**

- `skills/feature-loop/SKILL.md` — full rewrite per the flow above. Frontmatter: `argument-hint: "[issue-number | description]"`, `description` updated.

**Changesets — `--full-auto` and `plan` never shipped**

Both are still pending fragments in `[Unreleased]` (`CHANGELOG.md:8-9`). Shipping a *removal* note alongside them would announce and retract the same feature in one release.

- `.changesets/002-feature-loop-skill-full-auto-flag.md` — delete.
- `.changesets/003-feature-loop-plan-first-mode.md` — delete.
- `CHANGELOG.md` — never hand-edited; `scripts/regen-generated.sh` re-aggregates from `.changesets/` on push to `main`.

**Docs that describe the old flow**

- `README.md:40` — skill table row still reads "…→ DONE with confirmation gates"; update the flow and drop the gates wording.
- `README.md:41` — `/plan-html` row cites `feature-loop plan ...` as its caller; Phase 4 becomes the only caller.
- `skills/plan-html/SKILL.md:16,47,53` and `skills/plan-html/README.md:7,27` — same `/feature-loop plan <description>` entry point.
- `templates/AGENTS.hivesmith.md:8` and `skills/hivesmith-init/SKILL.md:84` — both say `/feature-loop` confirms at Gate 1. Under the new silent-policy Gate 1 that is false for `/feature-loop` (still true for `/feature-new`); reword to name `/feature-new` for the confirm behavior and note feature-loop follows the policy without prompting except under `ask`.

**Cross-references a rewrite invalidates**

Four sibling skills cite feature-loop by step number. Replace the step numbers with phase names so future rewrites cannot silently break them.

- `skills/merge-gate/SKILL.md:22` ("`/feature-loop` step 40") and `:105` (Gate 6).
- `skills/review-loop/SKILL.md:175` ("`/feature-loop` step 46 is verify-only").
- `skills/feature-implement/SKILL.md:62` (Gate 6).

**Superseding #20**

- `docs/product-specs/020-add-full-auto-flag-to-hs-feature-loop-skill.md` — `stage: DONE`, `pr: 21`, `shipped:` the merge date of PR #21, `## Notes` line pointing at #64. (`docs/product-specs/index.md` is generated on push to `main`, so `stage: DONE` is the verifiable proxy for the index row disappearing.)
- `docs/exec-plans/active/020-*.md` → `docs/exec-plans/completed/` (`git mv`), `Status: completed`, one `## Progress` supersession line.

### New files

- `.changesets/064-feature-loop-autonomous-by-default.md` — describes the autonomous default as a *new* behavior (not a removal), since neither `--full-auto` nor plan-first has been released.

### Resolved design details

- **Gate 1 under `[github] create_issues = ask`.** `ask` is documented as "no default; prompt every time" (`templates/AGENTS.hivesmith.md:8`), so "follow the policy silently" is undefined there. Under `ask`, Gate 1 **prompts** — a conditional third stop, present only for projects that opted into it. Every other policy value resolves silently.
- **Reviewer `verdict: block`.** The plan is still presented to the human (they are prompted either way now), but the block verdict and its rationale lead the `## Second opinion` section and the approval prompt says the reviewer wants the plan reconsidered. `block` never auto-applies fixes and never skips presentation.
- **Brain append invocation.** `provenance.source` is read from `HIVESMITH_SKILL` (`scripts/brain/append.sh:45`) and every sibling hardcodes the `hs-` prefix (`skills/review-loop/SKILL.md:128`), so the call is `HIVESMITH_SKILL=hs-feature-loop ~/.hivesmith/bin/brain-append --scope project --pr <n> …`.
- **Brain retrieval is bounded and delegated.** The Phase 3 research subagent runs the lookup, not the main thread — raw entries never enter the orchestrator's context. `~/.hivesmith/bin/brain-search <terms> --rank --limit 8` returns one line per hit (slug/scope/path/first body line, per `scripts/brain/search.sh`); the subagent `brain-read`s at most 3, only those with rank ≥2, and returns distilled bullets. Zero qualifying hits means zero reads and one line in the Research section. Scope-tagged retrieval already prevents a `project=A` lesson surfacing in a `project=B` session.
- **Brain writes are capped.** At most one entry per run, only on gate PASS, never on escalation. The redactor rejects code fences over 25 lines; entries carry `valid_until` so `/brain-garden` archives them. The run writes only a lesson a future run would act on differently — not "implemented feature X", which is what the exec plan and git history already record.
- **Phase 0 `DONE` + open-PR resume path** (`skills/feature-loop/SKILL.md:96`) survives the rewrite verbatim — it is the only way to finish a merge after the operator declines it.

### Tests

The artifact is prompt text; the checks are assertions over the source and the rendered output, in the style spec #20 used. Each assertion below fails on a plausibly-wrong rewrite, not just on today's file.

- Removals: `! grep -q -- '--full-auto'`, `! grep -qi 'plan-first'`, `! grep -q 'Approve this triage classification'` (triage gate gone), `! grep -q 'Push branch, open PR'` (Gate 5 gone).
- Additions: `grep -q '## Second opinion'`, `grep -q 'subagent_type'`, `grep -q 'Merge the PR now'` (merge stop survives), `grep -q 'brain-search'`, `grep -q 'brain-append'`, `grep -q 'argument-hint: "\[issue-number | description\]"'`.
- Stale-doc sweep: `! grep -rn 'feature-loop plan ' README.md skills/plan-html/`.
- Render correctness: after a real install, `.rendered/hs-/skills/hs-feature-loop/SKILL.md` contains `/hs-review-loop` and not `/review-loop`.

## Verification

```bash
# 1. Source-level assertions — removals
! grep -q -- '--full-auto' skills/feature-loop/SKILL.md
! grep -qi 'plan-first' skills/feature-loop/SKILL.md
! grep -q 'Approve this triage classification' skills/feature-loop/SKILL.md
! grep -q 'Push branch, open PR' skills/feature-loop/SKILL.md

# 2. Source-level assertions — additions
grep -q 'argument-hint: "\[issue-number | description\]"' skills/feature-loop/SKILL.md
grep -q '## Second opinion' skills/feature-loop/SKILL.md
grep -q 'subagent_type' skills/feature-loop/SKILL.md
grep -q 'Merge the PR now' skills/feature-loop/SKILL.md
grep -q 'brain-search' skills/feature-loop/SKILL.md
grep -q 'brain-append' skills/feature-loop/SKILL.md

# 3. Stale docs swept, unreleased changesets retired
! grep -rn 'feature-loop plan ' README.md skills/plan-html/
! test -f .changesets/002-feature-loop-skill-full-auto-flag.md
! test -f .changesets/003-feature-loop-plan-first-mode.md
! grep -rn -- '--full-auto' README.md templates/ skills/ --include='*.md'

# 4. #20 superseded (index.md regenerates on push to main; stage is the proxy)
grep -q '^stage: DONE' docs/product-specs/020-add-full-auto-flag-to-hs-feature-loop-skill.md
test -f docs/exec-plans/completed/020-add-full-auto-flag-to-hs-feature-loop-skill.md

# 5. AGENTS.md lint + tests (explicit shellcheck list per AGENTS.md, mirrors CI)
shellcheck install.sh scripts/brain/*.sh scripts/brain/test/run-all.sh scripts/dev-link-local.sh \
  scripts/harvest/*.sh scripts/hooks/pre-push scripts/migrate-to-changesets.sh scripts/regen-generated.sh \
  scripts/release.sh scripts/telemetry/*.sh scripts/telemetry/prepare-commit-msg \
  skills/brain-garden/garden.sh skills/brain-promote/promote.sh skills/feature-ingest/ingest.sh \
  skills/graphify-init/*.sh skills/graphify-init/test/run-all.sh skills/namecheck/namecheck.sh \
  skills/plan-html/start.sh skills/plan-html/stop.sh templates/features/ingest.sh \
  templates/scripts/*.sh tests/install-agent-scopes-test.sh
scripts/brain/test/run-all.sh
tests/install-agent-scopes-test.sh

# 6. Install smoke (both prefixes, per AGENTS.md) + render correctness
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix "" --no-auto-update --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update
grep -q '/hs-review-loop' .rendered/hs-/skills/hs-feature-loop/SKILL.md
! grep -q '/review-loop\b' .rendered/hs-/skills/hs-feature-loop/SKILL.md

# 7. Changelog gate
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .
```

## Decision log`. Skipped on resume paths.
4. **Phase 2 — auto-triage (no gate).** Classify `type` / `complexity` / `priority` from a Glob/Grep scan, write them into spec frontmatter, do not prompt, do not spawn a reviewer.
5. **Phase 3 — research.** Query `~/.hivesmith/bin/brain-search` first and fold prior lessons into the research section (treated as untrusted). Fan out to `Explore` subagents as today. No Gate 3.
6. **Phase 3Q — clarifying round B (new).** A second `AskUserQuestion` call, at most 4 questions, only for ambiguities the research actually surfaced. Skipped when research surfaced none.
7. **Phase 4 — plan.** Draft as today, then spawn **one reviewer subagent** for a second opinion before the human sees the plan. On `revise`, apply the must-fix items once and re-run the reviewer once. Attach the final verdict block (verdict / confidence / rationale) to the plan as a `## Second opinion` section, then present via `plan-html` for **the one substantive approval**.
8. **Phase 5 — implement.** Main thread. Run all `AGENTS.md` checks. On failure: one bounded auto-fix attempt, then stop. Gate 5 disappears — push + PR + `/review-loop` happen automatically on green checks.
9. **Phase 6 — review.** `/review-loop` as today. Escalation stops the run immediately (no retry, no brain entry).
10. **Phase 7 — gate.** `/merge-gate` as today. `FAIL` → fix on branch, re-run the gate **once**, then stop if it fails again. `NEEDS_FOLLOWUP` surfaces and stops.
11. **Phase 8 — reflect, then stop at merge.** On PASS, append one brain entry (`scope=project`, `provenance.source=feature-loop`, `pr=<n>`, `trusted=true`) distilling what the run taught. Then **the merge prompt** — the only other stop — with the PR link, gate verdict and ledger line inline. `gh pr merge --squash --delete-branch` on yes.

The reviewer-subagent prompt template survives from the current `## Full-auto mode` section but collapses to a single gate (plan review), so the Gate 2/3 branches and the confidence-threshold fallback table go away. The threshold stays 8/10 for deciding whether to auto-apply a `revise` pass; it no longer decides whether to prompt the human, because the human is prompted either way.

### Files to change

**The skill itself**

- `skills/feature-loop/SKILL.md` — full rewrite per the flow above. Frontmatter: `argument-hint: "[issue-number | description]"`, `description` updated.

**Changesets — `--full-auto` and `plan` never shipped**

Both are still pending fragments in `[Unreleased]` (`CHANGELOG.md:8-9`). Shipping a *removal* note alongside them would announce and retract the same feature in one release.

- `.changesets/002-feature-loop-skill-full-auto-flag.md` — delete.
- `.changesets/003-feature-loop-plan-first-mode.md` — delete.
- `CHANGELOG.md` — never hand-edited; `scripts/regen-generated.sh` re-aggregates from `.changesets/` on push to `main`.

**Docs that describe the old flow**

- `README.md:40` — skill table row still reads "…→ DONE with confirmation gates"; update the flow and drop the gates wording.
- `README.md:41` — `/plan-html` row cites `feature-loop plan ...` as its caller; Phase 4 becomes the only caller.
- `skills/plan-html/SKILL.md:16,47,53` and `skills/plan-html/README.md:7,27` — same `/feature-loop plan <description>` entry point.
- `templates/AGENTS.hivesmith.md:8` and `skills/hivesmith-init/SKILL.md:84` — both say `/feature-loop` confirms at Gate 1. Under the new silent-policy Gate 1 that is false for `/feature-loop` (still true for `/feature-new`); reword to name `/feature-new` for the confirm behavior and note feature-loop follows the policy without prompting except under `ask`.

**Cross-references a rewrite invalidates**

Four sibling skills cite feature-loop by step number. Replace the step numbers with phase names so future rewrites cannot silently break them.

- `skills/merge-gate/SKILL.md:22` ("`/feature-loop` step 40") and `:105` (Gate 6).
- `skills/review-loop/SKILL.md:175` ("`/feature-loop` step 46 is verify-only").
- `skills/feature-implement/SKILL.md:62` (Gate 6).

**Superseding #20**

- `docs/product-specs/020-add-full-auto-flag-to-hs-feature-loop-skill.md` — `stage: DONE`, `pr: 21`, `shipped:` the merge date of PR #21, `## Notes` line pointing at #64. (`docs/product-specs/index.md` is generated on push to `main`, so `stage: DONE` is the verifiable proxy for the index row disappearing.)
- `docs/exec-plans/active/020-*.md` → `docs/exec-plans/completed/` (`git mv`), `Status: completed`, one `## Progress` supersession line.

### New files

- `.changesets/064-feature-loop-autonomous-by-default.md` — describes the autonomous default as a *new* behavior (not a removal), since neither `--full-auto` nor plan-first has been released.

### Resolved design details

- **Gate 1 under `[github] create_issues = ask`.** `ask` is documented as "no default; prompt every time" (`templates/AGENTS.hivesmith.md:8`), so "follow the policy silently" is undefined there. Under `ask`, Gate 1 **prompts** — a conditional third stop, present only for projects that opted into it. Every other policy value resolves silently.
- **Reviewer `verdict: block`.** The plan is still presented to the human (they are prompted either way now), but the block verdict and its rationale lead the `## Second opinion` section and the approval prompt says the reviewer wants the plan reconsidered. `block` never auto-applies fixes and never skips presentation.
- **Brain append invocation.** `provenance.source` is read from `HIVESMITH_SKILL` (`scripts/brain/append.sh:45`) and every sibling hardcodes the `hs-` prefix (`skills/review-loop/SKILL.md:128`), so the call is `HIVESMITH_SKILL=hs-feature-loop ~/.hivesmith/bin/brain-append --scope project --pr <n> …`.
- **Brain retrieval is bounded and delegated.** The Phase 3 research subagent runs the lookup, not the main thread — raw entries never enter the orchestrator's context. `~/.hivesmith/bin/brain-search <terms> --rank --limit 8` returns one line per hit (slug/scope/path/first body line, per `scripts/brain/search.sh`); the subagent `brain-read`s at most 3, only those with rank ≥2, and returns distilled bullets. Zero qualifying hits means zero reads and one line in the Research section. Scope-tagged retrieval already prevents a `project=A` lesson surfacing in a `project=B` session.
- **Brain writes are capped.** At most one entry per run, only on gate PASS, never on escalation. The redactor rejects code fences over 25 lines; entries carry `valid_until` so `/brain-garden` archives them. The run writes only a lesson a future run would act on differently — not "implemented feature X", which is what the exec plan and git history already record.
- **Phase 0 `DONE` + open-PR resume path** (`skills/feature-loop/SKILL.md:96`) survives the rewrite verbatim — it is the only way to finish a merge after the operator declines it.

### Tests

The artifact is prompt text; the checks are assertions over the source and the rendered output, in the style spec #20 used. Each assertion below fails on a plausibly-wrong rewrite, not just on today's file.

- Removals: `! grep -q -- '--full-auto'`, `! grep -qi 'plan-first'`, `! grep -q 'Approve this triage classification'` (triage gate gone), `! grep -q 'Push branch, open PR'` (Gate 5 gone).
- Additions: `grep -q '## Second opinion'`, `grep -q 'subagent_type'`, `grep -q 'Merge the PR now'` (merge stop survives), `grep -q 'brain-search'`, `grep -q 'brain-append'`, `grep -q 'argument-hint: "\[issue-number | description\]"'`.
- Stale-doc sweep: `! grep -rn 'feature-loop plan ' README.md skills/plan-html/`.
- Render correctness: after a real install, `.rendered/hs-/skills/hs-feature-loop/SKILL.md` contains `/hs-review-loop` and not `/review-loop`.

## Verification

```bash
# 1. Source-level assertions
! grep -q -- '--full-auto' skills/feature-loop/SKILL.md
! grep -qi 'plan-first' skills/feature-loop/SKILL.md
grep -q 'brain-search' skills/feature-loop/SKILL.md
grep -q 'brain-append' skills/feature-loop/SKILL.md
! grep -q 'Push branch, open PR' skills/feature-loop/SKILL.md

# 2. No stale active row for #20
grep -q '^stage: DONE' docs/product-specs/020-add-full-auto-flag-to-hs-feature-loop-skill.md
test -f docs/exec-plans/completed/020-add-full-auto-flag-to-hs-feature-loop-skill.md

# 3. AGENTS.md lint + tests
shellcheck $(git ls-files '*.sh' | tr '\n' ' ')
scripts/brain/test/run-all.sh
tests/install-agent-scopes-test.sh

# 4. Install smoke + render correctness
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update
grep -q '/hs-review-loop' .rendered/hs-/skills/hs-feature-loop/SKILL.md
! grep -q '/review-loop\b' .rendered/hs-/skills/hs-feature-loop/SKILL.md

# 5. Changelog gate
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .
```

## Decision log

- **2026-09-04** — Hard-remove `--full-auto` and `plan` rather than accepting them as no-ops. Why: operator decision; a compatibility shim would preserve two behaviors in one prompt file indefinitely.
- **2026-09-04** — New runs start at RESEARCH; triage is auto-classified with no gate. Why: operator decision — triage exists to populate spec frontmatter for the index, not to extract a human judgment.
- **2026-09-04** — Clarifying questions in two rounds (before research, after research). Why: operator decision — the up-front round scopes the research, the second round asks the sharper questions research surfaced.
- **2026-09-04** — Implementation stays in the main thread; subagents used for research fan-out and the plan second opinion only. Why: a subagent implementer sees the plan text but not the conventions, which is the classic quality regression.
- **2026-09-04** — Self-reflection is appended after gate PASS and *before* the merge prompt. Why: the lesson survives even if the operator never returns to merge.
- **2026-09-04** — Stalls get exactly one bounded auto-retry (gate FAIL, failed check); review-loop escalation gets none. Why: escalated runs are already flagged unreliable by `/review-loop`, which is also why it refuses to write a brain entry on escalation.

## Second opinion

Reviewer subagent (`general-purpose`), run before the plan was presented for approval:

- **verdict:** revise — **confidence:** 8/10
- **rationale:** Approach covers every success-criteria bullet and stays inside the Non-goals, but the blast radius was materially incomplete (two *unreleased* changesets for the very features being removed, five docs still describing the old flow, four step-number cross-references from sibling skills) and two verification assertions were vacuous.
- **disposition:** all six must-fix items applied above (blast radius expanded, changesets 002/003 retired, `ask`-policy Gate 1 defined, `block` verdict path defined, assertions replaced with ones that fail on a wrong rewrite). All five nice-to-haves also applied.

## Progress

- **2026-09-04** — Plan feedback round 1: "how do we make sure this doesn't just bloat the context with irrelevant stuff?" — answered by bounding brain retrieval (delegated to the research subagent, `--rank --limit 8`, ≤3 full reads) and capping writes at one entry per run. Folded into Resolved design details.
- **2026-09-04** — Implemented: skill rewritten (285 lines), blast radius swept (README, plan-html docs, hivesmith-init, AGENTS template, four cross-references), changesets 002/003 retired, spec/plan #20 superseded to DONE. All AGENTS.md checks green.
- **2026-09-04** — Spec + exec plan scaffolded from `/feature-loop`; issue #64 opened; branch `feature/64-autonomous-feature-loop` created.

## Open questions

None — resolved in the two clarifying rounds.

## PR convergence ledger

## Gate verdict
