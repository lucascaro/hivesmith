---
issue: 29
pr: 30
type: added
bump: minor
---
- **`hs-plan-html` skill — interactive HTML review for plan-producing flows.** Renders a plan as a self-contained HTML page (dark-default, hl.js + mermaid, per-section feedback textareas with 1.2s autosave + ⌘S, `↻ updated since your last review` highlight, ✓ Approve button) backed by a tiny stdlib Python HTTP server bound to `127.0.0.1` and gated by a per-session URL token. The HTML, CSS, JS, and server are **frozen templates filled programmatically** (`render_plan.py` with a strict tag allowlist + `--self-test`) so the LLM authors only the per-section plan content, not the chrome — minimizing tokens and pinning the JS contracts (autosave path, approve path, token query param). `feature-loop` Phase 1P (P2) now defaults to invoking `hs-plan-html` when its templates are present; set `HIVESMITH_PLAN_HTML=0` or pass `--no-html` to fall back to the inline draft. Claude Code's built-in plan mode (outside hivesmith) is unaffected.
