#!/usr/bin/env bash
# namecheck — check whether a name is free on npm, the GitHub account
# namespace (users + orgs + reserved/held names), and popular TLDs.
#
# Usage:
#   namecheck.sh NAME [NAME...]
#   namecheck.sh -f wordlist.txt
#   namecheck.sh --json NAME ...
#
# Options:
#   -f, --file FILE       Read names from FILE (one per line, # comments allowed)
#   -c, --concurrency N   Parallel name workers (default: 6); each fans out internally
#   -r, --retries N       Retries per network call (default: 2)
#       --tlds LIST       Comma-separated TLDs to check (default: com,net,org,io,dev,app,ai)
#       --no-domains      Skip domain checks entirely
#       --json            Emit a single JSON array instead of the pretty output
#       --only-free       Print only names that are fully free
#   -h, --help            Show this help
#
# A name is "fully free" when it is free on every enabled service (npm,
# github, and each requested TLD). The GitHub check uses
# `GET /users/NAME/events`, which returns 200 for any claimed login —
# including names that are reserved or held by GitHub — and 404 only when
# the name is truly unclaimed, matching what the org-signup form reports.
# Domain availability uses RDAP (https://data.iana.org/rdap/dns.json),
# cached locally for 7 days, with a `whois` fallback for TLDs not in the
# bootstrap (notably .io). Unknown or unreachable registries return `error`,
# which is never treated as "free".
#
# Exit codes: 0 all fully free, 1 at least one taken/invalid/errored,
#             2 usage error, 3 tooling error (missing curl/gh/jq, or
#             gh not authenticated).
set -euo pipefail

die()  { printf 'error: %s\n' "$*" >&2; exit 2; }
need() { command -v "$1" >/dev/null 2>&1 || { printf 'error: %s not found on PATH\n' "$1" >&2; exit 3; }; }

usage() { sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; }

# ---------- arg parsing ----------
FILE=""
CONCURRENCY=6
RETRIES=2
JSON=0
ONLY_FREE=0
CHECK_DOMAINS=1
TLDS_CSV="com,net,org,io,dev,app,ai"
NAMES=()

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -f|--file) FILE="${2:-}"; [ -n "$FILE" ] || die "--file needs a path"; shift 2 ;;
    -c|--concurrency) CONCURRENCY="${2:-}"; shift 2 ;;
    -r|--retries) RETRIES="${2:-}"; shift 2 ;;
    --tlds) TLDS_CSV="${2:-}"; [ -n "$TLDS_CSV" ] || die "--tlds needs a value"; shift 2 ;;
    --no-domains) CHECK_DOMAINS=0; shift ;;
    --json) JSON=1; shift ;;
    --only-free) ONLY_FREE=1; shift ;;
    --) shift; NAMES+=("$@"); break ;;
    -*) die "unknown option: $1" ;;
    *) NAMES+=("$1"); shift ;;
  esac
done

[[ "$CONCURRENCY" =~ ^[0-9]+$ ]] && [ "$CONCURRENCY" -ge 1 ] || die "--concurrency must be a positive integer"
[[ "$RETRIES" =~ ^[0-9]+$ ]] || die "--retries must be a non-negative integer"

if [ -n "$FILE" ]; then
  [ -r "$FILE" ] || die "cannot read file: $FILE"
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | tr -d '[:space:]')"
    [ -n "$line" ] && NAMES+=("$line")
  done < "$FILE"
fi

[ "${#NAMES[@]}" -gt 0 ] || { usage; exit 2; }

need curl
need gh
need jq
gh auth status >/dev/null 2>&1 || { printf 'error: gh is not authenticated — run `gh auth login`\n' >&2; exit 3; }

