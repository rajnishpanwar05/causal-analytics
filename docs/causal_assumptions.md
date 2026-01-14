# Causal Inference Assumptions

## Treatment Definitions

### Treatment 1: Coupon Exposure
- **Treatment**: Households receiving coupon for category C in week t
- **Control**: Matched households not receiving coupon (pre-treatment: purchase frequency, demographics, coupon redemption history)
- **Outcome**: Weekly household revenue in category C
- **Window**: 4-8 weeks post-issuance

### Treatment 2: Campaign Participation
- **Treatment**: Households purchasing promoted product during campaign period
- **Control**: Propensity score matched (1:1 nearest neighbor, caliper 0.25 SD) on pre-treatment revenue, category frequency, demographics
- **Outcome**: Total weekly household revenue
- **Baseline**: 12 months pre-campaign; post-treatment: 4-8 weeks

### Treatment 3: Discount Depth
- **Treatment**: Discount percentage (binned: 0-10%, 10-20%, 20%+)
- **Control**: Same households purchasing at 0% discount
- **Outcome**: Category-level revenue
- **Identification**: Within-household variation enables fixed effects

---

## Core Assumptions

### 1. Parallel Trends (DiD)
Pre-treatment outcome trends identical for treated and control groups.

**Validation:**
- Event study: Pre-period lead coefficients should be near zero
- Graphical: Visual inspection of pre-treatment trends

**Violation Handling:** If parallel trends fail, use PSM or synthetic control methods.

### 2. Conditional Independence (PSM)
Treatment assignment independent of potential outcomes given observable covariates X.

**Validation:**
- Post-matching balance: Standardized mean differences < 0.25 for all covariates
- Propensity score overlap: Substantial common support region

**Threats:** Unobserved confounders (e.g., unmeasured price sensitivity) may violate assumption. Rich pre-treatment covariates mitigate but do not eliminate risk.

### 3. SUTVA
No spillover effects between treated and control households.

**Validation:**
- Spatial analysis: Compare effects in high vs. low treatment-density regions
- Exclusion tests: Re-estimate excluding weeks with >50% treatment density

**Mitigation:** If spillovers detected, estimate separately or restrict to isolated regions.

### 4. Positivity
All households have non-zero probability of treatment given covariates.

**Validation:**
- Propensity score distributions show overlap between treated and control groups

**Handling:** Trim extreme propensity scores (P(T=1|X) > 0.95 or < 0.05) and document exclusion.

---

## Threats to Validity

**Selection Bias:** Addressed via propensity score matching and household fixed effects.

**Temporal Confounds:** Time fixed effects control for aggregate time-varying confounds (holidays, macro conditions).

**Demand Shifting:** Extended post-treatment windows (8 weeks) and lead-lag analysis detect anticipation/stockpiling effects.

**Measurement Error:** Treatment assignment validated via coupon redemption as proxy for exposure. Sensitivity analysis varies treatment definitions.

**Heterogeneous Effects:** Average effects mask heterogeneity. Uplift modeling and subgroup analysis (income, region, category) provide segment-level estimates.

---

## Validation Protocol

1. **Pre-trend Diagnostics:** Event study plots, lead coefficient tests
2. **Balance Checks:** Standardized mean differences post-matching
3. **Placebo Tests:** False treatment dates should yield null effects
4. **Sensitivity Analysis:** Varying calipers (0.1, 0.25, 0.5 SD), time windows (6 vs. 12 months pre-treatment)
5. **Alternative Specifications:** Different control groups, matching algorithms

Results documented in `notebooks/validation/` with summary tables in `results/tables/robustness_checks.csv`.
