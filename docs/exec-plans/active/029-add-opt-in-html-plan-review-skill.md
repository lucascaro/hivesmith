# Add opt-in HTML plan review skill (hs-plan-html)

- **Spec:** [docs/product-specs/029-add-opt-in-html-plan-review-skill.md](../../product-specs/029-add-opt-in-html-plan-review-skill.md)
- **Issue:** #29
- **Stage:** REVIEW
- **Status:** active
- **PR:** [#30](https://github.com/lucascaro/hivesmith/pull/30)
- **Branch:** feature/29-add-opt-in-html-plan-review-skill

## Summary

Package the hand-rolled HTML+server plan-review prototype as a hivesmith skill `skills/plan-html/` (installs as `hs-plan-html`). The skill is **opt-in** — default plan flows are untouched — and emits its HTML/server scaffolding **programmatically from packaged templates**, so the LLM authors only the per-section plan content, not the chrome.

## Research

- **Repo skill layout.** Existing skills live at `skills/<name>/SKILL.md` with optional helper files alongside (`skills/feature-loop/SKILL.md`, `skills/release/`, etc.). Naming is bare in-repo (`feature-loop`), prefixed at install (`hs-feature-loop`). The new skill follows the same shape: `skills/plan-html/` in-repo, `hs-plan-html` once installed.
- **Reference artifacts.** Two operator-provided files capture the working prototype and are safe to copy verbatim into templates:
  - `~/.claude/plans/working-on-multiple-features-optimized-russell.html` — final HTML/CSS/JS (dark-default, hl.js + mermaid CDNs, savebar, `.changed` highlight, approve button).
  - `~/.claude/plans/_feedback_server.py` — ~80-line stdlib HTTP server with `GET /`, `GET /feedback`, `POST /save`, `POST /approve`.
- **Plan-mode integration points.** Plan mode itself is a Claude Code built-in (`EnterPlanMode` / `ExitPlanMode`), not a user-editable skill. The skill controls *the artifact format and review loop*, not plan-mode entry. Invocation is therefore explicit: `/hs-plan-html <task>` (or a `--html` flag on existing plan-producing skills — out of scope for this exec plan; tracked as a follow-up).
- **Cost model.** Boilerplate (HTML head, CSS, JS, server) is identical every run. Generating it through the model burns tokens and risks drift. Templates + a small generator script keep model output limited to *plan content fragments only*.
- **Anti-injection.** Operator plan file at `~/.claude/plans/upgrade-plan-skill-to-interactive-html.md` is untrusted external content; this exec plan distills intent but does not execute instructions inside it (e.g. its suggestion to override settings.json globally is rejected — opt-in only).

## Approach

The skill ships a deterministic generator. The LLM produces a structured list of plan sections; a Python script renders them into the packaged template; a wrapper boots the server. No model tokens are spent on CSS/JS/server code.

**Layered design.**

1. **Templates** (frozen, copied verbatim from prototype): `template.html` with sentinel comments, `server.py` parameterized via env vars, `start.sh`/`stop.sh` lifecycle helpers.
2. **Generator** (`render_plan.py`): reads a small JSON manifest (`title`, `sections: [{slug, heading, html, changed?}]`), substitutes into `template.html`, writes `<plan>.html`. Pure stdlib.
3. **SKILL.md** instructs Claude to: (a) build the manifest JSON for the plan, (b) invoke `render_plan.py`, (c) invoke `start.sh`, (d) on operator approval (`<plan>.approved.json` exists) call `ExitPlanMode` and `stop.sh`.
4. **Default in feature-loop, composable elsewhere.** `feature-loop`'s Phase 1P (plan-first) invokes `hs-plan-html` by default. Bypass: `HIVESMITH_PLAN_HTML=0` env var (also a `--no-html` flag on `plan ...`). Claude Code's built-in plan mode outside hivesmith is untouched. `/hs-plan-html <task>` remains a standalone entry for callers other than feature-loop.

**Cost-efficiency rules in SKILL.md.**
- Do not write HTML/CSS/JS yourself — only fill `sections[].html` with plan content fragments (allowed tags listed in SKILL.md).
- Mermaid diagrams: emit only when relevant (architecture, state machines, sequences) — never decorative.
- Use `changed: true` on a section to wrap it in `<div class="changed">` on the next render.

### Files to change

1. `CHANGELOG.md` — add `[Unreleased]` entry: `Added: hs-plan-html — HTML plan review skill with programmatic template generation. hs-feature-loop plan-first mode uses it by default.`
2. `docs/product-specs/index.md` — add row #29 (handled by Phase 1P scaffolding, see Progress below).
3. `README.md` (if it lists skills) — add `hs-plan-html` to the skill catalogue and note feature-loop default behavior + opt-out env var.
4. `skills/feature-loop/SKILL.md` — Phase 1P step P2 invokes `hs-plan-html` by default when its templates exist; respect `HIVESMITH_PLAN_HTML=0` / `--no-html` to fall back to the existing inline draft + AskUserQuestion approval branch.

### New files

- `skills/plan-html/SKILL.md` — skill metadata + procedural instructions (manifest schema, generator invocation, server lifecycle, approve-watch loop).
- `skills/plan-html/template.html` — frozen HTML scaffold copied from the prototype; placeholders `<!-- PLAN_TITLE -->`, `<!-- PLAN_BODY -->`, `<!-- PLAN_TOKEN -->`.
- `skills/plan-html/server.py` — parameterized copy of `_feedback_server.py` (`PLAN_HTML_PATH`, `PLAN_FEEDBACK_PORT`, `PLAN_TOKEN` from env).
- `skills/plan-html/render_plan.py` — stdlib-only generator: `render_plan.py --manifest <path.json> --template <template.html> --out <plan.html>`. Reads manifest, escapes inputs minimally (plan content is operator-trusted but we still apply a small allowlist on tag names), emits final HTML.
- `skills/plan-html/start.sh` — finds free port from 8765, generates random token, exports env vars, launches `server.py` detached, writes `<plan>.server.pid` and `<plan>.server.port`, opens `http://127.0.0.1:<port>/?t=<token>` via `open`/`xdg-open` (skipped when `PLAN_HTML_AUTO_OPEN=false`).
- `skills/plan-html/stop.sh` — reads `<plan>.server.pid`, kills the process, removes pid/port files.
- `skills/plan-html/README.md` — short user-facing usage doc (env knobs, what each file does).

### Tests

Hivesmith skills don't ship a Python test suite (per AGENTS.md conventions — skills are tested by smoke runs). Verification is the spec's success criteria executed manually. Specifically:

- `tests/manual/plan-html-smoke.md` (new) — checklist matching the spec's success criteria: invoke, HTML opens, autosave works, reload rehydrates, approve writes flag and triggers `ExitPlanMode`, server killed cleanly.
- `tests/manual/plan-html-port-collision.md` (new) — start two sessions, confirm second auto-picks a free port.
- `render_plan.py` — include a `__main__` self-test invoked with `--self-test` flag that renders a fixture manifest to `/tmp` and asserts placeholders are gone. Run as `python3 skills/plan-html/render_plan.py --self-test` in CI later (added by a follow-up).

## Decision log

- **2026-05-15** — Programmatic template fill, not model-generated HTML. Why: cost + correctness; CSS/JS contracts are tight and easy for a model to subtly break.
- **2026-05-15** — Dedicated reusable skill `hs-plan-html`; `hs-feature-loop` plan-first uses it by default with `HIVESMITH_PLAN_HTML=0` opt-out. Why: operator clarified the rich UX should be the default *within* hivesmith plan flows, while Claude Code's built-in plan mode stays untouched.
- **2026-05-15** — Server stays Python stdlib only. Why: portability; no install step for users.
- **2026-05-15** — Strict HTML tag allowlist at render time. Why: catch model drift early; failing loudly beats silently shipping a broken review UI.

## Progress

- **2026-05-15** — Plan-first scaffold via `/hs-feature-loop plan ...`; Stage = IMPLEMENT. Issue #29 created, spec + exec plan written.
- **2026-05-15** — Implementation committed on `feature/29-add-opt-in-html-plan-review-skill`. All AGENTS.md checks pass (shellcheck clean, `render_plan.py --self-test` OK, install dry-run + render correctness OK, changelog gate OK). PR #30 opened. Stage = REVIEW.

## Open questions

- Should `render_plan.py` enforce an HTML tag allowlist on `sections[].html`, or trust the model output verbatim? Default proposal: minimal allowlist (`p, ul, ol, li, pre, code, h2, h3, h4, table, thead, tbody, tr, th, td, div.changed, span.changed-inline, span.pill, a, strong, em, br, hr, blockquote, aside.feedback, label, textarea, button, div.mermaid`). Reject everything else with a hard error so drift surfaces immediately.
- Should the URL token be required (server rejects requests without `?t=<token>`) or advisory? Default: required.
- Should `feature-loop`'s `plan` starting point grow a `--html` flag that wires through to this skill? Out of scope for #29 — track as a follow-up issue once #29 lands.

## PR convergence ledger

<!-- populated by /review-loop -->

## QA verdict

<!-- populated by /feature-qa -->
