---
type: added
bump: minor
---
- **Cold-start guards on stage skills.** `feature-triage`, `feature-research`, `feature-plan`, `feature-implement`, and the new `feature-qa` each refuse to run if the plan's `Stage:` doesn't match the stage they own — they trust the file, not the caller. Any skill can now be invoked from a fresh agent context with just an issue number and figure out whether it should proceed.
