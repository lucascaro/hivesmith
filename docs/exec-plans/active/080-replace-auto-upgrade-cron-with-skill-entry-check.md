# Replace the auto-upgrade cron with an upgrade check at hivesmith skill entry

- **Spec:** [docs/product-specs/080-replace-auto-upgrade-cron-with-skill-entry-check.md](../../product-specs/080-replace-auto-upgrade-cron-with-skill-entry-check.md)
- **Issue:** — (local-only, no GitHub issue)
- **Status:** active
- **PR:** #83
- **Branch:** feature/080-replace-auto-upgrade-cron-with-skill-entry-check
- **Phase:** —

<!--
Stage is **not** carried here. The spec's YAML frontmatter `stage:` is the
sole source of truth.
-->

## Summary

Remove the opt-in daily auto-upgrade cron and replace it with a cheap, cache-backed "hivesmith is behind upstream" check that a small set of operator front-door skills run at entry, offering upgrade / ask later / not until next change / never ask again. Default-on, opt-out via one global config key.

## Research

### Relevant code

- `install.sh:19,90-91,101,122-126,141-144` — `AUTO_UPGRADE_CLI`, help text, flag parsing (incl. deprecated `--no-auto-update`), local-scope rejection.
- `install.sh:166,196-201` — `auto_upgrade` config key parse (hand-rolled TOML subset, `:180-212`).
- `install.sh:218-246` — `upsert_config_key key "line"` (empty line removes; honors `DRY_RUN`). The only writer of `~/.hivesmith.toml`.
- `install.sh:272-310` — auto-upgrade resolution; `CRON_GREP` + `has_hivesmith_cron` at `:281-282`; implicit cron opt-in migration.
- `install.sh:625-626` — `--status` "auto-upgrade: cron installed/off"; `:627-643` telemetry status pattern (and the stated reason machine-wide hooks are never installed by `install.sh`).
- `install.sh:652-655` — status warns when clone is not a git repo.
- `install.sh:673-684` — `--update`: bare `git pull --ff-only` under `set -e`, then re-enumerate skills/subagents; falls through to render (`:767-808`, `rm -rf` + `cp -R` + sed) and bin links. No preflight/error shaping.
- `install.sh:726-739` — global uninstall removes crontab entry and `auto_upgrade` key; `:744` hardcoded bin-link uninstall list (must mirror `brain_links`).
- `install.sh:1064-1098` — `~/.hivesmith/bin` symlinks (`brain_links` array, `src_rel:link_name`); `hs-metric` precedent comment ("Not a hook: only runs when a skill the operator started calls it").
- `install.sh:1100-1135` — cron install/removal block + "Auto-upgrade is opt-in" message.
- `install.sh:13` — `HIVESMITH_DIR` = dir of install.sh; a symlinked helper must resolve its clone via `readlink` of itself.
- `tests/install-agent-scopes-test.sh` — sandbox harness: `new_sandbox`, `isolate_global_side_effects` (scratch repo copy + no-op `crontab` stub), `hs_install`. `:81` passes `--no-auto-upgrade`.
- `scripts/telemetry/install-hooks-test.sh` — `check label expected actual` style; template for a script suite.
- `skills/{brainstorm,feature-loop,feature-next,pr-queue,review-pr}/SKILL.md` — chosen entry skills. `feature-next` (`Read Glob Grep Bash`) and `review-pr` (`Read Glob Grep Bash Agent`) lack `AskUserQuestion` in `allowed-tools`. `review-pr` is also invoked by `review-loop` (callee path must skip).
- `.github/workflows/ci.yml` — `--no-auto-update` at `:74,80,92,236`; `--no-auto-upgrade` at `:118-144`; shellcheck list twice (`:25-26`, `:27-55`); `script-suites` loop `:180-206`.
- Docs hits: `README.md:133,148,168,228`; `CONTRIBUTING.md:30`; `AGENTS.md:73,77,78,80`; `SECURITY.md:29` (crontab); `tests/manual/installer-smoke.md:4,34,49`, `plan-lane-smoke.md:12`, `brainstorm-smoke.md:14`; active plans `docs/exec-plans/active/016-*.md:147,156,157,181`, `033-*.md:100`. Historical (CHANGELOG, `.changesets/001`, `039`, completed plans) left alone.

