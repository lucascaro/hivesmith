---
type: changed
bump: minor
---
- **"Boil the lake" philosophy added to `AGENTS.md` and seven skills.** `review-pr`, `autofix`, `gc-sweep`, `doc-garden`, `feature-plan`, `feature-implement`, and `review-loop` now carry an explicit preamble: when the complete fix/implementation/sweep is bounded (a *lake*), do all of it in this change instead of recommending a partial shortcut. Genuine *oceans* (multi-quarter, cross-cutting) must be surfaced explicitly with a staged plan rather than half-done. The same paragraph lands in the project-wide `AGENTS.md` block (and `templates/AGENTS.hivesmith.md`) so downstream `hivesmith-init` projects inherit it.
