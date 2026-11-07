---
track: ml
section: ML coding · fundamentals
---

## Numerically Stable Softmax
> difficulty: Easy | tags: numpy, numerics

Return softmax along the last axis of `x` (any shape). It must not overflow for logits like `[1000, 1001]`.

```python starter
import numpy as np

def softmax(x):
    pass
```

```python solution
import numpy as np

def softmax(x):
    x = np.asarray(x, dtype=float)
    z = x - x.max(axis=-1, keepdims=True)     # shift: same result, no overflow
    e = np.exp(z)
    return e / e.sum(axis=-1, keepdims=True)
```

```python tests
import numpy as np
check(softmax([1.0, 2.0, 3.0]), [0.09003057, 0.24472847, 0.66524096])
check(softmax([1000.0, 1001.0]), [0.26894142, 0.73105858], "no overflow")
check(softmax(np.zeros((2, 4))).sum(axis=-1), [1.0, 1.0], "rows sum to 1")
```

## Cross-Entropy Loss and Its Gradient
> difficulty: Medium | tags: numpy, backprop

`logits (n, k)`, integer `labels (n,)`. Return `(loss, grad)`: the mean cross-entropy and its gradient with respect
to the logits, `(softmax - one_hot) / n`. Compute log-softmax stably.

```python starter
import numpy as np

def cross_entropy(logits, labels):
    pass
```

```python solution
import numpy as np

def cross_entropy(logits, labels):
    logits = np.asarray(logits, float)
    n = logits.shape[0]
    z = logits - logits.max(axis=1, keepdims=True)
    log_p = z - np.log(np.exp(z).sum(axis=1, keepdims=True))
    loss = -log_p[np.arange(n), labels].mean()
    grad = np.exp(log_p)
    grad[np.arange(n), labels] -= 1
    return loss, grad / n
```

```python tests
import numpy as np
loss, grad = cross_entropy([[2.0, 1.0, 0.1]], [0])
check(loss, 0.41702997)
check(grad, [[-0.34099886, 0.24243297, 0.09856589]])
rng = np.random.default_rng(0); L = rng.normal(size=(4, 5)); y = np.array([0, 3, 1, 4])
_, g = cross_entropy(L, y); eps = 1e-6; E = np.zeros_like(L); E[2, 1] = eps
num = (cross_entropy(L + E, y)[0] - cross_entropy(L - E, y)[0]) / (2 * eps)
check(g[2, 1], num, "matches a finite-difference check")
```

## Logistic Regression from Scratch
> difficulty: Medium | tags: numpy, gradient descent

Train `w (d,)` and `b` by full-batch gradient descent on the mean log-loss for `epochs` steps with learning rate
`lr`, starting from zeros. Return `(w, b)`. Write the sigmoid so it doesn't overflow.

```python starter
import numpy as np

def train_logreg(X, y, lr=0.1, epochs=500):
    pass
```

```python solution
import numpy as np

def sigmoid(z):
    return np.where(z >= 0, 1 / (1 + np.exp(-np.abs(z))), np.exp(-np.abs(z)) / (1 + np.exp(-np.abs(z))))

def train_logreg(X, y, lr=0.1, epochs=500):
    X, y = np.asarray(X, float), np.asarray(y, float)
    w, b = np.zeros(X.shape[1]), 0.0
    for _ in range(epochs):
        p = sigmoid(X @ w + b)
        err = p - y                       # d(loss)/d(logit)
        w -= lr * X.T @ err / len(y)
        b -= lr * err.mean()
    return w, b
```

```python tests
import numpy as np
rng = np.random.default_rng(0)
X = rng.normal(size=(400, 2)); y = (X[:, 0] - 2 * X[:, 1] + 0.3 > 0).astype(float)
w, b = train_logreg(X, y)
acc = (((X @ w + b) > 0) == y).mean()
check_true(acc > 0.95, f"training accuracy {acc:.3f} > 0.95")
check_true(w[0] > 0 and w[1] < 0, "weights point the right way")
```

## K-Means (Lloyd's Algorithm)
> difficulty: Medium | tags: numpy, clustering

Cluster `X (n, d)` into `k` groups. Initialise centroids as the first `k` rows, then alternate assign / update until
assignments stop changing (or `iters` passes). Keep a centroid in place if its cluster empties.
Return `(centroids, labels)`.

```python starter
import numpy as np

def kmeans(X, k, iters=100):
    pass
```

```python solution
import numpy as np

def kmeans(X, k, iters=100):
    X = np.asarray(X, float)
    C = X[:k].copy()
    labels = None
    for _ in range(iters):
        d = ((X[:, None, :] - C[None, :, :]) ** 2).sum(-1)
        new = d.argmin(1)
        if labels is not None and (new == labels).all():
            break
        labels = new
        for j in range(k):
            if (labels == j).any():
                C[j] = X[labels == j].mean(0)
    return C, labels
```

```python tests
import numpy as np
X = np.array([[0, 0], [10, 10], [0, 1], [1, 0], [10, 11], [11, 10]], float)
C, labels = kmeans(X, 2)
check(C, [[1 / 3, 1 / 3], [31 / 3, 31 / 3]])
check(labels.tolist(), [0, 1, 0, 0, 1, 1])
```

## ROC AUC and NDCG@k
> difficulty: Medium | tags: metrics, ranking

Write `roc_auc(y_true, scores)`: the probability a random positive outranks a random negative (ties count ½).
Write `ndcg_at_k(relevance, k)`: `relevance` is listed in ranked order; DCG uses `rel / log2(rank + 1)`.

