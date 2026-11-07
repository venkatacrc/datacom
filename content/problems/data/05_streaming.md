---
track: python-data
section: Streaming
---

## Moving Average of a Stream
> difficulty: Easy | tags: generator, deque | source: streaming

Write a generator that reads numbers from any iterable (possibly endless) and yields the mean of the last `k`
values after each one (fewer at the start). O(1) per item. Try it in the playground on
`stream(range(20), delay=0.1)` and watch the output arrive live.

```python starter
def moving_average(numbers, k):
    pass
```

```python solution
from collections import deque

def moving_average(numbers, k):
    window, total = deque(), 0.0
    for x in numbers:
        window.append(x)
        total += x
        if len(window) > k:
            total -= window.popleft()
        yield total / len(window)
```

```python tests
check(list(moving_average([1, 2, 3, 4, 5], 3)), [1.0, 1.5, 2.0, 3.0, 4.0])
import itertools
check(take(moving_average(itertools.count(1), 2), 4), [1.0, 1.5, 2.5, 3.5], "works on an endless stream")
check_true(hasattr(moving_average([], 1), "__next__"), "is a generator")
```

## Running Median of a Stream
> difficulty: Hard | tags: two heaps, generator | source: streaming

Yield the median after each number arrives. Same two-heap idea as *Find Median from Data Stream*, as a generator.

```python starter
def running_median(numbers):
    pass
```

```python solution
import heapq

def running_median(numbers):
    low, high = [], []          # max-heap (negated) and min-heap
    for x in numbers:
        heapq.heappush(low, -x)
        heapq.heappush(high, -heapq.heappop(low))
        if len(high) > len(low):
            heapq.heappush(low, -heapq.heappop(high))
        yield float(-low[0]) if len(low) > len(high) else (-low[0] + high[0]) / 2
```

```python tests
check(list(running_median([5, 15, 1, 3])), [5.0, 10.0, 5.0, 4.0])
check(list(running_median([])), [])
```

## Tumbling Window Counts (event time)
> difficulty: Medium | tags: windowing, event time | source: Flink/Spark

Events `{"ts", "user", …}` arrive in time order. Count events per user in fixed `size`-second windows
`[start, start + size)` aligned to multiples of `size`. Yield `(window_start, {user: count})` as soon as a window
closes (when an event for a later window arrives), and flush the last window at the end of the stream.

```python starter
def tumbling_counts(events, size):
    pass
```

```python solution
from collections import Counter

def tumbling_counts(events, size):
    current, counts = None, Counter()
    for e in events:
        start = e["ts"] - e["ts"] % size
        if current is not None and start != current:
            yield current, dict(counts)
            counts = Counter()
        current = start
        counts[e["user"]] += 1
    if current is not None:
        yield current, dict(counts)
```

```python tests
ev = [{"ts": 0, "user": "a"}, {"ts": 3, "user": "b"}, {"ts": 9, "user": "a"},
      {"ts": 10, "user": "a"}, {"ts": 25, "user": "b"}]
check(list(tumbling_counts(ev, 10)), [(0, {"a": 2, "b": 1}), (10, {"a": 1}), (20, {"b": 1})])
out = list(tumbling_counts(clickstream(500, seed=2), 60))
check(sum(sum(c.values()) for _, c in out), 500, "every generated click is counted once")
check_true(all(s % 60 == 0 for s, _ in out), "windows align to 60 s")
```

## Sessionize Clicks
> difficulty: Medium | tags: sessions, state per key | source: analytics

A session is a run of one user's events with no gap longer than `gap` seconds. Given time-ordered events, return a
list of sessions `{"user", "start", "end", "events"}` sorted by `(start, user)`.

```python starter
def sessionize(events, gap):
    pass
```

```python solution
def sessionize(events, gap):
    open_sessions, done = {}, []
    for e in events:
        s = open_sessions.get(e["user"])
        if s and e["ts"] - s["end"] <= gap:
            s["end"] = e["ts"]
            s["events"] += 1
        else:
            if s:
                done.append(s)
            open_sessions[e["user"]] = {"user": e["user"], "start": e["ts"], "end": e["ts"], "events": 1}
    done += open_sessions.values()
    return sorted(done, key=lambda s: (s["start"], s["user"]))
```

