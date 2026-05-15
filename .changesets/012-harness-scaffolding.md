---
type: added
bump: minor
---
- **Harness scaffolding.** `hivesmith-init` now lays down a `docs/` system-of-record tree (`design-docs/`, `exec-plans/{active,completed}/`, `product-specs/`, `references/`, `generated/`) and top-level stubs (`DESIGN.md`, `RELIABILITY.md`, `SECURITY.md`, `QUALITY_SCORE.md`, `PRODUCT_SENSE.md`, `PLANS.md`, `FRONTEND.md`, `golden-principles.md`). `AGENTS.md` is now a ~70-line table of contents pointing into the new tree, following the pattern documented in OpenAI's "Harness engineering" post.
