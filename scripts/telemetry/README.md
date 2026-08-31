# telemetry

One event schema, several agents, and a commit trailer that does not depend on
each tool volunteering its own name.

## Why

Measured on hive: **101 of 444 commits carry no `Co-Authored-By` trailer, and 65
of those touch `.go`, `.js` or `.ts` files** — including a 1,222-line feature.
Claude Code writes a trailer; other agents may not. Any metric keyed on model
silently drops that 15%, and the drop is shaped like "whichever tool is quiet",
which is the worst possible bias for a comparison between tools.

## The event schema

Every emitter appends one JSON object per line to
`${HIVESMITH_HOME:-~/.hivesmith}/telemetry/agent-events.jsonl`:

```
ts, event, project, tool, model, session_id, agent_id, agent_type
```

`project` is the git toplevel basename, so one stream covers every repo. Logging
user-level rather than per-repo is deliberate: hivesmith installs globally, and
scattering a log into every project it touches defeats the point.

| emitter | tool | events |
|---|---|---|
| `log-agent.sh` / `log-agent-stop.sh` (Claude Code hooks) | `claude-code` | `subagent_start`, `subagent_stop` |
| `pi-extension.ts` (pi extension) | `pi` | `session_start`, `agent_start`, `agent_stop`, `session_shutdown` |

`agent_type` is null for pi. Pi has no named-subagent concept, and inventing a
name would make its rows look like Claude Code's Task subagents when they are a
different thing. A null meaning "not applicable" beats a label meaning nothing.

## Install

```bash
scripts/telemetry/install-hooks.sh                    # Claude Code hooks
scripts/telemetry/install-hooks.sh --status
scripts/telemetry/install-pi.sh                       # pi extension, global
scripts/telemetry/install-pi.sh --local               # into ./.pi/extensions
scripts/telemetry/install-pi.sh --commit-trailer ~/checkout/hive
```

Both installers refuse to overwrite a file that does not look like theirs, and
both uninstall only their own entries. `--commit-trailer` is opt-in per
repository and never installed by default: it changes the commit-message format
of that repo, which should be a deliberate choice.

## The commit trailer

`prepare-commit-msg` infers the producing tool from telemetry rather than
trusting the tool to announce itself. If an event for this project landed within
`HIVESMITH_ATTRIBUTION_WINDOW_S` (default 1200s), it appends:

```
Agent-Tool: pi
Agent-Model: claude-opus-4.7
Agent-Session: 01H...
Agent-Attribution: inferred from telemetry 42s before commit
```

The last line is the point. This is inference, not proof — you might commit by
hand twenty seconds after an agent run — so the trailer carries the evidence and
lets a reader judge it. It never overwrites an existing `Co-Authored-By` or
`Agent-Tool`, never stamps merge, squash or amend commits, and **never fails a
commit**: every path exits 0, including a torn or unparseable log line.

## Tests

```
./scripts/telemetry/install-hooks-test.sh   # RESULT: PASS checks=14
./scripts/telemetry/attribution-test.sh     # RESULT: PASS checks=25
```

The attribution suite is mostly about staying out of the way — cross-project
bleed, window discipline, malformed JSONL, missing arguments, and a real commit
in a real repo verified through `git log --format='%(trailers:...)'` rather than
through grep.
