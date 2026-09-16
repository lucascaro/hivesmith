---
title: Replace the auto-upgrade cron with an upgrade check at hivesmith skill entry
type: enhancement
complexity: M
priority: P2
pr: 83
stage: GATE
---

# Replace the auto-upgrade cron with an upgrade check at hivesmith skill entry

- **Exec plan:** [docs/exec-plans/active/080-replace-auto-upgrade-cron-with-skill-entry-check.md](../exec-plans/active/080-replace-auto-upgrade-cron-with-skill-entry-check.md) (or completed/)

## Problem

Operators running a global hivesmith install drift onto stale skills without knowing it. The only upgrade path is an opt-in daily cron that in practice nobody enables; when it is enabled it doesn't run on a machine asleep at 04:17, and its output goes to /dev/null so failures are invisible. Staleness is discovered only when behavior diverges from upstream.

## Desired behavior

When an operator invokes an entry hivesmith skill in any harness and the installed hivesmith clone is behind upstream, the skill — before starting its work — tells them it's behind (and by how much) and offers four choices: upgrade now, ask later (snooze until next day), don't ask until upstream changes again, or never ask again. "Never ask again" persists across installs and upgrades and is reversible. After a successful upgrade the operator is told to reload/restart so new skills take effect. A failed upgrade (dirty/diverged clone) is reported, never swallowed. The check never adds noticeable latency: it uses the last known status and refreshes it in the background. On by default, opt-out at install time. The cron and the `auto_upgrade` config key are gone.

## Success criteria

- With the clone behind upstream, invoking an entry skill interactively surfaces the "behind" message and the four choices before the skill does any work.
- With the clone current, no upgrade message appears.
- Pipeline-internal stages, skills invoked by another skill or a subagent, autonomous loops, and non-interactive runs never show the prompt.
- Offline or with no upstream configured, the skill runs normally with no upgrade message and no error.
- The check does not block on network: with a stale/missing status the skill proceeds immediately and the status refreshes in the background.
- "Ask later" suppresses the prompt until the next calendar day; "not until next change" suppresses until upstream has a commit newer than the one declined.
- After "never ask again", no subsequent invocation prompts, including across new upstream commits and re-runs of `install.sh`.
- `install.sh --status` reports whether the check is enabled, disabled, or opted out; a documented way re-enables it.
- Accepting runs the full hivesmith upgrade (including re-rendering prefixed skills) then tells the operator to reload/restart; failure shows its error.
- An install with the opt-out flag never prompts.
- On an existing install with the cron and `auto_upgrade = true`, the next install run removes the crontab entry and the key; `--auto-upgrade` / `--no-auto-upgrade` / `--no-auto-update` are no longer accepted (or error with a pointer to the new mechanism).
- Uninstall leaves no upgrade-check artifacts except the operator's persisted opt-out choice.

## Non-goals

- Refreshing project scaffolding (AGENTS.md block, templates) — separate brainstorm.
- Auditing what other hooks are missing — separate brainstorm.
- Harness hooks/extensions (SessionStart, pi `session_start`) for this check.
- Unattended auto-upgrade without asking; nothing mutates silently.
- Hot-reloading skills mid-session or mid-workflow — operator reloads.

## Notes

- "Entry skill" = an operator-invoked front door, not a pipeline stage or a skill invoked by another skill. The plan fixes the exact list.
- Reverses the brainstorm's original hook approach: Claude Code hooks can't reliably prompt before the first message, and hooks fire in sessions that never use hivesmith.
- Open: startup latency budget; local-scope installs share the global clone and will see the prompt — confirm intended.
- Follow-ups: (a) project-scaffolding self-refresh brainstorm; (b) missing-hooks audit brainstorm.
