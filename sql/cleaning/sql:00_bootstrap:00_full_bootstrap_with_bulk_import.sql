/* ============================================================
   CAUSAL_ANALYTICS — Script 01
   Bootstrap DB + Raw Imports + Staging Tables (MySQL Workbench / macOS)

   IMPORTANT (macOS path):
   Project folder renamed:
   /Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/...

   This script:
   1) Creates DB
   2) Drops + recreates raw tables
   3) Loads CSVs via LOAD DATA LOCAL INFILE
   4) Builds staging tables
   5) Adds indexes
   6) Runs sanity checks + two critical gates
   ============================================================ */

CREATE DATABASE IF NOT EXISTS causal_analytics
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_0900_ai_ci;

USE causal_analytics;

/* -------------------------
   Relax SQL mode for loads
   ------------------------- */
SET @old_sql_mode := @@SESSION.sql_mode;
SET SESSION sql_mode = '';

/* Optional speed-ups for bulk load */
SET @old_unique_checks := @@SESSION.unique_checks;
SET @old_fk_checks     := @@SESSION.foreign_key_checks;
SET SESSION unique_checks = 0;
SET SESSION foreign_key_checks = 0;

/* ============================================================
   0) DROP STAGING TABLES FIRST
   ============================================================ */
DROP TABLE IF EXISTS stg_transactions;
DROP TABLE IF EXISTS stg_households;

/* ============================================================
   1) DROP RAW TABLES
   ============================================================ */
DROP TABLE IF EXISTS coupon_redempt;
DROP TABLE IF EXISTS coupon;
DROP TABLE IF EXISTS campaign_table;
DROP TABLE IF EXISTS campaign_desc_raw;
DROP TABLE IF EXISTS product;
DROP TABLE IF EXISTS hh_demographic;
DROP TABLE IF EXISTS transaction_data;

/* ============================================================
   2) RAW TABLE DEFINITIONS
   ============================================================ */

/* TRANSACTIONS
   Correct column order per Complete Journey:
   household_key, BASKET_ID, DAY, PRODUCT_ID, QUANTITY, SALES_VALUE,
   STORE_ID, RETAIL_DISC, TRANS_TIME, WEEK_NO, COUPON_DISC
*/
CREATE TABLE transaction_data (
    household_key   INT,
    basket_id       BIGINT,
    day             INT,
    product_id      INT,
    quantity        INT,
    sales_value     DECIMAL(12,2),
    store_id        INT,
    retail_disc     DECIMAL(12,2),
    trans_time      INT,
    week_no         INT,
    coupon_disc     DECIMAL(12,2)
);

CREATE TABLE hh_demographic (
    household_key         INT,
    age_desc              VARCHAR(40),
    marital_status_code   VARCHAR(10),
    income_desc           VARCHAR(60),
    homeowner_desc        VARCHAR(40),
    hh_comp_desc          VARCHAR(60),
    household_size_desc   VARCHAR(20)
);

CREATE TABLE product (
    product_id            INT,
    manufacturer          INT,
    department            VARCHAR(100),
    brand                 VARCHAR(100),
    commodity_desc        VARCHAR(150),
    sub_commodity_desc    VARCHAR(150),
    curr_size_of_product  VARCHAR(50) NULL
);

/* Campaign metadata (cleaned later in Script 02) */
CREATE TABLE campaign_desc_raw (
    description    VARCHAR(255),
    campaign       VARCHAR(50),
    start_day_raw  VARCHAR(50),
    end_day_raw    VARCHAR(50)
);

CREATE TABLE campaign_table (
    description     VARCHAR(255),
    campaign_raw    VARCHAR(50),
    household_key   INT
);

CREATE TABLE coupon (
    coupon_upc_raw  VARCHAR(50),
    product_id      INT,
    campaign_raw    VARCHAR(50)
);

CREATE TABLE coupon_redempt (
    household_key   INT,
    day             INT,
    coupon_upc_raw  VARCHAR(50),
    campaign_raw    VARCHAR(50)
);

/* ============================================================
   3) BULK IMPORTS (LOAD DATA LOCAL INFILE)
   NOTE: Use literal file paths (Workbench-safe).
   ============================================================ */

LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/transaction_data.csv'
INTO TABLE transaction_data
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(household_key, basket_id, day, product_id, quantity, sales_value, store_id, retail_disc, trans_time, week_no, coupon_disc);

LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/hh_demographic.csv'
INTO TABLE hh_demographic
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(household_key, age_desc, marital_status_code, income_desc, homeowner_desc, hh_comp_desc, household_size_desc);

/* Some product.csv versions have 6 columns, some have 7.
   If your product.csv only has 6 cols, remove curr_size_of_product below.
*/
LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/product.csv'
INTO TABLE product
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(product_id, manufacturer, department, brand, commodity_desc, sub_commodity_desc, curr_size_of_product);

LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/campaign_desc.csv'
INTO TABLE campaign_desc_raw
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@description, @campaign, @start_day, @end_day)
SET
  description   = NULLIF(TRIM(REPLACE(@description, '\r', '')), ''),
  campaign      = NULLIF(TRIM(REPLACE(@campaign, '\r', '')), ''),
  start_day_raw = NULLIF(TRIM(REPLACE(@start_day, '\r', '')), ''),
  end_day_raw   = NULLIF(TRIM(REPLACE(@end_day, '\r', '')), '');

LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/campaign_table.csv'
INTO TABLE campaign_table
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@description, @campaign, @household_key)
SET
  description   = NULLIF(TRIM(REPLACE(@description, '\r', '')), ''),
  campaign_raw  = NULLIF(TRIM(REPLACE(@campaign, '\r', '')), ''),
  household_key = NULLIF(TRIM(REPLACE(@household_key, '\r', '')), '');

/* COUPON (fixed: literal path; no CONCAT) */
LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/coupon.csv'
INTO TABLE coupon
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@coupon_upc, @product_id, @campaign)
SET
  coupon_upc_raw = NULLIF(TRIM(REPLACE(@coupon_upc, '\r', '')), ''),
  product_id     = NULLIF(TRIM(REPLACE(@product_id, '\r', '')), ''),
  campaign_raw   = NULLIF(TRIM(REPLACE(@campaign, '\r', '')), '');

/* COUPON REDEMPT (fixed: literal path; no CONCAT) */
LOAD DATA LOCAL INFILE '/Users/rajnishpanwar/Desktop/Casual Analytics/data/raw/coupon_redempt.csv'
INTO TABLE coupon_redempt
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(@household_key, @day, @coupon_upc, @campaign)
SET
  household_key  = NULLIF(TRIM(REPLACE(@household_key, '\r', '')), ''),
  day            = NULLIF(TRIM(REPLACE(@day, '\r', '')), ''),
  coupon_upc_raw = NULLIF(TRIM(REPLACE(@coupon_upc, '\r', '')), ''),
  campaign_raw   = NULLIF(TRIM(REPLACE(@campaign, '\r', '')), '');

/* ============================================================
   4) STAGING TABLES
   ============================================================ */

CREATE TABLE stg_transactions AS
SELECT
  CAST(household_key AS UNSIGNED)      AS household_id,
  CAST(basket_id AS UNSIGNED)          AS basket_id,
  CAST(day AS UNSIGNED)                AS day,
  CAST(product_id AS UNSIGNED)         AS product_id,
  CAST(store_id AS UNSIGNED)           AS store_id,
  CAST(week_no AS UNSIGNED)            AS week_number,
  CAST(quantity AS SIGNED)             AS quantity,
  CAST(sales_value AS DECIMAL(12,2))   AS sales_value,
  CAST(retail_disc AS DECIMAL(12,2))   AS retail_discount,
  CAST(coupon_disc AS DECIMAL(12,2))   AS coupon_discount
FROM transaction_data
WHERE household_key IS NOT NULL
  AND product_id IS NOT NULL
  AND sales_value IS NOT NULL;

CREATE TABLE stg_households AS
SELECT
  CAST(household_key AS UNSIGNED) AS household_id,
  NULLIF(TRIM(REPLACE(age_desc, '\r', '')), '')               AS age_band,
  NULLIF(TRIM(REPLACE(marital_status_code, '\r', '')), '')    AS marital_status,
  NULLIF(TRIM(REPLACE(income_desc, '\r', '')), '')            AS income_band,
  NULLIF(TRIM(REPLACE(homeowner_desc, '\r', '')), '')         AS homeownership,
  NULLIF(TRIM(REPLACE(hh_comp_desc, '\r', '')), '')           AS household_composition,
  NULLIF(TRIM(REPLACE(household_size_desc, '\r', '')), '')    AS household_size
FROM hh_demographic
WHERE household_key IS NOT NULL;

/* ============================================================
   5) INDEXES
   ============================================================ */
CREATE INDEX idx_stg_transactions_household ON stg_transactions (household_id);
CREATE INDEX idx_stg_transactions_week      ON stg_transactions (week_number);
CREATE INDEX idx_stg_transactions_hh_week   ON stg_transactions (household_id, week_number);
CREATE INDEX idx_stg_transactions_product   ON stg_transactions (product_id);

CREATE INDEX idx_product_product_id         ON product (product_id);

CREATE INDEX idx_stg_households_household   ON stg_households (household_id);

/* ============================================================
   6) SANITY COUNTS
   ============================================================ */
SELECT 'transaction_data'  AS table_name, COUNT(*) AS row_count FROM transaction_data
UNION ALL SELECT 'hh_demographic',     COUNT(*) FROM hh_demographic
UNION ALL SELECT 'product',            COUNT(*) FROM product
UNION ALL SELECT 'campaign_desc_raw',  COUNT(*) FROM campaign_desc_raw
UNION ALL SELECT 'campaign_table',     COUNT(*) FROM campaign_table
UNION ALL SELECT 'coupon',             COUNT(*) FROM coupon
UNION ALL SELECT 'coupon_redempt',     COUNT(*) FROM coupon_redempt
UNION ALL SELECT 'stg_transactions',   COUNT(*) FROM stg_transactions
UNION ALL SELECT 'stg_households',     COUNT(*) FROM stg_households;

/* ============================================================
   7) CRITICAL GATES (must pass)
   ============================================================ */

-- Gate 1: transactions must include real product IDs (>> 711)
SELECT
  MAX(product_id) AS max_product_id,
  SUM(product_id > 711) AS rows_gt_711,
  COUNT(*) AS n_rows
FROM stg_transactions;

-- Gate 2: join overlap with product master must be > 0
SELECT COUNT(*) AS overlap_rows
FROM stg_transactions t
JOIN product p
  ON p.product_id = t.product_id;

/* ============================================================
   Restore settings
   ============================================================ */
SET SESSION unique_checks = @old_unique_checks;
SET SESSION foreign_key_checks = @old_fk_checks;
SET SESSION sql_mode = @old_sql_mode;
