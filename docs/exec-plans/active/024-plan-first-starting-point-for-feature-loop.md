# Plan-first starting point for hs-feature-loop

- **Spec:** [docs/product-specs/024-plan-first-starting-point-for-feature-loop.md](../../product-specs/024-plan-first-starting-point-for-feature-loop.md)
- **Issue:** #24
- **Stage:** IMPLEMENT
- **Status:** active
- **PR:** —
- **Branch:** —

## Summary

Add an optional `plan <description>` input form to `/feature-loop` that enters Claude Code's plan mode, iterates on the implementation plan with the user, then on approval scaffolds spec + exec plan + (per policy) GitHub issue + index row and advances directly to Stage = IMPLEMENT. TRIAGE / RESEARCH / PLAN gates are treated as auto-satisfied by the plan-mode approval.

## Research

### Relevant code

- `skills/feature-loop/SKILL.md:15-18` — current "Input" stanza: number / text / nothing. New `plan ...` form must slot in here.
- `skills/feature-loop/SKILL.md:31-45` — Phase 0 dispatch on `$ARGUMENTS`. Needs a new branch detecting `plan` keyword that routes to a new Phase 1P.
- `skills/feature-loop/SKILL.md:47-76` — Phase 1 (new issue). The scaffolding logic (issue draft + create, number allocation, duplicate check, filename slug, spec write from `_template.md`, index row append) is reusable verbatim for plan-first; we just run it *after* the plan is approved and we have a confirmed title.
- `skills/feature-loop/SKILL.md:99-121` — Phase 3 (Research) builds the exec plan from `docs/exec-plans/_template.md`. For plan-first we instead fill both Research and Approach from the accepted plan-mode output.
- `skills/feature-loop/SKILL.md:123-143` — Phase 4 (Plan). Plan-first replaces Gate 4 with plan-mode approval, then jumps over Gates 2–4.
- `skills/feature-plan/SKILL.md` — existing PLAN-stage skill; documents the "Approach" / "Files to change" / "Tests" / "Open questions" sections we should ask the user's plan-mode output to cover.
- `docs/product-specs/_template.md` — Type/Complexity/Priority are bullets, blank by default — plan-first must still ask the user for these (or default sensibly) since the plan-mode flow skips Gate 2.
- `docs/exec-plans/_template.md` — Stage field can be set directly to `IMPLEMENT` for plan-first.

### Constraints / dependencies

