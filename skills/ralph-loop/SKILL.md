---
name: ralph-loop
description: Drive a PR through review → autofix → re-review until findings clear or escalation criteria hit
argument-hint: "[pr-number] [--max-iterations N]"
allowed-tools: Read Glob Grep Bash Agent AskUserQuestion
---

# Ralph Wiggum Loop

Drive a single PR to convergence by iterating review → respond → re-review. Named after the autonomous loop pattern documented in OpenAI's "Harness engineering" post.

This skill is the **inner PR-convergence loop**. It is independent of the feature pipeline — any PR (hand-authored, from `/feature-implement`, or from another tool) can be driven to convergence through it.

## Inputs

- `$ARGUMENTS` first token: PR number. If omitted, detect from the current branch (`gh pr view --json number -q .number`). If neither resolves, stop and tell the user to pass a PR number.
- `--max-iterations N` (default 5): hard stop on iteration count.

## 1. Resolve the PR

```bash
PR=${1:-$(gh pr view --json number -q .number 2>/dev/null)}
[ -z "$PR" ] && { echo "ABORT: no PR resolved. Pass a PR number."; exit 1; }
gh pr view "$PR" --json state,isDraft,mergeable,baseRefName -q . > /tmp/ralph-pr-$PR.json
```

Stop with a clear message if the PR is closed, merged, or in draft.

## 2. Iterate

Each iteration runs in a **fresh sub-agent** so the orchestrator's context stays roughly constant across iterations. The orchestrator's only per-iteration state is `prev_findings_hash` (for the loop-detection guard) and a short `iteration_results` log used in §4.

For iteration `i` from 1 to `--max-iterations`:

1. **Launch one sub-agent** via the `Agent` tool with `subagent_type: "general-purpose"`. Give it the prompt below (substitute `<PR>` and the `--strict` flag value). Do **not** invoke `/review-pr` or `/autofix` from the orchestrator directly — the worker owns that context.

   Worker prompt (self-contained — the worker has no view of this conversation):

   > You are one iteration of the ralph-loop harness for PR **#<PR>** in the current repo. Strict mode: **<true|false>**.
   >
   > Do exactly this, in order:
   >
   > 1. `PRE_SHA=$(gh pr view <PR> --json headRefOid -q .headRefOid)`
   > 2. Run `/review-pr <PR>`. Capture the full BLOCKING / IMPORTANT / MINOR / Verdict output.
   > 3. Compute `findings_hash`: lowercase-hex SHA-256 over the sorted, newline-joined `file|line|category|title` tuples across all BLOCKING + IMPORTANT findings. (No findings → empty string.)
   > 4. Decide the next action from the verdict:
   >    - `APPROVE` → stop. No autofix, no push.
   >    - `COMMENT` → if strict mode is true, treat as `REQUEST_CHANGES`; otherwise stop.
   >    - `REQUEST_CHANGES` → run `/autofix <PR>`. Then `git push`. Set `POST_SHA` from `gh pr view`. If `POST_SHA == PRE_SHA`, set `escalate_reason: "autofix produced no changes"`. Otherwise wait on CI: `gh pr checks <PR> --watch --interval 15`. If a required check fails non-flakily, set `escalate_reason: "required CI check failed: <name>"` and include a one-line summary in `ci_status`.
   >    - If autofix surfaces RISKY items it would not auto-apply, list them in `risky_surfaced` and set `escalate_reason: "risky fix needs human decision"`.
   > 5. Return your result as a single fenced ```json block as the **last** thing in your reply, with this exact shape (omit optional fields when not applicable):
   >    ```json
   >    {
   >      "verdict": "APPROVE | COMMENT | REQUEST_CHANGES",
   >      "findings_hash": "<hex or empty>",
   >      "findings_summary": ["<file:line> [CATEGORY] <title>", "..."],
   >      "autofix_ran": false,
   >      "pushed": false,
   >      "pre_sha": "...",
   >      "post_sha": "...",
   >      "ci_status": "passed | failed | not_run",
   >      "ci_failure": "<one line, only if failed>",
   >      "risky_surfaced": [],
   >      "escalate_reason": ""
   >    }
   >    ```
   > Cap `findings_summary` at 20 entries. Do not paste review prose, diff hunks, or CI logs into the envelope — those stay in your context only.

2. **Parse** the JSON envelope from the worker's reply. If it is missing or malformed, escalate with reason `"worker returned malformed envelope"`.

3. **Loop-detection guard.** If `envelope.findings_hash` is non-empty and equals `prev_findings_hash`, escalate with reason `"loop-detection guard: identical findings two iterations in a row"`. Otherwise set `prev_findings_hash = envelope.findings_hash`.

4. **Branch on verdict:**
   - `APPROVE` — done. Exit the loop and go to §4.
   - `COMMENT` with strict off — done. Exit the loop and go to §4.
   - `escalate_reason` non-empty — escalate with that reason (see §3).
   - Otherwise — append a short line to `iteration_results` (`#i: <verdict>, <N> findings, pushed=<bool>`) and continue to iteration `i+1`.

## 3. Escalation criteria

Stop the loop and surface to the user when any of these hit:

- Max iterations reached without `APPROVE`.
- Loop-detection guard fires (same findings two iterations in a row).
- Autofix produced no changes but findings remain.
- A required CI check fails twice with the same error (not a flake).
- A finding is classified RISKY by autofix and would change behavior in a way the user has not pre-authorized.
- A reviewer dimension explicitly disagreed with another (e.g. Security says block, UX says it's fine and the fix conflicts) — surface both rationales.
- The iteration sub-agent returned a non-empty `escalate_reason` (autofix made no changes, required CI failed, RISKY fix needs human decision, etc.) — propagate that reason verbatim.

When escalating, post a single PR comment summarizing:
- Iteration count reached.
- The unresolved findings (deduped, with file:line and confidence).
- The reason the loop stopped.
- A suggested next step the human can take.

## 4. Output

```
## Ralph loop result
PR: #<n>
Iterations: <i>/<max>
Final verdict: APPROVE | ESCALATED
<reason if escalated>

## Findings cleared this run
<bullet list>

## Findings remaining (if escalated)
<bullet list>
```

## 5. Rules

- Never merge from inside the loop. Convergence is "no BLOCKING findings"; merging is the human's call (or a separate skill).
- Never overwrite the user's pre-authorization. If the user said "do not change file X", autofix's RISKY classifier should hold — escalate instead.
- Always push after autofix runs and CI completes before re-reviewing — re-reviewing the old diff wastes a turn.
- Loop budget is finite. Five iterations is the default; more than that suggests the harness, not the loop, needs work.
- Run review-pr and autofix as full skill invocations, not by inlining their prompts. They evolve independently and the loop should track them.
- Each iteration runs in a fresh sub-agent context. The orchestrator keeps only the result envelope (`verdict`, `findings_hash`, short `findings_summary`, `escalate_reason`) — never the raw review prose, diffs, or CI logs. This keeps the orchestrator's per-iteration footprint flat regardless of iteration count.
