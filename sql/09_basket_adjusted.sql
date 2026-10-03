-- 09_basket_adjusted.sql
-- Basket-size-adjusted lift (stratified).
-- PROBLEM: in 08_basket_analysis.sql 96.5% of pairs had lift > 1 because large
-- baskets contain many categories, which inflates co-occurrence for every pair.
-- FIX: only baskets with 2+ categories can contain a pair, so keep those, split
-- them into 5 tiers by number of categories, and compute the expected pair
-- count within each tier:  expected = SUM over tiers of nA * nB / N_tier
-- adjusted_lift = observed pair baskets / expected pair baskets.
-- Depends on tables built by 08_basket_analysis.sql.
SET search_path = retail;

DROP TABLE IF EXISTS category_pairs_adjusted, category_dept,
                     cat_tier_counts, tier_sizes, basket_tier;

-- 1. Basket breadth tiers (baskets with 2+ categories only)
CREATE TABLE basket_tier AS
SELECT basket_id,
       COUNT(*) AS n_cats,
       CASE WHEN COUNT(*) <= 3  THEN 1
            WHEN COUNT(*) <= 6  THEN 2
            WHEN COUNT(*) <= 10 THEN 3
            WHEN COUNT(*) <= 15 THEN 4
            ELSE                     5 END AS tier
FROM basket_category
GROUP BY basket_id
HAVING COUNT(*) >= 2;

CREATE TABLE tier_sizes AS
SELECT tier, COUNT(*) AS n_baskets,
       MIN(n_cats) AS min_cats, MAX(n_cats) AS max_cats
FROM basket_tier
GROUP BY tier;

-- 2. Baskets per category within each tier
CREATE TABLE cat_tier_counts AS
SELECT bt.tier, bc.category, COUNT(*) AS n
FROM basket_category bc
JOIN basket_tier bt USING (basket_id)
GROUP BY bt.tier, bc.category;

CREATE INDEX idx_ctc ON cat_tier_counts (category, tier);

-- 3. Main department for each category (to find cross-department pairs)
CREATE TABLE category_dept AS
SELECT commodity_desc AS category,
       MODE() WITHIN GROUP (ORDER BY department) AS department
FROM products
WHERE is_merchandise
GROUP BY commodity_desc;

-- 4. Adjusted lift
CREATE TABLE category_pairs_adjusted AS
WITH expected AS (
    SELECT p.cat_a, p.cat_b,
           SUM(ca.n::numeric * cb.n / ts.n_baskets) AS exp_baskets
    FROM category_pairs p
    JOIN cat_tier_counts ca ON ca.category = p.cat_a
    JOIN cat_tier_counts cb ON cb.category = p.cat_b AND cb.tier = ca.tier
    JOIN tier_sizes ts ON ts.tier = ca.tier
    GROUP BY p.cat_a, p.cat_b
)
SELECT p.cat_a, p.cat_b,
       da.department AS dept_a, db.department AS dept_b,
       p.pair_baskets,
       p.lift AS naive_lift,
       ROUND(e.exp_baskets) AS expected_adj,
       ROUND(p.pair_baskets / e.exp_baskets, 2) AS adj_lift
FROM category_pairs p
JOIN expected e USING (cat_a, cat_b)
LEFT JOIN category_dept da ON da.category = p.cat_a
LEFT JOIN category_dept db ON db.category = p.cat_b;

-- =====================================================================
-- Results
-- =====================================================================

-- a) The tiers
SELECT tier, n_baskets, min_cats, max_cats FROM tier_sizes ORDER BY tier;

-- b) How much did the adjustment change things?
SELECT COUNT(*) AS pairs,
       COUNT(*) FILTER (WHERE naive_lift > 1) AS naive_above_1,
       COUNT(*) FILTER (WHERE adj_lift > 1)   AS adjusted_above_1,
       ROUND(100.0 * COUNT(*) FILTER (WHERE naive_lift > 1) / COUNT(*), 1) AS naive_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE adj_lift > 1)   / COUNT(*), 1) AS adjusted_pct,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY naive_lift))::numeric(6,2) AS median_naive_lift,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY adj_lift))::numeric(6,2)   AS median_adj_lift
FROM category_pairs_adjusted;

-- c) Top 15 by adjusted lift (pairs seen in >= 300 baskets)
SELECT cat_a, cat_b, pair_baskets, naive_lift, adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300
ORDER BY adj_lift DESC
LIMIT 15;

-- d) Top 15 CROSS-DEPARTMENT pairs by adjusted lift (least obvious affinities)
SELECT cat_a, dept_a, cat_b, dept_b, pair_baskets, adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND dept_a IS DISTINCT FROM dept_b
ORDER BY adj_lift DESC
LIMIT 15;

-- e) Bottom 10 by adjusted lift (categories that avoid each other)
SELECT cat_a, cat_b, pair_baskets, expected_adj, adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300
ORDER BY adj_lift ASC
LIMIT 10;

-- f) Do the headline pairs from 08 survive the adjustment?
SELECT cat_a, cat_b, pair_baskets, naive_lift, adj_lift
FROM category_pairs_adjusted
WHERE (cat_a, cat_b) IN (('BAKED BREAD/BUNS/ROLLS', 'FLUID MILK PRODUCTS'),
                         ('COLD CEREAL', 'FLUID MILK PRODUCTS'),
                         ('BAG SNACKS', 'SOFT DRINKS'),
                         ('CAT FOOD', 'CAT LITTER'),
                         ('CIGARETTES', 'YOGURT'),
                         ('CHEESES', 'DELI MEATS'))
   OR (cat_a, cat_b) IN (('BAKED BREAD/BUNS/ROLLS', 'HOT DOGS'),
                         ('DELI MEATS', 'BAKED BREAD/BUNS/ROLLS'))
ORDER BY adj_lift DESC;
