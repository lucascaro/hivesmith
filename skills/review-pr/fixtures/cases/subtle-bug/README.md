# `subtle-bug` — the specialist-vs-multiplexed measurement

## Why this case exists

`/review-pr` was changed (commit `add5536`) so the orchestrator reviews the diff
itself against all four dimensions, and dispatched agents became conditional.
That raised a question the fixture suite could not answer:

> Does a **dedicated single-dimension specialist** catch in-diff defects that a
> single reader **multiplexing all four dimensions** misses?

If yes, per-dimension fan-out earns its cost and must stay. If no, the fan-out is
paying for depth it isn't delivering, and the review can collapse to one linear
pass.

The three pre-existing cases cannot settle this. `planted-bugs` plants four
*blatant* defects (SQL injection, hardcoded secret, `range(n + 1)`) that any
reader catches; `clean-refactor` and `tiny-docs` are precision floors with no
defect at all. None of them tests review *depth*.

## The planted defect

`svc/orders.py:46` — the new discount branch returns early without calling
`tx.rollback()`, leaking the open transaction:

```python
code = order.get("discount_code")
if code is not None:
    discounted = apply_discount(db, code, total)
    if discounted is None:
        log.warning("rejected discount code %s", code)
        return {"ok": False, "error": "invalid discount"}   # <-- no tx.rollback()
    total = discounted
```

Every sibling error path in the same function — empty order, missing user, bad
quantity, out of stock, and `cancel_order`'s not-found — calls `tx.rollback()`
first, and the `except` block rolls back too.

Three properties make it subtle, and all three are deliberate:

1. **It is an absence, not a presence.** There is no suspicious line to notice.
   Every line that *is* there is correct.
2. **Attention is divided.** The surrounding diff is ~190 lines of benign churn:
   type hints across four files, structured logging, two extracted helpers, a
   new `svc/discount.py` module, and four new tests.
3. **It only reads as wrong in context.** The branch is locally plausible; it
   violates a convention its four siblings establish elsewhere in the function.

## Method

Both arms are **fresh subagents of the same type** (`Explore`), given the same
diff, the same snapshot tree, and the same output contract. Neither is told what
to look for. They differ in exactly one variable: **checklist breadth.**

| Arm | Prompt |
| --- | --- |
| **A — multiplexed** | All four dimension checklists (correctness, safety, security, performance/UX/consistency), simulating the orchestrator's §1.5 baseline pass |
| **B — specialist** | The correctness checklist only, with "you are the dedicated specialist for ONE dimension, go deep not broad" — simulating `add5536`'s dispatched dimension agent |

Three runs per arm. One sample of an LLM review is noise, and a single lucky
catch would send the design down the wrong branch.

The measurement is deliberately **not** run by the orchestrator that authored
this fixture — whoever planted the bug knows where it is and would "catch" it
from memory rather than from review.

## Decision rule (fixed before the runs, so the result cannot be rationalized)

- **B catches it reliably and A does not** → specialist depth is real. Keep
  per-dimension fan-out as shipped in `add5536`. Do not go linear.
- **Both catch it, or neither does** → the specialist adds nothing measurable.
  Collapse to a linear orchestrator pass, reserving dispatch for heavy
  beyond-diff retrieval only.

## Results

Run 2026-07-18. Six `Explore` subagents, three per arm, none told what to look for.

| Arm | Caught `orders.py:46` | Severity / confidence | Mean tokens |
| --- | --- | --- | --- |
| **A — multiplexed** (all 4 dimensions) | **3 / 3** | BLOCKING, 9/10 in every run | 26,980 |
| **B — specialist** (correctness only) | **3 / 3** | BLOCKING, 9/10 in every run | 25,717 |

Every one of the six runs independently found the missing `tx.rollback()`, all
at the same line, the same severity, and the same confidence. All six reasoned
from the same tell: the sibling error paths roll back and this one does not.

**The multiplexed arm was not merely equal — on this case it was better.** Two
of three arm-A runs also flagged that the discount tests cover only the success
path, and explicitly connected it to the bug ("which is exactly where the
missing rollback lives", "which is why the leak ships green"). That is a
*correctness↔test-hygiene* connection spanning two dimensions. The specialist
arm, confined to correctness, surfaced the coverage gap in only one of three
runs and rated it MINOR. Splitting dimensions across agents does not just fail
to add depth here — it severs links that cross dimension boundaries, and no
downstream dedup step can put them back together.

### Cost

Per-agent cost is near-identical (~26k), but that is the misleading number. One
multiplexed pass covers all four dimensions; the `add5536` shape pays that cost
four times over.

| Shape | Cost |
| --- | --- |
| One multiplexed pass | 26,980 tok |
| Four specialist dispatches | 102,868 tok |
| | **3.8×** |

### Verdict → proceed to linear

Per the decision rule fixed before the runs: **both arms caught it, so the
specialist adds nothing measurable.** The per-dimension fan-out was costing 3.8×
for equal recall and *worse* cross-dimension reasoning.

This retires the hypothesis `add5536` was preserving — that a dedicated
specialist catches subtle in-diff defects an opus-multiplexed baseline misses.
Measured, it does not.

### Caveats, so this is not over-read

- One defect class (missing cleanup on an early-return branch), one language,
  one diff size. It does not prove specialists never help — only that they did
  not help here, on the case built specifically to favor them.
- Both arms ran on the same model tier. `add5536` pinned dimension agents to
  sonnet with security on opus; a sonnet specialist would likely do *worse*
  than these results, not better, which strengthens the conclusion rather than
  weakening it.
- Re-run this case before ever reintroducing per-dimension fan-out.
