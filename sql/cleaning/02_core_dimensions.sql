/* =========================================================
   CORE DIMENSIONS (CLEANED) + INDEXES
   File: sql/cleaning/02_core_dimensions.sql
   Database: causal_analytics
   Depends on: Script 01 successful import + staging tables
   ========================================================= */

USE causal_analytics;

SET @old_sql_mode := @@SESSION.sql_mode;
SET SESSION sql_mode = '';

/* =========================================================
   PART A) CAMPAIGN DESCRIPTIONS (CLEAN)
   ========================================================= */

DROP TABLE IF EXISTS campaign_desc;
CREATE TABLE campaign_desc (
    campaign_id      INT UNSIGNED NOT NULL,
    start_day        DATE NULL,
    end_day          DATE NULL,
    start_day_num    INT UNSIGNED NULL,
    end_day_num      INT UNSIGNED NULL,
    campaign_type    VARCHAR(255) NULL,
    PRIMARY KEY (campaign_id),
    INDEX idx_campaign_desc_daynums (start_day_num, end_day_num)
);

INSERT INTO campaign_desc (campaign_id, start_day, end_day, start_day_num, end_day_num, campaign_type)
SELECT
    CAST(NULLIF(TRIM(REPLACE(campaign, '\r','')), '') AS UNSIGNED) AS campaign_id,

    CASE
      WHEN TRIM(REPLACE(start_day_raw, '\r','')) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN STR_TO_DATE(NULLIF(TRIM(REPLACE(start_day_raw, '\r','')), '0000-00-00'), '%Y-%m-%d')
      ELSE NULL
    END AS start_day,

    CASE
      WHEN TRIM(REPLACE(end_day_raw, '\r','')) REGEXP '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
        THEN STR_TO_DATE(NULLIF(TRIM(REPLACE(end_day_raw, '\r','')), '0000-00-00'), '%Y-%m-%d')
      ELSE NULL
    END AS end_day,

    CASE
      WHEN TRIM(REPLACE(start_day_raw, '\r','')) REGEXP '^[0-9]+$'
        THEN CAST(TRIM(REPLACE(start_day_raw, '\r','')) AS UNSIGNED)
      ELSE NULL
    END AS start_day_num,

    CASE
      WHEN TRIM(REPLACE(end_day_raw, '\r','')) REGEXP '^[0-9]+$'
        THEN CAST(TRIM(REPLACE(end_day_raw, '\r','')) AS UNSIGNED)
      ELSE NULL
    END AS end_day_num,

    NULLIF(TRIM(REPLACE(description, '\r','')), '') AS campaign_type
FROM campaign_desc_raw
WHERE NULLIF(TRIM(REPLACE(campaign, '\r','')), '') IS NOT NULL
  AND CAST(NULLIF(TRIM(REPLACE(campaign, '\r','')), '') AS UNSIGNED) > 0;


/* =========================================================
   PART B) PRODUCTS (DIM)
   ========================================================= */

DROP TABLE IF EXISTS dim_products;
CREATE TABLE dim_products AS
SELECT
    CAST(product_id AS UNSIGNED)                       AS product_id,
    CAST(manufacturer AS UNSIGNED)                     AS manufacturer_id,
    NULLIF(TRIM(REPLACE(department, '\r','')), '')     AS department,
    NULLIF(TRIM(REPLACE(brand, '\r','')), '')          AS brand,
    NULLIF(TRIM(REPLACE(commodity_desc, '\r','')), '') AS commodity_desc,
    NULLIF(TRIM(REPLACE(sub_commodity_desc, '\r','')), '') AS sub_commodity_desc
FROM product
WHERE product_id IS NOT NULL;

ALTER TABLE dim_products
  ADD PRIMARY KEY (product_id);

CREATE INDEX idx_dim_products_department ON dim_products (department);
CREATE INDEX idx_dim_products_commodity  ON dim_products (commodity_desc);


/* =========================================================
   PART C) CAMPAIGNS (DIM)
   ========================================================= */

DROP TABLE IF EXISTS dim_campaigns;
CREATE TABLE dim_campaigns AS
SELECT
    campaign_id,
    start_day,
    end_day,
    start_day_num,
    end_day_num,
    NULLIF(TRIM(REPLACE(campaign_type, '\r','')), '') AS campaign_type
FROM campaign_desc
WHERE campaign_id IS NOT NULL
  AND campaign_id > 0;

ALTER TABLE dim_campaigns
  ADD PRIMARY KEY (campaign_id);

CREATE INDEX idx_dim_campaigns_daynums ON dim_campaigns (start_day_num, end_day_num);


/* =========================================================
   PART D) CAMPAIGN HOUSEHOLDS (DIM)
   ========================================================= */

DROP TABLE IF EXISTS dim_campaign_households;
CREATE TABLE dim_campaign_households AS
SELECT
    CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED) AS campaign_id,
    CAST(household_key AS UNSIGNED) AS household_id,
    NULLIF(TRIM(REPLACE(description, '\r','')), '') AS description
FROM campaign_table
WHERE household_key IS NOT NULL
  AND NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') IS NOT NULL
  AND CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED) > 0;

CREATE INDEX idx_dim_campaign_households_campaign_household
    ON dim_campaign_households (campaign_id, household_id);

CREATE INDEX idx_dim_campaign_households_household
    ON dim_campaign_households (household_id);


/* =========================================================
   PART E) COUPONS (DIM)
   - keep coupon_upc as UNSIGNED numeric (UPC codes in file are numeric strings)
   ========================================================= */

