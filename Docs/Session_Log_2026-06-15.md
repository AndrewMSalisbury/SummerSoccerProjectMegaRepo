# Session Log — 2026-06-15

## Purpose
Record of decisions made, results produced, and their meaning. Covers finalisation of the expanded dataset and league exclusion decisions following the previous session's data expansion work.

---

## Context

The previous session (2026-06-12) expanded the dataset from 5 leagues / 10 seasons to 19 leagues / 20 seasons and removed the Argentine Liga Profesional due to confirmed data corruption. This session picked up from there, re-ran the analysis with Argentina correctly excluded, and refined the league set further based on model diagnostics.

---

## Issue: Argentina Still Appearing After Removal

The first `run_milestone3()` call still showed `liga-profesional-de-futbol` in the output (7,474 rows, same as before). Root cause: `source("model_comparison.R")` chains through `tabler.R`, but `tabler.R` does not re-source `source_data.r`. The RStudio session still had the old 20-league `xx_all_leagues()` in memory from a prior source call. Fix: explicitly `source("source_data.r")` before re-running.

---

## League Exclusion Decisions

Each league was evaluated by leave-one-league-out CV RMSE, in-sample `enhanced_wins`, and structural reasoning.

### Round 1: Remove J1 League and Liga MX (19 → 17 leagues)

**J1 League:** Missing match cache for 2014 and 2015 (warnings every run). Sparse market value data in early seasons. League-out CV RMSE 0.4033 (second worst after Argentina).

**Liga MX:** Each season captures only one tournament (Clausura) rather than a full calendar-year competition. Points totals are not comparable to a 38-game season. League-out CV RMSE 0.4204.

Result (17 leagues): R²=0.5438, season CV p=0.001, league CV p=0.083.

### Round 2: Remove Brazilian Série A and MLS (17 → 15 leagues)

**Brazilian Série A:** `enhanced_wins = FALSE` in-sample (minutes-weighting hurts). League-out CV RMSE 0.4088 vs baseline 0.3418 — enhanced is *worse* when Brazilian pattern is extrapolated from other leagues. Structural cause: clubs simultaneously play Brasileirão, Copa do Brasil, and Copa Libertadores; star players are rested from league games for continental fixtures, so Brasileirão minutes systematically underrepresent high-value players. Additionally, season runs April–December while Transfermarkt values are snapshotted in August, creating a timing mismatch.

**MLS:** `enhanced_wins = TRUE` but improvement is 0.0004 in-sample (negligible). Salary cap and expansion draft roster construction make Transfermarkt market values a poor proxy for squad strength. League-out CV RMSE 0.3810 (high).

Result (15 leagues): R²=0.6369, season CV p<0.0001, league CV p=0.0001. **Both tests significant.**

---

## Final Dataset

- **Leagues:** 15 (5 major European + Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, Allsvenskan, HNL, Süper Lig, LaLiga 2)
- **Seasons:** 2005–2024
- **Rows:** 5,403 team-seasons

---

## Final M3 Results (15 leagues)

| Metric | Baseline | Enhanced |
|---|---|---|
| R² | 0.592 | 0.637 |
| In-sample RMSE | 0.270 | 0.255 |
| Season CV RMSE | 0.276 | 0.262 |
| League CV RMSE | 0.278 | 0.264 |

- Season CV: mean improvement 0.0141, p < 0.0001, 95% CI lower = 0.011
- League CV: mean improvement 0.0140, p = 0.0001, 95% CI lower = 0.009
- `enhanced_wins` in-sample: 12/15 leagues (exceptions: Serie A, Allsvenskan, 1-HNL)

The Serie A exception (enhanced RMSE 0.2459 vs baseline 0.2233) is retained: conservative rotation in Italian football weakens the minutes-weighting signal but the contamination is modest, and Serie A is a core European league that should not be excluded on model-fit grounds alone.

---

## Cook's Distance Investigation: Kalmar FF Allsvenskan 2005

