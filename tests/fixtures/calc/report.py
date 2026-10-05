"""Formats an order summary from calc's results."""
from calc import apply_discount, total


def summary(prices, percent=0):
    amount = apply_discount(total(prices), percent)
    return f"{len(prices)} items, {amount:.2f}"
