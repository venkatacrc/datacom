---
track: gpu-kernels
section: Kernel thinking in NumPy
---

## Tiled Matrix Multiply
> difficulty: Medium | tags: tiling, shared memory | source: gpukernels lesson 04

A GPU block computes one `tile × tile` output tile by looping over the K dimension in `tile`-wide chunks that it
stages in shared memory. Write that loop nest with NumPy tiles (edges may be partial). Return `C = A @ B` and the
number of tile loads from A and B combined.

```python starter
import numpy as np

def tiled_matmul(A, B, tile):
    pass
```

```python solution
import numpy as np

def tiled_matmul(A, B, tile):
    M, K = A.shape
    _, N = B.shape
    C = np.zeros((M, N))
    loads = 0
    for i in range(0, M, tile):              # one "block" per (i, j) output tile
        for j in range(0, N, tile):
            acc = np.zeros((min(tile, M - i), min(tile, N - j)))
            for k in range(0, K, tile):      # stream K through shared memory
                a = A[i:i + tile, k:k + tile]
                b = B[k:k + tile, j:j + tile]
                loads += 2
                acc += a @ b
            C[i:i + tile, j:j + tile] = acc
    return C, loads
```

```python tests
import numpy as np
rng = np.random.default_rng(0)
A, B = rng.normal(size=(70, 45)), rng.normal(size=(45, 33))
C, loads = tiled_matmul(A, B, 16)
check(C, A @ B, "matches A @ B with ragged edges")
check(loads, 5 * 3 * 3 * 2, "5×3 output tiles × 3 K-steps × (A + B)")
```

## Online Softmax (one pass)
> difficulty: Medium | tags: numerics, fusion | source: gpukernels lesson 02

Softmax normally needs three passes (max, sum, normalise). Compute the max `m` and the normaliser `l = Σ exp(x - m)`
in a *single* pass over chunks of `x`, rescaling `l` whenever the running max grows. Return `(m, l)`.

```python starter
import numpy as np

def online_softmax_stats(x, chunk=4):
    pass
```

```python solution
import numpy as np

def online_softmax_stats(x, chunk=4):
    m, l = -np.inf, 0.0
    for s in range(0, len(x), chunk):
        block = np.asarray(x[s:s + chunk], float)
        m_new = max(m, block.max())
        l = l * np.exp(m - m_new) + np.exp(block - m_new).sum()   # rescale the old sum
        m = m_new
    return m, l
```

```python tests
import numpy as np
x = np.random.default_rng(2).normal(size=37) * 10
m, l = online_softmax_stats(x)
check(m, x.max())
check(l, np.exp(x - x.max()).sum())
check(np.exp(x - m) / l, np.exp(x - x.max()) / np.exp(x - x.max()).sum(), "gives the exact softmax")
```

## FlashAttention Forward (tiled)
> difficulty: Hard | tags: attention, tiling, online softmax | source: gpukernels lesson 06

Compute `softmax(q kᵀ / √d) v` for `q (Tq, d)`, `k, v (Tk, d)` without ever materialising the `Tq × Tk` score matrix:
loop over key/value blocks of size `block`, keep per-row running max `m`, normaliser `l` and output accumulator `o`,
and rescale them as each block arrives.

```python starter
import numpy as np

def flash_attention(q, k, v, block=8):
    pass
```

```python solution
import numpy as np

def flash_attention(q, k, v, block=8):
    Tq, d = q.shape
    m = np.full((Tq, 1), -np.inf)
    l = np.zeros((Tq, 1))
    o = np.zeros((Tq, v.shape[1]))
    for s in range(0, k.shape[0], block):
        kb, vb = k[s:s + block], v[s:s + block]
        scores = q @ kb.T / np.sqrt(d)                    # (Tq, block): only one tile in "SRAM"
        m_new = np.maximum(m, scores.max(1, keepdims=True))
        p = np.exp(scores - m_new)
        scale = np.exp(m - m_new)
        l = l * scale + p.sum(1, keepdims=True)
        o = o * scale + p @ vb
        m = m_new
    return o / l
```

```python tests
import numpy as np
rng = np.random.default_rng(3)
q, k, v = rng.normal(size=(10, 16)), rng.normal(size=(29, 16)), rng.normal(size=(29, 16))
s = q @ k.T / 4; p = np.exp(s - s.max(1, keepdims=True)); ref = (p / p.sum(1, keepdims=True)) @ v
check(flash_attention(q, k, v, block=8), ref, "block 8")
check(flash_attention(q, k, v, block=1), ref, "block 1")
check(flash_attention(q, k, v, block=64), ref, "one block")
```

