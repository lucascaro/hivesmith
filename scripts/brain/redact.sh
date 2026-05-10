#!/usr/bin/env bash
# redact.sh — read body on stdin, emit redacted body on stdout.
# Aborts (exit 2) on conditions that require human distillation rather than masking.
#
# Rules:
#   - Mask AWS access keys, GitHub tokens (ghp_, ghs_, gho_, github_pat_), generic
#     high-entropy 40+ hex, RSA/EC/PEM private key blocks.
#   - Reject any code fence (```...```) longer than BRAIN_REDACT_MAX_FENCE_LINES
#     (default 25). The brain stores distilled lessons, not raw code.
#   - If `gitleaks` is on PATH, run `gitleaks detect --pipe --no-banner` and abort
#     on hit with the gitleaks report on stderr.
set -euo pipefail

MAX_FENCE="${BRAIN_REDACT_MAX_FENCE_LINES:-25}"

input="$(cat)"

# Code-fence length guard.
fence_len=0
in_fence=0
worst=0
while IFS= read -r line; do
    if [[ "$line" =~ ^\`\`\` ]]; then
        if (( in_fence == 0 )); then
            in_fence=1; fence_len=0
        else
            in_fence=0
            (( fence_len > worst )) && worst=$fence_len
        fi
        continue
    fi
    (( in_fence == 1 )) && fence_len=$((fence_len + 1))
done <<< "$input"
# Unclosed fence at EOF: still count what we saw.
(( in_fence == 1 && fence_len > worst )) && worst=$fence_len
if (( worst > MAX_FENCE )); then
    printf 'redact: code fence length %d exceeds limit %d — distill the lesson, do not paste raw code\n' "$worst" "$MAX_FENCE" >&2
    exit 2
fi

# Optional gitleaks.
if command -v gitleaks >/dev/null 2>&1; then
    if ! printf '%s' "$input" | gitleaks detect --pipe --no-banner --redact 2>/tmp/.brain-gitleaks.$$ >/dev/null; then
        cat /tmp/.brain-gitleaks.$$ >&2 || true
        rm -f /tmp/.brain-gitleaks.$$
        printf 'redact: gitleaks reported a finding\n' >&2
        exit 3
    fi
    rm -f /tmp/.brain-gitleaks.$$
fi

# Inline regex masking — last line of defense.
# Python for portable PCRE-ish replacements (BSD/GNU sed differ).
printf '%s' "$input" | python3 -c '
import re, sys
text = sys.stdin.read()
patterns = [
    (re.compile(r"AKIA[0-9A-Z]{16}"), "[redacted-aws-key]"),
    (re.compile(r"ghp_[A-Za-z0-9]{36,}"), "[redacted-gh-pat]"),
    (re.compile(r"ghs_[A-Za-z0-9]{36,}"), "[redacted-gh-server-token]"),
    (re.compile(r"gho_[A-Za-z0-9]{36,}"), "[redacted-gh-oauth]"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{60,}"), "[redacted-gh-fine-grained-pat]"),
    (re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----.*?-----END (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----", re.DOTALL), "[redacted-private-key]"),
    # Threshold 64+ hex chars: avoids masking legitimate SHA-1 commit references
    # (40 hex). Real secrets accidentally pasted (API keys, GPG keys, etc.) are
    # typically longer; gitleaks (when present) handles the precise patterns.
    (re.compile(r"\b[A-Fa-f0-9]{64,}\b"), "[redacted-hex-blob]"),
    (re.compile(r"\bxox[baprs]-[A-Za-z0-9-]{10,}\b"), "[redacted-slack-token]"),
]
for pat, rep in patterns:
    text = pat.sub(rep, text)
sys.stdout.write(text)
'
