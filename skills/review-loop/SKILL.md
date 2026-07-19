---
name: review-loop
description: Drive a PR through review → autofix → re-review until findings clear or escalation criteria hit
argument-hint: "[pr-number] [--max-iterations N]"
allowed-tools: Read Glob Grep Bash Agent AskUserQuestion
---

# Review Loop

Drive a single PR to convergence by iterating review → respond → re-review. Originally called the *Ralph Wiggum Loop* after the autonomous loop pattern documented in OpenAI's "Harness engineering" post (see `references/openai-harness-engineering.md`).

This skill is the **inner PR-convergence loop**. It is independent of the feature pipeline — any PR (hand-authored, from `/feature-implement`, or from another tool) can be driven to convergence through it.

## Philosophy: boil the lake

Completeness is cheap when AI does the work. Keep iterating until findings actually clear — don't declare victory after one round of `/autofix` while non-trivial findings still stand. Each pass should fully apply the boil-the-lake stance from `/review-pr` and `/autofix`: every occurrence of every defect, every implementor of every touched contract. The loop ends when the review verdict is `APPROVE` (or `COMMENT` with only MINOR remaining), or when an escalation criterion fires (genuine ocean, contradictory findings, max iterations) — surface those for the user, don't quietly stop. The default bias is toward running the loop to true convergence, not to a comfortable-looking diff.

## Inputs

- `$ARGUMENTS` first token: PR number. If omitted, detect from the current branch (`gh pr view --json number -q .number`). If neither resolves, stop and tell the user to pass a PR number.
- `--max-iterations N` (default 5): hard stop on iteration count.

## Cold-start: read the convergence ledger

Before iterating, locate the matching exec plan (current: `docs/exec-plans/active/<NNN>-*.md` where `<NNN>` is derived from `gh pr view <PR> --json body,title` — look for `Fixes #<n>` / `Closes #<n>` in the PR body, or match the branch name `feature/<n>-*`). If a plan is found:

1. Read its `## PR convergence ledger` section. The last line gives `prev_findings_hash` (the hex value) — seed the loop-detection guard with it instead of starting empty.
2. Read `stage:` from the matching spec's YAML frontmatter (`docs/product-specs/<NNN>-*.md`) — the exec plan no longer carries a `Stage:` line, and the generated `index.md` is a derived view. If `stage` is not `REVIEW`, set it to `REVIEW` in the spec's frontmatter (no-op if already correct). **Legacy fallback:** when no spec frontmatter exists, read `Stage:` from the exec plan if present.
3. Throughout iteration, **append** one line per iteration to the ledger. Never rewrite or delete prior entries.

If no matching plan is found (PR was hand-authored, not from the feature pipeline), skip the ledger entirely and run the loop with an empty `prev_findings_hash`. This is fine — the ledger is an optimization, not a requirement.

## 1. Resolve the PR

```bash
PR=${1:-$(gh pr view --json number -q .number 2>/dev/null)}
[ -z "$PR" ] && { echo "ABORT: no PR resolved. Pass a PR number."; exit 1; }
gh pr view "$PR" --json state,isDraft,mergeable,baseRefName -q . > /tmp/review-loop-pr-$PR.json
```

Stop with a clear message if the PR is closed, merged, or in draft.

## 2. Iterate

Each iteration runs in a **fresh sub-agent** so the orchestrator's context stays roughly constant across iterations. The orchestrator's only per-iteration state is `prev_findings_hash` (for the loop-detection guard) and a short `iteration_results` log used in §4.

For iteration `i` from 1 to `--max-iterations`:

