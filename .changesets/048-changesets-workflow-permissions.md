---
type: fixed
bump: patch
---
- **Scaffolded `changesets.yml` limits `GITHUB_TOKEN` permissions** — CodeQL flags `block-generated-edits` and `verify-generated` for running with the default token, so every project scaffolded from the template inherited the alert. The workflow now declares a top-level `permissions: contents: read`; `regenerate-generated` keeps its job-level `contents: write`.
