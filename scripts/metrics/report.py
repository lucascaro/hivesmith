#!/usr/bin/env python3
"""Are the skills getting better, is the second opinion worth its cost, and
what shipped a regression.

Two tiers, deliberately separate:

  * git-derived -- gate verdicts, ledger entries, regression declarations.
    Computable in CI, backfillable, survives a machine wipe.
  * locally-emitted -- everything with a clock or a count in it: reviewer
    duration, must_fix/applied, seconds-to-approval, which retry fired. Lives
    in ${HIVESMITH_HOME}/telemetry/pipeline-events.jsonl and exists nowhere
    else. When it is absent this prints the git half and says so, rather than
    printing a smaller number as if it were the whole picture.

THE SECOND-OPINION NUMBER IS CORRELATIONAL AND SAYS SO. There is no holdout
arm -- at this repo's cadence a hold-one-in-five design yields ~3 samples a
year, which cannot separate a 30% effect from noise, and every holdout ships a
real feature unreviewed. So nothing here shows the reviewer PREVENTED
anything. It shows what it raised, what was acted on, and what happened next.
The disclaimer prints in the same block as the number, not in a footnote,
because a number that travels without its caveat eventually arrives without it.

Backfilled rows are counted separately and never enter a duration statistic --
the markdown they came from has dates, not clocks.

RESULT: PASS features=<n> live=<n> backfilled=<n>
"""
from __future__ import annotations

import argparse
import json
import os
import statistics
import subprocess
import sys
from collections import Counter, defaultdict
from pathlib import Path


def load_events(path: Path, since: str | None) -> list[dict]:
    if not path.is_file():
        return []
    out = []
    for line in path.read_text(errors="replace").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            r = json.loads(line)
        except ValueError:
            continue                      # a truncated line is not a reason to fail
        if since and r.get("ts", "") < since:
            continue
        out.append(r)
    return out


def fmt_secs(v: float | None) -> str:
    if v is None:
        return "—"
    v = int(v)
    if v < 90:
        return f"{v}s"
    if v < 5400:
        return f"{v // 60}m"
    return f"{v // 3600}h{(v % 3600) // 60:02d}"


