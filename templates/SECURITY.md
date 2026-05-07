# SECURITY.md

Security posture. Trust boundaries, secret handling, and the rules code is expected to follow.

## Trust boundaries

<Where untrusted input enters the system. Each entry should name the validator that gates it.>

- <Boundary> — validated by <module/function>

## Secrets

- <Where secrets live, who can read them, and how they are rotated.>

## Authentication & authorization

<Identity model. Who is allowed to do what. Link to the auth provider integration.>

## Hard rules

- All external input is parsed at the boundary into typed values.
- No secret values appear in logs, error messages, or version control.
- <Project-specific rules>

## Reporting vulnerabilities

See the top-level `SECURITY.md` (project root) for the disclosure process.
