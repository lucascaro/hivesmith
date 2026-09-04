# Wrap graphify's PreToolUse nudge

- **Spec:** [docs/product-specs/067-wrap-graphify-pretooluse-nudge.md](../../product-specs/067-wrap-graphify-pretooluse-nudge.md)
- **Issue:** #67
- **Status:** active
- **PR:** #68
- **Branch:** feature/67-graphify-nudge-wrapper

## Summary

Add `graphify-nudge.sh`, a pure-bash PreToolUse wrapper that forwards the tool payload to `graphify hook-guard`, passes strict denials through untouched, suppresses the soft nudge once it has fired for this `(session, kind)` or once the orientation stamp is fresh, and otherwise replaces the `MANDATORY: … You MUST …` text with neutral advisory wording. `graphify-setup.sh` installs it the same way it installs `graphify-refresh.sh`.

## Research

### Relevant code

- `skills/graphify-init/graphify-setup.sh:237-260` — the install convention a new hook script must follow. `REFRESH_REL="$OUT/graphify-refresh.sh"`; `copy_refresh_script()` copies from the skill dir into the **gitignored** out dir and `chmod +x`; `HOOK_COMMAND` (`:243`) references it as `sh -c '[ -x "$CLAUDE_PROJECT_DIR/graphify-out/graphify-refresh.sh" ] || exit 0; exec "…"'`. The gitignored target is a security invariant, not a preference: `.claude/settings.json` is committed, so a hook pointing at a *tracked* script is a branch-controlled payload — a PR editing the script body would execute on any maintainer who checks the branch out, with the reviewed command string unchanged. Recorded in `docs/exec-plans/completed/058-wire-graphify-into-hivesmith-with-shared-cache.md:171`. The `[ -x … ] || exit 0` prefix is equally required: the out dir can be wiped while the committed settings.json still names the hook.
- `skills/graphify-init/graphify-setup.sh:~300 claude_nudges()` — shells into graphify's private `install._install_claude_hook(Path("."), project=True)` to write the PreToolUse entries. Gated on `NUDGES=1` for install; uninstall always attempts removal. On install failure it dies with "refusing to report a successful setup with the nudges missing". There is **no positive verification that the expected command actually landed** — success is inferred from python's exit status.
- `skills/graphify-init/graphify-setup.sh:369-404 guard_nudge_commands()` — a `python3 -` heredoc that rewrites any PreToolUse command starting with the literal `graphify ` into `command -v graphify >/dev/null 2>&1 && <cmd> || exit 0`, idempotent via a `"command -v graphify" not in cmd` test. Current committed result, `.claude/settings.json:20,29`:
  - `command -v graphify >/dev/null 2>&1 && graphify hook-guard search || exit 0` (matcher `Bash|Grep`)
  - `command -v graphify >/dev/null 2>&1 && graphify hook-guard read || exit 0` (matcher `Read|Glob`)
  This is the seam to extend. Note its predicate only matches commands starting with `graphify `, so a wrapper command will not be re-guarded — the wrapper must carry its own fail-open.
