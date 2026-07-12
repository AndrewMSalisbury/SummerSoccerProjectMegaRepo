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

## Milestone 6: Coach/Player-Type Fit ✓
**Completed: July 9, 2026 (PL pilot) / July 12, 2026 (all big-5 leagues)**

Direction chosen July 6 (the "Playing Style Analysis" branch): derive player archetypes from SofaScore data and test whether coaches systematically over/underperform — per the M4/M5 residual — depending on the player types at their disposal.

Delivered: 11 face-valid player archetypes from 17,219 player-seasons across all five major leagues (38 style features, k-means within position groups; the wing-back archetype only emerged with back-3-league data); lagged minutes-weighted squad composition per coach stint, with cross-league lagging (1,475 stints, 100% joined to M5 residuals). **Headline finding, replicated from the PL pilot at 5× the data: squad archetype mix predicts performance above squad-value expectation (LRT p = 0.030; strict-lagged sensitivity p = 0.0016), led by wide-creator share (t ≈ 3.3; +10pp of minutes ≈ +2.8 points/season).** Per-coach fits are descriptive only (0/1,605 survive FDR; Gasperini + man-marking CBs, Vieira + destroyers, Pochettino − pressing forwards recur across specifications). Full pipeline: `src/player_archetypes.R`, `src/coach_fit.R`; findings in `Docs/Summary_of_Findings.md` Part 6.

Optional remaining: 2025/26 pass-coordinate validation; website refresh with big-5 fit results.

Unchosen direction (dropped for scope): **Player Development Score** — coach impact on player transfer value growth.

---

## Website ✓
**Completed: July 10, 2026**

Static presentation site (`site/`) covering every published result: a page per coach (2,341 — career PPG chart with club crests as clickable data points, grades/BLUPs from both ranking cuts, player-type fit), per club (496 — sortable coach history, actual-vs-expected seasons, squad value trends), and per league (14 — season selector, standings sortable by points or overperformance, diverging residual chart), plus the full writeup and a searchable leaderboard home page. Design in `Docs/Website_Design.md`, build plan in `Docs/Website_Implementation_Plan.md`. Regenerate data with `export_site_data()` (`src/site_export.R`); serve locally per `site/README.md`. Club crests scraped for all 496 clubs (`xx_data_populate_team_crests()`).
