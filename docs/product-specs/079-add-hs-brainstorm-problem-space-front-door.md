---
issue: 79
title: Add /hs-brainstorm — a problem-space front door to the feature pipeline
type: enhancement
complexity: M
priority: P2
pr: 81
shipped: 2026-09-16
stage: DONE
---

# Add /hs-brainstorm — a problem-space front door to the feature pipeline

- **Exec plan:** [docs/exec-plans/completed/079-add-hs-brainstorm-problem-space-front-door.md](../exec-plans/completed/079-add-hs-brainstorm-problem-space-front-door.md)

## Problem

The feature pipeline has no ideation stage. `/feature-new` and `/feature-loop` Phase 1 both take an
already-formed description and draft an issue from it verbatim — neither asks whether the idea is
worth building, who has the problem, or what the alternative shapes of a solution are. The spec
sections that `/merge-gate` later validates a PR against — `## Success criteria` and `## Non-goals` —
therefore have no owner at the front of the pipeline and arrive thin or empty. Every downstream
skill does solution-space work (`/feature-research`, `/feature-plan`) on top of a problem statement
nobody interrogated.

## Desired behavior

A standalone `/hs-brainstorm` skill turns a vague idea into a spec worth planning against. It reads
the codebase first, interrogates the operator in batched rounds about the problem rather than the
implementation, and terminates by handing the four drafted narrative sections to `/hs-feature-new`,
which creates the GitHub issue per the `[github] create_issues` policy and writes
`docs/product-specs/<NNN>-<slug>.md`. Because `/hs-feature-new` also runs triage, the spec lands at
`stage: RESEARCH`. `/hs-brainstorm` then hands off with `/hs-feature-loop <NNN>`.

`/feature-loop` Phase 1, given a description that names no concrete observable change, says so and
stops rather than manufacturing a thin spec from it.

## Success criteria

- `skills/brainstorm/SKILL.md` exists with `name: brainstorm`, a `description`, `argument-hint`, and
  `disable-model-invocation: true`; it contains no `/hs-` literal (golden principle #5).
- The resulting artifact is a spec at `docs/product-specs/<NNN>-<slug>.md` matching
  `docs/product-specs/_template.md`, with `## Problem`, `## Desired behavior`, `## Success criteria`
  and `## Non-goals` all non-placeholder. It lands at `stage: RESEARCH` rather than at triage,
  because the delegation target `/hs-feature-new` runs triage as part of its own flow.
- The skill does **not** reimplement issue creation: it delegates to `/feature-new`, passing the
  drafted sections, so the `[github] create_issues` policy (`opt-out` default; `opt-in` writes the
  spec with no `issue:` key; `ask` prompts) has exactly one implementation outside `/feature-loop`.
- `/feature-new` honours caller-supplied spec sections verbatim instead of re-drafting its own
  2–4 sentence body.
- The skill's last step hands off to `/feature-loop <NNN>`, and it never enters solution space —
  no file lists, no approach selection, no test design.
- `/feature-loop` Phase 1 stops on an under-specified description and names `/brainstorm`, and its
  "pauses exactly twice" contract is restated to stay accurate.
- `/brainstorm` appears in the pipeline arrow and prose in both `AGENTS.md` and
  `templates/AGENTS.hivesmith.md`, and in the `README.md` skill table.
- A manual smoke doc at `tests/manual/brainstorm-smoke.md` covers the render greps, the four-section
  output, the issue policy paths, and the untrusted-input path.

## Non-goals

- Solution-space work. Approach selection, file lists, test design and tradeoff analysis stay owned
  by `/feature-research` and `/feature-plan`; `/brainstorm` must not duplicate `/feature-plan`'s
  interrogation loop.
- A visual/browser companion. Superpowers' mockup server is out of scope.
- Porting superpowers' spike/bounded/architectural three-path model. Hivesmith already routes depth
  by triage `complexity:`.
- Auto-invocation of `/brainstorm` from inside `/feature-loop`. The loop points at it and stops; it
  never runs it, so the loop's approval-gate count is unchanged.
- A separate design doc artifact. The spec is the only handoff.

## Notes

- Modeled on the superpowers `brainstorming` skill
  (`~/.claude/plugins/cache/claude-plugins-official/superpowers/6.3.0/skills/brainstorming/SKILL.md`),
  borrowing its rationalization-table and hard-gate devices, not its paths or its artifact location.
- Nearest prior art in-repo is `skills/feature-plan/SKILL.md` step 6 (batched interrogation, stop
  rule, "surface, don't assume"); `/brainstorm` reuses that shape with a problem-space stop rule.
