---
type: added
bump: minor
---
- **Lifecycle stages `REVIEW` and `QA`** added to the canonical stage enum: `TRIAGE → RESEARCH → PLAN → IMPLEMENT → REVIEW → QA → DONE`. `REVIEW` covers PR-open + review-loop convergence; `QA` covers post-merge validation. Stage column in `docs/product-specs/index.md` and `docs/exec-plans/_template.md` updated; legacy `templates/features/templates/FEATURE.md` updated for parity.
