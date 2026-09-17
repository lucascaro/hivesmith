---
type: changed
bump: minor
---
- **The scaffolded changeset gate no longer needs a bypass for docs, CI or test-only PRs.** `hivesmith-init` now copies `scripts/check-changeset.sh`, a self-test and a `pre-push` hook. The `verify-generated` job calls the same script, so the local hook and CI share one list of exempt paths: `docs/`, `features/`, root markdown, `.github/`, `scripts/` and common test layouts. Tune the `EXEMPT` list at the top of the script for your project. The `no-changeset` label still covers other changes with no user-visible effect.
