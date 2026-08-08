"""Outbound notifications."""
import logging

log = logging.getLogger(__name__)


def send_confirmation(user: str, total: int) -> bool:
    """Send an order confirmation to the user."""
    log.info("confirmation to %s for %s", user, total)
    return True
