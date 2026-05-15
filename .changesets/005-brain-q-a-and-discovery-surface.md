---
type: added
bump: minor
---
- **Brain Q&A and discovery surface.** New CLI helpers `~/.hivesmith/bin/brain-list` (filter entries by scope/ecosystem/tag/project) and `~/.hivesmith/bin/brain-search` (case-insensitive AND-search across slug + tags + body, with `--rank`, `--limit`, `--paths-only`). New skill `/brain-ask` answers natural-language questions against the brain with citations. `/brain-promote` now presents a picker when invoked with no slug. Existing `brain-{read,append,index}` helpers fixed to resolve through symlinks so the documented `~/.hivesmith/bin/` invocation actually works (previously broken, masked by direct-path use in tests).
