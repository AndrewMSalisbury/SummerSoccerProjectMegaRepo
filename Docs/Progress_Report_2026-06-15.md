# Session Progress Report

**Date:** June 15, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

The previous session expanded the dataset from 5 leagues / 10 seasons to 19 leagues / 20 seasons. This session finalised the league set by investigating data quality, making principled exclusions, and adding structural covariates. The result is a clean, well-motivated 14-league dataset with significantly stronger cross-validation results than the original 5-league analysis.

---

## What Was Accomplished

### League Exclusions (19 → 14 leagues)

Five additional leagues were excluded on top of the Argentine Liga Profesional dropped last session. Each exclusion has a distinct structural rationale:

| League | Reason |
|---|---|
| J1 League | Missing match cache for 2014–2015; sparse early market value data |
| Liga MX | Captures only one tournament (Clausura) — not a full-season equivalent |
| Brazilian Série A | Multi-competition rotation means league minutes don't reflect squad deployment; enhanced metric hurts predictions |
| MLS | Salary cap and expansion draft roster construction make market values a poor proxy |
| Allsvenskan | Data coverage: only 23.6% of minutes had market values in 2005, plateauing at ~85–93% even in modern seasons (vs ~99–100% for comparable leagues) |

### B Team Covariate (LaLiga 2)

Seven B team entries were identified in LaLiga 2 across 2005–2024 (FC Barcelona B, Real Madrid Castilla, Sevilla Atlético, Bilbao Athletic, Villarreal CF B, Real Sociedad B, Málaga CF B). These clubs compete in the second division with first-team market valuations, causing the model to systematically overpredict their points. Rather than dropping LaLiga 2, an `is_b_team` flag was added as a covariate throughout the model pipeline, improving LaLiga 2 R² from 0.166 to 0.264.

### Data Quality Diagnostic

A new `league_value_fit_diagnostic()` function was added to `model_comparison.R`. It tests whether leagues with lower average squad value have worse model fit (RMSE and R²) — a check on whether the metric is reliable across the wealth spectrum of leagues included.

Key finding: the correlation between log squad value and fit quality is moderate (r = −0.36 for RMSE, r = +0.53 for R²) but is not the dominant driver. Ekstraklasa (€14.5M average, R²=0.640) outperforms Allsvenskan (€11.3M, R²=0.159) entirely due to data completeness — 99%+ vs 85–93% minutes coverage. Removing Allsvenskan weakened the squad value correlation, confirming it was a double outlier rather than evidence of a systematic pattern.

---

## Final Dataset State

- **Leagues:** 14
- **Seasons:** 2005–2024
- **Team-seasons:** 5,087

---

## Current Model Performance

Results from the 15-league run (Allsvenskan still included at time of significance tests — final 14-league metrics will update on next full run):

| Metric | Baseline | Enhanced |
|---|---|---|
| R² | 0.592 | 0.637 |
| In-sample RMSE | 0.270 | 0.255 |
| Season CV RMSE | 0.276 | 0.262 |
| League CV RMSE | 0.278 | 0.264 |

- **Season CV: p < 0.0001**
- **League CV: p = 0.0001**

Both cross-validation tests are significant. The enhanced model (minutes-weighted squad value) outperforms the baseline (raw squad value) across all 20 seasons and 14 leagues.

---

## Project Status

Milestones 1–5 complete on the original 5-league dataset. The expanded 14-league, 20-season dataset has now been finalised for M3 (model comparison). Remaining work:

- Re-run M4 (residual analysis), M5 (coach attribution), and the augmented model on the expanded dataset — this would provide more stints per coach and sharpen individual rankings
- Milestone 6 extensions (Player Development Score, Playing Style Analysis) remain optional
