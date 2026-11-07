---
track: python-data
section: Batch · pure Python
---

## Group By and Aggregate
> difficulty: Easy | tags: group by, dict | source: data interview

`rows` are order dicts like `{"category": "fruit", "qty": 3, "price": 0.5}`. Return
`{category: {"orders": n, "units": total qty, "revenue": total qty × price}}` with revenue rounded to 2 places.
`dc.orders()` generates sample rows; try `table(orders(10))` in the playground.

```python starter
def revenue_by_category(rows):
    pass
```

```python solution
from collections import defaultdict

def revenue_by_category(rows):
    out = defaultdict(lambda: {"orders": 0, "units": 0, "revenue": 0.0})
    for r in rows:
        agg = out[r["category"]]
        agg["orders"] += 1
        agg["units"] += r["qty"]
        agg["revenue"] += r["qty"] * r["price"]
    return {k: {**v, "revenue": round(v["revenue"], 2)} for k, v in out.items()}
```

```python tests
rows = [{"category": "fruit", "qty": 3, "price": 0.5}, {"category": "dairy", "qty": 1, "price": 3.0},
        {"category": "fruit", "qty": 2, "price": 0.25}]
check(revenue_by_category(rows), {"fruit": {"orders": 2, "units": 5, "revenue": 2.0},
                                  "dairy": {"orders": 1, "units": 1, "revenue": 3.0}})
check(revenue_by_category([]), {})
big = revenue_by_category(orders(5000, seed=3))
check(sum(v["orders"] for v in big.values()), 5000, "5,000 generated orders")
```

## Top N per Group
> difficulty: Medium | tags: group by, heap | source: data interview

Return, for each `group_key` value, the `n` rows with the highest `score_key`, highest first, as `{group: [rows]}`.
Break ties by the order rows appeared.

```python starter
def top_n_per_group(rows, group_key, score_key, n):
    pass
```

```python solution
import heapq
from collections import defaultdict

def top_n_per_group(rows, group_key, score_key, n):
    groups = defaultdict(list)
    for i, r in enumerate(rows):
        groups[r[group_key]].append((r[score_key], -i, r))
    return {g: [r for _, _, r in heapq.nlargest(n, items, key=lambda t: (t[0], t[1]))]
            for g, items in groups.items()}
```

```python tests
rows = [{"dept": "a", "name": "x", "pay": 10}, {"dept": "a", "name": "y", "pay": 30},
        {"dept": "b", "name": "z", "pay": 20}, {"dept": "a", "name": "w", "pay": 30}]
out = top_n_per_group(rows, "dept", "pay", 2)
check([r["name"] for r in out["a"]], ["y", "w"], "ties keep input order")
check([r["name"] for r in out["b"]], ["z"])
```

## Hash Join: Inner and Left
> difficulty: Medium | tags: join, hash map | source: data engineering

Join two lists of dicts on `key`. `how="inner"` keeps matches; `how="left"` also keeps unmatched left rows,
filling right-only columns with `None`. Output rows merge both dicts (right wins on name clashes, except the key).
Keep left order, and for each left row the right matches in their order.

```python starter
def join(left, right, key, how="inner"):
    pass
```

```python solution
from collections import defaultdict

def join(left, right, key, how="inner"):
    index = defaultdict(list)                 # build side: hash the right table
    right_cols = []
    for r in right:
        index[r[key]].append(r)
        for c in r:
            if c not in right_cols:
                right_cols.append(c)
    out = []
    for l in left:                            # probe side
        matches = index.get(l[key])
        if matches:
            out += [{**l, **r} for r in matches]
        elif how == "left":
            out.append({**{c: None for c in right_cols if c != key}, **l})
    return out
```

```python tests
users = [{"id": 1, "name": "ann"}, {"id": 2, "name": "bob"}, {"id": 3, "name": "cy"}]
buys = [{"id": 1, "item": "pen"}, {"id": 1, "item": "ink"}, {"id": 3, "item": "cup"}]
check(join(users, buys, "id"), [{"id": 1, "name": "ann", "item": "pen"}, {"id": 1, "name": "ann", "item": "ink"},
                                {"id": 3, "name": "cy", "item": "cup"}])
check(join(users, buys, "id", how="left")[2], {"id": 2, "name": "bob", "item": None}, "unmatched left row")
check(len(join(users, buys, "id", how="left")), 4)
```

