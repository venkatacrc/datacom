---
track: algorithms
section: Tries & bits
---

## Implement a Trie
> difficulty: Medium | tags: trie, design | leetcode: 208

Support `insert(word)`, `search(word)` (whole word) and `starts_with(prefix)`.

```python starter
class Trie:
    def __init__(self):
        pass

    def insert(self, word):
        pass

    def search(self, word):
        pass

    def starts_with(self, prefix):
        pass
```

```python solution
class Trie:
    def __init__(self):
        self.root = {}

    def insert(self, word):
        node = self.root
        for ch in word:
            node = node.setdefault(ch, {})
        node["$"] = True                  # end-of-word marker

    def _walk(self, s):
        node = self.root
        for ch in s:
            if ch not in node:
                return None
            node = node[ch]
        return node

    def search(self, word):
        node = self._walk(word)
        return bool(node and node.get("$"))

    def starts_with(self, prefix):
        return self._walk(prefix) is not None
```

```python tests
t = Trie()
t.insert("apple")
check(t.search("apple"), True)
check(t.search("app"), False)
check(t.starts_with("app"), True)
t.insert("app")
check(t.search("app"), True)
check(t.starts_with("b"), False)
```

## Autocomplete Top 3
> difficulty: Medium | tags: trie, sorting | leetcode: 1268

After each character typed of `query`, return up to three `products` with that prefix, in lexicographic order.

```python starter
def suggested_products(products, query):
    pass
```

```python solution
import bisect

def suggested_products(products, query):
    products = sorted(products)
    out, prefix = [], ""
    for ch in query:
        prefix += ch
        i = bisect.bisect_left(products, prefix)
        out.append([p for p in products[i:i + 3] if p.startswith(prefix)])
    return out
```

```python tests
check(suggested_products(["mobile", "mouse", "moneypot", "monitor", "mousepad"], "mouse"),
      [["mobile", "moneypot", "monitor"], ["mobile", "moneypot", "monitor"],
       ["mouse", "mousepad"], ["mouse", "mousepad"], ["mouse", "mousepad"]])
check(suggested_products(["havana"], "tatiana"), [[], [], [], [], [], [], []])
```

## Single Number
> difficulty: Easy | tags: XOR | leetcode: 136

Every value appears twice except one. Find it in O(n) time and O(1) space.

```python starter
def single_number(nums):
    pass
```

```python solution
from functools import reduce
from operator import xor

def single_number(nums):
    return reduce(xor, nums, 0)       # pairs cancel: x ^ x == 0
```

```python tests
check(single_number([2, 2, 1]), 1)
check(single_number([4, 1, 2, 1, 2]), 4)
check(single_number([-7]), -7)
```

## Counting Bits
> difficulty: Easy | tags: bits, DP | leetcode: 338

Return `[popcount(0), popcount(1), …, popcount(n)]` in O(n).

```python starter
def count_bits(n):
    pass
```

```python solution
def count_bits(n):
    out = [0] * (n + 1)
    for i in range(1, n + 1):
        out[i] = out[i >> 1] + (i & 1)
    return out
```

```python tests
check(count_bits(2), [0, 1, 1])
check(count_bits(5), [0, 1, 1, 2, 1, 2])
check(count_bits(0), [0])
```

## Reverse Bits
> difficulty: Easy | tags: bits | leetcode: 190

Reverse the bits of a 32-bit unsigned integer.

```python starter
def reverse_bits(n):
    pass
```

```python solution
def reverse_bits(n):
    out = 0
    for _ in range(32):
        out = (out << 1) | (n & 1)
        n >>= 1
    return out
```

```python tests
check(reverse_bits(0b00000010100101000001111010011100), 964176192)
check(reverse_bits(0b11111111111111111111111111111101), 3221225471)
check(reverse_bits(1), 2 ** 31)
```