### Constraints / dependencies

- No harness exposes a reliable "interactive?" / "invoked by another skill?" signal to a skill. Claude Code hooks: no documented print-mode field; model prompting before the first user message is undocumented. pi: `ctx.hasUI` exists, but hooks are out of scope now. Detection is therefore instruction-level in the preamble plus env guards in the helper.
- The operator's clone is not necessarily `~/.hivesmith` (this machine: `/Users/lucascaro/checkout/hivesmith`, `main` tracking `origin/main`). Helper must resolve the clone from its own symlink target.
- Running from a worktree install points `HIVESMITH_DIR` at the worktree; a branch with no upstream must stay silent.
- macOS has no `timeout(1)`; the fetch runs detached, so no timeout is needed on the caller path, but it must be `GIT_TERMINAL_PROMPT=0` and single-flight.
- `--update` rewrites `.rendered/` under a running skill — fine because the skill is already loaded; the operator is told to reload.
- The render step rewrites `/skill` references only in `SKILL.md`; helper scripts must use bare names (golden principle 5).
- Every new shell script must be in both CI shellcheck lists and `AGENTS.md` (golden principle 6), strict mode + bash shebang (GP 3).

### Prior lessons

- No prior lessons matched (`upgrade hook`, `install settings.json`, `upgrade` returned only unrelated rank-1 hits).

### Conventions card

From `AGENTS.md`:

- **Lint:** `shellcheck install.sh scripts/brain/append.sh … tests/install-agent-scopes-test.sh` (full list in `AGENTS.md`; mirrors `.github/workflows/ci.yml` shellcheck job).
- **Brain tests:** `scripts/brain/test/run-all.sh`
- **Agent scope resolution:** `tests/install-agent-scopes-test.sh`
- **Install smoke:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run` (then with `--prefix ""`)
- **Render correctness:** `HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update` then `grep -q '/hs-feature-plan' .rendered/hs-/skills/hs-feature-research/SKILL.md` and `! grep -q '/feature-plan\b' .rendered/hs-/skills/hs-feature-research/SKILL.md`
- **Subagent linking:** the `subagent-linking` job script in `.github/workflows/ci.yml`.
- **Script suites:** `for s in scripts/telemetry/install-hooks-test.sh … skills/plan-html/wait-test.sh; do bash "$s" || echo "FAILED $s"; done`

Conventions this feature touches:

- Shell: `#!/usr/bin/env bash` + `set -euo pipefail` (GP 3); new scripts added to CI shellcheck (both lists) and `AGENTS.md` lint line (GP 6); new test suites added to `script-suites` and `AGENTS.md`.
- Tests are plain bash suites with sandboxed `HOME`, printing `RESULT: PASS|FAIL`; never touch the real crontab or checkout.
- Skill source uses bare `/skill` names (GP 5); `~/.hivesmith/bin/*` helpers referenced by absolute path.
- User-visible change → changeset under `.changesets/` via `/changelog-update`; removed flags are breaking.
- Do not edit `docs/product-specs/index.md` (generated).

## Approach

A single helper, `scripts/upgrade/check.sh`, linked as `~/.hivesmith/bin/hs-upgrade-check`, owns all logic. Five entry skills carry an identical, marker-delimited preamble that calls it. `install.sh` loses the cron, gains `--upgrade-check` / `--no-upgrade-check`, migrates legacy installs, and reports state in `--status`.

**Why this beats the obvious alternative (a SessionStart hook / pi extension):** a hook can't reliably make the model prompt before the operator's first message, fires in sessions that never touch hivesmith, and needs per-harness settings surgery (`install.sh:627-630` records why machine-wide hooks were deliberately kept out of the installer). A skill already runs interactively in every harness, and `hs-metric` (`install.sh:1079-1081`) is the precedent for a bin helper that only runs when an operator-started skill calls it.

