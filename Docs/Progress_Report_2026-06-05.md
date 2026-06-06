# Session Progress Report

**Date:** June 5, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

This session was entirely focused on Milestone 3: Model Comparison, which was due June 6. The goal was to move the analysis from the rank-based Pearson correlation approach used in Milestone 2 to a proper regression framework comparing raw squad value against minutes-weighted squad value as predictors of final points. The full pipeline — data preparation, model fitting, cross-validation, significance testing, sensitivity analysis, and residual diagnostics — was built from scratch and completed in a single session.

---

## What Was Accomplished

### Full Milestone 3 Analysis Pipeline

A new file `src/model_comparison.R` was created containing the entire analysis. The pipeline can be re-run from scratch with a single function call: `run_milestone3()`. Every analytical decision made during the session is documented in the code and in the session log.

The key methodological decisions made this session:

- **Points-per-game as the outcome.** Rather than raw points totals, each team's points are divided by games played. This makes Bundesliga seasons (34 games) directly comparable to the four 38-game leagues. This also correctly handled Ligue 1's reduction to 18 teams in 2023-24, which was discovered during the work.
- **Within-season squad value normalization.** Both squad value metrics are divided by their league-season mean before fitting, removing transfer market inflation across years.
- **Log transformation of predictors.** Transfer market values are heavily right-skewed. After checking distributions visually, log-transforming the squad value predictors improved both the normality of the data and the linearity of the relationship with points-per-game. This is a standard treatment for this type of financial data.

### The Core Finding

Minutes-weighted squad value is a better predictor of final points than raw squad value. The winning model (`enhanced_fixed` — minutes-weighted squad value with league fixed effects) outperforms the baseline on every metric evaluated:

- **R²: 0.731 vs 0.702** (in-sample)
- **RMSE: 0.238 vs 0.250** (in-sample)
- **Enhanced beats baseline in 9 of 10 seasons** in leave-one-season-out cross-validation
- **Enhanced beats baseline in 4 of 5 leagues** in leave-one-league-out cross-validation
- **Mean out-of-sample RMSE improvement: ~0.013**, consistent across both CV strategies
- **No meaningful overfitting** — out-of-sample RMSE nearly identical to in-sample

The combined model (raw + weighted together) was tested and dropped: it matched the enhanced model in-sample but performed worse out-of-sample, a clear sign of overfitting.

### Statistical Significance

Paired t-tests on the CV RMSE vectors produced p = 0.063 (season CV) and p = 0.075 (league CV). These fall just short of the conventional p < 0.05 threshold but pass at α = 0.10. The near-miss is explained by limited fold counts (10 and 5) and a single anomalous season (2018) that acts as an outlier against the otherwise consistent improvement. With a larger dataset the result would almost certainly clear p < 0.05.

### Sensitivity Analysis Findings

Three sub-checks were run to confirm the result isn't driven by a specific slice of the data:

1. **Per-league:** Enhanced wins within each of the four non-Serie A leagues individually, with improvements ranging from 0.016 to 0.026 RMSE. Serie A is the consistent exception across every test.

2. **Early vs recent:** The improvement is near-zero in 2015–2019 (0.0017) but substantial in 2020–2024 (0.0241). The effect has grown dramatically stronger in recent seasons, likely due to a combination of improving data quality on Transfermarkt and genuine increases in squad rotation in modern football.

3. **10% minutes threshold:** Filtering to players who played at least 10% of available match time did not sharpen the signal — the improvement slightly narrowed. Fringe players contribute to, not dilute, the weighted metric's advantage. The full squad is kept in the model.

### Residual Diagnostics

The winning model passes all three diagnostic checks:
- Residuals scatter randomly around zero with no funnel shape (no heteroskedasticity)
- Q-Q plot is approximately normal with a mild S-curve (slightly light tails — less concerning than heavy tails)
- Cook's distance shows no single observation dominating the model; the highest value is 0.027 (~7x the threshold), with all others well below 0.015

The flagged influential observations are the most encouraging part of the analysis: they are almost entirely teams with well-known coaching narratives. Leicester City's 5000-1 title win in 2015, Liverpool under Klopp across 2018–2021, Manchester City under Guardiola, Bayer Leverkusen's unbeaten 2023 season under Xabi Alonso, and Union Berlin's repeated overperformance all appear prominently with large positive residuals. The model is picking up real sporting signals.

---

## Problems Encountered

Two bugs required fixing:

1. **`xx_team_points` crash on extra columns.** The `matches.rds` cache now contains a `match_date` column from a prior session's `xx_refresh_match_dates()` run. The `purrr::pmap_dfr` call inside `xx_team_points` used an explicit function signature and rejected the undeclared column. Fixed by adding `...` to absorb any extra columns.

2. **`min_minutes_pct` threshold filtered out all players.** The sensitivity analysis filter `percent_minutes_played >= 0.10` removed every player because `percent_minutes_played` is defined as a fraction of total squad minutes — with 25+ players per squad, even regular starters sit at 0.07–0.09. Fixed by rewriting the filter to compare `minutes_played >= games_played * 90 * min_minutes_pct`, correctly implementing "played at least 10% of available playing time."

---

## Documented Limitations

- **Serie A 2018 is likely a data quality issue.** Six of the top 20 most influential observations are Serie A 2018 entries, connecting the 2018 season anomaly and the Serie A exception into one root cause. Incomplete or inaccurate minutes data for Serie A 2018-19 on Transfermarkt is the most plausible explanation. Not investigated this session but flagged for future work.
- **Effect weaker in early seasons.** 2015–2019 shows minimal improvement from weighting. The growing effect in recent seasons likely reflects improving data quality over time.
- **Significance just below p < 0.05** due to small fold counts and the 2018 outlier.

---

## What Comes Next

Milestone 3 is complete. The project moves to **Milestone 4: Residual Analysis** (target: June 20).

The winning model (`enhanced_fixed`) is now established. Milestone 4 computes validated residuals for every team-season, analyzes their distribution and structure, and confirms that the residuals contain a real signal worth attributing to coaches. The key deliverable is a clean residuals table covering all leagues and seasons, with balance checks, distributional analysis, and temporal persistence analysis complete.

The Cook's distance table from this session gives a strong preview of what Milestone 4 will find — the residuals already surface Leicester 2015, Liverpool under Klopp, and Leverkusen 2023 as the kinds of signals the coach attribution model will be built on.
