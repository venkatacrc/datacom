---
track: ml
section: ML coding · transformers
---

## Scaled Dot-Product Attention with a Causal Mask
> difficulty: Medium | tags: attention, numpy

`q, k, v` have shape `(T, d)`. Return `softmax(q kᵀ / √d + mask) v`, where with `causal=True` position `i` may only
attend to positions `≤ i`.

```python starter
import numpy as np

def attention(q, k, v, causal=False):
    pass
```

```python solution
import numpy as np

def attention(q, k, v, causal=False):
    T, d = q.shape
    s = q @ k.T / np.sqrt(d)
    if causal:
        s = np.where(np.tril(np.ones((T, k.shape[0]), bool)), s, -np.inf)
    s = s - s.max(-1, keepdims=True)
    p = np.exp(s)
    p /= p.sum(-1, keepdims=True)
    return p @ v
```

```python tests
import numpy as np
rng = np.random.default_rng(0); q, k, v = (rng.normal(size=(5, 4)) for _ in range(3))
out = attention(q, k, v, causal=True)
check(out[0], v[0], "first token can only see itself")
check(attention(q, k, v).shape, (5, 4))
v2 = v.copy(); v2[4] += 100
check(attention(q, k, v2, causal=True)[:4], out[:4], "changing the last value can't affect earlier outputs")
check(attention(np.zeros((3, 2)), np.zeros((3, 2)), np.eye(3)), np.full((3, 3), 1 / 3))
```

## Multi-Head Attention
> difficulty: Medium | tags: attention, reshapes

`x (T, d_model)`, weights `Wq, Wk, Wv, Wo (d_model, d_model)`, `n_heads` divides `d_model`. Project, split into heads
`(n_heads, T, d_head)`, run causal attention per head, merge back to `(T, d_model)` and apply `Wo`.
Use batched matmuls, not a Python loop over heads.

```python starter
import numpy as np

def mha(x, Wq, Wk, Wv, Wo, n_heads):
    pass
```

```python solution
import numpy as np

def mha(x, Wq, Wk, Wv, Wo, n_heads):
    T, D = x.shape
    dh = D // n_heads
    def split(t):                               # (T, D) -> (H, T, dh)
        return t.reshape(T, n_heads, dh).transpose(1, 0, 2)
    q, k, v = split(x @ Wq), split(x @ Wk), split(x @ Wv)
    s = q @ k.transpose(0, 2, 1) / np.sqrt(dh)  # (H, T, T)
    s = np.where(np.tril(np.ones((T, T), bool)), s, -np.inf)
    p = np.exp(s - s.max(-1, keepdims=True))
    p /= p.sum(-1, keepdims=True)
    out = (p @ v).transpose(1, 0, 2).reshape(T, D)
    return out @ Wo
```

```python tests
import numpy as np
rng = np.random.default_rng(1)
T, D, H = 6, 8, 2
x = rng.normal(size=(T, D)); W = [rng.normal(size=(D, D)) / np.sqrt(D) for _ in range(4)]
def ref(x, Wq, Wk, Wv, Wo, H):
    dh = D // H; heads = []
    for h in range(H):
        sl = slice(h * dh, (h + 1) * dh)
        q, k, v = (x @ Wq)[:, sl], (x @ Wk)[:, sl], (x @ Wv)[:, sl]
        s = q @ k.T / np.sqrt(dh) + np.triu(np.full((T, T), -np.inf), 1)
        p = np.exp(s - s.max(1, keepdims=True)); p /= p.sum(1, keepdims=True)
        heads.append(p @ v)
    return np.concatenate(heads, 1) @ Wo
check(mha(x, *W, H), ref(x, *W, H), "matches a per-head loop")
check(mha(x, *W, 1), ref(x, *W, 1), "one head")
```

## LayerNorm and RMSNorm
> difficulty: Easy | tags: normalization

`layer_norm(x, gamma, beta, eps)` normalises the last axis to mean 0, variance 1 (biased variance), then scales and
shifts. `rms_norm(x, gamma, eps)` divides by `sqrt(mean(x²) + eps)` and scales (Llama-style, no mean subtraction).

```python starter
import numpy as np

def layer_norm(x, gamma, beta, eps=1e-5):
    pass

def rms_norm(x, gamma, eps=1e-6):
    pass
```