#### Helper contract — `hs-upgrade-check [status|upgrade|snooze-day|snooze-until-change <sha>|never]`

- **Whole body in `main "$@"; exit`** so bash has parsed the entire file before `upgrade` pulls a new copy of it.
- **Clone resolution:** follow the symlink chain of `$0` (`readlink` loop, no `-f` — BSD); relative targets resolved against the link's own directory; take `../..` of the resolved script. Never assumes `~/.hivesmith`.
- **State:** `$HOME/.hivesmith/upgrade-check/` (same hardcoded root install.sh uses for `bin/`; no new `HIVESMITH_HOME` knob) — `last-fetch` (epoch), `snooze-day` (YYYY-MM-DD declined), `snooze-sha` (upstream sha declined), `fetch.lock/` (single-flight `mkdir` lock; reclaimed when `find "$lock" -maxdepth 0 -mmin +60` matches — portable BSD/GNU).
- **Every git call in `status` guarded** (`if ! x=$(git … 2>/dev/null); then exit 0; fi`) so `set -e` never produces a non-zero exit or stderr on the silent paths.
- **Config:** `${HIVESMITH_DIR_CONFIG:-$HOME/.hivesmith.toml}`, key `upgrade_check = false` = opted out. Absent = on. Read-only in the helper; `install.sh` remains the only writer.
- **`status` (default), always exit 0, prints nothing unless all hold:** `CI` unset; `HIVESMITH_UPGRADE_CHECK` ≠ `0`; config not opted out; clone is a git repo; `@{u}` resolves; `rev-list --count HEAD..@{u}` > 0; today ≠ `snooze-day`; `@{u}` sha ≠ `snooze-sha`. Then prints exactly `BEHIND <n> <upstream-sha> <clone-dir>`.
  - Before computing (after the env/config guards), if `now - last-fetch ≥ ${HIVESMITH_UPGRADE_CHECK_INTERVAL:-21600}` and the lock is acquired: write `last-fetch`, then launch, fully detached, `nohup sh -c 'git -c http.lowSpeedLimit=1000 -c http.lowSpeedTime=60 fetch --quiet; rmdir "$1"' _ "$lock" </dev/null >/dev/null 2>&1 &` with `GIT_TERMINAL_PROMPT=0` and `GIT_SSH_COMMAND="${GIT_SSH_COMMAND:-ssh} -o BatchMode=yes -o ConnectTimeout=15 -o ServerAliveInterval=15 -o ServerAliveCountMax=2"` exported — the wrapper releases the lock; low-speed/keepalive caps stop a stalled fetch outliving the 60-min reclaim. BatchMode stops ssh from prompting for passphrase/host key via `/dev/tty`; `nohup` survives a harness tool call ending (no `setsid` on macOS). Computation uses local refs only — never waits on network. Offline: fetch fails silently in background; status reflects last known refs.
  - Test seam: `HIVESMITH_UPGRADE_CHECK_TODAY` overrides `date +%F`.
- **`upgrade`:** runs `"$clone/install.sh" --update`, streaming its output. Non-zero → prints `hs-upgrade-check: upgrade failed (exit <n>) — see output above` to stderr and exits with that code. Zero → clears `snooze-day`/`snooze-sha`, prints `hivesmith upgraded. Reload or restart this session so the new skills take effect.`
- **`snooze-day`:** writes today. **`snooze-until-change <sha>`:** validates `^[0-9a-f]{7,40}$`, writes it. **`never`:** runs `"$clone/install.sh" --no-upgrade-check`, output captured and shown only on failure.

#### Entry-skill preamble

**Sync mechanism (operator decision):** canonical text lives in `scripts/upgrade/preamble.md`. `scripts/upgrade/sync-preamble.sh` rewrites the block between the markers in each entry skill from that file (idempotent; `--check` exits non-zero and names drifted files without writing). The list of entry skills lives in one place — a header line in `preamble.md` (`<!-- entry-skills: brainstorm feature-loop feature-next pr-queue review-pr -->`) — read by both the sync script and the test. CI runs `sync-preamble.sh --check` (via the helper test suite) and fails with `run scripts/upgrade/sync-preamble.sh`. Nobody hand-edits a block.

