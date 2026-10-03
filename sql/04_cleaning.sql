-- 04_cleaning.sql
-- Builds clean analytical tables from the raw staging tables.
-- Staging data is never modified. Safe to re-run (everything is rebuilt).
-- Decisions are based on the findings in 03_profiling.sql.
SET search_path = retail;

BEGIN;

DROP TABLE IF EXISTS transaction_items, transactions, customers, stores,
                     products, calendar, work_lines, cleaning_log CASCADE;

-- =====================================================================
-- 1. Table structure (primary and foreign keys)
-- =====================================================================
CREATE TABLE calendar (
    day            INT  PRIMARY KEY,
    calendar_date  DATE NOT NULL,
    week_no        INT  NOT NULL,
    month_start    DATE NOT NULL
);

CREATE TABLE products (
    product_id          BIGINT  PRIMARY KEY,
    manufacturer        INT,
    department          TEXT,
    brand               TEXT,
    commodity_desc      TEXT,      -- used as the "category" in later analysis
    sub_commodity_desc  TEXT,
    package_size        TEXT,
    is_merchandise      BOOLEAN NOT NULL
);

CREATE TABLE customers (
    household_key        INT     PRIMARY KEY,
    age_desc             TEXT,
    marital_status_code  TEXT,
    income_desc          TEXT,
    homeowner_desc       TEXT,
    hh_comp_desc         TEXT,
    household_size_desc  TEXT,
    kid_category_desc    TEXT,
    has_demographics     BOOLEAN NOT NULL
);

CREATE TABLE stores (
    store_id  INT PRIMARY KEY
);

CREATE TABLE transactions (
    basket_id      BIGINT        PRIMARY KEY,
    household_key  INT           NOT NULL REFERENCES customers (household_key),
    store_id       INT           NOT NULL REFERENCES stores (store_id),
    day            INT           NOT NULL REFERENCES calendar (day),
    trans_time     INT,          -- HHMM, e.g. 1631 = 16:31
    week_no        INT           NOT NULL,
    item_count     INT           NOT NULL,
    basket_value   NUMERIC(12,2) NOT NULL
);

CREATE TABLE transaction_items (
    line_id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    basket_id          BIGINT        NOT NULL REFERENCES transactions (basket_id),
    product_id         BIGINT        NOT NULL REFERENCES products (product_id),
    quantity           INT           NOT NULL,
    sales_value        NUMERIC(10,2) NOT NULL,
    retail_disc        NUMERIC(10,2),
    coupon_disc        NUMERIC(10,2),
    coupon_match_disc  NUMERIC(10,2),
    qty_flag           TEXT          -- 'ZERO_QTY' or 'QTY_OVER_100' (kept, but suspect)
);

-- =====================================================================
-- 2. Calendar
-- ASSUMPTION: Dunnhumby gives DAY numbers (1..711), not real dates.
-- Day 1 is mapped to 2010-01-01 so we can build monthly cohorts.
-- Only the labels depend on this anchor, not any result or ranking.
-- =====================================================================
INSERT INTO calendar (day, calendar_date, week_no, month_start)
SELECT day,
       DATE '2010-01-01' + (day - 1),
       MIN(week_no),
       DATE_TRUNC('month', DATE '2010-01-01' + (day - 1))::date
FROM stg_transaction_data
GROUP BY day;

-- =====================================================================
-- 3. Products: trim text, blank -> NULL, flag non-merchandise
-- Non-merchandise = fuel, coupons, misc transactions, store supplies,
-- postal, charity, expense lines, blank department/commodity.
-- Only EXACT placeholder names are excluded: real categories such as
-- 'CRACKERS/MISC BKD FD' or 'MISC WINE' stay in.
-- =====================================================================
WITH c AS (
    SELECT product_id,
           manufacturer,
           NULLIF(UPPER(TRIM(department)), '')         AS department,
           NULLIF(UPPER(TRIM(brand)), '')              AS brand,
           NULLIF(UPPER(TRIM(commodity_desc)), '')     AS commodity_desc,
           NULLIF(UPPER(TRIM(sub_commodity_desc)), '') AS sub_commodity_desc,
           NULLIF(TRIM(curr_size_of_product), '')      AS package_size
    FROM stg_product
)
INSERT INTO products
SELECT product_id, manufacturer, department, brand, commodity_desc,
       sub_commodity_desc, package_size,
       (    department IS NOT NULL
        AND department NOT IN ('KIOSK-GAS', 'MISC SALES TRAN', 'MISC. TRANS.',
                               'COUP/STR & MFG', 'CNTRL/STORE SUP', 'POSTAL CENTER',
                               'CHARITABLE CONT', 'GM MERCH EXP')
        AND commodity_desc IS NOT NULL
        AND commodity_desc NOT IN ('NO COMMODITY DESCRIPTION', 'COUPON/MISC ITEMS',
                                   'COUPONS/STORE & MFG', 'COUPON',
                                   'MISCELLANEOUS(CORP USE ONLY)')
       ) AS is_merchandise
FROM c;

-- =====================================================================
-- 4. Work table: every raw line with a drop reason (NULL = keep)
-- Rules, applied in order:
--   NO_REVENUE       sales_value is 0 or NULL (not a real purchase line)
--   NON_MERCHANDISE  product is flagged is_merchandise = false
-- =====================================================================
CREATE TABLE work_lines AS
SELECT t.*,
       CASE WHEN COALESCE(t.sales_value, 0) <= 0 THEN 'NO_REVENUE'
            WHEN NOT p.is_merchandise            THEN 'NON_MERCHANDISE'
       END AS drop_reason
