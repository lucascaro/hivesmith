from svc.orders import _order_total, _validate, process_order


def test_empty_order(db):
    assert process_order(db, {"items": [], "user": "u1"})["ok"] is False


def test_bad_quantity(db):
    order = {"items": [{"sku": "a", "qty": 0, "price": 5}], "user": "u1"}
    assert process_order(db, order)["ok"] is False


def test_missing_user(db):
    order = {"items": [{"sku": "a", "qty": 1, "price": 5}], "user": ""}
    assert process_order(db, order)["error"] == "missing user"


def test_validate_accepts_good_order():
    assert _validate({"items": [{"qty": 1}], "user": "u1"}) is None


def test_order_total():
    assert _order_total([{"price": 5, "qty": 2}, {"price": 3, "qty": 1}]) == 13


def test_happy_path(db):
    order = {"items": [{"sku": "a", "qty": 2, "price": 5}], "user": "u1"}
    assert process_order(db, order) == {"ok": True, "total": 10}


def test_discount_applied(db):
    db.put("discounts", "SAVE10", {"percent": 10})
    order = {"items": [{"sku": "a", "qty": 2, "price": 5}], "user": "u1",
             "discount_code": "SAVE10"}
    assert process_order(db, order) == {"ok": True, "total": 9}