```python starter
def roc_auc(y_true, scores):
    pass

def ndcg_at_k(relevance, k):
    pass
```

```python solution
import math

def roc_auc(y_true, scores):
    pairs = sorted(zip(scores, y_true))
    # average ranks (1-based) handle ties; Mann–Whitney U statistic
    ranks, i = [0.0] * len(pairs), 0
    while i < len(pairs):
        j = i
        while j + 1 < len(pairs) and pairs[j + 1][0] == pairs[i][0]:
            j += 1
        for t in range(i, j + 1):
            ranks[t] = (i + j) / 2 + 1
        i = j + 1
    pos = sum(y for _, y in pairs)
    neg = len(pairs) - pos
    rank_sum = sum(r for r, (_, y) in zip(ranks, pairs) if y)
    return (rank_sum - pos * (pos + 1) / 2) / (pos * neg)

def ndcg_at_k(relevance, k):
    def dcg(rels):
        return sum(r / math.log2(i + 2) for i, r in enumerate(rels[:k]))
    ideal = dcg(sorted(relevance, reverse=True))
    return dcg(relevance) / ideal if ideal else 0.0
```

```python tests
check(roc_auc([0, 0, 1, 1], [0.1, 0.4, 0.35, 0.8]), 0.75)
check(roc_auc([0, 1], [0.5, 0.5]), 0.5, "a tie counts half")
check(roc_auc([1, 1, 0], [0.9, 0.8, 0.1]), 1.0)
check(ndcg_at_k([3, 2, 3, 0, 1, 2], 6), 0.96080819)
check(ndcg_at_k([0, 0, 1], 2), 0.0)
```

## Adam Optimizer Step
> difficulty: Medium | tags: optimizers

Implement `Adam(lr, beta1, beta2, eps)` with `step(params, grads)` that updates a list of NumPy arrays in place, with
bias correction. Then check it minimises a quadratic.

```python starter
import numpy as np

class Adam:
    def __init__(self, lr=1e-3, beta1=0.9, beta2=0.999, eps=1e-8):
        pass

    def step(self, params, grads):
        pass
```

```python solution
import numpy as np

class Adam:
    def __init__(self, lr=1e-3, beta1=0.9, beta2=0.999, eps=1e-8):
        self.lr, self.b1, self.b2, self.eps = lr, beta1, beta2, eps
        self.t, self.m, self.v = 0, None, None

    def step(self, params, grads):
        if self.m is None:
            self.m = [np.zeros_like(p) for p in params]
            self.v = [np.zeros_like(p) for p in params]
        self.t += 1
        for p, g, m, v in zip(params, grads, self.m, self.v):
            m[:] = self.b1 * m + (1 - self.b1) * g
            v[:] = self.b2 * v + (1 - self.b2) * g * g
            m_hat = m / (1 - self.b1 ** self.t)
            v_hat = v / (1 - self.b2 ** self.t)
            p -= self.lr * m_hat / (np.sqrt(v_hat) + self.eps)
```

```python tests
import numpy as np
p = [np.array([1.0, -2.0])]
opt = Adam(lr=0.1)
opt.step(p, [np.array([0.5, -0.5])])
check(p[0], [0.9, -1.9], "first step moves each weight by lr")
x = [np.array([5.0, -3.0])]
opt = Adam(lr=0.1)
for _ in range(500):
    opt.step(x, [2 * (x[0] - np.array([1.0, 2.0]))])
check(np.round(x[0], 2), [1.0, 2.0], "minimises (x - [1, 2])²")
```

## Two-Layer MLP Backprop
> difficulty: Hard | tags: backprop, gradient check

`forward_backward(X, y, W1, b1, W2, b2)` runs `h = relu(X @ W1 + b1)`, `out = h @ W2 + b2`, loss = mean squared error
`mean((out - y)²)`, and returns `(loss, {"W1": …, "b1": …, "W2": …, "b2": …})` gradients.

```python starter
import numpy as np

def forward_backward(X, y, W1, b1, W2, b2):
    pass
```

```python solution
import numpy as np

def forward_backward(X, y, W1, b1, W2, b2):
    z = X @ W1 + b1
    h = np.maximum(z, 0)
    out = h @ W2 + b2
    diff = out - y
    loss = (diff ** 2).mean()
    d_out = 2 * diff / diff.size
    grads = {"W2": h.T @ d_out, "b2": d_out.sum(0)}
    d_z = (d_out @ W2.T) * (z > 0)
    grads["W1"] = X.T @ d_z
    grads["b1"] = d_z.sum(0)
    return loss, grads
```

```python tests
import numpy as np
rng = np.random.default_rng(0)
X, y = rng.normal(size=(8, 3)), rng.normal(size=(8, 2))
P = {"W1": rng.normal(size=(3, 5)), "b1": rng.normal(size=5), "W2": rng.normal(size=(5, 2)), "b2": rng.normal(size=2)}
loss, g = forward_backward(X, y, **P)
for name in P:
    num = np.zeros_like(P[name]); eps = 1e-6
    for idx in np.ndindex(P[name].shape):
        Pp = {k: v.copy() for k, v in P.items()}; Pp[name][idx] += eps
        Pm = {k: v.copy() for k, v in P.items()}; Pm[name][idx] -= eps
        num[idx] = (forward_backward(X, y, **Pp)[0] - forward_backward(X, y, **Pm)[0]) / (2 * eps)
    check(g[name], num, f"d loss / d {name} matches finite differences", tol=1e-4)
```
