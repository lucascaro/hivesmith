#!/usr/bin/env bash
# shellcheck disable=SC2016
# Static contract checks for portable hivesmith skills. No Pi install or model is required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

failures=0
checks=0

has() {
    local file="$1" text="$2"
    checks=$((checks + 1))
    if ! grep -Fq -- "$text" "$file"; then
        printf 'FAIL: %s is missing from %s\n' "$text" "$file" >&2
        failures=$((failures + 1))
    fi
}

lacks() {
    local file="$1" text="$2"
    checks=$((checks + 1))
    if grep -Fq -- "$text" "$file"; then
        printf 'FAIL: unexpected %s in %s\n' "$text" "$file" >&2
        failures=$((failures + 1))
    fi
}

# Pi native skills and the boundary around optional user-owned agent plugins.
has README.md '/skill:<installed-name>'
has README.md 'Hivesmith does not install an agent/subagent plugin.'
has README.md 'Claude'
has scripts/upgrade/preamble.md 'if none is available, ask in chat with numbered options and wait for the answer.'

# A parent workflow must not depend on Claude's model-callable Skill tool.
lacks skills/review-loop/SKILL.md 'skill: "hivesmith:review-pr"'
lacks skills/review-loop/SKILL.md 'skill: "hivesmith:autofix"'
lacks skills/pr-queue/SKILL.md 'skill: "hivesmith:review-pr"'
lacks skills/pr-queue/SKILL.md 'skill: "hivesmith:review-loop"'
has skills/review-loop/SKILL.md 'the complete hivesmith `review-pr` skill instructions'
has skills/review-loop/SKILL.md 'the complete hivesmith `autofix` skill instructions'
has skills/review-loop/SKILL.md '"review_completed": false'
has skills/review-loop/SKILL.md 'Do not run loop detection, append a convergence-ledger row, or emit a `review_iteration` metric'
has skills/feature-loop/SKILL.md 'In the no-agent fallback or on malformed reviewer output, do not emit a `second_opinion` event as if a valid independent verdict existed:'
has skills/pr-queue/SKILL.md 'the complete hivesmith `review-loop` skill instructions'
has skills/brainstorm/SKILL.md 'read and follow the installed `feature-new/SKILL.md` instructions'
has skills/feature-implement/SKILL.md 'follow the installed `changelog-update/SKILL.md` workflow'
has skills/feature-implement/SKILL.md 'rather than assuming `/changelog-update` executes in Pi.'
has .changesets/README.md 'Required: `type`, `bump`. Optional: `issue`'
has templates/.changesets/README.md 'Required: `type`, `bump`. Optional: `issue`'
has skills/feature-next/SKILL.md 'Render every recommendation using the current host'

# Agent-dependent tasks use host capabilities with a truthful inline fallback.
for skill in review-loop pr-queue review-pr merge-gate feedback-loop feature-loop \
    feature-plan feature-plan-review feature-research doc-garden gc-sweep code-garden; do
    has "skills/$skill/SKILL.md" 'agent/subagent'
    has "skills/$skill/SKILL.md" 'inline'
done

# Claude-only hook setup is explicitly identified rather than advertised as Pi support.
has skills/graphify-init/SKILL.md 'it does not install a Pi extension or wire Pi hooks'
has skills/graphify-init/SKILL.md 'do not run the setup expecting Pi automation'

# The common entry-skill preamble is generated into its consumers, not hand-edited there.
bash scripts/upgrade/sync-preamble.sh --check >/dev/null

if [[ "$failures" -ne 0 ]]; then
    printf 'FAILED: %d/%d portability checks\n' "$failures" "$checks" >&2
    exit 1
fi
printf 'PASS: %d skill portability checks\n' "$checks"