# Parse + validate TLDs once. Empty list + --no-domains == skip.
TLDS=()
if [ "$CHECK_DOMAINS" -eq 1 ]; then
  IFS=',' read -r -a TLDS <<<"$TLDS_CSV"
  for t in "${TLDS[@]}"; do
    [[ "$t" =~ ^[a-z0-9]+(\.[a-z0-9]+)?$ ]] || die "invalid TLD in --tlds: $t"
  done
fi

# ---------- RDAP bootstrap (IANA) ----------
# Cache the bootstrap file for 7 days. Used to resolve TLD → RDAP base URL.
RDAP_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hivesmith/rdap-dns.json"
RDAP_BOOTSTRAP_URL='https://data.iana.org/rdap/dns.json'

rdap_bootstrap_fetch() {
  mkdir -p "$(dirname "$RDAP_CACHE")"
  local needs_refresh=1
  if [ -f "$RDAP_CACHE" ] && [ -z "$(find "$RDAP_CACHE" -mtime +7 2>/dev/null)" ]; then
    needs_refresh=0
  fi
  if [ "$needs_refresh" -eq 1 ]; then
    if ! curl -sS --max-time 10 -A 'hivesmith-namecheck/1.0' \
         -o "$RDAP_CACHE.tmp" "$RDAP_BOOTSTRAP_URL" 2>/dev/null; then
      rm -f "$RDAP_CACHE.tmp"
      # If we have a stale cache, use it. Otherwise domain checks will fail.
      [ -f "$RDAP_CACHE" ] || return 1
      return 0
    fi
    mv "$RDAP_CACHE.tmp" "$RDAP_CACHE"
  fi
}

rdap_base_for_tld() {
  local tld="$1"
  [ -s "$RDAP_CACHE" ] || return 1
  jq -r --arg t "$tld" '
    .services
    | map(select(.[0] | index($t)))
    | .[0][1][0] // empty
  ' "$RDAP_CACHE" 2>/dev/null
}

if [ "$CHECK_DOMAINS" -eq 1 ]; then
  rdap_bootstrap_fetch || printf 'warning: could not fetch RDAP bootstrap; domain checks will error\n' >&2
fi

# ---------- worker ----------
# Emits one JSON object per name on stdout (one per line).
check_one() {
  local name="$1"
  local normalized
  normalized="$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]')"

  if ! [[ "$normalized" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
    jq -cn --arg name "$normalized" \
      '{name:$name, ok:false, invalid:true, reason:"invalid characters"}'
    return
  fi

  local work pids=()
  work="$(mktemp -d -t namecheck-one.XXXXXX)"

  check_npm    "$normalized" >"$work/npm"    & pids+=($!)
  check_github "$normalized" >"$work/github" & pids+=($!)

  if [ "$CHECK_DOMAINS" -eq 1 ]; then
    for tld in $TLDS_SPACE; do
      if [[ ! "$normalized" =~ ^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$ ]]; then
        printf 'invalid' >"$work/d_$tld"
      else
        check_domain "$normalized" "$tld" >"$work/d_$tld" & pids+=($!)
      fi
    done
  fi

  local pid; for pid in "${pids[@]}"; do wait "$pid" || true; done

  local npm github
  npm="$(<"$work/npm")"
  github="$(<"$work/github")"

  local domains_json='{}'
  if [ "$CHECK_DOMAINS" -eq 1 ]; then
    domains_json="$(
      for tld in $TLDS_SPACE; do
        printf '%s\t%s\n' "$tld" "$(<"$work/d_$tld")"
      done \
      | jq -Rs 'split("\n") | map(select(length>0) | split("\t") | {key:.[0], value:.[1]}) | from_entries'
    )"
  fi

  rm -rf "$work"

  jq -cn \
    --arg    name     "$normalized" \
    --arg    npm      "$npm" \
    --arg    github   "$github" \
    --argjson domains "$domains_json" \
    '{
       name:     $name,
       invalid:  false,
       services: {npm:$npm, github:$github},
       domains:  $domains,
       ok:       (
         ([$npm,$github] | all(. == "free"))
         and ($domains | to_entries | all(.value == "free"))
       )
     }'
}