1. **Launch one sub-agent** via the `Agent` tool with `subagent_type: "general-purpose"`. Give it the prompt below (substitute `<PR>` and the `--strict` flag value). Do **not** invoke `/review-pr` or `/autofix` from the orchestrator directly — the worker owns that context.

   Worker prompt (self-contained — the worker has no view of this conversation):

   > You are one iteration of the review-loop harness for PR **#<PR>** in the current repo. Strict mode: **<true|false>**.
   >
   > Do exactly this, in order:
   >
   > 1. `PR_META=$(gh pr view <PR> --json headRefOid,mergeable,baseRefName)`; from it derive `PRE_SHA`, `MERGEABLE` (`MERGEABLE` | `CONFLICTING` | `UNKNOWN` | other), and `BASE`. On `MERGEABLE == UNKNOWN`, sleep 2s and re-query once; if still `UNKNOWN`, proceed with the value as-is (degraded — next iteration retries).
   > 2. Invoke the `Skill` tool with `skill: "hivesmith:review-pr"` and `args: "<PR>"`. Capture the full BLOCKING / IMPORTANT / MINOR / Verdict output from the result. Do **not** paraphrase the review or hand-write your own — the `Skill` invocation is the only way the loop runs review-pr.
   > 3. Fetch unresolved review threads (used as a parallel finding stream — the loop cannot APPROVE while any are open). `PullRequestReviewThread` has no `url` field — the URL lives on the first comment. Author info is needed for `copilot_threads_open`:
   >    ```bash
   >    gh api graphql -f query='query($owner:String!,$repo:String!,$pr:Int!,$cursor:String){
   >      repository(owner:$owner,name:$repo){
   >        pullRequest(number:$pr){
   >          reviewThreads(first:100, after:$cursor){
   >            pageInfo{ hasNextPage endCursor }
   >            nodes{ id isResolved comments(first:1){nodes{ url author{login} }} }}}}}' \
   >      -f owner=<owner> -f repo=<repo> -F pr=<PR>
   >    ```
   >    Paginate: if `pageInfo.hasNextPage` is true, re-run with `-f cursor=<endCursor>` and concat results until exhausted. (Without pagination, PRs with >100 threads would silently let the gate pass.) Filter to `isResolved == false`. Each thread's URL is `comments.nodes[0].url`; its author login is `comments.nodes[0].author.login`. Capture `unresolved_thread_ids` (sorted) and `unresolved_thread_urls`. Count `copilot_threads_open` as unresolved threads whose first-comment author login ends with `[bot]` AND case-insensitively contains `copilot` (covers `copilot-pull-request-reviewer`, `github-copilot[bot]`, and future variants).
   > 4. Compute `findings_hash`: lowercase-hex SHA-256 over the sorted, newline-joined `file|line|category|title` tuples across all BLOCKING + IMPORTANT findings, **followed by** the sorted unresolved `thread_id`s on their own lines. (No findings and no unresolved threads → empty string.) Including thread ids ensures the loop-detection guard fires when the same set of unresolved threads sits two iterations in a row.
   > 5. Decide the next action from the verdict (and the mergeable state — `CONFLICTING` always routes to autofix, regardless of verdict, because conflicts block merge even on LGTM):
   >    - `APPROVE` with **zero unresolved threads** AND `MERGEABLE != CONFLICTING` → stop. No autofix, no push.
   >    - `APPROVE` with unresolved threads → coerce to `REQUEST_CHANGES`. The review itself had nothing to say, but Copilot / human threads are still open and must be closed by autofix (fix or reply-and-resolve with a concrete reason).
   >    - **Any verdict with `MERGEABLE == CONFLICTING`** → coerce to `REQUEST_CHANGES`. Autofix's pre-flight merge initiator (step 2.5 of the autofix skill) will surface the conflict locally and resolve SAFE conflicts or surface RISKY ones.
   >    - `COMMENT` → if strict mode is true OR there are unresolved threads, treat as `REQUEST_CHANGES`; otherwise stop.
   >    - `REQUEST_CHANGES` (including coerced) → invoke the `Skill` tool with `skill: "hivesmith:autofix"` and `args: "<PR>"`. Treat its result as the autofix outcome — do **not** hand-write fixes yourself. Then `git push`. Set `POST_SHA` from `gh pr view`. Determine whether autofix took any thread-side actions by parsing the `Threads:` breakdown in autofix's Phase 5 summary (specifically the `Fixed:` and `Resolved with rationale:` counts — sum > 0 means thread-side actions occurred). If `POST_SHA == PRE_SHA` AND the parsed `Fixed + Resolved with rationale` total is `0`, set `escalate_reason: "autofix produced no changes"`. Otherwise wait on CI: `gh pr checks <PR> --watch --interval 15`. If a required check fails non-flakily, set `escalate_reason: "required CI check failed: <name>"` and include a one-line summary in `ci_status`.
   >    - After autofix, re-query unresolved threads (same paginated GraphQL call) and record `unresolved_threads_post`. Cross-check against autofix's Phase 5 `Threads:` line `Still open:` count. If the two disagree, **trust the GraphQL re-query as source of truth** and set `escalate_reason: "autofix Threads summary disagrees with GraphQL re-query"`.
   >    - If autofix surfaces RISKY items it would not auto-apply, list them in `risky_surfaced` and set `escalate_reason: "risky fix needs human decision"`.
   >    - If either `Skill` invocation fails (tool error, missing skill, malformed result), set `escalate_reason: "skill invocation failed: <which> — <error>"` and return immediately.
   > 6. Return your result as a single fenced ```json block as the **last** thing in your reply, with this exact shape (omit optional fields when not applicable):
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
   >      "unresolved_threads_pre": 0,
   >      "unresolved_threads_post": 0,
   >      "unresolved_thread_urls": [],
   >      "copilot_threads_open": 0,
   >      "mergeable": "MERGEABLE | CONFLICTING | UNKNOWN",
   >      "escalate_reason": ""
   >    }
   >    ```
   > Cap `findings_summary` at 20 entries. Do not paste review prose, diff hunks, or CI logs into the envelope — those stay in your context only.

