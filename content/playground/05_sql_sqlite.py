# title: SQL with sqlite3
# An in-memory database for practising joins and window functions.
import sqlite3

from dc import orders

db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE orders (order_id INT, customer TEXT, product TEXT, category TEXT, qty INT, price REAL, day INT)")
db.executemany("INSERT INTO orders VALUES (:order_id, :customer, :product, :category, :qty, :price, :day)", orders(100))

query = """
SELECT customer,
       SUM(qty * price)                              AS revenue,
       RANK() OVER (ORDER BY SUM(qty * price) DESC)  AS rnk
FROM orders
GROUP BY customer
ORDER BY rnk
LIMIT 5
"""
for row in db.execute(query):
    print(row)
