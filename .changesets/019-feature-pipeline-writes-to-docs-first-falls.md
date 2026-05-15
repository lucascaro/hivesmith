---
type: changed
bump: minor
---
- **Feature pipeline writes to `docs/` first, falls back to `features/` for one release.** Specs land in `docs/product-specs/`, exec plans in `docs/exec-plans/{active,completed}/`. The historical record (the *what* and *why*) and the engineering log (the *how* with append-only Decision log + Progress) are now separate artifacts. `feature-{ingest,new,triage,research,plan,implement,loop,next}` updated.