2. **Parse** the JSON envelope from the worker's reply. If it is missing or malformed, escalate with reason `"worker returned malformed envelope"`.

3. **Loop-detection guard.** If `envelope.findings_hash` is non-empty and equals `prev_findings_hash`, escalate with reason `"loop-detection guard: identical findings two iterations in a row"`. Otherwise set `prev_findings_hash = envelope.findings_hash`.

4. **Append to the plan ledger** (only if a matching plan was found in the cold-start step). Add one line to the plan's `## PR convergence ledger` section:

   ```
   - **<YYYY-MM-DD> iter <i>** — verdict: <APPROVE|COMMENT|REQUEST_CHANGES>; mergeable: <MERGEABLE|CONFLICTING|UNKNOWN>; findings_hash: <hex|empty>; threads_open: <post>; action: <stop|autofix+push|autofix+push (conflict)|escalated:<reason>>; head_sha: <short post_sha or pre_sha>.
   ```

   This is append-only. The orchestrator writes the line; the worker does not (the worker has no knowledge of the plan file).

5. **Branch on verdict:**
   - `APPROVE` AND `unresolved_threads_post == 0` — done. Exit the loop, append a brain entry (see §3.5) if a durable lesson was surfaced this run, then go to §4.
   - `APPROVE` with `unresolved_threads_post > 0` — never exit here. Continue to iteration `i+1` so autofix gets another pass at the open threads. If the next iteration's worker still cannot close them and we hit max iterations, §3 fires.
   - `COMMENT` with strict off AND `unresolved_threads_post == 0` — done. Same path as APPROVE.
   - `COMMENT` with `unresolved_threads_post > 0` — continue (same reasoning as APPROVE-with-threads).
   - `escalate_reason` non-empty — escalate with that reason (see §3). **Do NOT append a brain entry on escalation** — non-converged runs are unreliable.
   - Otherwise — append a short line to `iteration_results` (`#i: <verdict>, <N> findings, threads=<post>, pushed=<bool>`) and continue to iteration `i+1`.

## 3.5 Brain append on convergence

When the loop converges (APPROVE or COMMENT-with-strict-off), inspect the cleared findings. If a recurring *pattern* surfaced (e.g. "fixture file path drift", "shellcheck SC2086 came up across three files", "autofix kept widening try/except"), distill it into a one-paragraph lesson and append:

```
echo "<distilled pattern + how to avoid it next time>" | HIVESMITH_SKILL=hs-review-loop \
  ~/.hivesmith/bin/brain-append \
  --slug "<kebab-case-pattern-name>" \
  --scope project \
  --tags "review,autofix,<dimension>" \
  --confidence 0.5
```

Do not log run-specifics (which file, which PR) — those are in git history. Capture the *pattern*. Skip if the cleared findings were one-offs with no transferable lesson — silence is fine.

## 3. Escalation criteria

Stop the loop and surface to the user when any of these hit:

- Max iterations reached without `APPROVE`.
- Loop-detection guard fires (same findings two iterations in a row).
- Autofix produced no changes but findings remain.
- A required CI check fails twice with the same error (not a flake).
- A finding is classified RISKY by autofix and would change behavior in a way the user has not pre-authorized.
- A reviewer dimension explicitly disagreed with another (e.g. Security says block, UX says it's fine and the fix conflicts) — surface both rationales.
- The iteration sub-agent returned a non-empty `escalate_reason` (autofix made no changes, required CI failed, RISKY fix needs human decision, etc.) — propagate that reason verbatim.
- Max iterations reached AND `unresolved_threads_post > 0` — escalate with reason `"unresolved review threads remain (N): <urls>"` listing every open thread URL. This is the load-bearing case: it's what stops the loop from quietly converging while Copilot or human comments sit open.

When escalating, post a single PR comment summarizing:
- Iteration count reached.
- The unresolved findings (deduped, with file:line and confidence).
- The reason the loop stopped.
- A suggested next step the human can take.

## 4. Output

```
## Review loop result
PR: #<n>
Iterations: <i>/<max>
Final verdict: APPROVE | ESCALATED
<reason if escalated>

## Findings cleared this run
<bullet list>

## Findings remaining (if escalated)
<bullet list>
```

## 4a. On merge (best-effort post-loop hook)

If, after the loop converges with `APPROVE`, the orchestrator detects the PR has been merged (e.g. user merges in a separate window before this skill exits, or `/feature-loop` Phase 6 calls back into review-loop after merging): if a matching spec was found and its frontmatter `stage:` is `REVIEW`, set it to `QA` in the spec's frontmatter — that's the sole stage write. **Do not edit `docs/product-specs/index.md`** (it's generated). Tell the user to run `/feature-qa <issue-number>` next. Do not move the plan file or touch the Completed table — that is `/feature-qa`'s job after QA PASS.

## 5. Rules

- Never merge from inside the loop. Convergence is "no BLOCKING findings"; merging is the human's call (or a separate skill).
- Never overwrite the user's pre-authorization. If the user said "do not change file X", autofix's RISKY classifier should hold — escalate instead.
- Always push after autofix runs and CI completes before re-reviewing — re-reviewing the old diff wastes a turn.
- Loop budget is finite. Five iterations is the default; more than that suggests the harness, not the loop, needs work.
- Run review-pr and autofix as full skill invocations via the `Skill` tool (plugin-qualified: `hivesmith:review-pr`, `hivesmith:autofix`), not by inlining their prompts or relying on slash-command syntax inside sub-agents. They evolve independently and the loop should track them.
- Each iteration runs in a fresh sub-agent context. The orchestrator keeps only the result envelope (`verdict`, `findings_hash`, short `findings_summary`, thread counts, `escalate_reason`) — never the raw review prose, diffs, or CI logs. This keeps the orchestrator's per-iteration footprint flat regardless of iteration count.
- **Unresolved review threads block APPROVE.** Existing PR review comments — including Copilot's automated review — are findings, not context. Autofix owns resolving them (apply a fix and reply `Fixed in <SHA>.`, or reply with a concrete reason and resolve the thread). The loop only enforces the gate: while any thread remains unresolved, the loop keeps running, and at max iterations it escalates with the open thread URLs. Copilot threads get the same treatment as human threads — never silently ignored.