- `skills/graphify-init/graphify-setup.sh:423` — `settings_merge()` identifies PostToolUse entries by the substring `graphify-refresh.sh` and owns only PostToolUse. PreToolUse removal belongs to graphify's uninstaller.
- graphify `install.py:1814` — `_strip_graphify_hook` filters PreToolUse by `matcher in ("Glob|Grep","Bash","Bash|Grep","Read|Glob") and "graphify" in str(h)`. **The wrapper keeps both the matchers and the substring `graphify` (in the path `graphify-out/graphify-nudge.sh`), so graphify's own uninstall still removes the entries.** No new uninstall ownership is needed.
- graphify `cli.py:814-942 _run_hook_guard` — the contract being wrapped. Always exits 0; the exit code carries no signal. Output is a single compact JSON line. Payload shapes: `_SEARCH_NUDGE` / `_READ_NUDGE` / `_READ_NUDGE_STALE` carry `hookSpecificOutput.additionalContext`; `_READ_DENY` (`cli.py:57-73`) carries `hookSpecificOutput.permissionDecision` — **nested inside `hookSpecificOutput`, not top-level**. Silent on: unparseable stdin, non-search Bash commands, missing graph, out-of-project or non-source reads, any internal exception.
- graphify `cli.py:687-707` — `_touch_query_stamp` writes `graphify-out/cache/last_query_stamp`; `_query_stamp_fresh` reads its **mtime** against `GRAPHIFY_HOOK_STRICT_TTL` (default 1800s). Touched only by `query`, `path`, `explain`. `cli.py:710-737 _mark_session_denied` claims `graphify-out/cache/hook_sessions/<sanitized-sid>.denied` with `O_CREAT|O_EXCL`, GCing entries older than 24h — the precedent a per-session throttle should mirror.
- `skills/graphify-init/test/run-all.sh` — bash 3.2, `set -uo pipefail`, helpers `assert_file_contains` / `assert_file_lacks` (literal substrings), `run_test <name> <fn>` (rc 77 = skip), `need_graphify` (skips unless `GRAPHIFY_REQUIRED=1`), `setup_repo`. Three existing cases key off the literal `hook-guard`: `test_nudges_opt_out` (`:369`), `test_nudges_on_by_default` (`:389`), and `:424` which asserts `"command": "graphify hook-guard` is **absent** (an unguarded bare nudge is a failure).
- `AGENTS.md:65`, `.github/workflows/ci.yml:25` and its continuation list at `:26-53` — the shellcheck file list is hand-maintained in three places. `golden-principles.md:69-75` (principle 6) makes keeping them equal to the full `find` set a formal invariant.
- `golden-principles.md:39-45` (principle 3) — `#!/usr/bin/env bash` on line 1, `set -euo pipefail` within five lines. `graphify-refresh.sh:24` is the sanctioned exception: `set -u` only, with an explicit comment justifying the never-fail invariant. A PreToolUse wrapper has the same invariant and follows that precedent.
- `install.sh:783` — skills ship via `cp -R "$src_dir/."`, so a new file under `skills/graphify-init/` is packaged automatically. No manifest to update.

### Constraints / dependencies

- **python3 is not currently a post-install runtime dependency.** Every `python3 -` call in `graphify-setup.sh` runs at setup time on the machine of whoever runs `/graphify-init`; the installed hook path (`graphify-refresh.sh`) contains no python. A wrapper requiring python3 at hook time would make it one for every clone of a wired repo. The wrapper is therefore pure bash — and needs no JSON parser, because the deny/nudge distinction is the presence of the `permissionDecision` **key**, which is a substring test.
- Never match on graphify's nudge *text*. The gating logic changes roughly every release and the strings have been rewritten at least three times; the payload *shapes* have been stable across five releases and the last change (#1840, July 2026) was additive. `permissionDecision` is Claude Code's contract key, not graphify's.
- The wrapper must forward stdin unchanged — graphify reads the tool payload from it and decides in-project/staleness/indexing on that basis.
- `GRAPHIFY_OUT` relocates the out dir, but `HOOK_COMMAND` already hardcodes the literal `graphify-out` in the command string. Follow that precedent rather than fixing it here.

### Prior lessons

No prior lessons matched — `brain-search graphify hook nudge settings claude --rank --limit 8` returned zero rows, and broader queries found nothing. The brain has no graphify entries yet.

## Approach

A ~90-line bash script sits between Claude Code and `graphify hook-guard` and makes one decision per invocation. It delegates every question about *whether this call is in scope* to graphify (in-project, source-extension, staleness, indexing, strict gating) and owns only *how often*, *in what tone*, and — the reviewer's catch — *whether graphify needs to be run at all*.

