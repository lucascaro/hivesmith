---
type: changed
bump: minor
---
- **Plan-producing skills now use a runtime-neutral "draft + approve" rubric.** `feature-plan` (step 6–7) and `feature-loop` Phase 4 (Gate 4) no longer write the Approach section directly to the exec plan and then prompt for approval via `AskUserQuestion`. Instead, both first **draft the plan for review** — no file writes, no `gh` mutations, no Stage changes — then gate on explicit approval, then persist on approval. The draft + approval mechanism is described in two branches in the skill markdown: (1) if the runtime exposes a native plan mode (e.g. Claude Code's `EnterPlanMode` / `ExitPlanMode`), use it; (2) otherwise (e.g. Codex CLI), draft inline under a `### Draft plan for review` heading and gate on a yes/no/revise prompt. Same rubric retrofitted into `feature-loop` Phase 1P (P2) so all three plan-producing surfaces read consistently. Full-auto carve-out in Phase 4 is preserved (reviewer subagent against the drafted plan; same templates and confidence thresholds as before).

  **Migration for existing hivesmith codebases.** No data migration is required — exec-plan and product-spec file formats are unchanged. To pick up the new behavior:
  1. `cd` into your hivesmith checkout and run `./install.sh --update` (or `git pull` if you're on auto-upgrade). Skills install as symlinks, so the update is in-place across all detected agent dirs (Claude / Codex / Factory / Gemini / Copilot).
  2. In-flight features at Stage = PLAN keep working as-is. Next time you run `/feature-plan <N>` or hit Gate 4 in `/feature-loop <N>`, you'll get the new draft-first flow automatically.
  3. No flag, no opt-in. The skills detect runtime capability and pick the right branch.
