---
track: python-data
section: Batch · pandas
---

## Revenue per Customer (groupby)
> difficulty: Easy | tags: pandas, groupby

Given a DataFrame with `customer`, `qty`, `price`, return a DataFrame with columns `customer`, `revenue`
(sum of qty × price), sorted by revenue descending, then customer ascending. Reset the index.

```python starter
import pandas as pd

def revenue_per_customer(df):
    pass
```

```python solution
import pandas as pd

def revenue_per_customer(df):
    out = (df.assign(revenue=df["qty"] * df["price"])
             .groupby("customer", as_index=False)["revenue"].sum())
    return out.sort_values(["revenue", "customer"], ascending=[False, True]).reset_index(drop=True)
```

```python tests
import pandas as pd
df = pd.DataFrame({"customer": ["a", "b", "a", "c"], "qty": [1, 2, 3, 1], "price": [2.0, 1.0, 1.0, 4.0]})
check(revenue_per_customer(df), pd.DataFrame({"customer": ["a", "b", "c"], "revenue": [5.0, 2.0, 4.0]})
      .sort_values(["revenue", "customer"], ascending=[False, True]).reset_index(drop=True))
```

## Left Join and Fill Missing
> difficulty: Easy | tags: pandas, merge

Attach each order's `region` from `customers` (matching on `customer`). Orders with no match get region `"unknown"`.
Keep the orders' row order.

```python starter
import pandas as pd

def attach_region(orders, customers):
    pass
```

```python solution
import pandas as pd

def attach_region(orders, customers):
    out = orders.merge(customers[["customer", "region"]], on="customer", how="left")
    out["region"] = out["region"].fillna("unknown")
    return out
```

```python tests
import pandas as pd
o = pd.DataFrame({"order_id": [1, 2, 3], "customer": ["a", "z", "b"]})
c = pd.DataFrame({"customer": ["a", "b"], "region": ["west", "east"]})
check(attach_region(o, c)["region"].tolist(), ["west", "unknown", "east"])
check(attach_region(o, c)["order_id"].tolist(), [1, 2, 3])
```

## Rolling 3-Day Average per Store
> difficulty: Medium | tags: pandas, window functions

`df` has `store`, `day` (int) and `sales`. Add a column `avg3`: the mean of that store's sales over the current and
two previous rows (fewer at the start), ordered by day. Return rows sorted by store, then day.

```python starter
import pandas as pd

def rolling_avg(df):
    pass
```

```python solution
import pandas as pd

def rolling_avg(df):
    df = df.sort_values(["store", "day"]).reset_index(drop=True)
    df["avg3"] = df.groupby("store")["sales"].transform(lambda s: s.rolling(3, min_periods=1).mean())
    return df
```

```python tests
import pandas as pd
df = pd.DataFrame({"store": ["x", "x", "y", "x", "y"], "day": [1, 2, 1, 3, 2], "sales": [3, 6, 10, 9, 20]})
check(rolling_avg(df)["avg3"].tolist(), [3.0, 4.5, 6.0, 10.0, 15.0])
```

## Rank Within Group
> difficulty: Medium | tags: pandas, rank

Add `rank` = dense rank of `score` within each `team`, highest score = 1. Return in the original row order.

```python starter
import pandas as pd

def rank_in_team(df):
    pass
```

```python solution
import pandas as pd

def rank_in_team(df):
    df = df.copy()
    df["rank"] = df.groupby("team")["score"].rank(method="dense", ascending=False).astype(int)
    return df
```

```python tests
import pandas as pd
df = pd.DataFrame({"team": ["a", "a", "b", "a", "b"], "score": [90, 95, 70, 90, 80]})
check(rank_in_team(df)["rank"].tolist(), [2, 1, 2, 2, 1])
```

## Pivot: Units by Day and Category
> difficulty: Medium | tags: pandas, pivot_table

From order rows (`day`, `category`, `qty`), build a table with one row per day (index `day`, sorted), one column per
category (sorted), cells = total qty, missing = 0, integer dtype.

```python starter
import pandas as pd

def units_pivot(df):
    pass
```

```python solution
import pandas as pd

def units_pivot(df):
    return (df.pivot_table(index="day", columns="category", values="qty", aggfunc="sum", fill_value=0)
              .sort_index().sort_index(axis=1).astype(int))
```

```python tests
import pandas as pd
df = pd.DataFrame({"day": [1, 1, 2, 2, 2], "category": ["fruit", "dairy", "fruit", "fruit", "bakery"],
                   "qty": [3, 1, 2, 4, 5]})
p = units_pivot(df)
check(list(p.columns), ["bakery", "dairy", "fruit"])
check(p.loc[2].tolist(), [5, 0, 6])
check(p.loc[1].tolist(), [0, 1, 3])
```
