# Working Plan

Granular steps for each milestone. Each milestone ends with a clear definition of done.

---

## Milestone 1: Data Foundation ✓
**Completed**

Scraping infrastructure built for the top 5 leagues on Transfermarkt. Player squad data (name, age, position, minutes played, market value) and match results cached locally for ~10 seasons. Caching layer prevents redundant scraping. Points calculation function verified.

---

## Milestone 2: Core Metric ✓
**Completed**

Minutes-weighted squad value formula implemented: each player's market value is multiplied by their share of total team minutes, then summed per team. Raw squad value and weighted squad value are both computed per team-season. Rank-based Pearson correlation computed across both metrics as an initial feasibility check.

---

## Milestone 3: Model Comparison ✓
**Completed: June 5, 2026**

Both models are rebuilt on a points basis and rigorously evaluated. The milestone ends when there is a statistically confident answer to whether weighting by minutes produces a meaningfully better predictor of final points.

### Prerequisites
- Milestones 1 and 2 complete ✓

### Steps

**1. Normalize for league and season effects**
- Bundesliga has 18 teams (34 games); all others have 20 teams (38 games). Convert points to points-per-game to make seasons and leagues comparable, or include league as a fixed effect covariate.
- Transfer market values inflate over time, making a €50M squad in 2015 different from €50M in 2024. Normalize squad values within each league-season (e.g., divide by the league-season mean) before fitting models.

**2. Check distributional assumptions**
- Plot the distribution of both squad value metrics. Transfer values are heavily right-skewed — evaluate whether a log transformation improves model fit before committing to a model form.
- Plot squad value vs points for each league-season to verify the relationship is approximately linear.
- Document all transformation decisions and their justifications.

**3. Fit both models**
- Baseline: `lm(points_per_game ~ total_team_value)` with league fixed effects
- Enhanced: `lm(points_per_game ~ weighted_team_value)` with league fixed effects
- Combined: `lm(points_per_game ~ total_team_value + weighted_team_value)` — tests whether weighted adds predictive power over raw
- Apply any log transformations decided in step 2 consistently across all three models.

**4. Compute in-sample evaluation metrics**
- For each model: R², adjusted R², RMSE, MAE
- Record results in a comparison table.

**5. Leave-one-season-out cross-validation**
- For each season in the dataset: train on all remaining seasons, predict the held-out season.
- Compute out-of-sample R² and RMSE per fold.
- Average results across all folds. This tests whether the model generalizes across time.

**6. Leave-one-league-out cross-validation**
- For each of the 5 leagues: train on the other 4, predict the held-out league.
- Compute out-of-sample R² and RMSE per fold.
- Average results across all folds. This tests whether the model generalizes across competitions.

**7. Statistical significance testing**
- Run a paired t-test on per-season RMSE: baseline vs enhanced. Report p-value and 95% confidence interval on the improvement.
- Run a paired t-test on per-league RMSE: baseline vs enhanced.
- Both tests must individually show a statistically significant improvement for the enhanced model to be declared the winner.

**8. Sensitivity analysis**
- Does the weighted model outperform the baseline consistently within each individual league, or only in aggregate?
- Does the result hold in early seasons (2015–2019) vs recent seasons (2020–2024)?
- Test an alternative minutes threshold: restrict to players who played at least 10% of total team minutes, and re-run the comparison. Does this sharpen the signal?

**9. Residual diagnostics for the winning model**
- Plot residuals vs fitted values to check for heteroskedasticity.
- Q-Q plot to check normality of residuals.
- Compute Cook's distance to identify unduly influential observations.
- Flag any violations as limitations to be documented.

**10. Visualization**
- Scatter plot of squad value vs points for both raw and weighted versions, with regression line.
- Side-by-side bar chart of RMSE across seasons (baseline vs enhanced).
- Side-by-side bar chart of RMSE across leagues (baseline vs enhanced).

### Completed When
Both models have been compared using in-sample metrics, two cross-validation strategies, and paired statistical tests. The winning model is identified with documented statistical confidence. All assumption checks and sensitivity analyses are complete and their findings recorded.

---

## Milestone 4: Residual Analysis
**Target: ~June 20 | Status: Active**

A clean, validated residual is computed for every team-season. The distribution and structure of residuals are analyzed to confirm they contain a real signal worth attributing to coaches.

### Prerequisites
- Milestone 3 complete — winning model identified and validated.

### Steps

**1. Fit the winning model on all available data**
- Use the model specification determined in Milestone 3 (transformations, fixed effects included).
- Fit on the full dataset of all leagues and seasons.

