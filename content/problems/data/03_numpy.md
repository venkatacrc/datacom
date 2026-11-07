---
track: python-data
section: Batch · NumPy
---

## Standardize Columns
> difficulty: Easy | tags: numpy, broadcasting

Return `X` with each column shifted to mean 0 and scaled to standard deviation 1 (population std).
Columns with zero spread become all zeros. No Python loops.

```python starter
import numpy as np

def standardize(X):
    pass
```

```python solution
import numpy as np

def standardize(X):
    X = np.asarray(X, dtype=float)
    mu, sd = X.mean(axis=0), X.std(axis=0)
    return np.where(sd > 0, (X - mu) / np.where(sd > 0, sd, 1), 0.0)
```

```python tests
import numpy as np
Z = standardize([[1, 10, 5], [2, 20, 5], [3, 30, 5]])
check(Z.mean(axis=0), [0, 0, 0])
check(Z[:, :2].std(axis=0), [1, 1])
check(Z[:, 2], [0, 0, 0], "constant column")
```

## Pairwise Distances
> difficulty: Medium | tags: numpy, broadcasting

Return the `(n, m)` matrix of Euclidean distances between rows of `A (n, d)` and `B (m, d)` without loops.
Use `|a - b|² = |a|² + |b|² - 2a·b` and clip tiny negatives to 0.

```python starter
import numpy as np

def pairwise_dist(A, B):
    pass
```

```python solution
import numpy as np

def pairwise_dist(A, B):
    A, B = np.asarray(A, float), np.asarray(B, float)
    sq = (A * A).sum(1)[:, None] + (B * B).sum(1)[None, :] - 2 * A @ B.T
    return np.sqrt(np.maximum(sq, 0))
```

```python tests
import numpy as np
check(pairwise_dist([[0, 0], [3, 4]], [[0, 0], [6, 8]]), [[0, 10], [5, 5]])
rng = np.random.default_rng(0); A, B = rng.normal(size=(50, 8)), rng.normal(size=(40, 8))
check(pairwise_dist(A, B), np.linalg.norm(A[:, None] - B[None], axis=-1), "matches the broadcast version")
```

## One-Hot Encode
> difficulty: Easy | tags: numpy, fancy indexing

Turn integer labels `y` (values `0..k-1`) into an `(n, k)` float matrix of one-hot rows.

```python starter
import numpy as np

def one_hot(y, k):
    pass
```

```python solution
import numpy as np

def one_hot(y, k):
    y = np.asarray(y, dtype=int)
    out = np.zeros((y.size, k))
    out[np.arange(y.size), y] = 1.0
    return out
```

```python tests
check(one_hot([0, 2, 1], 3), [[1, 0, 0], [0, 0, 1], [0, 1, 0]])
check(one_hot([], 2).shape, (0, 2))
```

## Moving Average with cumsum
> difficulty: Easy | tags: numpy, prefix sums

Return the means of every length-`k` window of `x` in O(n) using a cumulative sum.

```python starter
import numpy as np

def moving_average(x, k):
    pass
```

```python solution
import numpy as np

def moving_average(x, k):
    c = np.cumsum(np.concatenate([[0.0], np.asarray(x, float)]))
    return (c[k:] - c[:-k]) / k
```

```python tests
check(moving_average([1, 2, 3, 4, 5], 2), [1.5, 2.5, 3.5, 4.5])
check(moving_average([5, 5, 5], 3), [5.0])
```

## Top-k Indices per Row
> difficulty: Medium | tags: numpy, argpartition

Return an `(n, k)` int array with the indices of the `k` largest values in each row, largest first.
Use `np.argpartition` so it's O(d) per row before the final small sort.

```python starter
import numpy as np

def topk_rows(X, k):
    pass
```

```python solution
import numpy as np

def topk_rows(X, k):
    X = np.asarray(X)
    part = np.argpartition(-X, k - 1, axis=1)[:, :k]          # k largest, unordered
    order = np.argsort(-np.take_along_axis(X, part, axis=1), axis=1, kind="stable")
    return np.take_along_axis(part, order, axis=1)
```

```python tests
check(topk_rows([[0.1, 0.9, 0.5, 0.7], [3, 1, 2, 0]], 2), [[1, 3], [0, 2]])
import numpy as np
X = np.random.default_rng(1).normal(size=(100, 64))
check(topk_rows(X, 5), np.argsort(-X, axis=1)[:, :5], "matches a full sort")
```
