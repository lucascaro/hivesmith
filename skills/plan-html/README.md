# hs-plan-html

Rich HTML review UX for plan-producing hivesmith skills.

## What it gives you

When you invoke `/hs-feature-loop plan <task>` (or `/hs-plan-html <task>` directly), instead of reviewing a plain text plan you get:

- A self-contained `<plan>.html` opened in your browser (dark by default, light theme follows OS preference).
- Per-section `<textarea>` slots that **autosave** to `<plan>.feedback.json` (1.2s debounce, ⌘S also saves).
- A `↻ updated since your last review` highlight on sections that changed since you last looked.
- A `✓ Approve plan` button that writes `<plan>.approved.json` — the agent watches for that file to proceed.
- Syntax-highlighted code, mermaid diagrams, tables, pills.

A tiny stdlib Python server backs it (`127.0.0.1`-bound, URL-token-gated).

## How it's built (why it's cheap)

The chrome (CSS, JS, savebar, theme wiring, mermaid + highlight.js setup, server) is **frozen** in `template.html` + `server.py`. The agent only authors per-section plan HTML fragments. A small `render_plan.py` script fills the template programmatically. This minimizes the tokens an LLM spends on plan rendering and pins the JS contracts (autosave path, approve path, token query param) so they can't drift.

## Configuration

| Env var | Default | Purpose |
|---|---|---|
| `PLAN_FEEDBACK_PORT` | `0` | Preferred port. `0` (default) lets the OS pick any free port — no TOCTOU window. Set to a specific port (e.g. `8765`) to request it; the server falls back to OS-picked if it's taken. |
| `PLAN_HTML_AUTO_OPEN` | `true` | Set to `false` to skip the `open`/`xdg-open` call (useful on SSH / headless). |
| `HIVESMITH_PLAN_HTML` | `1` | Set to `0` to opt out — `hs-feature-loop plan ...` falls back to the inline text-plan draft. |

## Sidecar files (next to `<plan>.html`)

- `<plan>.feedback.json` — your notes, autosaved.
- `<plan>.approved.json` — created on approve-click; the agent stops the server and proceeds.
- `<plan>.server.{pid,port,token,log}` — lifecycle metadata; removed on `stop.sh`.

## Manual smoke test

```bash
# Render the bundled fixture and inspect it.
python3 skills/plan-html/render_plan.py --self-test
open /tmp/hs-plan-html-selftest.html   # macOS

# Start a real server pointed at it.
skills/plan-html/start.sh /tmp/hs-plan-html-selftest.html
# ...edit some feedback in the browser, click Approve...
ls /tmp/hs-plan-html-selftest.{feedback,approved}.json
skills/plan-html/stop.sh /tmp/hs-plan-html-selftest.html
```
