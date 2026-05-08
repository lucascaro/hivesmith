---
name: doc-garden
description: Scan docs/ for staleness against the code, open scoped fix-up PRs (one per doc)
argument-hint: "[--dry-run] [--scope <path>]"
allowed-tools: Read Glob Grep Bash Edit Write Agent
---

# Doc Garden

Recurring background sweep over `docs/` and the top-level documentation files. Detects stale documentation that no longer matches the code it describes, and opens small targeted fix-up PRs — one PR per doc.

This skill is meant to run on a cadence (cron, weekly job, or manual). Each invocation does one full sweep.

## Philosophy: boil the lake

Completeness is cheap when AI does the work. When a doc is stale, the fix-up PR for that doc fixes **every stale section in the doc**, not just the one the scanner first noticed. One-PR-per-doc is about review locality, not about leaving the rest of the doc rotten. If a doc's full re-alignment is a genuine **ocean** (the doc describes a subsystem mid-rewrite, or fixing it requires answering an open product question), say so in the PR description, mark the unaddressed sections with a single TODO referencing the open question, and propose a staged plan — don't quietly ship a partial pass. The default bias is toward fully aligning the doc, now.

## Scope

By default scans:

- `docs/design-docs/`
- `docs/product-specs/`
- `docs/exec-plans/completed/` (active plans are work-in-progress; skip)
- `docs/generated/` (verifies the file matches its declared regenerate command)
- `AGENTS.md`, `DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `PRODUCT_SENSE.md`, `FRONTEND.md`, `PLANS.md`

`--scope <path>` narrows to a single file or subtree.

## 1. Setup

```bash
git fetch origin
git status --short
[ -n "$(git status --short)" ] && { echo "ABORT: working tree dirty"; exit 1; }
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
git checkout "$DEFAULT_BRANCH" && git pull --ff-only
```

## 2. Detect staleness signals

For each in-scope doc, check (in parallel — fan out via Explore agents if there are more than a few docs):

1. **Broken cross-links.** Resolve every relative link in the file. Any link that 404s within the repo is a finding.
2. **Dead symbol references.** Every backticked code identifier (`FunctionName`, `module.path`, `path/to/file.ext`) gets grepped against the current code. Identifiers that look like code but don't appear anywhere are findings — except in `exec-plans/completed/` where stale references to since-renamed symbols are expected (note them, don't act).
3. **Last-touch staleness.** If a doc's `git log` last-touch date is older than the most recent change to any file it references by path, flag it for review. Threshold: 90 days unless the project sets its own.
4. **Generated-doc drift.** For each file under `docs/generated/`, run its declared regenerate command in a scratch checkout. Diff against committed content. Drift is a finding.
5. **Tech-debt tracker hygiene.** Rows in `docs/exec-plans/tech-debt-tracker.md` whose linked exec plan is in `completed/` and the linked PR is merged are candidates for removal.

## 3. Group findings by doc

One PR per doc. Findings that touch multiple docs are split into multiple PRs — never bundle.

For each doc with findings:

1. Create a branch: `doc-garden/<slug>-<short-hash>` where slug is the doc's filename without extension.
2. Apply mechanical fixes:
   - Update broken intra-repo links if a single unambiguous target exists.
   - Regenerate `docs/generated/*` files via their declared command.
   - Remove resolved tech-debt rows.
   - Annotate dead symbol references with `<!-- doc-garden: symbol not found in code as of <date> -->` rather than deleting (humans decide what to do).
3. Open a PR titled `docs(garden): refresh <doc>` with the body listing each finding and what was done about it.

## 4. Skip rules

Do not open a PR if:

- The only findings are last-touch staleness without any concrete drift signal — staleness alone is a hint, not a fix.
- The doc was modified within the last 7 days (someone is actively working on it).
- An open PR already exists with the `doc-garden/<slug>` branch prefix.

## 5. Output

```
## Doc garden run
Scope: <paths>
Docs scanned: <N>
Docs with findings: <M>
PRs opened: <K>

## Per-PR summary
- #<n>: <doc> — <one-line summary of fixes>
```

## 6. Rules

- One PR per doc. Reviewable in under a minute is the target.
- Mechanical fixes only. Anything that requires judgment (rewriting prose, restructuring sections) is annotated, not edited.
- Never delete a doc, even if every reference in it is dead. Empty docs are humans' call.
- `--dry-run` skips PR creation; prints what would be done.
- Skip `docs/exec-plans/active/` — those are WIP and the owners haven't shipped yet.
