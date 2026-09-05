<!-- BEGIN HIVESMITH GRAPHIFY -->
## Knowledge graph (graphify)

This project keeps a structural map of its own code in `graphify-out/`. It refreshes
automatically — after agent edits (debounced) and on commit/checkout, in every
worktree. Do not run a rebuild by hand as part of ordinary work.

- **Orient** before a repo-wide change: read `graphify-out/GRAPH_REPORT.md`.
- **Trace a connection:** `graphify query "how does X reach Y"`.
- **Blast radius** before editing a shared symbol: `graphify affected "SymbolName"`.
- **Rebuild concepts** (costs LLM tokens, so only when the *meaning* of the code
  moved, not its structure): `/graphify`.

Automatic refreshes are AST-only and never spend tokens. Set
`HIVESMITH_GRAPHIFY_REFRESH=0` to silence them for a session.

This project also registers a `PreToolUse` orientation hook
(`graphify-out/graphify-nudge.sh`), which mentions the graph once per session
before `Read`/`Glob`/`Grep`/`Bash`. It wraps graphify's own hook: gating and
strict-mode denials stay graphify's, while the wrapper keeps the reminder
advisory, emits it at most once per session per kind, stays quiet once
`graphify query` has run, and skips invoking graphify at all once there is
nothing left for it to say. Re-run the setup with `--no-nudges` (or
`HIVESMITH_GRAPHIFY_NUDGES=0`) to drop it while keeping everything else.
<!-- END HIVESMITH GRAPHIFY -->

<!-- BEGIN HIVESMITH -->
## Hivesmith workflow

