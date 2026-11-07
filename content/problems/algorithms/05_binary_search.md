---
track: algorithms
section: Binary search
---

## Lower Bound
> difficulty: Easy | tags: binary search | leetcode: 35

Return the first index where `target` could be inserted into sorted `nums` to keep it sorted
(the index of the first element `>= target`). Write the loop yourself; no `bisect`.

```python starter
def lower_bound(nums, target):
    pass
```

```python solution
def lower_bound(nums, target):
    lo, hi = 0, len(nums)          # answer lives in [lo, hi]
    while lo < hi:
        mid = (lo + hi) // 2
        if nums[mid] < target:
            lo = mid + 1
        else:
            hi = mid
    return lo
```

```python tests
check(lower_bound([1, 3, 5, 6], 5), 2)
check(lower_bound([1, 3, 5, 6], 2), 1)
check(lower_bound([1, 3, 5, 6], 7), 4)
check(lower_bound([], 3), 0)
check(lower_bound([2, 2, 2, 3], 2), 0)
```

## Search in Rotated Sorted Array
> difficulty: Medium | tags: binary search | leetcode: 33

A sorted array of distinct values was rotated at an unknown pivot. Return the index of `target`, or -1, in O(log n).

```python starter
def search_rotated(nums, target):
    pass
```

```python solution
def search_rotated(nums, target):
    lo, hi = 0, len(nums) - 1
    while lo <= hi:
        mid = (lo + hi) // 2
        if nums[mid] == target:
            return mid
        if nums[lo] <= nums[mid]:                  # left half is sorted
            if nums[lo] <= target < nums[mid]:
                hi = mid - 1
            else:
                lo = mid + 1
        else:                                       # right half is sorted
            if nums[mid] < target <= nums[hi]:
                lo = mid + 1
            else:
                hi = mid - 1
    return -1
```

```python tests
check(search_rotated([4, 5, 6, 7, 0, 1, 2], 0), 4)
check(search_rotated([4, 5, 6, 7, 0, 1, 2], 3), -1)
check(search_rotated([1], 0), -1)
check(search_rotated([3, 1], 1), 1)
```

## Find Minimum in Rotated Sorted Array
> difficulty: Medium | tags: binary search | leetcode: 153

Return the smallest element of a rotated sorted array of distinct values, in O(log n).

```python starter
def find_min(nums):
    pass
```

```python solution
def find_min(nums):
    lo, hi = 0, len(nums) - 1
    while lo < hi:
        mid = (lo + hi) // 2
        if nums[mid] > nums[hi]:     # minimum is to the right of mid
            lo = mid + 1
        else:
            hi = mid
    return nums[lo]
```

```python tests
check(find_min([3, 4, 5, 1, 2]), 1)
check(find_min([4, 5, 6, 7, 0, 1, 2]), 0)
check(find_min([11, 13, 15, 17]), 11)
check(find_min([2, 1]), 1)
```

## Koko Eating Bananas
> difficulty: Medium | tags: binary search on the answer | leetcode: 875

Koko eats at most `k` bananas from one pile per hour. Return the minimum integer `k` that lets her finish all `piles` within `h` hours.

```python starter
def min_eating_speed(piles, h):
    pass
```

```python solution
def min_eating_speed(piles, h):
    def hours(k):
        return sum((p + k - 1) // k for p in piles)
    lo, hi = 1, max(piles)
    while lo < hi:                   # smallest k with hours(k) <= h
        mid = (lo + hi) // 2
        if hours(mid) <= h:
            hi = mid
        else:
            lo = mid + 1
    return lo
```

```python tests
check(min_eating_speed([3, 6, 7, 11], 8), 4)
check(min_eating_speed([30, 11, 23, 4, 20], 5), 30)
check(min_eating_speed([30, 11, 23, 4, 20], 6), 23)
check(min_eating_speed([1_000_000_000], 2), 500_000_000)
```

## Median of Two Sorted Arrays
> difficulty: Hard | tags: binary search, partition | leetcode: 4

Return the median of two sorted arrays in O(log(min(m, n))).

```python starter
def find_median_sorted_arrays(a, b):
    pass
```

```python solution
def find_median_sorted_arrays(a, b):
    if len(a) > len(b):
        a, b = b, a
    m, n = len(a), len(b)
    half = (m + n + 1) // 2
    lo, hi = 0, m
    while lo <= hi:
        i = (lo + hi) // 2            # take i from a, half - i from b
        j = half - i
        a_left = a[i - 1] if i > 0 else float("-inf")
        a_right = a[i] if i < m else float("inf")
        b_left = b[j - 1] if j > 0 else float("-inf")
        b_right = b[j] if j < n else float("inf")
        if a_left <= b_right and b_left <= a_right:
            if (m + n) % 2:
                return float(max(a_left, b_left))
            return (max(a_left, b_left) + min(a_right, b_right)) / 2
        if a_left > b_right:
            hi = i - 1
        else:
            lo = i + 1
```

```python tests
check(find_median_sorted_arrays([1, 3], [2]), 2.0)
check(find_median_sorted_arrays([1, 2], [3, 4]), 2.5)
check(find_median_sorted_arrays([], [1]), 1.0)
check(find_median_sorted_arrays([1, 2, 3, 4, 5], [6, 7, 8, 9, 10, 11]), 6.0)
```
