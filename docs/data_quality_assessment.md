# Data Quality Assessment

## Known Issues

### Missing Values
- Transaction-level: Missing `product_id`, `quantity`, or `sales_value` (exact rates TBD during EDA)
- Demographics: Missing income, household size, or region for subset of households
- **Handling:** Exclude transactions with missing critical fields. Impute demographics (median by region) to preserve sample size for PSM.

### Campaign Metadata
- Invalid date ranges (`start_date > end_date`)
- Missing `campaign_id` linkage in transactions
- Overlapping campaigns for same category
- **Handling:** Exclude invalid campaigns. Match transactions to campaigns via product category + date window. Use primary campaign for overlaps.

### Coupon Data
- Issuance-redemption discrepancies
- Missing expiry dates
- **Handling:** Use issuance (not redemption) as treatment indicator to avoid endogeneity. Assume 4-week validity if expiry missing.

### Outliers
- Extreme transaction values (bulk purchases, data entry errors)
- **Handling:** Winsorize at 1st and 99th percentiles. Exclude implausible values (negative quantity, revenue > $10k single transaction).

### Panel Attrition
- Unbalanced panel (households with gaps or limited observation windows)
- **Handling:** Balanced panel for DiD (requires pre/post observations). Unbalanced panel acceptable for PSM with household fixed effects.

### Product Hierarchy
- SKUs mapped to multiple categories
- Missing category assignments
- Temporal category definition changes
- **Handling:** Use primary category (first listed). Exclude SKUs without category. Use fixed-time snapshot to avoid temporal changes.

---

## Validation Checkpoints

- **Post-cleaning:** Missing value rates, outlier counts, record count validation
- **Post-aggregation:** Revenue totals match transaction-level sums
- **Post-cohorting:** Treatment/control group sizes, balance diagnostics
- **Post-feature engineering:** Feature distributions, correlation checks

Quality metrics tracked but targets established during initial EDA phase.
