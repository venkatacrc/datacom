# title: Scratchpad
# Write any Python here and press Run. Output streams below as it's printed.
# `dc` has test and data helpers: check, stream, clickstream, ticks, sensor, orders, table, Timer.
from dc import check, report


def solve(nums):
    return sorted(nums)


check(solve([3, 1, 2]), [1, 2, 3])
report()