Rejected alternative: reimplement graphify's gating in the wrapper and skip `hook-guard` entirely. That forks logic that changes every release — the gating is exactly the part upstream keeps fixing.

Rejected alternative: parse the JSON with python3 or `jq`. Neither buys anything over a substring test on the contract key. python3 is not currently a runtime dependency of any installed hook, and `jq` is not guaranteed present at all.

**Decision flow, in order.** Steps 4-5 come *before* the fork, which is what keeps the wrapper cheap:

1. `[ -x wrapper ] || exit 0` lives in the hook command string (as with `graphify-refresh.sh`), so a wiped out dir cannot produce exit 127 on every tool call.
2. Read stdin **once** into a variable (stdin cannot be consumed twice) and replay it to the subprocess with `printf '%s'`. `$(cat)` strips the trailing newline; that is harmless because `json.loads` does not care, but the wrapper does not claim to forward stdin byte-for-byte.
3. Extract and sanitize the session key from the captured payload — see **Session key** below.
4. **Decide whether graphify can still say anything actionable.** Strict mode is off unless `GRAPHIFY_HOOK_STRICT` is truthy or the hook command carries `--strict` (`cli.py:675-684`; the installed command carries neither). With strict off, the only payloads `hook-guard` can produce are soft nudges — so once this `(session, kind)` has been claimed *or* the orientation stamp is fresh, every possible outcome is "emit nothing". Exit 0 immediately, without forking. This is the difference between removing the token tax and removing the token tax *and* the ~100ms python startup that would otherwise be paid on every `Bash`/`Grep`/`Read`/`Glob` for the rest of the session. When strict **is** enabled, skip this shortcut and always fork: a deny is still possible and is graphify's to decide.
5. `command -v graphify` fails → exit 0.
6. Forward the payload to `graphify hook-guard <kind>`; capture stdout. Non-zero exit or empty output → exit 0.
7. Output contains `"permissionDecision"` → print it verbatim and exit 0. Blocking stays graphify's to own, byte for byte.
8. Re-check the orientation stamp and claim the `(session, kind)` slot (the pre-fork check in step 4 is skipped under strict mode, and graphify's own work may have taken time). Claim fails → exit 0.
9. Emit our own fixed JSON envelope. Two variants, chosen by a filesystem check rather than by reading graphify's text: `graphify-out/needs_update` exists → the stale-flavoured string (which mentions `graphify update`); otherwise the standard advisory. Neither contains "MANDATORY", "You MUST", or any instruction to propagate the rule into subagent prompts.

**Session key.** `session_id` is scraped from the captured payload with `sed`, anchored to the **first** `"session_id"` occurrence and stopping at the next unescaped quote, then sanitized exactly as upstream does before using a session id as a filename (`cli.py:713-714`): `tr -c 'A-Za-z0-9_-' '_'`, truncate to 64 characters, empty result → the literal `unknown`. The sanitization is load-bearing, not cosmetic: the payload of a `Bash` call being nudged can itself contain the literal `"session_id":` inside the command string, JSON key order is not contractual, and an unsanitized value containing `/` or `..` would write the claim file outside `graphify-out/cache/`. A wrong-but-sanitized key degrades to one extra nudge, which is the acceptable failure direction.

**Claim.** `( set -C; : > "$f" ) 2>/dev/null || exit 0`. Bash's noclobber opens with `O_EXCL`, so the claim is atomic, mirroring `_mark_session_denied` (`cli.py:710-737`). The subshell matters twice: `:` is a special builtin whose redirection failure would exit the shell in POSIX mode, and it keeps noclobber from leaking into later redirections. Entries older than 24h are swept on each successful claim, as upstream does.

Wording (fixed, no knob):

> graphify: this project has a knowledge graph at graphify-out/. For structural questions — where something is defined, what calls it, how two things connect — `graphify query "<question>"` returns a scoped subgraph and is usually cheaper than grepping. Reading or grepping files directly is fine.

Stale variant appends: the graph may be out of date for recent edits; `graphify update` refreshes it.

`set -u` only, with the same explicit justification comment `graphify-refresh.sh:24` carries: under `set -e` any unexpected non-zero — a missing `stat`, an unwritable cache dir — would abort before the fail-open `exit 0`, which is the one outcome a PreToolUse hook must never produce.

### Files to change

1. `skills/graphify-init/graphify-setup.sh`
   - Add `NUDGE_REL="$OUT/graphify-nudge.sh"` and a `copy_nudge_script()` mirroring `copy_refresh_script()` (copy from `$SELF_DIR`, `chmod +x`). It runs on install regardless of `NUDGES`, and `--uninstall` removes the copied file alongside the existing cleanup — the script is inert without a settings entry pointing at it, but leaving a stray executable in the out dir after uninstall is untidy.
   - Extend `guard_nudge_commands()` to match on the substring **`hook-guard`** (extracting the `search` / `read` kind from it), *not* `cmd.startswith("graphify ")`. Every already-wired repo — including this one, `.claude/settings.json:20,29` — carries the guarded form `command -v graphify >/dev/null 2>&1 && graphify hook-guard search || exit 0`, which the current predicate does not match. Matching on `hook-guard` migrates those repos on the next run; keeping the old predicate would make the new verification (below) hard-fail setup for every existing user. Rewrite to `sh -c '[ -x "$CLAUDE_PROJECT_DIR/graphify-out/graphify-nudge.sh" ] || exit 0; exec "$CLAUDE_PROJECT_DIR/graphify-out/graphify-nudge.sh" <kind>'`, and stay idempotent by skipping commands that already name `graphify-nudge.sh`.
   - Add the positive verification the function currently lacks: after rewriting, assert both expected commands are present in `.claude/settings.json` and that no bare `hook-guard` command survives, reusing the existing "refusing to report a successful setup" die.
   - Update `agents_block()` (`:~470`) — the text it writes into the consuming project's AGENTS.md — to describe the wrapper's behavior rather than graphify's raw nudges.
2. `AGENTS.md` — **two** separate edits: the generated graphify block at `:17-19`, which `agents_block()` produces and which goes stale the moment item 1 lands, and the shellcheck list at `:65`.
3. `.github/workflows/ci.yml:25` and the continuation list at `:26-53` — add the new script in both places (golden principle 6).
4. `skills/graphify-init/test/run-all.sh` — update the three cases that key on the literal `hook-guard` string, add the new cases below, and register them in the flat `run_test` list.
5. `skills/graphify-init/SKILL.md` — document the wrapper: what it suppresses, the two env knobs it honours, that it skips the fork entirely once satisfied, and that `--no-nudges` still removes the hooks.
6. `.claude/settings.json` — this repo's own committed hook commands, regenerated by running the installer. Dogfooding, and the migration path in item 1 is exactly what has to work here.

### New files

- `skills/graphify-init/graphify-nudge.sh` — the wrapper. Copied to `graphify-out/graphify-nudge.sh` at install; never referenced from its tracked path.
- `.changesets/067-graphify-nudge-wrapper.md` — user-visible changeset.

### Tests

All in `skills/graphify-init/test/run-all.sh`, following the existing `test_*` + `run_test` convention, `need_graphify` where the real binary is required. The wrapper is driven directly with a synthetic payload on stdin so most cases need no graphify at all — a `graphify` shim on `PATH` emitting a canned payload covers the branches deterministically.

- `test_nudge_wrapper_installed` — after install, both PreToolUse commands name `graphify-out/graphify-nudge.sh`, carry the `[ -x … ] || exit 0` prefix, and the target is git-ignored; asserts the bare `"command": "graphify hook-guard` form is absent (extends the existing `:424` assertion rather than replacing it).
- `test_nudge_passes_through_deny` — shim emits a `permissionDecision` payload; wrapper stdout is byte-identical to the shim's, and no throttle file is created.
- `test_nudge_throttles_per_session` — same session id twice: first call emits, second emits nothing; a different session id emits again.
- `test_nudge_respects_query_stamp` — touch `graphify-out/cache/last_query_stamp`; wrapper emits nothing. With the stamp backdated past the TTL it emits again.
- `test_nudge_text_is_advisory` — emitted `additionalContext` contains none of `MANDATORY`, `You MUST`, `subagent`; asserts the advisory string is present.
- `test_nudge_stale_variant` — with `graphify-out/needs_update` present, the emitted text mentions `graphify update`.
- `test_nudge_fails_open` — five sub-cases, each asserting exit 0 and empty stdout: `graphify` absent from `PATH`, shim emitting malformed JSON, shim emitting nothing, an unwritable `graphify-out/cache` dir, and a payload that is not JSON at all.
- `test_nudge_sanitizes_session_id` — a payload whose `session_id` is `../../escape` (and one where the literal `"session_id":` appears inside `tool_input.command`) creates its claim file **inside** `graphify-out/cache/hook_nudges/` and nowhere else; asserts no file is written outside the cache dir.
- `test_nudge_skips_fork_when_satisfied` — with the slot already claimed and strict off, a `graphify` shim that writes a marker file when invoked leaves no marker: the wrapper must not fork at all. With `GRAPHIFY_HOOK_STRICT=1` the marker appears, proving the shortcut is strict-aware.
- `test_setup_migrates_guarded_command` — seed `.claude/settings.json` with the **already-guarded** `command -v graphify … && graphify hook-guard search || exit 0` form, run setup, assert it is rewritten to the wrapper and that setup exits 0. This is the regression the reviewer caught: the old `startswith("graphify ")` predicate would leave it unmigrated and the new verification would then die.
- `test_nudges_opt_out` / `test_nudges_on_by_default` — updated to key on `graphify-nudge.sh` rather than `hook-guard`.

## Verification

Every command below fails on a wrong implementation — no `grep -c … # expect 2` comments, no `&& echo` that cannot fail.

```bash
set -e

# 1. The wrapper's own suite (needs graphify for the install-path cases)
GRAPHIFY_REQUIRED=1 skills/graphify-init/test/run-all.sh

# 2. Lint — new script must be in all three lists (golden principle 6)
shellcheck skills/graphify-init/graphify-nudge.sh
grep -q 'graphify-init/graphify-nudge.sh' AGENTS.md
[ "$(grep -c 'graphify-nudge.sh' .github/workflows/ci.yml)" = 2 ]

# 3. No MANDATORY-shaped text is EMITTED. (A file-level grep would be wrong:
#    the wrapper's header comment quotes graphify's wording to explain what it
#    fixes. The invariant is about output, which test_nudge_text_is_advisory
#    asserts directly; this is the end-to-end confirmation.)
printf '%s' "$first" | grep -qvE 'MANDATORY|You MUST'

# 4. Hook target is untracked and guarded (the security invariant)
grep -q 'graphify-out/graphify-nudge.sh' .claude/settings.json
grep -q '\[ -x "$CLAUDE_PROJECT_DIR/graphify-out/graphify-nudge.sh" \] || exit 0' .claude/settings.json
! grep -q '&& graphify hook-guard' .claude/settings.json      # the pre-migration form is gone
git check-ignore -q graphify-out/graphify-nudge.sh || { echo "hook target is TRACKED"; exit 1; }

# 5. End-to-end: two identical Grep calls in one session emit exactly one nudge
P='{"session_id":"vtest-'$RANDOM'","tool_input":{"pattern":"foo"}}'
first=$(printf '%s' "$P" | graphify-out/graphify-nudge.sh search)
second=$(printf '%s' "$P" | graphify-out/graphify-nudge.sh search)
[ -n "$first" ] || { echo "first call emitted nothing"; exit 1; }
[ -z "$second" ] || { echo "throttle failed: second call emitted"; exit 1; }
printf '%s' "$first" | grep -q 'graphify query'

# 6. Rest of the AGENTS.md suite (unchanged areas must stay green)
scripts/brain/test/run-all.sh
tests/install-agent-scopes-test.sh
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run

# 7. Changelog gate. CHANGELOG.md is generated from .changesets/ on push to main,
#    so run the regenerator locally first or this asserts against a stale aggregate.
scripts/regen-generated.sh
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .
```

## Decision log

- **2026-09-04** — Reuse `graphify-refresh.sh`'s `mtime_of` probe order (GNU `-c` first, BSD `-f` second, numeric backstop) rather than writing a fresh one. Why: the sibling script had already hit and documented this exact trap; probing BSD-first looks symmetric and is wrong, because GNU's `-f` succeeds with unrelated output instead of failing.
- **2026-09-04** — Check the throttle and orientation stamp *before* forking `graphify hook-guard`, whenever strict mode is off. Why: with strict off (the installed default — no `--strict` in the command, `cli.py:2457-2459`) every payload graphify can return is a soft nudge, so once the slot is claimed or the stamp is fresh the answer is "emit nothing" regardless. Forking anyway costs ~100ms of python startup on every Bash/Grep/Read/Glob for the rest of the session — the same tax the feature exists to remove, just paid in latency instead of tokens. Under strict mode the shortcut is skipped, because a deny is still possible.
- **2026-09-04** — Sanitize the extracted `session_id` before it becomes a path component (`tr -c 'A-Za-z0-9_-' '_'`, cap 64, empty → `unknown`), mirroring `cli.py:713-714`. Why: it is a filename. A `Bash` payload can contain the literal `"session_id":` inside the command being nudged, key order is not contractual, and `/` or `..` in the value would write outside `graphify-out/cache/`.
- **2026-09-04** — `guard_nudge_commands()` matches on the substring `hook-guard`, not `startswith("graphify ")`. Why: every already-wired repo carries the guarded form (`.claude/settings.json:20,29`), which the old predicate does not match — with the new must-be-present verification, that would turn a re-run in an existing repo into a hard setup failure instead of a migration.
- **2026-09-04** — Substring tests plus `sed`, not `jq`, despite golden principle 2 naming "a single `jq` extraction in shell" as the fix shape for stringly-typed probing. Why: `jq` is not a guaranteed dependency on a hook path that runs on every tool call, and the only structural question asked is the presence of one contract key. Recorded here so `/gc-sweep` does not re-litigate it.

- **2026-09-04** — Wrap `graphify hook-guard` rather than reimplement its gating. Why: the gating logic changes roughly every release (four commits in two months); the payload shapes have been stable across five. Wrapping forks the stable half.
- **2026-09-04** — Pure bash, no JSON parser. Why: the deny/nudge distinction is the presence of the `permissionDecision` key, which is a substring test; python3 is currently not a runtime dependency of any installed hook and adding one would burden every clone of a wired repo.
- **2026-09-04** — Branch on key presence, never on graphify's nudge text. Why: the strings have been rewritten at least three times while the shapes held; text matching would silently degrade to rewriting a deny.
- **2026-09-04** — Choose the stale variant from `graphify-out/needs_update` on disk rather than by detecting graphify's STALE wording. Why: same reason, and the file is the same signal graphify itself reads.
- **2026-09-04** — Reuse `GRAPHIFY_HOOK_STRICT_TTL` (default 1800s) for stamp freshness instead of inventing a knob. Why: it is the same question graphify already answers with that variable; a second knob would drift.
- **2026-09-04** — Throttle key is `(session_id, kind)`, claimed with `O_EXCL` via bash noclobber under `graphify-out/cache/hook_nudges/`, swept at 24h. Why: mirrors `_mark_session_denied` exactly, so the two throttles behave alike and share a GC story.
- **2026-09-04** — Missing `session_id` degrades to the key `unknown` rather than disabling the throttle. Why: the failure mode of a disabled throttle is the exact spam this feature exists to remove; at worst an unidentified caller is nudged once per 24h.
- **2026-09-04** — `set -u` only, matching `graphify-refresh.sh`'s documented exception to golden principle 3. Why: under `set -e` an unexpected non-zero (missing `stat`, unwritable cache) aborts before the fail-open `exit 0`, which is the one outcome a PreToolUse hook must never produce.
- **2026-09-04** — No new uninstall ownership. Why: graphify's `_strip_graphify_hook` filters by matcher plus the substring `graphify`, both of which the wrapper command retains.

## Second opinion

Reviewer subagent (`general-purpose`), run before the plan was presented:

- **verdict:** revise — **confidence:** 8/10
- **rationale:** The three riskiest upstream claims check out against source (`hook-guard` always exits 0; the deny nests `permissionDecision` inside `hookSpecificOutput`; `_strip_graphify_hook` still matches the rewritten command; bash noclobber is genuinely `O_EXCL`). What was unsound was the hand-waved parts: an unsanitized `session_id` used as a filename, a `guard_nudge_commands()` predicate that would hard-fail every already-wired repo instead of migrating it, a ~100ms fork retained on every tool call after the single nudge, four verification commands that could not fail, and a stale generated AGENTS.md block left out of the blast radius.
- **disposition:** all five must-fix items applied above, plus all five nice-to-haves (subshell around the noclobber claim, stdin read-once/replay made explicit, uninstall + `--no-nudges` behavior for the copied script specified, golden-principle-2 deviation recorded, and the changelog gate given its regenerator step).

## Progress

- **2026-09-04** — CI (Linux) caught a platform bug the macOS run could not: `stat -f` means `--file-system` on GNU coreutils, so `stat -f %m || stat -c %Y` succeeds with garbage instead of falling through, and the orientation-stamp check silently never fired. `graphify-refresh.sh:47` had already solved this — GNU-first probe order plus a numeric backstop — and the wrapper now reuses that shape with a pointer to it. Added `test_nudge_survives_gnu_stat`, which shims a GNU-only `stat` so the regression fails on either platform rather than only in CI. Suite: 29 passed, 0 failed.
- **2026-09-04** — Implemented. `test_setup_migrates_guarded_command` caught a real bug on first run: `verify_nudge_commands` grepped for `graphify-nudge.sh" <kind>` when the command is a JSON string and the quote is escaped on disk (`graphify-nudge.sh\\" search`), so the new post-install check rejected its own correct output and failed 9 install-path cases. Fixed with `grep -qF` and the escaped form. Suite: 28 passed, 0 failed (was 19 before this feature). This repo's own `.claude/settings.json` was migrated directly rather than by a full installer run — this worktree's `graphify-out/cache` is a real directory, so the installer correctly refuses without `--migrate`, and migrating would move cache entries shared with the operator's other worktrees as a side effect of an unrelated change. The migration path itself is covered by the new test.
- **2026-09-04** — Corrected a verification assertion from the approved plan: `! grep -qE 'MANDATORY|You MUST' skills/graphify-init/graphify-nudge.sh` fails on a correct implementation, because the wrapper's header comment quotes graphify's wording to explain what it fixes. The invariant is about emitted output, not file contents.
- **2026-09-04** — Issue #67 opened; spec + exec plan scaffolded; branch `feature/67-graphify-nudge-wrapper` created from `origin/main`. Clarifying round A answered: throttle once per session per kind; upstream comments plus a PR offer agreed as a separate deliverable. Round B skipped — research surfaced no genuine ambiguity.

## Open questions

None.

## PR convergence ledger

## Gate verdict
