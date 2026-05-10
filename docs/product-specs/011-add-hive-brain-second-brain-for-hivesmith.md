# Add hive brain — a second brain for hivesmith

- **Issue:** #11
- **Type:** enhancement
- **Complexity:** M
- **Priority:** P1
- **Exec plan:** [docs/exec-plans/completed/011-add-hive-brain-second-brain-for-hivesmith.md](../exec-plans/completed/011-add-hive-brain-second-brain-for-hivesmith.md)

## Problem

Hivesmith currently operates as a stateless harness — every skill run starts from scratch, with no shared memory of past decisions, findings, or lessons across features, PRs, or projects. The same gotchas get re-discovered in repo after repo, and conventions a user has refined over months never reach the next project's first skill run.

## Desired behavior

A persistent **cross-project** second brain — "hive brain" — that hivesmith skills can read from and write to. Lives outside any single repo (default `~/.hivesmith/brain/`), captures durable knowledge tagged by scope (universal / ecosystem / user / team / project), and surfaces only the entries relevant to the active project at the start of each skill run. Append-only, file-based, git-trackable so teams can share via a git remote without inventing a sync protocol.

## Success criteria

- A documented schema with explicit scope tagging (at minimum: `universal | ecosystem | user | project`) and a documented storage location outside any single repo.
- Read and write entry points usable from skills, with retrieval filtered by active-project context.
- Write-time redaction (secret scan + raw-code-block guard) so project A's code/secrets cannot reach project B's prompts.
- Promotion of an entry to broader scope (e.g. project → universal) is explicit, not automatic.
- At least two existing skills read from the brain at startup, and at least one writes to it on convergence — proven end-to-end across two different repos.

## Non-goals

- Embedding-based / vector retrieval in v1 (grep + tag filters only).
- Hosted memory backends in v1 (Mem0 / Letta / Zep adapters deferred).
- Replacing `CLAUDE.md`, `AGENTS.md`, or auto-memory — those remain the instructions/config layer; brain is the lessons layer.
- Real-time multi-writer sync — teams use a git remote; conflicts resolved like any other git conflict.

## Notes

Triage pending.
