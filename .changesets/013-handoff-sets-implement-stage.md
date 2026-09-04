---
type: changed
bump: patch
---
- **`/feature-plan-handoff` advances the stage.** A passing spec-driven handoff now writes `stage: IMPLEMENT` into the spec frontmatter when the spec is still earlier than that (`PLAN`, or unset), instead of assuming `/feature-plan` already did it. It never demotes a spec already at `REVIEW`, `GATE` or `DONE`, and never touches the generated `docs/product-specs/index.md`. Empty-target resolution widened to match specs at `stage: PLAN` as well as `IMPLEMENT`.
