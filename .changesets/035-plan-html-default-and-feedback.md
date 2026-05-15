---
issue: 35
pr: 37
type: changed
bump: minor
---
- **`feature-loop` Phase 4 now defaults to HTML plan review.** Previously the HTML plan renderer (`hs-plan-html`) was only the default in plan-first entry (Phase 1P). The canonical pipeline path (text → triage → research → plan) drafted plans via native plan mode or inline chat only, so HTML review was unreachable from the most common entry point. Phase 4 step 31 and Gate 4 step 32 now mirror Phase 1P: HTML rendering is the default, with native plan mode and inline chat as fallbacks. Set `HIVESMITH_PLAN_HTML=0` or pass `--no-html` to opt out.
- **`hs-plan-html` per-section feedback boxes are now default-on.** `skills/plan-html/render_plan.py` previously treated `section.feedback` and `global_feedback` as optional, so manifests that omitted them rendered without any per-section comment textareas. The renderer now synthesizes a feedback dict per section (and a global one) when none is provided; pass `"feedback": false` to opt out for a specific section. The packaged template already supported the asides — this closes the manifest ergonomics gap.
