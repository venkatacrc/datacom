---
track: algorithms
section: Sliding window
---

## Longest Substring Without Repeating Characters
> difficulty: Medium | tags: sliding window, hash map | leetcode: 3

Return the length of the longest substring of `s` with no repeated character.

```python starter
def length_of_longest_substring(s):
    pass
```

```python solution
def length_of_longest_substring(s):
    last = {}            # char -> last index seen
    left = best = 0
    for right, ch in enumerate(s):
        if last.get(ch, -1) >= left:
            left = last[ch] + 1      # jump past the previous copy
        last[ch] = right
        best = max(best, right - left + 1)
    return best
```

```python tests
check(length_of_longest_substring("abcabcbb"), 3)
check(length_of_longest_substring("bbbbb"), 1)
check(length_of_longest_substring("pwwkew"), 3)
check(length_of_longest_substring(""), 0)
check(length_of_longest_substring("abba"), 2)
```

## Minimum Window Substring
> difficulty: Hard | tags: sliding window, counting | leetcode: 76

Return the shortest substring of `s` that contains every character of `t` (with multiplicity), or `""`.

```python starter
def min_window(s, t):
    pass
```

```python solution
from collections import Counter

def min_window(s, t):
    need = Counter(t)
    missing = len(t)
    left = 0
    best = (float("inf"), 0, 0)
    for right, ch in enumerate(s):
        if need[ch] > 0:
            missing -= 1
        need[ch] -= 1
        while missing == 0:                       # window is valid: shrink it
            if right - left + 1 < best[0]:
                best = (right - left + 1, left, right + 1)
            need[s[left]] += 1
            if need[s[left]] > 0:
                missing += 1
            left += 1
    return s[best[1]:best[2]] if best[0] != float("inf") else ""
```

```python tests
check(min_window("ADOBECODEBANC", "ABC"), "BANC")
check(min_window("a", "a"), "a")
check(min_window("a", "aa"), "")
check(min_window("aaflslflsldkalskaaa", "aaa"), "aaa")
```

## Sliding Window Maximum
> difficulty: Hard | tags: monotonic deque | leetcode: 239

Return the maximum of every window of size `k` as it slides across `nums`, in O(n).

```python starter
def max_sliding_window(nums, k):
    pass
```

```python solution
from collections import deque

def max_sliding_window(nums, k):
    dq, out = deque(), []          # indices; their values decrease front to back
    for i, x in enumerate(nums):
        while dq and nums[dq[-1]] <= x:
            dq.pop()
        dq.append(i)
        if dq[0] <= i - k:
            dq.popleft()
        if i >= k - 1:
            out.append(nums[dq[0]])
    return out
```

```python tests
check(max_sliding_window([1, 3, -1, -3, 5, 3, 6, 7], 3), [3, 3, 5, 5, 6, 7])
check(max_sliding_window([1], 1), [1])
check(max_sliding_window([9, 8, 7, 6], 2), [9, 8, 7])
check(len(max_sliding_window(list(range(100_000)), 50)), 99_951, "100k items")
```

## Permutation in String
> difficulty: Medium | tags: fixed window, counting | leetcode: 567

Does `s2` contain some permutation of `s1` as a contiguous substring?

```python starter
def check_inclusion(s1, s2):
    pass
```

```python solution
from collections import Counter

def check_inclusion(s1, s2):
    k = len(s1)
    need, window = Counter(s1), Counter(s2[:k])
    if need == window:
        return True
    for i in range(k, len(s2)):
        window[s2[i]] += 1
        window[s2[i - k]] -= 1
        if window[s2[i - k]] == 0:
            del window[s2[i - k]]
        if window == need:
            return True
    return False
```

```python tests
check(check_inclusion("ab", "eidbaooo"), True)
check(check_inclusion("ab", "eidboaoo"), False)
check(check_inclusion("adc", "dcda"), True)
```
