# Make plan-html the default in feature-loop and add per-section feedback boxes

- **Spec:** [docs/product-specs/035-plan-html-default-and-per-section-feedback.md](../../product-specs/035-plan-html-default-and-per-section-feedback.md)
- **Issue:** #35
- **Status:** active
- **PR:** #37
- **Branch:** feature/35-plan-html-default-and-per-section-feedback

## Summary

Two-part fix to the plan-html review path:

1. Make the HTML plan renderer the default in Phase 4 (Plan) of `feature-loop`, not just in Phase 1P (plan-first entry).
2. Make per-section feedback textareas the default in the rendered HTML, so callers don't have to remember to attach a `feedback` object to every section in the manifest.

## Research

### Bug 1 — plan-html not default in Phase 4

`skills/feature-loop/SKILL.md`:
- Line 141 — Phase 1P **does** describe the HTML plan path as default ("**Default — HTML plan via `hs-plan-html`**...").
- Lines 225–227 — Phase 4 ("Plan") drafts the plan via *native plan mode* or *inline chat*. There is **no branch for HTML rendering** here. So any feature that enters via Phase 1 (text description → triage → research → plan) never reaches the HTML reviewer.
- Lines 235–243 — Gate 4 mirrors this: only native plan-mode approval or AskUserQuestion approval. No `start.sh` / `stop.sh` / `<plan>.approved.json` polling.

This is the bug: only the plan-first entry path uses HTML; the canonical pipeline path does not.

### Bug 2 — per-section feedback boxes missing

`skills/plan-html/render_plan.py`:
- Lines 24, 160–171, 184 — the manifest schema treats `section.feedback` as **optional**. `_render_feedback` returns an empty string when no `feedback` object is attached, and `_render_section` only appends a feedback aside when one is present.
- Lines 32, 213 — `global_feedback` is also optional and rendered only when present.

`skills/plan-html/template.html`:
- Lines 92–123, 206 — the template's CSS, JS, and DOM contract already handle `<aside class="feedback">` elements (autosave, reload, multi-section keying). The infrastructure is in place; it's just that the manifest doesn't always attach `feedback` to every section.

So the gap is in the manifest contract / renderer default: if a caller forgets to set `feedback` per section (which both `feature-loop` and `feature-plan` skills are prone to do because the docstring describes feedback as "optional"), reviewers lose per-section comments and have to use one global box.

### AGENTS.md conventions

Project conventions live in `AGENTS.md` (read during Phase 4). The render_plan.py already ships an internal `--selftest` mode (line 264 in the grep above checks `data-section="context"` rendered), so the test strategy is: extend the self-test to verify per-section feedback boxes appear *without* the caller attaching them.

## Approach

**Bug 1 — extend Phase 4 with an HTML branch (mirror Phase 1P, line 141).**

In `skills/feature-loop/SKILL.md` Phase 4 (step 31), add the HTML rendering branch as the **default** approval path, with native plan-mode and inline-chat as fallbacks. Gate 4 (step 32) gets the corresponding `<plan>.approved.json` poll + `<plan>.feedback.json` revise loop. The wording is copy-aligned with Phase 1P so the two paths converge on the same UX.

Rejected alternative: factor Phase 1P's HTML block into a shared sub-routine that both Phase 4 and Phase 1P call. Cleaner, but the SKILL.md is a prompt, not code — duplicating the four-line incantation is fine and avoids a second indirection a reader has to chase.

**Bug 2 — auto-default `feedback` per section in `render_plan.py`.**

In `_render_section`, if `section.get("feedback")` is absent, synthesize one from the section's `id`:

```python
fb = section.get("feedback") or {"slug": section["id"], "label": f"feedback — {heading}"}
```

Same for `global_feedback`: if absent, synthesize `{"slug": "global", "label": "feedback — global / open questions"}`. Callers who *want* to suppress the box can pass `"feedback": false` (treat `False` explicitly as opt-out).

Rejected alternative: require callers to always set `feedback` and hard-fail when missing. This punishes every caller for the common case and creates churn in `feature-loop` and `feature-plan` manifests. Making the default the helpful behavior is the right ergonomic.

### Files to change

1. `skills/feature-loop/SKILL.md` — Phase 4 step 31: add HTML rendering as the default branch (modeled on Phase 1P line 141). Phase 4 step 32 (Gate 4): add the approval-polling/feedback-revise loop. Keep native plan-mode and inline-chat as fallbacks.
2. `skills/plan-html/render_plan.py` — `_render_section`: synthesize a default `feedback` dict when none is given. `render_html`: same default for `global_feedback`. Honor explicit `False` as opt-out.
3. `skills/plan-html/render_plan.py` (docstring) — update the manifest schema docstring at lines 18–35 to note `feedback` is "default-on; pass `false` to suppress".

### New files

- None.

### Tests

- `skills/plan-html/render_plan.py --selftest` — extend the existing self-test (around line 263) to additionally:
  - Render a manifest where a section omits `feedback` entirely; assert the output contains `<aside class="feedback" data-section="<section-id>">`.
  - Render a manifest where `feedback: false` is set on a section; assert the output does **not** contain a feedback aside for that section.
  - Render a manifest with no `global_feedback`; assert the global aside is present.

## Decision log

- **2026-05-15** — Treat per-section feedback as default-on in `render_plan.py` rather than requiring all callers to set it. Why: the template already supports it, the manifests almost always want it, and `false` is a clean explicit opt-out.
- **2026-05-15** — Duplicate the Phase 1P HTML block into Phase 4 rather than extracting a shared subroutine. Why: SKILL.md is a prompt; an extra indirection costs more to read than the four-line copy.

## Progress

- **2026-05-15** — Research complete; spec stage = RESEARCH.
- **2026-05-15** — Plan approved via HTML plan review (no per-section feedback returned); spec stage = IMPLEMENT.
- **2026-05-15** — Implemented `_resolve_feedback` default-on helper in `render_plan.py`; extended `--self-test` with feedback-default assertions (pass). Added HTML branch to `feature-loop` Phase 4 step 31 + Gate 4 step 32. Changeset `.changesets/035-plan-html-default-and-feedback.md` written. AGENTS.md gates pass (shellcheck, brain tests, install smoke ×2, render correctness, changelog non-empty).

## Open questions

- None.

## PR convergence ledger

- **2026-05-15 iter 1** — verdict: APPROVE; findings_hash: empty; threads_open: 0; action: stop; head_sha: c366e1c.

## QA verdict

<!-- filled by /feature-qa -->
