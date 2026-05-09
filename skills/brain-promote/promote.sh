#!/usr/bin/env bash
# promote.sh — broaden an entry's scope via git mv + front-matter edit.
#
# Usage:
#   promote.sh <relative-or-absolute-path> --to <universal|ecosystem|user> [--ecosystem <lang>]
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB="$DIR/../../scripts/brain/lib.sh"
[ -f "$LIB" ] || LIB="${HIVESMITH_DIR:-$HOME/.hivesmith}/scripts/brain/lib.sh"
[ -f "$LIB" ] || LIB="$HOME/.hivesmith/bin/brain-lib.sh"
# shellcheck source=/dev/null disable=SC1091
. "$LIB"

if [ $# -lt 3 ]; then
    printf 'usage: promote.sh <path> --to <scope> [--ecosystem <lang>]\n' >&2
    exit 64
fi

INPUT="$1"; shift
TARGET_SCOPE=""
TARGET_ECOSYSTEM=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --to)        TARGET_SCOPE="$2"; shift 2 ;;
        --ecosystem) TARGET_ECOSYSTEM="$2"; shift 2 ;;
        *) printf 'promote: unknown arg: %s\n' "$1" >&2; exit 64 ;;
    esac
done

case "$TARGET_SCOPE" in
    universal|user|ecosystem) ;;
    *) printf 'promote: invalid --to scope: %s (must be universal|ecosystem|user)\n' "$TARGET_SCOPE" >&2; exit 64 ;;
esac
if [ "$TARGET_SCOPE" = "ecosystem" ] && [ -z "$TARGET_ECOSYSTEM" ]; then
    printf 'promote: --ecosystem required when --to ecosystem\n' >&2
    exit 64
fi

# Resolve the input to an absolute path under $BRAIN_HOME.
if [ -f "$INPUT" ]; then
    src="$(cd "$(dirname "$INPUT")" && pwd)/$(basename "$INPUT")"
elif [ -f "$BRAIN_HOME/$INPUT" ]; then
    src="$BRAIN_HOME/$INPUT"
else
    # Slug-based lookup.
    candidates=()
    while IFS= read -r -d '' f; do candidates+=("$f"); done < <(find "$BRAIN_HOME" -type f -name "${INPUT}.md" -print0)
    if [ "${#candidates[@]}" -eq 0 ]; then
        printf 'promote: no entry matches "%s"\n' "$INPUT" >&2
        exit 65
    fi
    if [ "${#candidates[@]}" -gt 1 ]; then
        printf 'promote: ambiguous "%s" — matches:\n' "$INPUT" >&2
        printf '  %s\n' "${candidates[@]}" >&2
        exit 65
    fi
    src="${candidates[0]}"
fi

slug="$(basename "$src" .md)"
old_scope="$(python3 "$(brain_yaml_py)" get "$src" scope 2>/dev/null || true)"
[ -z "$old_scope" ] && { printf 'promote: %s has no scope front-matter\n' "$src" >&2; exit 66; }

case "$TARGET_SCOPE" in
    universal) dst_dir="$BRAIN_HOME/universal" ;;
    ecosystem) dst_dir="$BRAIN_HOME/ecosystem/$TARGET_ECOSYSTEM" ;;
    user)      dst_dir="$BRAIN_HOME/user" ;;
esac
dst="$dst_dir/$slug.md"

if [ -e "$dst" ]; then
    printf 'promote: target already exists at %s\n' "$dst" >&2
    exit 67
fi

mkdir -p "$dst_dir"
git -C "$BRAIN_HOME" mv "${src#"$BRAIN_HOME"/}" "${dst#"$BRAIN_HOME"/}" 2>/dev/null || mv "$src" "$dst"

# Edit front-matter: scope, optionally remove repo, set/remove ecosystem.
python3 - "$dst" "$TARGET_SCOPE" "$TARGET_ECOSYSTEM" <<'PY'
import sys, re, datetime
path, scope, ecosystem = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path, encoding='utf-8').read()
m = re.match(r'^---\n(.*?)\n---\n(.*)$', text, re.DOTALL)
if not m:
    sys.exit('no front-matter')
fm, body = m.group(1), m.group(2)
lines = fm.splitlines()
out = []
saw_scope = False
saw_eco = False
for line in lines:
    if line.startswith('scope:'):
        out.append(f'scope: {scope}')
        saw_scope = True
    elif line.startswith('ecosystem:'):
        if scope == 'ecosystem':
            out.append(f'ecosystem: {ecosystem}')
            saw_eco = True
        # else drop
    elif line.startswith('repo:'):
        if scope == 'project':
            out.append(line)
        # else drop (broader scopes have no repo)
    else:
        out.append(line)
if not saw_scope:
    out.insert(0, f'scope: {scope}')
if scope == 'ecosystem' and not saw_eco:
    out.append(f'ecosystem: {ecosystem}')
new_fm = '\n'.join(out)
today = datetime.date.today().isoformat()
note = f'\n- {today} — Promoted to {scope} via /hs-brain-promote.\n'
if '## Decision log' in body:
    body = body.replace('## Decision log', '## Decision log' + note, 1)
else:
    body = body.rstrip() + '\n\n## Decision log\n' + note
open(path, 'w', encoding='utf-8').write(f'---\n{new_fm}\n---\n{body}')
PY

git -C "$BRAIN_HOME" add -A >/dev/null 2>&1 || true
git -C "$BRAIN_HOME" commit -q -m "brain: promote $slug ($old_scope → $TARGET_SCOPE)" >/dev/null 2>&1 || true

printf '%s\n' "$dst"
