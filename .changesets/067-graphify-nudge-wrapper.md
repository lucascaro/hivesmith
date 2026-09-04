---
issue: 67
type: changed
bump: minor
---
- **`/graphify-init` now installs a wrapper around graphify's orientation nudge.** Graphify's `PreToolUse` hook injects `MANDATORY: … You MUST run graphify query …` into the tool-result stream on every `Read`/`Glob`/`Grep`/`Bash` call. The new `graphify-out/graphify-nudge.sh` keeps the reminder and drops the noise: it re-states the message as advice (an imperative arriving through a tool-result channel reads as a prompt-injection attempt, and security-instructed subagents correctly refuse it), emits it at most once per session per kind, and stays quiet once `graphify query` has actually run — which graphify records but only consults on its strict path. Once nothing graphify could return would be used, the wrapper skips invoking it at all, so the reminder stops costing a process spawn on every tool call too.

  Gating and blocking stay graphify's: the wrapper forwards the tool payload untouched and passes strict-mode denials through byte for byte. It never blocks a tool call — missing graphify, malformed input, or an unwritable cache all exit 0 silently — and honours `GRAPHIFY_HOOK_STRICT` and `GRAPHIFY_HOOK_STRICT_TTL` rather than inventing new knobs. Projects wired before this change are migrated on the next `/graphify-init` run; `--no-nudges` / `HIVESMITH_GRAPHIFY_NUDGES=0` still skips the hook entirely.

  Upstream tracking: [#2202](https://github.com/Graphify-Labs/graphify/issues/2202), [#2984](https://github.com/Graphify-Labs/graphify/issues/2984) (measured 1.2% conversion over 1,739 firings), with fixes [#2985](https://github.com/Graphify-Labs/graphify/pull/2985) and [#3323](https://github.com/Graphify-Labs/graphify/pull/3323) unmerged as of graphify 0.9.53.
