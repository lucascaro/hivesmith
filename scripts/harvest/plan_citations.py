#!/usr/bin/env python3
"""Verify that an exec plan's code citations were true when it was written.

A hivesmith exec plan earns its authority from specificity: it does not say
"the VT wrapper", it says `internal/session/vt.go:35-52`. That specificity is
also the only part of a plan a machine can check, which makes it the one quality
signal available without CI, without a judge, and without waiting for telemetry.

Two mistakes make a naive checker useless, and this avoids both:

  1. CHECKING AGAINST THE WRONG TREE. A plan written in May citing
     main.js:2534 is measured against a tree where main.js has since been split
     into src/app/*.js and deleted outright. Every citation in it reads as a
     fabrication. Nor is "the commit that last touched the plan" the fix: one
     docs-hygiene commit in this corpus rewrote 14 plans at once, dragging all
     14 forward to a July tree. The reference point is the commit that ADDED
     the plan, following renames into completed/ -- the moment its citations
     were claims about the code. `--at head` deliberately measures the other
     thing: how far the code has drifted from its own documentation.

  2. READING SHORTHAND AS FABRICATION. A plan section about the GUI frontend
     cites `src/app/view.js:46`, meaning
     cmd/hivegui/frontend/src/app/view.js. Demanding a repo-root-relative path
     turns the most common citation style in the corpus into 45 phantom
     failures -- a 30-point error, and every one of them the tool's fault.
     Paths are therefore resolved by unique suffix against the tree at that
     commit. Exactly one tracked file ending in the cited path is a resolution;
     several is ambiguous and is not counted either way.

  3. COUNTING WHAT CANNOT BE CHECKED. Plans cite vendored source
     ($GOMODCACHE/...), URLs, and bare filenames belonging to dependencies
     ("state.go:477" is vt10x, not hive). A bare name that matches nothing is
     no evidence of a bad citation -- it is no evidence at all. Only a path
     that names a directory and still resolves to nothing is a real miss.

  4. PENALISING A PLAN FOR PROPOSING WORK. A TypeScript migration plan cites
     src/bridge.ts before src/bridge.ts exists -- that is the plan, not a bad
     citation. A path absent when the plan was written but present later is
     reported as `planned` and excluded. A path that never existed at any point
     is a miss, and the distinction is the whole point: it separates "describes
     the future" from "describes nothing".

Accuracy = ok / (ok + range + miss), over citations that were claims about
code that existed at the time.

RESULT: PASS plans=<n> citations=<n> accuracy=<pct> miss=<n> range=<n> ambiguous=<n> planned=<n>
RESULT: FAIL reason=<slug>
Exit 0 unless the repo is unreadable; a wrong citation is a finding, not an error.
"""
from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

# `path/to/file.ext:12` or `:12-34`, inside backticks or bare.
CITE = re.compile(r"`?([\w./+-]+\.[A-Za-z][\w]*):(\d+)(?:-(\d+))?`?")
EXTERNAL_HINTS = ("$GOMODCACHE", "GOMODCACHE", "vendor/", "node_modules/", "http")


