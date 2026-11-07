"""Datacom helpers, available to every problem and playground run.

    from dc import check, stream, clickstream, table

Tests:      check, check_true, check_raises, deep_sorted, run_tests, report
Structures: ListNode, TreeNode, make_list, list_values, make_tree, tree_values
Data:       stream, take, clickstream, ticks, sensor, orders, table, Timer
"""
import ast
import itertools
import json
import math
import random
import sys
import time
import traceback

__all__ = [
    "check", "check_true", "check_raises", "deep_sorted", "run_tests", "report",
    "ListNode", "TreeNode", "make_list", "list_values", "make_tree", "tree_values",
    "stream", "take", "clickstream", "ticks", "sensor", "orders", "table", "Timer", "pause",
]

_results = []


# ---------------------------------------------------------------- checks

def _same(a, b, tol):
    if hasattr(a, "to_dict") and hasattr(b, "to_dict") and hasattr(a, "equals"):
        try:
            import pandas as pd
            if isinstance(a, pd.DataFrame):
                pd.testing.assert_frame_equal(a.reset_index(drop=True), b.reset_index(drop=True),
                                              check_dtype=False, atol=tol)
            else:
                pd.testing.assert_series_equal(a.reset_index(drop=True), b.reset_index(drop=True),
                                               check_dtype=False, check_names=False, atol=tol)
            return True
        except AssertionError:
            return False
    if hasattr(a, "shape") or hasattr(b, "shape"):
        import numpy as np
        a, b = np.asarray(a), np.asarray(b)
        if a.shape != b.shape:
            return False
        if a.dtype.kind in "fc" or b.dtype.kind in "fc":
            return bool(np.allclose(a, b, rtol=tol, atol=tol, equal_nan=True))
        return bool((a == b).all())
    if isinstance(a, bool) or isinstance(b, bool):
        return a == b
    if isinstance(a, (int, float)) and isinstance(b, (int, float)):
        if isinstance(a, float) or isinstance(b, float):
            if math.isnan(a) and math.isnan(b):
                return True
            return math.isclose(a, b, rel_tol=tol, abs_tol=tol)
        return a == b
    if isinstance(a, (list, tuple)) and isinstance(b, (list, tuple)):
        return len(a) == len(b) and all(_same(x, y, tol) for x, y in zip(a, b))
    if isinstance(a, dict) and isinstance(b, dict):
        return a.keys() == b.keys() and all(_same(a[k], b[k], tol) for k in a)
    return a == b


def _short(x, n=300):
    s = repr(x)
    return s if len(s) <= n else s[:n] + " …"


def check(actual, expected, label=None, tol=1e-6):
    """Passes when actual equals expected. Floats, NumPy arrays and DataFrames compare with tolerance."""
    ok = _same(actual, expected, tol)
    _results.append(ok)
    name = label or f"test {len(_results)}"
    if ok:
        print(f"  ✓ {name}")
    else:
        print(f"  ✗ {name}\n      expected: {_short(expected)}\n      got:      {_short(actual)}")
    return ok


def check_true(condition, label=None):
    ok = bool(condition)
    _results.append(ok)
    print(f"  {'✓' if ok else '✗'} {label or f'test {len(_results)}'}")
    return ok


def check_raises(fn, exc=Exception, label=None):
    try:
        fn()
    except exc:
        return check_true(True, label)
    except Exception as e:  # noqa: BLE001
        print(f"      raised {type(e).__name__} instead of {exc.__name__}")
    return check_true(False, label)


def deep_sorted(x):
    """Sorts nested lists so answers can be compared regardless of order."""
    if isinstance(x, (list, tuple, set)):
        items = [deep_sorted(i) for i in x]
        try:
            return sorted(items)
        except TypeError:
            return sorted(items, key=repr)
    return x


def run_tests(src, g, filename="tests"):
    """Runs each top-level statement of the tests on its own, so one crash doesn't hide the rest."""
    module = sys.modules[__name__]
    for name in __all__:
        g.setdefault(name, getattr(module, name))
    try:
        tree = ast.parse(src, filename)
    except SyntaxError as e:
        print(f"  ✗ tests could not be parsed: {e}")
        _results.append(False)
        return report()
    for node in tree.body:
        code = compile(ast.Module(body=[node], type_ignores=[]), filename, "exec")
        try:
            exec(code, g)
        except Exception as e:  # noqa: BLE001
            _results.append(False)
            segment = (ast.get_source_segment(src, node) or "").strip().splitlines()
            first = segment[0][:80] if segment else "?"
            frames = [f for f in traceback.extract_tb(e.__traceback__) if f.filename not in (filename, __file__)]
            where = f" (line {frames[-1].lineno} of your code)" if frames else ""
            print(f"  ✗ {first}\n      raised {type(e).__name__}: {e}{where}")
    return report()


def report():
    passed, total = sum(_results), len(_results)
    if total:
        verdict = "All tests passed" if passed == total else f"{total - passed} of {total} failed"
        print(f"\n{passed}/{total} · {verdict}")
    sys.stdout.flush()
    print("__DC_RESULT__ " + json.dumps({"passed": passed, "total": total}))
    return passed == total


# ---------------------------------------------------------------- structures

class ListNode:
    def __init__(self, val=0, next=None):
        self.val, self.next = val, next

    def __repr__(self):
        return f"ListNode({list_values(self)})"