## Deduplicate, Keep the Latest
> difficulty: Easy | tags: dedupe, CDC | source: data engineering

Change-data-capture rows `{"id", "ts", ...}` arrive out of order. Keep only the newest row per `id` (largest `ts`),
returned sorted by `id`.

```python starter
def latest_per_id(rows):
    pass
```

```python solution
def latest_per_id(rows):
    best = {}
    for r in rows:
        if r["id"] not in best or r["ts"] > best[r["id"]]["ts"]:
            best[r["id"]] = r
    return [best[k] for k in sorted(best)]
```

```python tests
rows = [{"id": 2, "ts": 5, "v": "b1"}, {"id": 1, "ts": 9, "v": "a2"}, {"id": 1, "ts": 3, "v": "a1"},
        {"id": 2, "ts": 7, "v": "b2"}]
check([r["v"] for r in latest_per_id(rows)], ["a2", "b2"])
check(latest_per_id([]), [])
```

## Flatten Nested JSON
> difficulty: Medium | tags: recursion, JSON | source: data engineering

Flatten nested dicts into dotted keys. Lists become indexed keys: `{"a": [{"b": 1}]}` → `{"a.0.b": 1}`.
Empty dicts and lists stay as values.

```python starter
def flatten(obj):
    pass
```

```python solution
def flatten(obj, prefix=""):
    out = {}
    items = obj.items() if isinstance(obj, dict) else enumerate(obj)
    for k, v in items:
        key = f"{prefix}{k}"
        if isinstance(v, (dict, list)) and v:
            out.update(flatten(v, key + "."))
        else:
            out[key] = v
    return out
```

```python tests
check(flatten({"a": 1, "b": {"c": 2, "d": {"e": 3}}}), {"a": 1, "b.c": 2, "b.d.e": 3})
check(flatten({"user": {"tags": ["x", "y"]}, "items": [{"sku": 7}]}),
      {"user.tags.0": "x", "user.tags.1": "y", "items.0.sku": 7})
check(flatten({"empty": {}, "none": None, "list": []}), {"empty": {}, "none": None, "list": []})
```

## Parse Access Logs
> difficulty: Medium | tags: regex, parsing | source: data interview

Each line looks like `2026-11-07T10:00:01Z GET /api/items 200 123ms`. Skip malformed lines.
Return `{"requests": n, "errors": count of status >= 500, "p50_ms": …, "by_path": {path: count}}`, where p50 is the
nearest-rank median (`sorted(latencies)[ceil(0.5 * n) - 1]`).

```python starter
def summarize_logs(lines):
    pass
```

```python solution
import math
import re
from collections import Counter

LINE = re.compile(r"^\S+ (GET|POST|PUT|DELETE|PATCH) (\S+) (\d{3}) (\d+)ms$")

def summarize_logs(lines):
    latencies, paths, errors = [], Counter(), 0
    for line in lines:
        m = LINE.match(line.strip())
        if not m:
            continue
        _, path, status, ms = m.groups()
        paths[path] += 1
        errors += int(status) >= 500
        latencies.append(int(ms))
    latencies.sort()
    p50 = latencies[math.ceil(0.5 * len(latencies)) - 1] if latencies else None
    return {"requests": len(latencies), "errors": errors, "p50_ms": p50, "by_path": dict(paths)}
```

```python tests
logs = """2026-11-07T10:00:01Z GET /api/items 200 120ms
2026-11-07T10:00:02Z GET /api/items 200 80ms
garbage line
2026-11-07T10:00:03Z POST /api/cart 503 900ms
2026-11-07T10:00:04Z GET /health 200 2ms""".splitlines()
check(summarize_logs(logs), {"requests": 4, "errors": 1, "p50_ms": 80,
                             "by_path": {"/api/items": 2, "/api/cart": 1, "/health": 1}})
check(summarize_logs([])["requests"], 0)
```
