---
track: algorithms
section: Arrays & hashing
---

## Two Sum
> difficulty: Easy | tags: hash map | leetcode: 1

Return the indices `[i, j]` (with `i < j`) of the two numbers in `nums` that add up to `target`.
Exactly one answer exists. Aim for one pass, O(n).

```python starter
def two_sum(nums, target):
    pass
```

```python solution
def two_sum(nums, target):
    seen = {}                      # value -> index
    for j, x in enumerate(nums):
        if target - x in seen:
            return [seen[target - x], j]
        seen[x] = j
```

```python tests
check(two_sum([2, 7, 11, 15], 9), [0, 1])
check(two_sum([3, 2, 4], 6), [1, 2])
check(two_sum([3, 3], 6), [0, 1])
check(two_sum(list(range(100_000)), 199_997), [99_998, 99_999], "100k items")
```

## Group Anagrams
> difficulty: Medium | tags: hash map, sorting | leetcode: 49

Group the words that are anagrams of each other. Any order of groups and of words within a group is fine.

```python starter
def group_anagrams(words):
    pass
```

```python solution
from collections import defaultdict

def group_anagrams(words):
    groups = defaultdict(list)
    for w in words:
        groups["".join(sorted(w))].append(w)   # or a 26-count tuple key for O(n·k)
    return list(groups.values())
```

```python tests
check(deep_sorted(group_anagrams(["eat", "tea", "tan", "ate", "nat", "bat"])),
      deep_sorted([["bat"], ["nat", "tan"], ["ate", "eat", "tea"]]))
check(group_anagrams([""]), [[""]])
check(group_anagrams(["a"]), [["a"]])
```

## Top K Frequent Elements
> difficulty: Medium | tags: hash map, heap, bucket sort | leetcode: 347

Return the `k` most frequent values, most frequent first. Ties don't occur in the tests.
Can you beat O(n log n)? (Hint: bucket by count.)

```python starter
def top_k_frequent(nums, k):
    pass
```

```python solution
from collections import Counter

def top_k_frequent(nums, k):
    count = Counter(nums)
    buckets = [[] for _ in range(len(nums) + 1)]   # buckets[c] = values seen c times
    for x, c in count.items():
        buckets[c].append(x)
    out = []
    for c in range(len(buckets) - 1, 0, -1):
        for x in buckets[c]:
            out.append(x)
            if len(out) == k:
                return out
    return out
```

```python tests
check(top_k_frequent([1, 1, 1, 2, 2, 3], 2), [1, 2])
check(top_k_frequent([1], 1), [1])
check(top_k_frequent([4, 4, 4, 4, 5, 5, 5, 6, 6, 7], 3), [4, 5, 6])
```

## Product of Array Except Self
> difficulty: Medium | tags: prefix product | leetcode: 238

Return `out` where `out[i]` is the product of every element except `nums[i]`, in O(n) and without division.

```python starter
def product_except_self(nums):
    pass
```

```python solution
def product_except_self(nums):
    n = len(nums)
    out = [1] * n
    prefix = 1
    for i in range(n):            # out[i] = product of everything left of i
        out[i] = prefix
        prefix *= nums[i]
    suffix = 1
    for i in range(n - 1, -1, -1):  # times everything right of i
        out[i] *= suffix
        suffix *= nums[i]
    return out
```

```python tests
check(product_except_self([1, 2, 3, 4]), [24, 12, 8, 6])
check(product_except_self([-1, 1, 0, -3, 3]), [0, 0, 9, 0, 0])
check(product_except_self([0, 0]), [0, 0])
```

## Longest Consecutive Sequence
> difficulty: Medium | tags: hash set | leetcode: 128

Return the length of the longest run of consecutive integers in an unsorted list, in O(n).

```python starter
def longest_consecutive(nums):
    pass
```

```python solution
def longest_consecutive(nums):
    s = set(nums)
    best = 0
    for x in s:
        if x - 1 not in s:          # only start counting at the start of a run
            y = x
            while y + 1 in s:
                y += 1
            best = max(best, y - x + 1)
    return best
```

```python tests
check(longest_consecutive([100, 4, 200, 1, 3, 2]), 4)
check(longest_consecutive([0, 3, 7, 2, 5, 8, 4, 6, 0, 1]), 9)
check(longest_consecutive([]), 0)
check(longest_consecutive(list(range(200_000, 0, -1))), 200_000, "200k descending")
```
