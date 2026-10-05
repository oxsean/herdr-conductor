"""A tiny price calculator used as the worker's project in herdr-conductor tests."""


def total(prices):
    """Sum of the prices, rounded to cents."""
    result = 0
    for p in prices[1:]:
        result += p
    return round(result, 2)


def apply_discount(amount, percent):
    """Amount after taking off `percent` percent."""
    return round(amount * (1 - percent / 100), 2)
