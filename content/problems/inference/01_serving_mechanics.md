---
track: inference
section: Serving mechanics
---

## KV Cache Size
> difficulty: Easy | tags: KV cache, GQA | source: vllm_labs foundations

Return the KV cache size in GiB (2³⁰ bytes) for `batch` sequences of `seq_len` tokens: two tensors (K and V) per
layer, each `n_kv_heads × head_dim` per token, `bytes_per` bytes per element. With grouped-query attention
`n_kv_heads` is smaller than the number of query heads.

```python starter
def kv_cache_gib(layers, n_kv_heads, head_dim, seq_len, batch, bytes_per=2):
    pass
```

```python solution
def kv_cache_gib(layers, n_kv_heads, head_dim, seq_len, batch, bytes_per=2):
    return 2 * layers * n_kv_heads * head_dim * seq_len * batch * bytes_per / 2 ** 30
```

```python tests
check(kv_cache_gib(32, 32, 128, 4096, 1), 2.0, "Llama-2-7B, 4k tokens, bf16")
check(kv_cache_gib(32, 8, 128, 8192, 1), 1.0, "Llama-3-8B uses 8 KV heads")
check(kv_cache_gib(80, 8, 128, 8192, 16, bytes_per=1), 20.0, "70B, fp8 cache, batch 16")
```

## Incremental Decoding with a KV Cache
> difficulty: Medium | tags: KV cache, attention | source: nanogpt-kv-cache

`decode_step(x_t, cache, Wq, Wk, Wv)` takes one new token's hidden state `x_t (d,)`, appends its key and value to
`cache` (a dict with lists `"k"` and `"v"`), and returns the attention output for that token over all cached
positions. Running it token by token must reproduce full causal attention over the sequence.

```python starter
import numpy as np

def decode_step(x_t, cache, Wq, Wk, Wv):
    pass
```

```python solution
import numpy as np

def decode_step(x_t, cache, Wq, Wk, Wv):
    q = x_t @ Wq
    cache["k"].append(x_t @ Wk)          # only the new token's K and V are computed
    cache["v"].append(x_t @ Wv)
    K, V = np.stack(cache["k"]), np.stack(cache["v"])
    s = K @ q / np.sqrt(len(q))
    p = np.exp(s - s.max())
    return (p / p.sum()) @ V
```

```python tests
import numpy as np
rng = np.random.default_rng(0)
T, d = 7, 8
X = rng.normal(size=(T, d)); Wq, Wk, Wv = (rng.normal(size=(d, d)) for _ in range(3))
Q, K, V = X @ Wq, X @ Wk, X @ Wv
S = Q @ K.T / np.sqrt(d) + np.triu(np.full((T, T), -np.inf), 1)
P = np.exp(S - S.max(1, keepdims=True)); full = (P / P.sum(1, keepdims=True)) @ V
cache = {"k": [], "v": []}
inc = np.stack([decode_step(X[t], cache, Wq, Wk, Wv) for t in range(T)])
check(inc, full, "token-by-token equals full causal attention")
check(len(cache["k"]), T)
```

## Int8 Weight Quantization (per channel)
> difficulty: Medium | tags: quantization | source: quantization labs

Symmetric per-output-channel int8: for each row of `W`, `scale = max|row| / 127` (use 1 for an all-zero row),
`q = round(W / scale)` clipped to `[-127, 127]` as `int8`. Return `(q, scale)` with `scale` shaped `(rows, 1)`,
and write `dequantize(q, scale)`.

```python starter
import numpy as np

def quantize_int8(W):
    pass

def dequantize(q, scale):
    pass
```

```python solution
import numpy as np

def quantize_int8(W):
    W = np.asarray(W, float)
    amax = np.abs(W).max(axis=1, keepdims=True)
    scale = np.where(amax > 0, amax / 127, 1.0)
    q = np.clip(np.round(W / scale), -127, 127).astype(np.int8)
    return q, scale

def dequantize(q, scale):
    return q.astype(float) * scale
```

```python tests
import numpy as np
q, s = quantize_int8([[0.0, 0.5, -1.0], [2.0, 0.0, 0.0], [0.0, 0.0, 0.0]])
check(q.tolist(), [[0, 64, -127], [127, 0, 0], [0, 0, 0]])
check(q.dtype == np.int8, True, "int8 storage")
W = np.random.default_rng(5).normal(size=(64, 256))
q, s = quantize_int8(W)
err = np.abs(dequantize(q, s) - W).max(axis=1)
check_true((err <= s[:, 0] / 2 + 1e-12).all(), "error at most half a step per row")
```

## Paged KV Cache Allocator
> difficulty: Medium | tags: PagedAttention, memory management | source: vLLM

