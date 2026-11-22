---
issue: 99
type: added
bump: minor
---
- **Decision records: per-repo decisions that agents check new work against (phase 1 of 2, advisory).**
  - **The gap:** Agents had nothing durable to judge a plan, issue or idea against. Every judgment call fell back to the operator, and a decision made in one session was forgotten in the next.
  - **What is new:** `docs/decisions/NNNN-<slug>.md` holds records in a `proposed` → `accepted` → `superseded` lifecycle, managed by a new `hs-decision` helper (installed to `~/.hivesmith/bin/`). The helper has five commands: `propose`, `list`, `accept`, `supersede` and `lint`.
  - **Who reads records:** `/feature-triage`, `/feature-plan-review`, `/brainstorm`, `/feature-new` and `/feature-loop` read the accepted records. They report a contradiction as `conflicts with docs/decisions/NNNN-<slug>.md: <why>`. In `/feature-loop`'s plan second opinion, a contradiction is a must-fix.
  - **Who proposes records:** `/feature-loop`, `/feature-plan`, `/merge-gate` and `/brainstorm` propose records automatically for direction-setting decisions. Each run writes an explicit `proposed records:` line, so the step is visible even when nothing qualifies.
  - **Acceptance:** only the operator accepts or supersedes a record.
  - **Safety:** a proposal cannot forge its own acceptance. Arguments containing newlines are rejected, the helper always writes `status: proposed`, and only the first frontmatter block is ever parsed.
  - **Scope of phase 1:** records carry no authority yet. Phase 2 lets accepted records stand in for operator approval and adds the correction loop.
  - **Setup:** `/hivesmith-init` scaffolds `docs/decisions/`. In existing projects, the first proposal creates it.
