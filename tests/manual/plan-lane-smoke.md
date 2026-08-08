# Manual smoke: the plan lane

Covers `/feature-plan` (dual mode), `/feature-plan-review`, `/feature-plan-handoff`.
Run after changing any of the three `SKILL.md` files or `skills/feature-plan/plan-template.md`.

## 1. Install + prefix render (automatable)

```bash
export HOME_BAK="$HOME"; HOME=$(mktemp -d); mkdir -p "$HOME/.claude"
./install.sh --prefix hs- --no-auto-update

R=.rendered/hs-/skills
grep -q '^name: hs-feature-plan-review'  "$R/hs-feature-plan-review/SKILL.md"
grep -q '^name: hs-feature-plan-handoff' "$R/hs-feature-plan-handoff/SKILL.md"

# feature-plan's rewrite rule must NOT bleed into the longer names
grep -q '/hs-feature-plan-review' "$R/hs-feature-plan/SKILL.md"
! grep -qE '/hs-feature-plan-(review|handoff)-' "$R/hs-feature-plan/SKILL.md"
! grep -qE '(^|[^-])/feature-plan\b' "$R/hs-feature-plan/SKILL.md"

HOME="$HOME_BAK"
```

Then, from the source tree — golden principle #5, no rendered prefix in source:

```bash
! grep -rn '/hs-[a-z]' skills/feature-plan skills/feature-plan-review skills/feature-plan-handoff
```

## 2. Free-form end-to-end

`/feature-plan "make the brain reader pluggable"`

Expect:
- It reads code **before** asking anything — questions are about real tradeoffs, not things a grep answers.
- Questions arrive **batched**, not one at a time. At most 3 rounds.
- It stops asking once the file list and test list are settled.
- Writes `~/.hivesmith/plans/<yyyy-mm-dd>-make-the-brain-reader-pluggable.md` with `status: DRAFT`, every section of `skills/feature-plan/plan-template.md` present, and every answer recorded under `## Decisions` with its rejected alternative.
- Report points at `/feature-plan-review`, not `/feature-implement`.

## 3. Review catches planted defects

Hand-edit the plan from step 2 to plant three defects:
1. A path under `### Files to change` that does not exist.
2. A `PluggableReaderFactory` interface with exactly one implementation.
3. Delete one test from `### Tests` that `## Approach` still implies.

`/feature-plan-review <slug>`

Expect all three flagged, each with evidence (a real path/line for the grounding finding), the plan **edited in place** to fix them, a `## Review log` entry, and `status: REVIEWED`. No production files touched — confirm with `git status`.

## 4. Handoff gate

Add a line under `## Open questions`, then `/feature-plan-handoff <slug>`.

Expect a refusal that names the open question **and** any other failing check in the same output, pointing at `/feature-plan-review`. No pickup block printed, `status` unchanged.

Remove the open question, re-run. Expect `status: HANDED-OFF` and a pickup block with real values substituted — no `<slug>` placeholders left in the printed text.

## 5. Cold start (the actual point)

In a **different worktree**, open a **fresh** agent session — ideally a different harness — and paste the pickup block's prose verbatim. Expect the agent to execute without asking anything already settled in `## Decisions`.

## 6. Spec-mode regression

On a repo with a spec at `stage: PLAN`:

- `/feature-plan <N>` behaves as before — Approach lands in the exec plan, `gh` labels update, spec `stage:` advances to `IMPLEMENT` as the **last** write.
- `/feature-plan <N>` on a spec at the wrong stage still refuses and names the right skill.
- `/feature-plan-handoff <N>` prints the spec-driven pickup block and does **not** touch `stage:`.

## 7. Render mode

- A short plan (≲120 lines, no diagrams) renders as inline text.
- `--html` on the same plan boots `/plan-html`; `<plan>.approved.json` gates approval; `stop.sh` runs on exit.
- `HIVESMITH_PLAN_HTML=0` forces text even on a large plan.
