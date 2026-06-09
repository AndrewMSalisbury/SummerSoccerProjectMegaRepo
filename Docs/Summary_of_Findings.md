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
- **Leagues:** Premier League, La Liga, Ligue 1, Serie A, Bundesliga
- **Seasons:** 2015–2024 (10 seasons)
- **Dataset:** 976 team-seasons, 18,011 match results, coach tenure data for 975/976 team-seasons

---

## Part 1: Does Minutes-Weighted Squad Value Predict Points Better?

**Finding: Yes. The hypothesis is supported.**

Both models were fitted on points-per-game with league fixed effects and log-transformed, league-season-normalised squad values. The enhanced model (minutes-weighted) outperformed the baseline (raw squad value) on every metric:

| Metric | Baseline | Enhanced |
|---|---|---|
| R² | 0.706 | 0.731 |
| RMSE | 0.251 | 0.238 |
| Season CV wins | 1/10 | 9/10 |
| League CV wins | 1/5 | 4/5 |

The mean out-of-sample RMSE improvement is approximately 0.013 PPG. A combined model (raw + weighted together) overfits and was dropped; the weighted metric alone is the stronger predictor.

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

## Year 2 Dip

A consistent but statistically inconclusive pattern was identified across multiple cuts of the data: a coach's second season at a club shows a lower residual than their first, regardless of whether the appointment was pre-season or mid-season. The effect reverses from year 3 onward and is not significant in the mixed model (p > 0.5 for pre-season appointments).

Two explanations are consistent with the data but cannot be distinguished:

- **New manager bounce:** a motivational and tactical novelty effect inflates year 1 results, with year 2 representing regression to the coach's true level.
- **Value inflation:** strong year 1 performance raises player market values, increasing predicted PPG in year 2 and compressing the apparent residual even if coaching quality is unchanged.

This is noted as a caveat on the rankings: long-tenured coaches at a single club may be modestly underrated relative to coaches who move frequently.

---

## Limitations

1. **Sample size:** 10 seasons across 5 leagues gives most coaches 3–5 stints — too few for individual statistical significance. Rankings are directional for coaches with fewer than 5 seasons in the data.
2. **Serie A 2018 data quality:** Transfermarkt data anomalies inflate residuals for several Serie A clubs in 2018. These entries are retained but flagged throughout.
3. **League scope:** Only the top 5 European leagues. Coaches whose careers span other competitions are incompletely represented, which understates the career evidence for some managers.
4. **Value endogeneity:** Transfermarkt market values partly reflect past performance. If strong coaching in year 1 raises squad values, the model's baseline rises in year 2, potentially compressing residuals for long-tenured coaches (unconfirmed).
5. **No season fixed effects:** the pooled model produces small systematic imbalances in some league-seasons (8 of 50 flagged), concentrated in the anomalous seasons noted above.
6. **Attribution gaps:** 226 matches (0.6%) had no coach coverage and were excluded from attribution. SC Freiburg 2018 has no coach data.

---

## Conclusion

Both parts of the hypothesis are supported. Minutes-weighted squad value is a meaningfully better predictor of final points than raw squad value. The residual from that model contains a real, portable coaching signal: coach variance is statistically significant (p = 0.0011) and exceeds club variance, meaning performance above expectation follows the manager more than it stays at the club.

The rankings are consistent with external assessments of coaching quality. Only Guardiola achieves individual statistical significance with the current data, but the global test establishes that the coaching signal is real. Extending the dataset to additional seasons and leagues would allow more coaches to reach individual significance and would sharpen the ranking for coaches currently represented by only a few seasons.
