---
track: algorithms
section: Intervals & greedy
---

## Merge Intervals
> difficulty: Medium | tags: intervals, sorting | leetcode: 56

Merge every overlapping interval and return the result sorted by start.

```python starter
def merge(intervals):
    pass
```

```python solution
def merge(intervals):
    out = []
    for start, end in sorted(intervals):
        if out and start <= out[-1][1]:
            out[-1][1] = max(out[-1][1], end)
        else:
            out.append([start, end])
    return out
```

```python tests
check(merge([[1, 3], [2, 6], [8, 10], [15, 18]]), [[1, 6], [8, 10], [15, 18]])
check(merge([[1, 4], [4, 5]]), [[1, 5]])
check(merge([[1, 4], [0, 0]]), [[0, 0], [1, 4]])
check(merge([[1, 10], [2, 3], [4, 5]]), [[1, 10]])
```

## Meeting Rooms II
> difficulty: Medium | tags: intervals, heap, sweep line | leetcode: 253

Return the fewest rooms needed to hold every meeting `[start, end)`.

```python starter
def min_meeting_rooms(intervals):
    pass
```

```python solution
def min_meeting_rooms(intervals):
    events = []
    for s, e in intervals:
        events += [(s, 1), (e, -1)]
    rooms = best = 0
    for _, delta in sorted(events):     # at equal times the -1 (end) sorts first
        rooms += delta
        best = max(best, rooms)
    return best
```

```python tests
check(min_meeting_rooms([[0, 30], [5, 10], [15, 20]]), 2)
check(min_meeting_rooms([[7, 10], [2, 4]]), 1)
check(min_meeting_rooms([[1, 5], [5, 10]]), 1, "back to back")
check(min_meeting_rooms([]), 0)
```

## Insert Interval
> difficulty: Medium | tags: intervals | leetcode: 57

Insert `new` into sorted, non-overlapping `intervals`, merging where needed.

```python starter
def insert(intervals, new):
    pass
```

```python solution
def insert(intervals, new):
    s, e = new
    left = [iv for iv in intervals if iv[1] < s]
    right = [iv for iv in intervals if iv[0] > e]
    overlap = [iv for iv in intervals if not (iv[1] < s or iv[0] > e)]
    if overlap:
        s, e = min(s, overlap[0][0]), max(e, overlap[-1][1])
    return left + [[s, e]] + right
```

```python tests
check(insert([[1, 3], [6, 9]], [2, 5]), [[1, 5], [6, 9]])
check(insert([[1, 2], [3, 5], [6, 7], [8, 10], [12, 16]], [4, 8]), [[1, 2], [3, 10], [12, 16]])
check(insert([], [5, 7]), [[5, 7]])
```

## Jump Game
> difficulty: Medium | tags: greedy | leetcode: 55

`nums[i]` is the farthest jump from index `i`. Can you reach the last index?

```python starter
def can_jump(nums):
    pass
```

```python solution
def can_jump(nums):
    reach = 0
    for i, x in enumerate(nums):
        if i > reach:
            return False
        reach = max(reach, i + x)
    return True
```

```python tests
check(can_jump([2, 3, 1, 1, 4]), True)
check(can_jump([3, 2, 1, 0, 4]), False)
check(can_jump([0]), True)
```

## Gas Station
> difficulty: Medium | tags: greedy | leetcode: 134

Return the start index from which you can drive the full circle, or -1.

```python starter
def can_complete_circuit(gas, cost):
    pass
```

```python solution
def can_complete_circuit(gas, cost):
    if sum(gas) < sum(cost):
        return -1
    start = tank = 0
    for i in range(len(gas)):
        tank += gas[i] - cost[i]
        if tank < 0:                  # nothing from start..i can be the answer
            start, tank = i + 1, 0
    return start
```

```python tests
check(can_complete_circuit([1, 2, 3, 4, 5], [3, 4, 5, 1, 2]), 3)
check(can_complete_circuit([2, 3, 4], [3, 4, 3]), -1)
```
