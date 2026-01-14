/* =========================================================
   METRICS: DiD ESTIMATES (CAMPAIGN + POOLED) + DIAGNOSTICS
   PURCHASE-BASED VERSION (uses did_campaign_panel_purchase)

   File: sql/metrics/04_did_campaign_estimates.sql
   Database: causal_analytics
   Depends on: purchase cohort panel in did_campaign_panel_purchase
   ========================================================= */

USE causal_analytics;

SET @old_sql_mode := @@SESSION.sql_mode;
SET SESSION sql_mode = '';

/* =========================================================
   0) QUICK PANEL COVERAGE SNAPSHOT
   ========================================================= */

DROP TABLE IF EXISTS did_panel_coverage_purchase;
CREATE TABLE did_panel_coverage_purchase AS
SELECT
  COUNT(*) AS panel_rows,
  COUNT(DISTINCT campaign_id) AS panel_campaigns,
  COUNT(DISTINCT household_id) AS panel_households,
  SUM(treated=1) AS treated_rows,
  SUM(treated=0) AS control_rows
FROM did_campaign_panel_purchase;

/* =========================================================
   1) CAMPAIGN CELL MEANS (TREATED/CONTROL x PRE/POST)
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_cell_means_purchase;
CREATE TABLE did_campaign_cell_means_purchase AS
SELECT
  campaign_id,
  treated,
  post,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT household_id) AS n_households,
  CAST(AVG(total_sales_value) AS DECIMAL(18,6)) AS avg_sales,
  CAST(AVG(total_units) AS DECIMAL(18,6)) AS avg_units,
  CAST(AVG(total_coupon_discount) AS DECIMAL(18,6)) AS avg_coupon_disc,
  CAST(AVG(total_retail_discount) AS DECIMAL(18,6)) AS avg_retail_disc
FROM did_campaign_panel_purchase
GROUP BY campaign_id, treated, post;

CREATE INDEX idx_did_campaign_cell_means_purchase
  ON did_campaign_cell_means_purchase (campaign_id, treated, post);

/* =========================================================
   2) CAMPAIGN COMPLETENESS FLAGS (WHICH CELLS EXIST?)
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_cell_flags_purchase;
CREATE TABLE did_campaign_cell_flags_purchase AS
SELECT
  campaign_id,
  SUM(CASE WHEN treated=1 AND post=0 THEN 1 ELSE 0 END) AS has_treat_pre,
  SUM(CASE WHEN treated=1 AND post=1 THEN 1 ELSE 0 END) AS has_treat_post,
  SUM(CASE WHEN treated=0 AND post=0 THEN 1 ELSE 0 END) AS has_ctrl_pre,
  SUM(CASE WHEN treated=0 AND post=1 THEN 1 ELSE 0 END) AS has_ctrl_post
FROM did_campaign_cell_means_purchase
GROUP BY campaign_id;

ALTER TABLE did_campaign_cell_flags_purchase
  ADD PRIMARY KEY (campaign_id);

/* =========================================================
   3) CAMPAIGN DiD ESTIMATES (COMPUTE WHEN POSSIBLE)
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_estimates_purchase;
CREATE TABLE did_campaign_estimates_purchase AS
SELECT
  cm.campaign_id,

  MAX(CASE WHEN cm.treated=1 AND cm.post=0 THEN cm.n_households END) AS treated_hh_pre,
  MAX(CASE WHEN cm.treated=1 AND cm.post=1 THEN cm.n_households END) AS treated_hh_post,
  MAX(CASE WHEN cm.treated=0 AND cm.post=0 THEN cm.n_households END) AS control_hh_pre,
  MAX(CASE WHEN cm.treated=0 AND cm.post=1 THEN cm.n_households END) AS control_hh_post,

  MAX(CASE WHEN cm.treated=1 AND cm.post=0 THEN cm.avg_sales END) AS treated_pre_avg_sales,
  MAX(CASE WHEN cm.treated=1 AND cm.post=1 THEN cm.avg_sales END) AS treated_post_avg_sales,
  MAX(CASE WHEN cm.treated=0 AND cm.post=0 THEN cm.avg_sales END) AS control_pre_avg_sales,
  MAX(CASE WHEN cm.treated=0 AND cm.post=1 THEN cm.avg_sales END) AS control_post_avg_sales,

  CASE
    WHEN f.has_treat_pre>0 AND f.has_treat_post>0 AND f.has_ctrl_pre>0 AND f.has_ctrl_post>0
    THEN
      (
        (MAX(CASE WHEN cm.treated=1 AND cm.post=1 THEN cm.avg_sales END) - MAX(CASE WHEN cm.treated=1 AND cm.post=0 THEN cm.avg_sales END))
        -
        (MAX(CASE WHEN cm.treated=0 AND cm.post=1 THEN cm.avg_sales END) - MAX(CASE WHEN cm.treated=0 AND cm.post=0 THEN cm.avg_sales END))
      )
    ELSE NULL
  END AS did_sales_lift,

  MAX(CASE WHEN cm.treated=1 AND cm.post=0 THEN cm.avg_units END) AS treated_pre_avg_units,
  MAX(CASE WHEN cm.treated=1 AND cm.post=1 THEN cm.avg_units END) AS treated_post_avg_units,
  MAX(CASE WHEN cm.treated=0 AND cm.post=0 THEN cm.avg_units END) AS control_pre_avg_units,
  MAX(CASE WHEN cm.treated=0 AND cm.post=1 THEN cm.avg_units END) AS control_post_avg_units,

  CASE
    WHEN f.has_treat_pre>0 AND f.has_treat_post>0 AND f.has_ctrl_pre>0 AND f.has_ctrl_post>0
    THEN
      (
        (MAX(CASE WHEN cm.treated=1 AND cm.post=1 THEN cm.avg_units END) - MAX(CASE WHEN cm.treated=1 AND cm.post=0 THEN cm.avg_units END))
        -
        (MAX(CASE WHEN cm.treated=0 AND cm.post=1 THEN cm.avg_units END) - MAX(CASE WHEN cm.treated=0 AND cm.post=0 THEN cm.avg_units END))
      )
    ELSE NULL
  END AS did_units_lift,

  f.has_treat_pre,
  f.has_treat_post,
  f.has_ctrl_pre,
  f.has_ctrl_post,

  CASE
    WHEN f.has_treat_pre=0 OR f.has_treat_post=0 OR f.has_ctrl_pre=0 OR f.has_ctrl_post=0
    THEN 1 ELSE 0
  END AS did_incomplete_2x2

FROM did_campaign_cell_means_purchase cm
JOIN did_campaign_cell_flags_purchase f
  ON f.campaign_id = cm.campaign_id
GROUP BY cm.campaign_id;

ALTER TABLE did_campaign_estimates_purchase
  ADD PRIMARY KEY (campaign_id);

/* =========================================================
   4) POOLED (OVERALL) DiD ACROSS ALL CAMPAIGNS
   ========================================================= */

