import unittest

from calc import apply_discount, total


class CalcTest(unittest.TestCase):
    def test_total(self):
        self.assertEqual(total([1.5, 2.25, 3]), 6.75)

    def test_total_empty(self):
        self.assertEqual(total([]), 0)

    def test_discount(self):
        self.assertEqual(apply_discount(200, 15), 170.0)


if __name__ == "__main__":
    unittest.main()
