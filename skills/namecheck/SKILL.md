---
name: namecheck
description: Check whether one or more names are available on npm, the GitHub namespace, and popular TLD domains
argument-hint: [name...] | -f wordlist.txt
allowed-tools: Bash Read
---

# Check name availability

Given one or more candidate names, check if each is free on **npm**, the **GitHub** account namespace (users + orgs share one namespace — the script uses an endpoint that also catches GitHub-reserved / held names, matching what the org-signup form reports), and a configurable set of **TLD domains** (defaults: `com,net,org,io,dev,app,ai`). Backed by `namecheck.sh`, which handles validation, concurrency, retries with backoff, RDAP + WHOIS fallback for domains, and machine-readable output.

## Steps

1. **Verify tooling.** `curl`, `gh`, and `jq` must be on `PATH`, and `gh auth status` must succeed. `whois` is optional but required to check TLDs not in the IANA RDAP bootstrap (notably `.io`) — without it those TLDs will return `error`. If a required tool is missing, report it and stop; `namecheck.sh` exits with code 3.

2. **Gather names.**
   - Names may arrive as `$ARGUMENTS` (space-separated) or via `-f <file>`.
   - If none provided, ask the user what to check and stop.

3. **Run the script.** Invoke `skills/namecheck/namecheck.sh` with the names. The script is the source of truth — do not re-implement its logic.
   - One-off: `./namecheck.sh foo bar baz`
   - From file: `./namecheck.sh -f wordlist.txt`
   - Machine-readable: add `--json` when the caller wants to pipe output into something else.
   - Only winners: add `--only-free` to suppress noise for long lists.
   - Custom TLDs: `--tlds com,dev,xyz` to override the default list. `--no-domains` skips domain checks entirely.

4. **Interpret the exit code.**
   - `0` — every name is fully free on all enabled services (npm, github, and each requested TLD).
   - `1` — at least one name is taken, invalid, or errored. Per-name status is in the table / JSON.
   - `2` — usage error. Fix the invocation.
   - `3` — missing tool or `gh` not authenticated. Tell the user how to fix it.

5. **Summarize.** Highlight the fully-free names (if any) and flag any `error` entries separately — an `error` is *not* the same as `taken` and deserves a retry.

## Rules

- **Do not mark a name "available" on an `error` result.** Transient network or rate-limit failures show up as `error`; re-run the check for those names before claiming anything.
- **Respect the validator.** Names with invalid characters are rejected up front (`^[a-z0-9][a-z0-9_-]*$`). Don't try to work around it — pick a different name.
- **Keep concurrency reasonable.** Default is 6. Raising it past ~15 invites npm/GitHub rate limits; if the user asks for more, warn them.
- **No scraping fallbacks.** The script uses the official npm registry and the authenticated GitHub API only. Do not add HTML-scraping code paths.