## Roofline: Memory- or Compute-Bound?
> difficulty: Easy | tags: roofline, performance model | source: gpukernels lesson 00

For a kernel that does `flops` floating-point operations and moves `bytes_moved` bytes on a GPU with `peak_flops`
(FLOP/s) and `peak_bw` (bytes/s), return `(intensity, attainable_flops, "memory" | "compute")`.
Attainable = `min(peak_flops, intensity × peak_bw)`. At exactly the ridge point, call it `"compute"`.
Then fill in `vector_add_bytes(n)` (fp32 `c = a + b`) and `matmul_flops_bytes(n)` (fp32 `n×n` GEMM, each matrix moved once).

```python starter
def roofline(flops, bytes_moved, peak_flops, peak_bw):
    pass

def vector_add_bytes(n):
    pass

def matmul_flops_bytes(n):
    pass
```

```python solution
def roofline(flops, bytes_moved, peak_flops, peak_bw):
    intensity = flops / bytes_moved
    attainable = min(peak_flops, intensity * peak_bw)
    bound = "compute" if intensity >= peak_flops / peak_bw else "memory"
    return intensity, attainable, bound

def vector_add_bytes(n):
    return 3 * 4 * n                 # read a and b, write c, 4 bytes each

def matmul_flops_bytes(n):
    return 2 * n ** 3, 3 * 4 * n * n # a multiply and an add per inner step; read A, B, write C
```

```python tests
B200 = dict(peak_flops=2.25e15, peak_bw=8e12)       # roughly: dense BF16 FLOP/s, HBM3e bytes/s
n = 1 << 24
i, att, bound = roofline(n, vector_add_bytes(n), **B200)
check(round(i, 4), 0.0833); check(bound, "memory", "vector add is memory-bound")
f, b = matmul_flops_bytes(8192)
check(roofline(f, b, **B200)[2], "compute", "big GEMM is compute-bound")
check(roofline(281.25, 1, **B200)[2], "compute", "exactly at the ridge")
check(roofline(1, 1, 10, 2)[1], 2, "attainable is capped by bandwidth")
```

## Parallel Reduction Tree
> difficulty: Easy | tags: reduction, warps | source: gpukernels lesson 05

Simulate a shared-memory tree reduction: at each step, element `i` adds element `i + stride` for every `i < stride`,
halving `stride` from `n/2` down to 1. `n` is a power of two. Return `(total, steps)`; there should be `log2(n)` steps.

```python starter
import numpy as np

def tree_reduce(x):
    pass
```

```python solution
import numpy as np

def tree_reduce(x):
    buf = np.array(x, dtype=float)
    stride, steps = len(buf) // 2, 0
    while stride >= 1:
        buf[:stride] += buf[stride:2 * stride]     # every "thread" i < stride works in parallel
        stride //= 2
        steps += 1
    return buf[0], steps
```

```python tests
import numpy as np
x = np.arange(1024, dtype=float)
check(tree_reduce(x), (x.sum(), 10))
check(tree_reduce([5.0]), (5.0, 0))
```

## Blelloch Exclusive Scan
> difficulty: Hard | tags: scan, prefix sum | source: GPU algorithms

Implement the work-efficient exclusive prefix sum: an up-sweep that builds partial sums in a tree, set the root to 0,
then a down-sweep. `n` is a power of two. Use vectorised slices for each level (that's one parallel step on a GPU).

```python starter
import numpy as np

def blelloch_scan(x):
    pass
```

```python solution
import numpy as np

def blelloch_scan(x):
    a = np.array(x, dtype=float)
    n = len(a)
    d = 1
    while d < n:                                   # up-sweep (reduce)
        a[2 * d - 1::2 * d] += a[d - 1::2 * d]
        d *= 2
    a[-1] = 0
    d = n // 2
    while d >= 1:                                  # down-sweep
        left = a[d - 1::2 * d].copy()
        a[d - 1::2 * d] = a[2 * d - 1::2 * d]
        a[2 * d - 1::2 * d] += left
        d //= 2
    return a
```

```python tests
import numpy as np
check(blelloch_scan([3, 1, 7, 0, 4, 1, 6, 3]), [0, 3, 4, 11, 11, 15, 16, 22])
x = np.random.default_rng(4).integers(0, 9, 256)
check(blelloch_scan(x), np.concatenate([[0], np.cumsum(x)[:-1]]), "256 random ints")
```