The block sits between `<!-- BEGIN hivesmith upgrade-check -->` / `<!-- END hivesmith upgrade-check -->` as a `## Before you start: upgrade check` section immediately after the H1 intro of: `brainstorm`, `feature-loop`, `feature-next`, `pr-queue`, `review-pr`. Content (summary):

1. **Skip entirely** when: you cannot ask the operator and wait for an answer (print/non-interactive mode, no question tool and no live operator); this skill was invoked by another skill or you are a subagent — including a chained handoff within the same session (e.g. `brainstorm` → `feature-new` → `feature-loop`), so the operator is asked at most once per chain; the run is unattended (scheduled, `/loop`, cron); or `~/.hivesmith/bin/hs-upgrade-check` does not exist.
2. Run `~/.hivesmith/bin/hs-upgrade-check`. Empty output → continue silently.
3. On `BEHIND <n> <sha> <dir>`: ask one question (AskUserQuestion where available) — "hivesmith (<dir>) is <n> commits behind upstream. Upgrade now?" with four options: **Upgrade now**, **Ask me later** (tomorrow), **Not until the next upstream change**, **Never ask again** (re-enable: `install.sh --upgrade-check`).
4. Dispatch: `upgrade` / `snooze-day` / `snooze-until-change <sha>` / `never`.
5. After **Upgrade now**: success → relay the reload message and **stop this skill** (its loaded text and the scripts it calls may now disagree; the operator re-invokes after reloading). Failure → show the error and **also stop**, telling the operator to reload once the problem is fixed (the pull may have succeeded before render/link failed, so loaded text may already be stale). Any other choice → continue.

Adds `AskUserQuestion` to `allowed-tools` of `feature-next` and `review-pr` (the other three already have it). No `/skill` references in the preamble (GP 5 render safety).

#### install.sh

- **`--update` re-execs after the pull.** Bash reads a running script incrementally, so continuing after `git pull` rewrites `install.sh` runs mismatched bytes — and this PR rewrites `install.sh` heavily. Save `ORIG_ARGS=("$@")` before parsing; inside the (fully parsed) `update` block: pull, then `if [[ -z "${HIVESMITH_UPDATE_REEXEC:-}" ]]; then HIVESMITH_UPDATE_REEXEC=1 exec bash "$HIVESMITH_DIR/install.sh" "${ORIG_ARGS[@]}"; fi`. The re-exec'd run skips the pull and does render/links/migration with the new code, so migration happens on the upgrade run itself. **Transition caveat:** the one upgrade *into* this change is performed by the *old* `install.sh` (no re-exec), which carries the pre-existing mid-read hazard; that cannot be fixed retroactively. The changeset tells operators to run `install.sh` once after pulling this release; migration then happens on that run.
- Delete `AUTO_UPGRADE_*` state, `auto_upgrade` parse, resolution block, `write_config_auto_upgrade`, cron install block and the "opt-in" message.
- `--auto-upgrade` / `--no-auto-upgrade` / `--no-auto-update` → `err` "`<flag>` was removed: the daily cron is replaced by an upgrade check inside hivesmith skills (on by default). Opt out with --no-upgrade-check." and `exit 1`.
- New `--upgrade-check` (removes key) / `--no-upgrade-check` (writes `upgrade_check = false`), global only (rejected with `--local`, like the old flags), persisted via `upsert_config_key`, skipped on uninstall.
- **Migration** (global scope, `install` and `update` modes): if `has_hivesmith_cron` → remove the entry (dry-run aware) and say so; if the config has an `auto_upgrade` key → remove it. `CRON_GREP`/`has_hivesmith_cron` kept solely for this and for uninstall.
- `--status` (global): replace the auto-upgrade line with `upgrade-check: on` | `upgrade-check: off (upgrade_check = false in <config>; re-enable: install.sh --upgrade-check)` | `upgrade-check: disabled in this shell (HIVESMITH_UPGRADE_CHECK=0 or CI set)`. If a legacy cron is still present: warn and count as a `--doctor` problem.
- Bin links: add `scripts/upgrade/check.sh:hs-upgrade-check`; add `hs-upgrade-check` to the uninstall list (`:744`); global uninstall also removes `$HOME/.hivesmith/upgrade-check/` and keeps the `upgrade_check` key.
- Help text + config-keys paragraph updated.