DROP TABLE IF EXISTS did_overall_cell_means_purchase;
CREATE TABLE did_overall_cell_means_purchase AS
SELECT
  treated,
  post,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT household_id) AS n_households,
  CAST(AVG(total_sales_value) AS DECIMAL(18,6)) AS avg_sales,
  CAST(AVG(total_units) AS DECIMAL(18,6)) AS avg_units
FROM did_campaign_panel_purchase
GROUP BY treated, post;

ALTER TABLE did_overall_cell_means_purchase
  ADD PRIMARY KEY (treated, post);

DROP TABLE IF EXISTS did_overall_estimate_purchase;
CREATE TABLE did_overall_estimate_purchase AS
SELECT
  (SELECT n_households FROM did_overall_cell_means_purchase WHERE treated=1 AND post=0) AS treated_hh_pre,
  (SELECT n_households FROM did_overall_cell_means_purchase WHERE treated=1 AND post=1) AS treated_hh_post,
  (SELECT n_households FROM did_overall_cell_means_purchase WHERE treated=0 AND post=0) AS control_hh_pre,
  (SELECT n_households FROM did_overall_cell_means_purchase WHERE treated=0 AND post=1) AS control_hh_post,

  (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=1 AND post=0) AS treated_pre_avg_sales,
  (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=1 AND post=1) AS treated_post_avg_sales,
  (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=0 AND post=0) AS control_pre_avg_sales,
  (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=0 AND post=1) AS control_post_avg_sales,

  (
    ((SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=1 AND post=1) - (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=1 AND post=0))
    -
    ((SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=0 AND post=1) - (SELECT avg_sales FROM did_overall_cell_means_purchase WHERE treated=0 AND post=0))
  ) AS did_sales_lift,

  (
    ((SELECT avg_units FROM did_overall_cell_means_purchase WHERE treated=1 AND post=1) - (SELECT avg_units FROM did_overall_cell_means_purchase WHERE treated=1 AND post=0))
    -
    ((SELECT avg_units FROM did_overall_cell_means_purchase WHERE treated=0 AND post=1) - (SELECT avg_units FROM did_overall_cell_means_purchase WHERE treated=0 AND post=0))
  ) AS did_units_lift;

/* =========================================================
   5) EVENT-STUDY READY TABLE
   ========================================================= */

DROP TABLE IF EXISTS did_event_study_weekly_purchase;
CREATE TABLE did_event_study_weekly_purchase AS
SELECT
  campaign_id,
  rel_week,
  treated,
  COUNT(*) AS n_rows,
  COUNT(DISTINCT household_id) AS n_households,
  CAST(AVG(total_sales_value) AS DECIMAL(18,6)) AS avg_sales,
  CAST(AVG(total_units) AS DECIMAL(18,6)) AS avg_units
FROM did_campaign_panel_purchase
GROUP BY campaign_id, rel_week, treated;

CREATE INDEX idx_event_study_campaign_week_purchase
  ON did_event_study_weekly_purchase (campaign_id, rel_week);

/* =========================================================
   6) SANITY CHECKS / OUTPUTS
   ========================================================= */

SELECT * FROM did_panel_coverage_purchase;

SELECT
  COUNT(*) AS n_campaigns_in_estimates_table,
  SUM(did_incomplete_2x2) AS n_campaigns_incomplete_2x2,
  SUM(did_sales_lift IS NULL) AS n_campaigns_with_null_did_sales_lift
FROM did_campaign_estimates_purchase;

SELECT * FROM did_campaign_estimates_purchase ORDER BY campaign_id;

SELECT * FROM did_overall_cell_means_purchase ORDER BY treated, post;
SELECT * FROM did_overall_estimate_purchase;

SET SESSION sql_mode := @old_sql_mode;


