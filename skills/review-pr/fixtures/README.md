# review-pr regression suite

Fixture-based regression tests for `skills/review-pr/SKILL.md`. The skill is executed by an LLM, so this suite cannot be a unit test — it's a graded harness you run when you change the skill.

## What it tests

| Case | Asserts |
|---|---|
| `tiny-docs` | Fan-out gate fires. Baseline review only, **zero agents dispatched**, verdict `APPROVE`, 0 BLOCKING/IMPORTANT findings. |
| `planted-bugs` | All 4 planted issues caught: SQL injection, race, off-by-one, hardcoded secret. Verdict `REQUEST_CHANGES`. All four are in-diff and in one file — this is the diff-level fidelity floor. |
| `clean-refactor` | False-positive floor. A pure rename with no real issues should yield ≤ 1 MINOR finding and verdict `APPROVE`. |
| `cross-file` | **Out-of-diff** breakage: an exported signature gains a required param and a caller in a file that is *not in the diff* is left broken. Only catchable by a dispatched agent that greps callers. Guards the §2 correctness trigger and the §5.2 rule that keeps out-of-diff citations. |

## Layout

```
fixtures/
  bin/
    mock-gh         # stand-in for `gh` CLI; reads from the active case dir
    run-case        # sets up env for one case and prints next steps
    grade           # compares actual JSON output vs expected.yaml
  cases/
    <case-name>/
      pr.patch      # the diff (what `gh pr diff` returns)
      meta.json     # what `gh pr view --json ...` returns
      expected.yaml # ground-truth findings + verdict
      snapshot/     # minimal source tree the patch applies against
                    #   (so the verification pass can Read the cited files)
```

## Running a case

```bash
cd skills/review-pr/fixtures
./bin/run-case tiny-docs
```

That puts `mock-gh` on `PATH`, exports `FIXTURE_DIR`, and prints the exact prompt to send to Claude. Claude executes the skill against the fixture (the skill calls `gh`, which routes to `mock-gh`, which reads from `FIXTURE_DIR`). Save Claude's final JSON output to a file, then:

```bash
./bin/grade tiny-docs /tmp/actual.json
```

The grader prints precision, recall, false-positive count, verdict match, and exits non-zero on regression.

## Adding a case

1. Create `cases/<name>/`.
2. Write `pr.patch` — a real unified diff. Make it apply cleanly to `snapshot/`.
3. Write `meta.json` — at minimum: `{title, body, baseRefName, headRefName, files, comments, reviews}`. Mirrors `gh pr view --json title,body,baseRefName,headRefName,files,comments,reviews`.
4. Populate `snapshot/` with the post-patch state of changed files (the verification pass reads these). If the case tests out-of-diff effects, `snapshot/` must also hold the *unchanged* files the effect lands in — they appear nowhere in `pr.patch` by design. Verify the patch and snapshot agree: `cd snapshot && git apply --reverse --check ../pr.patch`.
5. Write `expected.yaml`:
   ```yaml
   verdict: REQUEST_CHANGES   # or APPROVE / COMMENT
   must_find:                 # findings the suite REQUIRES to be caught (recall)
     - file: app/db.py
       line_range: [40, 50]
       category: security
       keywords: [sql, injection]
   must_not_find:             # things the skill must NOT flag (precision)
     - file: README.md
       reason: typo fix, no behavior change
   max_findings: 6            # cap above which we count noise
   ```
6. Run it. Tune until the skill consistently passes. That's your new floor.

## What this suite does not do

- Cost / token measurement. That requires Claude API instrumentation — out of scope here. If you want it, run the same case 3 times across old/new skill versions and eyeball the trace.
- Automated CI. There's no CI runner for "invoke an LLM with this prompt." A nightly Claude API job calling each case is the natural extension.
