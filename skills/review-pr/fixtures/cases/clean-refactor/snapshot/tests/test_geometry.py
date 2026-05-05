import math
import pytest
from src.geometry import circle_area, rectangle_area, triangle_area


def test_circle_area():
    assert circle_area(2) == pytest.approx(math.pi * 4)


def test_circle_area_zero():
    assert circle_area(0) == 0


def test_circle_area_negative():
    with pytest.raises(ValueError):
        circle_area(-1)


def test_rectangle_area():
    assert rectangle_area(3, 4) == 12


def test_rectangle_area_negative():
    with pytest.raises(ValueError):
        rectangle_area(-1, 2)


def test_triangle_area():
    assert triangle_area(4, 5) == 10


def test_triangle_area_negative():
    with pytest.raises(ValueError):
        triangle_area(-1, 2)
