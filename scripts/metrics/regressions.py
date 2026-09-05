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


def git_ok(root: Path, *args: str) -> bool:
    return subprocess.run(["git", "-C", str(root), *args],
                          capture_output=True, text=True).returncode == 0


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
    # Total by construction. `collect()` reads raw frontmatter out of git
    # history, where the format gate (--validate-changed) never ran: it only
    # ever inspects changesets in a PR diff, so anything landed before that
    # job existed reaches here unchecked. A bare int() turned one malformed
    # declaration (`regression_of: #42`) into a ValueError that killed the
    # whole report and the CI metrics job. Unparseable targets are dropped
    # here and surface as a dangling declaration, which is the visible state.
    return [int(x) for x in raw.split(",") if x.strip().lstrip("+-").isdigit()]


def cat_file_batch(root: Path, specs: list[str]) -> list[str]:
    """Read many blobs in ONE git process.

    Binary, not text=True: `cat-file --batch` frames each blob with a BYTE
    length, and changeset bodies are full of em dashes, so slicing a decoded
    string by that length desyncs the stream and silently shifts every
    subsequent file's content onto the wrong changeset.
    """
    if not specs:
        return []
    proc = subprocess.run(["git", "-C", str(root), "cat-file", "--batch"],
                          input=("\n".join(specs) + "\n").encode(), capture_output=True)
    data, out, i = proc.stdout, [], 0
    for _ in specs:
        nl = data.find(b"\n", i)
        if nl == -1:
            out.append("")
            continue
        parts = data[i:nl].split()
        if len(parts) < 3 or parts[1] != b"blob":
            out.append("")            # missing / not a blob
            i = nl + 1
            continue
        size = int(parts[2])
        start = nl + 1
        out.append(data[start:start + size].decode("utf-8", "replace"))
        i = start + size + 1          # git appends a newline after the blob
    return out


def commit_prs(root: Path) -> tuple[dict, dict]:
    """The full merged-PR universe: sha -> pr, and pr -> {date, subject}.

    This deliberately walks ALL history, not just commits that added a
    changeset. A PR merged under the `no-changeset` label (docs, CI) shipped
    code like any other and can still be the thing a later fix undoes. Deriving
    the universe from changeset-adding commits only would drop those PRs from
    the denominator AND make a legitimate `regression_of:` pointing at one look
    like a dangling reference to a PR that never existed.
    """
    by_sha: dict[str, int] = {}
    by_pr: dict[int, dict] = {}
    raw = git(root, "log", "--date=short",
              "--format=" + SEP.join(["%H", "%ad", "%s", "%b"]) + REC)
    for block in raw.split(REC):
        parts = block.lstrip("\n").split(SEP)
        if len(parts) < 4:
            continue
        sha, when, subject, body = parts[:4]
        pr = pr_of(subject, body)
        if pr is None:
            continue
        by_sha[sha] = pr
        by_pr.setdefault(pr, {"date": when, "subject": subject})
    return by_sha, by_pr


def changeset_history(root: Path) -> list[dict]:
    """Every changeset ever ADDED, with the commit that added it.

    --diff-filter=A is what survives release.sh's deletion: the file is gone at
    HEAD but its addition is still in the history.

    The format deliberately omits %b. A multi-line body run together with
    --name-only has no marker between the two, and any record separator
    appended to the format lands *before* the file list, so the files get
    parsed as part of the next commit — a silent bug where every commit
    appears to touch nothing. A subject is single-line, so this is
    unambiguous, and the body is not needed here: the PR number comes from
    commit_prs().
    """
    fmt = REC + SEP.join(["%H", "%ad", "%s"])
    raw = git(root, "log", "--diff-filter=A", "--date=short",
              "--format=" + fmt, "--name-only", "--", ".changesets/")
    out = []
    for block in raw.split(REC):
        if not block.strip():
            continue
        lines = block.lstrip("\n").splitlines()
        head = lines[0].split(SEP)
        if len(head) < 3:
            continue
        sha, when, subject = head[:3]
        for path in lines[1:]:
            path = path.strip()
            if not path or not path.endswith(".md") or path.endswith("README.md"):
                continue
            out.append({"sha": sha, "date": when, "subject": subject, "path": path})
    for entry, text in zip(out, cat_file_batch(root, [f"{e['sha']}:{e['path']}" for e in out])):
        entry["fm"] = frontmatter(text)
    return out


def collect(root: Path, soak_days: int):
    entries = changeset_history(root)
    by_sha, merged = commit_prs(root)
    declarations: list[dict] = []

    for e in entries:
        pr = by_sha.get(e["sha"])
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
    # An unresolvable ref makes `git diff` print nothing to stdout and fail on
    # stderr, which this would otherwise read as "no changesets changed" and
    # report as a PASS. A gate that silently passes when it cannot see the diff
    # is worse than no gate, so both refs are resolved first.
    for ref in (base, head):
        if not git_ok(root, "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"):
            print(f"  cannot resolve ref: {ref}")
            print("RESULT: FAIL reason=unresolvable-ref")
            return 1

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