class TreeNode:
    def __init__(self, val=0, left=None, right=None):
        self.val, self.left, self.right = val, left, right

    def __repr__(self):
        return f"TreeNode({tree_values(self)})"


def make_list(values):
    head = None
    for v in reversed(list(values)):
        head = ListNode(v, head)
    return head


def list_values(head, limit=10_000):
    out = []
    while head is not None and len(out) < limit:
        out.append(head.val)
        head = head.next
    return out


def make_tree(values):
    """Builds a tree from level order with None for gaps: make_tree([3, 9, 20, None, None, 15, 7])."""
    values = list(values)
    if not values or values[0] is None:
        return None
    root = TreeNode(values[0])
    queue, i = [root], 1
    for node in queue:
        if i >= len(values):
            break
        if values[i] is not None:
            node.left = TreeNode(values[i])
            queue.append(node.left)
        i += 1
        if i < len(values) and values[i] is not None:
            node.right = TreeNode(values[i])
            queue.append(node.right)
        i += 1
    return root


def tree_values(root):
    out, queue = [], [root]
    for node in queue:
        out.append(node.val if node else None)
        if node:
            queue += [node.left, node.right]
    while out and out[-1] is None:
        out.pop()
    return out


# ---------------------------------------------------------------- data

def pause(seconds):
    """time.sleep that also paces output in the browser, where Python runs in a web worker."""
    if seconds <= 0:
        return
    if sys.platform == "emscripten":
        end = time.time() + seconds
        while time.time() < end:
            pass
    else:
        time.sleep(seconds)


def stream(items, delay=0.0):
    """Yields items one at a time, sleeping `delay` seconds before each, like reading a socket or a topic."""
    for x in items:
        pause(delay)
        yield x


def take(iterable, n):
    return list(itertools.islice(iterable, n))


def clickstream(n=200, users=8, seed=1, start=1_700_000_000, max_gap=30,
                pages=("home", "search", "item", "cart", "checkout")):
    """Synthetic web events in time order: {"ts", "user", "page", "ms"}."""
    rng = random.Random(seed)
    ts = start
    for _ in range(n):
        ts += rng.randint(0, max_gap)
        yield {"ts": ts, "user": f"u{rng.randrange(users)}", "page": rng.choice(pages),
               "ms": rng.randint(20, 2000)}


def ticks(n=200, symbols=("AAPL", "MSFT", "NVDA"), seed=1, start=1_700_000_000):
    """Synthetic trades: {"ts", "symbol", "price", "qty"} with a random walk per symbol."""
    rng = random.Random(seed)
    price = {s: 100.0 + 50 * i for i, s in enumerate(symbols)}
    ts = start
    for _ in range(n):
        ts += rng.randint(0, 3)
        s = rng.choice(symbols)
        price[s] = max(1.0, price[s] * (1 + rng.gauss(0, 0.002)))
        yield {"ts": ts, "symbol": s, "price": round(price[s], 2), "qty": rng.randint(1, 500)}


def sensor(n=200, seed=1, base=20.0, noise=0.5, outlier_rate=0.02, missing_rate=0.02):
    """Synthetic readings {"t", "value"}: noisy, with occasional spikes and None values."""
    rng = random.Random(seed)
    for t in range(n):
        r = rng.random()
        if r < missing_rate:
            v = None
        elif r < missing_rate + outlier_rate:
            v = round(base + rng.choice((-1, 1)) * rng.uniform(15, 30), 2)
        else:
            v = round(base + math.sin(t / 15) * 2 + rng.gauss(0, noise), 2)
        yield {"t": t, "value": v}


def orders(n=50, seed=1, customers=10,
           products=(("apple", "fruit", 0.5), ("banana", "fruit", 0.25), ("milk", "dairy", 3.0),
                     ("cheese", "dairy", 6.5), ("bread", "bakery", 2.75), ("bagel", "bakery", 1.25))):
    """A list of order rows: {"order_id", "customer", "product", "category", "qty", "price", "day"}."""
    rng = random.Random(seed)
    rows = []
    for i in range(n):
        name, cat, price = rng.choice(products)
        rows.append({"order_id": 1000 + i, "customer": f"c{rng.randrange(customers)}", "product": name,
                     "category": cat, "qty": rng.randint(1, 5), "price": price, "day": 1 + rng.randrange(7)})
    return rows


def table(rows, cols=None, limit=20):
    """Prints a list of dicts (or a DataFrame) as an aligned text table."""
    if hasattr(rows, "to_dict"):
        print(rows.head(limit).to_string())
        return
    rows = list(rows)
    if not rows:
        print("(no rows)")
        return
    cols = cols or list(rows[0].keys())
    shown = rows[:limit]
    width = {c: max(len(str(c)), *(len(str(r.get(c, ""))) for r in shown)) for c in cols}
    print("  ".join(str(c).ljust(width[c]) for c in cols))
    print("  ".join("-" * width[c] for c in cols))
    for r in shown:
        print("  ".join(str(r.get(c, "")).ljust(width[c]) for c in cols))
    if len(rows) > limit:
        print(f"… {len(rows) - limit} more rows")


class Timer:
    """with Timer("sort"): ...  prints how long the block took."""

    def __init__(self, label="elapsed"):
        self.label = label

    def __enter__(self):
        self.start = time.perf_counter()
        return self

    def __exit__(self, *exc):
        self.seconds = time.perf_counter() - self.start
        print(f"{self.label}: {self.seconds * 1000:.2f} ms")
