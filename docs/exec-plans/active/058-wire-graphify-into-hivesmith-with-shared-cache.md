# Wire graphify into hivesmith with shared cache and auto-refresh hooks

- **Spec:** [docs/product-specs/058-wire-graphify-into-hivesmith-with-shared-cache.md](../../product-specs/058-wire-graphify-into-hivesmith-with-shared-cache.md)
- **Issue:** #58
- **Status:** active
- **PR:** #59
- **Branch:** `feature/58-wire-graphify-into-hivesmith-with-shared-cache`

## Summary

Ship `/hs-graphify-init`, a hivesmith skill that wires graphify into a project so its knowledge graph stays fresh inside git worktrees without re-paying for semantic extraction per worktree. Three moving parts: a shared extraction cache under the git common dir, graphify's own git hooks with the worktree guard lifted, and a debounced Claude Code `PostToolUse` hook doing AST-only incremental rebuilds.

## Research

Authored via plan-first mode. Findings from reading the installed graphify **0.9.53** package and this repo:

**Reuse (already upstream — do not reimplement):**

- `graphify/paths.py` — `GRAPHIFY_OUT` env override; `_atomic_replace` (temp file + `os.replace`, symlink-transparent — it resolves the destination via `os.path.realpath` and writes *through* the link, which is what makes the symlinked cache safe).
- `graphify/hooks.py` + `graphify hook install` — post-commit/post-checkout, pinned-interpreter detection, cross-platform detached launch, flock, rebase/merge skip, `GRAPHIFY_SKIP_HOOK` opt-out. Hooks land in `$(git rev-parse --git-common-dir)/hooks`, so one install covers every worktree.
- `graphify update <path>` — incremental, AST-only, no LLM. `--no-cluster` skips clustering.
- `graphify claude install` — upstream `PreToolUse` orientation nudges; merge semantics in `graphify/install.py:_install_claude_hook` (read → filter prior graphify entries → append → write with backup) are the model for our own settings merge.
- `graphify/cache.py:cache_dir()` — cache keys are SHA-256 of file contents; AST entries are namespaced `cache/ast/v{version}-s{schema}/` and stale ones pruned, semantic entries are `cache/semantic/` and deliberately *not* version-namespaced (re-extraction costs LLM calls, #1252).

**The three gaps:**

1. `graphify/hooks.py:295` — `_WORKTREE_GUARD` is spliced unconditionally into both generated hooks and does a bare `exit 0` whenever `git rev-parse --git-dir != --git-common-dir`. Upstream's rationale (#1809, #1806) is that the canonical graph belongs to the primary checkout; that is the opposite of hivesmith's working model.
2. `cache_dir()` resolves to `Path(root).resolve() / graphify-out / cache / kind` — per checkout. `~/.graphify-cache/` on this machine is a dead pre-0.5.3 layout; no current code path reads it (`grep -rn "graphify-cache" graphify/*.py` returns nothing).
3. `AGENTS.md:1-5` carries a hand-written Graphify section telling agents to run `graphify . --update` manually. No enforcement.

**Repo facts that shape the work:**

- `install.sh:321` auto-discovers `skills/*/` — no skill list to edit. But the executable-bit list near `install.sh:1046` (`"skills/brain-promote/promote.sh:brain-promote"`, …) does need the new scripts.
- `.gitignore` ignores `.claude/` wholesale; `scripts/dev-link-local.sh` only writes under `.claude/skills/`, so a narrow `!.claude/settings.json` negation is safe.
- Test convention is assert-style bash, bash 3.2 compatible — `scripts/brain/test/run-all.sh` is the model. No Python test framework in the repo.
- CI jobs: `shellcheck`, `install-smoke`, `render-correctness`, `subagent-linking`, `brain-tests`, `install-smoke-macos` (`.github/workflows/ci.yml`). The shellcheck job's file list is mirrored in `AGENTS.md` and must stay in sync.
- `skills/hivesmith-init/SKILL.md:109` currently prints a passive "tip: install graphify".

## Approach

Reproduced from the approved plan.

The load-bearing idea: **the shared cache lives inside `$(git rev-parse --git-common-dir)`**. That directory is the one location every worktree already agrees on, it is never tracked, it needs no `.gitignore` entry, it survives `git clean -xfd` inside a worktree, and it disappears when the repo does. Each worktree's `graphify-out/cache` becomes a symlink into it; each worktree keeps its own `graph.json`, which is correct because each is on its own branch.

Concurrency is safe by construction rather than by locking: cache entries are keyed by SHA-256 of file contents and written through `paths._atomic_replace`. Two worktrees writing the same key write identical bytes; two writing different keys do not collide.

### 1. `/hs-graphify-init` — the skill

Thin orchestrator: check graphify is importable, compare the packaged version against `~/.claude/skills/graphify/.graphify_version` and warn on drift (currently 0.4.23 vs 0.9.53 — a stale skill silently teaches the agent an old CLI), then run `graphify-setup.sh` and report what changed. Accepts `--uninstall` and `--migrate`.

### 2. `graphify-setup.sh` — the worker

**a. Shared cache.** Resolve `COMMON=$(git rev-parse --git-common-dir)` to an absolute path; `SHARED=$COMMON/graphify-cache`. `mkdir -p` both it and `graphify-out/`. If `graphify-out/cache` is already the right symlink, no-op. If it is a real directory, **refuse and exit non-zero** unless `--migrate` is passed, in which case copy its contents into `$SHARED` (never overwriting a newer entry) and then replace it with the symlink. Silently deleting a populated semantic cache is real money.

**b. Git hooks, worktree-enabled.** Run `graphify hook install` (upstream writes into `$COMMON/hooks`, so one install covers every worktree). Then rewrite *only* the guard's terminal `exit 0` to be conditional:

```bash
    [ "${HIVESMITH_GRAPHIFY_WORKTREE:-1}" = "1" ] || exit 0
```

The patch is applied by matching the exact upstream guard text. If the match fails — i.e. upstream reshaped the block in a newer release — the script **exits non-zero naming the graphify version it saw** rather than leaving the user with silently-stale worktrees. A test asserts the patch applies against the currently installed graphify, so a version bump that breaks it fails CI, not production.

**c. Claude Code `PostToolUse` hook.** Merge a `PostToolUse` entry matching `Edit|Write|MultiEdit` into `.claude/settings.json`, command `scripts/graphify-refresh.sh`. Merge semantics mirror graphify's own installer: read, filter out any prior hivesmith-graphify entry, append, write with backup — so re-running never duplicates and never clobbers unrelated hooks. Also run `graphify claude install` for the upstream `PreToolUse` orientation nudges.

**d. `graphify-refresh.sh` — the debounce.** Ordered cheapest-check-first so the common case costs one `stat`:

```bash
[ "${HIVESMITH_GRAPHIFY_REFRESH:-1}" = "1" ] || exit 0
[ -f graphify-out/graph.json ] || exit 0      # never bootstrap from a hook
stamp=graphify-out/.graphify_refresh_stamp
age=$(( $(date +%s) - $(mtime "$stamp") ))
[ "$age" -lt "${HIVESMITH_GRAPHIFY_DEBOUNCE:-90}" ] && exit 0
touch "$stamp"
graphify update . --no-cluster >>graphify-out/.refresh.log 2>&1 &
exit 0
```

Three invariants: it **never blocks** the agent, it **never exits non-zero** (a hook failure must not fail a tool call), and it **never bootstraps** a graph from scratch — an absent `graph.json` means the user has not run `/graphify` yet, and a hook is the wrong place to start a multi-minute build.

**e. AGENTS.md block.** Replace this repo's hand-written Graphify section with a marker-delimited `<!-- BEGIN HIVESMITH GRAPHIFY -->` block, matching the existing `BEGIN HIVESMITH` convention so it is regenerable. It documents orientation via `GRAPH_REPORT.md`, querying via `graphify query` / `graphify affected`, and — correcting the current text — that refresh is now automatic, so agents should stop being told to run it by hand.

**f. Uninstall.** Restores `graphify-out/cache` as a real directory (copying back from shared), removes the hook blocks, and strips the settings entry.

### 3. Distribution

`install.sh` auto-discovers `skills/*/`, so no list edit is needed — but the executable-bit list around `install.sh:1046` does need the two new scripts. `templates/scripts/` gets copies so `/hs-hivesmith-init` scaffolds them into new projects, and that skill's passive "tip: install graphify" (`skills/hivesmith-init/SKILL.md:109`) becomes an actual offer to run `/hs-graphify-init`.

### Files to change

- `AGENTS.md` — replace the ad-hoc Graphify section with the generated block; add both new scripts to the shellcheck command list; add the new test suite to the build/test commands.
- `.github/workflows/ci.yml` — add the two scripts to the `shellcheck` job; add a `graphify-init-tests` job running the new suite.
- `.gitignore` — add `!.claude/settings.json` so the committed hook config ships while `settings.local.json` and the `dev-link-local.sh` symlinks under `.claude/skills/` stay ignored.
- `skills/hivesmith-init/SKILL.md` — line 109: replace the passive tip with an offer to run `/hs-graphify-init`.
- `CHANGELOG.md` — `[Unreleased]` entry (CI gate requires non-empty). Per repo convention this lands as a `.changesets/` file.

### New files

- `skills/graphify-init/SKILL.md` — the skill body: preflight, version-drift warning, invoke setup, report.
- `skills/graphify-init/graphify-setup.sh` — shared-cache symlink, hook install + guard patch, settings merge, AGENTS.md block, `--migrate` / `--uninstall`.
- `skills/graphify-init/graphify-refresh.sh` — debounced AST-only refresh, called by `PostToolUse`.
- `skills/graphify-init/test/run-all.sh` — assert-style suite, bash 3.2 compatible, mirroring `scripts/brain/test/run-all.sh`. 18 tests after review iteration 2.
- `scripts/graphify-refresh.sh` — the copy `graphify-setup.sh` places in a wired project; committed here because this repo dogfoods the setup. Kept in sync with the skill copy by `test_refresh_copy_in_sync`.
- `.gitattributes` — written by `graphify hook install` (union merge driver for `graph.json`). Committed so a setup re-run leaves a clean worktree.
- `.changesets/<n>-graphify-init.md` — per repo convention.

### Tests

New suite `skills/graphify-init/test/run-all.sh`. Each case builds a throwaway git repo plus a linked worktree in a `mktemp -d`.

- `test_shared_cache_symlink` — after running setup in both primary and worktree, each `graphify-out/cache` is a symlink and both `readlink -f` to the same `$COMMON/graphify-cache`.
- `test_migrate_preserves_entries` — pre-seeded `graphify-out/cache/semantic/<hash>.json` survives `--migrate` and is readable through the symlink.
- `test_refuses_to_clobber_cache` — without `--migrate`, a populated real cache dir causes non-zero exit and the file is untouched.
- `test_worktree_guard_lifted` — against the *actually installed* graphify: the guard patch applies, and the generated `post-commit` no longer contains an unconditional `exit 0` inside the guard block.
- `test_guard_patch_fails_loudly` — given a `post-commit` whose guard text does not match, setup exits non-zero and the message names the graphify version.
- `test_refresh_debounces` — two back-to-back refresh calls launch exactly one rebuild; a third after the window launches a second.
- `test_refresh_noop_without_graph` — no `graph.json` ⇒ exit 0, no process spawned, no stamp written.
- `test_refresh_never_fails` — with `graphify` absent from `PATH`, refresh still exits 0.
- `test_setup_idempotent` — two runs ⇒ one hook block (not two), byte-identical `.claude/settings.json`, one `AGENTS.md` block.
- `test_uninstall_reverses` — symlink replaced by a real dir with contents intact, hook blocks stripped, settings entry gone.
- `test_settings_merge_preserves_others` — a pre-existing unrelated `PostToolUse` hook survives install *and* uninstall.

## Verification

```bash
# New suite
skills/graphify-init/test/run-all.sh

# Lint (new scripts appended to the AGENTS.md / CI list)
shellcheck skills/graphify-init/graphify-setup.sh skills/graphify-init/graphify-refresh.sh \
           templates/scripts/graphify-setup.sh templates/scripts/graphify-refresh.sh

# Existing gates that this change passes through
scripts/brain/test/run-all.sh
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix "" --no-auto-update --dry-run
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .

# End-to-end smoke in this repo (dogfood)
skills/graphify-init/graphify-setup.sh
readlink graphify-out/cache        # -> <git-common-dir>/graphify-cache
grep -c 'HIVESMITH_GRAPHIFY_WORKTREE' "$(git rev-parse --git-common-dir)/hooks/post-commit"   # -> 1
```

## Decision log

- **2026-08-30** — Shared cache lives at `$(git rev-parse --git-common-dir)/graphify-cache`, not `<primary>/graphify-cache`. Why: it is the one path every worktree resolves identically regardless of creation order, is never tracked, needs no `.gitignore` entry, and survives `git clean -xfd` inside a worktree.
- **2026-08-30** — Per-worktree `graph.json`, shared cache only (not a single shared `GRAPHIFY_OUT`). Why: worktrees sit on different branches; one shared graph would have them overwrite each other, and flock serializes that without making it correct.
- **2026-08-30** — All automatic refresh paths are AST-only (`graphify update`). Why: semantic extraction is LLM spend; no hook should be able to bill the user.
- **2026-08-30** — The worktree guard is lifted by patching upstream's generated hook text, with a loud failure when the match breaks. Why: reimplementing the hook would discard upstream's flock, timeout, detach and interpreter-detection logic. Accepted cost: version coupling, covered by a test that runs against the installed graphify.
- **2026-08-30** — `.claude/settings.json` is committed via a narrow `.gitignore` negation. Why: a `PostToolUse` hook that is not shared is not a project setup. Raised as an open question at plan review; approved at the stated default.
- **2026-08-30** — Dropped the planned `templates/scripts/graphify-*.sh` copies. Why: `graphify-setup.sh` copies the refresh script into the target project itself, so a template copy would be a third source of the same file to keep in sync. `/hs-hivesmith-init` now offers to run the skill instead of scaffolding scripts it cannot keep current.
- **2026-08-30** — No `install.sh` change needed. Why: it already auto-discovers `skills/*/` and renders with `cp -R`, which preserves the executable bit; the list near line 1046 is the brain-specific PATH-symlink list, not a general chmod list. The scripts are invoked by path, not from `PATH`.
- **2026-08-30** — `.gitignore` uses `.claude/*` + `!.claude/settings.json`, not `.claude/` + a negation. Why: git cannot re-include a file whose parent directory is excluded, so the negation is silently inert against a directory pattern. Verified with `git check-ignore -v`.
- **2026-08-30** — `graphify-setup.sh` resolves the shared-cache path with `pwd -P`. Why: on macOS a repo reached via a symlinked path (`/var` -> `/private/var`) would otherwise record a logical target that differs per route; the symlink must point at a physical path.
- **2026-08-30** (review iter 1) — `--migrate` / `--uninstall` copy with a single `cp -R … || die` instead of a `find | while` pipeline. Why: the loop body ran in a subshell on the right of a pipe, so a failure flag set inside it could never reach the following `rm -rf` — a swallowed copy error destroyed the very cache the `die` above it exists to protect. Review finding, BLOCKING.
- **2026-08-30** (review iter 1) — Wired graphify's `PreToolUse` orientation nudges by calling `graphify.install._install_claude_hook(Path('.'), project=True)` directly rather than `graphify claude install`. Why: the CLI also writes a graphify section into `CLAUDE.md`, duplicating the `AGENTS.md` block this script maintains. `project=True` emits a bare command rather than an installing-machine-specific path (graphify #3129), which is correct for a committed `settings.json`. Best-effort with a graceful skip, since it reaches into a private function. Closes the plan/code gap the review flagged.
- **2026-08-30** (review iter 1) — Documented rather than "fixed" the refresh debounce race. Why: `graphify.watch._rebuild_code` already takes a non-blocking per-repo flock (`watch.py:1327`), so a second concurrent `graphify update` exits instead of racing. The debounce avoids process-spawn cost; mutual exclusion lives downstream. A second lock would be redundant machinery guarding an already-guarded section.
- **2026-08-30** (review iter 1) — Kept `graphifyy` unpinned in CI. Why: the `graphify-init-tests` job exists to catch upstream reshaping its generated hook text. Pinning would test a version nobody runs and let the drift reach users undetected. Operator decision.
- **2026-08-30** (review iter 1) — Kept `.gitattributes` committed despite `merge=graphify` being inert here (graph.json is gitignored). Why: `graphify hook install` recreates it on every setup run, so deleting it makes each run dirty the worktree. Documented in the file itself.
- **2026-08-30** (review iter 1) — Capped `.refresh.log` at 1 MiB (`HIVESMITH_GRAPHIFY_LOG_CAP`) and left `scripts/graphify-refresh.sh` a copy rather than a symlink. Why: a symlink's survival through `install.sh`'s `cp -R` rendering is an unverified risk, and `test_refresh_copy_in_sync` already fails the build on drift.
- **2026-08-30** (review iter 2) — Guard-patch temp files now come from `mktemp "$hook.hivesmith.XXXXXX"`. Why: `$hook` lives in the git COMMON hooks dir, so every worktree derived the identical fixed temp path — two concurrent `/hs-graphify-init` runs, the exact scenario this feature exists for, could interleave and `cat` a corrupted hook into place. Review finding.
- **2026-08-30** (review iter 2) — The `PreToolUse` nudges added in iter 1 got `--no-nudges` / `HIVESMITH_GRAPHIFY_NUDGES=0`, plus documentation in SKILL.md, the AGENTS.md block, and the changeset. Why: iter 1's decision entry justified *how* they were installed but never weighed that they print agent-directing text on an agent's most frequent tool calls, and that a committed `settings.json` delivers them to everyone who clones the repo rather than only whoever ran the skill. Undocumented and un-disableable was the actual defect; the hooks themselves stay on by default because orienting before grepping is the point of having a graph.
- **2026-08-30** (review iter 2) — `test_migrate_failure_preserves_cache` now asserts setup exited non-zero before asserting the cache survived. Why: it previously discarded the exit status, so the day `chmod a-w` stops blocking the write (root, an ACL, a refactor that copies before it checks) the test would pass vacuously and silently stop covering the data-loss path it was added for.
- **2026-08-30** — `/hs-graphify-init` stays an explicit offer in `/hs-hivesmith-init`, not an automatic step. Why: installing git hooks and editor hooks unprompted is the wrong default. Raised at plan review; approved at the stated default.

## Progress

- **2026-08-30** — Plan-first scaffold; stage = IMPLEMENT (set in spec frontmatter).
- **2026-08-30** — Review iteration 2: COMMENT (no BLOCKING), 3 IMPORTANT, zero threads. Technically convergence under the loop rules, but two findings were real defects introduced by the iter-1 fix commit, so continued rather than stopping: fixed-name temp files racing across worktrees, and a vacuously-passing safety test. Also gave the PreToolUse nudges an opt-out plus documentation. 18 tests.
- **2026-08-30** — Review iteration 1: REQUEST_CHANGES, escalated (autofix found zero SAFE fixes — all 10 findings were design decisions). Fixed the BLOCKING `--migrate` data-loss defect and its `--uninstall` twin, closed the `graphify claude install` plan gap, added 3 tests (16 total), capped the refresh log. Documented the debounce/flock relationship, `.gitattributes`, and the CI-pinning decision rather than changing them.
- **2026-08-30** — Implemented on `feature/58-wire-graphify-into-hivesmith-with-shared-cache`. Skill + two scripts + 13-test suite written; repo wired (AGENTS.md, ci.yml, .gitignore, hivesmith-init, changeset); setup dogfooded in this worktree. All AGENTS.md checks pass: shellcheck (28 scripts), graphify-init suite 13/13, brain suite 13/13, install smoke (both prefixes), render correctness, changelog gate.

## Open questions

None blocking. Deferred, not blocking:

- Shared cache growth is unbounded — upstream prunes stale AST entries by version namespace but not semantic ones. A `--prune` is future work.
- The 90s debounce default is a guess, not a measurement. Revisit after real use; tunable via `HIVESMITH_GRAPHIFY_DEBOUNCE`.
- Worth filing upstream regardless: ask graphify for a `GRAPHIFY_ALLOW_WORKTREE=1` escape hatch so the guard patch can be deleted.

## PR convergence ledger

- **2026-08-30 iter 2** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 92f097ccff3c8bb5121a1e85dc75931e988f54e5b157d7a7ce8f37ec9349e5c8; threads_open: 0; action: fixes applied by operator decision (continued past technical convergence per boil-the-lake); head_sha: d43453c.
- **2026-08-30 iter 1** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: 40a4c2f4c53fadd11a3b6ac81f9d0dc8f0d5f0f2b3fb4e00cf7b0e0e6a89c47f; threads_open: 0; action: escalated:risky fix needs human decision; head_sha: e94a5e4.

## QA verdict
