-- 08_basket_analysis.sql
-- Market basket analysis at commodity (category) level.
--   support    = share of ALL baskets containing both A and B
--   confidence = P(B in basket | A in basket)
--   lift       = confidence / P(B)  (>1: bought together more than chance)
-- Filters: category must appear in >= 1,000 baskets (~0.4%) and a pair
-- must co-occur in >= 100 baskets, so lift is not driven by tiny counts.
SET search_path = retail;

DROP TABLE IF EXISTS category_pairs, category_stats, basket_category;

-- 1. One row per (basket, category), merchandise only
CREATE TABLE basket_category AS
SELECT DISTINCT i.basket_id, p.commodity_desc AS category
FROM transaction_items i
JOIN products p USING (product_id)
WHERE p.is_merchandise AND p.commodity_desc IS NOT NULL;

-- 2. Category frequencies (computed on ALL categories, before filtering)
CREATE TABLE category_stats AS
SELECT category, COUNT(*) AS baskets_with_cat
FROM basket_category
GROUP BY category;

-- 3. Drop rare categories, then index for the self-join
DELETE FROM basket_category bc
USING category_stats s
WHERE bc.category = s.category AND s.baskets_with_cat < 1000;

CREATE INDEX idx_bc_basket ON basket_category (basket_id);
ANALYZE basket_category;

-- 4. Category pairs (a.category < b.category counts each pair once)
CREATE TABLE category_pairs AS
WITH n AS (SELECT COUNT(*)::numeric AS total FROM transactions),
pairs AS (
    SELECT a.category AS cat_a, b.category AS cat_b, COUNT(*) AS pair_baskets
    FROM basket_category a
    JOIN basket_category b
      ON a.basket_id = b.basket_id AND a.category < b.category
    GROUP BY a.category, b.category
    HAVING COUNT(*) >= 100
)
SELECT p.cat_a, p.cat_b, p.pair_baskets,
       ROUND(p.pair_baskets / n.total, 5)                            AS support,
       ROUND(p.pair_baskets::numeric / sa.baskets_with_cat, 3)       AS confidence_a_to_b,
       ROUND(p.pair_baskets::numeric / sb.baskets_with_cat, 3)       AS confidence_b_to_a,
       ROUND((sa.baskets_with_cat::numeric * sb.baskets_with_cat) / n.total) AS expected_baskets,
       ROUND((p.pair_baskets * n.total)
             / (sa.baskets_with_cat::numeric * sb.baskets_with_cat), 2) AS lift
FROM pairs p
CROSS JOIN n
JOIN category_stats sa ON sa.category = p.cat_a
JOIN category_stats sb ON sb.category = p.cat_b;

-- =====================================================================
-- Results
-- =====================================================================

-- a) Scope
SELECT (SELECT COUNT(*) FROM transactions)                       AS total_baskets,
       (SELECT COUNT(DISTINCT category) FROM basket_category)    AS categories_kept,
       (SELECT COUNT(*) FROM category_pairs)                     AS pairs_analysed,
       (SELECT COUNT(*) FROM category_pairs WHERE lift > 1)      AS pairs_lift_above_1;

-- b) Strongest affinities: top 15 by lift (pairs seen in >= 300 baskets)
SELECT cat_a, cat_b, pair_baskets, expected_baskets, support,
       confidence_a_to_b, confidence_b_to_a, lift
FROM category_pairs
WHERE pair_baskets >= 300
ORDER BY lift DESC
LIMIT 15;

-- c) Most common pairs: top 15 by support
SELECT cat_a, cat_b, pair_baskets, support, lift
FROM category_pairs
ORDER BY pair_baskets DESC
LIMIT 15;

-- d) Cross-sell rules "buyers of A also buy B": high confidence AND lift >= 1.5
WITH rules AS (
    SELECT cat_a AS if_basket_has, cat_b AS then_also_has,
           pair_baskets, confidence_a_to_b AS confidence, lift FROM category_pairs
    UNION ALL
    SELECT cat_b, cat_a, pair_baskets, confidence_b_to_a, lift FROM category_pairs
)
SELECT *
FROM rules
WHERE lift >= 1.5 AND pair_baskets >= 300
ORDER BY confidence DESC
LIMIT 15;

-- e) Weakest pairings (lift below 1): categories that tend NOT to share a basket
SELECT cat_a, cat_b, pair_baskets, expected_baskets, lift
FROM category_pairs
WHERE pair_baskets >= 300
ORDER BY lift ASC
LIMIT 10;
