---
track: training
section: Training mechanics
---

## Training Memory Budget
> difficulty: Easy | tags: memory, mixed precision | source: interview classic

Estimate GPU memory in GB (1e9 bytes) for training a model with `n_params` parameters using mixed precision and Adam:
bf16 weights (2 B) and grads (2 B), plus fp32 master weights, Adam `m` and `v` (4 B each). Ignore activations.
With `zero_stage=3` and `n_gpus`, every one of those is sharded evenly. Return GB per GPU.

```python starter
def training_memory_gb(n_params, n_gpus=1, zero_stage=0):
    pass
```

```python solution
def training_memory_gb(n_params, n_gpus=1, zero_stage=0):
    weights, grads, optimizer = 2 * n_params, 2 * n_params, 12 * n_params   # 16 bytes per parameter
    if zero_stage >= 1:
        optimizer /= n_gpus
    if zero_stage >= 2:
        grads /= n_gpus
    if zero_stage >= 3:
        weights /= n_gpus
    return (weights + grads + optimizer) / 1e9
```

```python tests
check(training_memory_gb(7e9), 112.0, "7B params × 16 bytes")
check(training_memory_gb(7e9, n_gpus=8, zero_stage=3), 14.0)
check(training_memory_gb(7e9, n_gpus=8, zero_stage=1), 38.5, "ZeRO-1 shards only optimizer state")
```

## Gradient Accumulation Equals a Big Batch
> difficulty: Medium | tags: gradient accumulation, linear model

For linear regression with mean-squared-error loss, `grad(w, X, y)` returns `2 Xᵀ(Xw − y) / n`.
Write `accumulated_grad(w, X, y, micro)` that splits the batch into micro-batches of size `micro` (the last may be
smaller) and combines their gradients so the result equals the full-batch gradient exactly.

```python starter
import numpy as np

def grad(w, X, y):
    return 2 * X.T @ (X @ w - y) / len(y)

def accumulated_grad(w, X, y, micro):
    pass
```

```python solution
import numpy as np

def grad(w, X, y):
    return 2 * X.T @ (X @ w - y) / len(y)

def accumulated_grad(w, X, y, micro):
    total = np.zeros_like(w)
    for s in range(0, len(y), micro):
        xb, yb = X[s:s + micro], y[s:s + micro]
        total += grad(w, xb, yb) * len(yb)        # weight by size: the last micro-batch can be short
    return total / len(y)
```

```python tests
import numpy as np
rng = np.random.default_rng(0)
X, y, w = rng.normal(size=(50, 3)), rng.normal(size=50), rng.normal(size=3)
check(accumulated_grad(w, X, y, 10), grad(w, X, y), "even split")
check(accumulated_grad(w, X, y, 16), grad(w, X, y), "uneven last micro-batch")
```

## Ring All-Reduce
> difficulty: Hard | tags: data parallel, collectives | source: NCCL

Simulate ring all-reduce over `n` workers, each holding an array split into `n` chunks. Reduce-scatter: in step `s`,
worker `i` sends chunk `(i − s) mod n` to worker `i+1`, which adds it in. All-gather: in step `s`, worker `i` sends chunk
`(i + 1 − s) mod n` to worker `i+1`, which overwrites. All sends in a step happen at once.
Return `(arrays, steps)` where every worker ends with the elementwise sum and `steps == 2(n − 1)`.

```python starter
import numpy as np

def ring_allreduce(arrays):
    pass
```

```python solution
import numpy as np

def ring_allreduce(arrays):
    n = len(arrays)
    chunks = [np.array_split(np.array(a, dtype=float), n) for a in arrays]
    steps = 0
    for s in range(n - 1):                               # reduce-scatter
        sends = [(i, (i - s) % n, chunks[i][(i - s) % n].copy()) for i in range(n)]
        for i, c, data in sends:
            chunks[(i + 1) % n][c] += data
        steps += 1
    for s in range(n - 1):                               # all-gather
        sends = [(i, (i + 1 - s) % n, chunks[i][(i + 1 - s) % n].copy()) for i in range(n)]
        for i, c, data in sends:
            chunks[(i + 1) % n][c] = data
        steps += 1
    return [np.concatenate(c) for c in chunks], steps
```

```python tests
import numpy as np
rng = np.random.default_rng(1)
arrs = [rng.normal(size=10) for _ in range(4)]
out, steps = ring_allreduce(arrs)
check_true(all(np.allclose(o, sum(arrs)) for o in out), "every worker holds the sum")
check(steps, 6)
out, steps = ring_allreduce([np.ones(3), 2 * np.ones(3)])
check([o.tolist() for o in out], [[3, 3, 3], [3, 3, 3]]); check(steps, 2)
```

