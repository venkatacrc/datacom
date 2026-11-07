---
track: algorithms
section: Graphs
---

## Number of Islands
> difficulty: Medium | tags: grid, BFS/DFS | leetcode: 200

Count the groups of `"1"` cells connected up, down, left or right.

```python starter
def num_islands(grid):
    pass
```

```python solution
def num_islands(grid):
    if not grid:
        return 0
    rows, cols = len(grid), len(grid[0])
    seen = set()
    count = 0
    for r in range(rows):
        for c in range(cols):
            if grid[r][c] == "1" and (r, c) not in seen:
                count += 1
                stack = [(r, c)]               # iterative DFS: no recursion limit
                seen.add((r, c))
                while stack:
                    y, x = stack.pop()
                    for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                        if 0 <= ny < rows and 0 <= nx < cols and grid[ny][nx] == "1" and (ny, nx) not in seen:
                            seen.add((ny, nx))
                            stack.append((ny, nx))
    return count
```

```python tests
check(num_islands([list("11110"), list("11010"), list("11000"), list("00000")]), 1)
check(num_islands([list("11000"), list("11000"), list("00100"), list("00011")]), 3)
check(num_islands([]), 0)
check(num_islands([["1"] * 300 for _ in range(300)]), 1, "300×300 of land")
```

## Course Schedule (Topological Order)
> difficulty: Medium | tags: graph, topological sort | leetcode: 210

`prereqs` holds pairs `[course, needs]`. Return an order to take all `n` courses, or `[]` if a cycle makes it impossible.
Any valid order passes.

```python starter
def find_order(n, prereqs):
    pass
```

```python solution
from collections import deque

def find_order(n, prereqs):
    graph = [[] for _ in range(n)]
    indegree = [0] * n
    for course, need in prereqs:
        graph[need].append(course)
        indegree[course] += 1
    q = deque(i for i in range(n) if indegree[i] == 0)   # Kahn's algorithm
    order = []
    while q:
        u = q.popleft()
        order.append(u)
        for v in graph[u]:
            indegree[v] -= 1
            if indegree[v] == 0:
                q.append(v)
    return order if len(order) == n else []
```

```python tests
def valid(n, prereqs, order):
    pos = {c: i for i, c in enumerate(order)}
    return len(order) == n and all(pos[need] < pos[c] for c, need in prereqs)
check_true(valid(2, [[1, 0]], find_order(2, [[1, 0]])), "2 courses")
p = [[1, 0], [2, 0], [3, 1], [3, 2]]
check_true(valid(4, p, find_order(4, p)), "diamond")
check(find_order(2, [[1, 0], [0, 1]]), [], "cycle")
check(sorted(find_order(3, [])), [0, 1, 2], "no prerequisites")
```

## Network Delay Time (Dijkstra)
> difficulty: Medium | tags: graph, shortest path, heap | leetcode: 743

`times` holds directed edges `(u, v, w)` over nodes `1..n`. A signal starts at `k`. How long until every node hears it? Return -1 if some never do.

```python starter
def network_delay_time(times, n, k):
    pass
```

```python solution
import heapq
from collections import defaultdict

def network_delay_time(times, n, k):
    graph = defaultdict(list)
    for u, v, w in times:
        graph[u].append((v, w))
    dist = {}
    heap = [(0, k)]
    while heap:
        d, u = heapq.heappop(heap)
        if u in dist:
            continue                      # already settled with a shorter distance
        dist[u] = d
        for v, w in graph[u]:
            if v not in dist:
                heapq.heappush(heap, (d + w, v))
    return max(dist.values()) if len(dist) == n else -1
```

```python tests
check(network_delay_time([[2, 1, 1], [2, 3, 1], [3, 4, 1]], 4, 2), 2)
check(network_delay_time([[1, 2, 1]], 2, 1), 1)
check(network_delay_time([[1, 2, 1]], 2, 2), -1)
check(network_delay_time([[1, 2, 5], [1, 3, 1], [3, 2, 1]], 3, 1), 2, "detour is shorter")
```

## Number of Provinces (Union-Find)
> difficulty: Medium | tags: union-find | leetcode: 547

`connected[i][j] == 1` means city `i` and city `j` are directly linked. Count the connected groups.
Implement union-find with path compression and union by size.

```python starter
def find_circle_num(connected):
    pass
```

```python solution
def find_circle_num(connected):
    n = len(connected)
    parent, size = list(range(n)), [1] * n

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]    # path halving
            x = parent[x]
        return x

    groups = n
    for i in range(n):
        for j in range(i + 1, n):
            if connected[i][j]:
                a, b = find(i), find(j)
                if a != b:
                    if size[a] < size[b]:
                        a, b = b, a
                    parent[b] = a
                    size[a] += size[b]
                    groups -= 1
    return groups
```

```python tests
check(find_circle_num([[1, 1, 0], [1, 1, 0], [0, 0, 1]]), 2)
check(find_circle_num([[1, 0, 0], [0, 1, 0], [0, 0, 1]]), 3)
check(find_circle_num([[1, 0, 0, 1], [0, 1, 1, 0], [0, 1, 1, 1], [1, 0, 1, 1]]), 1)
```

## Word Ladder
> difficulty: Hard | tags: BFS | leetcode: 127

Change one letter at a time, each step being a word in `words`. Return the number of words in the shortest sequence from `begin` to `end` (including both), or 0.

```python starter
def ladder_length(begin, end, words):
    pass
```

```python solution
from collections import defaultdict, deque

def ladder_length(begin, end, words):
    words = set(words)
    if end not in words:
        return 0
    buckets = defaultdict(list)            # "h*t" -> ["hot", "hit"]
    for w in words | {begin}:
        for i in range(len(w)):
            buckets[w[:i] + "*" + w[i + 1:]].append(w)
    q, seen = deque([(begin, 1)]), {begin}
    while q:
        w, d = q.popleft()
        if w == end:
            return d
        for i in range(len(w)):
            key = w[:i] + "*" + w[i + 1:]
            for nxt in buckets.pop(key, []):   # each bucket is expanded once
                if nxt not in seen:
                    seen.add(nxt)
                    q.append((nxt, d + 1))
    return 0
```

```python tests
check(ladder_length("hit", "cog", ["hot", "dot", "dog", "lot", "log", "cog"]), 5)
check(ladder_length("hit", "cog", ["hot", "dot", "dog", "lot", "log"]), 0)
check(ladder_length("a", "c", ["a", "b", "c"]), 2)
```
