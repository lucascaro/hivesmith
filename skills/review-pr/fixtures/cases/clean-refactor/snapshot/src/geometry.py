"""Geometry helpers."""
import math


def circle_area(radius: float) -> float:
    if radius < 0:
        raise ValueError("radius must be non-negative")
    return math.pi * radius * radius


def rectangle_area(width: float, height: float) -> float:
    if width < 0 or height < 0:
        raise ValueError("dimensions must be non-negative")
    return width * height


def triangle_area(base: float, height: float) -> float:
    if base < 0 or height < 0:
        raise ValueError("dimensions must be non-negative")
    return 0.5 * base * height
