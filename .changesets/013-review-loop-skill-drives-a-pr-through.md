---
type: added
bump: minor
---
- `review-loop` skill — drives a PR through review → autofix → re-review until findings clear or escalation criteria hit (max iterations, loop-detection, RISKY-fix authorization, repeated CI failure). Independent of the feature pipeline; works on any PR.
