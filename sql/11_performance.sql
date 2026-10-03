-- 11_performance.sql
-- Index tuning demo: EXPLAIN ANALYZE before and after adding indexes.
-- Query 1: all items in one basket.
-- Query 2: top categories by spend for one household (3-table join).
SET search_path = retail;

-- Start from a known state: no secondary indexes (safe to re-run)
DROP INDEX IF EXISTS idx_items_basket, idx_trans_household;
ANALYZE;

-- Pick a sample basket and household so both runs use identical inputs
SELECT basket_id AS sample_basket FROM transactions ORDER BY basket_id OFFSET 1000 LIMIT 1 \gset
SELECT household_key AS sample_hh FROM customers ORDER BY household_key OFFSET 500 LIMIT 1 \gset

-- Warm-up runs (results hidden) so both timings are measured on a warm cache
\o /dev/null
SELECT i.product_id, i.quantity, i.sales_value FROM transaction_items i WHERE i.basket_id = :sample_basket;
SELECT p.commodity_desc, SUM(i.sales_value) FROM transactions t JOIN transaction_items i ON i.basket_id = t.basket_id JOIN products p ON p.product_id = i.product_id WHERE t.household_key = :sample_hh GROUP BY p.commodity_desc;
\o

\echo '=== BEFORE INDEXES: Query 1 (basket lookup) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.product_id, i.quantity, i.sales_value
FROM transaction_items i
WHERE i.basket_id = :sample_basket;

\echo '=== BEFORE INDEXES: Query 2 (household category spend) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.commodity_desc, SUM(i.sales_value) AS spend
FROM transactions t
JOIN transaction_items i ON i.basket_id = t.basket_id
JOIN products p ON p.product_id = i.product_id
WHERE t.household_key = :sample_hh
GROUP BY p.commodity_desc
ORDER BY spend DESC
LIMIT 10;

-- Add indexes on the join/filter columns
CREATE INDEX idx_items_basket ON transaction_items (basket_id);
CREATE INDEX idx_trans_household ON transactions (household_key);
ANALYZE;

\echo '=== AFTER INDEXES: Query 1 (basket lookup) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.product_id, i.quantity, i.sales_value
FROM transaction_items i
WHERE i.basket_id = :sample_basket;

\echo '=== AFTER INDEXES: Query 2 (household category spend) ==='
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.commodity_desc, SUM(i.sales_value) AS spend
FROM transactions t
JOIN transaction_items i ON i.basket_id = t.basket_id
JOIN products p ON p.product_id = i.product_id
WHERE t.household_key = :sample_hh
GROUP BY p.commodity_desc
ORDER BY spend DESC
LIMIT 10;

\echo '=== Index sizes ==='
SELECT indexrelname AS index_name, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE schemaname = 'retail' AND indexrelname IN ('idx_items_basket', 'idx_trans_household');
