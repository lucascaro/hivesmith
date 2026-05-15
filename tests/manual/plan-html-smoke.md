# Manual smoke — hs-plan-html

Covers the success criteria in `docs/product-specs/029-add-opt-in-html-plan-review-skill.md`.

## Setup

```bash
python3 skills/plan-html/render_plan.py --self-test
# expect: "self-test OK -> /tmp/hs-plan-html-selftest.html"
# expect: "self-test OK (allowlist rejected <script>)"
```

## 1 · End-to-end smoke

```bash
skills/plan-html/start.sh /tmp/hs-plan-html-selftest.html
# expect:
#   - "hs-plan-html: server pid=<N> port=8765 log=/tmp/hs-plan-html-selftest.server.log"
#   - "hs-plan-html: open http://127.0.0.1:8765/?t=<32-hex>"
#   - the browser opens that URL (unless PLAN_HTML_AUTO_OPEN=false).
```

In the browser:

- Page renders with the dark theme (default).
- "Smoke test plan" appears as both `<title>` and `<h1>`.
- Two sections render with feedback textareas.
- A "↻ updated since your last review" banner appears on the Approach section (it's wrapped in `.changed`).
- Savebar at the bottom: status indicator, reload, save, ✓ Approve plan.

Type something in the Context feedback textarea — within ~1.2s the status changes to "saved 1 section · <time>".

```bash
cat /tmp/hs-plan-html-selftest.feedback.json
# expect: {"context": "<what you typed>"}
```

Reload the page — your text reappears. (The page re-fetches `/feedback?t=…` on load.)

Click **✓ Approve plan**, confirm the dialog.

```bash
ls /tmp/hs-plan-html-selftest.approved.json
cat /tmp/hs-plan-html-selftest.approved.json
# expect: {"feedback": {...}, "approved_at": "<iso8601>"}
```

```bash
skills/plan-html/stop.sh /tmp/hs-plan-html-selftest.html
# expect: "hs-plan-html: killed pid=<N>"
ls /tmp/hs-plan-html-selftest.server.pid 2>&1
# expect: No such file or directory
ps -p <pid> 2>&1
# expect: process gone
```

## 2 · URL token enforcement

While the server is running:

```bash
curl -i http://127.0.0.1:8765/
# expect: HTTP/1.0 403 ; body {"error":"missing or invalid token"}

curl -i "http://127.0.0.1:8765/?t=wrong"
# expect: HTTP/1.0 403

curl -i "http://127.0.0.1:8765/?t=$(cat /tmp/hs-plan-html-selftest.server.token)"
# expect: HTTP/1.0 200 ; body = HTML.
```

## 3 · Port collision

In two terminals:

```bash
# terminal 1
skills/plan-html/start.sh /tmp/plan-a.html   # (render a fixture first)
# expect: port=8765

# terminal 2
skills/plan-html/start.sh /tmp/plan-b.html
# expect: port=8766 (auto-bump)
```

Both URLs open and work independently. `stop.sh` against each cleans them up.

## 4 · Headless mode

```bash
PLAN_HTML_AUTO_OPEN=false skills/plan-html/start.sh /tmp/hs-plan-html-selftest.html
# expect: URL printed, no browser opened.
```

## 5 · Cleanup discipline

After `stop.sh`:

- No `python3 .../server.py` process remains for the plan (check `pgrep -af server.py`).
- `.server.{pid,port,token}` sidecars are gone.
- `.feedback.json` and `.approved.json` remain (user notes preserved).
- `.server.log` remains (left for inspection).
