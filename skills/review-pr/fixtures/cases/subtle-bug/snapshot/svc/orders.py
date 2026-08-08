"""Order processing."""
import logging
from typing import Any, Optional

from .discount import apply_discount
from .inventory import release, reserve
from .notify import send_confirmation

log = logging.getLogger(__name__)


def _validate(order: dict[str, Any]) -> Optional[str]:
    """Return an error string, or None if the order is well-formed."""
    if not order.get("items"):
        return "empty order"
    if not order.get("user"):
        return "missing user"
    for item in order["items"]:
        if item["qty"] <= 0:
            return "bad quantity"
    return None


def _order_total(items: list[dict[str, Any]]) -> int:
    """Sum the line totals for an order."""
    return sum(item["price"] * item["qty"] for item in items)


def process_order(db, order: dict[str, Any]) -> dict[str, Any]:
    """Validate, price, reserve stock for, and persist an order."""
    tx = db.begin()
    try:
        error = _validate(order)
        if error is not None:
            log.info("rejected order for %s: %s", order.get("user"), error)
            tx.rollback()
            return {"ok": False, "error": error}

        total = _order_total(order["items"])

        code = order.get("discount_code")
        if code is not None:
            discounted = apply_discount(db, code, total)
            if discounted is None:
                log.warning("rejected discount code %s", code)
                return {"ok": False, "error": "invalid discount"}
            total = discounted

        if not reserve(db, order["items"]):
            log.info("out of stock for %s", order["user"])
            tx.rollback()
            return {"ok": False, "error": "out of stock"}

        db.insert("orders", {"user": order["user"], "total": total})
        tx.commit()
        send_confirmation(order["user"], total)
        return {"ok": True, "total": total}
    except Exception:
        tx.rollback()
        raise


def cancel_order(db, order_id: str) -> dict[str, Any]:
    """Release reserved stock and delete the order."""
    tx = db.begin()
    try:
        row = db.get("orders", order_id)
        if row is None:
            log.info("cancel: order %s not found", order_id)
            tx.rollback()
            return {"ok": False, "error": "not found"}
        release(db, row["items"])
        db.delete("orders", order_id)
        tx.commit()
        return {"ok": True}
    except Exception:
        tx.rollback()
        raise
