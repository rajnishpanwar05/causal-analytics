/* ============================================================================
File: sql/cohorting/03_cohort_campaign_participation.sql
DB: causal_analytics

Purchase-based cohorting panel (DiD-ready) with CONTROL PRESERVATION.

Key parameters:
- pre_weeks  = 8
- post_weeks = 8

Core fix vs previous version:
- Guarantee anchor_week is NOT NULL for every (campaign_id, household_id)
  by adding robust campaign_start_week fallback + global fallback.
- Build full rel_week grid (-8..+8) for ALL assigned households.
- Left join weekly revenue; missing weeks => zeros.

Dependencies (must exist):
- dim_campaign_households(campaign_id, household_id, description)
- dim_campaigns(campaign_id, start_day_num, end_day_num, campaign_type)
- bridge_campaign_products(campaign_id, product_id)
- stg_transactions(household_id, week_number, day, product_id, sales_value, quantity,
                   retail_discount, coupon_discount)

Output:
- did_campaign_panel_purchase

============================================================================ */

USE causal_analytics;

SET @pre_weeks  := 8;
SET @post_weeks := 8;

/* -----------------------------
0) Global fallback week (ultimate safety)
----------------------------- */
DROP TABLE IF EXISTS global_week_fallback;

CREATE TABLE global_week_fallback AS
SELECT
  MIN(CAST(week_number AS SIGNED)) AS global_min_week,
  MAX(CAST(week_number AS SIGNED)) AS global_max_week
FROM stg_transactions
WHERE week_number IS NOT NULL;

CREATE INDEX idx_global_week_fallback ON global_week_fallback (global_min_week);

/* -----------------------------
A) Assigned households
----------------------------- */
DROP TABLE IF EXISTS cohort_campaign_assigned_households;

CREATE TABLE cohort_campaign_assigned_households AS
SELECT
  CAST(campaign_id AS UNSIGNED)  AS campaign_id,
  CAST(household_id AS UNSIGNED) AS household_id,
  description
FROM dim_campaign_households;

CREATE INDEX idx_cohort_assigned_campaign_household
  ON cohort_campaign_assigned_households (campaign_id, household_id);

/* -----------------------------
B) Household-week revenue (ALL transactions)
----------------------------- */
DROP TABLE IF EXISTS fct_household_week_revenue;

CREATE TABLE fct_household_week_revenue AS
SELECT
  CAST(t.household_id AS UNSIGNED) AS household_id,
  CAST(t.week_number AS SIGNED)    AS week_number,
  SUM(COALESCE(t.sales_value, 0))  AS total_sales_value,
  SUM(COALESCE(t.quantity, 0))     AS total_units,
  SUM(COALESCE(t.retail_discount, 0)) AS total_retail_discount,
  SUM(COALESCE(t.coupon_discount, 0)) AS total_coupon_discount
FROM stg_transactions t
WHERE t.household_id IS NOT NULL
  AND t.week_number IS NOT NULL
GROUP BY
  CAST(t.household_id AS UNSIGNED),
  CAST(t.week_number AS SIGNED);

CREATE INDEX idx_fct_hh_week_household_week
  ON fct_household_week_revenue (household_id, week_number);

CREATE INDEX idx_fct_hh_week_week
  ON fct_household_week_revenue (week_number);

/* -----------------------------
C) Robust campaign_start_week (NEW)
   - For each campaign, find the first observed week_number on/after start_day_num
   - This is more robust than limiting to campaign-window transactions only.
----------------------------- */
DROP TABLE IF EXISTS campaign_start_week;

CREATE TABLE campaign_start_week AS
SELECT
  c.campaign_id,
  MIN(CAST(t.week_number AS SIGNED)) AS campaign_start_week
FROM dim_campaigns c
JOIN stg_transactions t
  ON t.day >= c.start_day_num
WHERE t.week_number IS NOT NULL
GROUP BY c.campaign_id;

CREATE INDEX idx_campaign_start_week_campaign
  ON campaign_start_week (campaign_id);

/* -----------------------------
D) Campaign week bounds (still useful, but no longer critical)
----------------------------- */
DROP TABLE IF EXISTS campaign_week_bounds;

CREATE TABLE campaign_week_bounds AS
SELECT
  c.campaign_id,
  MIN(CAST(t.week_number AS SIGNED)) AS min_week_obs,
  MAX(CAST(t.week_number AS SIGNED)) AS max_week_obs
FROM dim_campaigns c
JOIN stg_transactions t
  ON t.day BETWEEN c.start_day_num AND c.end_day_num
WHERE t.week_number IS NOT NULL
GROUP BY c.campaign_id;

CREATE INDEX idx_campaign_week_bounds_campaign
  ON campaign_week_bounds (campaign_id);

/* -----------------------------
E) Treated households (purchase-based)
----------------------------- */
DROP TABLE IF EXISTS cohort_campaign_treated_households;

