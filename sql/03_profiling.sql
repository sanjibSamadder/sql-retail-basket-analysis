-- 03_profiling.sql
-- Data quality profiling of the raw staging tables.
-- Results here drive the cleaning decisions in 04_cleaning.sql.
SET search_path = retail;

-- 1. Overview
SELECT COUNT(*)                      AS total_rows,
       COUNT(DISTINCT household_key) AS households,
       COUNT(DISTINCT basket_id)     AS baskets,
       COUNT(DISTINCT store_id)      AS stores,
       COUNT(DISTINCT product_id)    AS products_sold,
       MIN(day) AS first_day, MAX(day) AS last_day
FROM stg_transaction_data;

-- 2. Suspicious values
SELECT COUNT(*) FILTER (WHERE quantity = 0)       AS qty_zero,
       COUNT(*) FILTER (WHERE quantity < 0)       AS qty_negative,
       COUNT(*) FILTER (WHERE sales_value = 0)    AS sales_zero,
       COUNT(*) FILTER (WHERE sales_value < 0)    AS sales_negative,
       COUNT(*) FILTER (WHERE quantity > 100)     AS qty_over_100,
       COUNT(*) FILTER (WHERE household_key IS NULL OR basket_id IS NULL
                          OR product_id IS NULL OR store_id IS NULL) AS null_keys
FROM stg_transaction_data;

-- 3. Basket integrity: does each basket map to exactly one household, store and day?
SELECT COUNT(*) AS inconsistent_baskets
FROM (SELECT basket_id
      FROM stg_transaction_data
      GROUP BY basket_id
      HAVING COUNT(DISTINCT household_key) > 1
          OR COUNT(DISTINCT store_id) > 1
          OR COUNT(DISTINCT day) > 1) x;

-- 4. Fully identical duplicate rows
SELECT COUNT(*) AS rows_in_duplicate_groups,
       SUM(cnt - 1) AS extra_copies
FROM (SELECT COUNT(*) AS cnt
      FROM stg_transaction_data
      GROUP BY household_key, basket_id, day, product_id, quantity, sales_value,
               store_id, retail_disc, trans_time, week_no, coupon_disc, coupon_match_disc
      HAVING COUNT(*) > 1) d;

-- 5. Orphan and duplicate products
SELECT COUNT(DISTINCT t.product_id) AS products_missing_from_product_table
FROM stg_transaction_data t
LEFT JOIN stg_product p USING (product_id)
WHERE p.product_id IS NULL;

SELECT COUNT(*) - COUNT(DISTINCT product_id) AS duplicate_product_ids
FROM stg_product;

-- 6. Departments by revenue (spot the non-merchandise ones)
SELECT p.department,
       COUNT(*) AS lines,
       ROUND(SUM(t.sales_value)) AS revenue
FROM stg_transaction_data t
JOIN stg_product p USING (product_id)
GROUP BY p.department
ORDER BY revenue DESC;

-- 7. Placeholder categories
SELECT commodity_desc, COUNT(*) AS products
FROM stg_product
WHERE commodity_desc ILIKE '%NO COMMODITY%'
   OR commodity_desc ILIKE '%COUPON%'
   OR commodity_desc ILIKE '%MISC%'
   OR TRIM(commodity_desc) = ''
GROUP BY commodity_desc
ORDER BY products DESC;

-- 8. Demographics coverage
SELECT (SELECT COUNT(DISTINCT household_key) FROM stg_hh_demographic) AS hh_with_demographics,
       (SELECT COUNT(DISTINCT household_key) FROM stg_transaction_data) AS hh_with_transactions;
