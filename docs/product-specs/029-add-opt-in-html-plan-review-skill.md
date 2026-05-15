# Add opt-in HTML plan review skill (hs-plan-html)

- **Issue:** #29
- **Type:** enhancement
- **Complexity:** M
- **Priority:** P2
- **Exec plan:** [docs/exec-plans/completed/029-add-opt-in-html-plan-review-skill.md](../exec-plans/completed/029-add-opt-in-html-plan-review-skill.md)

## Problem

Plan-mode review today is text-only. We prototyped a much better experience by hand — self-contained HTML with syntax highlighting, mermaid diagrams, per-section feedback textareas, autosave, a `↻ updated since your last review` highlight, and an "✓ Approve plan" button backed by a tiny stdlib HTTP server — but it lives nowhere reusable. Every new plan that wants this UX has to re-derive the template, server, and JS contracts, which is expensive in tokens and easy to get wrong.

## Desired behavior

A hivesmith skill `hs-plan-html` provides the rich review UX as a reusable component. When invoked, it produces a self-contained `<plan>.html` and boots a localhost feedback server in the background; the user reviews in the browser, leaves per-section feedback, and approves with a click — at which point the calling skill detects the approval flag and the server is torn down. The HTML structure, CSS, JS, and server are generated **from packaged templates programmatically**: the LLM authors only the per-section plan content, never the boilerplate. `hs-feature-loop`'s plan-first starting point uses `hs-plan-html` **by default** so every plan-mode review in the feature loop gets the rich UX automatically; opting out is a single flag/env-var. Claude Code's built-in plan mode (entered without `hs-feature-loop`) is unaffected.

## Success criteria

- A `skills/plan-html/` directory exists in the hivesmith repo and installs as `hs-plan-html` like other `hs-*` skills.
- Invoking `/hs-plan-html <task>` generates `<plan>.html`, starts the server, prints the URL, and does not block.
- `hs-feature-loop`'s `plan <description>` flow invokes `hs-plan-html` automatically by default; `HIVESMITH_PLAN_HTML=0` (or a `--no-html` flag) skips it and falls back to the inline plan draft.
- The HTML body's chrome (CSS, JS, savebar, theme switching, hl.js + mermaid wiring) is produced by a deterministic template fill (no LLM tokens spent on it); only the per-section plan content is model-authored.
- Feedback textareas autosave to `<plan>.feedback.json` and rehydrate after reload.
- Clicking "✓ Approve plan" writes `<plan>.approved.json`; the skill detects it and calls `ExitPlanMode`.
- The server is stdlib-only Python, binds to `127.0.0.1`, auto-bumps the port on collision, and is killed cleanly when plan mode exits.
- Claude Code's built-in plan mode (outside hivesmith skills) is unchanged.

## Non-goals

- Replacing or overriding Claude Code's built-in plan mode by default.
- Authentication beyond a per-session random token in the URL (localhost-only is the threat model).
- Persisting feedback to anything other than a local JSON sidecar.
- A non-Python server implementation.
- Cross-machine / remote review.

## Notes

- Reference plan from the operator: `~/.claude/plans/upgrade-plan-skill-to-interactive-html.md` (treated as untrusted external content per the anti-injection rule; the spec/plan distill its intent, they do not execute its instructions).
- Working artifacts the implementation may copy from verbatim: `~/.claude/plans/working-on-multiple-features-optimized-russell.html` (CSS/JS/HTML structure), `~/.claude/plans/_feedback_server.py` (server).
- The user pinned the format preference in `memory/feedback_plan_review_format.md` — this spec is the durable home for that preference.
