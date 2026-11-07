---
track: algorithms
section: Two pointers
---

## Valid Palindrome
> difficulty: Easy | tags: two pointers, strings | leetcode: 125

After lowercasing and dropping every non-alphanumeric character, does `s` read the same both ways?
Do it in O(1) extra space.

```python starter
def is_palindrome(s):
    pass
```

```python solution
def is_palindrome(s):
    i, j = 0, len(s) - 1
    while i < j:
        if not s[i].isalnum():
            i += 1
        elif not s[j].isalnum():
            j -= 1
        elif s[i].lower() != s[j].lower():
            return False
        else:
            i, j = i + 1, j - 1
    return True
```

```python tests
check(is_palindrome("A man, a plan, a canal: Panama"), True)
check(is_palindrome("race a car"), False)
check(is_palindrome(" "), True)
check(is_palindrome("0P"), False)
```

## 3Sum
> difficulty: Medium | tags: two pointers, sorting | leetcode: 15

Return every unique triplet `[a, b, c]` from `nums` with `a + b + c == 0`. Any order is fine.

```python starter
def three_sum(nums):
    pass
```

```python solution
def three_sum(nums):
    nums = sorted(nums)
    out = []
    for i, a in enumerate(nums):
        if a > 0:
            break
        if i and a == nums[i - 1]:
            continue
        lo, hi = i + 1, len(nums) - 1
        while lo < hi:
            s = a + nums[lo] + nums[hi]
            if s < 0:
                lo += 1
            elif s > 0:
                hi -= 1
            else:
                out.append([a, nums[lo], nums[hi]])
                lo += 1
                while lo < hi and nums[lo] == nums[lo - 1]:
                    lo += 1
    return out
```

```python tests
check(deep_sorted(three_sum([-1, 0, 1, 2, -1, -4])), [[-1, -1, 2], [-1, 0, 1]])
check(three_sum([0, 1, 1]), [])
check(three_sum([0, 0, 0, 0]), [[0, 0, 0]])
check(deep_sorted(three_sum([-2, 0, 1, 1, 2])), [[-2, 0, 2], [-2, 1, 1]])
```

## Container With Most Water
> difficulty: Medium | tags: two pointers, greedy | leetcode: 11

`height[i]` is a vertical line at `x = i`. Pick two lines that, with the x-axis, hold the most water. Return that area.

```python starter
def max_area(height):
    pass
```

```python solution
def max_area(height):
    i, j, best = 0, len(height) - 1, 0
    while i < j:
        best = max(best, (j - i) * min(height[i], height[j]))
        if height[i] < height[j]:    # the shorter side limits the area: move it
            i += 1
        else:
            j -= 1
    return best
```

```python tests
check(max_area([1, 8, 6, 2, 5, 4, 8, 3, 7]), 49)
check(max_area([1, 1]), 1)
check(max_area([4, 3, 2, 1, 4]), 16)
```

## Trapping Rain Water
> difficulty: Hard | tags: two pointers, prefix max | leetcode: 42

Given bar heights, how many units of rain water are trapped between them? O(n) time, O(1) space.

```python starter
def trap(height):
    pass
```

```python solution
def trap(height):
    i, j = 0, len(height) - 1
    left_max = right_max = water = 0
    while i < j:
        if height[i] < height[j]:
            left_max = max(left_max, height[i])
            water += left_max - height[i]
            i += 1
        else:
            right_max = max(right_max, height[j])
            water += right_max - height[j]
            j -= 1
    return water
```

```python tests
check(trap([0, 1, 0, 2, 1, 0, 1, 3, 2, 1, 2, 1]), 6)
check(trap([4, 2, 0, 3, 2, 5]), 9)
check(trap([]), 0)
check(trap([5, 4, 3, 2, 1]), 0)
```