```python tests
ev = [{"ts": 0, "user": "a"}, {"ts": 5, "user": "b"}, {"ts": 20, "user": "a"},
      {"ts": 100, "user": "a"}, {"ts": 101, "user": "b"}]
check(sessionize(ev, 30), [
    {"user": "a", "start": 0, "end": 20, "events": 2},
    {"user": "b", "start": 5, "end": 5, "events": 1},
    {"user": "a", "start": 100, "end": 100, "events": 1},
    {"user": "b", "start": 101, "end": 101, "events": 1}])
check(sessionize([], 30), [])
```

## Sliding-Window Rate Limiter
> difficulty: Medium | tags: rate limiting, deque | source: system design

`allow(user, ts)` returns True if the request is allowed: each user may make at most `limit` requests in any
`window`-second span `(ts - window, ts]`. Denied requests don't count.

```python starter
class RateLimiter:
    def __init__(self, limit, window):
        pass

    def allow(self, user, ts):
        pass
```

```python solution
from collections import defaultdict, deque

class RateLimiter:
    def __init__(self, limit, window):
        self.limit, self.window = limit, window
        self.log = defaultdict(deque)          # user -> timestamps of allowed requests

    def allow(self, user, ts):
        q = self.log[user]
        while q and q[0] <= ts - self.window:
            q.popleft()
        if len(q) < self.limit:
            q.append(ts)
            return True
        return False
```

```python tests
rl = RateLimiter(limit=3, window=10)
check([rl.allow("a", t) for t in (0, 1, 2, 3)], [True, True, True, False])
check(rl.allow("b", 3), True, "limits are per user")
check(rl.allow("a", 10), True, "the request at t=0 has expired")
check(rl.allow("a", 10), False)
```

## Deduplicate Within a Time Window
> difficulty: Medium | tags: idempotency, TTL | source: streaming

At-least-once delivery means repeats. Yield each event `{"id", "ts"}` unless the same `id` was already yielded
within the last `ttl` seconds (`ts - first_ts < ttl`). Keep memory bounded: forget ids older than `ttl`.

```python starter
def dedupe(events, ttl):
    pass
```

```python solution
from collections import deque

def dedupe(events, ttl):
    seen, order = {}, deque()          # id -> ts yielded; (ts, id) in arrival order
    for e in events:
        while order and order[0][0] <= e["ts"] - ttl:
            ts, i = order.popleft()
            if seen.get(i) == ts:
                del seen[i]
        if e["id"] in seen:
            continue
        seen[e["id"]] = e["ts"]
        order.append((e["ts"], e["id"]))
        yield e
```

```python tests
ev = [{"id": "x", "ts": 0}, {"id": "x", "ts": 3}, {"id": "y", "ts": 4}, {"id": "x", "ts": 12}, {"id": "y", "ts": 5}]
check([(e["id"], e["ts"]) for e in dedupe(ev, 10)], [("x", 0), ("y", 4), ("x", 12)])
def naive(events, ttl):
    last, out = {}, []
    for e in events:
        if e["id"] not in last or e["ts"] - last[e["id"]] >= ttl:
            last[e["id"]] = e["ts"]
            out.append(e["ts"])
    return out
long = [{"id": i % 3, "ts": i} for i in range(10_000)]
check([e["ts"] for e in dedupe(iter(long), 5)], naive(long, 5), "10,000 events match a simple reference")
```

## Reservoir Sampling
> difficulty: Medium | tags: sampling, probability | source: streaming

Return `k` items chosen uniformly at random from a stream of unknown length, in one pass and O(k) memory
(Algorithm R). Use the `rng` you're given (a `random.Random`).

```python starter
def reservoir_sample(stream, k, rng):
    pass
```

```python solution
def reservoir_sample(stream, k, rng):
    sample = []
    for i, x in enumerate(stream):
        if i < k:
            sample.append(x)
        else:
            j = rng.randint(0, i)        # keep x with probability k / (i + 1)
            if j < k:
                sample[j] = x
    return sample
```

```python tests
import random
check(sorted(reservoir_sample(range(3), 5, random.Random(0))), [0, 1, 2], "stream shorter than k")
s = reservoir_sample(iter(range(1000)), 10, random.Random(1))
check_true(len(s) == 10 and len(set(s)) == 10 and all(0 <= x < 1000 for x in s), "10 distinct items")
hits = [0] * 10
rng = random.Random(42)
for _ in range(20_000):
    for x in reservoir_sample(range(10), 3, rng):
        hits[x] += 1
check_true(all(abs(h / 20_000 - 0.3) < 0.02 for h in hits), "each item kept ~30% of the time")
```

