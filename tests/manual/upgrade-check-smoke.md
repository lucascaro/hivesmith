# Upgrade-check smoke test

The automated suites (`scripts/upgrade/check-test.sh`, `tests/install-upgrade-check-test.sh`) cover the helper and the installer. What they cannot cover is the **model's** behavior in a real harness: whether an entry skill actually asks before working, skips when it should, and stops after an upgrade. Walk this once in Claude Code when changing `scripts/upgrade/preamble.md`, `scripts/upgrade/check.sh`, or the entry-skill list.

## Setup — a clone that is behind

Use a throwaway global install so your real one is untouched:

```bash
SB=$(mktemp -d)
git clone -q https://github.com/lucascaro/hivesmith.git "$SB/hivesmith"
git -C "$SB/hivesmith" reset -q --hard HEAD~3          # 3 commits behind origin/main
export HOME="$SB/home"; mkdir -p "$HOME/.claude"
"$SB/hivesmith/install.sh" --prefix hs-
~/.hivesmith/bin/hs-upgrade-check                        # expect: BEHIND 3 <sha> <dir> (after a fetch)
```

If the first call prints nothing, the status was stale and a background fetch just started; run it again a second later. Start `claude` with this `HOME`.

## Checks

1. **Prompt before work.** Run `/hs-feature-next`. Before the pipeline table, the skill asks "hivesmith (`…`) is 3 commits behind upstream. Upgrade now?" with exactly four options.
2. **Ask me later.** Choose it. The skill continues normally. Re-run `/hs-feature-next`: no prompt. `cat ~/.hivesmith/upgrade-check/snooze-day` shows today.
3. **Not until next change.** `rm ~/.hivesmith/upgrade-check/snooze-day`, re-run, choose it: no prompt on the next run; `snooze-sha` holds the upstream sha.
4. **Upgrade now stops the skill.** Clear both snooze files, re-run, choose **Upgrade now**: `install.sh --update` output appears, then the reload message, and the skill does **not** continue. `git -C "$SB/hivesmith" rev-list --count HEAD..@{u}` is `0`.
5. **Failure is shown, and also stops.** Reset 3 behind again, make the clone dirty on a file upstream changes (e.g. `echo x >> "$SB/hivesmith/install.sh"`), choose **Upgrade now**: git's error and `upgrade failed (exit …)` are shown, the skill stops.
6. **Never ask again.** `git -C "$SB/hivesmith" checkout -- .`, choose **Never ask again**: `~/.hivesmith.toml` has `upgrade_check = false`; `install.sh --status` says `upgrade-check: off`; no prompt on later runs, even after `install.sh` is re-run.
7. **Callee skips.** `install.sh --upgrade-check`, stay behind, run `/hs-review-loop <pr>` (which invokes `/hs-review-pr`): no upgrade prompt from `review-pr`.
8. **Chained handoff asks once.** Clear both snooze files. Run `/hs-brainstorm` and answer the upgrade question with **Ask me later**, then immediately `rm ~/.hivesmith/upgrade-check/snooze-day` in another terminal. Let brainstorm run to its handoff into `/hs-feature-new` and `/hs-feature-loop`: neither asks again, even though the snooze is gone — the chain was already asked.
9. **Print mode skips.** `claude -p "/hs-feature-next"`: output has the pipeline table and no upgrade question.
10. **Background fetch survives the tool call.** `rm ~/.hivesmith/upgrade-check/last-fetch`, note `stat -f %m "$SB/hivesmith/.git/FETCH_HEAD" 2>/dev/null || stat -c %Y "$SB/hivesmith/.git/FETCH_HEAD"`, run `/hs-feature-next`. The Bash call for the check returns immediately; a few seconds later `FETCH_HEAD`'s mtime has advanced. Repeat in pi and codex if you use them — a harness that kills the tool's process group would leave `FETCH_HEAD` unchanged, which silently disables the "behind" signal there.
