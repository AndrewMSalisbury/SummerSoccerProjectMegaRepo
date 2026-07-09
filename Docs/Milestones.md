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

## Milestone 4: Residual Analysis ✓
**Completed: June 9, 2026**

Residuals from `enhanced_fixed` computed for all 976 team-seasons (6 NA due to imputation edge case). Distribution is approximately normal (SD = 0.238 PPG, mean = 0) with heavy tails driven by the 2018 data quality issue. No heteroskedasticity detected — rankings equally reliable across all squad value tiers. Lag-1 temporal persistence r = 0.25: modest club effect, meaningful year-to-year variation. Full pipeline in `src/residual_analysis.R`, reproducible via `run_milestone4()`.

---

*[ Gap: June 23 – July 3 ]*

---

## Milestone 5: Coach Attribution & Rankings
**Target: ~July 25**

Residuals are linked to the coaches responsible for each team-season. Coaches with multiple teams are analyzed for consistency of residuals across different environments. A defensible ranking of coaches by performance above expectation is produced, and findings clearly support, refute, or refine the original hypothesis.

---

## Milestone 6: Coach/Player-Type Fit
**Target: ~August 10 | Status: Active — data foundation complete July 9**

Direction chosen July 6 (the "Playing Style Analysis" branch): derive player archetypes from SofaScore data (season heatmaps, ~110-field season statistics, per-match statistics, shot coordinates, per-match formations) and test whether coaches systematically over/underperform — per the M4/M5 residual — depending on the player types at their disposal. Deliverable: descriptive findings, each backed by statistical evidence.

Completed: SofaScore data layer, full PL 2015/16–2024/25 pilot scrape (5,356 player-seasons, 3,800 matches, zero failures), Transfermarkt crosswalks for all ten seasons (99.2–100% matched).

Remaining: archetype feature engineering and clustering, lagged squad-composition measures, coach-fit analysis, write-up.

Unchosen direction (dropped for scope): **Player Development Score** — coach impact on player transfer value growth.