## Heavy Hitters (Misra–Gries)
> difficulty: Hard | tags: sketch, frequent items | source: streaming

With only `k - 1` counters, find candidates for every item that occurs more than `n / k` times in a stream of length
`n`. Return the counter dict. Every true heavy hitter must be a key (some extra keys are fine).

```python starter
def misra_gries(stream, k):
    pass
```

```python solution
def misra_gries(stream, k):
    counters = {}
    for x in stream:
        if x in counters:
            counters[x] += 1
        elif len(counters) < k - 1:
            counters[x] = 1
        else:
            for key in list(counters):       # decrement everyone; drop zeros
                counters[key] -= 1
                if counters[key] == 0:
                    del counters[key]
    return counters
```

```python tests
import random
from collections import Counter
rng = random.Random(3)
data = [rng.choice("ab") if rng.random() < 0.6 else rng.choice("cdefghijklmnop") for _ in range(10_000)]
mg = misra_gries(iter(data), k=5)
heavy = {x for x, c in Counter(data).items() if c > len(data) / 5}
check_true(heavy <= set(mg), f"keeps every heavy hitter {sorted(heavy)}")
check_true(len(mg) <= 4, "uses at most k-1 counters")
```

## Count-Min Sketch
> difficulty: Hard | tags: sketch, hashing | source: streaming

Implement `CountMin(width, depth, seed)` with `add(item, count=1)` and `estimate(item)`. Estimates may overcount
but never undercount. Hash with `hash((seed, row, item))` so it's deterministic within a run.

```python starter
class CountMin:
    def __init__(self, width, depth, seed=0):
        pass

    def add(self, item, count=1):
        pass

    def estimate(self, item):
        pass
```

```python solution
class CountMin:
    def __init__(self, width, depth, seed=0):
        self.w, self.d, self.seed = width, depth, seed
        self.rows = [[0] * width for _ in range(depth)]

    def _cols(self, item):
        return [hash((self.seed, r, item)) % self.w for r in range(self.d)]

    def add(self, item, count=1):
        for r, c in enumerate(self._cols(item)):
            self.rows[r][c] += count

    def estimate(self, item):
        return min(self.rows[r][c] for r, c in enumerate(self._cols(item)))
```

```python tests
from collections import Counter
cm = CountMin(width=200, depth=4)
words = [f"w{i % 300}" for i in range(30_000)] + ["hot"] * 5_000
for w in words:
    cm.add(w)
truth = Counter(words)
check_true(all(cm.estimate(w) >= c for w, c in truth.items()), "never undercounts")
check_true(cm.estimate("hot") - 5_000 < 1_000, "close on the heavy item")
check(cm.estimate("never-seen") >= 0, True)
```

## Online Mean, Variance and Anomalies (Welford)
> difficulty: Medium | tags: online statistics | source: monitoring

Yield `(t, value)` for each sensor reading whose z-score against all *previous* valid readings exceeds `z`, once at
least `warmup` readings have been seen. Skip `None` values. Use Welford's update for mean and variance (no lists).

```python starter
def anomalies(readings, z=4.0, warmup=20):
    pass
```

```python solution
import math

def anomalies(readings, z=4.0, warmup=20):
    n, mean, m2 = 0, 0.0, 0.0
    for r in readings:
        x = r["value"]
        if x is None:
            continue
        if n >= warmup:
            sd = math.sqrt(m2 / (n - 1))
            if sd > 0 and abs(x - mean) / sd > z:
                yield r["t"], x
        n += 1
        delta = x - mean
        mean += delta / n
        m2 += delta * (x - mean)
```

```python tests
flat = [{"t": i, "value": 10.0 + (i % 3) * 0.1} for i in range(50)]
spiky = flat[:30] + [{"t": 30, "value": 50.0}] + [{"t": 31, "value": None}] + flat[32:]
check(list(anomalies(spiky)), [(30, 50.0)])
found = list(anomalies(sensor(500, seed=4, outlier_rate=0.03)))
check_true(len(found) >= 5 and all(abs(v - 20) > 10 for _, v in found), "catches the generated spikes only")
```

## Merge K Sorted Streams Lazily
> difficulty: Medium | tags: heap, generators | source: streaming

Merge sorted iterables (possibly endless) into one sorted generator that reads each input only as needed.
Don't use `heapq.merge`.

