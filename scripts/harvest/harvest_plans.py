#!/usr/bin/env python3
"""Join every exec plan to the work it produced: plan -> PR -> commit -> models -> files.

The point of this is a baseline that already exists. A repo built by agents has
been recording, in ordinary git metadata, which model wrote which change and
what shipped -- for months, without anyone deciding to measure it. This walks
that back into one table so the questions can be asked retrospectively rather
than waiting a quarter for fresh telemetry.

What it will NOT do is pretend the table is an experiment. Thirty plans across
eight model identities is roughly four each, unrandomised, confounded by task
difficulty and by the repo's own maturity over the same period. The summary
prints counts, never a ranking, and the caveat is printed with them.

Joining is the hard part, because the corpus is real:

  * The PR field is written five different ways -- `#242`, a bare pull URL,
    `[#179](url)`, prose about a PR that was closed unmerged -- and 13 of 34
    plans have no PR line at all. Hence a fallback chain, with every row
    reporting HOW it was joined so a weak link is visible rather than silently
    equal to a strong one.
  * The number in a plan's filename is its SPEC number, which is not its PR
    number and often not its issue number either. Treating them as one key
    silently mismatches rows.
  * The model is not in a Model: trailer. It is in Co-Authored-By, and a
    squash-merge carries one per squashed commit, so a PR has a SET of models,
    not a model. Rows that name three models are real and must not be flattened
    to the first.

CI outcome needs the GitHub API and is therefore optional enrichment behind
--gh; without it every row still carries its git-derived columns.

RESULT: PASS plans=<n> joined=<n> commits=<n> models=<n>
RESULT: FAIL reason=<slug>
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import shutil
import subprocess
import sys
from collections import Counter
from pathlib import Path

FIELD = re.compile(r"^\s*[-*]\s*\*\*(?P<key>[A-Za-z]+):\*\*\s*(?P<val>.*?)\s*$", re.M)
PR_IN_TEXT = re.compile(r"(?:/pull/|#)(\d+)")
SQUASH = re.compile(r"\(#(\d+)\)\s*$")
COAUTHOR = re.compile(r"^Co-authored-by:\s*(.+?)\s*<", re.I | re.M)
ISSUE_REF = re.compile(r"#(\d+)")
# "Claude Opus 5 (1M context)" and "Claude Opus 5" are one model run two ways.
CONTEXT_SUFFIX = re.compile(r"\s*\((\d+M) context\)\s*$")
NON_MODEL = ("dependabot", "greptile", "github-advanced-security")


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args],
                          capture_output=True, text=True).stdout


def header_fields(text: str) -> dict[str, str]:
    """The `- **Key:** value` block at the top of a plan."""
    head = text.split("\n## ", 1)[0]
    return {m.group("key").lower(): m.group("val") for m in FIELD.finditer(head)}


def parse_ref(val: str) -> int | None:
    """First PR/issue number in a field written any of five ways."""
    if not val or val.strip() in {"—", "-", "n/a", "none", ""}:
        return None
    m = PR_IN_TEXT.search(val)
    return int(m.group(1)) if m else None


def split_model(raw: str) -> tuple[str, str]:
    """('Claude Opus 5', '1M') -- the identity and the context window it ran with."""
    m = CONTEXT_SUFFIX.search(raw)
    return (CONTEXT_SUFFIX.sub("", raw).strip(), m.group(1) if m else "")


class Repo:
    def __init__(self, root: Path, limit: int):
        self.root = root
        self.commits: list[dict] = []
        raw = git(root, "log", f"-{limit}", "--format=%H%x1f%h%x1f%ad%x1f%s%x1f%b%x1e",
                  "--date=short")
        for chunk in raw.split("\x1e"):
            if not chunk.strip():
                continue
            parts = chunk.strip("\n").split("\x1f")
            if len(parts) < 5:
                continue
            sha, short, date, subj, body = parts[:5]
            self.commits.append({
                "sha": sha, "short": short, "date": date, "subject": subj,
                "body": body,
                "pr": int(SQUASH.search(subj).group(1)) if SQUASH.search(subj) else None,
                "refs": {int(n) for n in ISSUE_REF.findall(subj + "\n" + body)},
            })
        self.by_pr = {c["pr"]: c for c in self.commits if c["pr"]}

    def models(self, c: dict) -> list[tuple[str, str]]:
        out = []
        for raw in COAUTHOR.findall(c["subject"] + "\n" + c["body"]):
            if any(b in raw.lower() for b in NON_MODEL) or "@" in raw:
                continue
            ident = split_model(raw)
            if ident not in out:
                out.append(ident)
        return out

    def files(self, sha: str) -> list[str]:
        out = git(self.root, "show", "--name-only", "--format=", sha)
        return [ln for ln in out.splitlines() if ln.strip()]

    def churn(self, sha: str) -> tuple[int, int]:
        out = git(self.root, "show", "--shortstat", "--format=", sha)
        ins = re.search(r"(\d+) insertion", out)
        dele = re.search(r"(\d+) deletion", out)
        return (int(ins.group(1)) if ins else 0, int(dele.group(1)) if dele else 0)


def join_plan(repo: Repo, plan: Path, root: Path) -> dict:
    text = plan.read_text(encoding="utf-8", errors="replace")
    fields = header_fields(text)
    stem = plan.stem
    spec_no = int(stem.split("-", 1)[0]) if stem.split("-", 1)[0].isdigit() else None
    pr_no = parse_ref(fields.get("pr", ""))
    issue_no = parse_ref(fields.get("issue", ""))

    commit, how = None, "unjoined"
    if pr_no and pr_no in repo.by_pr:                      # strongest: stated PR
        commit, how = repo.by_pr[pr_no], "pr-field"
    if commit is None and spec_no:                          # the spec number as a PR
        if spec_no in repo.by_pr:
            commit, how = repo.by_pr[spec_no], "spec-as-pr"
    if commit is None and spec_no:                          # anything citing the spec
        cands = [c for c in repo.commits if spec_no in c["refs"]]
        if cands:
            commit, how = cands[-1], "issue-ref"
    if commit is None and pr_no:
        cands = [c for c in repo.commits if pr_no in c["refs"]]
        if cands:
            commit, how = cands[-1], "pr-ref"

    row = {
        "plan": plan.relative_to(root).as_posix(),
        "spec": spec_no or "", "issue": issue_no or "", "pr": pr_no or "",
        "stage": fields.get("stage", ""), "status": fields.get("status", ""),
        "join": how, "commit": "", "date": "", "models": "", "context": "",
        "files": 0, "insertions": 0, "deletions": 0, "paths": [],
    }
    if commit:
        ms = repo.models(commit)
        files = repo.files(commit["sha"])
        ins, dele = repo.churn(commit["sha"])
        row.update({
            "commit": commit["short"], "date": commit["date"],
            "models": "; ".join(sorted({m for m, _ in ms})),
            "context": "; ".join(sorted({c for _, c in ms if c})),
            "files": len(files), "insertions": ins, "deletions": dele,
            "paths": files, "_sha": commit["sha"],
        })
    return row


def enrich_gh(rows: list[dict], repo_slug: str) -> str:
    """PR state and CI conclusion from the GitHub API. Requires an authed `gh`.

    Written to fail loud and change nothing: the git-derived table stands on its
    own, and a missing or unauthenticated gh must degrade to a note, never to a
    blank column that reads as 'no CI'.
    """
    if not shutil.which("gh"):
        return "gh not on PATH -- CI columns skipped"
    for row in rows:
        if not row["pr"]:
            continue
        out = subprocess.run(
            ["gh", "pr", "view", str(row["pr"]), "--repo", repo_slug, "--json",
             "state,mergedAt,statusCheckRollup,reviews,additions,deletions"],
            capture_output=True, text=True)
        if out.returncode != 0:
            row["pr_state"] = "unavailable"
            continue
        try:
            d = json.loads(out.stdout)
        except json.JSONDecodeError:
            row["pr_state"] = "unparseable"
            continue
        checks = d.get("statusCheckRollup") or []
        concl = {c.get("conclusion") for c in checks if isinstance(c, dict)}
        row["pr_state"] = d.get("state", "")
        row["merged_at"] = (d.get("mergedAt") or "")[:10]
        row["ci"] = ("FAILURE" if "FAILURE" in concl
                     else "SUCCESS" if concl and concl <= {"SUCCESS", "NEUTRAL", "SKIPPED"}
                     else "mixed" if concl else "none")
        row["reviews"] = len(d.get("reviews") or [])
    return f"enriched {sum(1 for r in rows if r.get('pr_state'))} rows via gh"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("root", nargs="?", default=".")
    ap.add_argument("--plans-dir", default="docs/exec-plans")
    ap.add_argument("--limit", type=int, default=600, help="commits to scan")
    ap.add_argument("--csv", metavar="PATH", help="write the full join as CSV")
    ap.add_argument("--json", metavar="PATH", help="write the full join as JSON")
    ap.add_argument("--gh", metavar="OWNER/REPO",
                    help="enrich with PR state and CI conclusion (needs authed gh)")
    args = ap.parse_args()

    root = Path(args.root).expanduser().resolve()
    if not (root / ".git").exists():
        print(f"RESULT: FAIL reason=not-a-git-repo path={root}")
        return 1
    plans_dir = root / args.plans_dir
    if not plans_dir.is_dir():
        print(f"RESULT: FAIL reason=no-plans-dir dir={plans_dir}")
        return 1
    plans = sorted(p for sub in ("completed", "active", ".")
                   for p in (plans_dir / sub).glob("*.md"))
    plans = [p for p in plans if p.name.lower() not in {"readme.md", "index.md", "_template.md"}]
    if not plans:
        print(f"RESULT: FAIL reason=no-plans dir={plans_dir}")
        return 1

    repo = Repo(root, args.limit)
    if not repo.commits:
        print("RESULT: FAIL reason=no-commits")
        return 1

    rows = [join_plan(repo, p, root) for p in plans]
    note = enrich_gh(rows, args.gh) if args.gh else ""

    joined = [r for r in rows if r["commit"]]
    print(f"{'PLAN':<44}{'PR':>6}{'COMMIT':>9}{'DATE':>12}  {'JOIN':<11}"
          f"{'FILES':>6}{'+':>7}{'-':>7}  MODELS")
    for r in sorted(rows, key=lambda r: (r["date"] or "0000")):
        name = Path(r["plan"]).stem
        print(f"{name[:43]:<44}{str(r['pr']):>6}{r['commit']:>9}{r['date']:>12}  "
              f"{r['join']:<11}{r['files']:>6}{r['insertions']:>7}{r['deletions']:>7}  "
              f"{r['models'][:44]}")

    print()
    print(f"Joined {len(joined)} of {len(rows)} plans to a commit.")
    by_how = Counter(r["join"] for r in rows)
    print("  by method: " + ", ".join(f"{k} {v}" for k, v in by_how.most_common()))

    model_counts: Counter[str] = Counter()
    for r in joined:
        for m in filter(None, r["models"].split("; ")):
            model_counts[m] += 1
    if model_counts:
        spans: dict[str, list[str]] = {}
        for r in joined:
            for m in filter(None, r["models"].split("; ")):
                spans.setdefault(m, []).append(r["date"])
        print()
        print("Plans per model identity (a plan with several co-authors counts once each):")
        print(f"  {'N':>3}  {'FIRST':<12}{'LAST':<12}IDENTITY")
        for m, n in model_counts.most_common():
            d = sorted(spans[m])
            print(f"  {n:>3}  {d[0]:<12}{d[-1]:<12}{m}")

        # Whether these identities can be compared at all is a question the data
        # answers by itself: if their date ranges do not overlap, model is a
        # proxy for calendar time, and any difference between them is
        # indistinguishable from the repo growing up.
        ranges = {m: (min(spans[m]), max(spans[m])) for m in spans}
        overlaps = sum(1 for a in ranges for b in ranges
                       if a < b and ranges[a][0] <= ranges[b][1]
                       and ranges[b][0] <= ranges[a][1])
        pairs = len(ranges) * (len(ranges) - 1) // 2
        print()
        if pairs and overlaps == 0:
            print("  NOT COMPARABLE. No two identities worked in overlapping periods, so")
            print("  model is a proxy for calendar time here. Any difference between them")
            print("  is indistinguishable from the repo maturing, the task mix changing,")
            print("  or the author learning the tool. Use these rows to generate")
            print("  hypotheses and test them prospectively; do not rank models with them.")
        else:
            print(f"  {overlaps} of {pairs} identity pairs overlap in time. Counts only, not a")
            print("  ranking: unrandomised, confounded by task difficulty and repo maturity.")
        print(f"  ~{len(joined) / max(len(model_counts), 1):.1f} plans per identity.")

    if note:
        print(f"\ngh: {note}")
        ci = Counter(r.get("ci", "") for r in rows if r.get("ci"))
        if ci:
            print("  CI conclusions: " + ", ".join(f"{k} {v}" for k, v in ci.most_common()))

    if args.csv or args.json:
        out_rows = [{k: v for k, v in r.items() if k != "_sha"} for r in rows]
        if args.csv:
            keys = sorted({k for r in out_rows for k in r} - {"paths"})
            with open(args.csv, "w", newline="", encoding="utf-8") as fh:
                w = csv.DictWriter(fh, fieldnames=keys, extrasaction="ignore")
                w.writeheader()
                w.writerows(out_rows)
            print(f"\nwrote {args.csv}")
        if args.json:
            Path(args.json).write_text(json.dumps(out_rows, indent=2), encoding="utf-8")
            print(f"wrote {args.json}")

    print()
    print(f"RESULT: PASS plans={len(rows)} joined={len(joined)} "
          f"commits={len(repo.commits)} models={len(model_counts)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
