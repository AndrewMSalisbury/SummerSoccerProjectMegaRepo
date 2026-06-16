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

## Files Modified

- `src/source_data.r` — removed `xx_league_id_J_LEAGUE`, `xx_league_id_LIGA_MX`, `xx_league_id_SERIE_A_BRAZIL`, `xx_league_id_MLS` from `xx_all_leagues()`
- `Docs/Summary_of_Findings.md` — updated Data section, Part 1 metrics, Limitations, Conclusion
- `CLAUDE.md` — updated league description to reflect 15 active leagues and exclusion rationale
- `Docs/Session_Log_2026-06-15.md` — this file
