/* =========================================================
   METRICS: PUBLISH DiD OUTPUTS (VALID vs INVALID CAMPAIGNS)
   File: sql/metrics/05_publish_campaign_estimates_purchase.sql
   Database: causal_analytics
   Depends on: sql/metrics/04_did_campaign_estimates.sql (purchase-based)
   ========================================================= */

USE causal_analytics;

SET @old_sql_mode := @@SESSION.sql_mode;
SET SESSION sql_mode = '';

/* -------------------------
   Optional thresholds
   (keep conservative; adjust later)
   ------------------------- */
SET @min_treated_hh_pre  = 2;
SET @min_treated_hh_post = 2;
SET @min_ctrl_hh_pre     = 2;
SET @min_ctrl_hh_post    = 2;

/* =========================================================
   1) VALID CAMPAIGNS (complete 2x2 + meets HH thresholds)
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_estimates_purchase_valid;
CREATE TABLE did_campaign_estimates_purchase_valid AS
SELECT
  e.*,
  c.campaign_type,
  c.start_day_num,
  c.end_day_num
FROM did_campaign_estimates_purchase e
LEFT JOIN dim_campaigns c
  ON c.campaign_id = e.campaign_id
WHERE e.did_incomplete_2x2 = 0
  AND e.treated_hh_pre  >= @min_treated_hh_pre
  AND e.treated_hh_post >= @min_treated_hh_post
  AND e.control_hh_pre  >= @min_ctrl_hh_pre
  AND e.control_hh_post >= @min_ctrl_hh_post;

ALTER TABLE did_campaign_estimates_purchase_valid
  ADD PRIMARY KEY (campaign_id);

CREATE INDEX idx_did_valid_lift_sales
  ON did_campaign_estimates_purchase_valid (did_sales_lift);

/* =========================================================
   2) INVALID CAMPAIGNS (incomplete 2x2 OR fails thresholds)
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_estimates_purchase_invalid;
CREATE TABLE did_campaign_estimates_purchase_invalid AS
SELECT
  e.*,
  c.campaign_type,
  c.start_day_num,
  c.end_day_num,
  CASE
    WHEN e.did_incomplete_2x2 = 1 THEN 'missing_2x2_cell'
    WHEN e.treated_hh_pre  < @min_treated_hh_pre  THEN 'treated_hh_pre_below_threshold'
    WHEN e.treated_hh_post < @min_treated_hh_post THEN 'treated_hh_post_below_threshold'
    WHEN e.control_hh_pre  < @min_ctrl_hh_pre     THEN 'control_hh_pre_below_threshold'
    WHEN e.control_hh_post < @min_ctrl_hh_post    THEN 'control_hh_post_below_threshold'
    ELSE 'other'
  END AS invalid_reason
FROM did_campaign_estimates_purchase e
LEFT JOIN dim_campaigns c
  ON c.campaign_id = e.campaign_id
WHERE NOT (
  e.did_incomplete_2x2 = 0
  AND e.treated_hh_pre  >= @min_treated_hh_pre
  AND e.treated_hh_post >= @min_treated_hh_post
  AND e.control_hh_pre  >= @min_ctrl_hh_pre
  AND e.control_hh_post >= @min_ctrl_hh_post
);

CREATE INDEX idx_did_invalid_reason
  ON did_campaign_estimates_purchase_invalid (invalid_reason);

/* =========================================================
   3) (Optional but useful) Analysis-ready panel filtered to valid campaigns
   ========================================================= */

DROP TABLE IF EXISTS did_campaign_panel_purchase_valid;
CREATE TABLE did_campaign_panel_purchase_valid AS
SELECT p.*
FROM did_campaign_panel_purchase p
JOIN did_campaign_estimates_purchase_valid v
  ON v.campaign_id = p.campaign_id;

CREATE INDEX idx_panel_valid_campaign
  ON did_campaign_panel_purchase_valid (campaign_id);

/* =========================================================
   4) PUBLISH SUMMARY
   ========================================================= */

SELECT
  (SELECT COUNT(*) FROM did_campaign_estimates_purchase) AS n_campaigns_total,
  (SELECT COUNT(*) FROM did_campaign_estimates_purchase_valid) AS n_campaigns_valid,
  (SELECT COUNT(*) FROM did_campaign_estimates_purchase_invalid) AS n_campaigns_invalid;

SELECT invalid_reason, COUNT(*) AS n_campaigns
FROM did_campaign_estimates_purchase_invalid
GROUP BY invalid_reason
ORDER BY n_campaigns DESC;

-- Top positive lifts (if any)
SELECT campaign_id, campaign_type, did_sales_lift
FROM did_campaign_estimates_purchase_valid
ORDER BY did_sales_lift DESC
LIMIT 20;

-- Most negative lifts
SELECT campaign_id, campaign_type, did_sales_lift
FROM did_campaign_estimates_purchase_valid
ORDER BY did_sales_lift ASC
LIMIT 20;

SET SESSION sql_mode = @old_sql_mode;
