---
type: fixed
bump: patch
---
- **`regen-generated.py --check` is now genuinely read-only** — it used to regenerate every aggregate on disk, compare, then restore the originals in a `finally`. Net-neutral on content, but it churned mtimes and `unlink()`'d targets that did not exist, so an interrupted run left a modified tree. It now compares in memory and writes nothing, making it safe for CI and pre-commit hooks.
