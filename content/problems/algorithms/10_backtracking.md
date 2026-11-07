---
track: algorithms
section: Backtracking
---

## Subsets
> difficulty: Medium | tags: backtracking, bitmask | leetcode: 78

Return every subset of a list of distinct numbers. Any order.

```python starter
def subsets(nums):
    pass
```

```python solution
def subsets(nums):
    out, path = [], []
    def go(i):
        if i == len(nums):
            out.append(path[:])
            return
        go(i + 1)                 # skip nums[i]
        path.append(nums[i])      # take nums[i]
        go(i + 1)
        path.pop()
    go(0)
    return out
```

```python tests
check(deep_sorted(subsets([1, 2, 3])), deep_sorted([[], [1], [2], [3], [1, 2], [1, 3], [2, 3], [1, 2, 3]]))
check(subsets([]), [[]])
check(len(subsets(list(range(10)))), 1024)
```

## Permutations
> difficulty: Medium | tags: backtracking | leetcode: 46

Return every ordering of a list of distinct numbers.

```python starter
def permute(nums):
    pass
```

```python solution
def permute(nums):
    out, path, used = [], [], [False] * len(nums)
    def go():
        if len(path) == len(nums):
            out.append(path[:])
            return
        for i, x in enumerate(nums):
            if not used[i]:
                used[i] = True
                path.append(x)
                go()
                path.pop()
                used[i] = False
    go()
    return out
```

```python tests
check(deep_sorted(permute([1, 2, 3])), deep_sorted([[1, 2, 3], [1, 3, 2], [2, 1, 3], [2, 3, 1], [3, 1, 2], [3, 2, 1]]))
check(permute([1]), [[1]])
check(len(permute(list(range(6)))), 720)
```

## Combination Sum
> difficulty: Medium | tags: backtracking, pruning | leetcode: 39

Return every unique combination of `candidates` (each usable many times) that sums to `target`.

```python starter
def combination_sum(candidates, target):
    pass
```

```python solution
def combination_sum(candidates, target):
    candidates = sorted(candidates)
    out, path = [], []
    def go(start, remaining):
        if remaining == 0:
            out.append(path[:])
            return
        for i in range(start, len(candidates)):
            c = candidates[i]
            if c > remaining:
                break                         # sorted: nothing later fits either
            path.append(c)
            go(i, remaining - c)              # i, not i + 1: c can repeat
            path.pop()
    go(0, target)
    return out
```

```python tests
check(deep_sorted(combination_sum([2, 3, 6, 7], 7)), [[2, 2, 3], [7]])
check(deep_sorted(combination_sum([2, 3, 5], 8)), [[2, 2, 2, 2], [2, 3, 3], [3, 5]])
check(combination_sum([2], 1), [])
```

## N-Queens (count)
> difficulty: Hard | tags: backtracking, sets | leetcode: 52

How many ways can `n` queens sit on an `n × n` board with no two attacking each other?

```python starter
def total_n_queens(n):
    pass
```

```python solution
def total_n_queens(n):
    cols, diag, anti = set(), set(), set()
    def go(r):
        if r == n:
            return 1
        count = 0
        for c in range(n):
            if c in cols or r - c in diag or r + c in anti:
                continue
            cols.add(c); diag.add(r - c); anti.add(r + c)
            count += go(r + 1)
            cols.remove(c); diag.remove(r - c); anti.remove(r + c)
        return count
    return go(0)
```

```python tests
check(total_n_queens(1), 1)
check(total_n_queens(4), 2)
check(total_n_queens(6), 4)
check(total_n_queens(8), 92)
```

## Word Search
> difficulty: Medium | tags: backtracking, grid | leetcode: 79

Can `word` be traced through adjacent cells of `board` without reusing a cell?

```python starter
def exist(board, word):
    pass
```

```python solution
def exist(board, word):
    rows, cols = len(board), len(board[0])
    def go(r, c, i):
        if i == len(word):
            return True
        if not (0 <= r < rows and 0 <= c < cols) or board[r][c] != word[i]:
            return False
        ch, board[r][c] = board[r][c], "#"      # mark as used
        found = any(go(r + dr, c + dc, i + 1) for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        board[r][c] = ch
        return found
    return any(go(r, c, 0) for r in range(rows) for c in range(cols))
```

```python tests
b = [list("ABCE"), list("SFCS"), list("ADEE")]
check(exist(b, "ABCCED"), True)
check(exist(b, "SEE"), True)
check(exist(b, "ABCB"), False)
```
