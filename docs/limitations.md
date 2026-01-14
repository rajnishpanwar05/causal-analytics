# Limitations

## Methodological Constraints

**Assumption Dependence:** Causal estimates rely on parallel trends, conditional independence, and SUTVA. Validation is imperfect; unobserved confounders remain possible.

**Average Effects Mask Heterogeneity:** ATE provides single summary but effects vary by segment, category, timing. Addressed via uplift modeling and subgroup analysis.

**Time Window Constraints:** 4-8 week post-treatment window may miss long-term demand shifting. Extended windows used where data permits; structural models recommended for full decomposition.

**Cross-Category Effects:** Analysis focuses on target category revenue. Full basket analysis needed to quantify cannibalization and spillovers comprehensively.

## Data Constraints

**Estimated Margins:** Product-level margin rates not observed. ROI calculations use estimated category margins, introducing uncertainty. Collaboration with Finance needed for ground-truth data.

**Endogenous Assignment:** Campaign/coupon targeting may be strategic (e.g., high-value customers). Addressed via matching and fixed effects but cannot eliminate all endogeneity.

**Missing Context:** Competitor activity, macroeconomic conditions, store-level characteristics not available. Time and region fixed effects partially mitigate.

## Technical Constraints

**Batch Processing:** Not real-time. Propensity score matching on 80k+ households computationally intensive. Stream processing and incremental updates recommended for production.

**Historical Validation Only:** Model validation on historical data. Prospective A/B testing framework needed for true external validation.

**Interpretability Trade-offs:** Complex uplift models (gradient boosting, neural networks) may sacrifice interpretability for accuracy. Segment-level summaries provided for business stakeholders.

## Business Context

**Multi-Objective Decisions:** Campaign decisions involve brand building, competitive positioning, supplier relationships beyond ROI. Framework provides ROI input but not sole decision criterion.

**Competitive Dynamics:** Competitive responses and long-term equilibrium effects not modeled. Short-term treatment effects may not persist.

---

**Mitigation strategies documented in respective methodology sections. Framework designed for incremental enhancement as constraints are addressed.**
