# SQL Scripts

## Structure

- `cleaning/`: Deduplication, outlier handling, missing value imputation, campaign/coupon validation
- `cohorting/`: Treatment assignment, propensity score calculation, matching (caliper 0.25 SD, 1:1 nearest neighbor with replacement)
- `metrics/`: Weekly household revenue aggregation, category-level metrics, campaign summaries

## Execution Order

1. Cleaning scripts (any order within `cleaning/`)
2. Metrics aggregation (`aggregate_household_revenue.sql`, `aggregate_category_revenue.sql`, `campaign_summary.sql`)
3. Treatment assignment (`treatment_*.sql`)
4. Propensity scores (`calculate_propensity_scores.sql` requires metrics)
5. Matched pairs (`create_matched_pairs.sql` requires propensity scores)

## Standards

- Naming: `snake_case` for tables and columns
- Script headers: Purpose, input/output tables, dependencies
- Business logic: Pre-treatment 12 months (or 6 if limited), post-treatment 4-8 weeks

## Platform Notes

BigQuery/Snowflake compatible. Date arithmetic and ML functions use platform-specific syntax. Partitioning and indexing recommended for ~2.5M transactions.
