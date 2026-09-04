---
name: graphify-init
description: Wire graphify into this project so its knowledge graph stays fresh across git worktrees — shared extraction cache, worktree-aware git hooks, debounced auto-refresh after edits
argument-hint: "[--migrate] [--no-nudges] [--uninstall]"
allowed-tools: Bash Read
---

# Wire graphify into this project

Sets up [graphify](https://github.com/Graphify-Labs/graphify) so a project's code knowledge graph maintains itself — including inside git worktrees, which graphify's own hooks deliberately skip.

Backed by `graphify-setup.sh` in this skill directory. **The script is the source of truth — do not re-implement its logic, and do not hand-edit what it writes.**

## What it sets up

1. **A shared extraction cache.** Each checkout's `graphify-out/cache` becomes a symlink into `$(git rev-parse --git-common-dir)/graphify-cache`. Cache keys are content hashes, so a file extracted once in any worktree is never re-extracted in another. This is the part that saves money: semantic extraction costs LLM calls, and without sharing every new worktree re-pays for identical files.

2. **Worktree-aware git hooks.** `graphify hook install` writes `post-commit` and `post-checkout` into the common hooks dir (one install covers every worktree), and the setup then lifts graphify's built-in worktree guard, which otherwise exits early in any linked worktree.

3. **A debounced auto-refresh.** A Claude Code `PostToolUse` hook on `Edit|Write|MultiEdit` runs `graphify-refresh.sh`, which triggers an AST-only incremental rebuild at most once per debounce window. It never blocks, never fails a tool call, and never spends LLM tokens. The script is installed into the **gitignored** output dir (`graphify-out/graphify-refresh.sh`), never a tracked path — a committed hook aimed at a tracked file is a payload any PR could change, since review sees the unchanging command string rather than the file it points at. Setup adds the output dir to `.gitignore` if it is not already ignored, and the hook no-ops when the script is absent.

4. **A `PreToolUse` orientation hook** (`graphify-out/graphify-nudge.sh`, wrapping `graphify hook-guard search` / `read`). Unlike the refresh hook, this one *prints text that is fed back as context* on `Read`/`Glob`/`Grep`/`Bash` — an agent's most frequent tool calls — to nudge it toward consulting the graph before grepping. Because `.claude/settings.json` is committed, whatever it prints reaches everyone who clones the repo, so the wrapper exists to keep that cheap and non-invasive. It delegates to graphify everything about *whether* a call is in scope (in-project, source extension, indexed, stale) and *whether to block* (strict mode, passed through byte for byte), and owns three things graphify currently gets wrong:
   - **Tone.** Graphify emits `MANDATORY: … You MUST run graphify query …`. An imperative arriving through a tool-result channel is the shape agents are instructed to distrust, so security-instructed subagents refuse it — it is anti-effective on exactly the agents that follow their instructions. The wrapper re-states it as advice.
   - **Frequency.** Upstream has no throttle, so the same line repeats on every matching call. The wrapper emits at most once per `(session, kind)`, claimed atomically under `graphify-out/cache/hook_nudges/`.
   - **Self-defeat.** `graphify query` records orientation in `cache/last_query_stamp`, which only upstream's strict path reads. The wrapper honours it, so complying makes the reminder stop.

   It also skips invoking graphify at all once nothing it could return would be used — with strict mode off, that saves a process spawn on every tool call for the rest of the session. It never blocks a tool call: missing graphify, malformed input, or an unwritable cache all exit 0 silently. Honours `GRAPHIFY_HOOK_STRICT` and `GRAPHIFY_HOOK_STRICT_TTL` (the stamp freshness window, default 1800s) rather than inventing its own knobs. Disable the hook entirely with `--no-nudges` or `HIVESMITH_GRAPHIFY_NUDGES=0`; the rest of the setup is unaffected.

   Upstream tracking: [#2202](https://github.com/Graphify-Labs/graphify/issues/2202) (reads as prompt injection), [#2984](https://github.com/Graphify-Labs/graphify/issues/2984) (no rate limit — 1.2% conversion over 1,739 firings), [#2985](https://github.com/Graphify-Labs/graphify/pull/2985) (open) and [#3323](https://github.com/Graphify-Labs/graphify/pull/3323) (closed without merging).

5. **An `AGENTS.md` block** telling agents how to orient (`GRAPH_REPORT.md`), trace (`graphify query`), and check blast radius (`graphify affected`) — and that they no longer need to rebuild by hand.

## Steps

1. **Check `graphify` is on `PATH`.** If not, tell the user to install it (`pip install graphifyy` or `uv tool install graphifyy`) and stop. Do not attempt the install yourself.

2. **Check for skill/package version drift.** Compare `graphify --version` against `~/.claude/skills/graphify/.graphify_version`. If they differ, warn — a stale `/graphify` skill teaches the agent an older CLI than the installed package — and suggest `graphify install --platform claude`. This is a warning, not a blocker; continue either way.

3. **Confirm the project is a git repository.** The whole design keys off `git rev-parse --git-common-dir`. If it is not a repo, stop and say so.

4. **Run the setup** with the working directory set to the project root. Invoke `graphify-setup.sh` **from this skill's own directory** (or by its absolute path) — an installed skill lives under `~/.claude/skills/<prefix>graphify-init/`, so a repo-relative `skills/graphify-init/...` path only resolves inside a hivesmith checkout, which is the one project that least needs this skill.

   ```bash
   "$(dirname "$0")/graphify-setup.sh"   # or: ~/.claude/skills/hs-graphify-init/graphify-setup.sh
   ```

   Pass through the user's arguments:
   - `--migrate` — required when `graphify-out/cache` already exists as a real directory. Without it the script **refuses**, on purpose: those entries cost real money to rebuild, so it will not delete them behind the user's back. Relay the refusal and ask before re-running with `--migrate`.
   - `--no-nudges` — skip the `PreToolUse` orientation hook described above, keeping the cache, git hooks, and refresh hook.
   - `--uninstall` — reverses everything: restores a real cache directory (contents preserved), strips the hook blocks, removes the settings entry and the `AGENTS.md` block.

5. **Report what changed** — the script prints one line per component. If it exited non-zero, relay the message verbatim rather than paraphrasing; the failure modes are deliberately specific.

6. **Offer the first build.** If `graphify-out/graph.json` does not exist, the automatic paths will not fire (they never bootstrap a graph from scratch — a tool hook is the wrong place to start a multi-minute build). Tell the user to run `/graphify` once. Do not run it for them: it costs LLM tokens.

## Failure modes worth relaying verbatim

- **"could not lift the worktree guard"** — a newer graphify reshaped its generated hook text and the patch no longer matches. The script refuses rather than leaving worktree graphs silently stale. It names the version it saw; the fix is to update `GUARD_IF` in `graphify-setup.sh` to match the new upstream text.
- **"is a real directory with existing cache entries"** — see `--migrate` above.

## Env knobs

| Variable | Default | Effect |
| --- | --- | --- |
| `HIVESMITH_GRAPHIFY_REFRESH` | `1` | `0` disables the post-edit refresh for a session. |
| `HIVESMITH_GRAPHIFY_DEBOUNCE` | `90` | Seconds between refreshes. |
| `HIVESMITH_GRAPHIFY_WORKTREE` | `1` | `0` restores graphify's upstream behavior (skip rebuilds in linked worktrees). |
| `HIVESMITH_GRAPHIFY_NUDGES` | `1` | `0` skips graphify's `PreToolUse` orientation hooks at setup time. |
| `HIVESMITH_GRAPHIFY_LOG_CAP` | `1048576` | Bytes; `.refresh.log` is truncated past this. |
| `GRAPHIFY_OUT` | `graphify-out` | Output directory name; honored by graphify and by both scripts. |

## Tests

`skills/graphify-init/test/run-all.sh` — bash 3.2 compatible, self-contained temp repos. Tests needing `graphify` on `PATH` skip when it is absent; set `GRAPHIFY_REQUIRED=1` (as CI does) to turn a skip into a failure.