FROM stg_transaction_data t
JOIN products p USING (product_id);

-- =====================================================================
-- 5. Cleaning log: how many rows each rule affected
-- =====================================================================
CREATE TABLE cleaning_log (
    step              INT PRIMARY KEY,
    rule              TEXT,
    action            TEXT,
    rows_affected     BIGINT,
    revenue_affected  NUMERIC(14,2)
);

INSERT INTO cleaning_log
SELECT 0, 'Raw lines in staging', 'start',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM stg_transaction_data;

INSERT INTO cleaning_log
SELECT 1, 'No revenue (sales_value = 0)', 'removed',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM work_lines WHERE drop_reason = 'NO_REVENUE';

INSERT INTO cleaning_log
SELECT 2, 'Non-merchandise (fuel, coupons, misc, blank)', 'removed',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM work_lines WHERE drop_reason = 'NON_MERCHANDISE';

INSERT INTO cleaning_log
SELECT 3, 'Quantity = 0 but revenue > 0', 'kept + flagged',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM work_lines WHERE drop_reason IS NULL AND COALESCE(quantity, 0) = 0;

INSERT INTO cleaning_log
SELECT 4, 'Quantity > 100', 'kept + flagged',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM work_lines WHERE drop_reason IS NULL AND quantity > 100;

INSERT INTO cleaning_log
SELECT 5, 'Clean lines in transaction_items', 'end',
       COUNT(*), COALESCE(SUM(sales_value), 0)
FROM work_lines WHERE drop_reason IS NULL;

-- =====================================================================
-- 6. Load clean tables (parents first, so foreign keys hold)
-- =====================================================================
INSERT INTO customers
SELECT k.household_key,
       d.age_desc, d.marital_status_code, d.income_desc, d.homeowner_desc,
       d.hh_comp_desc, d.household_size_desc, d.kid_category_desc,
       (d.household_key IS NOT NULL)
FROM (SELECT DISTINCT household_key FROM work_lines WHERE drop_reason IS NULL) k
LEFT JOIN (SELECT DISTINCT ON (household_key) *
           FROM stg_hh_demographic
           ORDER BY household_key) d USING (household_key);

INSERT INTO stores
SELECT DISTINCT store_id FROM work_lines WHERE drop_reason IS NULL;

-- One row per basket. Profiling confirmed each basket maps to exactly
-- one household, store and day, so MIN() is safe here.
INSERT INTO transactions (basket_id, household_key, store_id, day,
                          trans_time, week_no, item_count, basket_value)
SELECT basket_id, MIN(household_key), MIN(store_id), MIN(day),
       MIN(trans_time), MIN(week_no), COUNT(*), SUM(sales_value)
FROM work_lines
WHERE drop_reason IS NULL
GROUP BY basket_id;

INSERT INTO transaction_items (basket_id, product_id, quantity, sales_value,
                               retail_disc, coupon_disc, coupon_match_disc, qty_flag)
SELECT basket_id, product_id, COALESCE(quantity, 0), sales_value,
       retail_disc, coupon_disc, coupon_match_disc,
       CASE WHEN COALESCE(quantity, 0) = 0 THEN 'ZERO_QTY'
            WHEN quantity > 100            THEN 'QTY_OVER_100'
       END
FROM work_lines
WHERE drop_reason IS NULL;

DROP TABLE work_lines;

COMMIT;

ANALYZE;

-- =====================================================================
-- 7. Verification
-- =====================================================================

-- 7a. What each cleaning rule did
SELECT step, rule, action, rows_affected,
       ROUND(100.0 * rows_affected /
             FIRST_VALUE(rows_affected) OVER (ORDER BY step), 2) AS pct_of_raw_rows,
       revenue_affected
FROM cleaning_log
ORDER BY step;

-- 7b. Rows in each clean table
SELECT 'calendar' AS table_name, COUNT(*) AS row_count FROM calendar
UNION ALL SELECT 'products (all)', COUNT(*) FROM products
UNION ALL SELECT 'products (merchandise)', COUNT(*) FROM products WHERE is_merchandise
UNION ALL SELECT 'customers', COUNT(*) FROM customers
UNION ALL SELECT 'stores', COUNT(*) FROM stores
UNION ALL SELECT 'transactions', COUNT(*) FROM transactions
UNION ALL SELECT 'transaction_items', COUNT(*) FROM transaction_items;

-- 7c. Reconciliation: raw = removed + kept (unaccounted must be 0)
SELECT l0.rows_affected AS raw_rows,
       r.removed,
       k.kept,
       l0.rows_affected - r.removed - k.kept AS unaccounted
FROM cleaning_log l0
CROSS JOIN (SELECT SUM(rows_affected) AS removed
            FROM cleaning_log WHERE action = 'removed') r
CROSS JOIN (SELECT COUNT(*) AS kept FROM transaction_items) k
WHERE l0.step = 0;

-- 7d. Revenue ties out between items and baskets (the two must be equal)
SELECT (SELECT SUM(sales_value)  FROM transaction_items) AS item_revenue,
       (SELECT SUM(basket_value) FROM transactions)      AS basket_revenue;

-- 7e. Each day maps to exactly one week (must be 0)
SELECT COUNT(*) AS days_with_multiple_weeks
FROM (SELECT day FROM stg_transaction_data
      GROUP BY day HAVING COUNT(DISTINCT week_no) > 1) x;

-- 7f. Date range of the calendar
SELECT MIN(calendar_date) AS first_date, MAX(calendar_date) AS last_date,
       COUNT(*) AS days FROM calendar;