**2. Compute residuals for every team-season**
- residual = actual points − predicted points
- Store as a clean table: `team_season_id`, `league`, `season`, `actual_points`, `predicted_points`, `residual`.

**3. Validate residual balance**
- Within each league-season, residuals should sum to approximately zero — points are zero-sum within a season.
- Flag any league-season where the sum deviates materially as a data quality issue to investigate.

**4. Analyze residual distribution**
- Plot histogram and Q-Q plot of all residuals.
- Identify statistical outliers (residuals beyond ±2 standard deviations).
- List the top 10 positive and top 10 negative team-season residuals and verify they match known narratives (e.g., Leicester City 2015–16 should appear prominently as a large positive outlier).

**5. Check for heteroskedasticity by squad value**
- Plot residual magnitude vs squad value. Wealthier teams may have lower residual variance — if so, this is a limitation on the reliability of coach rankings for elite clubs.
- Document the finding either way.

**6. Temporal persistence analysis**
- For each team, compute the correlation between its residual in one season and the next.
- High persistence across seasons suggests a persistent club effect (culture, infrastructure, ownership) rather than a coach effect.
- Low persistence suggests the residual is more volatile and more likely coach-driven.
- This directly informs how to interpret M5 results and should be documented as context for the coach rankings.

**7. Identify top over- and underperformers**
- Produce a ranked table of all team-seasons by residual.
- Manually spot-check the top and bottom entries for plausibility.

**8. Visualization**
- Bar chart of residuals per team for a selected league-season.
- Heatmap of team residuals across all seasons (rows = teams, columns = seasons) to surface persistence patterns.

### Completed When
A validated table of residuals exists for every team-season. Balance checks, distributional analysis, heteroskedasticity check, and temporal persistence analysis are all complete and documented. The residuals are confirmed to contain a meaningful signal.

---

*[ Gap: June 23 – July 3 ]*

---

## Milestone 5: Coach Attribution & Rankings
**Target: ~July 25**

Coach-team-season assignments are scraped and integrated. Residuals are attributed to coaches. A final ranking is produced with documented statistical confidence.

### Prerequisites
- Milestone 4 complete — validated residuals table in hand.
- Coach data scraped from Transfermarkt.

### Steps

**1. Scrape coach-team-season data from Transfermarkt** ✓
- Implemented as `xx_raw_team_season_coach()` / `xx_data_coach()` in `source_data.r`, storing to `data/cache/coaches.rds`.
- Schema: `team_season_id`, `coach_id` (Transfermarkt URL), `coach_name`, `date_from`, `date_to` (NA if still in charge at season end).
- Coverage: 975 of 976 team-seasons scraped. One gap: SC Freiburg 2018 (lone scrape failure, negligible).

**2. Validate coach data quality**
- Check what percentage of team-seasons in the residuals table have matching coach data.
- Identify gaps, duplicates, and seasons with mid-season manager changes.
- Document coverage — any unmatched team-seasons are excluded from M5 and flagged.

**3. Define and apply the mid-season change rule**
- Each match is attributed to the coach whose `[date_from, date_to]` tenure bracket covers the match date. A match on a coach's exact `date_from` belongs to the new coach.
- Matches covered by no coach in the data (caretaker gaps, scrape misses) are dropped from both actual and expected for that stint — they contribute to neither numerator nor denominator.
- For each coach stint: `partial_residual_ppg = (actual_points_in_stint / games_in_stint) − predicted_ppg`, where `predicted_ppg` is the squad-value model's season-level prediction (constant within the season).
- No minimum games threshold is applied at this stage; very short stints are retained and can be filtered later if the data warrants it.

**4. Join coach data to residuals**
- Match each team-season residual to its coach using the rule from step 3.
- Produce a joined table: `coach_id`, `coach_name`, `team_season_id`, `league`, `season`, `residual`.

**5. Set and document a minimum data threshold**
- Coaches with fewer than a minimum number of seasons (e.g., 3) are excluded from the final ranking.
- The threshold should be documented and justified — too low allows noise to dominate; too high reduces the number of rankable coaches.
- Coaches below the threshold are not ranked but their data is retained for reference.

**6. Compute coach-level statistics**
- Mean residual across all managed team-seasons.
- Standard deviation of residuals (a measure of consistency).
- Number of seasons managed and number of distinct teams managed.
- Mean residual broken down by team (to surface whether the effect is portable or team-specific).

