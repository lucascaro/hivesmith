# Check the hive brain in feature-implement and the other feature skills that skip it

- **Spec:** [docs/product-specs/074-check-hive-brain-in-feature-skills.md](../../product-specs/074-check-hive-brain-in-feature-skills.md)
- **Issue:** #74
- **Status:** completed
- **PR:** [#75](https://github.com/lucascaro/hivesmith/pull/75)
- **Branch:** `feature/74-check-hive-brain-in-feature-skills`
- **Phase:** —

## Summary

The hive brain's read side is applied unevenly: `/feature-plan`, `/feature-research` and `/review-pr`
consult it, `/feature-loop` searches it during research, but `/feature-implement` — the skill that
*writes* lessons — never reads them, and `/feature-triage` and `/feature-new` skip it entirely. Close
those read-side gaps so a lesson captured by one run reaches the standalone skill most likely to hit
the same gotcha again.

## Research

### Current read/append surface

| Skill | Reads brain | Appends |
|---|---|---|
| `feature-loop` | yes — `brain-search --rank --limit 8`, then `brain-read` on ≤3 hits, inside Explore workers (`skills/feature-loop/SKILL.md:142-146`) | yes |
| `feature-research` | yes — bare `brain-read` (`skills/feature-research/SKILL.md` step 5) | no |
| `feature-plan` | yes — bare `brain-read` (`skills/feature-plan/SKILL.md:54`) | no |
| `review-pr` | yes — `BRAIN_FILES=... brain-read` (`skills/review-pr/SKILL.md:97`) | yes |
| `review-loop` | no | yes (`skills/review-loop/SKILL.md:157`) |
| **`feature-implement`** | **no** | yes (`skills/feature-implement/SKILL.md:54`) |
| **`feature-triage`** | **no** | no |
| **`feature-new`** | **no** | no |

The three bold rows are the gap. `feature-implement` is the sharpest: it is the only skill that
writes lessons without ever reading them.

### Helper surface

- `scripts/brain/read.sh` — `[--cwd P] [--budget N] [--files "a,b,c"]`; also honours `BRAIN_FILES`
  and `BRAIN_BUDGET_TOKENS` (default 8000 tokens ≈ 32K chars). Emits HOT tier + project-filtered
  ALL tier wrapped in `<project-memory untrusted="true">`. `--files` filters by `applies_to` globs;
  entries with no `applies_to` always pass.
- `scripts/brain/search.sh` — `<terms> [--rank] [--limit N] [--paths-only]`, AND semantics across
  slug/tags/body. Prints one line per hit (`slug \t scope \t path \t first-body-line`), never bodies.

### Blast radius

Three copies of the same "which skills read/append" sentence, all stale after this change:

- `AGENTS.md:51` — this repo's own hivesmith block.
- `templates/AGENTS.hivesmith.md:26` — shipped into user projects by `/hivesmith-init`.
- `README.md:17`.

Checked and clean: `templates/brain/{README,SCHEMA}.md` (storage/schema only),
`skills/hivesmith-init/SKILL.md` (no roster), `agents/*.md`, `tests/manual/*.md`.
`claude-plugin/skills` is a symlink to `../skills` — nothing to sync.

### Constraints

- **Prefix rendering.** `install.sh:786-789` rewrites `^name: <skill>` and bare `/<skill>` →
  `/<prefix><skill>`. The `[^[:alnum:]_./-]` guard means `~/.hivesmith/bin/brain-search` passes
  through untouched (and no skill dir is named `brain-search`/`brain-read`). Slash-commands must be
  written **bare** (`/brain-promote`, not `/hs-brain-promote`) or they render wrong under
  `--prefix ""`. CI pins this at `.github/workflows/ci.yml:93-95`.
- **`HIVESMITH_SKILL=` values hardcode the `hs-` prefix** at every existing call site
  (`feature-plan:54`, `feature-research:38`, `review-pr:97`, `feature-loop:295`). Match it.
- **No `allowed-tools` change needed.** `feature-triage` and `feature-new` already list `Bash`;
  `feature-implement` has no `allowed-tools` key (unrestricted).
- **No test asserts SKILL.md brain wording.** `scripts/brain/test/run-all.sh` covers the scripts
  only; `regen-generated.py --check` cares about the changeset and spec frontmatter, not skills.

### Prior lessons

No prior lessons matched (`brain-search` returned zero hits for this feature's terms).

## Approach

Add a hive-brain lookup to the three skills that skip it, each at the step where the information
would actually change what the skill does, and each using the mechanism that matches the input it
has. A single uniform `brain-read` in all three was the obvious alternative and is rejected:
`feature-implement` already knows the exact file list from the plan, so an unfiltered dump would
spend budget on entries that cannot apply, while `feature-triage` and `feature-new` have no file
list at all and only feature terms to go on.

Every lookup is best-effort by construction — a missing helper or an empty result is skipped
silently and never fails the skill — and carries the same untrusted-data wording the existing call
sites use.

**No repeated lookups.** Each new lookup opens with an explicit skip condition: if brain output for
this feature is already in context from an earlier step in the same session, do not fetch it again.
Re-reading it changes nothing and spends budget. Concretely:

- `feature-implement` skips its read when `/feature-loop`'s research phase or a `/feature-plan` run
  in the same session already loaded the brain for this feature.
- `feature-new` passes its hits forward to the triage phase it invokes; `feature-triage` skips its
  own search when `feature-new` just ran, and only searches when entered cold.
- The escape hatch is narrow and stated: re-fetch only when *this* step's scope differs from what
  was already loaded — a different file list, or terms the earlier search did not cover.

1. **`feature-implement`** — new step between "Read `AGENTS.md`" (3) and "Create a feature branch"
   (4), so the lookup lands before any code is written. Mechanism: file-scoped
   `BRAIN_FILES="<plan's Files-to-change list>" HIVESMITH_SKILL=hs-feature-implement
   ~/.hivesmith/bin/brain-read`, mirroring `review-pr:97`.

   Deriving `BRAIN_FILES` is spelled out in the skill text, because raw markdown bullets are not a
   path list: take each `### Files to change` bullet, strip the leading `- `, take the text inside
   the first pair of backticks (that is the path; everything after the em-dash is prose), drop any
   entry that is not a path, and join with commas — no spaces, no quotes around individual paths.
   If the plan lists no parseable paths, run `brain-read` with no `--files` (the unfiltered,
   budget-capped form) rather than skipping the lookup. If the list exceeds 40 paths, pass the
   first 40 — `applies_to` matching is a glob OR, so a truncated list only narrows recall, and the
   default 8000-token budget caps the output either way.
2. **`feature-triage`** — fold into the existing step 4 ("Quick codebase scan"), which already
   exists to inform the complexity estimate. Mechanism: `brain-search <feature terms> --rank
   --limit 5`; read at most 2 bodies with rank ≥ 2. Deliberately smaller than feature-loop's 8/3 —
   triage is explicitly a shallow stage.
3. **`feature-new`** — the lookup must run **before Gate 1**, not at the step 6 duplicate check:
   Gate 1 (`skills/feature-new/SKILL.md:25`) is where the operator decides, and step 6 (`:51`) runs
   after it. So the lookup goes into step 2 (drafting, `:23`), and its hits are shown alongside the
   draft title/body at Gate 1. Mechanism: `brain-search <title terms> --rank --limit 5`, headlines
   only (slug + first body line), no body reads. It never blocks issue creation.
4. **Docs** — update the reader roster in `AGENTS.md:51`, `templates/AGENTS.hivesmith.md:26` and
   `README.md:17` to name the new readers.
5. **Changeset** — one `.changesets/<NNN>-*.md` entry (user-visible: skill behavior changes).

Existing readers are left alone. Normalizing `feature-plan`/`feature-research`'s bare `brain-read`
to a file-scoped or search form is a behavior change to a working call site and is out of scope per
the spec's Non-goals.

### Files to change

- `skills/feature-implement/SKILL.md` — insert the file-scoped brain-read step before branch
  creation; renumber the following steps and their cross-references (step 9's "skip steps 9-11"
  note, and the Rules section if it cites numbers). Also normalize the hardcoded
  `/hs-brain-promote` at `:54` to the bare `/brain-promote` form — it currently survives the
  renderer verbatim and is wrong under `--prefix ""`. In scope because it is in the block being
  edited and because Verification step 3 forbids exactly that pattern.
- `skills/feature-triage/SKILL.md` — extend step 4 with the `brain-search` lookup; fix the step
  numbering skip (`8` → `10`, no `9`) in the same section.
- `skills/feature-new/SKILL.md` — add the `brain-search` lookup to step 2 (drafting, `:23`) and
  show its hits alongside the draft at Gate 1 (`:25`). Not step 6 — that runs *after* the gate.
- `AGENTS.md` — update the Hive brain paragraph's reader roster.
- `templates/AGENTS.hivesmith.md` — same sentence, same update.
- `README.md` — same sentence, same update.

### New files

- `.changesets/<NNN>-check-hive-brain-in-feature-skills.md` — changeset for the release notes.

### Tests

Markdown-only change; no code paths added, so no new automated test. Coverage comes from the
existing CI gates plus one explicit render assertion:

- `.github/workflows/ci.yml` render-correctness job — already fails if a bare `/<skill>` survives
  unprefixed. Manually assert the new text renders correctly under both prefixes (see Verification).
- `scripts/regen-generated.py --check` — enforces the changeset + spec frontmatter.
- Source-level greps asserting the anti-injection and silent-skip wording is actually present in
  each edited skill (success criteria 3 and 4 are entirely about wording, so without these the
  change could "pass" with the wording omitted). See Verification steps 4 and 5.
- No addition to `scripts/brain/test/run-all.sh`: it tests the brain scripts, which are untouched.

## Verification

```bash
set -e
REPO="$(pwd)"

# 1. Lint (unchanged file set — must still pass)
shellcheck install.sh scripts/brain/*.sh scripts/metrics/emit.sh

# 2. Render correctness under a prefix. install.sh:14 sets RENDER_ROOT="$HIVESMITH_DIR/.rendered",
#    i.e. inside the repo (gitignored) — NOT under $HOME. Same path ci.yml:93-95 greps.
FAKE="$(mktemp -d)"; mkdir -p "$FAKE/.claude"
HOME="$FAKE" ./install.sh --prefix hs- --no-auto-update
R="$REPO/.rendered/hs-/skills"
test -f "$R/hs-feature-implement/SKILL.md"   # fail loudly if the path is wrong
test -f "$R/hs-feature-triage/SKILL.md"
test -f "$R/hs-feature-new/SKILL.md"
grep -q 'bin/brain-read'   "$R/hs-feature-implement/SKILL.md"
grep -q 'bin/brain-search' "$R/hs-feature-triage/SKILL.md"
grep -q 'bin/brain-search' "$R/hs-feature-new/SKILL.md"
# meaningful only because the source is normalized to the bare `/brain-promote` form (see
# Files to change): the renderer must turn it into `/hs-brain-promote` under `--prefix hs-`.
grep -q '/hs-brain-promote' "$R/hs-feature-implement/SKILL.md"

# 3. No pre-prefixed slash-command in the SOURCE of the three edited skills — that is the bug the
#    renderer cannot fix (it would survive verbatim under `--prefix ""`). A dry-run install asserts
#    nothing, so this is a source grep instead.
for f in skills/feature-implement/SKILL.md skills/feature-triage/SKILL.md skills/feature-new/SKILL.md; do
  if grep -nE '(^|[^[:alnum:]_./-])/hs-[a-z]' "$f"; then echo "PRE-PREFIXED in $f"; exit 1; fi
done

# 4. Success criterion 3 — each new lookup carries the anti-injection wording. Assert the exact
#    call-site phrasing used at skills/review-pr/SKILL.md:97, not the bare word "untrusted"
#    (which already appears in feature-implement and feature-triage today).
for f in skills/feature-implement/SKILL.md skills/feature-triage/SKILL.md skills/feature-new/SKILL.md; do
  grep -q 'untrusted external data' "$f" || { echo "no anti-injection wording in $f"; exit 1; }
done
grep -q 'project-memory untrusted="true"' skills/feature-implement/SKILL.md

# 4b. No-repeated-lookup guard present in all three.
for f in skills/feature-implement/SKILL.md skills/feature-triage/SKILL.md skills/feature-new/SKILL.md; do
  grep -qiE 'already in your context|already in context|already loaded|Do not re-run' "$f" \
    || { echo "no repeat-lookup guard in $f"; exit 1; }
done

# 5. Success criterion 4 — each new lookup is explicitly best-effort.
for f in skills/feature-implement/SKILL.md skills/feature-triage/SKILL.md skills/feature-new/SKILL.md; do
  grep -qiE 'skip silently|silently skip|continue without it' "$f" \
    || { echo "no silent-skip wording in $f"; exit 1; }
done

# 6. Success criterion 5 — existing readers and the brain scripts were not touched. Stricter than
#    the criterion (which permits consistency-only wording edits); if such an edit is made,
#    narrow this list rather than deleting the check. `git fetch` first — a stale origin/main
#    makes this assert nothing.
git fetch origin main --quiet
git diff --quiet origin/main -- skills/feature-plan/SKILL.md skills/feature-research/SKILL.md \
  skills/review-pr/SKILL.md scripts/brain/
# feature-loop is deliberately NOT in that list: review round 1 found its `brain-read <path>`
# invocation is rejected by read.sh (exit 64) and its search terms are unquoted — the same two
# defects this change introduced by copying from it. Fixed there too rather than shipping a known
# -broken pattern. Assert the fix instead of asserting no-change:
grep -q 'brain-search "<feature terms>"' skills/feature-loop/SKILL.md
! grep -q 'brain-read <path>' skills/feature-loop/SKILL.md

# 7. The three docs no longer claim the old roster (per-file, so one stale copy still fails).
for f in AGENTS.md README.md templates/AGENTS.hivesmith.md; do
  if grep -q 'Read at the start of `feature-research` / `feature-plan` / `review-pr`' "$f"; then
    echo "stale roster in $f"; exit 1
  fi
  # the *reader* roster must now name the three new readers, not just the appenders
  grep -qE 'feature-implement.*feature-triage|feature-triage.*feature-implement' "$f" \
    || { echo "reader roster not updated in $f"; exit 1; }
done

# 7b. No dangling step cross-reference after feature-implement's renumbering.
if grep -nE 'steps 9[-–]11' skills/feature-implement/SKILL.md; then
  echo "stale step cross-reference — renumber it"; exit 1
fi

# 8. Brain suite still green (scripts untouched, but they are the contract).
scripts/brain/test/run-all.sh

# 9. Generated artifacts + changeset present for THIS change.
#    `regen-generated.py --check` EXITS 1 here by design: the new spec row and changeset line are
#    real, expected drift that CI's `regenerate-generated` job rebuilds on main. Under `set -e` a
#    bare call aborts the block, so assert what actually matters instead — that the PR does not
#    hand-edit either generated file (CI's `block-generated-edits` job enforces the same thing).
python3 scripts/regen-generated.py --check || echo "expected drift (new spec row + changeset)"
git diff --quiet main...HEAD -- docs/product-specs/index.md CHANGELOG.md
ls .changesets/*check-hive-brain*.md
```

## Second opinion

Two reviewer rounds, both `revise` at confidence 8. Reviewer round 1 found the Verification block
materially broken (wrong `.rendered/` path — `install.sh:14` puts it in the repo, not `$HOME`; a
vacuous `--prefix "" --dry-run` step; no assertion at all for success criteria 3 and 4) and one
design hole: `feature-new`'s lookup was placed at step 6, which runs *after* the Gate 1 where the
plan promised to surface its hits. All 5 must-fix items applied.

Round 2 confirmed those but caught the fixes half-landing: `### Files to change` still named
`feature-new` step 6 while the Approach said step 2, Verification step 3's grep would fail on the
*pre-existing* `/hs-brain-promote` at `feature-implement:54`, and three of the new assertions were
vacuous (`grep -q 'untrusted'` already passes today). All 4 applied — including normalizing
`feature-implement:54` to the bare `/brain-promote` form, which turns two of those asserts into
real ones.

Not applied: rewriting `.changesets/006-*` and its `CHANGELOG.md [Unreleased]` text. Those are the
historical record of what that PR shipped; the release notes reading as a timeline is correct.

| Round | Verdict | Confidence | must_fix | applied |
|---|---|---|---|---|
| 1 | revise | 8 | 5 | 5 |
| 2 | revise | 8 | 4 | 4 |

## Decision log

- **2026-09-06** — "Learnings ledger" resolved to the hive brain, confirmed against `/feature-loop`'s Phase 3 usage (`brain-search --rank --limit 8`, then `brain-read` on ≤3 top hits). Why: it is the only ledger-like store in this repo and the one feature-loop already consults.
- **2026-09-06** — Scope limited to `feature-implement`, `feature-triage`, `feature-new`; existing readers get consistency-only wording at most. Why: operator chose the smallest diff that closes the actual gap.
- **2026-09-06** — Gate PASS on re-run. Both validators independently judged the criterion-5 reword honest bookkeeping rather than retroactive justification, citing that it is narrowly scoped to a verified defect, requires a Decision-log record plus a Verification assertion, and that both gate rounds flagged the mismatch instead of passing it silently.
- **2026-09-06** — Gate FAIL round 1 recorded; fixes pushed to the same PR (the point of gating pre-merge). Re-running the gate once — no second retry.
- **2026-09-06** — Gate round 1 FAIL (doc accuracy) / NEEDS_FOLLOWUP (acceptance): the plan's own Verification block was broken in two places. Step 4b grepped `already in context` against prose that reads "already in *your* context", so it failed on 2 of 3 files; step 9's bare `regen-generated --check` exits 1 on expected drift and, under `set -e`, aborted the block before steps 5-9 ran. Both fixed, and the Progress line claiming "all verification steps pass" corrected — it was not true as literally written.
- **2026-09-06** — Success criterion 5 reworded. The `feature-loop` edit is a functional command fix (broken invocation + quoting), not the "consistency-only" wording change the criterion literally permitted. Both gate validators flagged the mismatch rather than passing it. Amending the criterion to describe what shipped is the right resolution — its intent was "don't break existing readers", which a disclosed defect fix serves — but the spec should say so instead of being quietly exceeded.
- **2026-09-06** — Review round 2 MINOR: `brain-search` is AND across every term, so passing a full title returns zero hits. The placeholders now say "2-4 distinctive terms". Left alone: four sibling skills still hardcode `/hs-brain-promote` (`brain-garden:36`, `brain-ask:71`, `hivesmith-init:140`, `brain-promote:47`) — pre-existing, out of diff, wants its own sweep.
- **2026-09-06** — Review round 1 (IMPORTANT ×2): `brain-read <path>` is not a supported invocation — `read.sh` takes only `--cwd/--budget/--files` and exits 64 on a positional (verified). Replaced with a direct `cat` of `$BRAIN_HOME/<rel-path>` in `feature-triage` **and** in `feature-loop:146`, where the pattern was copied from. Also quoted the `<terms>` placeholder in all three call sites — they come from untrusted issue text. Why `feature-loop` too: it is the same defect, one line, and leaving it means the next run re-copies it. Root-cause alternative (teach `read.sh` a positional path) rejected as a shared-helper CLI change needing tests, out of scope here.
- **2026-09-06** — `feature-new` inlines its own triage steps (11-15) rather than invoking `/feature-triage`, so "carry hits forward to triage" points at its step 11, not the standalone skill. Why: discovered while implementing; the plan's cross-reference was wrong.
- **2026-09-06** — Each lookup carries an explicit "skip if already in context" guard (operator feedback at the plan stop). Why: `/feature-loop` research → implement, and `feature-new` → triage, both run in one session; a second fetch of the same entries returns the same bytes and only spends budget.
- **2026-09-06** — Normalize `/hs-brain-promote` → `/brain-promote` at `skills/feature-implement/SKILL.md:54`. Why: `install.sh:788` only rewrites the bare form, so the hardcoded one renders wrong under `--prefix ""`. Limited to this one file — the same bug at `skills/hivesmith-init/SKILL.md:140` and the `brain-*` skills is left alone, out of scope.
- **2026-09-06** — `HIVESMITH_SKILL=hs-feature-implement` hardcodes the `hs-` prefix, which is wrong under `--prefix ""`. Why: matching the pre-existing convention at `feature-plan:54`, `feature-research:38`, `review-pr:97`, `feature-loop:295`; fixing it repo-wide is a separate change, not this spec's scope.
- **2026-09-06** — Mechanism is per-skill, not uniform: targeted `brain-search` where the input is feature terms, file-scoped `brain-read --files` where a concrete file list exists. Why: operator's choice; a bare `brain-read` in `feature-implement` would dump unfiltered context when the plan already names the files.

## Progress

- **2026-09-06** — Spec #74 created, triaged S/P2, advanced to RESEARCH.
- **2026-09-06** — Research done (no prior brain lessons matched); plan drafted, 2 reviewer rounds (revise/revise, 9 must-fix applied), approved at the plan stop after one revise round for the no-repeated-lookup guard.
- **2026-09-06** — Implemented on `feature/74-check-hive-brain-in-feature-skills`. Lint, render under `--prefix hs-`, source-wording asserts, existing-readers-untouched and the brain suite (13/13) all pass. `regen-generated --check` exits 1 on the new spec row + changeset line — expected drift, rebuilt by CI on main.

## Open questions

<none>

## PR convergence ledger

- **2026-09-06 iter 2** — verdict: APPROVE; mergeable: MERGEABLE; findings_hash: empty; threads_open: 0; action: stop; head_sha: 1ea9ddc.
- **2026-09-06 iter 1** — verdict: COMMENT; mergeable: MERGEABLE; findings_hash: 2 IMPORTANT + 1 MINOR; threads_open: 0; action: autofix+push; head_sha: 63e4ae6.

## Gate verdict

- **2026-09-06** — verdict: PASS; phase: —; checks: 3 passed / 0 failed / 0 followups; followups: none; one-line: round-1's two Verification defects and the criterion-5 mismatch are all resolved, and the block now runs end to end under `set -e`.
  - 2026-09-06 dimensions:
    - acceptance — PASS — all six criteria re-checked from scratch; the repaired step 4b was confirmed **non-vacuous** by stripping the guard prose from a scratch copy and watching the grep fail; full Verification block exits 0.
    - non-goals — PASS — carried from round 1, unaffected by the fixes (they touched only the plan, the spec's criterion 5 wording, and no skill files).
    - doc accuracy — PASS — Verification block ran top to bottom under `set -e` with no abort (round-1's sole FAIL, cleared); step 9's substitution judged sound rather than a paper-over; roster, changeset and generated-file boundaries all re-verified.

- **2026-09-06** — verdict: FAIL; phase: —; checks: 2 passed / 1 failed / 1 followups; followups: none (PR open, fixed in-place); one-line: shipped behavior is correct, but the plan's own Verification block was broken in two places and criterion 5 was exceeded without being amended.
  - 2026-09-06 dimensions:
    - acceptance — NEEDS_FOLLOWUP — all 6 criteria substantively met (feature-implement step 4 sits between AGENTS.md read and branch creation; feature-new's lookup precedes Gate 1; anti-injection wording inline in all three; `brain-read` positional exit-64 confirmed and no longer documented; existing readers clean vs origin/main), but Verification step 4b's grep failed on feature-triage and feature-new, and the feature-loop edit exceeds criterion 5's "consistency-only" wording.
    - non-goals — PASS — `scripts/brain/` untouched; no reads added beyond the three named skills; no auto-promotion; every lookup explicitly non-blocking; `index.md` not edited. feature-loop edit judged in-scope (single line, fixes exactly the two inherited defects); `/hs-brain-promote` normalization and the triage renumbering judged justified drive-bys.
    - doc accuracy — FAIL — reader roster correct and consistent across all three copies, changeset valid, generated files not hand-edited; but the plan's Verification block is not runnable as written (step 4b regex vs actual prose), falsifying the Progress claim that all steps pass.