### Files to change

1. `install.sh` — as above, including stale comments at `:154` (config sample) and `:1100-1102` (cron header).
2. `skills/brainstorm/SKILL.md`, `skills/feature-loop/SKILL.md`, `skills/feature-next/SKILL.md`, `skills/pr-queue/SKILL.md`, `skills/review-pr/SKILL.md` — preamble block; `allowed-tools` += `AskUserQuestion` for `feature-next`, `review-pr`.
3. `tests/install-agent-scopes-test.sh` — `:81` drop `--no-auto-upgrade`; comments `:13-15` and `:40-41` ("auto-upgrade branch") updated (the stub remains: migration still reads crontab).
4. `.github/workflows/ci.yml` — add `scripts/upgrade/sync-preamble.sh` to both shellcheck lists; replace `--no-auto-update`/`--no-auto-upgrade` (`:74,80,92,118-144,236`) with `--no-upgrade-check`; add new scripts to both shellcheck lists; add `scripts/upgrade/check-test.sh` to `script-suites`; add `tests/install-upgrade-check-test.sh` to the `agent-scopes` job.
5. `AGENTS.md` — lint list, smoke/render commands, script-suites list, new install-upgrade-check test line.
6. `README.md` — `:133` (local scope rejects the new flags), `:148` (status), `:168` (Update section rewritten: skill-entry check, snooze options, opt-out/re-enable, migration note), `:228` (uninstall).
7. `CONTRIBUTING.md:30`, `SECURITY.md:29` (crontab now only read/cleaned for migration; `git fetch` runs in background from skills).
8. `tests/manual/installer-smoke.md`, `tests/manual/plan-lane-smoke.md`, `tests/manual/brainstorm-smoke.md` — flag/cron references.
9. `docs/exec-plans/active/016-*.md`, `docs/exec-plans/active/033-*.md` — old flag in their smoke commands.

### New files

- `scripts/upgrade/check.sh` — the helper.
- `scripts/upgrade/preamble.md` — canonical preamble text + entry-skill list (single source).
- `scripts/upgrade/sync-preamble.sh` — writes the canonical block into each listed skill; `--check` for CI.
- `scripts/upgrade/check-test.sh` — helper suite.
- `tests/install-upgrade-check-test.sh` — installer suite (sandbox pattern from `install-agent-scopes-test.sh`, recording `crontab` stub).
- `tests/manual/upgrade-check-smoke.md` — model-behavior checks not automatable (prompt shown before work; callee/subagent/print-mode skip; stop-after-upgrade).
- `.changesets/080-skill-entry-upgrade-check.md` — `type: changed`, breaking note for removed flags.

### Tests

`scripts/upgrade/check-test.sh` (sandbox: bare origin + clone holding a copy of `check.sh` and a stub `install.sh` that records argv and does `git pull --ff-only` on `--update`; helper invoked through a symlink in a fake bin dir; fetch counted via `remote.origin.uploadpack` wrapper that logs and optionally sleeps):

Every "silent" case asserts **exit 0, empty stdout AND empty stderr**.