CREATE TABLE cohort_campaign_treated_households AS
SELECT
  a.campaign_id,
  a.household_id,
  MIN(t.day)             AS first_participation_day,
  MIN(CAST(t.week_number AS SIGNED)) AS first_participation_week
FROM cohort_campaign_assigned_households a
JOIN dim_campaigns c
  ON c.campaign_id = a.campaign_id
JOIN bridge_campaign_products b
  ON b.campaign_id = a.campaign_id
JOIN stg_transactions t
  ON t.household_id = a.household_id
 AND t.product_id   = b.product_id
 AND t.day BETWEEN c.start_day_num AND c.end_day_num
WHERE t.week_number IS NOT NULL
GROUP BY a.campaign_id, a.household_id;

CREATE INDEX idx_cohort_treated_campaign_household
  ON cohort_campaign_treated_households (campaign_id, household_id);

/* -----------------------------
F) Control households
----------------------------- */
DROP TABLE IF EXISTS cohort_campaign_control_households;

CREATE TABLE cohort_campaign_control_households AS
SELECT
  a.campaign_id,
  a.household_id
FROM cohort_campaign_assigned_households a
LEFT JOIN cohort_campaign_treated_households th
  ON th.campaign_id = a.campaign_id
 AND th.household_id = a.household_id
WHERE th.household_id IS NULL;

CREATE INDEX idx_cohort_control_campaign_household
  ON cohort_campaign_control_households (campaign_id, household_id);

/* -----------------------------
G) Treated anchor week (bounded when bounds exist)
----------------------------- */
DROP TABLE IF EXISTS treated_anchor_week;

CREATE TABLE treated_anchor_week AS
SELECT
  th.campaign_id,
  th.household_id,
  CASE
    WHEN cb.min_week_obs IS NULL OR cb.max_week_obs IS NULL THEN th.first_participation_week
    WHEN th.first_participation_week < cb.min_week_obs THEN cb.min_week_obs
    WHEN th.first_participation_week > cb.max_week_obs THEN cb.max_week_obs
    ELSE th.first_participation_week
  END AS anchor_week
FROM cohort_campaign_treated_households th
LEFT JOIN campaign_week_bounds cb
  ON cb.campaign_id = th.campaign_id;

CREATE INDEX idx_treated_anchor_campaign_household
  ON treated_anchor_week (campaign_id, household_id);

/* -----------------------------
H) Campaign default anchor (median treated anchor when available)
   - MySQL 8 window functions; if treated set empty, campaign not present in this table.
----------------------------- */
DROP TABLE IF EXISTS campaign_default_anchor;

CREATE TABLE campaign_default_anchor AS
SELECT
  x.campaign_id,
  CAST(AVG(x.anchor_week) AS SIGNED) AS default_anchor_week
FROM (
  SELECT
    t.campaign_id,
    t.anchor_week,
    ROW_NUMBER() OVER (PARTITION BY t.campaign_id ORDER BY t.anchor_week) AS rn,
    COUNT(*) OVER (PARTITION BY t.campaign_id) AS cnt
  FROM treated_anchor_week t
) x
WHERE x.rn IN (FLOOR((x.cnt + 1)/2), FLOOR((x.cnt + 2)/2))
GROUP BY x.campaign_id;

CREATE INDEX idx_campaign_default_anchor_campaign
  ON campaign_default_anchor (campaign_id);

/* -----------------------------
I) Final anchor per assigned household (CRITICAL FIX)
   Fallback order (guarantees non-null):
   1) treated anchor_week
   2) median treated anchor for campaign
   3) campaign_start_week (NEW)
   4) campaign_week_bounds.min_week_obs (extra)
   5) global_min_week (ultimate)
----------------------------- */
DROP TABLE IF EXISTS cohort_household_anchor_week;

CREATE TABLE cohort_household_anchor_week AS
SELECT
  a.campaign_id,
  a.household_id,
  COALESCE(
    taw.anchor_week,
    cda.default_anchor_week,
    csw.campaign_start_week,
    cb.min_week_obs,
    gw.global_min_week
  ) AS anchor_week
FROM cohort_campaign_assigned_households a
LEFT JOIN treated_anchor_week taw
  ON taw.campaign_id = a.campaign_id
 AND taw.household_id = a.household_id
LEFT JOIN campaign_default_anchor cda
  ON cda.campaign_id = a.campaign_id
LEFT JOIN campaign_start_week csw
  ON csw.campaign_id = a.campaign_id
LEFT JOIN campaign_week_bounds cb
  ON cb.campaign_id = a.campaign_id
CROSS JOIN global_week_fallback gw;

CREATE INDEX idx_cohort_hh_anchor_campaign_household
  ON cohort_household_anchor_week (campaign_id, household_id);

/* -----------------------------
J) rel_week grid: -8..+8 (17 rows)
----------------------------- */
DROP TABLE IF EXISTS rel_week_grid;

