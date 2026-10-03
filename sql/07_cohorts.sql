-- 07_cohorts.sql
-- Cohort analysis: which first-basket categories lead to more repeat visits?
-- DESIGN NOTES (from 06_cohort_diagnostics.sql):
--  * 99% of households first appear Jan-Apr 2010 (enrollment ramp-up), so
--    "first purchase month" is not a true acquisition date. Cohorts are
--    defined by first-basket CATEGORY instead.
--  * Only ~7% of households stop shopping, so "ever returned" cannot
--    discriminate. Outcome = distinct shopping days in the 90 days after
--    the first basket (typical gap between shops is 4 days).
--  * Larger first baskets come from heavier shoppers, so each category is
--    compared with households that had a similar-sized first basket.
SET search_path = retail;

DROP TABLE IF EXISTS cohort_category_results, cohort_retention, cohort_households;

-- =====================================================================
-- 1. One row per household: first basket, size tier, 90-day visits
-- A "visit" is a distinct shopping day, so a second basket on the same
-- day as the first does not count as a repeat visit.
-- in_scope = at least 570 days of follow-up (drops ~1% of late-appearing households)
-- =====================================================================
CREATE TABLE cohort_households AS
WITH ranked AS (
    SELECT household_key, basket_id, day, item_count,
           ROW_NUMBER() OVER (PARTITION BY household_key
                              ORDER BY day, trans_time, basket_id) AS rn
    FROM transactions
),
first_basket AS (
    SELECT household_key, basket_id AS first_basket_id,
           day AS first_day, item_count AS first_basket_items
    FROM ranked
    WHERE rn = 1
),
visits AS (
    SELECT f.household_key,
           COUNT(DISTINCT t.day) FILTER (WHERE t.day > f.first_day
                                           AND t.day <= f.first_day + 90) AS visits_90d
    FROM first_basket f
    JOIN transactions t USING (household_key)
    GROUP BY f.household_key, f.first_day
)
SELECT f.household_key, f.first_basket_id, f.first_day, f.first_basket_items,
       c.month_start AS cohort_month,
       CASE WHEN f.first_basket_items <= 3  THEN '1) 1-3 items'
            WHEN f.first_basket_items <= 7  THEN '2) 4-7 items'
            WHEN f.first_basket_items <= 14 THEN '3) 8-14 items'
            WHEN f.first_basket_items <= 29 THEN '4) 15-29 items'
            ELSE                                 '5) 30+ items'
       END AS size_tier,
       v.visits_90d,
       (f.first_day + 569 <= (SELECT MAX(day) FROM calendar)) AS in_scope
FROM first_basket f
JOIN visits v USING (household_key)
JOIN calendar c ON c.day = f.first_day;

ALTER TABLE cohort_households ADD PRIMARY KEY (household_key);

-- =====================================================================
-- 2. Retention by enrollment cohort (30-day periods since first basket)
-- Period 0 = first 30 days. A household is "active" in a period if it
-- shopped at least once in that period.
-- =====================================================================
CREATE TABLE cohort_retention AS
WITH active AS (
    SELECT DISTINCT h.household_key, h.cohort_month,
           (t.day - h.first_day) / 30 AS month_number
    FROM cohort_households h
    JOIN transactions t USING (household_key)
    WHERE h.in_scope
      AND t.day - h.first_day < 570
),
sizes AS (
    SELECT cohort_month, COUNT(*) AS cohort_size
    FROM cohort_households
    WHERE in_scope
    GROUP BY cohort_month
)
SELECT a.cohort_month, s.cohort_size, a.month_number,
       COUNT(*) AS active_households,
       ROUND(100.0 * COUNT(*) / s.cohort_size, 1) AS retention_pct
FROM active a
JOIN sizes s USING (cohort_month)
GROUP BY a.cohort_month, s.cohort_size, a.month_number;

-- =====================================================================
-- 3. Category cohorts: visits vs. expectation for a same-sized first basket
-- =====================================================================
CREATE TABLE cohort_category_results AS
WITH base AS (
    SELECT household_key, visits_90d,
           AVG(visits_90d) OVER (PARTITION BY size_tier) AS expected_visits
    FROM cohort_households
    WHERE in_scope
),
first_cats AS (
    SELECT DISTINCT h.household_key, p.commodity_desc AS category
    FROM cohort_households h
    JOIN transaction_items i ON i.basket_id = h.first_basket_id
    JOIN products p ON p.product_id = i.product_id
    WHERE h.in_scope AND p.is_merchandise
),
agg AS (
    SELECT fc.category,
           COUNT(*)                          AS households,
           AVG(b.visits_90d)                 AS avg_visits,
           AVG(b.expected_visits)            AS exp_visits,
           1.96 * STDDEV_SAMP(b.visits_90d - b.expected_visits)
                / SQRT(COUNT(*))             AS ci95
    FROM first_cats fc
    JOIN base b USING (household_key)
    GROUP BY fc.category
    HAVING COUNT(*) >= 100
)
SELECT category, households,
       ROUND(avg_visits, 2)                              AS avg_visits_90d,
       ROUND(exp_visits, 2)                              AS expected_visits,
       ROUND(avg_visits - exp_visits, 2)                 AS diff_visits,
       ROUND(100.0 * (avg_visits / exp_visits - 1), 1)   AS uplift_pct,
       ROUND(ci95::numeric, 2)                           AS ci95_visits,
       CASE WHEN ABS(avg_visits - exp_visits) > ci95
            THEN 'yes' ELSE 'no' END                     AS significant
FROM agg;

-- =====================================================================
-- 4. Results
-- =====================================================================

-- 4a. Scope
SELECT in_scope, COUNT(*) AS households FROM cohort_households GROUP BY in_scope;

-- 4b. Visits in 90 days by first-basket size (shows why we adjust for size)
SELECT size_tier,
       COUNT(*) AS households,
       ROUND(AVG(visits_90d), 2) AS avg_visits_90d,
       (PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY visits_90d))::numeric(5,1) AS median_visits
FROM cohort_households
WHERE in_scope
GROUP BY size_tier
ORDER BY size_tier;

-- 4c. Retention by enrollment cohort (% active in each 30-day period)
SELECT cohort_month, cohort_size AS households,
       MAX(retention_pct) FILTER (WHERE month_number = 1)  AS m1,
       MAX(retention_pct) FILTER (WHERE month_number = 2)  AS m2,
       MAX(retention_pct) FILTER (WHERE month_number = 3)  AS m3,
       MAX(retention_pct) FILTER (WHERE month_number = 6)  AS m6,
       MAX(retention_pct) FILTER (WHERE month_number = 9)  AS m9,
       MAX(retention_pct) FILTER (WHERE month_number = 12) AS m12,
       MAX(retention_pct) FILTER (WHERE month_number = 15) AS m15,
       MAX(retention_pct) FILTER (WHERE month_number = 18) AS m18
FROM cohort_retention
WHERE cohort_size >= 100
GROUP BY cohort_month, cohort_size
ORDER BY cohort_month;

-- 4d. Category cohorts: how many tested, how many significant
SELECT COUNT(*) AS categories_tested,
       COUNT(*) FILTER (WHERE significant = 'yes') AS significant_at_95pct
FROM cohort_category_results;

-- 4e. Categories whose first-basket households visit MOST (size-adjusted)
SELECT * FROM cohort_category_results ORDER BY uplift_pct DESC LIMIT 10;

-- 4f. Categories whose first-basket households visit LEAST (size-adjusted)
SELECT * FROM cohort_category_results ORDER BY uplift_pct ASC LIMIT 10;