- `current_clone_is_silent`
- `behind_prints_count_sha_and_dir` — exact `BEHIND 2 <sha> <clone>` line.
- `resolves_clone_through_symlink` — absolute and relative link targets.
- `no_upstream_is_silent`
- `not_a_git_repo_is_silent`
- `offline_is_silent_and_exits_zero` — origin URL points nowhere, stale `last-fetch`.
- `fetch_runs_non_interactive` — the uploadpack wrapper logs `GIT_TERMINAL_PROMPT` and `GIT_SSH_COMMAND`; assert `0` and `BatchMode=yes`.
- `stale_lock_is_reclaimed` — lock dir back-dated >60 min (`touch -t`) → fetch runs; fresh lock → no fetch.
- `upgrade_survives_self_rewrite` — origin commit rewrites `check.sh` (appends lines shifting offsets); `upgrade` completes with the original success message and exit 0.
- `stale_status_fetches_in_background_without_blocking` — uploadpack sleeps 5s; status returns in <2s; fetch log appears later; behind count visible on the next call.
- `fresh_status_skips_fetch` — `last-fetch` = now → no fetch logged.
- `concurrent_calls_fetch_once` — lock single-flight.
- `ci_env_is_silent`, `env_opt_out_is_silent`, `config_opt_out_is_silent`
- `snooze_day_suppresses_until_next_day` — via `HIVESMITH_UPGRADE_CHECK_TODAY`.
- `snooze_until_change_suppresses_until_new_commit`
- `snooze_until_change_rejects_non_sha`
- `never_invokes_install_no_upgrade_check`
- `upgrade_success_clears_snoozes_and_prints_reload`
- `upgrade_failure_propagates_exit_and_message`
- `entry_skills_carry_canonical_preamble` — against the real repo: `sync-preamble.sh --check` passes; exactly the listed skills contain the markers; those have `AskUserQuestion` in `allowed-tools`.
- `sync_rewrites_drifted_block_and_is_idempotent` — scratch copy of two skills with a hand-edited block: `--check` exits non-zero naming the file; sync restores it byte-identical; second sync changes nothing; content outside markers untouched.
- `sync_inserts_block_when_markers_missing` — skill listed but without markers → block inserted after the H1 intro.

`tests/install-upgrade-check-test.sh`:

- `default_install_links_helper_and_status_on`
- `migration_removes_cron_entry_and_auto_upgrade_key` — seeded crontab has a hivesmith line and a foreign line; foreign survives.
- `removed_flags_exit_nonzero_with_pointer` — all three flags.
- `no_upgrade_check_persists_across_reinstall` — second plain install keeps the key; `--upgrade-check` removes it; status text follows.
- `local_scope_rejects_upgrade_check_flags`
- `uninstall_removes_helper_and_state_keeps_optout`
- `update_reexecs_new_install_sh_after_pull` — sandbox clone of a bare origin; origin commit changes `install.sh` (inserts a marker `say` near the top that shifts offsets, plus a seeded legacy cron + `auto_upgrade = true`); `install.sh --update` exits 0, prints the new marker exactly once, and the cron line and key are gone after that single run.

## Verification

