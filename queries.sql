-- ==== SETUP: clean analytical view (dedupe lines, treat missing discount as 0, compute sales & profit)
DROP VIEW IF EXISTS v_sales;
CREATE VIEW v_sales AS
SELECT oi.order_item_id, o.order_id, o.order_date,
       CAST(strftime('%Y', o.order_date) AS INTEGER) AS yr,
       strftime('%Y-%m', o.order_date)               AS ym,
       o.ship_mode, c.customer_id, c.customer_name, c.segment, c.region, c.country,
       p.category, p.sub_category, oi.quantity,
       COALESCE(oi.discount, 0) AS discount,
       ROUND(oi.quantity * p.unit_price * (1 - COALESCE(oi.discount, 0)), 2) AS sales,
       ROUND(oi.quantity * p.unit_price * (1 - COALESCE(oi.discount, 0))
             - oi.quantity * p.unit_cost, 2) AS profit
FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY order_id, product_id ORDER BY order_item_id) AS rn
      FROM order_items) oi
JOIN orders    o ON o.order_id    = oi.order_id
JOIN customers c ON c.customer_id = o.customer_id
JOIN products  p ON p.product_id  = oi.product_id
WHERE oi.rn = 1;

-- ==== Q1: Data quality checks on the raw tables
SELECT 'total order lines' AS check_name, COUNT(*) AS value FROM order_items
UNION ALL
SELECT 'duplicate order lines (same order + product)',
       COUNT(*) - COUNT(DISTINCT order_id || '-' || product_id) FROM order_items
UNION ALL
SELECT 'lines with NULL discount', COUNT(*) FROM order_items WHERE discount IS NULL
UNION ALL
SELECT 'order lines with no matching order', COUNT(*)
FROM order_items oi LEFT JOIN orders o ON o.order_id = oi.order_id WHERE o.order_id IS NULL
UNION ALL
SELECT 'orders with no order lines', COUNT(*)
FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.order_id WHERE oi.order_id IS NULL;

-- ==== Q2: Sales, profit, margin and share of total by region
SELECT region,
       ROUND(SUM(sales), 0)                                   AS total_sales,
       ROUND(SUM(profit), 0)                                  AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 1)             AS margin_pct,
       ROUND(100.0 * SUM(sales) / SUM(SUM(sales)) OVER (), 1) AS share_of_sales_pct
FROM v_sales
GROUP BY region
ORDER BY total_sales DESC;

-- ==== Q3: Top 10 customers by sales (CTE + RANK)
WITH cust AS (
    SELECT customer_id, customer_name, segment, region,
           COUNT(DISTINCT order_id) AS orders,
           SUM(sales)  AS total_sales,
           SUM(profit) AS total_profit
    FROM v_sales
    GROUP BY customer_id, customer_name, segment, region
)
SELECT RANK() OVER (ORDER BY total_sales DESC) AS sales_rank,
       customer_name, segment, region, orders,
       ROUND(total_sales, 0)  AS total_sales,
       ROUND(total_profit, 0) AS total_profit
FROM cust
ORDER BY sales_rank
LIMIT 10;

-- ==== Q4: Year-over-year sales and profit growth (LAG)
WITH yearly AS (
    SELECT yr, SUM(sales) AS sales, SUM(profit) AS profit
    FROM v_sales GROUP BY yr
)
SELECT yr,
       ROUND(sales, 0)  AS sales,
       ROUND(profit, 0) AS profit,
       ROUND(100.0 * (sales  - LAG(sales)  OVER (ORDER BY yr)) / LAG(sales)  OVER (ORDER BY yr), 1) AS sales_yoy_pct,
       ROUND(100.0 * (profit - LAG(profit) OVER (ORDER BY yr)) / LAG(profit) OVER (ORDER BY yr), 1) AS profit_yoy_pct
FROM yearly
ORDER BY yr;

-- ==== Q5: Sub-category profitability, flagging loss-making lines
SELECT category, sub_category,
       ROUND(SUM(sales), 0)                        AS total_sales,
       ROUND(SUM(profit), 0)                       AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 1)  AS margin_pct,
       ROUND(100 * AVG(discount), 1)               AS avg_discount_pct,
       CASE WHEN SUM(profit) < 0 THEN 'LOSS-MAKING' ELSE 'profitable' END AS status
FROM v_sales
GROUP BY category, sub_category
ORDER BY margin_pct;

-- ==== Q6: Does discounting hurt profit? Margin by discount bucket
SELECT CASE WHEN discount = 0    THEN '1. No discount'
            WHEN discount <= 0.1 THEN '2. Up to 10%'
            WHEN discount <= 0.3 THEN '3. 10-30%'
            ELSE                      '4. Over 30%' END AS discount_bucket,
       COUNT(*)                                     AS order_lines,
       ROUND(SUM(sales), 0)                         AS total_sales,
       ROUND(SUM(profit), 0)                        AS total_profit,
       ROUND(100.0 * SUM(profit) / SUM(sales), 1)   AS margin_pct
FROM v_sales
GROUP BY discount_bucket
ORDER BY discount_bucket;

-- ==== Q7: Ship mode analysis: orders and average order value
WITH order_totals AS (
    SELECT order_id, ship_mode, SUM(sales) AS order_value, COUNT(*) AS lines
    FROM v_sales GROUP BY order_id, ship_mode
)
SELECT ship_mode,
       COUNT(*)                     AS orders,
       ROUND(AVG(order_value), 1)   AS avg_order_value,
       ROUND(AVG(lines), 2)         AS avg_lines_per_order,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_of_orders_pct
FROM order_totals
GROUP BY ship_mode
ORDER BY orders DESC;

-- ==== Q8: Monthly sales for 2025 with 3-month moving average and running total
SELECT ym, monthly_sales, moving_avg_3m, ytd_sales
FROM (
    SELECT ym, yr,
           ROUND(SUM(sales), 0) AS monthly_sales,
           ROUND(AVG(SUM(sales)) OVER (ORDER BY ym ROWS BETWEEN 2 PRECEDING AND CURRENT ROW), 0) AS moving_avg_3m,
           ROUND(SUM(SUM(sales)) OVER (PARTITION BY yr ORDER BY ym), 0) AS ytd_sales
    FROM v_sales
    GROUP BY ym, yr
)
WHERE yr = 2025
ORDER BY ym;