```python starter
def merge_streams(*streams):
    pass
```

```python solution
import heapq

def merge_streams(*streams):
    its = [iter(s) for s in streams]
    heap = []
    for i, it in enumerate(its):
        for x in it:
            heap.append((x, i))
            break
    heapq.heapify(heap)
    while heap:
        x, i = heap[0]
        yield x
        for nxt in its[i]:
            heapq.heapreplace(heap, (nxt, i))
            break
        else:
            heapq.heappop(heap)
```

```python tests
check(list(merge_streams([1, 4, 7], [2, 5, 8], [3, 6, 9])), list(range(1, 10)))
check(list(merge_streams([], [1], [])), [1])
import itertools
evens, odds = itertools.count(0, 2), itertools.count(1, 2)
check(take(merge_streams(evens, odds), 6), [0, 1, 2, 3, 4, 5], "endless inputs")
```

## Windows with Watermarks and Late Events
> difficulty: Hard | tags: event time, watermark | source: Flink/Beam

Events can arrive out of order. Track the watermark = (largest `ts` seen) − `max_delay`. Sum `value` per tumbling
window of `size` seconds. Emit `(window_start, total)` once the watermark reaches the window end. Events for windows
already emitted are late: count them in `late` instead. At end of stream, emit remaining windows in order.
Return `(emitted, late)`.

```python starter
def watermark_windows(events, size, max_delay):
    pass
```

```python solution
def watermark_windows(events, size, max_delay):
    open_w, emitted, late = {}, [], 0
    closed_up_to = None          # every window starting before this has been emitted
    max_ts = None
    for e in events:
        start = e["ts"] - e["ts"] % size
        if closed_up_to is not None and start < closed_up_to:
            late += 1
            continue
        open_w[start] = open_w.get(start, 0) + e["value"]
        max_ts = e["ts"] if max_ts is None else max(max_ts, e["ts"])
        watermark = max_ts - max_delay
        for s in sorted(open_w):
            if s + size <= watermark:
                emitted.append((s, open_w.pop(s)))
                closed_up_to = s + size
            else:
                break
    for s in sorted(open_w):
        emitted.append((s, open_w.pop(s)))
    return emitted, late
```

```python tests
ev = [{"ts": 1, "value": 1}, {"ts": 12, "value": 2}, {"ts": 4, "value": 3},   # 4 is late but within delay
      {"ts": 25, "value": 4}, {"ts": 2, "value": 5},                           # 2 is too late: window 0 closed
      {"ts": 31, "value": 6}]
check(watermark_windows(ev, size=10, max_delay=5), ([(0, 4), (10, 2), (20, 4), (30, 6)], 1))
check(watermark_windows([], 10, 5), ([], 0))
```

## Stream–Stream Join Within a Window
> difficulty: Hard | tags: join, state, time window | source: streaming

Two time-ordered streams were merged into one: `{"kind": "order"|"payment", "id", "ts"}`. Yield
`(id, order_ts, payment_ts)` whenever an order and a payment with the same `id` are at most `within` seconds apart,
as soon as the second one arrives. Evict state older than `within` so memory stays bounded.

```python starter
def join_orders_payments(events, within):
    pass
```

```python solution
from collections import deque

def join_orders_payments(events, within):
    state = {"order": {}, "payment": {}}      # kind -> id -> ts
    expiry = deque()                          # (ts, kind, id)
    for e in events:
        while expiry and expiry[0][0] < e["ts"] - within:
            ts, kind, i = expiry.popleft()
            if state[kind].get(i) == ts:
                del state[kind][i]
        other = "payment" if e["kind"] == "order" else "order"
        if e["id"] in state[other]:
            t = state[other].pop(e["id"])
            yield (e["id"], t, e["ts"]) if other == "order" else (e["id"], e["ts"], t)
        else:
            state[e["kind"]][e["id"]] = e["ts"]
            expiry.append((e["ts"], e["kind"], e["id"]))
```

```python tests
ev = [{"kind": "order", "id": 1, "ts": 0}, {"kind": "order", "id": 2, "ts": 1},
      {"kind": "payment", "id": 1, "ts": 5}, {"kind": "payment", "id": 3, "ts": 6},
      {"kind": "order", "id": 3, "ts": 8}, {"kind": "payment", "id": 2, "ts": 40}]
check(list(join_orders_payments(ev, within=10)), [(1, 0, 5), (3, 8, 6)])
```
