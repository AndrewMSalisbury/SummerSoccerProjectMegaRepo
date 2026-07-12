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
**Target: ~August 10 | Status: Complete on all big-5 leagues (July 12)**

Tests whether coaches perform above/below expectation depending on the player types at their disposal, using the M4/M5 residual as the outcome. Piloted on the Premier League 2015/16–2024/25 (July 9), then extended to all five major leagues (July 12). Deliverable: descriptive findings with statistical backing.

### Design decisions (July 6)

- **Lagged characteristics:** a player's in-season charts reflect the current coach's system. Player archetypes are defined from *prior* seasons when measuring what a coach had at their disposal.
- **Low-dimensional archetypes:** the residual signal is small, so players are grouped into a handful of robust archetypes (~6–10), not many fine categories.
- **Empirical formations:** coach formation tendencies come from per-match lineup data, not a static "preferred formation" label.

### Completed — data foundation (July 6–9)

1. SofaScore data layer (`src/source_sofascore.r`): headless-Chrome scraping, resumable per-season caches. See CLAUDE.md for access method, politeness rules, and schemas. ✓
2. Pilot scrape: all 10 seasons — 5,356 player-seasons (season stats + heatmaps), 3,800 matches (formations, per-player match stats, shot coordinates; xG from mid-2021/22). Zero failures. ✓
3. Transfermarkt crosswalk (`src/sofascore_crosswalk.r`): SofaScore ids ↔ TM player URLs, all seasons, 99.2–100% matched. ✓
4. Pass/dribble coordinate charts (`rating-breakdown` endpoint) located and scoped: only available 2025/26+, reserved as an optional validation layer. ✓

### Completed — analytical core (July 9)

See `Docs/Session_Log_2026-07-09b.md` for full detail.

**1. Feature engineering** ✓ — `src/player_archetypes.R` (`pa_` prefix). 3,476 player-seasons (≥600 minutes, non-GK), 38 style features (heatmap shape, per-90 profiles, shot locations; no xG, no quality outcomes), z-scored within season × position group. Shot coordinates verified to use a goal-at-origin convention (opposite of heatmaps); two stat fields dropped for existing only in recent seasons.

**2. Archetype clustering** ✓ — k-means within D/M/F position groups. Chosen granularity D=4, M=4, F=3 → **11 archetypes** (no-nonsense CB, ball-playing CB, defensive/attacking fullback, deep playmaker, destroyer, advanced creator, wide midfielder, pressing forward, box striker, wide creator). Silhouette preferred k=2 (sub-positions only); the fine cut was chosen for interpretability with split-half stability 0.32–0.68 documented as a limitation. Cached to `data/cache/sofascore/archetypes.rds`.

**3. Squad composition measures** ✓ — `src/coach_fit.R` (`cf_` prefix). Lagged archetypes with flagged current-season fallback (~30% of classified minutes; 2015 all-fallback by construction); minutes-weighted shares per coach stint from per-match minutes (match side derived from `is_home` — lineup team ids are scrape-time clubs, not match teams). 301 stints, unclassified share 2.6%.

**4. Coach-fit analysis** ✓ — 301/301 stints joined to M5 partial residuals (game counts r = 1.000). Global mixed model: **composition predicts residuals, LRT p = 0.013 (strict-lagged sensitivity p = 0.0017)**; wide-creator share is the dominant positive coefficient. Per-coach: 26 coaches ≥4 stints, 0/280 tests survive FDR; recurring descriptive pairs (Klopp + pressing forwards, Guardiola/Arteta + ball-playing CBs) reported as exploratory.

**6. Write-up** ✓ — `Docs/Summary_of_Findings.md` Part 6 with limitations.

### Completed — big-5 extension (July 12)

See `Docs/Session_Log_2026-07-12.md` for full detail.

1. Big-5 scrape verified complete and committed (all 40 new league-seasons; ~22k player-seasons, ~14k matches). ✓
2. Archetypes rebuilt on 17,219 player-seasons, z-scored within league × season × position group; same 11-archetype recipe with better stability (split-half ARI 0.62–0.92). M-group relabeled: destroyer / deep playmaker / **wing-back (new — surfaced by back-3 leagues)** / advanced creator. ✓
3. Team mapper rewritten (greedy one-to-one + token containment/edit-distance) after Gladbach→Dortmund-style failures; relegation-playoff teams filtered; name drift handled. Crosswalks built for all 40 new league-seasons (99.27% matched). ✓
4. Coach-fit re-run on 1,475 stints across five leagues (1,475/1,475 joined, game counts r = 1.000; cross-league lagging cut fallback share to 26.2%). **Headline replicated: composition predicts residuals, p = 0.030 / strict p = 0.0016; wide-creator share dominant at t ≈ 3.2–3.3** (+10pp ≈ +2.8 pts/season — the pilot's +5 was a small-sample overestimate). Per-coach: 149 coaches ≥4 stints, 0/1,605 survive FDR; recurring pairs led by Gasperini + no-nonsense CBs, Vieira + destroyers, Pochettino − pressing forwards. ✓
5. Write-up updated (`Summary_of_Findings.md` Part 6); `archetype_fit.rds` regenerated for the site. ✓

### Remaining (optional)

- **Validation** — scrape 2025/26 `rating-breakdown` (~11k requests/league) and confirm archetypes from cheap historical features agree with archetypes from true pass coordinates.
- **Website refresh** — re-run `export_site_data()` so coach pages show the big-5 fit results and relabeled archetypes.
- Review flagged unmatched crosswalk rows in La Liga 2023/24 and Serie A 2021/22 (NA player names in the TM cache).

### Completed When
Archetypes are validated and interpretable, squad composition measures are lagged and joined to residuals, the fit analysis is run with documented statistical evidence, and findings are written up. **Done on the full big-5 dataset July 12.**

---

## Website ✓
**Completed: July 10, 2026**

Static presentation site in `site/` covering every published result. Designed and planned first (`Docs/Website_Design.md`, `Docs/Website_Implementation_Plan.md` — the plan's ten phases are the granular steps and each records its verification), then built in a single session; see `Docs/Session_Log_2026-07-10.md` for the build record, bugs found by rendering, and the QA pass.

Key pieces: result exports (`save_coach_grades()`, `cf_save_results()`), the JSON exporter (`src/site_export.R`, `export_site_data()`), the club-crest scraper (496/496 clubs from the TM image CDN), and the vanilla-JS frontend (coach/team/league/home/writeup pages, hand-rolled SVG charts, light + dark mode).

### Completed When
Every page type renders with verified numbers, interactions work (crest click-through, sort toggles, season switcher, search), the JSON link sweep is clean, and docs are updated. **All verified July 10.** Deferred by choice: public hosting (GitHub-Pages-ready).