CREATE TABLE rel_week_grid AS
SELECT -8 AS rel_week
UNION ALL SELECT -7
UNION ALL SELECT -6
UNION ALL SELECT -5
UNION ALL SELECT -4
UNION ALL SELECT -3
UNION ALL SELECT -2
UNION ALL SELECT -1
UNION ALL SELECT 0
UNION ALL SELECT 1
UNION ALL SELECT 2
UNION ALL SELECT 3
UNION ALL SELECT 4
UNION ALL SELECT 5
UNION ALL SELECT 6
UNION ALL SELECT 7
UNION ALL SELECT 8;

CREATE INDEX idx_rel_week_grid_relweek
  ON rel_week_grid (rel_week);

/* -----------------------------
K) Final DiD panel (purchase-based)
   - full 17-week grid for EVERY assigned unit
   - missing weeks => zeros
----------------------------- */
DROP TABLE IF EXISTS did_campaign_panel_purchase;

CREATE TABLE did_campaign_panel_purchase AS
SELECT
  a.campaign_id,
  a.household_id,
  (ah.anchor_week + g.rel_week) AS week_number,
  ah.anchor_week AS anchor_week,
  g.rel_week     AS rel_week,
  CASE WHEN th.household_id IS NULL THEN 0 ELSE 1 END AS treated,
  CASE WHEN g.rel_week >= 0 THEN 1 ELSE 0 END AS post,
  COALESCE(r.total_sales_value, 0)     AS total_sales_value,
  COALESCE(r.total_units, 0)           AS total_units,
  COALESCE(r.total_coupon_discount, 0) AS total_coupon_discount,
  COALESCE(r.total_retail_discount, 0) AS total_retail_discount
FROM cohort_campaign_assigned_households a
JOIN cohort_household_anchor_week ah
  ON ah.campaign_id = a.campaign_id
 AND ah.household_id = a.household_id
JOIN rel_week_grid g
  ON 1=1
LEFT JOIN cohort_campaign_treated_households th
  ON th.campaign_id = a.campaign_id
 AND th.household_id = a.household_id
LEFT JOIN fct_household_week_revenue r
  ON r.household_id = a.household_id
 AND r.week_number  = (ah.anchor_week + g.rel_week)
WHERE ah.anchor_week IS NOT NULL;

CREATE INDEX idx_did_panel_campaign_household
  ON did_campaign_panel_purchase (campaign_id, household_id);

CREATE INDEX idx_did_panel_relweek
  ON did_campaign_panel_purchase (campaign_id, rel_week);

CREATE INDEX idx_did_panel_treated_post
  ON did_campaign_panel_purchase (treated, post);

/* ============================================================================
QC + MUST-PASS GATES
============================================================================ */

/* QC 1: Row counts */
SELECT 'cohort_campaign_assigned_households' AS table_name, COUNT(*) AS n_rows FROM cohort_campaign_assigned_households
UNION ALL
SELECT 'cohort_campaign_treated_households', COUNT(*) FROM cohort_campaign_treated_households
UNION ALL
SELECT 'cohort_campaign_control_households', COUNT(*) FROM cohort_campaign_control_households
UNION ALL
SELECT 'cohort_household_anchor_week', COUNT(*) FROM cohort_household_anchor_week
UNION ALL
SELECT 'did_campaign_panel_purchase', COUNT(*) FROM did_campaign_panel_purchase;

/* QC 2: Null checks */
SELECT
  SUM(campaign_id IS NULL)  AS null_campaign_id,
  SUM(household_id IS NULL) AS null_household_id,
  SUM(week_number IS NULL)  AS null_week_number,
  SUM(anchor_week IS NULL)  AS null_anchor_week,
  SUM(rel_week IS NULL)     AS null_rel_week,
  SUM(treated IS NULL)      AS null_treated,
  SUM(post IS NULL)         AS null_post
FROM did_campaign_panel_purchase;

/* QC 3: 2x2 presence */
SELECT
  treated,
  post,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT household_id) AS n_households
FROM did_campaign_panel_purchase
GROUP BY treated, post
ORDER BY treated, post;

/* MUST-PASS Gate: Controls present */
SELECT
  COUNT(DISTINCT household_id) AS control_households_in_panel
FROM did_campaign_panel_purchase
WHERE treated = 0;

/* MUST-PASS Gate: Assigned units preserved */
SELECT
  (SELECT COUNT(*) FROM cohort_campaign_assigned_households) AS assigned_rows,
  (SELECT COUNT(DISTINCT CONCAT(campaign_id, ':', household_id)) FROM did_campaign_panel_purchase) AS distinct_panel_units;

/* MUST-PASS Gate: ~17 rows per assigned unit */
SELECT
  COUNT(*) AS total_panel_rows,
  (SELECT COUNT(*) FROM cohort_campaign_assigned_households) AS assigned_rows,
  (COUNT(*) / NULLIF((SELECT COUNT(*) FROM cohort_campaign_assigned_households), 0)) AS rows_per_assigned_unit_expected_17
FROM did_campaign_panel_purchase;
