-- 05_eda.sql
-- Exploratory analysis on the clean tables.
-- NOTE: calendar dates are synthetic (day 1 anchored to 2010-01-01), so
-- month-level trends are valid but day-of-week analysis is NOT.
SET search_path = retail;

-- 1. Monthly revenue and month-over-month growth (LAG)
-- days_in_data shows partial months (the data starts and ends mid-month).
WITH monthly AS (
    SELECT c.month_start,
           COUNT(DISTINCT t.day)            AS days_in_data,
           COUNT(*)                         AS baskets,
           COUNT(DISTINCT t.household_key)  AS active_households,
           SUM(t.basket_value)              AS revenue
    FROM transactions t
    JOIN calendar c USING (day)
    GROUP BY c.month_start
)
SELECT month_start, days_in_data, baskets, active_households,
       ROUND(revenue) AS revenue,
       ROUND(100.0 * (revenue - LAG(revenue) OVER (ORDER BY month_start))
             / NULLIF(LAG(revenue) OVER (ORDER BY month_start), 0), 1) AS mom_growth_pct,
       ROUND(revenue / days_in_data) AS revenue_per_day
FROM monthly
ORDER BY month_start;

-- 2. Top 10 stores by revenue (RANK, share of total)
SELECT RANK() OVER (ORDER BY SUM(basket_value) DESC) AS store_rank,
       store_id,
       ROUND(SUM(basket_value))                 AS revenue,
       COUNT(*)                                 AS baskets,
       COUNT(DISTINCT household_key)            AS households,
       ROUND(AVG(basket_value), 2)              AS avg_basket_value,
       ROUND(100.0 * SUM(basket_value)
             / SUM(SUM(basket_value)) OVER (), 2) AS pct_of_total_revenue
FROM transactions
GROUP BY store_id
ORDER BY revenue DESC
LIMIT 10;

-- 3. Top 15 categories (commodity) by revenue, with share and basket penetration
SELECT p.commodity_desc AS category,
       ROUND(SUM(i.sales_value))                AS revenue,
       ROUND(100.0 * SUM(i.sales_value)
             / SUM(SUM(i.sales_value)) OVER (), 2) AS revenue_share_pct,
       ROUND(100.0 * COUNT(DISTINCT i.basket_id)
             / (SELECT COUNT(*) FROM transactions), 1) AS pct_of_baskets_containing
FROM transaction_items i
JOIN products p USING (product_id)
GROUP BY p.commodity_desc
ORDER BY revenue DESC
LIMIT 15;

-- 4. Department revenue share
SELECT p.department,
       ROUND(SUM(i.sales_value))                AS revenue,
       ROUND(100.0 * SUM(i.sales_value)
             / SUM(SUM(i.sales_value)) OVER (), 1) AS revenue_share_pct
FROM transaction_items i
JOIN products p USING (product_id)
GROUP BY p.department
ORDER BY revenue DESC
LIMIT 10;

-- 5. Basket size and value (mean vs median shows skew)
SELECT COUNT(*)                                                    AS baskets,
       ROUND(AVG(basket_value), 2)                                 AS avg_basket_value,
       ROUND((PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY basket_value))::numeric, 2) AS median_basket_value,
       ROUND(AVG(item_count), 1)                                   AS avg_items,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY item_count))::int AS median_items,
       MAX(basket_value)                                           AS largest_basket
FROM transactions;

-- 6. Household engagement: how often do customers shop?
WITH h AS (
    SELECT household_key, COUNT(*) AS baskets, SUM(basket_value) AS spend
    FROM transactions
    GROUP BY household_key
)
SELECT COUNT(*)                                                       AS households,
       ROUND(AVG(baskets), 1)                                         AS avg_baskets_per_hh,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY baskets))::int    AS median_baskets_per_hh,
       ROUND(AVG(spend))                                              AS avg_spend_per_hh,
       ROUND(100.0 * COUNT(*) FILTER (WHERE baskets >= 2)  / COUNT(*), 1) AS pct_2plus_baskets,
       ROUND(100.0 * COUNT(*) FILTER (WHERE baskets >= 20) / COUNT(*), 1) AS pct_20plus_baskets
FROM h;

-- 7. Customer concentration: revenue share by spend decile (NTILE)
WITH h AS (
    SELECT household_key, SUM(basket_value) AS spend
    FROM transactions
    GROUP BY household_key
), d AS (
    SELECT spend, NTILE(10) OVER (ORDER BY spend DESC) AS spend_decile
    FROM h
)
SELECT spend_decile,
       COUNT(*)                                       AS households,
       ROUND(SUM(spend))                              AS revenue,
       ROUND(100.0 * SUM(spend) / SUM(SUM(spend)) OVER (), 1) AS pct_of_revenue
FROM d
GROUP BY spend_decile
ORDER BY spend_decile;

-- 8. Shopping by hour of day (trans_time is HHMM)
SELECT trans_time / 100 AS hour_of_day,
       COUNT(*)                                       AS baskets,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_baskets,
       ROUND(AVG(basket_value), 2)                    AS avg_basket_value
FROM transactions
GROUP BY trans_time / 100
ORDER BY hour_of_day;
