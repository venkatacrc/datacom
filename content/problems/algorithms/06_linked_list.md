---
track: algorithms
section: Linked lists
---

## Reverse Linked List
> difficulty: Easy | tags: linked list | leetcode: 206

Reverse a singly linked list and return the new head. `ListNode`, `make_list` and `list_values` come from `dc`.

```python starter
from dc import ListNode

def reverse_list(head):
    pass
```

```python solution
from dc import ListNode

def reverse_list(head):
    prev = None
    while head:
        head.next, prev, head = prev, head, head.next
    return prev
```

```python tests
check(list_values(reverse_list(make_list([1, 2, 3, 4, 5]))), [5, 4, 3, 2, 1])
check(list_values(reverse_list(make_list([1, 2]))), [2, 1])
check(list_values(reverse_list(None)), [])
```

## Merge Two Sorted Lists
> difficulty: Easy | tags: linked list, two pointers | leetcode: 21

Splice two sorted lists into one sorted list and return its head.

```python starter
from dc import ListNode

def merge_two_lists(a, b):
    pass
```

```python solution
from dc import ListNode

def merge_two_lists(a, b):
    dummy = tail = ListNode()
    while a and b:
        if a.val <= b.val:
            tail.next, a = a, a.next
        else:
            tail.next, b = b, b.next
        tail = tail.next
    tail.next = a or b
    return dummy.next
```

```python tests
check(list_values(merge_two_lists(make_list([1, 2, 4]), make_list([1, 3, 4]))), [1, 1, 2, 3, 4, 4])
check(list_values(merge_two_lists(None, None)), [])
check(list_values(merge_two_lists(None, make_list([0]))), [0])
```

## Linked List Cycle
> difficulty: Easy | tags: fast & slow pointers | leetcode: 141

Does the list loop back on itself? Use O(1) memory (Floyd's tortoise and hare).

```python starter
def has_cycle(head):
    pass
```

```python solution
def has_cycle(head):
    slow = fast = head
    while fast and fast.next:
        slow, fast = slow.next, fast.next.next
        if slow is fast:
            return True
    return False
```

```python tests
head = make_list([3, 2, 0, -4]); head.next.next.next.next = head.next
check(has_cycle(head), True, "tail points at node 1")
check(has_cycle(make_list([1, 2])), False)
check(has_cycle(None), False)
```

## Remove Nth Node From End
> difficulty: Medium | tags: two pointers | leetcode: 19

Remove the `n`-th node from the end in one pass and return the head.

```python starter
from dc import ListNode

def remove_nth_from_end(head, n):
    pass
```

```python solution
from dc import ListNode

def remove_nth_from_end(head, n):
    dummy = ListNode(0, head)
    fast = slow = dummy
    for _ in range(n + 1):           # open a gap of n nodes
        fast = fast.next
    while fast:
        fast, slow = fast.next, slow.next
    slow.next = slow.next.next
    return dummy.next
```

```python tests
check(list_values(remove_nth_from_end(make_list([1, 2, 3, 4, 5]), 2)), [1, 2, 3, 5])
check(list_values(remove_nth_from_end(make_list([1]), 1)), [])
check(list_values(remove_nth_from_end(make_list([1, 2]), 2)), [2])
```

## LRU Cache
> difficulty: Medium | tags: hash map, doubly linked list, design | leetcode: 146

Build a cache with `get(key)` (returns -1 when missing) and `put(key, value)`, both O(1).
When full, `put` evicts the least recently used key. Try it without `OrderedDict` too.

```python starter
class LRUCache:
    def __init__(self, capacity):
        pass

    def get(self, key):
        pass

    def put(self, key, value):
        pass
```

```python solution
class LRUCache:
    class Node:
        __slots__ = ("key", "val", "prev", "next")

        def __init__(self, key=0, val=0):
            self.key, self.val, self.prev, self.next = key, val, None, None

    def __init__(self, capacity):
        self.cap = capacity
        self.map = {}
        self.head, self.tail = self.Node(), self.Node()   # sentinels: head.next is the oldest
        self.head.next, self.tail.prev = self.tail, self.head

    def _unlink(self, node):
        node.prev.next, node.next.prev = node.next, node.prev

    def _append(self, node):
        node.prev, node.next = self.tail.prev, self.tail
        self.tail.prev.next = node
        self.tail.prev = node

    def get(self, key):
        node = self.map.get(key)
        if not node:
            return -1
        self._unlink(node)
        self._append(node)
        return node.val

    def put(self, key, value):
        if key in self.map:
            self._unlink(self.map[key])
        node = self.map[key] = self.Node(key, value)
        self._append(node)
        if len(self.map) > self.cap:
            oldest = self.head.next
            self._unlink(oldest)
            del self.map[oldest.key]
```

```python tests
c = LRUCache(2)
c.put(1, 1); c.put(2, 2)
check(c.get(1), 1)
c.put(3, 3)                     # evicts 2
check(c.get(2), -1, "2 was evicted")
c.put(4, 4)                     # evicts 1
check(c.get(1), -1, "1 was evicted")
check([c.get(3), c.get(4)], [3, 4])
c.put(3, 30)
check(c.get(3), 30, "update keeps the key")
```
