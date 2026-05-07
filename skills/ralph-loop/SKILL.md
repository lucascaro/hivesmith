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

For iteration `i` from 1 to `--max-iterations`:

1. **Capture the head SHA** before the loop body runs:
   ```bash
   PRE_SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
   ```
2. **Run `/review-pr $PR`.** Capture the structured output (BLOCKING / IMPORTANT / MINOR / Verdict).
3. **Branch on Verdict:**
   - `APPROVE` — done. Report convergence; exit the loop.
   - `COMMENT` (only IMPORTANT or MINOR findings, no BLOCKING) — by default treat as done unless the user passed `--strict` (then continue).
   - `REQUEST_CHANGES` (any BLOCKING) — continue to step 4.
4. **Loop-detection guard.** Hash the set of findings as `(file, line, category, title)` tuples. If this hash matches the previous iteration's, the loop is not converging. Escalate (see §3).
5. **Run `/autofix $PR`.** Autofix reads the review output from conversation context. Let it apply SAFE fixes; for RISKY items it will surface them — escalate the loop if any RISKY fix is gated on user judgment that wasn't pre-authorized.
6. **Push if anything changed:**
   ```bash
   git push
   POST_SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
   ```
   If `POST_SHA == PRE_SHA`, autofix made no changes — escalate.
7. **Wait for required CI checks** to complete on the new SHA before re-reviewing:
   ```bash
   gh pr checks "$PR" --watch --interval 15
   ```
   If any required check fails permanently (not flake), escalate with the failure log.
8. Continue to iteration `i+1`.

## 3. Escalation criteria

Stop the loop and surface to the user when any of these hit:

- Max iterations reached without `APPROVE`.
- Loop-detection guard fires (same findings two iterations in a row).
- Autofix produced no changes but findings remain.
- A required CI check fails twice with the same error (not a flake).
- A finding is classified RISKY by autofix and would change behavior in a way the user has not pre-authorized.
- A reviewer dimension explicitly disagreed with another (e.g. Security says block, UX says it's fine and the fix conflicts) — surface both rationales.

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
