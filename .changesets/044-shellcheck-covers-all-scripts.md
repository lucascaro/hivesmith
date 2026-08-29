---
type: changed
bump: patch
---
- **CI shellcheck list now mirrors `AGENTS.md`.** The explicit `additional_files` list in the shellcheck job and the `AGENTS.md` lint command had drifted (`scripts/hooks/pre-push`, `skills/plan-html/{start,stop}.sh`, two `templates/scripts/*.sh`); both lists are now identical. `scandir: '.'` already discovered every one of these scripts, so this is list hygiene, not new lint coverage. Also cleared the actionlint SC2155/SC2251 warnings in workflow `run:` steps.
