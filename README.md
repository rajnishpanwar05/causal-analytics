# Causal Impact & Experimentation Platform

## Business Context

Promotional spending represents 10-15% of grocery retail revenue. Without causal inference, correlation-based analytics systematically overestimate promotion effectiveness by conflating incremental lift with demand shifting and cannibalization.

**Decision Support:**
- Quantify incremental revenue impact of promotions and coupons
- Identify high-uplift customer segments for targeted campaigns
- Flag underperforming promotions for optimization or discontinuation

---

## Dataset

**Dunnhumby Complete Journey** (Kaggle public release)
- ~2.5M transactions, ~80k households
- Multi-year weekly panel data
- Campaign metadata, coupon issuance/redemption, product hierarchy, demographics

**Identification Strategy:**
Differential coupon exposure and campaign participation create natural experiments. Pre-treatment purchase history enables propensity score matching. Temporal variation supports difference-in-differences estimation.

**Key Assumptions:**
- Parallel pre-trends (validated via event studies)
- Conditional independence given observables (addressed via matching)
- No spillover effects between treated and control households

See `docs/causal_assumptions.md` for treatment definitions and validation strategies.

---

## Methodology

### Treatment Definitions
1. **Coupon Exposure**: Households receiving coupon vs. matched non-recipients (target category revenue)
2. **Campaign Participation**: Households purchasing promoted product vs. matched non-participants (total revenue)
3. **Discount Depth**: Percentage discount effects on category revenue (within-household variation)

### Estimation Methods
- **Difference-in-Differences**: Household and time fixed effects, robust standard errors
- **Propensity Score Matching**: 1:1 nearest neighbor, caliper 0.25 SD, balance diagnostics
- **Uplift Modeling**: T-Learner for individual treatment effect predictions

### Business Metrics
- **Incremental Revenue**: ATE × households × weeks
- **ROI**: (Incremental Revenue × Margin Rate - Campaign Cost) / Campaign Cost
- **Rejection Criteria**: p > 0.10, ATE < 0, or ROI < 5%

---

## Architecture

### Data Pipeline
```
Raw data → SQL cleaning → Intermediate tables → Feature engineering → Model inputs → Results → Dashboards
```

**Key Stages:**
- `sql/cleaning/`: Deduplication, outlier handling, missing value imputation
- `sql/cohorting/`: Treatment assignment, propensity score calculation, matching
- `sql/metrics/`: Weekly household revenue aggregation, campaign summaries
- Feature engineering: Pre-treatment purchase behavior, demographics, campaign attributes
- Modeling: DiD, PSM, uplift estimation (Python)
- Dashboards: Power BI for campaign ROI, household uplift segments, diagnostic validation

### Outputs
- Campaign-level incremental revenue and ROI estimates
- Household-level uplift predictions (decile rankings)
- Pre-trend diagnostic visualizations
- Treatment effect confidence intervals with rejection flags

---

## Limitations

**Methodological:**
- Assumptions validated where possible but not perfectly testable
- Average treatment effects mask heterogeneity (addressed via uplift modeling and subgroup analysis)
- 4-8 week post-treatment window may miss long-term demand shifting

**Data:**
- Margin rates estimated (not observed); ROI calculations subject to uncertainty
- Campaign assignments may be endogenous; addressed via matching and fixed effects
- Missing competitor activity, macroeconomic context

**Technical:**
- Batch processing (not real-time)
- Model validation on historical data only; prospective A/B testing recommended

See `docs/limitations.md` for detailed constraints and mitigation strategies.

---

## Project Layout + Run Order

This repository implements a SQL-to-Parquet extraction pipeline followed by causal inference analysis using Difference-in-Differences (DiD) and uplift modeling.

**What this repo does:**
- SQL pipeline builds purchase-based DiD panel from raw transaction data
- Python notebooks extract tables to Parquet, perform EDA, and fit TWFE DiD models
- Uplift modeling (T-Learner, S-Learner) provides household-level treatment effect predictions
- Robustness checks validate model stability and sensitivity

**Critical data gates:**
- PRODUCT_ID linkage gates pass; transactions join to product master
- Panel extraction validated; 2x2 treated×post structure confirmed
- Panel scale: ~122k rows, 45 households, 20 campaigns (expanded from initial small sample)

### Run Order

**SQL Scripts (execute in MySQL):**
1. `sql/cleaning/sql:00_bootstrap:00_full_bootstrap_with_bulk_import.sql` - Bootstrap database and load raw data
2. `sql/cleaning/02_core_dimensions.sql` - Build core dimension tables
3. `sql/cohorting/03_cohort_campaign_participation.sql` - Create campaign participation cohorts
4. `sql/metrics/04_did_campaign_estimates.sql` - Compute DiD campaign estimates
5. `sql/metrics/05_publish_campaign_estimates_purchase.sql` - Publish valid/invalid campaign splits

**Python Notebooks (execute in order):**
1. `notebooks/01_extract_from_mysql.ipynb` - Extract DiD tables from MySQL to Parquet
2. `notebooks/eda/01_panel_eda_and_pretrends.ipynb` - Panel EDA, coverage analysis, pre-trend diagnostics
3. `notebooks/eda/modeling/02_did_twfe_regression.ipynb` - TWFE DiD regression with household/week FE
4. `notebooks/eda/modeling/04_uplift_modeling.ipynb` - T-Learner and S-Learner uplift models
5. `notebooks/eda/modeling/05_uplift_robustness_and_validation.ipynb` - Uplift validation and bootstrap uncertainty
6. `notebooks/eda/modeling/06_twfe_robustness_and_sensitivity.ipynb` - TWFE robustness (SE variants, winsorization, LOHO, placebo)

### Output Locations

**Data:**
- Raw CSVs: `data/raw/` (not committed)
- Intermediate Parquet: `data/intermediate/` (not committed)
- Processed datasets: `data/processed/` (not committed)

**Results:**
- EDA outputs: `results/eda/figures/`, `results/eda/tables/`, `results/eda/EDA_SUMMARY.md`
- TWFE outputs: `results/modeling/` (CSV files), `results/modeling/figures/`
- Uplift outputs: `results/modeling/uplift/figures/`, `results/modeling/uplift/tables/`
- Uplift validation: `results/modeling/uplift_validation/figures/`, `results/modeling/uplift_validation/tables/`
- Robustness outputs: `results/modeling/robustness/figures/`, `results/modeling/robustness/tables/`
- Run manifests: `results/run_manifests/` (JSON files with execution metadata)

### Power BI Readiness

For Power BI dashboards, load:
- Campaign-level estimates: `results/modeling/uplift_validation/tables/topk_comparison.csv`
- Uplift validation tables: `results/modeling/uplift_validation/tables/recommended_households_conservative.csv`
- TWFE baseline results: `results/modeling/twfe_did_summary.csv`
- Avoid loading full panel Parquet files (too large for Power BI)

### Project Structure

```
.
├── data/              # Raw, intermediate, processed (excluded from version control)
├── sql/               # Cleaning, cohorting, metrics queries
├── src/               # Reserved for future refactor (see src/README.md)
├── notebooks/         # EDA, modeling, validation
├── dashboards/        # Power BI assets and screenshots
├── results/           # Tables, figures, model outputs (excluded from version control)
└── docs/              # Causal assumptions, data quality, limitations
```

---

**Status:** Pipeline operational. All notebooks run end-to-end from cold start.
**Maintained By:** Pricing & Promotions Analytics Team
