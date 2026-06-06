# Project Milestones

**Timeline:** May 27 – August 16 (gap: June 23 – July 3)

---

## Milestone 1: Data Foundation ✓
**Completed**

Player squad data and match results are confirmed clean and queryable across cached seasons. The pipeline can be re-run without manual intervention. A source for coach-team-season assignments is identified and integrated into the data layer.

---

## Milestone 2: Core Metric ✓
**Completed**

Minutes-weighted squad value is calculated for every team-season in the dataset. A sanity check confirms the metric behaves as expected (e.g., elite clubs score higher, clubs with injured starters score lower than their raw value suggests). The data pipeline runs end-to-end: scrape → clean → metric.

---

## Milestone 3: Model Comparison ✓
**Completed: June 5, 2026**

Both models rebuilt on a points-per-game basis with league fixed effects and log-transformed, normalized squad values. Minutes-weighted squad value (`enhanced_fixed`) outperforms raw squad value (`baseline_fixed`) on every in-sample metric and in 9/10 seasons and 4/5 leagues in cross-validation. Mean out-of-sample RMSE improvement ~0.013. Combined model overfits and is dropped. Winning model: `enhanced_fixed` (R² = 0.731, RMSE = 0.238). Two documented limitations: Serie A 2018 data quality issue, and near-but-not-quite p < 0.05 significance due to small fold counts. Full analysis pipeline in `src/model_comparison.R`, reproducible via `run_milestone3()`.

---

## Milestone 4: Residual Analysis
**Target: ~June 20 | Status: Active**

Residuals from the best-performing model are computed for every team-season. The distribution and structure of those residuals is analyzed — do certain teams consistently over- or underperform their expected points? This milestone stands on its own: even without coach attribution, a reliable residual is a defensible analytical result.

---

*[ Gap: June 23 – July 3 ]*

---

## Milestone 5: Coach Attribution & Rankings
**Target: ~July 25**

Residuals are linked to the coaches responsible for each team-season. Coaches with multiple teams are analyzed for consistency of residuals across different environments. A defensible ranking of coaches by performance above expectation is produced, and findings clearly support, refute, or refine the original hypothesis.

---

## Milestone 6: Extensions (Stretch)
**Target: ~August 10**

Further development pursued if time and results from earlier milestones support it. Possible directions:
- **Player Development Score** — measuring coach impact on player transfer value growth
- **Playing Style Analysis** — categorizing coaches by tactical fingerprint
