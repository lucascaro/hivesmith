---
name: release
description: Cut a release — pre-flight checks, version bump suggestion, run scripts/release.sh
argument-hint: [version]
allowed-tools: Read Bash
---

# Cut a release

Walk through the release process end to end. The heavy lifting (version bump, CHANGELOG stamping, tagging, GitHub release) is done by `scripts/release.sh`; this skill owns the pre-flight and the version-bump decision.

## Steps

1. **Verify tooling.**
   - `scripts/release.sh` exists and is executable. If missing, tell the user to run `/hivesmith-init` and stop.
   - `gh` CLI is installed and authenticated.

2. **Pre-flight checks.** All must pass before continuing:
   - Current branch is `main` (or the project's release branch — check `AGENTS.md` if unsure).
   - Working tree is clean (`git status --porcelain` empty).
   - Local `main` is in sync with `origin/main`.
   - `CHANGELOG.md` has a `## [Unreleased]` section with at least one bullet under it.
   - Latest CI on `origin/main` is green (`gh run list --branch main --limit 1`).

   If any check fails, report which and stop.

3. **Determine the version.**
   - If `$ARGUMENTS` supplies a version (e.g. `0.3.1`), use it.
   - Otherwise read `[Unreleased]` contents and suggest a bump based on the latest tag (`git tag -l 'v*' --sort=-v:refname | head -1`):
     - Any `### Removed` or breaking `### Changed` entries → **major** bump.
     - Any `### Added` entries → **minor** bump.
     - Only `### Fixed` / `### Security` → **patch** bump.
   - Show the suggestion with the rationale and confirm with the user before proceeding.

4. **Show the release notes preview.** Print the `[Unreleased]` body verbatim — this is what the GitHub release will display.

5. **Run `scripts/release.sh <version>`.** It will:
   - Bump the version in the configured `VERSION_FILE`
   - Stamp `[Unreleased]` with the date
   - Rewrite compare links
   - Commit, tag, (optionally cross-compile), push, and create a GitHub release

6. **Post-release verification.**
   - `gh release view v<version>` shows the expected notes and artifacts.
   - `git describe --tags` on `main` matches the new tag.
   - Report the release URL back to the user.

## Rules

- **Never bypass failed pre-flight checks.** If CI is red or the tree is dirty, stop — the user can override by running `scripts/release.sh` directly if they know what they're doing.
- **Never force-push or re-tag an existing version.** If the tag exists, stop and ask.
- **Do not edit `CHANGELOG.md` here** — `release.sh` handles the stamp. Use `/changelog-update` earlier if entries are missing.
- **One release at a time.** If a previous release commit is unpushed, resolve that first.
