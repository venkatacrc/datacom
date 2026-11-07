---
track: algorithms
section: Trees
---

## Maximum Depth of Binary Tree
> difficulty: Easy | tags: tree, DFS | leetcode: 104

Return the number of nodes on the longest root-to-leaf path. Build trees with `make_tree([3, 9, 20, None, None, 15, 7])`.

```python starter
from dc import TreeNode

def max_depth(root):
    pass
```

```python solution
from dc import TreeNode

def max_depth(root):
    if not root:
        return 0
    return 1 + max(max_depth(root.left), max_depth(root.right))
```

```python tests
check(max_depth(make_tree([3, 9, 20, None, None, 15, 7])), 3)
check(max_depth(make_tree([1, None, 2])), 2)
check(max_depth(None), 0)
```

## Binary Tree Level Order Traversal
> difficulty: Medium | tags: tree, BFS | leetcode: 102

Return the values level by level, left to right: `[[3], [9, 20], [15, 7]]`.

```python starter
from dc import TreeNode

def level_order(root):
    pass
```

```python solution
from collections import deque

def level_order(root):
    if not root:
        return []
    out, q = [], deque([root])
    while q:
        level = []
        for _ in range(len(q)):        # exactly one level per pass
            node = q.popleft()
            level.append(node.val)
            if node.left: q.append(node.left)
            if node.right: q.append(node.right)
        out.append(level)
    return out
```

```python tests
check(level_order(make_tree([3, 9, 20, None, None, 15, 7])), [[3], [9, 20], [15, 7]])
check(level_order(make_tree([1])), [[1]])
check(level_order(None), [])
```

## Validate Binary Search Tree
> difficulty: Medium | tags: tree, DFS, bounds | leetcode: 98

Is every node strictly greater than everything in its left subtree and strictly smaller than everything in its right?

```python starter
def is_valid_bst(root):
    pass
```

```python solution
def is_valid_bst(root, lo=float("-inf"), hi=float("inf")):
    if not root:
        return True
    if not lo < root.val < hi:
        return False
    return is_valid_bst(root.left, lo, root.val) and is_valid_bst(root.right, root.val, hi)
```

```python tests
check(is_valid_bst(make_tree([2, 1, 3])), True)
check(is_valid_bst(make_tree([5, 1, 4, None, None, 3, 6])), False)
check(is_valid_bst(make_tree([5, 4, 6, None, None, 3, 7])), False, "3 sits right of 5")
check(is_valid_bst(make_tree([2, 2, 2])), False, "duplicates")
```

## Lowest Common Ancestor
> difficulty: Medium | tags: tree, DFS | leetcode: 236

Given the root and the *values* `p` and `q` of two nodes in a binary tree (values are unique), return the value of their lowest common ancestor.

```python starter
def lowest_common_ancestor(root, p, q):
    pass
```

```python solution
def lowest_common_ancestor(root, p, q):
    def walk(node):
        if not node or node.val in (p, q):
            return node
        left, right = walk(node.left), walk(node.right)
        if left and right:
            return node            # p and q are on different sides
        return left or right
    return walk(root).val
```

```python tests
t = make_tree([3, 5, 1, 6, 2, 0, 8, None, None, 7, 4])
check(lowest_common_ancestor(t, 5, 1), 3)
check(lowest_common_ancestor(t, 5, 4), 5)
check(lowest_common_ancestor(t, 7, 8), 3)
check(lowest_common_ancestor(t, 7, 4), 2)
```

## Kth Smallest Element in a BST
> difficulty: Medium | tags: BST, in-order | leetcode: 230

Return the `k`-th smallest value (1-indexed). Stop as soon as you find it.

```python starter
def kth_smallest(root, k):
    pass
```

```python solution
def kth_smallest(root, k):
    stack, node = [], root
    while True:
        while node:                  # iterative in-order traversal
            stack.append(node)
            node = node.left
        node = stack.pop()
        k -= 1
        if k == 0:
            return node.val
        node = node.right
```

```python tests
check(kth_smallest(make_tree([3, 1, 4, None, 2]), 1), 1)
check(kth_smallest(make_tree([5, 3, 6, 2, 4, None, None, 1]), 3), 3)
check(kth_smallest(make_tree([5, 3, 6, 2, 4, None, None, 1]), 6), 6)
```

## Serialize and Deserialize a Binary Tree
> difficulty: Hard | tags: tree, design | leetcode: 297

Write `serialize(root) -> str` and `deserialize(s) -> root` so that `deserialize(serialize(t))` rebuilds the same tree.

```python starter
from dc import TreeNode

def serialize(root):
    pass

def deserialize(s):
    pass
```

```python solution
from dc import TreeNode

def serialize(root):
    out = []
    def pre(node):
        if not node:
            out.append("#")
            return
        out.append(str(node.val))
        pre(node.left)
        pre(node.right)
    pre(root)
    return ",".join(out)

def deserialize(s):
    vals = iter(s.split(","))
    def build():
        v = next(vals)
        if v == "#":
            return None
        node = TreeNode(int(v))
        node.left = build()
        node.right = build()
        return node
    return build()
```

```python tests
for shape in ([1, 2, 3, None, None, 4, 5], [], [1], [5, 4, None, 3, None, 2, None, 1], [-1, 0, 1]):
    check(tree_values(deserialize(serialize(make_tree(shape)))), shape, f"round trip {shape}")
check_true(isinstance(serialize(make_tree([1, 2])), str), "serialize returns a string")
```
