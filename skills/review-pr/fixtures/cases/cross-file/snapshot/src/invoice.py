"""Invoice rendering."""

from .pricing import line_total


def render_line(item) -> str:
    """One formatted invoice line."""
    total = line_total(item["price"], item["qty"])
    return f"{item['name']}: {total:.2f}"


def render(items) -> str:
    """Render every line of an invoice."""
    return "\n".join(render_line(i) for i in items)
