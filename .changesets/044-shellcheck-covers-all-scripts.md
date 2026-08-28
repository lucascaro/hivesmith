---
type: fixed
bump: patch
---
- **CI shellcheck now covers every script.** `scripts/hooks/pre-push` (extension-less, invisible to `scandir`) and `skills/plan-html/{start,stop}.sh` were never linted in CI; they are now listed explicitly, and the `AGENTS.md` lint command mirrors the list again.
