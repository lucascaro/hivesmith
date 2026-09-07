---
type: changed
bump: minor
---
- **The feature skills that skipped the hive brain now read it.** `/feature-implement` — which writes lessons via `brain-append` but never read them back — now does a file-scoped `BRAIN_FILES=<the plan's Files-to-change> brain-read` before writing any code, mirroring `/review-pr`. `/feature-triage` folds a `brain-search --rank --limit 5` into its complexity-estimate scan, and `/feature-new` searches at draft time so prior lessons are on screen at Gate 1 and are carried forward to its triage phase. Every lookup is best-effort (missing helper or no hits → skipped silently, never blocks) and every one opens with a **skip-if-already-in-context** guard, so a `/feature-loop` run that loaded the brain during research does not re-fetch it at implement. Also normalizes the hardcoded `/hs-brain-promote` in `feature-implement` to the bare `/brain-promote` form, which is what `install.sh`'s prefix renderer expects.
