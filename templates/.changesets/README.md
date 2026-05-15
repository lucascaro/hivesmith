# Changesets

Per-PR contribution files that drive `CHANGELOG.md` generation. Each PR with a user-visible change adds **one** file here. A GitHub Action regenerates the `[Unreleased]` section of `CHANGELOG.md` from these files on every push to `main`.

This directory exists so multiple parallel PRs do not conflict on `CHANGELOG.md`.

## File naming

```
.changesets/<NNN>-<slug>.md
```

- `NNN` — zero-padded sequential id. Always allocate `max(existing IDs) + 1` — never reuse an unused slot earlier in the sequence. Monotonic allocation keeps changeset rendering strictly append-only; reusing an earlier slot would re-introduce the merge-conflict pattern this directory is designed to eliminate. The GitHub issue number is fine as the id only when it is larger than every existing changeset id.
- `<slug>` — kebab-case summary, ~3–6 words. Matches the spec slug when there is one.

Example: `.changesets/029-decentralize-indices.md`.

Filenames are the sort key. Within each `### <Type>` section in `CHANGELOG.md`, entries appear strictly in filename order — never re-sorted by content or timestamp — so adding a new changeset always appends and never rewrites existing lines.

## Schema

```markdown
---
issue: 29
pr: 30                    # optional pre-merge; filled when PR opens
type: added | changed | fixed | removed | deprecated | security
bump: major | minor | patch | none
---
- **Headline line.** Body bullets land verbatim under the `### <Type>` heading in `CHANGELOG.md`'s `[Unreleased]` section. Keep the headline imperative and outcome-focused; bullets explain the user-facing change, not the implementation.
```

Required: `issue`, `type`, `bump`. Optional: `pr`.

`type` values follow [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) (lowercase here, capitalized in the rendered section heading).

`bump` is informational — it does not auto-bump VERSION today, but the regenerator records it for the release flow to summarize ("largest bump among unreleased: minor").

## How to add one

When you ship a user-visible change:

1. Create `.changesets/<NNN>-<slug>.md` with the schema above.
2. Commit it on your feature branch.
3. Open the PR. The `verify-generated` CI job will fail if your PR is user-visible but carries no changeset, unless the PR has the `no-changeset` label (use sparingly — docs-only / CI-only changes).

You **never** edit `CHANGELOG.md` directly. CI rejects PRs that touch generated files; the `block-generated-edits` job points reviewers here.

## Release flow

When `scripts/release.sh` runs:

1. The current `[Unreleased]` body is promoted into a new stamped `## [<version>] — <date>` section.
2. All `.changesets/*.md` files are deleted.
3. `[Unreleased]` is regenerated empty until the next post-release changeset lands.

This dir is preserved across releases via `.gitkeep`.