- **Plan-mode tool surface.** Claude Code exposes `EnterPlanMode` and `ExitPlanMode` (deferred tools per environment). The skill instructs the agent to enter plan mode before any file writes and to call `ExitPlanMode` for user approval. No writes may occur until ExitPlanMode is approved.
- **Triage info still needed.** Spec template requires Type / Complexity / Priority. We can either (a) auto-fill from the plan-mode output (Claude proposes, user reviewed implicitly in plan mode), or (b) ask via a single AskUserQuestion before scaffolding. Going with (a) — plan-mode approval is the gate; if user wants different triage they can edit the spec post-scaffold. Type defaults to `enhancement` and Priority to `P2` unless the plan-mode discussion settled on something else.
- **GitHub issue policy gate** in Phase 1 (step 3a, `.hivesmith/config.toml [github] create_issues`) still applies — the plan-first scaffolding must respect `opt-out` / `opt-in` / `ask`.
- **GitHub issue gating** rule near the top (line 20) — must skip `gh issue edit` calls when user opted out. Reused as-is.
- **Argument parsing.** `$ARGUMENTS` starting with `plan` (case-insensitive) followed by whitespace OR end-of-string is the new prefix. `plan` alone prompts for the description via AskUserQuestion; `plan <desc>` uses the remainder as description. Edge case: a real issue with title starting with the word "plan" — disambiguated because text-input flow handles arbitrary descriptions, and numeric input is unambiguous.
- **Anti-injection rule** (line 211) — must extend coverage to the plan-mode transcript: the user-approved plan content is trusted (came from the operator's session); the description text passed in is the only external untrusted input and goes into Problem section only.

### Pattern to reuse

Phase 1 (issue scaffolding) and Phase 3 (exec-plan creation) already do everything we need — plan-first is essentially a re-ordering: plan-mode first, then scaffold using the same primitives, then mark Stage=IMPLEMENT. No new file-format work, no new template.

## Approach

Add a new input form `plan [description]` recognized in Phase 0. When matched, dispatch to a new **Phase 1P: Plan-first** that:

1. Resolves the description (uses `$ARGUMENTS` minus the `plan` prefix; if empty, AskUserQuestion prompts for it).
2. Calls `EnterPlanMode` immediately. The agent drafts an implementation plan covering Approach, Files to change, New files, Tests, Open questions — the same shape `/feature-plan` produces. User iterates; agent uses `ExitPlanMode` for approval. **No file writes are allowed until ExitPlanMode is approved.**
3. On approval, derives a concise issue title from the approved plan (or asks the user to confirm one), then reuses Phase 1 step 3a (read `.hivesmith/config.toml` policy) and Gate 1 (Create issue / Skip GitHub / Edit / Cancel) — same primitives, same flow.
4. After the issue is created (or skipped + local number allocated), runs the same duplicate-check, slug, and spec-write logic as Phase 1 steps 7–10, with one difference: Type/Complexity/Priority are auto-filled to `enhancement` / `S` / `P2` (user can edit post-scaffold).
5. Creates the exec plan from `docs/exec-plans/_template.md`. Both **Research** and **Approach** sections are populated from the approved plan-mode content. Stage is set directly to `IMPLEMENT`.
6. Appends an index row with Stage = `IMPLEMENT` and the auto-defaulted priority.
7. Applies GitHub labels equivalent to TRIAGE→RESEARCH→PLAN traversal (`--add-label planned`) when a GitHub issue exists, respecting the existing issue-gating rule.
8. Continues to Phase 5 (Implement).

**Why this over the obvious alternative** (a separate `/feature-plan-first` skill): the loop already owns the scaffolding primitives (issue draft, policy gate, slug, index row, exec-plan template). Forking a new skill duplicates all of that and creates a second source of truth for the scaffolding contract. A new input form inside the loop reuses the primitives and keeps the loop as the single entry point for new features.

**Anti-injection extension.** The plan-mode transcript content the user approved is trusted (it is the operator's own session). The description passed as `$ARGUMENTS` after `plan` remains untrusted external text and only flows into the spec's Problem section.

### Files to change

1. `skills/feature-loop/SKILL.md` — five edits:
   - **`argument-hint`** (line 4): change to `"[issue-number | plan <description> | description]"`.
   - **Input stanza** (lines 15–18): add bullet for `plan <description>` describing plan-first behavior and pointing at Phase 1P.
   - **Phase 0 dispatch** (lines 34–37): add a branch — `$ARGUMENTS` starts with `plan` (case-insensitive, followed by whitespace or end-of-string) → Phase 1P. Order: check plan-prefix before the generic text branch.
   - **New Phase 1P section** inserted between Phase 1 and Phase 2 (after line 76). ~50 lines. Steps mirrored from the Approach above. Explicitly references `EnterPlanMode` / `ExitPlanMode` and the no-writes-before-approval rule. Documents the reuse of Phase 1 steps 3a + 5 + 6 + 7–10 for issue/spec scaffolding and Phase 3 step 19 for exec-plan creation.
   - **Rules section** (lines 197–207): add a bullet — "Plan-first input (`plan ...`) auto-satisfies TRIAGE/RESEARCH/PLAN gates via plan-mode approval; the approved plan content is treated as trusted; only the description argument is untrusted external input."

### New files

None.

### Tests

This repo's "tests" for skill changes are render-correctness + smoke checks defined in `AGENTS.md` (lines under "Build / test / lint commands"). For this change:

- **Render check** (existing convention, extend mentally): After install, the rendered `hs-feature-loop/SKILL.md` must contain the string `Phase 1P` and `plan <description>`, and must not contain accidental references to a non-existent `/feature-plan-first` skill. Add to the render-correctness invocation list during implementation:
  ```
  grep -q 'Phase 1P' .rendered/hs-/skills/hs-feature-loop/SKILL.md
  grep -q 'plan <description>' .rendered/hs-/skills/hs-feature-loop/SKILL.md
  ```
- **Shellcheck** — unchanged; no shell code touched.
- **Install smoke** — unchanged; just confirms the rewritten SKILL.md still renders without prefix collisions.
- **Manual acceptance** (post-merge `/feature-qa`): run `/feature-loop plan add a hello-world skill` in a scratch workspace; confirm plan mode opens, approval scaffolds spec+exec-plan+(issue or local number) with Stage=IMPLEMENT; confirm `/feature-loop <N>` resume lands in Phase 5. These are the success criteria from the spec.

No new automated test harness — consistent with how `feature-loop`, `feature-plan`, `feature-research` are exercised today (render check + manual acceptance).

## Open questions / risks

- **Risk:** if a user types `plan` as the literal first word of a real feature description ("plan the migration to ..."), it would be intercepted. **Mitigation:** the description after the `plan` keyword still becomes the spec's Problem section, and the plan-mode iteration gives the user a chance to redirect ("never mind, this is just a description"). Acceptable.
- **Risk:** plan-mode output quality varies; if the approved plan is thin, the resulting exec plan is thin. **Mitigation:** Phase 1P step 2 explicitly instructs the agent to cover Approach / Files / New files / Tests / Open questions in the plan-mode draft — same shape `/feature-plan` produces.
- **Risk:** `EnterPlanMode` / `ExitPlanMode` are deferred tools in this environment. **Mitigation:** the skill instructs the harness to use plan mode but does not hard-fail if unavailable; falls back to a regular AskUserQuestion approval gate.

## Decision log

## Progress

- **2026-05-12** — Spec + exec plan scaffolded; Stage = RESEARCH.
- **2026-05-12** — Research complete; Stage → PLAN.
- **2026-05-12** — Plan approved; Stage → IMPLEMENT.
- **2026-05-12** — Implementation complete: 5 edits to `skills/feature-loop/SKILL.md` + CHANGELOG entry. All checks pass.

## Open questions

- Should plan-first auto-default Type/Priority or surface a one-shot AskUserQuestion before scaffolding? (Leaning auto-default; user can edit the spec.)

## PR convergence ledger

## QA verdict