def git(root: Path, *args: str) -> str:
    try:
        return subprocess.run(["git", "-C", str(root), *args],
                              capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return ""


def authoring_commit(root: Path, rel: str) -> str:
    """The commit that first added this plan, following renames.

    Plans are written under active/ and later moved to completed/, so a
    rename-blind lookup finds the move. A bulk docs edit is worse: it makes
    every plan it touched look as though it were written that day.
    """
    for args in (("log", "--follow", "--diff-filter=A", "-1", "--format=%H", "--", rel),
                 ("log", "--diff-filter=A", "-1", "--format=%H", "--", rel),
                 ("log", "-1", "--format=%H", "--", rel)):
        c = git(root, *args).strip()
        if c:
            return c
    return "WORKTREE"


_TREE: dict[str, list[str]] = {}


def tracked_at(root: Path, commit: str) -> list[str]:
    """Every tracked path at commit, cached. Worktree files if commit is WORKTREE."""
    if commit in _TREE:
        return _TREE[commit]
    if commit == "WORKTREE":
        out = git(root, "ls-files")
    else:
        out = git(root, "ls-tree", "-r", "--name-only", commit)
    _TREE[commit] = [ln for ln in out.splitlines() if ln]
    return _TREE[commit]


def resolve(root: Path, commit: str, raw: str) -> tuple[str | None, str]:
    """Map a cited path to one tracked file.

    Returns (path, how) where how is exact | suffix | ambiguous | miss.
    A plan may cite a path relative to the section it is describing, so a
    unique suffix match is a resolution, not a guess. Several matches is
    ambiguous: the citation may well be correct, but nothing here can tell
    which file it meant, so it is excluded rather than judged.
    """
    paths = tracked_at(root, commit)
    if raw in paths:
        return raw, "exact"
    tail = "/" + raw
    hits = [p for p in paths if p.endswith(tail)]
    if len(hits) == 1:
        return hits[0], "suffix"
    if len(hits) > 1:
        return None, "ambiguous"
    # A bare filename that matches nothing is most often a dependency's file
    # quoted in prose. Nothing here can call that wrong.
    return None, ("miss" if "/" in raw else "unresolvable")


def file_len_at(root: Path, commit: str, path: str) -> int | None:
    """Line count of path at commit, or None if it did not exist there."""
    if commit == "WORKTREE":
        p = root / path
        try:
            return len(p.read_text(encoding="utf-8", errors="replace").splitlines()) if p.is_file() else None
        except OSError:
            return None
    out = subprocess.run(["git", "-C", str(root), "show", f"{commit}:{path}"],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return None
    return len(out.stdout.splitlines())


def classify(root: Path, commit: str, raw: str, start: int, end: int) -> tuple[str, str]:
    """Verdict for one citation, plus how its path was resolved."""
    if any(h in raw for h in EXTERNAL_HINTS):
        return "external", "-"
    path, how = resolve(root, commit, raw)
    if path is None:
        if how == "miss" and resolve(root, "HEAD", raw)[0] is not None:
            return "planned", how    # the repo went on to create it
        return how, how          # ambiguous | unresolvable | miss
    n = file_len_at(root, commit, path)
    if n is None:
        return "miss", how
    return ("ok" if end <= n else "range"), how


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--at", choices=["plan", "head"], default="plan",
                    help="resolve citations at the plan's own commit (default) or at HEAD")
    ap.add_argument("--plans-dir", default="docs/exec-plans")
    ap.add_argument("--verbose", action="store_true", help="list every non-ok citation")
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not (root / ".git").exists():
        print(f"RESULT: FAIL reason=not-a-git-repo path={root}")
        return 1
    plans_dir = root / args.plans_dir
    plans = sorted(p for sub in ("completed", "active", ".")
                   for p in (plans_dir / sub).glob("*.md")) if plans_dir.is_dir() else []
    plans = [p for p in plans if p.name.lower() not in {"readme.md", "index.md"}]
    if not plans:
        print(f"RESULT: FAIL reason=no-plans dir={plans_dir}")
        return 1

    totals = {k: 0 for k in ("ok", "range", "miss", "planned", "ambiguous",
                             "unresolvable", "external")}
    by_suffix = 0
    rows, findings = [], []

    for plan in plans:
        rel = plan.relative_to(root).as_posix()
        commit = "HEAD" if args.at == "head" else authoring_commit(root, rel)
        text = plan.read_text(encoding="utf-8", errors="replace")
        seen, counts = set(), {k: 0 for k in totals}
        for m in CITE.finditer(text):
            raw, s, e = m.group(1), int(m.group(2)), int(m.group(3) or m.group(2))
            if (raw, s, e) in seen:
                continue
            seen.add((raw, s, e))
            verdict, how = classify(root, commit, raw, s, e)
            if how == "suffix":
                by_suffix += 1
            counts[verdict] += 1
            totals[verdict] += 1
            if verdict in ("miss", "range"):
                findings.append((rel, raw, s, e, verdict))
        checkable = counts["ok"] + counts["range"] + counts["miss"]
        rows.append((rel, checkable, counts["ok"], counts["range"], counts["miss"],
                     counts["external"] + counts["ambiguous"]
                     + counts["unresolvable"] + counts["planned"]))

    checkable = totals["ok"] + totals["range"] + totals["miss"]
    acc = (100.0 * totals["ok"] / checkable) if checkable else 0.0

    print(f"Plans: {len(plans)}   resolved at: "
          + ("HEAD (drift mode)" if args.at == "head" else "the commit that wrote each plan"))
    print()
    print(f"{'PLAN':<58}{'chk':>5}{'ok':>5}{'rng':>5}{'miss':>6}{'skip':>6}")
    for rel, chk, ok, rng, miss, skip in sorted(rows, key=lambda r: (-(r[3] + r[4]), r[0])):
        name = rel.split("/")[-1]
        print(f"{name[:57]:<58}{chk:>5}{ok:>5}{rng:>5}{miss:>6}{skip:>6}")
    if findings and args.verbose:
        print()
        print("Non-ok citations:")
        for rel, raw, s, e, verdict in findings:
            span = f"{s}" if s == e else f"{s}-{e}"
            print(f"  {verdict:<6} {raw}:{span}   ({rel.split('/')[-1]})")
    print()
    print(f"Resolved {checkable}  ok {totals['ok']}  range {totals['range']}  "
          f"miss {totals['miss']}   |  excluded: ambiguous {totals['ambiguous']}, "
          f"planned {totals['planned']}, unresolvable {totals['unresolvable']}, "
          f"external {totals['external']}")
    print(f"Of the resolved, {by_suffix} matched by unique suffix "
          f"(cited relative to a section, not the repo root).")
    print()
    print(f"RESULT: PASS plans={len(plans)} citations={checkable} "
          f"accuracy={acc:.1f} miss={totals['miss']} range={totals['range']} "
          f"ambiguous={totals['ambiguous']} planned={totals['planned']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
