---
track: algorithms
section: Heaps & top-k
---

## Kth Largest Element in an Array
> difficulty: Medium | tags: heap, quickselect | leetcode: 215

Return the `k`-th largest value without fully sorting. A size-`k` min-heap gives O(n log k).

```python starter
def find_kth_largest(nums, k):
    pass
```

```python solution
import heapq

def find_kth_largest(nums, k):
    heap = nums[:k]
    heapq.heapify(heap)              # the k largest so far; heap[0] is the smallest of them
    for x in nums[k:]:
        if x > heap[0]:
            heapq.heapreplace(heap, x)
    return heap[0]
```

```python tests
check(find_kth_largest([3, 2, 1, 5, 6, 4], 2), 5)
check(find_kth_largest([3, 2, 3, 1, 2, 4, 5, 5, 6], 4), 4)
check(find_kth_largest([1], 1), 1)
```

## Merge K Sorted Lists
> difficulty: Hard | tags: heap, linked list | leetcode: 23

Merge `k` sorted linked lists into one sorted list in O(N log k).

```python starter
from dc import ListNode

def merge_k_lists(lists):
    pass
```

```python solution
import heapq
from dc import ListNode

def merge_k_lists(lists):
    heap = [(node.val, i, node) for i, node in enumerate(lists) if node]   # i breaks ties
    heapq.heapify(heap)
    dummy = tail = ListNode()
    while heap:
        _, i, node = heapq.heappop(heap)
        tail.next = tail = node
        if node.next:
            heapq.heappush(heap, (node.next.val, i, node.next))
    return dummy.next
```

```python tests
check(list_values(merge_k_lists([make_list([1, 4, 5]), make_list([1, 3, 4]), make_list([2, 6])])),
      [1, 1, 2, 3, 4, 4, 5, 6])
check(list_values(merge_k_lists([])), [])
check(list_values(merge_k_lists([None, make_list([1])])), [1])
```

## K Closest Points to Origin
> difficulty: Medium | tags: heap | leetcode: 973

Return the `k` points closest to `(0, 0)`, sorted nearest first.

```python starter
def k_closest(points, k):
    pass
```

```python solution
import heapq

def k_closest(points, k):
    return heapq.nsmallest(k, points, key=lambda p: p[0] * p[0] + p[1] * p[1])
```

```python tests
check(k_closest([[1, 3], [-2, 2]], 1), [[-2, 2]])
check(k_closest([[3, 3], [5, -1], [-2, 4]], 2), [[3, 3], [-2, 4]])
```

## Find Median from Data Stream
> difficulty: Hard | tags: two heaps, streaming | leetcode: 295

`add_num(x)` takes numbers one at a time; `find_median()` returns the median of everything so far in O(1).
This is the core of every "p50 of a live metric" question.

```python starter
class MedianFinder:
    def __init__(self):
        pass

    def add_num(self, x):
        pass

    def find_median(self):
        pass
```

```python solution
import heapq

class MedianFinder:
    def __init__(self):
        self.low = []    # max-heap (negated) of the smaller half
        self.high = []   # min-heap of the larger half

    def add_num(self, x):
        heapq.heappush(self.low, -x)
        heapq.heappush(self.high, -heapq.heappop(self.low))
        if len(self.high) > len(self.low):
            heapq.heappush(self.low, -heapq.heappop(self.high))

    def find_median(self):
        if len(self.low) > len(self.high):
            return float(-self.low[0])
        return (-self.low[0] + self.high[0]) / 2
```

```python tests
m = MedianFinder()
m.add_num(1); m.add_num(2)
check(m.find_median(), 1.5)
m.add_num(3)
check(m.find_median(), 2.0)
import random, statistics
rng = random.Random(0); m = MedianFinder(); seen = []
ok = True
for _ in range(2000):
    x = rng.randint(-1000, 1000); m.add_num(x); seen.append(x)
    ok = ok and m.find_median() == statistics.median(seen)
check_true(ok, "matches statistics.median over 2,000 random numbers")
```

## Task Scheduler
> difficulty: Medium | tags: greedy, counting | leetcode: 621

CPU tasks (letters) need `n` idle slots between two runs of the same letter. Return the fewest time slots to finish all tasks.

```python starter
def least_interval(tasks, n):
    pass
```

```python solution
from collections import Counter

def least_interval(tasks, n):
    counts = Counter(tasks).values()
    top = max(counts)
    n_top = sum(1 for c in counts if c == top)
    return max(len(tasks), (top - 1) * (n + 1) + n_top)
```

```python tests
check(least_interval(list("AAABBB"), 2), 8)
check(least_interval(list("AAABBB"), 0), 6)
check(least_interval(list("AAAAAABCDEFG"), 2), 16)
```
