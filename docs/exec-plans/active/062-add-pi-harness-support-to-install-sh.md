# Add pi harness support to install.sh

- **Spec:** [docs/product-specs/062-add-pi-harness-support-to-install-sh.md](../../product-specs/062-add-pi-harness-support-to-install-sh.md)
- **Issue:** #62
- **Status:** active
- **PR:** #63
- **Branch:** `feature/62-add-pi-harness-support-to-install-sh`

<!--
Stage is **not** carried here. The spec's YAML frontmatter `stage:` is the
sole source of truth. Skills read and write stage from the spec — never from
this file or from the generated `docs/product-specs/index.md`.
-->

## Summary

Register the pi coding agent in `agents.json` so `install.sh` fans skills into it like every other harness. pi's global and project skill directories are not the same shape, so the registry schema gains one optional key (`local_skills_dir`) that only pi declares.

## Research

Authored via plan-first mode; findings gathered during plan-mode iteration.

**Relevant code**

- `install.sh:330-357` — registry load. `agents.json` is parsed by a python3 one-liner that joins `name`, `skills_dir`, `agents_dir`, `detect_dir` with `\x1f` (US). The US separator (not tab) exists specifically so empty optional fields survive `read`.
- `install.sh:360-365` — `scope_path()`. Local scope is derived mechanically: strip `~/`, prepend `$PWD`. This is the assumption pi breaks.
- `install.sh:429-448` — `build_targets()`. Resolves `skills_dir` / `agents_dir` per scope into `TARGETS` / `AGENT_TARGETS`. Everything downstream (status, doctor, uninstall, ownership sweep) derives from those two arrays.
- `install.sh:380-387` — `detected_local_agents()` uses `detect_dir` through the same `scope_path`; `~/.pi` → `./.pi` is correct in both scopes, so no override is needed there.
- `scripts/telemetry/install-pi.sh:26,33` — existing precedent for pi's path asymmetry: `$HOME/.pi/agent/extensions` global vs `./.pi/extensions` local.
- `agents.json` — `agents_dir` is already an optional key declared only by `claude`, which is the precedent this change copies.

**Constraints**

- pi's documented skill locations (installed pi 0.84.4, `docs/skills.md`): global `~/.pi/agent/skills/` and `~/.agents/skills/`; project `.pi/skills/` and `.agents/skills/`, the project ones loaded only after the project is trusted.
- pi implements the Agent Skills standard and discovers directories containing `SKILL.md` recursively — hivesmith skills need no format change.
- `install.sh` has no unit-test harness. Coverage is shellcheck plus real installs in CI (`install-smoke`, `render-correctness`, `subagent-linking` jobs).
- Bash 3.2 compatibility is the repo norm for shell scripts.

## Approach

Add an **optional `local_skills_dir`** key to the `agents.json` registry. `build_targets()` uses it in place of `skills_dir` when the scope is local and the value is non-empty. pi is the only entry that sets it; every other harness takes the existing code path unchanged.

Chosen over the obvious alternative — special-casing pi inside `install.sh` — because `agents.json` is the source of truth for harness layout, and a hardcoded name in generic fan-out code would need a second special case for the next divergent harness. It mirrors the precedent already in the file: `agents_dir` is optional and only `claude` declares one.

Also rejected: registering pi at its harness-agnostic `~/.agents/skills/` location. That would need no schema change, but the directory is shared with other tools (making the uninstall ownership sweep riskier) and gives no usable `detect_dir` — its presence would not mean pi is installed.

The `local_skills_dir` value keeps the `~/` prefix (`~/.pi/skills`) so `scope_path` strips it uniformly for every field; no second path convention is introduced.

### Files to change

