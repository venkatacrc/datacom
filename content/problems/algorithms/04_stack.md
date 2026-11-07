---
track: algorithms
section: Stack & monotonic stack
---

## Valid Parentheses
> difficulty: Easy | tags: stack | leetcode: 20

Is every bracket in `s` (`()[]{}`) closed by the right type in the right order?

```python starter
def is_valid(s):
    pass
```

```python solution
def is_valid(s):
    pairs = {")": "(", "]": "[", "}": "{"}
    stack = []
    for ch in s:
        if ch in pairs:
            if not stack or stack.pop() != pairs[ch]:
                return False
        else:
            stack.append(ch)
    return not stack
```

```python tests
check(is_valid("()"), True)
check(is_valid("()[]{}"), True)
check(is_valid("(]"), False)
check(is_valid("([)]"), False)
check(is_valid("{[]}"), True)
check(is_valid("(("), False)
```

## Daily Temperatures
> difficulty: Medium | tags: monotonic stack | leetcode: 739

For each day, how many days until a warmer temperature? Use 0 if none comes.

```python starter
def daily_temperatures(temps):
    pass
```

```python solution
def daily_temperatures(temps):
    out = [0] * len(temps)
    stack = []                       # indices of days still waiting, temps decreasing
    for i, t in enumerate(temps):
        while stack and temps[stack[-1]] < t:
            j = stack.pop()
            out[j] = i - j
        stack.append(i)
    return out
```

```python tests
check(daily_temperatures([73, 74, 75, 71, 69, 72, 76, 73]), [1, 1, 4, 2, 1, 1, 0, 0])
check(daily_temperatures([30, 40, 50, 60]), [1, 1, 1, 0])
check(daily_temperatures([30, 60, 90]), [1, 1, 0])
```

## Evaluate Reverse Polish Notation
> difficulty: Medium | tags: stack | leetcode: 150

Evaluate tokens like `["2", "1", "+", "3", "*"]`. Division truncates toward zero.

```python starter
def eval_rpn(tokens):
    pass
```

```python solution
def eval_rpn(tokens):
    stack = []
    for tok in tokens:
        if tok in "+-*/" and len(tok) == 1:
            b, a = stack.pop(), stack.pop()
            if tok == "+": stack.append(a + b)
            elif tok == "-": stack.append(a - b)
            elif tok == "*": stack.append(a * b)
            else: stack.append(int(a / b))     # truncate toward zero
        else:
            stack.append(int(tok))
    return stack[0]
```

```python tests
check(eval_rpn(["2", "1", "+", "3", "*"]), 9)
check(eval_rpn(["4", "13", "5", "/", "+"]), 6)
check(eval_rpn(["10", "6", "9", "3", "+", "-11", "*", "/", "*", "17", "+", "5", "+"]), 22)
```

## Min Stack
> difficulty: Medium | tags: stack, design | leetcode: 155

Design a stack with `push`, `pop`, `top` and `get_min`, each O(1).

```python starter
class MinStack:
    def __init__(self):
        pass

    def push(self, x):
        pass

    def pop(self):
        pass

    def top(self):
        pass

    def get_min(self):
        pass
```

```python solution
class MinStack:
    def __init__(self):
        self.items = []              # (value, min so far)

    def push(self, x):
        m = min(x, self.items[-1][1]) if self.items else x
        self.items.append((x, m))

    def pop(self):
        self.items.pop()

    def top(self):
        return self.items[-1][0]

    def get_min(self):
        return self.items[-1][1]
```

```python tests
s = MinStack()
s.push(-2); s.push(0); s.push(-3)
check(s.get_min(), -3)
s.pop()
check(s.top(), 0)
check(s.get_min(), -2)
```

## Largest Rectangle in Histogram
> difficulty: Hard | tags: monotonic stack | leetcode: 84

Return the area of the largest rectangle that fits under the histogram `heights`.

```python starter
def largest_rectangle_area(heights):
    pass
```

```python solution
def largest_rectangle_area(heights):
    stack, best = [], 0              # indices with increasing heights
    for i, h in enumerate(heights + [0]):
        while stack and heights[stack[-1]] >= h:
            j = stack.pop()
            left = stack[-1] + 1 if stack else 0
            best = max(best, heights[j] * (i - left))
        stack.append(i)
    return best
```

```python tests
check(largest_rectangle_area([2, 1, 5, 6, 2, 3]), 10)
check(largest_rectangle_area([2, 4]), 4)
check(largest_rectangle_area([1, 1, 1, 1]), 4)
```
