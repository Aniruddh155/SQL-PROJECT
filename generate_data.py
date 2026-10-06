"""Generates a synthetic retail sales database (SQLite) for the SQL analysis project.
Data is randomly generated (seeded, reproducible). It is NOT real company data.
A small number of duplicates and NULL discounts are injected on purpose so the
data-quality checks in queries.sql have something real to find."""
import sqlite3, random, datetime as dt, os

random.seed(42)
DB = "sales.db"
if os.path.exists(DB):
    os.remove(DB)
con = sqlite3.connect(DB)
cur = con.cursor()

cur.executescript("""
CREATE TABLE customers (customer_id INTEGER PRIMARY KEY, customer_name TEXT, segment TEXT, region TEXT, country TEXT);
CREATE TABLE products (product_id INTEGER PRIMARY KEY, product_name TEXT, category TEXT, sub_category TEXT, unit_price REAL, unit_cost REAL);
CREATE TABLE orders (order_id INTEGER PRIMARY KEY, order_date TEXT, customer_id INTEGER, ship_mode TEXT);
CREATE TABLE order_items (order_item_id INTEGER PRIMARY KEY, order_id INTEGER, product_id INTEGER, quantity INTEGER, discount REAL);
""")

# Customers
first = ["Aarav","Priya","Rohan","Sneha","Vikram","Ananya","Karan","Meera","Arjun","Ishita","Rahul","Neha","Dev","Kavya","Sahil","Tanvi","Nikhil","Pooja","Yash","Riya"]
last = ["Sharma","Verma","Singh","Gupta","Nair","Mehta","Kapoor","Reddy","Das","Joshi","Malik","Bose","Iyer","Khan","Patel"]
regions = {"North":["India","Nepal"],"South":["India","Sri Lanka"],"East":["India","Bangladesh"],"West":["India","UAE"]}
region_w = [0.22,0.30,0.18,0.30]
segments = ["Consumer","Corporate","Home Office"]
customers, seen = [], set()
while len(customers) < 250:
    n = f"{random.choice(first)} {random.choice(last)}"
    if n in seen: continue
    seen.add(n)
    r = random.choices(list(regions), region_w)[0]
    customers.append((len(customers)+1, n, random.choice(segments), r, random.choice(regions[r])))
cur.executemany("INSERT INTO customers VALUES (?,?,?,?,?)", customers)

# Products: (category, sub_category, base_price, margin, max_discount)
subcats = [
 ("Technology","Phones",450,0.30,0.15),("Technology","Copiers",900,0.35,0.10),
 ("Technology","Accessories",60,0.40,0.20),("Technology","Machines",600,0.25,0.20),
 ("Furniture","Chairs",250,0.28,0.25),("Furniture","Tables",400,0.12,0.45),
 ("Furniture","Bookcases",300,0.20,0.30),("Furniture","Furnishings",40,0.38,0.20),
 ("Office Supplies","Binders",12,0.10,0.50),("Office Supplies","Paper",8,0.45,0.10),
 ("Office Supplies","Storage",55,0.30,0.20),("Office Supplies","Art",15,0.42,0.15),
]
products, subinfo = [], {}
pid = 1
for cat, sub, price, margin, maxd in subcats:
    for i in range(1, 5):
        p = round(price * random.uniform(0.7, 1.4), 2)
        c = round(p * (1 - margin * random.uniform(0.85, 1.15)), 2)
        products.append((pid, f"{sub} Model {i}", cat, sub, p, c))
        subinfo[pid] = maxd
        pid += 1
cur.executemany("INSERT INTO products VALUES (?,?,?,?,?,?)", products)

# Orders and items, 2022-2025, growing volume with seasonality
ship_modes = ["Standard","Express","Same Day","Economy"]
ship_w = [0.55,0.2,0.05,0.2]
orders, items = [], []
oid, iid = 1, 1
year_orders = {2022:900, 2023:1100, 2024:1350, 2025:1500}
for yr, n in year_orders.items():
    for _ in range(n):
        month = random.choices(range(1,13), [6,6,7,7,8,8,7,8,9,10,12,13])[0]
        day = random.randint(1, 28)
        d = dt.date(yr, month, day).isoformat()
        orders.append((oid, d, random.choice(customers)[0], random.choices(ship_modes, ship_w)[0]))
        k = random.choices([1,2,3,4],[50,30,15,5])[0]
        for prod in random.sample(products, k):   # distinct products within an order
            p = prod[0]
            disc = round(random.choice([0,0,0,0.05,0.1,0.15,0.2,0.3,0.4,0.5]) * (subinfo[p] / 0.5), 2)
            disc = min(disc, subinfo[p])
            items.append([iid, oid, p, random.randint(1,6), disc])
            iid += 1
        oid += 1
cur.executemany("INSERT INTO orders VALUES (?,?,?,?)", orders)

# Inject data-quality issues on purpose
for row in random.sample(items, 25):          # exact duplicate order lines
    items.append([iid, row[1], row[2], row[3], row[4]]); iid += 1
for row in random.sample(items, 20):          # missing discounts
    row[4] = None
cur.executemany("INSERT INTO order_items VALUES (?,?,?,?,?)", items)

con.commit()
for t in ["customers","products","orders","order_items"]:
    print(t, cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0])
con.close()
