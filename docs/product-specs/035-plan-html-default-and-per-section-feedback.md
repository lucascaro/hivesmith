---
issue: 35
title: Make plan-html the default in feature-loop and add per-section feedback boxes
type: bug
complexity: S
priority: P2
stage: IMPLEMENT
---

# Make plan-html the default in feature-loop and add per-section feedback boxes

- **Exec plan:** [docs/exec-plans/active/035-plan-html-default-and-per-section-feedback.md](../exec-plans/active/035-plan-html-default-and-per-section-feedback.md)

## Problem

Two related defects in the plan-html review path of the feature-loop pipeline:

1. **plan-html is not used by default.** Although #30 set the intent that the HTML plan renderer is the default review path in feature-loop, the skill currently does not invoke `hs-plan-html` automatically when drafting the implementation plan. The non-HTML markdown path is still taking precedence in practice.

2. **HTML plan output is missing per-section feedback boxes.** The rendered `<plan>.html` does not include the inline-feedback slots that the user expects (one input per section), so reviewers can only approve/reject globally rather than per section.

## Desired behavior

When running `/hs-feature-loop`, the plan review stage automatically renders the plan as HTML via `skills/plan-html/render_plan.py`, starts the feedback server, and the rendered page includes a feedback textarea adjacent to each section that writes per-section comments to `<plan>.feedback.json`.

## Success criteria

- Running `/hs-feature-loop` on a new feature renders an HTML plan by default (no flag needed), and the URL is surfaced to the user.
- Each plan section in the rendered HTML has its own feedback textarea; submitted content lands in `<plan>.feedback.json` keyed by section.
- The user's saved feedback preference (`feedback_plan_review_format.md`) is honored — HTML with syntax highlighting, visual aids, inline-feedback slots.

## Non-goals

- Redesigning the approval flow itself (only adding per-section comment capture alongside the existing global approve).
- Changing the manifest schema beyond what is needed for per-section feedback IDs.

## Notes

- Built on #29 / #30 (the opt-in plan-html skill).
- Related skill source: `skills/plan-html/`, `skills/feature-loop/SKILL.md`.
