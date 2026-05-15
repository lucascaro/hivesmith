#!/usr/bin/env python3
"""Local feedback server for hs-plan-html.

Serves the plan HTML and accepts POSTs to /save (feedback) and /approve
(approval flag). Single-purpose, stdlib only, runs in foreground.

Configuration via env vars (set by start.sh):
  PLAN_HTML_PATH   absolute path to <plan>.html (required)
  PLAN_FEEDBACK_PORT  TCP port to bind on 127.0.0.1 (required)
  PLAN_TOKEN       required ?t=<token> URL query param; rejects others (required)

Sidecars (next to PLAN_HTML_PATH):
  <plan>.feedback.json   read by /feedback, written by /save
  <plan>.approved.json   written by /approve; existence == approval

The server binds to 127.0.0.1 only. The URL token defends against
same-machine drive-by access from other browser tabs.
"""
from __future__ import annotations

import datetime
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse


def _env(name: str) -> str:
    val = os.environ.get(name)
    if not val:
        sys.stderr.write(f"hs-plan-html server: missing env var {name}\n")
        sys.exit(2)
    return val


PLAN_HTML = Path(_env("PLAN_HTML_PATH"))
FEEDBACK_JSON = PLAN_HTML.with_suffix(".feedback.json")
APPROVAL_JSON = PLAN_HTML.with_suffix(".approved.json")
PORT = int(_env("PLAN_FEEDBACK_PORT"))
TOKEN = _env("PLAN_TOKEN")


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status: int, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_token(self) -> bool:
        qs = parse_qs(urlparse(self.path).query)
        tok = (qs.get("t") or [""])[0]
        if tok != TOKEN:
            self._send_json(403, {"error": "missing or invalid token"})
            return False
        return True

    def do_GET(self) -> None:  # noqa: N802
        if not self._check_token():
            return
        path = urlparse(self.path).path
        if path in ("/", "/index.html", "/plan"):
            try:
                data = PLAN_HTML.read_bytes()
            except OSError as exc:
                self._send_json(500, {"error": str(exc)})
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        elif path == "/feedback":
            data = FEEDBACK_JSON.read_bytes() if FEEDBACK_JSON.exists() else b"{}"
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        else:
            self._send_json(404, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._check_token():
            return
        path = urlparse(self.path).path
        if path not in ("/save", "/approve"):
            self._send_json(404, {"error": "not found"})
            return
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            payload = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError as exc:
            self._send_json(400, {"error": f"bad json: {exc}"})
            return
        if not isinstance(payload, dict):
            self._send_json(400, {"error": "payload must be a JSON object"})
            return
        if path == "/approve":
            payload["approved_at"] = datetime.datetime.now().isoformat(timespec="seconds")
            APPROVAL_JSON.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
            sys.stderr.write(f"[approve] plan approved at {payload['approved_at']} -> {APPROVAL_JSON}\n")
            sys.stderr.flush()
            self._send_json(200, {"ok": True, "approved_at": payload["approved_at"]})
            return
        FEEDBACK_JSON.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        sys.stderr.write(f"[feedback] saved {len(payload)} sections to {FEEDBACK_JSON}\n")
        sys.stderr.flush()
        self._send_json(200, {"ok": True, "saved_sections": list(payload.keys())})

    def log_message(self, format: str, *args) -> None:  # quiet default access log
        sys.stderr.write("[%s] %s\n" % (self.log_date_time_string(), format % args))


def main() -> int:
    if not PLAN_HTML.exists():
        sys.stderr.write(f"plan file not found: {PLAN_HTML}\n")
        return 1
    server = HTTPServer(("127.0.0.1", PORT), Handler)
    sys.stderr.write(f"hs-plan-html server listening on http://127.0.0.1:{PORT}/?t={TOKEN}\n")
    sys.stderr.write(f"feedback file: {FEEDBACK_JSON}\n")
    sys.stderr.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