```bash
bash scripts/upgrade/check-test.sh
scripts/upgrade/sync-preamble.sh --check
bash tests/install-upgrade-check-test.sh
bash tests/install-agent-scopes-test.sh
shellcheck install.sh scripts/upgrade/sync-preamble.sh scripts/brain/append.sh scripts/brain/index.sh scripts/brain/lib.sh scripts/brain/list.sh scripts/brain/read.sh scripts/brain/redact.sh scripts/brain/search.sh scripts/brain/test/run-all.sh scripts/dev-link-local.sh scripts/harvest/correction-episodes-test.sh scripts/harvest/harvest-plans-test.sh scripts/harvest/plan-citations-test.sh scripts/hooks/pre-push scripts/metrics/backfill-test.sh scripts/metrics/emit-test.sh scripts/metrics/emit.sh scripts/metrics/regressions-test.sh scripts/migrate-to-changesets.sh scripts/regen-generated.sh scripts/release.sh scripts/telemetry/attribution-test.sh scripts/telemetry/install-hooks-test.sh scripts/telemetry/install-hooks.sh scripts/telemetry/install-pi.sh scripts/telemetry/log-agent-stop.sh scripts/telemetry/log-agent.sh scripts/telemetry/prepare-commit-msg skills/brain-garden/garden.sh skills/brain-promote/promote.sh skills/feature-ingest/ingest.sh skills/graphify-init/graphify-nudge.sh skills/graphify-init/graphify-refresh.sh skills/graphify-init/graphify-setup.sh skills/graphify-init/test/run-all.sh skills/namecheck/namecheck.sh skills/plan-html/start.sh skills/plan-html/stop.sh skills/plan-html/wait-test.sh skills/plan-html/wait.sh templates/features/ingest.sh templates/scripts/migrate-to-changesets.sh templates/scripts/regen-generated.sh templates/scripts/release.sh tests/install-agent-scopes-test.sh tests/install-upgrade-check-test.sh scripts/upgrade/check.sh scripts/upgrade/check-test.sh
fail=0; for s in scripts/telemetry/install-hooks-test.sh scripts/telemetry/attribution-test.sh scripts/harvest/plan-citations-test.sh scripts/harvest/harvest-plans-test.sh scripts/harvest/correction-episodes-test.sh scripts/metrics/emit-test.sh scripts/metrics/regressions-test.sh scripts/metrics/backfill-test.sh skills/plan-html/wait-test.sh scripts/upgrade/check-test.sh; do bash "$s" || { echo "FAILED $s"; fail=1; }; done; [ "$fail" = 0 ]
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-upgrade-check --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix "" --no-upgrade-check --dry-run
# Old flags gone from live docs/CI (fails today). Excludes the test that must exercise them and this feature's own plan/spec:
! grep -rnE -- '--(no-)?auto-up(grade|date)' .github README.md CONTRIBUTING.md AGENTS.md tests docs/exec-plans/active \
    | grep -vE '^(tests/install-upgrade-check-test\.sh|docs/exec-plans/active/080-)'
# Cron install code gone (fails today):
! grep -n '17 4 \* \* \*' install.sh
# Render keeps preamble byte-identical under prefix, for all 5 entry skills:
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-upgrade-check && drift=0 && \
  for s in brainstorm feature-loop feature-next pr-queue review-pr; do
    diff <(sed -n '/BEGIN hivesmith upgrade-check/,/END hivesmith upgrade-check/p' ".rendered/hs-/skills/hs-$s/SKILL.md" | sed '1d;$d') scripts/upgrade/preamble.md || { echo "RENDER DRIFT $s"; drift=1; }
  done; [ "$drift" = 0 ]
```

Plus `tests/manual/upgrade-check-smoke.md` walked once by hand in Claude Code, including: make the clone stale (`last-fetch` back-dated, origin ahead), invoke an entry skill, confirm the Bash call returns immediately and `.git/FETCH_HEAD` mtime updates afterwards (proves the detached fetch survives the harness tool call).

## Second opinion

