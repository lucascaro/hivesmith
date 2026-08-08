"""Discount code resolution."""
import logging
from typing import Any, Optional

log = logging.getLogger(__name__)


def apply_discount(db, code: str, total: int) -> Optional[int]:
    """Apply a discount code to a total.

    Returns the discounted total, or None if the code is unknown or expired.
    """
    row = db.get("discounts", code)
    if row is None:
        return None
    if row.get("expired"):
        return None
    pct = row["percent"]
    if pct < 0 or pct > 100:
        log.error("discount %s has out-of-range percent %s", code, pct)
        return None
    return int(total * (100 - pct) / 100)
