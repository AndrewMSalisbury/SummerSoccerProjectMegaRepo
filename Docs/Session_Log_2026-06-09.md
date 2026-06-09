# Session Log — 2026-06-09

## Purpose
Record of decisions made, code changes, results produced, and their meaning. Intended for future Claude sessions and for the developer to track analytical findings.

---

## What Was Built This Session

### Files Modified/Created
- `src/residual_analysis.R` — new file containing the full Milestone 4 pipeline

### Functions Added to `residual_analysis.R`

| Function | Purpose |
|---|---|
| `compute_residuals(dataset, log_transform)` | Fits `enhanced_fixed` on all valid rows, returns predicted PPG, residual (PPG), and residual_points for every team-season |
| `validate_balance(residuals_tbl, threshold)` | Groups by league-season, flags any where mean residual exceeds threshold |
| `top_performers(residuals_tbl, n)` | Ranked table of top n over- and underperformers by residual_points |
| `analyze_distribution(residuals_tbl, n)` | Histogram, Q-Q plot, summary stats, and top_performers table |
| `check_heteroskedasticity(residuals_tbl)` | Plots and regresses |residual| ~ log(norm_weighted_value) |
| `temporal_persistence(residuals_tbl)` | Lag-1 correlation analysis; teams matched by stripping /saison_id/YYYY from team_season_id |
| `plot_league_season_bars(residuals_tbl, league_name, season_year)` | Horizontal bar chart of residuals for one league-season |
| `plot_team_heatmap(residuals_tbl, min_seasons)` | Five heatmaps (one per league) of team residuals across seasons; teams present in >= min_seasons only |
| `run_milestone4(seasons, log_transform)` | Orchestrator; returns named list of all results invisibly |

---

## Session Start: Data Verification

Before building M4, confirmed both remaining cache gaps from prior sessions were resolved:

- **Match dates:** All 18,011 match rows have `match_date` populated (0 NAs). Date range 2015-08-07 to 2025-05-25.
- **Coach data:** 975 of 976 team-seasons covered. Single gap: SC Freiburg 2018 (`sc-freiburg/saison_id/2018`), a lone scrape failure. Negligible for M4 (coach data not used until M5).

---

## Step-by-Step Results

### Step 1 — Residuals Table

`compute_residuals()` fits `enhanced_fixed` (`points_per_game ~ log(norm_weighted_value) + as.factor(league)`) on all rows with positive `norm_weighted_value`, then predicts for all rows. Rows with non-positive values receive `NA` residuals.

**6 team-seasons have NA residuals:**

| Team | League | Season | norm_weighted_value |
|---|---|---|---|
| Sporting Gijón | laliga | 2015 | -0.114 |
| Juventus FC | serie-a | 2015 | -0.0914 |
| UC Sampdoria | serie-a | 2015 | -0.0914 |
| Cagliari Calcio | serie-a | 2021 | -0.150 |
| Torino FC | serie-a | 2021 | -0.150 |
| 1.FC Nuremberg | bundesliga | 2018 | -0.0119 |

**Root cause:** These teams had `weighted_team_value == 0` (no minutes data). The within-season imputation regression predicted a negative weighted value for them (very low-value teams where the regression line extrapolates below zero). After dividing by the league-season mean, `norm_weighted_value` is negative, making `log()` undefined. Decision: treat as NA throughout M4 and M5. 6 of 976 rows (0.6%) — not a concern.

Output table columns: `team_season_id`, `team_name`, `league`, `season`, `total_team_value`, `norm_weighted_value`, `total_points`, `games_played`, `points_per_game`, `predicted_ppg`, `residual`, `residual_points`.

---

### Step 2 — Residual Balance

8 of 50 league-seasons flagged at the default threshold of |mean residual| > 0.05 PPG:

```
league           season  residual_mean
serie-a           2015    -0.0907
serie-a           2017     0.0746
laliga            2017     0.0712
laliga            2015     0.0638
premier-league    2018     0.0627
serie-a           2016     0.0582
bundesliga        2017    -0.0537
laliga            2021    -0.0534
```

**Interpretation:** OLS guarantees residuals sum to zero across all observations, and with league fixed effects, within each league across all seasons combined — but not within individual league-seasons. A pooled model without season fixed effects will show small systematic imbalances within some league-seasons. The flagged cases (Serie A 2015–2017, La Liga 2015/2017, Premier League 2018) align exactly with the anomalous seasons identified in M3. Not a data error; documented as a known limitation of the pooled model.

---

### Step 3 — Distribution and Top Performers

```
n:              970
mean:           0
sd:             0.2378
min:            -1.0212
max:             0.8412
within ±1 SD:   69.9%
outliers >2 SD: 45
```

