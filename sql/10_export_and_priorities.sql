-- 10_export_and_priorities.sql
-- 1) Exports result tables to CSV (for charts), 2) ranks cross-sell opportunities by
-- excess baskets (observed - expected) so volume matters, not just ratio.
-- Run from the project root so the relative paths work.

\copy (SELECT c.month_start, COUNT(DISTINCT t.day) AS days_in_data, COUNT(*) AS baskets, COUNT(DISTINCT t.household_key) AS active_households, ROUND(SUM(t.basket_value)) AS revenue FROM retail.transactions t JOIN retail.calendar c USING (day) GROUP BY c.month_start ORDER BY c.month_start) TO 'results/monthly_revenue.csv' CSV HEADER

\copy (SELECT cohort_month, cohort_size, month_number, active_households, retention_pct FROM retail.cohort_retention ORDER BY cohort_month, month_number) TO 'results/cohort_retention.csv' CSV HEADER

\copy (SELECT * FROM retail.cohort_category_results ORDER BY uplift_pct DESC) TO 'results/cohort_category_results.csv' CSV HEADER

\copy (SELECT p.cat_a, p.cat_b, a.dept_a, a.dept_b, p.pair_baskets, p.support, p.confidence_a_to_b, p.confidence_b_to_a, a.naive_lift, a.expected_adj, a.adj_lift FROM retail.category_pairs p JOIN retail.category_pairs_adjusted a USING (cat_a, cat_b) WHERE p.pair_baskets >= 300 ORDER BY a.adj_lift DESC) TO 'results/category_pairs_adjusted.csv' CSV HEADER

\copy (SELECT * FROM retail.cleaning_log ORDER BY step) TO 'results/cleaning_log.csv' CSV HEADER

SET search_path = retail;

-- Opportunity ranking: pairs with real affinity (adjusted lift >= 1.5), by excess baskets
SELECT cat_a, cat_b, dept_a, dept_b, pair_baskets, expected_adj,
       pair_baskets - expected_adj AS excess_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift >= 1.5
ORDER BY excess_baskets DESC
LIMIT 15;

-- Same ranking restricted to different departments
SELECT cat_a, cat_b, dept_a, dept_b, pair_baskets, expected_adj,
       pair_baskets - expected_adj AS excess_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift >= 1.5 AND dept_a IS DISTINCT FROM dept_b
ORDER BY excess_baskets DESC
LIMIT 10;

-- Biggest substitute pairs by volume: baskets "missing" versus expectation
SELECT cat_a, cat_b, pair_baskets, expected_adj,
       expected_adj - pair_baskets AS missing_baskets,
       adj_lift
FROM category_pairs_adjusted
WHERE pair_baskets >= 300 AND adj_lift <= 0.7
ORDER BY missing_baskets DESC
LIMIT 10;
