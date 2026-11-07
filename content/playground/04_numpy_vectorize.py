# title: Loops vs NumPy
# Same computation three ways. Vectorising moves the loop from Python into C.
import numpy as np

from dc import Timer

n = 200_000
x = np.random.default_rng(0).normal(size=n)

with Timer("python loop"):
    total = 0.0
    for v in x.tolist():
        total += v * v

with Timer("generator + sum"):
    total2 = sum(v * v for v in x.tolist())

with Timer("numpy dot"):
    total3 = float(x @ x)

print(round(total, 6) == round(total3, 6), round(total3, 3))