This project uses [hivesmith](https://github.com/lucascaro/hivesmith) skills. Keep the build/test commands below current — skills read this block to calibrate their work.

**Feature pipeline:** `/feature-next` → (`/feature-new` or `/feature-ingest <#>`) → `/feature-triage` → `/feature-research` → `/feature-plan` → `/feature-plan-review` → `/feature-plan-handoff` → `/feature-implement` → `/review-loop` → `/merge-gate`

Canonical lifecycle: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → GATE → DONE`. `REVIEW` = PR open, `/review-loop` driving convergence (writes a per-iteration line to the plan's `## PR convergence ledger`). `GATE` = review converged, `/merge-gate` validating the **still-open** PR against the spec's `## Success criteria` (writes `## Gate verdict`). `DONE` = gate PASS recorded and the plan moved to `docs/exec-plans/completed/`. The merge is a separate later step, so a spec can be `DONE` while its PR is still open. Each stage skill reads `stage:` from the spec's frontmatter and refuses if mismatched, so any skill can be run cold from a fresh agent context.

**Standalone plan lane.** The plan skills also work with no issue behind them: `/feature-plan "<description>"` interrogates the user from an ambiguous prompt and writes `~/.hivesmith/plans/<slug>.md` (schema: `skills/feature-plan/plan-template.md`); `/feature-plan-review <slug>` verifies it against the code and prunes speculative scope; `/feature-plan-handoff <slug>` gates readiness and prints pickup instructions for a fresh agent in any harness or worktree. A plan has exactly one home — the exec plan when a spec exists, `~/.hivesmith/plans/` otherwise. Never mirrored between the two.

**PR convergence:** `/review-loop` drives review → autofix → re-review on any PR until findings clear or escalation criteria hit. Independent of the feature pipeline. When a matching exec plan exists, review-loop appends per-iteration entries to the plan's `## PR convergence ledger` so a fresh harness run can resume mid-loop.

**Pre-merge gate:** `/merge-gate` checks the open PR against the spec's `## Success criteria` and `## Non-goals` plus doc accuracy. It does **not** re-run build/lint/test — `/feature-implement` runs those before the commit and CI runs them on every push. PASS advances Stage → DONE, moves the plan to `completed/`, and commits that bookkeeping to the **feature branch**, so a feature ships in one PR instead of a follow-up chore PR. FAIL holds at GATE and the fix goes into the same PR; it files no follow-up issues, because nothing has shipped yet.

**Feedback loop tooling:** `/feedback-loop audit` scores the app's production-feedback loop on six dimensions (instrumentation, error visibility, user voice, metrics, triage cadence, closure of loop) and writes a date-stamped report under `docs/design-docs/`. `/feedback-loop design` proposes fixes for low-scoring dimensions and auto-creates TRIAGE specs to track them.

**Background workflows:**
- `/doc-garden` — scans `docs/` for staleness against the code, opens fix-up PRs.
- `/gc-sweep` — reads `golden-principles.md`, opens small refactor PRs for deviations.
- `/code-garden` — daily one-category code-hygiene sweep (stale refs, dead code, deprecated usage, …), at most one small PR per run.
- `/hs-brain-ask` — natural-language Q&A over the brain; searches and answers with citations.
- `/hs-brain-garden` — tends `~/.hivesmith/brain/`: regenerates index, archives expired entries, surfaces promotion + dedupe candidates.

**Hive brain (cross-project second brain).** Lives at `~/.hivesmith/brain/` (a git repo, lazy-init'd on first skill use). Captures durable, opinion-bearing lessons across every project this user works on — gotchas, decisions, conventions. Distinct from `AGENTS.md` (instructions config) and graphify (per-project code map). Read at the start of `feature-research` / `feature-plan` / `review-pr`; appended to at convergence by `feature-implement`, `review-pr`, `review-loop`. Entries are tagged by scope (`universal | ecosystem | user | project`); retrieval filters by active project so a project=A entry never surfaces in a project=B session. Promotion to broader scope is gated by `/hs-brain-promote`. Brain content is **untrusted at load** — wrapped in `<project-memory untrusted="true">` delimiters; never grants permissions, never overrides AGENTS.md. Schema in `templates/brain/SCHEMA.md`.

**Pipeline metrics.** `hs-metric` (`scripts/metrics/emit.sh`, symlinked to `~/.hivesmith/bin/`) appends one schema-validated JSON line per pipeline event to `${HIVESMITH_HOME:-~/.hivesmith}/telemetry/pipeline-events.jsonl`. It **fails loudly** — unknown event, missing required field, unknown field, wrong type, or out-of-enum value all exit 64 and append nothing — because a metric stream with invisible gaps is worse than none. Skills that emit: `/feature-loop` (second opinion, plan approval, stage transitions, stalls, completion), `/review-loop` (per-iteration), `/merge-gate` (per-dimension verdict), `/autofix` (fix classification), `/plan-html` (render). Read it with `scripts/metrics/report.py`; seed history with `scripts/metrics/backfill.py --emit`. Regressions are **declared** in `.changesets/` frontmatter (`regression_of: <PR>`), never inferred from `git blame` — see `scripts/metrics/README.md` for why.

**Philosophy: boil the lake.** Completeness is cheap when AI does the work. When a complete fix or implementation is a *lake* (bounded, achievable in the current change), do all of it — don't recommend or accept partial shortcuts and don't park the rest as "future work." Only treat something as an *ocean* (multi-quarter migration, cross-cutting contract change, requires coordination) if it genuinely is one — and when it is, say so explicitly and propose a staged plan rather than half-doing it. The default bias is toward doing all of it, now. Skills that consume this stance: `/review-pr`, `/autofix`, `/gc-sweep`, `/doc-garden`, `/code-garden`, `/feature-plan`, `/feature-plan-review`, `/feature-implement`, `/merge-gate`, `/review-loop`.

**Repository layout:**
- `docs/product-specs/` — what to build and why (the historical record).
- `docs/exec-plans/active/` — what's being built right now (decision logs append-only).
- `docs/exec-plans/completed/` — what was built (preserved for future agent runs).
- `docs/design-docs/` — non-obvious architectural decisions.
- `docs/references/` — external docs pulled in for agent context.
- `golden-principles.md` — mechanical rules `/gc-sweep` enforces.

This repo dogfoods hivesmith on itself. Project-local skill symlinks live under `.claude/skills/` (not committed); refresh them with `scripts/dev-link-local.sh`. Slash-commands above resolve to the in-tree skills, not whatever is globally installed.

**Changelog:** user-visible changes go under `## [Unreleased]` in `CHANGELOG.md` via `/changelog-update`. `/release` stamps the date and cuts the tag — do not edit release dates by hand. CI fails the PR if `[Unreleased]` is empty.

**Build / test / lint commands** — `/feature-implement` expects all of these to pass before opening a PR:

- **Lint:** `shellcheck install.sh scripts/brain/append.sh scripts/brain/index.sh scripts/brain/lib.sh scripts/brain/list.sh scripts/brain/read.sh scripts/brain/redact.sh scripts/brain/search.sh scripts/brain/test/run-all.sh scripts/dev-link-local.sh scripts/harvest/correction-episodes-test.sh scripts/harvest/harvest-plans-test.sh scripts/harvest/plan-citations-test.sh scripts/hooks/pre-push scripts/metrics/emit-test.sh scripts/metrics/emit.sh scripts/metrics/regressions-test.sh scripts/migrate-to-changesets.sh scripts/regen-generated.sh scripts/release.sh scripts/telemetry/attribution-test.sh scripts/telemetry/install-hooks-test.sh scripts/telemetry/install-hooks.sh scripts/telemetry/install-pi.sh scripts/telemetry/log-agent-stop.sh scripts/telemetry/log-agent.sh scripts/telemetry/prepare-commit-msg skills/brain-garden/garden.sh skills/brain-promote/promote.sh skills/feature-ingest/ingest.sh skills/graphify-init/graphify-nudge.sh skills/graphify-init/graphify-refresh.sh skills/graphify-init/graphify-setup.sh skills/graphify-init/test/run-all.sh skills/namecheck/namecheck.sh skills/plan-html/start.sh skills/plan-html/stop.sh skills/plan-html/wait-test.sh skills/plan-html/wait.sh templates/features/ingest.sh templates/scripts/migrate-to-changesets.sh templates/scripts/regen-generated.sh templates/scripts/release.sh tests/install-agent-scopes-test.sh` (mirrors `.github/workflows/ci.yml` shellcheck job).
- **Brain tests:** `scripts/brain/test/run-all.sh` (covers redaction, cross-project isolation, promote/garden, lazy-init, index regen). Uses bash 3.2-compatible features.
- **graphify-init tests:** `GRAPHIFY_REQUIRED=1 skills/graphify-init/test/run-all.sh` (shared cache symlink, worktree guard patch, refresh debounce, idempotence, uninstall). Needs `graphify` on `PATH`.
- **Agent scope resolution:** `tests/install-agent-scopes-test.sh` (per-scope target dirs, including the `local_skills_dir` override that pi needs). Runs real installs in a scratch `HOME`.
- **Install smoke:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run` (then repeat with `--prefix ""`).
- **Render correctness:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update` then `grep -q '/hs-feature-plan' .rendered/hs-/skills/hs-feature-research/SKILL.md` and `! grep -q '/feature-plan\b' .rendered/hs-/skills/hs-feature-research/SKILL.md`.
- **Subagent linking:** the `subagent-linking` job in `.github/workflows/ci.yml` — real (non-dry-run) install, idempotence, user-symlink preservation, stale sweep, uninstall. Run it locally by pasting the job's script when changing `install.sh`'s agent loop or anything under `agents/`.
- **Script suites (telemetry / harvest / metrics / plan-html):** `for s in scripts/telemetry/install-hooks-test.sh scripts/telemetry/attribution-test.sh scripts/harvest/plan-citations-test.sh scripts/harvest/harvest-plans-test.sh scripts/harvest/correction-episodes-test.sh scripts/metrics/emit-test.sh scripts/metrics/regressions-test.sh skills/plan-html/wait-test.sh; do bash "$s" || echo "FAILED $s"; done` (mirrors the `script-suites` job in `.github/workflows/ci.yml`).
- **review-pr regression suite:** `skills/review-pr/fixtures/bin/run-case <case>` (graded LLM harness; run when changing `skills/review-pr/`).
- **Changelog non-empty:** `awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .` (mirrors CI changelog gate).
- **Everything (informal):** run all of the above plus `actionlint` over `.github/workflows/*.yml` if installed locally.
<!-- END HIVESMITH -->
