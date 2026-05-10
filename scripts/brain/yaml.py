#!/usr/bin/env python3
"""Tiny YAML front-matter helper for hivesmith brain entries.

Stdlib only. Supports the small subset hivesmith brain entries need:
  - scalars (strings, numbers, booleans, ISO dates)
  - flow-style lists: tags: [a, b, c]
  - simple nested mapping: provenance: { source: foo, trusted: true }
  - block-style nested mapping (one level deep)

Commands:
  yaml.py read <path>           emit key=value lines from front-matter
  yaml.py get <path> <key>      emit one value (dotted path supported, e.g. provenance.source)
  yaml.py validate <path>       exit 0 if front-matter parses and required keys present
"""
from __future__ import annotations

import sys
from pathlib import Path

REQUIRED = {"slug", "scope", "provenance", "confidence", "created"}


def split_frontmatter(text: str) -> tuple[dict, str]:
    if not text.startswith("---\n"):
        return {}, text
    end = text.find("\n---\n", 4)
    if end == -1:
        return {}, text
    raw = text[4:end]
    body = text[end + 5 :]
    return parse_block(raw), body


def parse_scalar(s: str):
    s = s.strip()
    if not s:
        return ""
    if s.startswith("[") and s.endswith("]"):
        inner = s[1:-1].strip()
        if not inner:
            return []
        return [parse_scalar(x) for x in split_flow(inner)]
    if s.startswith("{") and s.endswith("}"):
        inner = s[1:-1].strip()
        if not inner:
            return {}
        out = {}
        for pair in split_flow(inner):
            if ":" in pair:
                k, v = pair.split(":", 1)
                out[k.strip()] = parse_scalar(v.strip())
        return out
    if (s.startswith('"') and s.endswith('"')) or (s.startswith("'") and s.endswith("'")):
        return s[1:-1]
    if s.lower() in ("true", "yes"):
        return True
    if s.lower() in ("false", "no"):
        return False
    if s.lower() in ("null", "~", ""):
        return None
    try:
        if "." in s:
            return float(s)
        return int(s)
    except ValueError:
        pass
    return s


def split_flow(s: str) -> list[str]:
    out, depth, buf = [], 0, []
    for ch in s:
        if ch in "[{":
            depth += 1
        elif ch in "]}":
            depth -= 1
        if ch == "," and depth == 0:
            out.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    if buf:
        out.append("".join(buf).strip())
    return out


def parse_block(text: str) -> dict:
    out: dict = {}
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        line = lines[i]
        if not line.strip() or line.lstrip().startswith("#"):
            i += 1
            continue
        if line.startswith(" ") or line.startswith("\t"):
            i += 1
            continue
        if ":" not in line:
            i += 1
            continue
        key, rest = line.split(":", 1)
        key = key.strip()
        rest = rest.strip()
        if rest:
            out[key] = parse_scalar(rest)
            i += 1
            continue
        # Block-style nested mapping: collect indented lines.
        block: dict = {}
        i += 1
        while i < len(lines) and (lines[i].startswith(" ") or lines[i].startswith("\t")):
            sub = lines[i].strip()
            if sub and not sub.startswith("#") and ":" in sub:
                k, v = sub.split(":", 1)
                block[k.strip()] = parse_scalar(v.strip())
            i += 1
        out[key] = block
    return out


def flatten(d: dict, prefix: str = "") -> list[tuple[str, str]]:
    rows = []
    for k, v in d.items():
        key = f"{prefix}.{k}" if prefix else k
        if isinstance(v, dict):
            rows.extend(flatten(v, key))
        elif isinstance(v, list):
            rows.append((key, ",".join(str(x) for x in v)))
        else:
            rows.append((key, "" if v is None else str(v)))
    return rows


def cmd_read(path: str) -> int:
    text = Path(path).read_text(encoding="utf-8")
    fm, _ = split_frontmatter(text)
    if not fm:
        return 0
    for k, v in flatten(fm):
        print(f"{k}={v}")
    return 0


def cmd_get(path: str, key: str) -> int:
    text = Path(path).read_text(encoding="utf-8")
    fm, _ = split_frontmatter(text)
    cur = fm
    for part in key.split("."):
        if not isinstance(cur, dict) or part not in cur:
            return 1
        cur = cur[part]
    if isinstance(cur, list):
        print(",".join(str(x) for x in cur))
    elif cur is None:
        pass
    else:
        print(cur)
    return 0


def cmd_validate(path: str) -> int:
    text = Path(path).read_text(encoding="utf-8")
    fm, _ = split_frontmatter(text)
    if not fm:
        print(f"no front-matter in {path}", file=sys.stderr)
        return 2
    missing = [k for k in REQUIRED if k not in fm]
    if missing:
        print(f"{path}: missing required keys: {','.join(missing)}", file=sys.stderr)
        return 3
    return 0


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 64
    cmd = argv[1]
    if cmd == "read" and len(argv) == 3:
        return cmd_read(argv[2])
    if cmd == "get" and len(argv) == 4:
        return cmd_get(argv[2], argv[3])
    if cmd == "validate" and len(argv) == 3:
        return cmd_validate(argv[2])
    print(__doc__, file=sys.stderr)
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
