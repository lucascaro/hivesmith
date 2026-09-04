---
issue: 67
title: Wrap graphify's PreToolUse nudge
type: enhancement
complexity: S
priority: P2
stage: REVIEW
pr: 68
---

# Wrap graphify's PreToolUse nudge

- **Exec plan:** [docs/exec-plans/active/067-wrap-graphify-pretooluse-nudge.md](../exec-plans/active/067-wrap-graphify-pretooluse-nudge.md)

## Problem

Graphify's `hook-guard` PreToolUse hook injects `MANDATORY: graphify-out/graph.json exists. You MUST run \`graphify query "<question>"\` before grepping raw files.` into the tool-result stream on every matching `Bash`/`Grep`/`Read`/`Glob` call. Three defects compound:

1. **It reads as a prompt injection.** An imperative directive arriving through a tool-result channel, phrased "MANDATORY / You MUST", is the exact shape agents are instructed to distrust. In one hivesmith session, three independent `hs-validator` subagents each flagged and disregarded it unprompted. The nudge is anti-effective on precisely the agents that follow their security instructions. Graphify's own Gemini variant (`_GEMINI_NUDGE_TEXT`) is worded advisorily and does not trigger this.
2. **It has no throttle.** The identical line is re-emitted on every matching call for the life of a session.
3. **It ignores its own success signal.** `graphify query|explain|path` records orientation in `graphify-out/cache/last_query_stamp`, but only the strict-deny path reads it — an agent that complies still gets nudged seconds later.

All three are known upstream and unfixed on the current release (0.9.53): [#2202](https://github.com/Graphify-Labs/graphify/issues/2202) open since 2026-07-25, [#2984](https://github.com/Graphify-Labs/graphify/issues/2984) open with measured data (1,739 firings → 21 graphify calls, ~1.2% conversion, ~95K tokens of context tax), [#2985](https://github.com/Graphify-Labs/graphify/pull/2985) unmerged, [#3323](https://github.com/Graphify-Labs/graphify/pull/3323) closed unmerged.

Hivesmith already post-processes graphify's `settings.json` entries in `graphify-setup.sh`, so it already owns the seam where this is fixable.

## Desired behavior

The orientation reminder still reaches the agent once, in wording it will act on rather than refuse, and then gets out of the way.

A wrapper script sits between Claude Code and `graphify hook-guard`. It forwards the tool payload to graphify, then decides what to emit:

- Graphify emitted nothing → emit nothing.
- Graphify emitted a strict `permissionDecision` deny → pass it through byte-for-byte. Blocking behavior is graphify's to own.
- The nudge already fired this session for this kind (`search` / `read`) → emit nothing.
- `graphify-out/cache/last_query_stamp` is fresh → emit nothing. The agent already oriented.
- Otherwise → emit the same `hookSpecificOutput` envelope with `additionalContext` replaced by neutral advisory wording: no "MANDATORY", no "You MUST", no instruction to propagate the rule to subagents.

Any error at any step fails open: exit 0, emit nothing, never block the tool call.

## Success criteria

- The wrapper emits at most one nudge per `(session, kind)` pair; a second matching tool call in the same session produces no output.
- No emitted text contains `MANDATORY`, `You MUST`, or an instruction to include the rule in subagent prompts.
- A strict-mode `permissionDecision` payload from `graphify hook-guard` is forwarded unchanged.
- When `graphify-out/cache/last_query_stamp` is newer than the configured freshness window, the wrapper emits nothing.
- With `graphify` absent from `PATH`, malformed stdin, an unwritable stamp directory, or `python3` missing, the wrapper exits 0 and emits nothing.
- `graphify-setup.sh` installs the wrapper as the `PreToolUse` command for both kinds; `--uninstall` removes it; re-running the installer is idempotent.
- `--no-nudges` / `HIVESMITH_GRAPHIFY_NUDGES=0` still skips the hooks entirely.
- `skills/graphify-init/test/run-all.sh` covers each of the branches above and passes.

## Non-goals

- Reimplementing graphify's in-project, staleness, or indexing logic — the wrapper delegates all of that.
- Changing graphify's strict mode, the `PostToolUse` refresh hook, or the shared-cache/git-hook parts of `graphify-setup.sh`.
- Making the nudge wording configurable. One fixed advisory string; no knob.
- Fixing graphify upstream in this repo. The upstream comments and PR are tracked separately (see Notes).

## Notes

Upstream follow-up agreed with the operator: comment on [#2202](https://github.com/Graphify-Labs/graphify/issues/2202) and [#2984](https://github.com/Graphify-Labs/graphify/issues/2984) with this session's evidence, then offer the wrapper's logic as a PR against graphify. That is a separate deliverable in a different repo and does not ride in this PR.