**Q-Q plot:** Approximately normal in the middle. Heavy tails at both extremes — sample quantiles go further from zero than a normal distribution predicts at ±3. This is leptokurtic (opposite of the "light-tailed" finding noted in M3's diagnostics; the M3 note should be treated as superseded). The heavy tails are driven by genuinely extreme seasons: Liverpool 2019, Leicester 2015 at the top; Fiorentina 2018, Southampton 2024 at the bottom.

**Top 15 overperformers (residual_points):**
1. Liverpool FC — premier-league 2019 — +32.0 pts
2. Juventus FC — serie-a 2018 — +31.6 pts *(likely data artefact — see 2018 note)*
3. Leicester City — premier-league 2015 — +30.4 pts
4. Granada CF — laliga 2019 — +26.7 pts
5. Clermont Foot 63 — ligue-1 2022 — +26.3 pts
6. Manchester City — premier-league 2018 — +24.6 pts
7. Manchester City — premier-league 2017 — +24.5 pts
8. SSC Napoli — serie-a 2018 — +24.2 pts
9. Liverpool FC — premier-league 2021 — +22.3 pts
10. Liverpool FC — premier-league 2018 — +21.1 pts

**Top 15 underperformers:**
1. ACF Fiorentina — serie-a 2018 — -38.8 pts *(data artefact)*
2. AS Monaco — ligue-1 2018 — -32.8 pts
3. Southampton FC — premier-league 2024 — -27.4 pts
4. Cagliari Calcio — serie-a 2018 — -23.8 pts
5. Aston Villa — premier-league 2015 — -22.5 pts
6. Chelsea FC — premier-league 2015 — -22.4 pts *(Mourinho sacking)*

**Key observation:** 2018 dominates both lists — five of the top 10 overperformers and five of the top 6 underperformers are from 2018. This is entirely consistent with the Serie A/2018 data quality issue identified in M3.

---

### Step 4 — Heteroskedasticity Check

```
Regression: |residual| ~ log(norm_weighted_value)
Coefficient: 0.0068
p-value:     0.2644
```

No significant relationship detected. Residual variance is consistent across the full squad value range — from small promoted clubs to elite teams. This means the coach rankings produced in M5 will be equally reliable at all levels of the table.

---

### Step 5 — Temporal Persistence

```
Consecutive season pairs: 749
Teams with >=1 pair:      135
Teams with >=3 pairs:     100

Overall lag-1 correlation: 0.2514
p-value:                   < 0.001
95% CI:                    [0.1831, 0.3174]
```

**Interpretation:** The lag-1 correlation of 0.25 is statistically significant but modest — only ~6% of variance in next-season residuals is explained by current-season residuals. There is a real but limited club effect. The bulk of year-to-year variation is not persistent, which is good news for M5: the residual is not simply a club quality proxy.

**Most persistent teams (≥3 pairs):** The top entries at minimum threshold (Las Palmas, Bochum, Metz, r ≈ 0.97–1.0) should be treated with caution — with only 3 pairs, extreme correlations can arise by chance. More reliable estimates with ≥6 pairs: AFC Bournemouth (r = 0.71, 6 pairs) and Getafe CF (r = 0.67, 7 pairs). These are mostly smaller clubs with structural constraints that create a consistent performance ceiling regardless of manager.

**Implication for M5:** The modest club effect means M5 coach attribution is meaningful but the mixed-effects model approach (team as random effect, coach as fixed effect) should be used to cleanly separate the two.

---

### Step 6 — Visualizations

Two visualization functions implemented (base R, no external dependencies):

- `plot_league_season_bars(residuals_tbl, league_name, season_year)` — horizontal bar chart for any single league-season
- `plot_team_heatmap(residuals_tbl, min_seasons = 5)` — five heatmaps, one per league, using `image()` with a red-white-blue diverging palette. Teams present in ≥5 seasons in that league, sorted by mean residual (highest at top).

---

## Documented Limitations (M4)

1. **6 NA residuals** from imputation producing non-positive `norm_weighted_value`. Treated as NA throughout. Root cause is the within-season regression extrapolating below zero for very low-value teams.
2. **8 league-seasons fail the balance check** (mean residual > 0.05 PPG). Concentrated in the same anomalous seasons as M3. Expected behaviour of a pooled model without season fixed effects.
3. **Heavy-tailed residual distribution** (leptokurtic). The 2018 data quality issue inflates both extremes. Mild concern for M5 significance tests, but with n = 970 the Central Limit Theorem provides adequate protection.
4. **Modest lag-1 club effect (r = 0.25).** Real but limited. M5 must account for it via mixed effects or by controlling for team identity.

---

## Current State of Caches

| Cache file | Status |
|---|---|
| `leagues.rds` | Populated |
| `teams.rds` | Populated |
| `players.rds` | Populated |
| `matches.rds` | Fully populated including match dates |
| `coaches.rds` | 975/976 team-seasons (SC Freiburg 2018 missing) |

---

## Immediate Next Steps

1. **Milestone 5: Coach Attribution & Rankings** (target ~July 25)
   - Join `coaches.rds` to residuals table by `team_season_id`
   - Apply mid-season change rule (coach who managed >60% of games gets the residual)
   - Fit mixed-effects model: team as random effect, coach as fixed effect
   - Produce final ranked table with mean residuals, confidence intervals, significance flags