- `agents.json` — new `pi` entry: `skills_dir: ~/.pi/agent/skills`, `local_skills_dir: ~/.pi/skills`, `detect_dir: ~/.pi`. No `agents_dir`.
- `install.sh` — registry record grows a fifth field:
  - python emitter (~line 341): add `a.get('local_skills_dir', '')` to the `\x1f` join.
  - record-layout comment (~line 336) and US-separator comment (~line 331): document the new field.
  - `build_targets()` (~line 430): read the extra field; when `scope == local` and it is non-empty, resolve it instead of `skills_raw`.
- `README.md` (~line 99) — add `~/.pi/agent/skills/` to the fan-out list; note that pi's local target is `./.pi/skills` (not `./.pi/agent/skills`) and that pi loads project skills only after the project is trusted.
- `tests/manual/installer-smoke.md` — extend step 11 (multi-harness detection) to include pi, plus a bullet asserting the local path.
- `AGENTS.md` — add the new test script to the shellcheck file list and to the build/test command block.
- `.github/workflows/ci.yml` — add the new script to the `shellcheck` job's file list, and a job that runs it (shape copied from `brain-tests`).
- `.changesets/062-add-pi-harness-to-installer.md` — user-visible change; the CI changelog gate requires an entry.

### New files

- `tests/install-agent-scopes-test.sh` — real (non-dry-run) install into a scratch `HOME` and scratch project; the one runnable check for this change.

### Tests

`install.sh` has no unit harness; the new test follows the repo's existing style (real install into a scratch environment) rather than introducing a framework. Four assertions in `tests/install-agent-scopes-test.sh`:

1. `local_target_uses_override` — `install.sh --local --agents pi` creates symlinks under `./.pi/skills/` and `./.pi/agent/` does **not** exist. This is the regression the change exists to prevent.
2. `global_target_uses_skills_dir` — with `$HOME/.pi` present, `--global` populates `$HOME/.pi/agent/skills/` with the same non-zero count as `ls skills | wc -l`.
3. `override_absent_is_unchanged` — the same local install for `claude` still lands in `./.claude/skills/`, proving the new branch is inert without the key.
4. `local_uninstall_sweeps_override_dir` — `--uninstall --local --agents pi` removes every link under `./.pi/skills/`.

## Verification

```bash
# Lint (new file appended to the AGENTS.md list)
shellcheck install.sh tests/install-agent-scopes-test.sh

# The new suite
bash tests/install-agent-scopes-test.sh

# Existing install smoke, both prefixes
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix hs- --no-auto-update --dry-run
HOME=$(mktemp -d) && mkdir -p "$HOME/.claude" && ./install.sh --prefix "" --no-auto-update --dry-run

# Changelog gate
awk '/^## \[Unreleased\]/{f=1;next} f&&/^## \[/{exit} f' CHANGELOG.md | grep -q .
```

## Decision log

- **2026-09-01** — Add an optional `local_skills_dir` registry key rather than special-casing pi in `install.sh`. Why: `agents.json` is the source of truth for harness layout; a hardcoded harness name in generic code would need repeating for the next divergent harness.
- **2026-09-01** — Do not declare an `agents_dir` for pi. Why: pi core ships no subagent directory; subagents come from the optional `pi-subagents` package.

## Progress

- **2026-09-01** — Plan-first scaffold; stage = IMPLEMENT (set in spec frontmatter).
- **2026-09-01** — PR #63 opened; review loop converged in 2 iterations (one safe fix: test sandbox isolation). Stage = GATE.

## Open questions

- pi's dedup behavior across skill roots is undocumented: users who already point pi's `settings.json` `skills` array at `~/.claude/skills` will have hivesmith skills discovered twice after this ships. Mitigated with a README note, not code.

## PR convergence ledger

- **2026-09-01 iter 1** — verdict: REQUEST_CHANGES; mergeable: MERGEABLE; findings_hash: 88be3bbd; threads_open: 0; action: autofix+push; head_sha: 815b30b.
- **2026-09-01 iter 2** — verdict: APPROVE; mergeable: MERGEABLE; findings_hash: empty; threads_open: 0; action: stop; head_sha: 815b30b.

## Gate verdict