def half_split(values: list, n: int = 5) -> tuple[list, list]:
    """First n vs last n, in the order recorded. Not a statistic — a direction."""
    if len(values) < 2:
        return [], []
    k = min(n, len(values) // 2)
    return values[:k], values[-k:]


def trend(name: str, first: list, last: list, unit: str = "", lower_is_better=True) -> str:
    if not first or not last:
        return f" {name:<32} not enough history yet"
    a, b = statistics.mean(first), statistics.mean(last)
    arrow = "—" if abs(a - b) < 1e-9 else ("↓" if b < a else "↑")
    good = "" if arrow == "—" else ("  better" if (b < a) == lower_is_better else "  worse")
    return f" {name:<32} first {len(first)}: {a:<6.1f}{unit}  last {len(last)}: {b:<6.1f}{unit} {arrow}{good}"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--repo", default=".", type=Path)
    ap.add_argument("--since", help="ISO date; drop events before it")
    ap.add_argument("--events", type=Path,
                    default=Path(os.environ.get("HIVESMITH_HOME",
                                                Path.home() / ".hivesmith"))
                    / "telemetry" / "pipeline-events.jsonl")
    ap.add_argument("--json", type=Path)
    args = ap.parse_args()

    ev = load_events(args.events, args.since)
    live = [e for e in ev if not e.get("backfilled")]
    back = [e for e in ev if e.get("backfilled")]
    by = defaultdict(list)
    for e in ev:
        by[e.get("event", "?")].append(e)
    features = {e.get("feature") for e in ev if e.get("feature")}

    print(f"PIPELINE   {args.since or 'all time'} → now      "
          f"features={len(features)}  live={len(live)}  backfilled={len(back)}")
    if not ev:
        print(f"  no events at {args.events}")
        print("  This is the local tier. It is written by hs-metric during pipeline runs")
        print("  and exists on this machine only. Seed history with:")
        print("    python3 scripts/metrics/backfill.py --emit")

    # ---- stage / stall ------------------------------------------------------
    if by["stage_transition"] or by["stall"]:
        print()
        stalls = Counter(e.get("retry", "?") for e in by["stall"])
        moves = Counter(e.get("to", "?") for e in by["stage_transition"])
        # Attribute a stall by the `stage` field it already carries. Matching
        # the stage name against the retry slug instead was wrong twice over:
        # REVIEW's first four letters ("revi") are a substring of
        # "plan-revise-rerun", so a PLAN stall was counted under REVIEW as
        # well as PLAN, and a retry slug naming no stage was counted nowhere.
        stalls_by_stage = Counter(e.get("stage", "?") for e in by["stall"])
        print(" stage reached      count   stalls")
        for stage in ["RESEARCH", "PLAN", "IMPLEMENT", "REVIEW", "GATE", "DONE"]:
            if not moves.get(stage):
                continue
            rel = stalls_by_stage.get(stage, 0)
            print(f" {stage:<18} {moves[stage]:>5}   {rel or ''}")
        for retry, n in stalls.most_common():
            print(f"   stall: {retry} × {n}")

    # ---- trends -------------------------------------------------------------
    # Ordered by feature number, not by row order. Backfilled rows all carry
    # the timestamp of the backfill run, so `ts` cannot order history; the
    # feature number can, because it is allocated monotonically. Getting this
    # wrong turns "first 5 vs last 5" into a directory-listing artifact.
    def fnum(f):
        try:
            return int(f)
        except (TypeError, ValueError):
            return 10 ** 9

    iters = defaultdict(int)
    for e in by["review_iteration"]:
        iters[e.get("feature")] = max(iters[e.get("feature")], e.get("iter", 1))
    iters = {k: iters[k] for k in sorted(iters, key=fnum)}
    gates = [1.0 if e.get("verdict") != "PASS" else 0.0
             for e in sorted(by["gate_verdict"], key=lambda e: fnum(e.get("feature")))]
    rounds = [e.get("rounds", 1)
              for e in sorted(by["plan_approved"], key=lambda e: fnum(e.get("feature")))]

    if iters or gates or rounds:
        print("\nTREND — are the skills getting better?")
        f, l = half_split(list(iters.values()))
        print(trend("review iterations to converge", f, l))
        f, l = half_split(gates)
        print(trend("gate non-PASS rate", [x * 100 for x in f], [x * 100 for x in l], "%"))
        f, l = half_split(rounds)
        print(trend("plan approval rounds", f, l))
        print(" (directional only — small n, unrandomised. Do not read a p-value into this.)")

    # ---- second opinion -----------------------------------------------------
    so = by["second_opinion"]
    if so:
        print("\nSECOND OPINION — correlational, not causal. No holdout arm exists, so")
        print("nothing here shows the second opinion PREVENTED anything. It shows what it")
        print("found, what was acted on, and what happened next.")
        durs = [e["duration_s"] for e in so if not e.get("backfilled") and "duration_s" in e]
        raised = sum(e.get("must_fix_count", 0) for e in so)
        applied = sum(e.get("applied_count", 0) for e in so)
        verdicts = Counter(e.get("verdict") for e in so)
        total = fmt_secs(sum(durs)) if durs else "—"
        p50 = fmt_secs(statistics.median(durs)) if durs else "—"
        print(f" runs {len(so)}   cost {total} total (p50 {p50})   "
              f"verdicts: " + " / ".join(f"{k} {v}" for k, v in verdicts.most_common()))
        if raised:
            print(f" must_fix {raised} raised, {applied} applied ({100 * applied // raised}%)"
                  "   — applied/raised is the honest ratio: a rejected item is a")
            print("   recorded outcome, so a reviewer at 10 raised / 2 applied is making noise.")
        else:
            print(" must_fix 0 raised — nothing to act on yet")
        # flips: same feature, round 2 exists
        rounds_by = defaultdict(dict)
        for e in so:
            rounds_by[e.get("feature")][e.get("round")] = e.get("verdict")
        flips = sum(1 for r in rounds_by.values()
                    if r.get(1) == "revise" and r.get(2) == "approve")
        revises = sum(1 for r in rounds_by.values() if r.get(1) == "revise")
        if revises:
            print(f" revise→approve flips: {flips} of {revises}")
        # downstream correlation
        with_mf = [f for f, r in rounds_by.items()
                   if any(e.get("must_fix_count", 0) > 0 for e in so if e.get("feature") == f)]
        wo_mf = [f for f in rounds_by if f not in with_mf]
        def mean_iters(fs):
            vals = [iters[f] for f in fs if f in iters]
            return statistics.mean(vals) if vals else None
        a, b = mean_iters(with_mf), mean_iters(wo_mf)
        if a is not None and b is not None:
            print(f" features with must_fix>0 → {a:.1f} review iters;  must_fix=0 → {b:.1f}")
            print("   (if that gap is real, the reviewer is DETECTING difficulty, which is a")
            print("    different claim from creating quality — and also worth knowing.)")

    # ---- regressions --------------------------------------------------------
    print()
    r = subprocess.run([sys.executable, str(Path(__file__).with_name("regressions.py")),
                        str(args.repo)], capture_output=True, text=True)
    sys.stdout.write(r.stdout)
    # A half-empty report that still says PASS is worse than a failure: the
    # regressions block simply vanishes and anything parsing the RESULT line
    # reads it as healthy. Carry the child's failure into the exit status.
    if r.returncode != 0:
        sys.stderr.write(r.stderr)
        print(f"  regressions.py failed (rc={r.returncode}) — see stderr above")

    if args.json:
        args.json.write_text(json.dumps(
            {"features": sorted(x for x in features if x), "live": len(live),
             "backfilled": len(back),
             "counts": {k: len(v) for k, v in by.items()}}, indent=2))

    if r.returncode != 0:
        print("\nRESULT: FAIL reason=regressions-failed")
        return 1
    print(f"\nRESULT: PASS features={len(features)} live={len(live)} backfilled={len(back)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
