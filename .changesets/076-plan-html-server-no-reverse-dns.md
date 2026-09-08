---
type: fixed
bump: patch
---
- **`/plan-html` no longer hangs on a wedged DNS resolver.** `http.server.HTTPServer.server_bind()` calls `socket.getfqdn(host)` after the bind — a reverse-DNS round trip (mDNSResponder on macOS) inside the constructor, before `server.py` writes the port file or logs a line. When the resolver stalls, `start.sh` hits its 5s poll budget and reports `timed out waiting for server.py to bind` with an empty server log, and the plan falls back to inline approval. The server now binds via a subclass that skips the lookup; the FQDN was only ever used for CGI env vars this server never emits.