## Warmup + Cosine Learning-Rate Schedule
> difficulty: Easy | tags: schedules

Return the learning rate at `step`: linear warmup from 0 to `peak` over `warmup` steps (step `warmup` is exactly
`peak`), then cosine decay to `floor` at `total` steps, constant after that.

```python starter
import math

def lr_at(step, peak, warmup, total, floor=0.0):
    pass
```

```python solution
import math

def lr_at(step, peak, warmup, total, floor=0.0):
    if step < warmup:
        return peak * step / warmup
    if step >= total:
        return floor
    progress = (step - warmup) / (total - warmup)
    return floor + (peak - floor) * 0.5 * (1 + math.cos(math.pi * progress))
```

```python tests
check(lr_at(0, 3e-4, 100, 1000), 0.0)
check(lr_at(50, 3e-4, 100, 1000), 1.5e-4)
check(lr_at(100, 3e-4, 100, 1000), 3e-4)
check(lr_at(550, 3e-4, 100, 1000, floor=3e-5), 1.65e-4, "halfway down")
check(lr_at(5000, 3e-4, 100, 1000, floor=3e-5), 3e-5)
```

## Dynamic Loss Scaling
> difficulty: Medium | tags: fp16, mixed precision

fp16 gradients underflow, so training multiplies the loss by a scale. Implement `LossScaler(init, growth_interval)`
with `update(found_inf)`: on overflow, halve the scale and reset the clean-step counter (and report the step is
skipped); after `growth_interval` clean steps in a row, double the scale. `update` returns True if the optimizer
step should run.

```python starter
class LossScaler:
    def __init__(self, init=2.0 ** 16, growth_interval=2000):
        pass

    def update(self, found_inf):
        pass
```

```python solution
class LossScaler:
    def __init__(self, init=2.0 ** 16, growth_interval=2000):
        self.scale, self.interval, self.clean = init, growth_interval, 0

    def update(self, found_inf):
        if found_inf:
            self.scale /= 2
            self.clean = 0
            return False
        self.clean += 1
        if self.clean == self.interval:
            self.scale *= 2
            self.clean = 0
        return True
```

```python tests
s = LossScaler(init=1024.0, growth_interval=3)
check(s.update(True), False, "overflow skips the step"); check(s.scale, 512.0)
check([s.update(False) for _ in range(3)], [True, True, True]); check(s.scale, 1024.0, "grows after 3 clean steps")
s.update(False); s.update(True); s.update(False); s.update(False)
check(s.scale, 512.0, "an overflow resets the clean-step count")
```

## Knowledge Distillation Loss
> difficulty: Medium | tags: distillation, KL divergence | source: distillation labs

Hinton-style distillation: `loss = α · T² · KL(softmax(teacher/T) ‖ softmax(student/T)) + (1 − α) · CE(student, labels)`,
averaged over the batch. Inputs are logits `(n, k)` and integer labels `(n,)`.

```python starter
import numpy as np

def distill_loss(student, teacher, labels, T=2.0, alpha=0.5):
    pass
```

```python solution
import numpy as np

def log_softmax(z):
    z = z - z.max(-1, keepdims=True)
    return z - np.log(np.exp(z).sum(-1, keepdims=True))

def distill_loss(student, teacher, labels, T=2.0, alpha=0.5):
    student, teacher = np.asarray(student, float), np.asarray(teacher, float)
    log_ps, log_pt = log_softmax(student / T), log_softmax(teacher / T)
    kl = (np.exp(log_pt) * (log_pt - log_ps)).sum(-1).mean()
    ce = -log_softmax(student)[np.arange(len(labels)), labels].mean()
    return alpha * T * T * kl + (1 - alpha) * ce
```

```python tests
import numpy as np
s = np.array([[2.0, 0.5, -1.0], [0.1, 0.2, 3.0]]); t = np.array([[3.0, 1.0, -2.0], [0.0, 0.5, 2.5]]); y = np.array([0, 2])
check(distill_loss(s, s, y, alpha=1.0), 0.0, "student equal to teacher has zero KL")
check(distill_loss(s, t, y, alpha=0.0), 0.17545638, "alpha 0 is plain cross-entropy", tol=1e-5)
check_true(distill_loss(s, t, y, T=4.0, alpha=1.0) > 0, "KL is positive when they differ")
```
