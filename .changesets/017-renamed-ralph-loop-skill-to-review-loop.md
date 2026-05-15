---
type: changed
bump: minor
---
- **Renamed `ralph-loop` skill to `review-loop`.** The PR-convergence loop is now `/hs-review-loop` (was `/hs-ralph-loop`). The old name was internal jargon; the new name says what the skill does. Behavior is unchanged. All sibling skills, templates (`AGENTS.hivesmith.md`, `AGENTS.md`, legacy `FEATURE.md`), root docs (`AGENTS.md`, `README.md`), and scaffolding (`docs/exec-plans/_template.md`, `docs/product-specs/index.md`) updated to match. No back-compat alias — `/hs-ralph-loop` no longer resolves. The external citation in `references/openai-harness-engineering.md` preserves the original "Ralph Wiggum Loop" name.
