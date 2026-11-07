---
track: python-data
section: Batch · SQL
---

## Second Highest Salary
> difficulty: Easy | tags: SQL, subquery | leetcode: 176

Write a SQLite query over `employees(id, name, salary, dept)` that returns one row with one column: the second
highest *distinct* salary, or `NULL` if there isn't one. The tests run `QUERY` against an in-memory database.

```python starter
QUERY = """
SELECT ...
"""
```

```python solution
QUERY = """
SELECT (SELECT DISTINCT salary FROM employees ORDER BY salary DESC LIMIT 1 OFFSET 1) AS second
"""
```

```python tests
import sqlite3
def run(rows):
    db = sqlite3.connect(":memory:")
    db.execute("CREATE TABLE employees (id INT, name TEXT, salary INT, dept TEXT)")
    db.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)", rows)
    return db.execute(QUERY).fetchall()
check(run([(1, "a", 100, "x"), (2, "b", 200, "x"), (3, "c", 300, "y")]), [(200,)])
check(run([(1, "a", 100, "x"), (2, "b", 100, "y")]), [(None,)], "only one distinct salary")
check(run([(1, "a", 300, "x"), (2, "b", 300, "x"), (3, "c", 200, "y")]), [(200,)], "ties at the top")
```

## Top Earner per Department (window function)
> difficulty: Medium | tags: SQL, window functions | leetcode: 184

Return `(dept, name, salary)` for everyone paid the highest salary in their department, ordered by `dept`, then
`name`. Use `RANK() OVER (PARTITION BY …)`.

```python starter
QUERY = """
SELECT ...
"""
```

```python solution
QUERY = """
SELECT dept, name, salary FROM (
    SELECT dept, name, salary,
           RANK() OVER (PARTITION BY dept ORDER BY salary DESC) AS r
    FROM employees
) WHERE r = 1
ORDER BY dept, name
"""
```

```python tests
import sqlite3
db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE employees (id INT, name TEXT, salary INT, dept TEXT)")
db.executemany("INSERT INTO employees VALUES (?, ?, ?, ?)",
               [(1, "joe", 70, "it"), (2, "jim", 90, "it"), (3, "henry", 80, "sales"),
                (4, "sam", 60, "sales"), (5, "max", 90, "it")])
check(db.execute(QUERY).fetchall(), [("it", "jim", 90), ("it", "max", 90), ("sales", "henry", 80)])
```

## Running Total per User
> difficulty: Medium | tags: SQL, window functions

Over `payments(user_id, day, amount)`, return `(user_id, day, amount, running)` where `running` is that user's
cumulative amount through `day`, ordered by `user_id`, `day`.

```python starter
QUERY = """
SELECT ...
"""
```

```python solution
QUERY = """
SELECT user_id, day, amount,
       SUM(amount) OVER (PARTITION BY user_id ORDER BY day
                         ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running
FROM payments
ORDER BY user_id, day
"""
```

```python tests
import sqlite3
db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE payments (user_id INT, day INT, amount INT)")
db.executemany("INSERT INTO payments VALUES (?, ?, ?)", [(1, 2, 5), (1, 1, 10), (2, 1, 7), (1, 3, 1)])
check(db.execute(QUERY).fetchall(), [(1, 1, 10, 10), (1, 2, 5, 15), (1, 3, 1, 16), (2, 1, 7, 7)])
```

## Consecutive Login Streaks
> difficulty: Hard | tags: SQL, gaps and islands

`logins(user_id, day)` may contain duplicates. Return `(user_id, longest)` — each user's longest run of consecutive
days — ordered by `user_id`. Hint: `day - ROW_NUMBER()` is constant within a run.

```python starter
QUERY = """
SELECT ...
"""
```

```python solution
QUERY = """
WITH d AS (SELECT DISTINCT user_id, day FROM logins),
g AS (SELECT user_id, day - ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY day) AS grp FROM d),
runs AS (SELECT user_id, COUNT(*) AS len FROM g GROUP BY user_id, grp)
SELECT user_id, MAX(len) AS longest FROM runs GROUP BY user_id ORDER BY user_id
"""
```

```python tests
import sqlite3
db = sqlite3.connect(":memory:")
db.execute("CREATE TABLE logins (user_id INT, day INT)")
db.executemany("INSERT INTO logins VALUES (?, ?)",
               [(1, 1), (1, 2), (1, 2), (1, 3), (1, 7), (1, 8), (2, 5), (2, 7), (2, 8), (2, 9), (2, 10)])
check(db.execute(QUERY).fetchall(), [(1, 3), (2, 4)])
```
