#!/usr/bin/env bash
# hivesmith pipeline metrics: append one validated event to the local stream.
#
# Installed as ~/.hivesmith/bin/hs-metric.
#
# WHY THIS IS A SEPARATE FILE FROM scripts/telemetry/
#
# The telemetry hooks fire on every subagent in every session and must NEVER
# fail one, so they swallow every error and always exit 0. This script has the
# exact opposite contract: it must fail LOUDLY. It is called by skills whose
# whole job is to record what happened, and an event that silently didn't get
# written is worse than no metrics at all — it is a gap you cannot see.
# Opposite contracts belong in opposite files, so this writes to
# pipeline-events.jsonl and never touches agent-events.jsonl (which
# prepare-commit-msg reads for tool attribution).
#
# WHY UNKNOWN FIELDS ARE REJECTED
#
# The problem being solved is that the pipeline already produces structured
# data and then dissolves it into prose. A free-text escape hatch here would be
# used for everything within a week and we would be back where we started. If
# you need a field that isn't in the schema, add it to the schema.
#
# Usage:
#   hs-metric --event <name> --field k=v [--field k=v ...]
#             [--backfilled --backfill-source <file:line>] [--dry-run]
#
# Exit codes: 0 appended · 64 rejected (nothing written) · 2 usage
set -uo pipefail

EVENT=""
DRY_RUN=0
BACKFILLED=0
BACKFILL_SOURCE=""
FIELDS=()

# A value-taking flag MUST be checked before `shift 2`. Without `set -e`, a
# `shift 2` with one argument left fails silently and shifts NOTHING, so `$1`
# is still the same flag next pass and the loop spins forever — `--field` then
# grows FIELDS until the process is killed. `${2:-}` hides it by making the
# assignment succeed. Callers are LLM-composed command lines, where an empty
# variable collapses `--field "$X"` into a trailing `--field`, so this is a
# reachable input, not a theoretical one.
need_value() {
    if [[ $2 -lt 2 ]]; then
        echo "hs-metric: $1 requires a value" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --event)           need_value "$1" $#; EVENT="$2"; shift 2 ;;
        --field)           need_value "$1" $#; FIELDS+=("$2"); shift 2 ;;
        --backfilled)      BACKFILLED=1; shift ;;
        --backfill-source) need_value "$1" $#; BACKFILL_SOURCE="$2"; shift 2 ;;
        --dry-run)         DRY_RUN=1; shift ;;
        -h|--help)         sed -n '2,28p' "${BASH_SOURCE[0]}"; exit 0 ;;
        *) echo "hs-metric: unknown argument: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$EVENT" ]]; then
    echo "hs-metric: --event is required" >&2
    exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "hs-metric: python3 not found" >&2; exit 2; }

HOME_DIR="${HIVESMITH_HOME:-$HOME/.hivesmith}"
LOG_DIR="$HOME_DIR/telemetry"
LOG="$LOG_DIR/pipeline-events.jsonl"

PROJECT=$(git rev-parse --show-toplevel 2>/dev/null) || PROJECT=""
if [[ -n "$PROJECT" ]]; then PROJECT=$(basename "$PROJECT"); else PROJECT=$(basename "$PWD"); fi

HS_EVENT="$EVENT" \
HS_LOG="$LOG" \
HS_LOG_DIR="$LOG_DIR" \
HS_PROJECT="$PROJECT" \
HS_DRY_RUN="$DRY_RUN" \
HS_BACKFILLED="$BACKFILLED" \
HS_BACKFILL_SOURCE="$BACKFILL_SOURCE" \
HS_SKILL="${HIVESMITH_SKILL:-}" \
HS_SESSION="${CLAUDE_SESSION_ID:-}" \
python3 - "${FIELDS[@]+"${FIELDS[@]}"}" <<'PY'
import datetime, difflib, json, os, sys

# event -> (required fields, optional fields)
SCHEMA = {
    "plan_rendered":    ({"feature", "round"}, {"sections", "bytes"}),
    "plan_approved":    ({"feature", "rounds", "seconds_to_approval"}, {"via"}),
    "second_opinion":   ({"feature", "verdict", "confidence", "must_fix_count",
                          "applied_count", "round", "duration_s"}, set()),
    "review_iteration": ({"feature", "pr", "iter", "verdict", "findings_count",
                          "threads_open", "action"},
                         {"findings_hash", "mergeable", "head_sha", "escalate_reason"}),
    "autofix_applied":  ({"feature", "pr", "safe", "risky", "deferred"},
                         {"threads_fixed", "threads_resolved", "threads_open", "checks"}),
    "gate_verdict":     ({"feature", "verdict", "acceptance", "non_goals",
                          "doc_accuracy"}, {"followups", "legacy_dimension"}),
    "stall":            ({"feature", "retry", "stage"}, {"reason"}),
    "stage_transition": ({"feature", "from", "to"}, set()),
    "feature_done":     ({"feature"}, {"pr", "seconds_total"}),
}

STAGES = {"TRIAGE", "RESEARCH", "PLAN", "IMPLEMENT", "REVIEW", "GATE", "DONE"}
DIMENSION = {"PASS", "FAIL", "NEEDS_FOLLOWUP"}