- **Round 1:** revise (confidence 7) — 6 must-fix, all applied: verification grep that could never pass; `--update` re-exec after pull + helper body in `main`; SSH BatchMode for background fetch; portable lock reclaim + test; `nohup` detach + manual FETCH_HEAD smoke; silent-path tests assert exit 0 + empty stderr.
- **Round 2:** approve (confidence 7) — no must-fix. Folded nice-to-haves: explicit lock-release wrapper, fetch stall caps, no new `HIVESMITH_HOME` knob, `exec bash` re-exec, stop the skill on failed upgrade, literal non-zero-exiting verification commands.
- **Not applied (operator's call, recorded):** pi/codex FETCH_HEAD smoke for harnesses that kill the process group; extracting `upsert_config_key` to `scripts/lib/config.sh` so `never` avoids a full install run.

## Decision log

- **2026-09-16** — Spec revised from harness hooks to a skill-entry check. Why: Claude Code hooks cannot reliably prompt before the first user message and fire in non-hivesmith sessions; a skill can prompt, only runs for hivesmith users, and works in every harness.
- **2026-09-16** — Entry skills = minimal set: `brainstorm`, `feature-loop`, `feature-next`, `pr-queue`, `review-pr`. Why: operator choice — daily-driver doors, least drift surface.
- **2026-09-16** — Opt-out and "never ask again" share one key, `upgrade_check = false` in `~/.hivesmith.toml`. Why: install.sh already owns that file and never wipes unknown keys; one source of truth for status.
- **2026-09-16** — Background refresh at most every 6h. Why: operator choice; first-ever invocation may be silent.
- **2026-09-16** — Headless detection = helper env guards (`CI`, `HIVESMITH_UPGRADE_CHECK=0`) + preamble instruction (skip when no way to ask the operator, when invoked by another skill/subagent, or in an unattended run). Why: no harness signal exists.

- **2026-09-16** — Preambles kept in sync by canonical `scripts/upgrade/preamble.md` + `sync-preamble.sh` + CI `--check`. Why: operator choice at plan review over a one-liner that defers text to helper output.

- **2026-09-16** — `git pull` writes new inodes, so a running bash never reads the pulled bytes (verified: inode changes across `git pull`). The `--update` re-exec is kept for its real purpose — the pulled code does render/links/migration in the same run — and the helper's `main "$@"; exit` guards in-place rewrites only. Comments say exactly that; `upgrade_survives_self_rewrite` simulates an in-place write so the guard is tested. Why: the round-1 reviewer's stated hazard did not apply to git, and prose must not claim a guarantee the code does not need.
- **2026-09-16** — CI/docs/manual smoke drop the removed flags instead of swapping in `--no-upgrade-check`. Why: the old flags existed to avoid installing a cron; nothing machine-wide is installed by default now, and `CI` already silences the helper.
- **2026-09-16** — Fixed `crontab -l | grep -v … | crontab -` aborting under `pipefail` when the hivesmith line was the only entry (uninstall path, pre-existing; migration reuses it). Why: the migration would otherwise inherit the bug; `migration_handles_cron_with_only_our_line` covers it.
- **2026-09-16** — `snooze-until-change` resolves a short sha to the full upstream sha before storing it. Why: status compares against the full `@{u}` sha; storing a prefix would never match and the snooze would silently not apply.

## Progress

- **2026-09-16** — Spec created via /brainstorm (local-only), revised to skill-entry mechanism; research complete.
- **2026-09-16** — Plan approved (2 second-opinion rounds, 1 HTML revise round, approved in chat after page timeout).
- **2026-09-16** — Implemented on `feature/080-replace-auto-upgrade-cron-with-skill-entry-check`: helper (24 cases), installer suite (9 cases), preamble sync, docs/CI. Mutation-checked both suites (re-exec, lock, BatchMode, backgrounding, snooze clearing, opt-out write, cron `|| true`, main-wrapper, upstream guard). All AGENTS.md checks pass locally; manual harness smoke (`tests/manual/upgrade-check-smoke.md`) not yet walked.

## Open questions

- **Stop after a successful upgrade** (vs continue on the loaded version) — chosen for correctness; costs one re-invoke.
- **`never` shells out to a full `install.sh --no-upgrade-check`** (relink + re-render, a few seconds) to keep a single config writer. Alternative: extract `upsert_config_key` into a sourced `scripts/lib/config.sh` shared by both — cleaner, but refactors `install.sh`.
- **Model-level skip rules are not mechanically enforceable** (no harness signal). Env guards cover CI/explicit opt-out; the rest is instruction + manual smoke.
- **Worktree installs** point the helper at the worktree; a branch without upstream is silent by design; a deleted worktree leaves a dangling link that `--doctor` already reports.
- `feature-loop` itself is autonomous after entry; the prompt happens before Phase 0, while the operator is present. `review-pr` invoked by `review-loop` must skip (callee rule).
- Local-scope installs still reach the global helper → they see the prompt (spec open question; matches shared clone).

## PR convergence ledger

- **2026-09-16 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: e1d9c9439dc67e928d752cc8f939b0ad1e0792d6b24eee34d610aad0aac11949; threads_open: 0; action: autofix+push; head_sha: 62e527e.
- **2026-09-16 iter 2** — verdict: APPROVE; mergeable: MERGEABLE; findings_hash: empty; threads_open: 0; action: stop; head_sha: 62e527e.

## Gate verdict