# Returns one of: free | taken | error
check_npm() {
  local name="$1" attempt=0 code
  while : ; do
    code="$(curl -sS -o /dev/null -w '%{http_code}' \
              --max-time 9 \
              -A 'hivesmith-namecheck/1.0' \
              "https://registry.npmjs.org/$(jq -rn --arg s "$name" '$s|@uri')" \
              || true)"
    case "$code" in
      200) printf 'taken'; return ;;
      404) printf 'free';  return ;;
    esac
    attempt=$((attempt + 1))
    [ "$attempt" -gt "$RETRIES" ] && { printf 'error'; return; }
    sleep "$(awk -v a="$attempt" 'BEGIN{srand(); printf "%.2f", 0.3*(2^a) + rand()*0.4}')"
  done
}

# Returns one of: free | taken | error.
#
# `GET /users/NAME/events` is the authoritative GitHub namespace availability
# signal. Unlike `/users/NAME` or `/orgs/NAME`, it returns 200 for any claimed
# name — public users, public orgs, *and* names that are reserved or held by
# GitHub (e.g. after an org deletion, or globally reserved logins like
# `pingwatch`). It returns 404 only when the login is truly unclaimed, which
# matches what the `github.com/account/organizations/new` signup form reports.
check_github() {
  local name="$1" attempt=0 out rc
  while : ; do
    out="$(gh api "users/$name/events" 2>&1)"; rc=$?
    if [ "$rc" -eq 0 ]; then printf 'taken'; return; fi
    printf '%s' "$out" | grep -q 'HTTP 404' && { printf 'free'; return; }
    attempt=$((attempt + 1))
    [ "$attempt" -gt "$RETRIES" ] && { printf 'error'; return; }
    sleep "$(awk -v a="$attempt" 'BEGIN{srand(); printf "%.2f", 0.4*(2^a) + rand()*0.5}')"
  done
}

# Returns one of: free | taken | error
# Tries RDAP first; falls back to `whois` for TLDs not in the IANA RDAP
# bootstrap (notably .io). If both paths fail, returns "error".
check_domain() {
  local name="$1" tld="$2" attempt=0 base code
  base="$(rdap_base_for_tld "$tld")"
  if [ -n "$base" ]; then
    base="${base%/}"
    while : ; do
      code="$(curl -sS -o /dev/null -w '%{http_code}' \
                --max-time 9 \
                -H 'Accept: application/rdap+json' \
                -A 'hivesmith-namecheck/1.0' \
                "$base/domain/$name.$tld" \
                || true)"
      case "$code" in
        200)    printf 'taken'; return ;;
        404)    printf 'free';  return ;;
        429|5*) : ;;  # retry
      esac
      attempt=$((attempt + 1))
      [ "$attempt" -gt "$RETRIES" ] && break
      sleep "$(awk -v a="$attempt" 'BEGIN{srand(); printf "%.2f", 0.5*(2^a) + rand()*0.5}')"
    done
    printf 'error'; return
  fi
  check_domain_whois "$name" "$tld"
}

# WHOIS fallback for TLDs without RDAP. Output format varies per registry;
# we match a small set of well-known phrases. Returns: free | taken | error.
check_domain_whois() {
  local name="$1" tld="$2" attempt=0 out
  command -v whois >/dev/null 2>&1 || { printf 'error'; return; }
  while : ; do
    out="$(whois "$name.$tld" 2>/dev/null || true)"
    if [ -n "$out" ]; then
      if printf '%s' "$out" | grep -qiE '(no match|not found|no entries found|no data found|available for registration|^Domain not found|status: *free)'; then
        printf 'free'; return
      fi
      if printf '%s' "$out" | grep -qiE '(creation date|registry domain id|registrar:|registrant[:[:space:]]|^domain name:|^registered on:)'; then
        printf 'taken'; return
      fi
    fi
    attempt=$((attempt + 1))
    [ "$attempt" -gt "$RETRIES" ] && { printf 'error'; return; }
    sleep "$(awk -v a="$attempt" 'BEGIN{srand(); printf "%.2f", 0.5*(2^a) + rand()*0.5}')"
  done
}

