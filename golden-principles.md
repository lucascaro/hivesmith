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

**Detection:** look for inline helpers (sort comparators, retry loops, throttles, concurrency-limiters) duplicated across more than two files.

**Fix shape:** extract the helper to the shared utilities package, replace call sites, add unit tests for the helper.

---

## 2. Validate at the boundary; never probe shapes inside the system

**Why:** internal code shouldn't carry uncertainty about the shape of its inputs. Probing leads to defensive code paths that mask real bugs.

**Detection:** `if ('field' in x)` checks, ad-hoc `typeof` guards, or optional-chaining cascades on values that came from outside the system.

**Fix shape:** introduce or extend a typed parser at the entry point (Zod / pydantic / equivalent); replace internal probing with the parsed type.

---

## 3. <Add your own>

**Why:** ...

**Detection:** ...

**Fix shape:** ...