DROP TABLE IF EXISTS dim_coupons;
CREATE TABLE dim_coupons AS
SELECT DISTINCT
    CAST(NULLIF(TRIM(REPLACE(coupon_upc_raw, '\r','')), '') AS UNSIGNED) AS coupon_upc,
    CAST(product_id AS UNSIGNED) AS product_id,
    CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED)  AS campaign_id
FROM coupon
WHERE NULLIF(TRIM(REPLACE(coupon_upc_raw, '\r','')), '') IS NOT NULL
  AND product_id IS NOT NULL
  AND NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') IS NOT NULL
  AND CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED) > 0;

CREATE INDEX idx_dim_coupons_campaign ON dim_coupons (campaign_id);
CREATE INDEX idx_dim_coupons_product  ON dim_coupons (product_id);
CREATE INDEX idx_dim_coupons_coupon   ON dim_coupons (coupon_upc);


/* =========================================================
   PART F) COUPON REDEMPTIONS (FACT-LIKE)
   ========================================================= */

DROP TABLE IF EXISTS fct_coupon_redemptions;
CREATE TABLE fct_coupon_redemptions AS
SELECT
    CAST(household_key AS UNSIGNED) AS household_id,
    CAST(day AS UNSIGNED) AS day,
    CAST(NULLIF(TRIM(REPLACE(coupon_upc_raw, '\r','')), '') AS UNSIGNED) AS coupon_upc,
    CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED) AS campaign_id
FROM coupon_redempt
WHERE household_key IS NOT NULL
  AND day IS NOT NULL
  AND NULLIF(TRIM(REPLACE(coupon_upc_raw, '\r','')), '') IS NOT NULL
  AND NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') IS NOT NULL
  AND CAST(NULLIF(TRIM(REPLACE(campaign_raw, '\r','')), '') AS UNSIGNED) > 0;

CREATE INDEX idx_fct_redemptions_household_campaign
    ON fct_coupon_redemptions (household_id, campaign_id);

CREATE INDEX idx_fct_redemptions_campaign_day
    ON fct_coupon_redemptions (campaign_id, day);

CREATE INDEX idx_fct_redemptions_coupon
    ON fct_coupon_redemptions (coupon_upc);


/* =========================================================
   PART G) OPTIONAL: CAMPAIGN↔COUPON↔PRODUCT BRIDGE (VERY USEFUL)
   - This is the clean join surface for purchase-based participation
   ========================================================= */

DROP TABLE IF EXISTS bridge_campaign_products;
CREATE TABLE bridge_campaign_products AS
SELECT DISTINCT
  dc.campaign_id,
  dc.product_id
FROM dim_coupons dc
WHERE dc.campaign_id IS NOT NULL
  AND dc.product_id IS NOT NULL;

CREATE INDEX idx_bridge_campaign_products
  ON bridge_campaign_products (campaign_id, product_id);


/* =========================================================
   PART H) QC + SANITY CHECKS
   ========================================================= */

-- Row counts
SELECT 'campaign_desc' AS table_name, COUNT(*) AS row_count FROM campaign_desc
UNION ALL SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL SELECT 'dim_campaigns', COUNT(*) FROM dim_campaigns
UNION ALL SELECT 'dim_campaign_households', COUNT(*) FROM dim_campaign_households
UNION ALL SELECT 'dim_coupons', COUNT(*) FROM dim_coupons
UNION ALL SELECT 'bridge_campaign_products', COUNT(*) FROM bridge_campaign_products
UNION ALL SELECT 'fct_coupon_redemptions', COUNT(*) FROM fct_coupon_redemptions;

-- Campaign ID integrity
SELECT
  SUM(campaign_id IS NULL) AS null_campaign_ids,
  SUM(campaign_id = 0)     AS zero_campaign_ids
FROM dim_campaigns;

-- Campaign daynum coverage
SELECT
  SUM(start_day_num IS NULL) AS null_start_day_num,
  SUM(end_day_num IS NULL)   AS null_end_day_num,
  MIN(start_day_num)         AS min_start_day_num,
  MAX(end_day_num)           AS max_end_day_num
FROM dim_campaigns;

-- Household mapping null checks
SELECT
  SUM(campaign_id IS NULL)  AS null_campaign_id,
  SUM(household_id IS NULL) AS null_household_id
FROM dim_campaign_households;

-- Redemption null checks
SELECT
  SUM(campaign_id IS NULL)  AS null_campaign_id,
  SUM(household_id IS NULL) AS null_household_id,
  SUM(coupon_upc IS NULL)   AS null_coupon_upc,
  SUM(day IS NULL)          AS null_day
FROM fct_coupon_redemptions;

-- NEW: Confirm coupon products exist in product master (helps purchase-based mapping)
SELECT
  COUNT(*) AS coupon_rows,
  SUM(p.product_id IS NOT NULL) AS coupon_products_in_master,
  ROUND(SUM(p.product_id IS NOT NULL)/COUNT(*), 4) AS coupon_product_match_rate
FROM dim_coupons c
LEFT JOIN dim_products p
  ON p.product_id = c.product_id;

-- NEW: Confirm bridge_campaign_products can be joined to stg_transactions (non-zero)
SELECT
  COUNT(*) AS bridge_txn_overlap_rows
FROM bridge_campaign_products b
JOIN stg_transactions t
  ON t.product_id = b.product_id;


/* =========================================================
   RESTORE SQL MODE
   ========================================================= */

SET SESSION sql_mode = @old_sql_mode;
