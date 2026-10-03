-- 06_cohort_diagnostics.sql
-- Checks that decide how the cohort analysis is designed.
SET search_path = retail;

-- 1. When does each household first appear? (tests the ramp-up / left-censoring)
WITH f AS (
    SELECT household_key, MIN(day) AS first_day
    FROM transactions
    GROUP BY household_key
)
SELECT c.month_start AS first_basket_month,
       COUNT(*) AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_of_households,
       ROUND(100.0 * SUM(COUNT(*)) OVER (ORDER BY c.month_start)
             / SUM(COUNT(*)) OVER (), 1) AS cumulative_pct
FROM f
JOIN calendar c ON c.day = f.first_day
GROUP BY c.month_start
ORDER BY c.month_start;

-- 2. Do households drop out? Days between last basket and end of data
WITH l AS (
    SELECT household_key,
           (SELECT MAX(day) FROM calendar) - MAX(day) AS days_before_end
    FROM transactions
    GROUP BY household_key
)
SELECT CASE WHEN days_before_end <= 30  THEN 'a) last basket within final 30 days'
            WHEN days_before_end <= 90  THEN 'b) 31-90 days before end'
            WHEN days_before_end <= 180 THEN 'c) 91-180 days before end'
            ELSE                             'd) 180+ days before end (churned)'
       END AS last_seen,
       COUNT(*) AS households,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct
FROM l
GROUP BY 1
ORDER BY 1;

-- 3. Typical gap between shopping days (sets the "repeat visit" window)
WITH d AS (
    SELECT DISTINCT household_key, day FROM transactions
), g AS (
    SELECT day - LAG(day) OVER (PARTITION BY household_key ORDER BY day) AS gap
    FROM d
)
SELECT COUNT(gap) AS gaps_measured,
       (PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY gap))::int AS p50_days,
       (PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY gap))::int AS p75_days,
       (PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY gap))::int AS p90_days,
       (PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY gap))::int AS p95_days
FROM g;