Kalmar FF 2005 had Cook's D = 0.034, roughly 3× the next-highest entry. Investigation showed 26 of 27 players had `NA` market value (only César Santin at €50,000 recorded). The weighted squad value was effectively €3,700, causing the model to predict near-zero PPG. Actual performance was normal for an Allsvenskan club, producing a residual of +2.02 — entirely a data quality artifact from sparse 2005 Transfermarkt coverage. No action taken; noted as a limitation of early-season smaller-league data.

---

---

## Part 2: Data Quality Investigation and Further Refinements

### B Team Flag (LaLiga 2)

`league_value_fit_diagnostic()` (new function, see below) showed LaLiga 2 had R²=0.166 despite €19.3M average squad value — worse than Ekstraklasa (R²=0.636, €14.5M). Root cause: B teams (FC Barcelona B, Real Madrid Castilla, Sevilla Atlético, Bilbao Athletic, Villarreal CF B, Real Sociedad B, Málaga CF B) are registered on Transfermarkt with first-team squad valuations but compete in the second division. The model predicts them to score like top-flight clubs; they don't.

Decision: add `is_b_team` as a covariate rather than dropping LaLiga 2. Implemented via regex in `build_model_dataset()`:
```r
grepl(" B$|Castilla|Bilbao Athletic|Mestalla|Fabril|Sevilla Atlético", team_name)
```
Seven B team entries confirmed across all 20 seasons. LaLiga 2 R² improved from 0.166 to 0.264.

A rank-deficient warning emerged in `cv_by_league()`: when LaLiga 2 is the test fold, the training data contains no B teams, making `is_b_team` a constant. Fixed by conditionally including `is_b_team` in the league CV formula only when `any(train$is_b_team)` is TRUE.

### Allsvenskan Data Coverage Investigation

Minutes-coverage analysis (% of minutes played by players with non-NA market values):

| Season | Allsvenskan | Ekstraklasa |
|---|---|---|
| 2005 | 23.6% | 99.9% |
| 2006 | 48.8% | 99.8% |
| 2010 | 89.2% | 99.7% |
| 2024 | 88.7% | 100.0% |

Ekstraklasa has near-100% coverage across all 20 seasons. Allsvenskan was catastrophically sparse in 2005–2006 and never exceeded 94% even in modern seasons. This directly explains the R² gap (Allsvenskan 0.159 vs Ekstraklasa 0.640) — it is purely a data completeness problem on Transfermarkt, not a structural issue with Swedish football.

Decision: drop Allsvenskan entirely. The data is fundamentally incomplete and the metric is unreliable for this league across the full time span.

### league_value_fit_diagnostic() Function

New function added to `model_comparison.R`. Joins per-league mean squad value (in €M) with in-sample RMSE and R² from the enhanced_fixed model residuals. Prints a table sorted by squad value and reports correlations. Call with `league_value_fit_diagnostic(results$dataset)`.

Final diagnostic results (14 leagues):
- Correlation (log squad value vs RMSE): −0.364
- Correlation (log squad value vs R²): +0.526
- Removing Allsvenskan weakened both correlations (from −0.552 / +0.627), confirming it was a double outlier driving the pattern rather than a genuine relationship between league wealth and model fit quality.

### Final Dataset (after all exclusions)

- **Leagues:** 14 (5 major European + Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, HNL, Süper Lig, LaLiga 2)
- **Seasons:** 2005–2024
- **Rows:** 5,087 team-seasons

---

## Files Modified

- `src/source_data.r` — removed `xx_league_id_J_LEAGUE`, `xx_league_id_LIGA_MX`, `xx_league_id_SERIE_A_BRAZIL`, `xx_league_id_MLS`, `xx_league_id_ALLSVENSKAN` from `xx_all_leagues()`
- `src/model_comparison.R` — added `is_b_team` to `build_model_dataset()`, all model formulas, and both CV functions; added `league_value_fit_diagnostic()`; fixed rank-deficient warning in `cv_by_league()`
- `Docs/Summary_of_Findings.md` — updated Data section, Part 1 metrics, Limitations, Conclusion
- `CLAUDE.md` — updated league description to reflect active leagues and exclusion rationale
- `Docs/Session_Log_2026-06-15.md` — this file
- `Docs/Progress_Report_2026-06-15.md` — session progress report
