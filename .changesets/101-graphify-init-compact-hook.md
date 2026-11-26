---
type: fixed
bump: patch
---
- **`graphify-init` setup works with graphify 0.9.119+.** Newer graphify also registers a `SessionStart` (matcher `compact`) hook as a bare `graphify hook-guard compact`, which made setup abort with "the PreToolUse entries are not pointing at graphify-out/graphify-nudge.sh". Setup now routes that hook through `graphify-nudge.sh` too, so it degrades to a no-op where graphify is not installed, and a context compaction re-enables the once-per-session nudge before graphify restates the graph. `--uninstall` also drops the empty hook lists graphify leaves behind.