# (event, field) -> allowed values. `verdict` means three different things in
# three events, which is exactly why this is keyed by event and not by name.
ENUM = {
    ("second_opinion", "verdict"):   {"approve", "revise", "block"},
    ("review_iteration", "verdict"): {"APPROVE", "COMMENT", "REQUEST_CHANGES"},
    ("review_iteration", "action"):  {"stop", "autofix+push", "autofix+push (conflict)", "escalated"},
    ("review_iteration", "mergeable"): {"MERGEABLE", "CONFLICTING", "UNKNOWN"},
    ("gate_verdict", "verdict"):     DIMENSION,
    ("gate_verdict", "acceptance"):  DIMENSION,
    ("gate_verdict", "non_goals"):   DIMENSION,
    ("gate_verdict", "doc_accuracy"): DIMENSION,
    ("autofix_applied", "checks"):   {"PASS", "FAIL"},
    ("stage_transition", "from"):    STAGES,
    ("stage_transition", "to"):      STAGES,
    ("plan_approved", "via"):        {"html", "native-plan-mode", "chat"},
    ("stall", "retry"):              {"plan-revise-rerun", "implement-checks-refix",
                                      "gate-fail-rerun", "review-loop-guard"},
    ("stall", "stage"):              STAGES,
}

INT = {"confidence", "must_fix_count", "applied_count", "round", "rounds",
       "iter", "safe", "risky", "deferred", "threads_open", "threads_fixed",
       "threads_resolved", "duration_s", "seconds_to_approval", "seconds_total",
       "findings_count", "sections", "bytes", "pr"}

RANGE = {"confidence": (1, 10)}

# Fields the historical markdown record never contained, so a --backfilled row
# is allowed to omit them. This is a narrow, enumerated exemption, not a
# general escape hatch: the alternative is inventing values for
# `findings_count` and calling it measurement, which is the exact failure this
# whole tool exists to prevent. A live (non-backfilled) emit must still supply
# every one of them.
BACKFILL_EXEMPT = {
    "review_iteration": {"findings_count", "threads_open", "pr"},
    "gate_verdict": {"acceptance", "non_goals", "doc_accuracy"},
}


def die(msg):
    sys.stderr.write("hs-metric: %s\n" % msg)
    sys.exit(64)


event = os.environ["HS_EVENT"]
if event not in SCHEMA:
    near = difflib.get_close_matches(event, SCHEMA, n=1, cutoff=0.6)
    hint = ' (did you mean %s?)' % near[0] if near else ''
    die('unknown event "%s"%s\n  known events: %s'
        % (event, hint, ", ".join(sorted(SCHEMA))))

required, optional = SCHEMA[event]
allowed = required | optional

fields = {}
for raw in sys.argv[1:]:
    if "=" not in raw:
        die('field "%s" is not k=v' % raw)
    k, v = raw.split("=", 1)
    k = k.strip()
    if k in fields:
        die('field "%s" given more than once' % k)
    fields[k] = v

unknown = sorted(set(fields) - allowed)
if unknown:
    die('event=%s unknown field(s): %s\n  allowed: %s'
        % (event, ", ".join(unknown), ", ".join(sorted(allowed))))

backfilled_flag = os.environ["HS_BACKFILLED"] == "1"
effective_required = required
if backfilled_flag:
    effective_required = required - BACKFILL_EXEMPT.get(event, set())
missing = sorted(effective_required - set(fields))
if missing:
    hint = "" if backfilled_flag else (
        "\n  (a --backfilled row may omit: %s)"
        % ", ".join(sorted(BACKFILL_EXEMPT[event])) if event in BACKFILL_EXEMPT else "")
    die("event=%s missing required field(s): %s%s" % (event, ", ".join(missing), hint))

typed = {}
for k, v in fields.items():
    if k in INT:
        try:
            n = int(v)
        except ValueError:
            die('field %s="%s" is not an integer' % (k, v))
        lo_hi = RANGE.get(k)
        if lo_hi and not (lo_hi[0] <= n <= lo_hi[1]):
            die("field %s=%d is outside %d..%d" % (k, n, lo_hi[0], lo_hi[1]))
        typed[k] = n
        continue
    allowed_vals = ENUM.get((event, k))
    if allowed_vals is not None and v not in allowed_vals:
        die('field %s="%s" not in {%s}' % (k, v, ", ".join(sorted(allowed_vals))))
    typed[k] = v

backfilled = backfilled_flag
source = os.environ["HS_BACKFILL_SOURCE"]
if source and not backfilled:
    die("--backfill-source requires --backfilled")
if backfilled and not source:
    die("--backfilled requires --backfill-source <file:line>")

record = {
    "ts": datetime.datetime.now(datetime.timezone.utc)
             .strftime("%Y-%m-%dT%H:%M:%SZ"),
    "event": event,
    "project": os.environ["HS_PROJECT"],
    "tool": "hivesmith-skill",
    "session_id": os.environ["HS_SESSION"] or None,
    "skill": os.environ["HS_SKILL"] or None,
}
record.update(typed)
# Backfilled rows are never mixed into a live statistic. The marker travels
# with the row so the reader cannot lose track of which is which.
if backfilled:
    record["backfilled"] = True
    record["backfill_source"] = source

line = json.dumps(record, ensure_ascii=False, sort_keys=False) + "\n"

if os.environ["HS_DRY_RUN"] == "1":
    sys.stdout.write(line)
    sys.exit(0)

os.makedirs(os.environ["HS_LOG_DIR"], exist_ok=True)
# One O_APPEND write of one line: atomic under PIPE_BUF, so concurrent
# worktrees cannot interleave halves of two events.
fd = os.open(os.environ["HS_LOG"], os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
try:
    os.write(fd, line.encode("utf-8"))
finally:
    os.close(fd)
PY
