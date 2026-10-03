-- 01_schema.sql
-- Raw staging tables for the Dunnhumby "The Complete Journey" dataset.
-- Data is loaded as-is here and cleaned in later scripts.

CREATE SCHEMA IF NOT EXISTS retail;
SET search_path = retail;

CREATE TABLE stg_transaction_data (
    household_key       INT,
    basket_id           BIGINT,
    day                 INT,
    product_id          BIGINT,
    quantity            INT,
    sales_value         NUMERIC(10,2),
    store_id            INT,
    retail_disc         NUMERIC(10,2),
    trans_time          INT,
    week_no             INT,
    coupon_disc         NUMERIC(10,2),
    coupon_match_disc   NUMERIC(10,2)
);

CREATE TABLE stg_product (
    product_id            BIGINT,
    manufacturer          INT,
    department            TEXT,
    brand                 TEXT,
    commodity_desc        TEXT,
    sub_commodity_desc    TEXT,
    curr_size_of_product  TEXT
);

CREATE TABLE stg_hh_demographic (
    age_desc              TEXT,
    marital_status_code   TEXT,
    income_desc           TEXT,
    homeowner_desc        TEXT,
    hh_comp_desc          TEXT,
    household_size_desc   TEXT,
    kid_category_desc     TEXT,
    household_key         INT
);
