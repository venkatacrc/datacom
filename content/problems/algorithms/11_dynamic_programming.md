---
track: algorithms
section: Dynamic programming
---

## Climbing Stairs
> difficulty: Easy | tags: 1-D DP | leetcode: 70

You climb 1 or 2 steps at a time. How many distinct ways reach step `n`?

```python starter
def climb_stairs(n):
    pass
```

```python solution
def climb_stairs(n):
    a, b = 1, 1                  # ways to reach step i-1 and step i
    for _ in range(n - 1):
        a, b = b, a + b
    return b
```

```python tests
check(climb_stairs(1), 1)
check(climb_stairs(2), 2)
check(climb_stairs(3), 3)
check(climb_stairs(45), 1836311903)
```

## House Robber
> difficulty: Medium | tags: 1-D DP | leetcode: 198

You can't rob two adjacent houses. Return the most money you can take.

```python starter
def rob(nums):
    pass
```

```python solution
def rob(nums):
    skip = take = 0               # best total if the previous house was skipped / taken
    for x in nums:
        skip, take = max(skip, take), skip + x
    return max(skip, take)
```

```python tests
check(rob([1, 2, 3, 1]), 4)
check(rob([2, 7, 9, 3, 1]), 12)
check(rob([]), 0)
check(rob([2, 1, 1, 2]), 4)
```

## Coin Change
> difficulty: Medium | tags: unbounded knapsack | leetcode: 322

Return the fewest coins that make `amount`, or -1 if impossible.

```python starter
def coin_change(coins, amount):
    pass
```

```python solution
def coin_change(coins, amount):
    INF = amount + 1
    dp = [0] + [INF] * amount     # dp[a] = fewest coins for a
    for a in range(1, amount + 1):
        for c in coins:
            if c <= a and dp[a - c] + 1 < dp[a]:
                dp[a] = dp[a - c] + 1
    return dp[amount] if dp[amount] != INF else -1
```

```python tests
check(coin_change([1, 2, 5], 11), 3)
check(coin_change([2], 3), -1)
check(coin_change([1], 0), 0)
check(coin_change([186, 419, 83, 408], 6249), 20)
```

## Longest Increasing Subsequence
> difficulty: Medium | tags: DP, binary search | leetcode: 300

Return the length of the longest strictly increasing subsequence. O(n²) DP works; patience sorting gives O(n log n).

```python starter
def length_of_lis(nums):
    pass
```

```python solution
import bisect

def length_of_lis(nums):
    tails = []                    # tails[i] = smallest tail of an increasing run of length i+1
    for x in nums:
        i = bisect.bisect_left(tails, x)
        if i == len(tails):
            tails.append(x)
        else:
            tails[i] = x
    return len(tails)
```

```python tests
check(length_of_lis([10, 9, 2, 5, 3, 7, 101, 18]), 4)
check(length_of_lis([0, 1, 0, 3, 2, 3]), 4)
check(length_of_lis([7, 7, 7, 7]), 1)
check(length_of_lis(list(range(5000))), 5000, "5,000 increasing")
```

## Longest Common Subsequence
> difficulty: Medium | tags: 2-D DP | leetcode: 1143

Return the length of the longest subsequence common to `a` and `b`.

```python starter
def longest_common_subsequence(a, b):
    pass
```

```python solution
def longest_common_subsequence(a, b):
    prev = [0] * (len(b) + 1)            # one row of the table at a time
    for ca in a:
        cur = [0]
        for j, cb in enumerate(b):
            cur.append(prev[j] + 1 if ca == cb else max(prev[j + 1], cur[j]))
        prev = cur
    return prev[-1]
```

```python tests
check(longest_common_subsequence("abcde", "ace"), 3)
check(longest_common_subsequence("abc", "abc"), 3)
check(longest_common_subsequence("abc", "def"), 0)
```

## Edit Distance
> difficulty: Medium | tags: 2-D DP | leetcode: 72

Fewest single-character inserts, deletes or replaces to turn `a` into `b`.

```python starter
def min_distance(a, b):
    pass
```

```python solution
def min_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            if ca == cb:
                cur.append(prev[j - 1])
            else:
                cur.append(1 + min(prev[j], cur[j - 1], prev[j - 1]))   # delete, insert, replace
        prev = cur
    return prev[-1]
```

```python tests
check(min_distance("horse", "ros"), 3)
check(min_distance("intention", "execution"), 5)
check(min_distance("", "abc"), 3)
```

## Word Break
> difficulty: Medium | tags: DP, strings | leetcode: 139

Can `s` be split into words from `words`?

```python starter
def word_break(s, words):
    pass
```

```python solution
def word_break(s, words):
    words = set(words)
    longest = max(map(len, words), default=0)
    ok = [True] + [False] * len(s)       # ok[i]: s[:i] can be split
    for i in range(1, len(s) + 1):
        for j in range(max(0, i - longest), i):
            if ok[j] and s[j:i] in words:
                ok[i] = True
                break
    return ok[-1]
```

```python tests
check(word_break("leetcode", ["leet", "code"]), True)
check(word_break("applepenapple", ["apple", "pen"]), True)
check(word_break("catsandog", ["cats", "dog", "sand", "and", "cat"]), False)
check(word_break("a" * 200 + "b", ["a", "aa", "aaa"]), False, "no exponential blow-up")
```

## 0/1 Knapsack
> difficulty: Medium | tags: 2-D DP | leetcode: —

Each item `(weight, value)` can be taken at most once. Return the best total value within `capacity`.

```python starter
def knapsack(items, capacity):
    pass
```

```python solution
def knapsack(items, capacity):
    dp = [0] * (capacity + 1)            # dp[c] = best value with capacity c
    for w, v in items:
        for c in range(capacity, w - 1, -1):   # backwards so each item is used once
            dp[c] = max(dp[c], dp[c - w] + v)
    return dp[capacity]
```

```python tests
check(knapsack([(1, 1), (3, 4), (4, 5), (5, 7)], 7), 9)
check(knapsack([(5, 10)], 4), 0)
check(knapsack([(10, 60), (20, 100), (30, 120)], 50), 220)
```
