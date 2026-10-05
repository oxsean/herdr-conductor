#!/bin/bash
# Start from a calc whose tests pass: this card is not about the total() bug.
sed -i.bak "s/prices\[1:\]/prices/" calc.py && rm calc.py.bak
