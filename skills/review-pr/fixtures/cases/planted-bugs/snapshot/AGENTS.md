# Agent guide

## Module map

- `app/db.py` — database access. All queries go through here.

## Conventions

- Parameterize all SQL. String concatenation into queries is forbidden.
- No secrets in source. Read tokens from env: `os.environ["BILLING_API_TOKEN"]`.
- Module-level mutable state must be protected by `threading.Lock` if touched from request handlers.
