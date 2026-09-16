---
pr: 83
type: changed
bump: minor
---
- **hivesmith now tells you when it is out of date — and the auto-upgrade cron is gone.** `/brainstorm`, `/feature-loop`, `/feature-next`, `/pr-queue` and `/review-pr` start by checking whether your hivesmith clone is behind upstream and, if it is, ask once: upgrade now, ask me later (tomorrow), not until the next upstream change, or never ask again. The check answers from the last fetch and refreshes it with a non-interactive background `git fetch` at most every 6 hours, so it never slows a skill down; it stays silent offline, without an upstream, in CI, in subagents and unattended runs. After an upgrade the skill stops and asks you to reload the session. On by default; opt out with `install.sh --no-upgrade-check`, re-enable with `--upgrade-check`, and `install.sh --status` shows which is in effect.
- **Breaking: `--auto-upgrade`, `--no-auto-upgrade` and `--no-auto-update` were removed** and now exit with an error pointing at `--no-upgrade-check`. The next global `install.sh` run removes an existing hivesmith crontab entry and the `auto_upgrade` key from `~/.hivesmith.toml`; `--doctor` fails while a legacy cron is still present. If you upgrade into this release with an older `install.sh --update` (or the old cron), run `install.sh` once more so the new installer performs that cleanup.
- **`install.sh --update` now re-runs itself from the freshly pulled `install.sh`**, so rendering, linking and migrations always use the code that was just pulled rather than the previous version.
- **Fixed: a global uninstall aborted when the hivesmith cron line was the only crontab entry.** The crontab was emptied, then `set -o pipefail` killed the script before the rest of the cleanup ran.
