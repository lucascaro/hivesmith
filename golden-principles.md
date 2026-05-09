# Golden principles

Mechanical, opinionated rules that keep this codebase legible and consistent for future agent runs. `gc-sweep` reads this file, scans the code for deviations, and opens small targeted refactor PRs.

Each principle has:

- A short rule.
- A **Why** line — the failure mode it prevents.
- A **Detection** line — how `gc-sweep` (or a human) can find a deviation. Greppable patterns, lint rule names, or a procedure.
- A **Fix shape** line — what the refactor PR should look like (one paragraph, max).

Keep this file short. Five to ten principles is the right size — more becomes wallpaper.

---

## 1. Prefer shared utility packages over hand-rolled helpers

**Why:** invariants stay centralized; one fix propagates everywhere.

**Detection:** three or more near-identical occurrences of the same helper logic anywhere in the tree — within a single file or across files. Targets sort comparators, retry/backoff loops, throttles, concurrency-limiters, ad-hoc parsers. The within-file vs across-file split is about reviewability, not correctness; three copies is the smell.

**Fix shape:** extract the helper to the shared utilities package (or a `lib.sh` for shell), replace call sites, add a unit test for the helper.

---

## 2. Validate at the boundary; never probe shapes inside the system

**Why:** internal code shouldn't carry uncertainty about the shape of its inputs. Probing leads to defensive code paths that mask real bugs.

**Detection:** the same external blob (CLI output, HTTP response, file contents) being parsed at more than one call site instead of once at the entry point. Examples:

- **Shell:** multiple `grep`/`jq`/`awk` passes over the same `gh ... --json`, `git log --format`, or `curl` body — pluck the fields once at the boundary into named bash variables, then pass those variables.
- **TS / Python:** `if ('field' in x)` checks, ad-hoc `typeof` guards, optional-chaining cascades, or `dict.get(...)` chains on values that came from outside the system.

**Fix shape:** introduce or extend a typed parser at the entry point (Zod / pydantic / a single `jq` extraction in shell); replace internal probing with the parsed values.

---

## 3. Shell scripts use strict mode and a consistent shebang

**Why:** silent pipeline failures and unset-variable bugs are the most common shell footgun; an inconsistent shebang causes platform-dependent behavior between Linux CI and macOS dev.

**Detection:** every `*.sh` file (excluding fixture snapshots under `skills/*/fixtures/`) must have `#!/usr/bin/env bash` as its first line and `set -euo pipefail` somewhere in the first five lines. Grep: `head -5 path/to/script.sh`.

**Fix shape:** prepend the shebang and `set -euo pipefail`; verify the script still passes `bash -n` and the project's shellcheck command from `AGENTS.md`.

---

## 4. SKILL.md frontmatter is complete for the skill's class

**Why:** the harness loads skills from frontmatter. Missing keys produce surprising runtime behavior — a skill silently model-invocable when it shouldn't be, no argument hint shown to the user, no tool restriction applied.

**Detection:** parse YAML frontmatter from each `skills/*/SKILL.md`. Required everywhere: `name`, `description`. Required for pipeline skills (`skills/feature-*/SKILL.md`): `disable-model-invocation: true`. Required when the skill accepts arguments: `argument-hint`. Recommended (warn, don't block): `allowed-tools`.

**Fix shape:** add the missing key with a value cribbed from the closest sibling skill of the same class. Do not invent semantics — if no sibling has the key, escalate to a human.

---

## 5. Source SKILL.md files use bare slash-command names; no rendered prefix in source

**Why:** `install.sh` rewrites `/skill-name` → `/<prefix>skill-name` at render time so the same source supports both prefixed and unprefixed installs. A hardcoded `/hs-foo` in source breaks the unprefixed install path and double-prefixes the prefixed path.

**Detection:** `grep -rn '/hs-[a-z]' skills/ templates/` should return zero hits. The rendered tree (`.rendered/`) is gitignored and is not in scope.

**Fix shape:** replace `/hs-foo` with `/foo`. If the reference is genuinely to an external (non-hivesmith) command that happens to start with `hs-`, leave it and add a one-line comment explaining why the rewrite shouldn't apply.

---

## 6. Every shell script in the tree is linted by both CI and AGENTS.md

**Why:** lint coverage drift is how style erodes silently. CI's shellcheck job and the `Lint:` command in `AGENTS.md` must agree, and both must cover every script.

**Detection:** take the set `S = find . -type f -name '*.sh' -not -path './.git/*' -not -path './.worktrees/*' -not -path './.rendered/*' -not -path './skills/*/fixtures/*'`. The `additional_files` list in `.github/workflows/ci.yml` (shellcheck job) must equal `S`. The script list in the `Lint:` line of `AGENTS.md` must also equal `S`. Any diff is a deviation.

**Fix shape:** add the missing scripts to both lists in a single PR. Never resolve drift by *removing* a script from one list to match the other.