# Flatten TLDS array into a space-separated string for the exported env, so
# subshells spawned by xargs can read it without re-parsing the CSV.
TLDS_SPACE="${TLDS[*]:-}"

export -f check_one check_npm check_github check_domain check_domain_whois rdap_base_for_tld
export RETRIES CHECK_DOMAINS TLDS_SPACE RDAP_CACHE

# ---------- fan out ----------
RESULTS="$(mktemp -t namecheck.XXXXXX)"
trap 'rm -f "$RESULTS"' EXIT

printf '%s\n' "${NAMES[@]}" \
  | xargs -I{} -P "$CONCURRENCY" -n 1 bash -c 'check_one "$@"' _ {} \
  > "$RESULTS"

# ---------- output ----------
if [ "$JSON" -eq 1 ]; then
  jq -s '.' "$RESULTS"
else
  # Single-row-per-name table. Columns: NAME, service columns, one column per
  # configured TLD (header shown as ".tld"), STATUS.
  SVC_LABELS=(npm github)
  SVC_KEYS=(npm github)
  DOM_HEADERS=()
  if [ "$CHECK_DOMAINS" -eq 1 ]; then
    for t in "${TLDS[@]}"; do DOM_HEADERS+=(".$t"); done
  fi

  # Build a format string: name col is 28, every other value col is 7.
  fmt='%-28s'
  for _ in "${SVC_LABELS[@]}";  do fmt+=' %-7s'; done
  for _ in ${DOM_HEADERS[@]+"${DOM_HEADERS[@]}"}; do fmt+=' %-7s'; done
  fmt+=' %s\n'

  # Header row.
  # shellcheck disable=SC2059  # fmt is built above from known, safe pieces
  printf "$fmt" NAME "${SVC_LABELS[@]}" ${DOM_HEADERS[@]+"${DOM_HEADERS[@]}"} STATUS
  sep_cells=(----)
  for _ in "${SVC_LABELS[@]}";  do sep_cells+=(-------); done
  for _ in ${DOM_HEADERS[@]+"${DOM_HEADERS[@]}"}; do sep_cells+=(-------); done
  # shellcheck disable=SC2059
  printf "$fmt" "${sep_cells[@]}" ------

  while IFS= read -r line; do
    name="$(jq -r '.name' <<<"$line")"
    if [ "$(jq -r '.invalid' <<<"$line")" = "true" ]; then
      [ "$ONLY_FREE" -eq 1 ] && continue
      printf '%-28s %s\n' "$name" "✗ invalid ($(jq -r '.reason' <<<"$line"))"
      continue
    fi
    ok="$(jq -r '.ok' <<<"$line")"
    [ "$ONLY_FREE" -eq 1 ] && [ "$ok" != "true" ] && continue

    row=("$name")
    for k in "${SVC_KEYS[@]}"; do
      row+=("$(jq -r --arg k "$k" '.services[$k]' <<<"$line")")
    done
    if [ "$CHECK_DOMAINS" -eq 1 ]; then
      for t in ${TLDS[@]+"${TLDS[@]}"}; do
        row+=("$(jq -r --arg k "$t" '.domains[$k] // "-"' <<<"$line")")
      done
    fi
    status=$([ "$ok" = "true" ] && echo "✅ free" || echo "❌ taken/error")
    row+=("$status")
    # shellcheck disable=SC2059
    printf "$fmt" "${row[@]}"
  done < "$RESULTS"
fi

# ---------- exit code ----------
if jq -e 'any(.ok == false)' <(jq -s '.' "$RESULTS") >/dev/null; then
  exit 1
fi
exit 0
