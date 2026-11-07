# title: Streaming pipeline (live)
# A generator pipeline: source -> filter -> window -> sink. Each stage pulls one event at a time,
# so memory stays flat however long the stream runs. Watch the output arrive as events flow.
from collections import Counter, deque

from dc import clickstream, stream


def source(n=60):
    return stream(clickstream(n, users=4, seed=7, max_gap=8), delay=0.05)


def only_pages(events, pages):
    return (e for e in events if e["page"] in pages)


def sliding_counts(events, seconds):
    """Yields (ts, counts per page) over the last `seconds` of event time."""
    window, counts = deque(), Counter()
    for e in events:
        window.append(e)
        counts[e["page"]] += 1
        while window[0]["ts"] <= e["ts"] - seconds:
            counts[window.popleft()["page"]] -= 1
        yield e["ts"], +counts          # unary + drops zero counts


for ts, counts in sliding_counts(only_pages(source(), {"item", "cart", "checkout"}), seconds=30):
    funnel = " ".join(f"{p}={counts.get(p, 0)}" for p in ("item", "cart", "checkout"))
    print(f"t={ts % 10_000:>4}  {funnel}")
