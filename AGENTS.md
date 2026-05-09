## Knowledge Graph (Graphify)
This repository uses Graphify to maintain a structural map of its logic and assets.
- **Orientation:** Always read `graphify-out/GRAPH_REPORT.md` before attempting repo-wide refactors.
- **Workflow:** If you need to understand how module A connects to module B, use `graphify query`.
- **Sync:** Run `graphify . --update` after every significant file change to ensure your local map remains accurate.

<!-- BEGIN HIVESMITH -->
## Hivesmith workflow

This project uses [hivesmith](https://github.com/lucascaro/hivesmith) skills. Keep the build/test commands below current — skills read this block to calibrate their work.

**Feature pipeline:** `/feature-next` → (`/feature-new` or `/feature-ingest <#>`) → `/feature-triage` → `/feature-research` → `/feature-plan` → `/feature-implement` → `/ralph-loop` → `/feature-qa`

Canonical lifecycle: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → QA → DONE`. `REVIEW` = PR open, `/ralph-loop` driving convergence (writes a per-iteration line to the plan's `## PR convergence ledger`). `QA` = PR merged, `/feature-qa` validating against the spec's `## Success criteria` (writes `## QA verdict`). `DONE` = QA PASS; plan moved to `docs/exec-plans/completed/`. Each stage skill reads `Stage:` from the plan/index and refuses if mismatched, so any skill can be run cold from a fresh agent context.

**PR convergence:** `/ralph-loop` drives review → autofix → re-review on any PR until findings clear or escalation criteria hit. Independent of the feature pipeline. When a matching exec plan exists, ralph-loop appends per-iteration entries to the plan's `## PR convergence ledger` so a fresh harness run can resume mid-loop.

**Post-merge validation:** `/feature-qa` runs build/lint/test plus checks against the spec's `## Success criteria` and `## Non-goals`. PASS advances Stage → DONE and moves the plan to `completed/`; FAIL/NEEDS_FOLLOWUP opens follow-up issues and holds at QA.

**Feedback loop tooling:** `/feedback-loop audit` scores the app's production-feedback loop on six dimensions (instrumentation, error visibility, user voice, metrics, triage cadence, closure of loop) and writes a date-stamped report under `docs/design-docs/`. `/feedback-loop design` proposes fixes for low-scoring dimensions and auto-creates TRIAGE specs to track them.

**Background workflows:**
- `/doc-garden` — scans `docs/` for staleness against the code, opens fix-up PRs.
- `/gc-sweep` — reads `golden-principles.md`, opens small refactor PRs for deviations.

**Philosophy: boil the lake.** Completeness is cheap when AI does the work. When a complete fix or implementation is a *lake* (bounded, achievable in the current change), do all of it — don't recommend or accept partial shortcuts and don't park the rest as "future work." Only treat something as an *ocean* (multi-quarter migration, cross-cutting contract change, requires coordination) if it genuinely is one — and when it is, say so explicitly and propose a staged plan rather than half-doing it. The default bias is toward doing all of it, now. Skills that consume this stance: `/review-pr`, `/autofix`, `/gc-sweep`, `/doc-garden`, `/feature-plan`, `/feature-implement`, `/feature-qa`, `/ralph-loop`.

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

- **Lint:** `shellcheck install.sh scripts/dev-link-local.sh scripts/release.sh skills/feature-ingest/ingest.sh skills/namecheck/namecheck.sh templates/features/ingest.sh templates/scripts/release.sh` (mirrors `.github/workflows/ci.yml` shellcheck job).
- **Install smoke:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run` (then repeat with `--prefix ""`).
- **Render correctness:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update` then `grep -q '/hs-feature-plan' .rendered/hs-/skills/hs-feature-research/SKILL.md` and `! grep -q '/feature-plan\b' .rendered/hs-/skills/hs-feature-research/SKILL.md`.
- **review-pr regression suite:** `skills/review-pr/fixtures/bin/run-case <case>` (graded LLM harness; run when changing `skills/review-pr/`).
- **Changelog non-empty:** `awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .` (mirrors CI changelog gate).
- **Everything (informal):** run all of the above plus `actionlint` over `.github/workflows/*.yml` if installed locally.
<!-- END HIVESMITH -->
