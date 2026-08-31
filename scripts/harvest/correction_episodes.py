#!/usr/bin/env python3
"""Attribute corrections back to the work that caused them, by blaming the lines.

The question this answers is "how often does merged work come back". The usual
way to answer it is to look for later commits touching the same files, and that
is close to useless here: hive averages 10.3 files per commit and CHANGELOG.md
appears in 131 of the last 300, so file overlap attributes every fix to almost
every feature.

This blames the lines instead. A fix commit's diff has a pre-image -- the lines
it deleted or replaced -- and those lines were written by some earlier commit.
`git blame` on the parent, restricted to exactly those line ranges, names it.
That is attribution by evidence rather than by proximity, and it degrades
honestly: a fix that only ADDS lines has no pre-image and is reported as
unattributable rather than guessed at.

What it deliberately does not do:

  * Guess at additive fixes. A fix that only adds a null check corrects an
    absence, and no line carries the blame. Counted separately, never assigned.
  * Treat code movement as a defect. This matters more than it sounds: hive
    split main.js into modules in June, and with ordinary blame that refactor
    absorbed 11 corrections it had no part in causing -- it was merely the last
    commit to touch those lines. Blame therefore runs with aggressive copy
    detection (-C -C -C), which follows a line back across the move to whoever
    actually wrote it. Verify this on your own history before trusting any
    ranking: a refactor at the top of the table is the signature of the bug.
  * Count incidental edits as corrections. Line blame is literal: when a fix
    touches `import { scrollTrace } from './trace.js';` it blames whoever wrote
    that import, and editing an import is not correcting a defect. Measured on
    hive, a code-movement refactor collected 11 "corrections" totalling 26
    lines -- 2.4 lines each, almost all imports and changed call signatures --
    while genuine defect origins run 8 to 20 lines per episode. Attributions
    below --min-lines are therefore dropped as churn, and the ranking is by
    lines corrected rather than by episode count, because one 20-line
    correction says more than five one-line ones.

  * Pretend the denominator is obvious. Escaped-defect rate is reported per
    introducing commit AND per changed line, because a 1,200-line feature and a
    3-line one attracting one fix each are not the same result.
  * Claim the numbers measure quality. They measure defects FOUND, which tracks
    usage as much as correctness. On a project with three users, a feature
    nobody exercises scores perfect. The report says so; do not remove that.

RESULT: PASS fixes=<n> attributed=<n> episodes=<n> median_days=<n> incidental=<n>
RESULT: FAIL reason=<slug>
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import re
import subprocess
import sys
from pathlib import Path

HUNK = re.compile(r"^@@ -(\d+)(?:,(\d+))? \+\d+(?:,\d+)? @@")
# Paths whose churn says nothing about correctness.
NOISE = re.compile(
    r"(^|/)(CHANGELOG|BACKLOG|README|index)\.md$"
    r"|^docs/|^\.changeset/|(^|/)package-lock\.json$|(^|/)pnpm-lock\.yaml$"
    r"|(^|/)go\.sum$|\.snap$", re.I)
COAUTHOR = re.compile(r"^Co-authored-by:\s*(.+?)\s*<", re.I | re.M)
AGENT_TOOL = re.compile(r"^Agent-Tool:\s*(\S+)", re.I | re.M)
AGENT_MODEL = re.compile(r"^Agent-Model:\s*(.+?)\s*$", re.I | re.M)
CONTEXT_SUFFIX = re.compile(r"\s*\((\d+M) context\)\s*$")
NON_MODEL = ("dependabot", "greptile", "github-advanced-security", "copilot autofix")


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args],
                          capture_output=True, text=True).stdout


def commit_meta(root: Path, sha: str) -> dict:
    out = git(root, "show", "-s", "--format=%H%x1f%h%x1f%ad%x1f%s%x1f%b", "--date=short", sha)
    parts = out.strip("\n").split("\x1f")
    if len(parts) < 5:
        return {}
    full, short, date, subj, body = parts[:5]
    blob = subj + "\n" + body
    models = []
    for raw in COAUTHOR.findall(blob):
        if any(b in raw.lower() for b in NON_MODEL):
            continue
        m = CONTEXT_SUFFIX.sub("", raw).strip()
        if m not in models:
            models.append(m)
    tool = AGENT_TOOL.search(blob)
    amodel = AGENT_MODEL.search(blob)
    if amodel and amodel.group(1).strip() not in models:
        models.append(amodel.group(1).strip())
    return {"sha": full, "short": short, "date": date, "subject": subj,
            "models": models, "tool": tool.group(1) if tool else
            ("claude-code" if models and not tool else "")}


def kind(subject: str) -> str:
    m = re.match(r"^([a-z]+)(\([^)]*\))?!?:", subject)
    return m.group(1).lower() if m else ""


def preimage_ranges(root: Path, sha: str) -> dict[str, list[tuple[int, int]]]:
    """Files -> line ranges that this commit DELETED or REPLACED in its parent.

    Only these lines have an author to blame. Pure additions are excluded here
    and counted as unattributable by the caller.
    """
    diff = git(root, "show", sha, "--unified=0", "--format=", "--no-color", "-M")
    out: dict[str, list[tuple[int, int]]] = {}
    path = None
    for line in diff.splitlines():
        if line.startswith("+++ b/"):
            path = line[6:].strip()
            continue
        if line.startswith("+++ ") or line.startswith("--- "):
            continue
        if path and line.startswith("@@"):
            m = HUNK.match(line)
            if not m:
                continue
            start, count = int(m.group(1)), int(m.group(2) or 1)
            if count == 0:            # pure insertion: nothing removed
                continue
            out.setdefault(path, []).append((start, start + count - 1))
    return out


def blame_authors(root: Path, parent: str, path: str, lo: int, hi: int) -> collections.Counter:
    """Which commits wrote lines lo..hi of path at parent. Follows renames."""
    out = subprocess.run(
        # -C -C -C: find lines moved or copied from ANY file in the tree, not
        # just within this file's own history. Without it a refactor that moves
        # code inherits the blame for every defect in what it moved.
        ["git", "-C", str(root), "blame", "--line-porcelain", "-C", "-C", "-C", "-M",
         "-L", f"{lo},{hi}", parent, "--", path],
        capture_output=True, text=True)
    c: collections.Counter = collections.Counter()
    if out.returncode != 0:
        return c
    for line in out.stdout.splitlines():
        m = re.match(r"^([0-9a-f]{40}) \d+ \d+", line)
        if m:
            c[m.group(1)] += 1
    return c


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--limit", type=int, default=500, help="commits to scan")
    ap.add_argument("--window", type=int, default=90,
                    help="days after a commit within which a fix counts against it")
    ap.add_argument("--fix-types", default="fix,perf",
                    help="conventional-commit types that count as corrections")
    ap.add_argument("--origin-types", default="feat,fix,refactor,perf,frontend,tui",
                    help="types eligible to be blamed as the origin")
    ap.add_argument("--min-lines", type=int, default=2,
                    help="attributions smaller than this are incidental churn "
                         "(imports, signatures) rather than corrections")
    ap.add_argument("--by-model", action="store_true", help="group escapes by model")
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not (root / ".git").exists():
        print(f"RESULT: FAIL reason=not-a-git-repo path={root}")
        return 1
    fix_types = {t.strip() for t in args.fix_types.split(",") if t.strip()}
    origin_types = {t.strip() for t in args.origin_types.split(",") if t.strip()}

    shas = [s for s in git(root, "log", f"-{args.limit}", "--format=%H").split() if s]
    if not shas:
        print("RESULT: FAIL reason=no-commits")
        return 1
    meta = {s: commit_meta(root, s) for s in shas}
    meta = {s: m for s, m in meta.items() if m}

    fixes = [s for s in shas if kind(meta.get(s, {}).get("subject", "")) in fix_types]
    if not fixes:
        print(f"RESULT: FAIL reason=no-fix-commits types={','.join(sorted(fix_types))}")
        return 1

    episodes = []          # (fix_sha, origin_sha, lines, days)
    additive_only = 0
    noise_only = 0
    no_origin = 0
    incidental = 0

    for fsha in fixes:
        ranges = preimage_ranges(root, fsha)
        had_preimage = bool(ranges)
        ranges = {p: r for p, r in ranges.items() if not NOISE.search(p)}
        if not ranges:
            # Two different reasons for having nothing to blame, and conflating
            # them hides which one is happening: a fix that only ADDED lines has
            # no author to point at, while a fix confined to CHANGELOG and docs
            # was never a code correction in the first place.
            if had_preimage:
                noise_only += 1
            else:
                additive_only += 1
            continue
        parent = git(root, "rev-parse", f"{fsha}^").strip()
        if not parent:
            continue
        blame: collections.Counter = collections.Counter()
        for path, rs in ranges.items():
            for lo, hi in rs:
                blame += blame_authors(root, parent, path, lo, hi)
        if not blame:
            no_origin += 1
            continue
        fdate = dt.date.fromisoformat(meta[fsha]["date"])
        hit = False
        for osha, lines in blame.most_common():
            om = meta.get(osha) or commit_meta(root, osha)
            if not om:
                continue
            if kind(om["subject"]) not in origin_types:
                continue
            odate = dt.date.fromisoformat(om["date"])
            days = (fdate - odate).days
            if days < 0 or days > args.window:
                continue
            if lines < args.min_lines:
                incidental += 1
                continue
            episodes.append((fsha, osha, lines, days))
            hit = True
        if not hit:
            no_origin += 1

    by_origin: dict[str, list] = collections.defaultdict(list)
    for f, o, l, d in episodes:
        by_origin[o].append((f, l, d))

    print(f"Scanned {len(shas)} commits: {len(fixes)} corrections "
          f"({'/'.join(sorted(fix_types))}), window {args.window}d\n")

    print(f"{'ORIGIN':<9}{'DATE':<12}{'LINES':>7}{'FIXES':>6}{'DAYS':>6}  SUBJECT")
    for osha, hits in sorted(by_origin.items(),
                             key=lambda kv: -sum(l for _, l, _ in kv[1]))[:18]:
        om = meta.get(osha) or commit_meta(root, osha)
        days = sorted(d for _, _, d in hits)
        print(f"{om['short']:<9}{om['date']:<12}"
              f"{sum(l for _, l, _ in hits):>7}{len(hits):>6}{days[len(days)//2]:>6}  "
              f"{om['subject'][:44]}")

    if args.verbose:
        print("\nEpisodes:")
        for f, o, l, d in sorted(episodes, key=lambda e: e[3]):
            fm, om = meta[f], (meta.get(o) or commit_meta(root, o))
            print(f"  {fm['short']} corrects {om['short']} after {d}d "
                  f"({l} lines) — {fm['subject'][:50]}")

    alldays = sorted(d for _, _, _, d in episodes)
    med = alldays[len(alldays)//2] if alldays else 0
    origins_eligible = [s for s in shas if kind(meta.get(s, {}).get("subject", "")) in origin_types]
    # An origin blamed outside the scanned window has no denominator to belong
    # to. Counting it inflates the rate with commits the scan never considered.
    eligible_set = set(origins_eligible)
    escaped_in_window = sum(1 for o in by_origin if o in eligible_set)
    escaped_outside = len(by_origin) - escaped_in_window
    escaped = len(by_origin)

    print()
    print(f"Correction episodes: {len(episodes)} across {escaped} originating commits.")
    print(f"  attributable {len(fixes) - additive_only - no_origin} of {len(fixes)} corrections"
          f"  |  additive-only {additive_only} (no line to blame), "
          f"noise-only {noise_only} (docs/changelog), unresolved {no_origin}")
    print(f"  dropped {incidental} attribution(s) under {args.min_lines} lines as "
          f"incidental churn rather than correction")
    if alldays:
        print(f"  days to correction: median {med}, p90 {alldays[int(len(alldays)*0.9)]}, "
              f"max {alldays[-1]}")
    if origins_eligible:
        print(f"  of {len(origins_eligible)} eligible commits in the scanned window, "
              f"{escaped_in_window} attracted a correction within {args.window}d "
              f"= {100*escaped_in_window/len(origins_eligible):.0f}%")
        if escaped_outside:
            print(f"  a further {escaped_outside} origins predate the scan and are "
                  f"excluded from that rate; raise --limit to bring them in")

    if args.by_model:
        mc: collections.Counter = collections.Counter()
        mt: collections.Counter = collections.Counter()
        unattributed = 0
        for s in origins_eligible:
            ms = meta[s]["models"]
            if not ms:
                unattributed += 1
                continue
            for m in ms:
                mt[m] += 1
        for osha in (o for o in by_origin if o in eligible_set):
            om = meta.get(osha) or commit_meta(root, osha)
            for m in om["models"]:
                mc[m] += 1
        print("\nEscapes by model identity:")
        print(f"  {'ESCAPED':>8}{'SHIPPED':>9}{'RATE':>7}  IDENTITY")
        for m, n in mt.most_common():
            print(f"  {mc.get(m,0):>8}{n:>9}{100*mc.get(m,0)/n:>6.0f}%  {m}")
        if unattributed:
            print(f"  {unattributed} of {len(origins_eligible)} eligible commits carry NO model "
                  f"attribution at all ({100*unattributed/len(origins_eligible):.0f}%).")
            print("  Those are excluded above, and the exclusion is not random -- it is")
            print("  whichever tool does not write a trailer. Fix attribution before")
            print("  reading anything into this table.")

    print()
    print("  These are defects FOUND, not defects PRESENT. Detection tracks usage:")
    print("  code nobody exercises scores perfectly. Read this alongside a usage")
    print("  signal or not at all.")
    print()
    print(f"RESULT: PASS fixes={len(fixes)} attributed={len(by_origin)} "
          f"episodes={len(episodes)} median_days={med} incidental={incidental}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