**7. Test for portability of the coach effect**
- For coaches who managed multiple teams: does their residual pattern persist across different clubs?
- Use a mixed-effects model with team as a random effect and coach as the fixed effect of interest. A significant coach fixed effect after accounting for team-level variation is strong evidence that the residual is portable coaching quality.
- This is the central analytical test of the hypothesis.

**8. Statistical significance per coach**
- For each coach above the minimum threshold, run a one-sample t-test on their residuals against a mean of zero.
- Apply a false discovery rate (FDR) correction to account for testing many coaches simultaneously.
- Distinguish between coaches with statistically significant results and those with directional but inconclusive results.

**9. Produce the final rankings**
- Rank all coaches above the minimum threshold by mean residual.
- Final table columns: rank, coach name, mean residual, 95% confidence interval, seasons managed, distinct teams managed, significance flag.

**10. Validate against known outcomes**
- Manually check whether elite coaches (e.g., Guardiola, Klopp during peak years) rank highly.
- Investigate any surprising results — either anomalies worth flagging as limitations or genuinely interesting findings.

**11. Write a summary of findings**
- State whether the hypothesis is supported, refuted, or partially supported.
- Describe the model, the methodology, and its known limitations.
- This written summary is the primary deliverable of the project.

### Completed When
A ranked list of coaches exists with mean residuals, confidence intervals, significance flags, and sample sizes. The portability test is complete. The written summary of findings is drafted. The result is presentable.

---

## Milestone 6: Coach/Player-Type Fit
**Target: ~August 10 | Status: Active**

Tests whether coaches perform above/below expectation depending on the player types at their disposal, using the M4/M5 residual as the outcome. Pilot scope: Premier League 2015/16–2024/25. Deliverable: descriptive findings with statistical backing.

### Design decisions (July 6)

- **Lagged characteristics:** a player's in-season charts reflect the current coach's system. Player archetypes are defined from *prior* seasons when measuring what a coach had at their disposal.
- **Low-dimensional archetypes:** the residual signal is small, so players are grouped into a handful of robust archetypes (~6–10), not many fine categories.
- **Empirical formations:** coach formation tendencies come from per-match lineup data, not a static "preferred formation" label.

### Completed — data foundation (July 6–9)

1. SofaScore data layer (`src/source_sofascore.r`): headless-Chrome scraping, resumable per-season caches. See CLAUDE.md for access method, politeness rules, and schemas. ✓
2. Pilot scrape: all 10 seasons — 5,356 player-seasons (season stats + heatmaps), 3,800 matches (formations, per-player match stats, shot coordinates; xG from mid-2021/22). Zero failures. ✓
3. Transfermarkt crosswalk (`src/sofascore_crosswalk.r`): SofaScore ids ↔ TM player URLs, all seasons, 99.2–100% matched. ✓
4. Pass/dribble coordinate charts (`rating-breakdown` endpoint) located and scoped: only available 2025/26+, reserved as an optional validation layer. ✓

### Remaining steps

**1. Feature engineering (per player-season)**
- Heatmap shape descriptors: centroid, spread, width/depth balance, zone occupancy shares.
- Per-90-normalized profiles from season stats: zone-split passing, long balls, crosses, dribbles, ground/aerial duels, defensive actions, touches.
- Shot profile from shot coordinates: volume, mean distance, central vs wide share, headers.
- Filter to a minimum-minutes threshold (to be set and documented).

**2. Archetype clustering**
- Cluster player-seasons (likely per broad position group) into ~6–10 archetypes; method and k to be decided with diagnostics (silhouette, stability across seasons).
- Face-validity check: known players should land in sensible archetypes.

**3. Squad composition measures**
- Lag each player's archetype to prior seasons (endogeneity guard).
- Per coach-season: archetype shares of the squad, minutes-weighted; formation distribution per coach.

**4. Coach-fit analysis**
- Join squad archetype shares to M4 residuals via the crosswalk and coach tenure data.
- Test pre-specified interactions (coach × archetype availability) with FDR control; descriptive per-coach findings for coaches with sufficient data.

**5. Optional validation**
- Scrape 2025/26 `rating-breakdown` (~11k requests) and confirm archetypes from cheap historical features agree with archetypes from true pass coordinates.

**6. Write-up**
- Add findings to `Docs/Summary_of_Findings.md` with limitations (coverage boundaries, single-league pilot, lagged-archetype survivorship).

### Completed When
Archetypes are validated and interpretable, squad composition measures are lagged and joined to residuals, the fit analysis is run with documented statistical evidence, and findings are written up.
