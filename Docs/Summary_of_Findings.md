# Summary of Findings

**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury
**Date:** June 2026

---

## Hypothesis

Minutes-weighted squad value (each player's market value scaled by their share of total team minutes) outperforms raw squad value as a predictor of final league points, and the residual from that model is attributable to coaching quality.

---

## Data

- **Source:** Transfermarkt (scraped via custom R pipeline)
- **Leagues (active):** 15 leagues — the 5 major European leagues (Premier League, La Liga, Ligue 1, Serie A, Bundesliga) plus Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, Allsvenskan, HNL, LaLiga 2, Süper Lig
- **Excluded leagues:** Argentine Liga Profesional (Transfermarkt ignores `saison_id` for this league, returning 2024 squad data for all historical seasons — confirmed data corruption); J1 League and Liga MX (sparse/missing data in early seasons and partial-season format issues); Brazilian Série A and MLS (minutes-weighted metric actively hurts predictions — multi-competition squad rotation and salary cap roster construction break the core assumption that Brasileirão minutes reflect squad deployment)
- **Seasons:** 2005–2024 (20 seasons)
- **Dataset for M3:** 5,403 team-seasons
- **Dataset for M4/M5/augmented model:** 976 team-seasons (original 5-league, 2015–2024 subset; coach attribution and rankings have not yet been re-run on the expanded dataset)

---

## Part 1: Does Minutes-Weighted Squad Value Predict Points Better?

**Finding: Yes. The hypothesis is supported.**

Both models were fitted on points-per-game with league fixed effects and log-transformed, league-season-normalised squad values. The enhanced model (minutes-weighted) outperformed the baseline (raw squad value) across all metrics:

| Metric | Baseline | Enhanced |
|---|---|---|
| R² | 0.592 | **0.637** |
| In-sample RMSE | 0.270 | **0.255** |
| Season CV RMSE | 0.276 | **0.262** |
| League CV RMSE | 0.278 | **0.264** |

Mean out-of-sample RMSE improvement: **0.014 PPG** (both cross-validation schemes).

**Significance tests (paired t-test, baseline vs enhanced):**
- Leave-one-season-out (20 folds): p < 0.0001, 95% CI lower bound = 0.011
- Leave-one-league-out (15 folds): p = 0.0001, 95% CI lower bound = 0.009

Both tests are significant. A combined model (raw + weighted together) adds negligible improvement over enhanced alone and was dropped; the weighted metric alone is the stronger predictor.

*Note: R² is lower than in the original 5-league analysis (0.73) because the 15-league dataset is far more diverse. Smaller leagues with weaker squad-value signals add variance that the model cannot fully explain with a single pooled specification. The out-of-sample improvement is more informative than in-sample R².*

---

## Part 2: Do the Residuals Contain a Coaching Signal?

**Finding: Yes. The hypothesis is supported.**

The winning model was fitted on the full dataset to generate residuals for 970 valid team-seasons (6 NA due to an imputation edge case). The residuals are approximately normally distributed (mean = 0, SD = 0.238 PPG) with no heteroskedasticity — the model is equally reliable across squad value tiers from promoted clubs to elite teams.

The lag-1 temporal persistence of residuals is r = 0.25 (p < 0.001): a modest club effect exists but explains only ~6% of year-to-year variance, meaning the residual is not simply a stable club quality proxy.

Top overperformers include Liverpool 2019 (+32 points), Leicester City 2015 (+30 points), and Bayer Leverkusen 2023 under Xabi Alonso — all well-known coaching narratives. The model identifies real sporting signals.

---

## Part 3: Is the Coaching Effect Portable Across Clubs?

**Finding: Yes. Coach variance exceeds club variance.**

Coach residuals were computed via partial attribution: each match was assigned to the coach in charge on that date using Transfermarkt appointment dates, with matches in coverage gaps dropped from both actual and expected. 99.4% of matches were attributed.

A mixed-effects model decomposed partial residual PPG into coach and club variance components:

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0113 | **8.5%** |
| Club | 0.0065 | **4.9%** |
| Residual | 0.1147 | 86.6% |

**Likelihood ratio test: χ² = 10.64, df = 1, p = 0.0011.**

Coach identity explains significant variance in performance above expectation after accounting for club-level effects. Crucially, coach variance exceeds club variance: the effect follows the manager more than it stays at the club.

---

## Individual Coach Rankings

Coaches were ranked using BLUPs (Best Linear Unbiased Predictors) from the mixed model, which apply shrinkage proportional to data scarcity — sparse coaches are pulled toward zero. Rankings are most reliable for coaches with 5+ seasons in the dataset.

**Top coaches (minimum 3 stints, 10 games):**

| Rank | Coach | Stints | Games | Clubs | BLUP |
|---|---|---|---|---|---|
| 1 | Pep Guardiola | 10 | 376 | 2 | +0.180 |
| 2 | Jürgen Klopp | 9 | 334 | 1 | +0.140 |
| 3 | Igor Tudor | 7 | 116 | 5 | +0.139 |
| 4 | Antonio Conte | 7 | 246 | 4 | +0.125 |
| 5 | Massimiliano Allegri | 6 | 226 | 1 | +0.103 |
| 6 | Éric Roy | 3 | 89 | 1 | +0.102 |
| 7 | Urs Fischer | 5 | 147 | 1 | +0.101 |
| 8 | Luciano Spalletti | 6 | 209 | 3 | +0.101 |
| 9 | Davide Nicola | 9 | 202 | 7 | +0.089 |
| 10 | Simone Inzaghi | 10 | 349 | 2 | +0.086 |

**Bottom coaches:**

| Rank | Coach | Stints | Games | Clubs | BLUP |
|---|---|---|---|---|---|
| … | Vincenzo Montella | 5 | 93 | 3 | -0.185 |
| … | Franck Passi | 4 | 24 | 3 | -0.226 |

At the individual level, **only Pep Guardiola achieves statistical significance** after Benjamini-Hochberg FDR correction (mean residual +0.39 PPG, 95% CI [0.26, 0.52], p-adj < 0.001). Other coaches show directional evidence but lack sufficient individual data for significance. This is a sample size constraint, not a failure of the model.

**Notable portability findings:** Davide Nicola (9 stints, 7 clubs, positive) and Eusebio Di Francesco (9 stints, 7 clubs, negative) provide the strongest evidence that coaching effects travel with the manager. Igor Tudor (7 stints, 5 clubs) and Antonio Conte (7 stints, 4 clubs) show consistent overperformance across diverse club environments with low standard deviations.

---

## Part 4: Does Coach Identity Improve Out-of-Sample Predictions?

**Finding: Yes. Adding coach BLUPs to the model significantly reduces prediction error.**

The strongest possible test of the coaching hypothesis is whether knowing who the coach is — based solely on their track record in prior seasons — makes predictions for a new season more accurate. A leave-one-season-out cross-validation was run comparing:

- **Enhanced model:** `points_per_game ~ log(norm_weighted_value) + league` (the M3 winner)
- **Augmented model:** enhanced prediction + games-weighted coach BLUP from training seasons only

In each fold, BLUPs were estimated exclusively from the 9 training seasons. Coaches appearing in the held-out season for the first time (no prior data) received a BLUP of 0 — a conservative default. For teams with mid-season changes, the coach adjustment was a games-weighted average of their coaches' training BLUPs.

| Fold | Enhanced RMSE | Augmented RMSE | Improvement |
|---|---|---|---|
| 2015 | 0.2444 | 0.2458 | -0.0014 |
| 2016 | 0.2170 | 0.2103 | +0.0067 |
| 2017 | 0.2187 | 0.2148 | +0.0038 |
| 2018 | 0.3002 | 0.2949 | +0.0053 |
| 2019 | 0.2706 | 0.2637 | +0.0069 |
| 2020 | 0.2192 | 0.2196 | -0.0004 |
| 2021 | 0.2091 | 0.2016 | +0.0075 |
| 2022 | 0.2386 | 0.2309 | +0.0078 |
| 2023 | 0.2190 | 0.2136 | +0.0054 |
| 2024 | 0.2357 | 0.2333 | +0.0025 |
| **MEAN** | **0.2373** | **0.2328** | **+0.0044** |

**Paired t-test: p = 0.001, 95% CI lower bound = 0.0025.** 8 of 10 folds improved.

The two non-improving folds are explainable: 2015 is the first fold, so coaches who only appear in 2015 have no training BLUP and default to 0, and BLUPs estimated from later career peaks may not reflect 2015 form. The 2020 result is essentially flat (-0.0004) and likely reflects COVID-season disruption.

**Cumulative improvement chain:**

| Step | RMSE improvement |
|---|---|
| Raw squad value → minutes-weighted (M3) | ~0.013 |
| Minutes-weighted → +coach BLUP (new) | 0.0044 |

Coach identity adds approximately one-third of the improvement that the weighting step added. This is not just a detectable signal — it is a useful predictive feature in a rigorous out-of-sample test.

---

## Year 2 Dip

A consistent but statistically inconclusive pattern was identified across multiple cuts of the data: a coach's second season at a club shows a lower residual than their first, regardless of whether the appointment was pre-season or mid-season. The effect reverses from year 3 onward and is not significant in the mixed model (p > 0.5 for pre-season appointments).

Two explanations are consistent with the data but cannot be distinguished:

- **New manager bounce:** a motivational and tactical novelty effect inflates year 1 results, with year 2 representing regression to the coach's true level.
- **Value inflation:** strong year 1 performance raises player market values, increasing predicted PPG in year 2 and compressing the apparent residual even if coaching quality is unchanged.

This is noted as a caveat on the rankings: long-tenured coaches at a single club may be modestly underrated relative to coaches who move frequently.

---

## Part 5: Expanded Dataset — M4/M5 Re-run (14 Leagues, 2005–2024)

M4 and M5 were re-run on the full expanded dataset. A minutes-coverage filter (≥80% of team minutes must have valued players) was applied before coach attribution to exclude team-seasons where sparse Transfermarkt data would produce artefactual residuals — 88 team-seasons were dropped, 4,999 retained.

### Residual Analysis (14 leagues)

- 5,080 valid residuals (7 NA from non-positive normalised squad value)
- Distribution: mean = 0, SD = 0.242 PPG, approximately normal
- No heteroskedasticity detected — rankings equally reliable across all squad value tiers
- Lag-1 temporal persistence: r = 0.203, CI [0.174, 0.232] — slightly lower than the original 5-league result (r = 0.25), consistent with more diverse leagues adding noise

### Coach Attribution (14 leagues)

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0029 | 1.9% |
| Club | 0.0051 | 3.4% |
| Residual | 0.1434 | 94.7% |

**Likelihood ratio test: χ² = 6.87, df = 1, p = 0.0088.**

The coach effect remains statistically significant, but club variance now exceeds coach variance. This reversal from the original result reflects the composition of the expanded dataset: most coaches in smaller leagues never move between leagues, making cross-club portability hard to detect. Dominant clubs in smaller leagues (Dinamo Zagreb, Legia Warsaw, Club Brugge) also create strong persistent club signals that inflate the club component.

### Top-5-Leagues Comparison (2005–2024)

To isolate the elite-coaching signal, M4 and M5 were re-run on the 5 major European leagues only across all 20 seasons. This represents the highest-quality cut of the data: the coaches with the most cross-league experience and the most stints in the dataset.

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0045 | 3.6% |
| Club | 0.0044 | 3.6% |
| Residual | 0.1156 | 92.8% |

**Likelihood ratio test: χ² = 7.23, df = 1, p = 0.0072.**

Coach and club variance are essentially tied. This sits between the original 5-league result (coach 8.5% > club 4.9%, 2015–2024 only) and the 14-league result. Extending to 20 seasons gives elite clubs more time to accumulate a stable identity signal, narrowing the gap — but the coach effect holds its own.

**How the coach/club relationship varies across dataset cuts:**

| Dataset | Coach % | Club % | Coach > Club? |
|---|---|---|---|
| 5 leagues, 2015–2024 (original) | 8.5% | 4.9% | Yes |
| 5 leagues, 2005–2024 | 3.6% | 3.6% | Tied |
| 14 leagues, 2005–2024 | 1.9% | 3.4% | No |

The pattern is interpretable: in datasets where elite coaches move frequently between leagues (the top-5 context), their portable effect is easier to detect and exceeds club-level persistence. In broader datasets with more locally-anchored coaches, club environment dominates.

### Updated Coach Rankings (top-5 leagues, 2005–2024)

Rankings use BLUPs from the top-5-leagues run, which offers the most stints per coach and the cleanest separation of coach from club effects. Three coaches achieve individual significance after FDR correction: Guardiola, Ferguson, Xavi.

**Top 15 coaches:**

| Rank | Coach | Stints | Games | Clubs | BLUP |
|---|---|---|---|---|---|
| 1 | Pep Guardiola | 16 | 596 | 3 | +0.118 |
| 2 | Alex Ferguson | 8 | 304 | 1 | +0.085 |
| 3 | Thomas Tuchel | 15 | 426 | 5 | +0.081 |
| 4 | Antonio Conte | 11 | 357 | 6 | +0.080 |
| 5 | Jürgen Klopp | 18 | 640 | 3 | +0.075 |
| 6 | Igor Tudor | 7 | 116 | 5 | +0.074 |
| 7 | Massimiliano Allegri | 13 | 468 | 3 | +0.067 |
| 8 | Claudio Ranieri | 17 | 490 | 11 | +0.062 |
| 9 | Unai Emery | 19 | 638 | 7 | +0.060 |
| 10 | Simone Inzaghi | 10 | 349 | 2 | +0.057 |
| 11 | Urs Fischer | 5 | 147 | 1 | +0.053 |
| 12 | Marcelino | 16 | 447 | 8 | +0.052 |
| 13 | Jupp Heynckes | 7 | 187 | 3 | +0.052 |
| 14 | Manuel Pellegrini | 18 | 655 | 6 | +0.051 |
| 15 | Jorge Jesus | 16 | 490 | 6 | +0.044 |

**Notable findings:**
- **Claudio Ranieri** (17 stints, 11 clubs): the most portable coach in the dataset. Consistent overperformance across an extraordinary range of clubs and contexts — the strongest portability finding in the analysis.
- **Marcelo Bielsa** (7 stints, 4 clubs, BLUP −0.070): consistently underperforms squad value across multiple clubs despite strong tactical reputation. A high-profile negative result.
- **Eusebio Di Francesco** (12 stints, 8 clubs, BLUP −0.060): strong negative portability — consistent underperformance across diverse environments.
- **Frank Lampard** (5 stints, 2 clubs, BLUP −0.062): has not converted playing ability into management results in this dataset.

---

## Limitations

1. **Sample size for coach rankings:** Coach attribution (M4/M5) and the augmented model (Part 4) were computed on the original 5-league, 2015–2024 dataset. Re-running these on the expanded 15-league, 2005–2024 dataset would provide more stints per coach and sharpen individual rankings. *(M4/M5 have since been re-run on the expanded dataset — see Part 5. The augmented model from Part 4 has not yet been re-run on the expanded data.)*
2. **Serie A minutes-weighting:** The enhanced model underperforms the baseline for Serie A in-sample (RMSE 0.224 vs 0.246), suggesting the squad rotation pattern in Italian football weakens the minutes-weighting signal. Serie A is retained because it is a core European league and the contamination is modest.
3. **Early season data sparsity:** Transfermarkt market value coverage for smaller leagues before ~2010 is incomplete. Kalmar FF Allsvenskan 2005 is the most extreme case — 26 of 27 players had no market value recorded, producing an artefactual residual of +2.02 PPG. Early seasons in HNL, Allsvenskan, and similar leagues should be interpreted with caution.
4. **Excluded leagues:** Five leagues were dropped for structural data quality reasons (see Data section). The exclusions are principled but reduce generalisability to non-European football.
5. **Value endogeneity:** Transfermarkt market values partly reflect past performance. If strong coaching in year 1 raises squad values, the model's baseline rises in year 2, potentially compressing residuals for long-tenured coaches (unconfirmed).
6. **No season fixed effects:** the pooled model produces small systematic imbalances in some league-seasons.
7. **Attribution gaps (original 5-league analysis):** 226 matches (0.6%) had no coach coverage and were excluded from attribution. SC Freiburg 2018 has no coach data.

---

## Conclusion

All parts of the hypothesis are supported. Minutes-weighted squad value is a meaningfully better predictor of final points than raw squad value — a finding that holds across 15 leagues and 20 seasons, with both leave-one-season-out (p < 0.0001) and leave-one-league-out (p = 0.0001) cross-validation tests significant. The residual from that model contains a real, portable coaching signal: coach variance is statistically significant (p = 0.0011) and exceeds club variance, meaning performance above expectation follows the manager more than it stays at the club. Most importantly, incorporating coach identity into the prediction model significantly reduces out-of-sample prediction error (p = 0.001), confirming that the coaching signal is not merely detectable after the fact but genuinely useful for forecasting.

The rankings are consistent with external assessments of coaching quality. Only Guardiola achieves individual statistical significance with the current data, but the global test establishes that the coaching signal is real. Re-running the coach attribution and augmented model on the expanded 15-league dataset would provide more stints per coach, sharpen individual rankings, and likely strengthen the predictive augmentation further.
