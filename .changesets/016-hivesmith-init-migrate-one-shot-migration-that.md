---
type: added
bump: minor
---
- `hivesmith-init --migrate` — one-shot migration that splits existing `features/<state>/<NNN>-*.md` files into product specs (`docs/product-specs/`) and exec plans (`docs/exec-plans/{active,completed}/`). Decision log and progress preserved verbatim. Legacy `features/` is left untouched as a fallback.
