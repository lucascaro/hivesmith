"""Inventory reservation."""
import logging
from typing import Any

log = logging.getLogger(__name__)


def reserve(db, items: list[dict[str, Any]]) -> bool:
    """Reserve stock for every line, or nothing at all."""
    for item in items:
        stock = db.get("stock", item["sku"])
        if stock is None or stock["qty"] < item["qty"]:
            log.info("insufficient stock for %s", item["sku"])
            return False
    for item in items:
        db.decrement("stock", item["sku"], item["qty"])
    return True


def release(db, items: list[dict[str, Any]]) -> None:
    """Return reserved stock to the pool."""
    for item in items:
        db.increment("stock", item["sku"], item["qty"])
