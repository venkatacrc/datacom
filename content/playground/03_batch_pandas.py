# title: Batch with pandas
# Load a static table, clean it, aggregate it. On the phone, pandas loads the first time (a few seconds).
import pandas as pd

from dc import orders

df = pd.DataFrame(orders(200, seed=11))
df["revenue"] = df["qty"] * df["price"]

daily = (df.groupby(["day", "category"], as_index=False)
           .agg(orders=("order_id", "count"), revenue=("revenue", "sum")))
print(daily.pivot(index="day", columns="category", values="revenue").round(2))

top = (df.groupby("customer")["revenue"].sum()
         .sort_values(ascending=False).head(3))
print("\nTop customers:\n" + top.round(2).to_string())