```python solution
import numpy as np

def layer_norm(x, gamma, beta, eps=1e-5):
    mu = x.mean(-1, keepdims=True)
    var = ((x - mu) ** 2).mean(-1, keepdims=True)
    return (x - mu) / np.sqrt(var + eps) * gamma + beta

def rms_norm(x, gamma, eps=1e-6):
    return x / np.sqrt((x * x).mean(-1, keepdims=True) + eps) * gamma
```

```python tests
import numpy as np
x = np.array([[1.0, 2.0, 3.0, 4.0], [2.0, 2.0, 2.0, 2.0]])
y = layer_norm(x, np.ones(4), np.zeros(4))
check(y[0], [-1.34163542, -0.44721181, 0.44721181, 1.34163542])
check(y[1], [0, 0, 0, 0], "constant row")
check(rms_norm(np.array([3.0, 4.0]), np.ones(2)), [0.84852814, 1.13137085], tol=1e-5)
```

## Top-k and Top-p (Nucleus) Filtering
> difficulty: Medium | tags: sampling, decoding

Given `logits (V,)`, return a probability vector after filtering. `top_k`: keep the `k` largest logits.
`top_p`: keep the smallest set of tokens, taken by descending probability, whose total probability reaches `p`
(always keep at least one). Renormalise; everything else is 0. Apply `top_k` first when both are set.

```python starter
import numpy as np

def filter_probs(logits, top_k=None, top_p=None):
    pass
```

```python solution
import numpy as np

def filter_probs(logits, top_k=None, top_p=None):
    logits = np.asarray(logits, float).copy()
    if top_k is not None:
        kth = np.sort(logits)[-top_k]
        logits[logits < kth] = -np.inf
    p = np.exp(logits - logits.max())
    p /= p.sum()
    if top_p is not None:
        order = np.argsort(-p, kind="stable")
        cum = np.cumsum(p[order])
        keep = order[: int(np.searchsorted(cum, top_p - 1e-12)) + 1]
        mask = np.zeros_like(p, bool)
        mask[keep] = True
        p = np.where(mask, p, 0)
        p /= p.sum()
    return p
```

```python tests
import numpy as np
lg = np.log([0.5, 0.3, 0.15, 0.05])
check(filter_probs(lg, top_k=2), [0.625, 0.375, 0, 0])
check(filter_probs(lg, top_p=0.8), [0.625, 0.375, 0, 0], "0.5 + 0.3 reaches 0.8")
check(filter_probs(lg, top_p=0.81), [0.5 / 0.95, 0.3 / 0.95, 0.15 / 0.95, 0])
check(filter_probs(lg, top_p=0.1), [1, 0, 0, 0], "keeps at least one token")
check(filter_probs(lg), [0.5, 0.3, 0.15, 0.05])
```

## Byte-Pair Encoding: Learn the Merges
> difficulty: Hard | tags: tokenization

Start from characters. Repeat `n_merges` times: count adjacent symbol pairs across all words (weighted by word
frequency), merge the most frequent pair (break ties by the lexicographically smallest pair). Return the list of
merges as tuples. `corpus` is `{word: count}`.

```python starter
def learn_bpe(corpus, n_merges):
    pass
```

```python solution
from collections import Counter

def learn_bpe(corpus, n_merges):
    words = {tuple(w): c for w, c in corpus.items()}
    merges = []
    for _ in range(n_merges):
        pairs = Counter()
        for syms, c in words.items():
            for a, b in zip(syms, syms[1:]):
                pairs[(a, b)] += c
        if not pairs:
            break
        best = min(pairs, key=lambda p: (-pairs[p], p))
        merges.append(best)
        new = {}
        for syms, c in words.items():
            out, i = [], 0
            while i < len(syms):
                if i + 1 < len(syms) and (syms[i], syms[i + 1]) == best:
                    out.append(syms[i] + syms[i + 1])
                    i += 2
                else:
                    out.append(syms[i])
                    i += 1
            new[tuple(out)] = new.get(tuple(out), 0) + c
        words = new
    return merges
```

```python tests
corpus = {"low": 5, "lower": 2, "newest": 6, "widest": 3}
check(learn_bpe(corpus, 4), [("e", "s"), ("es", "t"), ("l", "o"), ("lo", "w")])
check(learn_bpe({"a": 1}, 3), [], "nothing to merge")
```
