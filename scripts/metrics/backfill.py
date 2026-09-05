#!/usr/bin/env python3
"""Seed the metric stream from the plan markdown that already recorded it.

Gate verdicts and PR-convergence ledger lines have been written into exec plans
for months. They are semi-structured -- `key: value;` pairs in a bullet -- so
they can be recovered without an LLM. That gives the trend lines a history
instead of starting from zero.

WHAT IS NOT BACKFILLED, AND WHY

  * Second opinions. Exactly two plans carry a `## Second opinion` section and
    both say `revise`. A bespoke prose parser to recover two identical rows is
    more code than the data is worth. That series starts live.
  * Durations. The markdown records dates, not clocks. There is no
    `duration_s` to recover and inventing one would be exactly the failure this
    tool exists to prevent, so every backfilled row omits it and `report.py`
    keeps backfilled rows out of every duration statistic.

WHAT THE CORPUS ACTUALLY LOOKS LIKE (all of this is real, all of it is handled)

  * `## QA verdict` is the legacy heading for `## Gate verdict` and is still
    live in five plans. It also carries `build/lint/test` and `regression`
    dimensions that no longer exist; those are preserved in `legacy_dimension`
    rather than dropped.
  * Ledger fields are inconsistent between the template, the skill spec, and
    reality: some lines carry `mergeable`, some do not; `threads_open` is in
    every real entry but missing from the template. Parsing is key-based, never
    positional.
  * Values contain prose. One entry reads
    `verdict: REQUEST_CHANGES (Copilot thread on duplicate heading)` and
    another `findings_hash: <unrecorded -- worker returned summary without
    envelope>`. Enum fields are matched, not trusted; unparseable values are
    dropped rather than passed through as strings.

Every row is emitted through `hs-metric --backfilled --backfill-source
<file:line>`, so it carries its provenance and can never be mistaken for live
measurement.

RESULT: PASS plans=<n> gate=<n> ledger=<n> skipped=<n>
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

ENTRY = re.compile(r"^\s*-\s+\*\*(?P<date>\d{4}-\d{2}-\d{2})(?P<rest>.*)$")
# A sub-iteration ("iter 3c", "iter 1.5") is NOT iteration 3 or 1. Without the
# lookahead this captures the leading digits and silently collides with the
# real iteration of that number. Today those rows happen to be dropped by the
# enum check instead, but that is luck, not design: a sub-iteration with valid
# enum values would backfill under the wrong iteration number.
ITER = re.compile(r"\biter\s+(\d+)(?![\w.])")
DIM = re.compile(r"^\s+-\s+(?P<name>[a-z/ -]+?)\s+—\s+(?P<verdict>PASS|FAIL|NEEDS_FOLLOWUP)\b")
HEX = re.compile(r"^[0-9a-f]{6,}$")
PR_HDR = re.compile(r"^\s*-\s*\*\*PR:\*\*\s*.*?#?(\d+)", re.M)

GATE_V = {"PASS", "FAIL", "NEEDS_FOLLOWUP"}
REVIEW_V = {"APPROVE", "COMMENT", "REQUEST_CHANGES"}
MERGEABLE = {"MERGEABLE", "CONFLICTING", "UNKNOWN"}
ACTIONS = ["autofix+push (conflict)", "autofix+push", "escalated", "stop"]
# The dimension names that outlived the rename, mapped to schema fields.
DIM_FIELD = {"acceptance": "acceptance", "non-goals": "non_goals",
             "doc accuracy": "doc_accuracy"}


def fields_of(rest: str) -> dict:
    """Split `k: v; k: v;` into a dict. Key-based on purpose -- the field set
    genuinely differs between entries, so position means nothing."""
    out = {}
    for chunk in rest.split(";"):
        if ":" not in chunk:
            continue
        k, v = chunk.split(":", 1)
        # The first chunk of a ledger line is "iter 1** — verdict", and of a
        # gate line "** — verdict": the real key is whatever follows the last
        # em dash, if there is one.
        k = k.rsplit("—", 1)[-1]
        k = k.strip().strip("*").strip().lower().replace(" ", "_")
        out[k] = v.strip().rstrip(".").strip()
    return out


def enum_of(raw: str, allowed: set) -> str | None:
    """Match an enum inside a value that may carry trailing prose."""
    if not raw:
        return None
    token = raw.strip().split()[0].strip("().,")
    return token if token in allowed else None


def action_of(raw: str) -> str | None:
    raw = (raw or "").strip()
    if raw.startswith("escalated"):
        return "escalated"
    for a in ACTIONS:
        if raw.startswith(a):
            return a
    return None


def section(lines: list[str], *headings: str) -> tuple[int, list[str]] | None:
    for i, ln in enumerate(lines):
        if ln.strip() in headings:
            body = []
            for j in range(i + 1, len(lines)):
                if lines[j].startswith("## "):
                    break
                body.append((j + 1, lines[j]))
            return i + 1, body
    return None


def emit(tool: str, event: str, fields: dict, source: str, dry: bool) -> bool:
    argv = [tool, "--event", event]
    for k, v in fields.items():
        if v is None or v == "":
            continue
        argv += ["--field", f"{k}={v}"]
    argv += ["--backfilled", "--backfill-source", source]
    if dry:
        argv.append("--dry-run")
    r = subprocess.run(argv, capture_output=True, text=True)
    if r.returncode != 0:
        sys.stderr.write(f"  skip {source}: {r.stderr.strip()}\n")
        return False
    if dry:
        sys.stdout.write(r.stdout)
    return True


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", nargs="?", default=".", type=Path)
    ap.add_argument("--emit", action="store_true", help="required; without it nothing runs")
    ap.add_argument("--dry-run", action="store_true", help="print rows instead of appending")
    ap.add_argument("--tool", default=os.path.expanduser("~/.hivesmith/bin/hs-metric"))
    args = ap.parse_args()
    if not args.emit:
        ap.error("pass --emit (with --dry-run first)")

    tool = args.tool
    if not Path(tool).exists():
        local = args.repo / "scripts/metrics/emit.sh"
        if local.exists():
            tool = str(local)
        else:
            print(f"RESULT: FAIL reason=no-hs-metric path={tool}")
            return 1

    plans = sorted(list((args.repo / "docs/exec-plans/active").glob("*.md"))
                   + list((args.repo / "docs/exec-plans/completed").glob("*.md")))
    n_plans = n_gate = n_ledger = n_skip = 0
    skipped: list[tuple[str, str]] = []

    for plan in plans:
        m = re.match(r"(\d{3})-", plan.name)
        if not m:
            continue          # tech-debt-tracker.md and friends
        feature = m.group(1)
        text = plan.read_text()
        lines = text.splitlines()
        rel = plan.relative_to(args.repo)
        pr_m = PR_HDR.search(text)
        pr = pr_m.group(1) if pr_m else None
        n_plans += 1

        # ---- gate verdicts (with the legacy heading) -----------------------
        sec = section(lines, "## Gate verdict", "## QA verdict")
        if sec:
            _, body = sec
            current = None
            pending = []
            for lineno, ln in body:
                e = ENTRY.match(ln)
                if e and "iter " not in e.group("rest"):
                    if current:
                        pending.append(current)
                    f = fields_of(e.group("rest"))
                    v = enum_of(f.get("verdict", ""), GATE_V)
                    current = None if not v else {
                        "feature": feature, "verdict": v, "src": f"{rel}:{lineno}"}
                    if current:
                        fu = f.get("followups", "")
                        nums = re.findall(r"\d+", fu)
                        if nums and "none" not in fu.lower():
                            current["followups"] = ",".join(nums)
                    continue
                d = DIM.match(ln)
                if d and current is not None:
                    name = d.group("name").strip()
                    if name in DIM_FIELD:
                        current[DIM_FIELD[name]] = d.group("verdict")
                    else:
                        current.setdefault("legacy_dimension", name.replace(" ", "-"))
            if current:
                pending.append(current)
            for row in pending:
                src = row.pop("src")
                if emit(tool, "gate_verdict", row, src, args.dry_run):
                    n_gate += 1
                else:
                    n_skip += 1

        # ---- convergence ledger -------------------------------------------
        sec = section(lines, "## PR convergence ledger")
        if sec:
            _, body = sec
            for lineno, ln in body:
                e = ENTRY.match(ln)
                if not e:
                    continue
                it = ITER.search(e.group("rest"))
                if not it:
                    continue
                f = fields_of(e.group("rest"))
                v = enum_of(f.get("verdict", ""), REVIEW_V)
                a = action_of(f.get("action", ""))
                if not v or not a:
                    # Pre-enum history: prose in the action field ("fixed 3
                    # findings + push"), `verdict: n/a (operator decision)`,
                    # sub-iterations like `iter 3c`. These are NOT mapped onto
                    # the nearest enum value -- guessing that "fixed 3 findings
                    # + push" meant `autofix+push` would put an invented value
                    # in the series and there would be no way to tell later.
                    # They are dropped and named, so the gap is inspectable.
                    n_skip += 1
                    # Name the field that failed, with its raw value. Printing
                    # a truncated excerpt of the line instead would usually cut
                    # off before the offending field, which is the one thing
                    # the operator needs in order to judge the gap.
                    why = []
                    if not v:
                        why.append(f"verdict={f.get('verdict', '')!r}")
                    if not a:
                        why.append(f"action={f.get('action', '')!r}")
                    skipped.append((f"{rel}:{lineno}", "; ".join(why)))
                    continue
                row = {"feature": feature, "iter": it.group(1), "verdict": v, "action": a}
                if pr:
                    row["pr"] = pr
                th = f.get("threads_open", "")
                if th.isdigit():
                    row["threads_open"] = th
                mg = enum_of(f.get("mergeable", ""), MERGEABLE)
                if mg:
                    row["mergeable"] = mg
                fh = f.get("findings_hash", "")
                # "empty", "(empty)", and "<unrecorded -- ...>" are all real.
                # A hash that was never recorded is null, not a string.
                if HEX.match(fh):
                    row["findings_hash"] = fh
                sha = f.get("head_sha", "")
                if re.match(r"^[0-9a-f]{6,}$", sha):
                    row["head_sha"] = sha
                if a == "escalated":
                    reason = f.get("action", "")
                    if ":" in reason:
                        row["escalate_reason"] = reason.split(":", 1)[1].strip()[:60]
                if emit(tool, "review_iteration", row, f"{rel}:{lineno}", args.dry_run):
                    n_ledger += 1
                else:
                    n_skip += 1

    if skipped:
        print(f"\n{len(skipped)} pre-enum ledger entries not backfilled "
              f"(values that predate the enum contract; not mapped, to avoid "
              f"inventing history):")
        for src, why in skipped:
            print(f"  {src}\n    unmapped: {why}")
    print(f"\nRESULT: PASS plans={n_plans} gate={n_gate} ledger={n_ledger} skipped={n_skip}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