Manage `num_blocks` physical blocks of `block_size` tokens. `append(seq, n)` adds `n` tokens to sequence `seq`,
allocating new blocks (lowest free id first) only when the last block is full; it returns False and changes nothing
if there aren't enough free blocks. `free(seq)` returns its blocks. `table(seq)` returns its block ids in order.

```python starter
class PagedKV:
    def __init__(self, num_blocks, block_size):
        pass

    def append(self, seq, n):
        pass

    def free(self, seq):
        pass

    def table(self, seq):
        pass
```

```python solution
import heapq

class PagedKV:
    def __init__(self, num_blocks, block_size):
        self.bs = block_size
        self.free_ids = list(range(num_blocks))      # a min-heap: lowest id first
        self.tables, self.lengths = {}, {}

    def append(self, seq, n):
        length = self.lengths.get(seq, 0)
        have = len(self.tables.get(seq, []))
        need = -(-(length + n) // self.bs) - have    # ceil division
        if need > len(self.free_ids):
            return False
        table = self.tables.setdefault(seq, [])
        for _ in range(need):
            table.append(heapq.heappop(self.free_ids))
        self.lengths[seq] = length + n
        return True

    def free(self, seq):
        for b in self.tables.pop(seq, []):
            heapq.heappush(self.free_ids, b)
        self.lengths.pop(seq, None)

    def table(self, seq):
        return list(self.tables.get(seq, []))
```

```python tests
kv = PagedKV(num_blocks=4, block_size=16)
check(kv.append("a", 20), True); check(kv.table("a"), [0, 1])
check(kv.append("b", 16), True); check(kv.table("b"), [2])
check(kv.append("a", 12), True); check(kv.table("a"), [0, 1], "fits in a's partial block")
check(kv.append("a", 1), True); check(kv.table("a"), [0, 1, 3])
check(kv.append("b", 1), False, "out of blocks"); check(kv.table("b"), [2], "unchanged on failure")
kv.free("a"); check(kv.append("b", 40), True); check(kv.table("b"), [2, 0, 1, 3], "reuses freed blocks")
```

## Continuous Batching Scheduler
> difficulty: Hard | tags: scheduling, batching | source: vLLM / SGLang

Simulate decode steps. Each request `(rid, arrival_step, output_tokens)` joins the running batch at the first step
`≥ arrival_step` when there is room (`max_batch` sequences), in arrival order (ties by `rid`). Every step, each running
request produces one token; a request finishing its last token leaves at the end of that step, freeing its slot for
the next step. Return `{rid: finish_step}` (the step that produced its last token). Steps start at 0.

```python starter
def continuous_batching(requests, max_batch):
    pass
```

```python solution
def continuous_batching(requests, max_batch):
    waiting = sorted(requests, key=lambda r: (r[1], r[0]))
    running, done, step = {}, {}, 0                   # rid -> tokens left
    while waiting or running:
        while waiting and len(running) < max_batch and waiting[0][1] <= step:
            rid, _, n = waiting.pop(0)
            running[rid] = n
        for rid in list(running):
            running[rid] -= 1
            if running[rid] == 0:
                done[rid] = step
                del running[rid]
        step += 1
    return done
```

```python tests
reqs = [("a", 0, 3), ("b", 0, 1), ("c", 1, 2), ("d", 1, 2)]
check(continuous_batching(reqs, max_batch=2), {"b": 0, "c": 2, "a": 2, "d": 4})
check(continuous_batching([("x", 5, 1)], 4), {"x": 5}, "idle until the request arrives")
static = {"b": 0, "a": 2}
check({k: v for k, v in continuous_batching(reqs[:2], 2).items()}, static)
```

## Speculative Decoding: Greedy Verification
> difficulty: Medium | tags: speculative decoding | source: vllm_labs lab 10

A draft model proposed `draft` tokens. One target-model pass gives `target_argmax`, of length `len(draft) + 1`:
the target's greedy choice at each draft position plus one more. Accept the longest prefix where draft and target agree,
then append the target's token at the first disagreement (or the bonus token if all matched). Return the emitted tokens.

```python starter
def verify(draft, target_argmax):
    pass
```

```python solution
def verify(draft, target_argmax):
    out = []
    for d, t in zip(draft, target_argmax):
        if d != t:
            out.append(t)            # the target's correction ends this round
            return out
        out.append(d)
    out.append(target_argmax[len(draft)])   # every draft token accepted: free bonus token
    return out
```

```python tests
check(verify([5, 7, 9], [5, 7, 9, 2]), [5, 7, 9, 2], "all accepted plus a bonus token")
check(verify([5, 7, 9], [5, 8, 1, 2]), [5, 8], "first mismatch replaced by the target's token")
check(verify([4], [6, 1]), [6], "even a full rejection emits one token")
check(verify([], [3]), [3])
```
