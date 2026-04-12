# Contributing to hivesmith

Thanks for your interest in improving hivesmith. This guide covers local development, skill authoring conventions, and the PR process. By contributing, you agree that your contributions are licensed under the MIT license (see [LICENSE](./LICENSE)) and that you abide by the [Code of Conduct](./CODE_OF_CONDUCT.md).

Security issues: don't open a public issue — see [SECURITY.md](./SECURITY.md) for private reporting.

## Local development

Clone the repo somewhere you don't mind hacking on:

```bash
git clone https://github.com/lucascaro/hivesmith ~/work/hivesmith
```

Point hivesmith at your working copy by setting the env var (or symlinking):

```bash
export HIVESMITH_DIR=~/work/hivesmith
# or: ln -s ~/work/hivesmith ~/.hivesmith
```

### Testing `install.sh` in isolation

Don't test against your real `$HOME` — use a throwaway one so you can repeat freely:

```bash
TEST_HOME="$(mktemp -d)"
mkdir -p "$TEST_HOME/.claude/skills"
HOME="$TEST_HOME" HIVESMITH_DIR_CONFIG="$TEST_HOME/hivesmith.toml" \
  ~/work/hivesmith/install.sh --prefix hs- --no-auto-update
ls "$TEST_HOME/.claude/skills"
```

Clean up with `rm -rf "$TEST_HOME"`.

The installer supports `--dry-run` for previewing actions without touching anything.

## Skill authoring

Each skill lives under `skills/<name>/` with a `SKILL.md` file. The installer auto-discovers every directory — no central registry.

### SKILL.md frontmatter

```yaml
---
name: feature-plan                              # must match directory name
description: One-sentence summary for Claude    # shown in skill autocomplete
argument-hint: [issue-number]                   # optional; shown after /name
allowed-tools: Read Glob Grep Edit Bash Agent   # space-separated tool names
disable-model-invocation: true                  # optional; skill is user-invoked only
---
```

### Cross-skill references

When one skill refers to another in its body, use the `/skill-name` slash-command form:

```markdown
…remind the user to run `/feature-plan <number>` next.
```

This matters because the installer's `--prefix` mode rewrites `/skill-name` references automatically so the pipeline still works under a prefix. Plain skill names, paths (`scripts/release.sh`), and path-like segments (`some/release`) are left alone.

### Scripts

Shell scripts (installer, `ingest.sh`, scaffolded `release.sh`) must pass `shellcheck` on the default ruleset. CI enforces this.

## Pull requests

1. Fork, branch from `main`.
2. Make the change. Add a `[Unreleased]` entry to `CHANGELOG.md` (the `/changelog-update` skill does this for you).
3. Verify:
   - `shellcheck install.sh` is clean.
   - `install.sh` works with and without `--prefix`, `--update`, `--uninstall` (use the isolated-`HOME` pattern above).
4. Open the PR. CI must pass before review.
5. Reviews use the `/review-pr` skill or manual review — no strict requirement on which.
6. Squash-merge or rebase-merge. `main` is protected with linear history.

## Commit style

Conventional-ish, informal: `fix:`, `feat:`, `docs:`, `ci:`, `refactor:`, `chore:`. Reference issues with `Fixes #N` when applicable. The subject line is what shows up in `git log --oneline`; write it so it makes sense to someone skimming the history a year from now.
