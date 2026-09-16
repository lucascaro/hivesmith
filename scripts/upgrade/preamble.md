<!-- entry-skills: brainstorm feature-loop feature-next pr-queue review-pr -->
## Before you start: upgrade check

Do this before anything else in this skill, then carry on with the rest of it.

**Skip this section entirely** — go straight to the skill's own work and say nothing about it — when any of these hold:

- You cannot ask the operator a question and wait for the answer: non-interactive or print mode, a CI run, no live operator.
- This skill was invoked by another skill or by a subagent, or reached through a chained handoff in the same session (for example brainstorm handing off to feature-new, then feature-loop). The operator is asked at most once per chain.
- The run is unattended: scheduled, looped, or started by cron.
- `~/.hivesmith/bin/hs-upgrade-check` does not exist.

Otherwise run:

```bash
~/.hivesmith/bin/hs-upgrade-check
```

It returns immediately: it answers from cached state and refreshes that state in the background. If it prints nothing, continue silently.

If it prints `BEHIND <n> <sha> <dir>`, ask the operator one question — with AskUserQuestion where the harness has it — "hivesmith (`<dir>`) is `<n>` commits behind upstream. Upgrade now?", offering exactly these options, then run the matching command:

| Option | Command |
|---|---|
| Upgrade now | `~/.hivesmith/bin/hs-upgrade-check upgrade` |
| Ask me later (tomorrow) | `~/.hivesmith/bin/hs-upgrade-check snooze-day` |
| Not until the next upstream change | `~/.hivesmith/bin/hs-upgrade-check snooze-until-change <sha>` |
| Never ask again (re-enable: `install.sh --upgrade-check`) | `~/.hivesmith/bin/hs-upgrade-check never` |

After **Upgrade now**, stop this skill whatever the result:

- **Success:** relay the reload message it prints. The instructions you loaded are now older than the code on disk, so the operator reloads or restarts the session and invokes this skill again.
- **Failure:** show its output, and tell the operator to fix the problem, reload, and invoke this skill again — the pull may have landed before a later step failed.

After any other option, continue with this skill.
