#!/usr/bin/env python3
"""Which shipped features later needed fixing -- from declarations, not inference.

A regression is recorded when the agent writing the fix says so, in the
changeset's `regression_of:` frontmatter. Nothing here guesses.

WHY NOT BLAME. The obvious approach is to blame the lines a fix changes and
attribute the defect to whatever introduced them. It does not survive contact
with a real repo: a bug frequently lives on lines the fix never touches (a
missing guard, an unhandled case, an ordering assumption), and a refactor that
rewrites a file is not a defect in the file it rewrote. Both directions of
error are silent. Declaration works here for a specific reason -- every commit
and PR title in this corpus is agent-written, so the agent fixing a defect can
read the last ten merged PR subjects and know which one it is undoing.
`scripts/harvest/correction_episodes.py` still does the blame-based pass; it is
useful as a detector for regressions nobody declared, which this reports as
candidates and never counts.

WHY GIT HISTORY AND NOT THE WORKING TREE. `scripts/release.sh` deletes every
`.changesets/*.md` at release, and the regenerator renders only the body into
CHANGELOG.md -- the frontmatter is dropped. A working-tree scan therefore
reports zero regressions forever, starting at the next release, and looks fine
doing it. Walking `git log --diff-filter=A -- .changesets/` recovers every
declaration ever made, plus the commit and date, and backfills for free.

THE THREE STATES. Reporting a bare "regression rate" would lie, because a PR
merged yesterday has had no chance to show a defect. Every merged PR is
Regressed, Clean (survived the soak window with nothing declared), or
Unobserved (too new to say). All three are printed, always.

RESULT: PASS merged=<n> regressed=<n> clean=<n> unobserved=<n>
RESULT: FAIL reason=<slug>
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import date, datetime
from pathlib import Path

# A squash merge puts the PR number at the end of the subject; `harvest_plans.py`
# uses the same shape. A merge commit announces it at the front. This repo is
# squash-only, but hivesmith scaffolds projects that are not.
SQUASH = re.compile(r"\(#(\d+)\)\s*$")
MERGE = re.compile(r"^Merge pull request #(\d+)\b")
INT_LIST = re.compile(r"^\s*\d+(\s*,\s*\d+)*\s*$")
SEP = "\x1f"
REC = "\x1e"


def git(root: Path, *args: str) -> str:
    r = subprocess.run(["git", "-C", str(root), *args],
                       capture_output=True, text=True)
    return r.stdout


def pr_of(subject: str, body: str) -> int | None:
    """Recover the PR number from a merged commit, both merge styles."""
    m = SQUASH.search(subject) or MERGE.match(subject)
    if m:
        return int(m.group(1))
    # A long conventional-commit subject can push "(#N)" onto the body's first
    # line when the squash subject was truncated.
    first = body.lstrip().splitlines()[0] if body.strip() else ""
    m = SQUASH.search(first)
    return int(m.group(1)) if m else None


def frontmatter(text: str) -> dict:
    """Parse the leading --- block. Deliberately not a YAML dependency: these
    files are flat scalars by schema, and the CI validator must run anywhere."""
    if not text.startswith("---"):
        return {}
    end = text.find("\n---", 3)
    if end == -1:
        return {}
    out = {}
    for line in text[3:end].splitlines():
        line = line.split("#", 1)[0].strip()
        if not line or ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


def parse_regression_of(raw: str) -> list[int]:
    return [int(x) for x in raw.split(",") if x.strip()]


def changeset_history(root: Path) -> list[dict]:
    """Every changeset ever ADDED, with the commit that added it.

    --diff-filter=A is what survives release.sh's deletion: the file is gone at
    HEAD but its addition is still in the history.

    The commit metadata and the file list are two separate queries on purpose.
    Asking for both at once (`--format=...%b --name-only`) interleaves them --
    a multi-line %b runs straight into the file list with no marker between
    them, and any record separator you append to the format lands *before* the
    files, so they get parsed as part of the next commit. The bug is silent:
    every commit appears to touch nothing.
    """
    fmt = SEP.join(["%H", "%h", "%ad", "%s", "%b"]) + REC
    raw = git(root, "log", "--diff-filter=A", "--date=short",
              "--format=" + fmt, "--", ".changesets/")
    out = []
    for block in raw.split(REC):
        if not block.strip():
            continue
        parts = block.lstrip("\n").split(SEP)
        if len(parts) < 5:
            continue
        sha, short, when, subject, body = parts[:5]
        files = git(root, "show", "--diff-filter=A", "--name-only",
                    "--format=", sha, "--", ".changesets/").split()
        for path in files:
            if path.endswith("README.md") or not path.endswith(".md"):
                continue
            text = git(root, "show", f"{sha}:{path}")
            out.append({"sha": sha, "short": short, "date": when,
                        "subject": subject, "body": body,
                        "path": path, "fm": frontmatter(text)})
    return out


def collect(root: Path, soak_days: int):
    entries = changeset_history(root)
    merged: dict[int, dict] = {}      # pr -> {date, subject}
    declarations: list[dict] = []

    for e in entries:
        pr = pr_of(e["subject"], e["body"])
        if pr is not None and pr not in merged:
            merged[pr] = {"date": e["date"], "subject": e["subject"]}
        raw = e["fm"].get("regression_of")
        if not raw:
            continue
        if e["fm"].get("type") != "fixed":
            continue  # validator's problem, not the report's
        for target in parse_regression_of(raw):
            declarations.append({
                "fix_pr": pr, "fix_date": e["date"], "target_pr": target,
                "changeset": e["path"], "issue": e["fm"].get("regression_of_issue"),
            })

    today = date.today()
    regressed, clean, unobserved = [], [], []
    by_target: dict[int, list] = {}
    for d in declarations:
        by_target.setdefault(d["target_pr"], []).append(d)

    for pr, meta in sorted(merged.items()):
        if pr in by_target:
            for d in by_target[pr]:
                ttd = None
                if d["fix_date"]:
                    ttd = (datetime.strptime(d["fix_date"], "%Y-%m-%d").date()
                           - datetime.strptime(meta["date"], "%Y-%m-%d").date()).days
                regressed.append({"pr": pr, "fix_pr": d["fix_pr"],
                                  "merged": meta["date"], "fixed": d["fix_date"],
                                  "days_to_detect": ttd,
                                  "changeset": d["changeset"]})
            continue
        age = (today - datetime.strptime(meta["date"], "%Y-%m-%d").date()).days
        (clean if age > soak_days else unobserved).append({"pr": pr, "merged": meta["date"], "age": age})

    # A declaration naming a PR we never saw merged is a real signal, not noise:
    # either the number is wrong or the corpus is shallower than the claim.
    dangling = [d for d in declarations if d["target_pr"] not in merged]
    return merged, regressed, clean, unobserved, dangling


def validate_changed(root: Path, base: str, head: str) -> int:
    """Format-only gate for CI. Never fails on ABSENCE of a declaration."""
    names = git(root, "diff", "--name-only", "--diff-filter=AM",
                f"{base}...{head}", "--", ".changesets/").split()
    problems = []
    for path in names:
        if path.endswith("README.md"):
            continue
        try:
            text = Path(root, path).read_text()
        except OSError:
            continue
        fm = frontmatter(text)
        raw = fm.get("regression_of")
        if raw is None:
            if fm.get("regression_of_issue"):
                problems.append(f"{path}: regression_of_issue without regression_of")
            continue
        if fm.get("type") != "fixed":
            problems.append(f"{path}: regression_of requires type: fixed (got {fm.get('type')!r})")
            continue
        if not INT_LIST.match(raw):
            problems.append(f"{path}: regression_of must be an integer or comma-separated "
                            f"integers, got {raw!r} — omit the field rather than guessing")
            continue
        merged = {pr for pr in (pr_of(s, "") for s in
                                git(root, "log", "--format=%s", base).splitlines()) if pr}
        for target in parse_regression_of(raw):
            if merged and target not in merged:
                problems.append(f"{path}: regression_of: {target} names a PR that is not "
                                f"in this branch's history")
    for p in problems:
        print(f"  {p}")
    if problems:
        print(f"RESULT: FAIL reason=bad-regression-declaration count={len(problems)}")
        return 1
    print(f"RESULT: PASS checked={len(names)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("repo", nargs="?", default=".", type=Path)
    ap.add_argument("--soak-days", type=int, default=30,
                    help="a merged PR is only 'clean' after surviving this long")
    ap.add_argument("--json", type=Path, help="write the full table here")
    ap.add_argument("--validate-changed", nargs=2, metavar=("BASE", "HEAD"),
                    help="CI mode: check declaration FORMAT on changed changesets")
    args = ap.parse_args()

    root = args.repo.resolve()
    if not (root / ".git").exists():
        print("RESULT: FAIL reason=not-a-git-repo")
        return 1

    if args.validate_changed:
        return validate_changed(root, *args.validate_changed)

    merged, regressed, clean, unobserved, dangling = collect(root, args.soak_days)

    print(f"REGRESSIONS — declared, not inferred (.changesets/ regression_of:)")
    print(f"  merged PRs {len(merged)}   regressed {len(regressed)}   "
          f"clean {len(clean)}   unobserved {len(unobserved)} "
          f"(<{args.soak_days}d, nothing claimed)")
    if not merged:
        print("  no merged PRs found in .changesets/ history — nothing to report")
    for r in regressed:
        ttd = f"{r['days_to_detect']}d" if r["days_to_detect"] is not None else "?"
        print(f"  #{r['pr']} <- #{r['fix_pr']}  ({ttd})   {r['changeset']}")
    days = [r["days_to_detect"] for r in regressed if r["days_to_detect"] is not None]
    if days:
        days.sort()
        print(f"  median time-to-detect {days[len(days) // 2]}d")
    for d in dangling:
        print(f"  WARN regression_of: {d['target_pr']} in {d['changeset']} "
              f"names a PR not seen in this history")
    if not regressed and merged:
        print("  no declared regressions. That is not the same as no regressions —")
        print("  it means none were declared. 'unobserved' above is the honest gap.")

    if args.json:
        args.json.write_text(json.dumps(
            {"merged": merged, "regressed": regressed, "clean": clean,
             "unobserved": unobserved, "dangling": dangling,
             "soak_days": args.soak_days}, indent=2, default=str))

    print(f"RESULT: PASS merged={len(merged)} regressed={len(regressed)} "
          f"clean={len(clean)} unobserved={len(unobserved)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
