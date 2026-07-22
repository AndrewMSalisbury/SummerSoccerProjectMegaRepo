# Summary of Findings

**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury
**Date:** June 2026

---

## Hypothesis

Minutes-weighted squad value (each player's market value scaled by their share of total team minutes) outperforms raw squad value as a predictor of final league points, and the residual from that model is attributable to coaching quality.

---

## Data

- **Sources:** Transfermarkt (squad values, minutes, coaches, matches) and SofaScore (per-player style data for Part 6), both scraped via custom R pipelines
- **Leagues (active):** 14 leagues — the 5 major European leagues (Premier League, La Liga, Ligue 1, Serie A, Bundesliga) plus Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, HNL, LaLiga 2, Süper Lig
- **Excluded leagues:** Argentine Liga Profesional (Transfermarkt ignores `saison_id` for this league, returning 2024 squad data for all historical seasons — confirmed data corruption); J1 League and Liga MX (sparse/missing data in early seasons and partial-season format issues); Brazilian Série A and MLS (minutes-weighted metric actively hurts predictions — multi-competition squad rotation and salary cap roster construction break the core assumption that Brasileirão minutes reflect squad deployment); Allsvenskan (market value coverage too sparse across the full time span — 23.6% of minutes valued in 2005, never above ~94%)
- **Seasons:** 2005–2024 (20 seasons)
- **Dataset for M3–M5:** 5,087 team-seasons (14 leagues; Parts 1–3 report the original 5-league results where noted, Part 5 the expanded re-run)
- **Dataset for Part 6 (player-type fit):** SofaScore big-5 leagues, 2015/16–2024/25 — 17,219 qualifying player-seasons, 1,475 coach stints

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

*Correction (2026-07-10): a bug in the stint builder duplicated a coach's season totals when they had two tenure brackets in the same team-season (caretaker then permanent, or sacked and re-appointed) — 79 stints were double-counted, double-weighting those stints in the coach statistics and the mixed model. All Part 5 figures below reflect the corrected data (8,207 stints across 2,341 coaches). Parts 2–4 record the original 5-league analysis as it was run; the handful of affected stints there does not change any of those conclusions.*

*Revision (2026-07-14): the M5 mixed model now weights each stint by its number of games. A per-game residual over 2 games has ~19× the sampling variance of one over 38, and the unweighted fit let brief caretaker stints count like full seasons — the estimated variance function is Var(stint) ≈ 0.014 + 1.50/n, so inverse-variance weights are essentially proportional to games (a saturating n/(n+k) alternative with the fitted k = 110 was rank-correlated 0.998 with plain games weights and less numerically stable). Games-weighted BLUPs also predicted held-out stints better than unweighted ones in an even/odd-season split test (games-weighted correlation with held-out stint residuals 0.13 vs 0.09), and they match the games-weighted quality refits that the recommender's pre-registered payoff validation tested out-of-sample (Part 7). The known trade-off: stint length is itself an outcome of performance — short stints are truncated bad spells (mean stint residual runs from −0.41 PPG at 1–5 games to +0.10 at 46+, a mostly within-coach gradient), so games weighting slightly downweights each coach's truncated disasters. The out-of-sample test says the noise reduction outweighs this selection tilt; it is retained as a limitation. The leaderboard effect is material (rank correlation 0.79 with the unweighted version): long-tenure coaches judged by full seasons rise, coaches whose best numbers came in short bursts fall. The per-coach descriptive statistics and significance tests are weighted the same way (games-weighted mean with SE = √(σ̂²_game / total games), a weighted one-sample t-test); testing now requires ≥ 3 stints, because on 1 degree of freedom the SE estimate can collapse to ~0 when a coach's two stints agree by luck. All Part 5 figures below are games-weighted; Parts 2–4 record the original unweighted analysis as it was run.*

*Display note (2026-07-14, second revision): grades, the leaderboard, and the recommender candidate pool now require a **certification bar of ≥ 109 career games** in the cut (or individual FDR significance — as of this date that exemption re-admits exactly one coach, Xavi, 103 games). The bar is presentational, not a model change: sub-bar coaches keep their BLUP and stay in the mixed model, but the site declines to certify them. Rationale: the games-weighted BLUP correctly down-weights short bad stints, so a thin record whose long stints went well can rank high on evidence the data cannot distinguish from luck (the motivating case: Andrea Mandorlini, 108 games, ranked 7th in the top-5 cut with three discounted short stints averaging −0.42 PPG). Every score-side correction tested — weight floors, a truncation-share penalty, a penalty on the weighted-minus-unweighted career-mean gap — degraded out-of-sample prediction of held-out stints (the gap even carries the opposite sign: high-gap coaches slightly beat their BLUP, p ≈ 0.02–0.03), so the ranking math is untouched and thin records are excluded from certification instead. The grade curve is re-fit on certified coaches (215 top-5, 545 all-leagues).*

### Residual Analysis (14 leagues)

- 5,080 valid residuals (7 NA from non-positive normalised squad value)
- Distribution: mean = 0, SD = 0.242 PPG, approximately normal
- No heteroskedasticity detected — rankings equally reliable across all squad value tiers
- Lag-1 temporal persistence: r = 0.203, CI [0.174, 0.232] — slightly lower than the original 5-league result (r = 0.25), consistent with more diverse leagues adding noise

### Coach Attribution (14 leagues)

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0030 | 3.7% |
| Club | 0.0031 | 3.8% |
| Residual | 1.8143 (per game) | 92.4% |

*The residual variance in the weighted model is per game; the % shares put it on the stint scale at the mean stint length (24.4 games).*

**Likelihood ratio test: χ² = 28.47, df = 1, p < 0.0001.**

The coach effect is strongly significant — much more so than in the unweighted fit (χ² = 6.01), because down-weighting noisy caretaker stints sharpens the coach signal. Coach and club variance are now essentially tied in the broad cut. The relative prominence of the club component still reflects the composition of the expanded dataset: most coaches in smaller leagues never move between leagues, making cross-club portability hard to detect, and dominant clubs in smaller leagues (Dinamo Zagreb, Legia Warsaw, Club Brugge) create strong persistent club signals.

### Top-5-Leagues Comparison (2005–2024)

To isolate the elite-coaching signal, M4 and M5 were re-run on the 5 major European leagues only across all 20 seasons. This represents the highest-quality cut of the data: the coaches with the most cross-league experience and the most stints in the dataset.

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0038 | 5.3% |
| Club | 0.0032 | 4.5% |
| Residual | 1.7683 (per game) | 90.2% |

*Per-game residual; % shares computed at the mean stint length (27.6 games).*

**Likelihood ratio test: χ² = 17.89, df = 1, p < 0.0001.**

Coach variance exceeds club variance in the top-5 cut, as in the original 5-league result (coach 8.5% > club 4.9%, 2015–2024 only, unweighted). Extending to 20 seasons gives elite clubs more time to accumulate a stable identity signal, but with caretaker noise down-weighted the portable coach effect stays clearly ahead.

**How the coach/club relationship varies across dataset cuts:**

| Dataset | Coach % | Club % | Coach > Club? |
|---|---|---|---|
| 5 leagues, 2015–2024 (original, unweighted) | 8.5% | 4.9% | Yes |
| 5 leagues, 2005–2024 | 5.3% | 4.5% | Yes |
| 14 leagues, 2005–2024 | 3.7% | 3.8% | Tied |

The pattern is interpretable: in datasets where elite coaches move frequently between leagues (the top-5 context), their portable effect is easier to detect and exceeds club-level persistence. In broader datasets with more locally-anchored coaches, the club environment carries as much signal as the coach.

### Updated Coach Rankings (top-5 leagues, 2005–2024)

Rankings use BLUPs from the top-5-leagues run, which offers the most stints per coach and the cleanest separation of coach from club effects. Four coaches achieve individual significance after FDR correction: Ferguson, Guardiola, Conte, and Xavi (Conte joins the pre-weighting three; in the all-leagues cut the set is Ferguson, Guardiola, Marek Papszun, Xavi).

**Top 15 coaches:**

| Rank | Coach | Stints | Games | Clubs | BLUP |
|---|---|---|---|---|---|
| 1 | Pep Guardiola | 16 | 596 | 3 | +0.145 |
| 2 | Alex Ferguson | 8 | 304 | 1 | +0.118 |
| 3 | Antonio Conte | 11 | 357 | 6 | +0.102 |
| 4 | Massimiliano Allegri | 13 | 468 | 3 | +0.098 |
| 5 | Urs Fischer | 5 | 147 | 1 | +0.094 |
| 6 | Thomas Tuchel | 15 | 426 | 5 | +0.085 |
| 7 | Jürgen Klopp | 18 | 640 | 3 | +0.075 |
| 8 | Franck Haise | 6 | 184 | 3 | +0.069 |
| 9 | Simone Inzaghi | 10 | 349 | 2 | +0.068 |
| 10 | Claudio Ranieri | 17 | 490 | 11 | +0.061 |
| 11 | Manuel Pellegrini | 18 | 655 | 6 | +0.057 |
| 12 | Gian Piero Gasperini | 18 | 597 | 4 | +0.054 |
| 13 | Marcelino | 16 | 447 | 8 | +0.054 |
| 14 | Unai Emery | 19 | 638 | 7 | +0.053 |
| 15 | Maurizio Sarri | 9 | 332 | 5 | +0.052 |

Games weighting reshuffles the top: full-season track records (Ferguson, Allegri, Gasperini) rise, while coaches whose strongest numbers came in shorter spells (Igor Tudor, 7 stints averaging 17 games, formerly 6th) drop out of the top 15. The certification bar removes Andrea Mandorlini (108 games, briefly 7th on the games-weighted BLUP) — see the display note above.

**Notable findings:**
- **Claudio Ranieri** (17 stints, 11 clubs): the most portable coach in the dataset. Consistent overperformance across an extraordinary range of clubs and contexts — the strongest portability finding in the analysis.
- **Marcelo Bielsa** (7 stints, 4 clubs, BLUP −0.043): consistently underperforms squad value across multiple clubs despite strong tactical reputation. A high-profile negative result.
- **Eusebio Di Francesco** (12 stints, 8 clubs, BLUP −0.039): strong negative portability — consistent underperformance across diverse environments.
- **Frank Lampard** (5 stints, 2 clubs, BLUP −0.056): has not converted playing ability into management results in this dataset.

---

## Part 6: Does Coach Performance Depend on the Player Types Available? (Milestone 6)

**Finding: Squad archetype mix predicts performance above expectation — replicated across all five major leagues; individual coach × archetype fits are suggestive but not individually significant.**

All big-5 leagues, 2015/16–2024/25, using SofaScore per-player data (season statistics, positional heatmaps, shot coordinates, per-match minutes). The analysis was first run as a Premier League pilot (July 9), then extended to the full five-league dataset (July 12); the pilot's headline finding replicated with stronger evidence at 5× the sample.

### Player archetypes

17,219 player-seasons (≥600 league minutes, outfield) were described by 38 style features — heatmap shape descriptors, per-90 passing/carrying/defending profiles, and shot-location profiles; no goals, assists, ratings, or xG (style, not quality; xG is unavailable before mid-2021/22). Features were z-scored within league × season × position group (so a player is described relative to contemporaries in the same competition) and clustered with k-means into **11 archetypes**:

| Group | Archetypes |
|---|---|
| Defenders | no-nonsense CB (Tarkowski, Pezzella) · ball-playing CB (Van Dijk, Rüdiger, Marquinhos) · defensive fullback (Azpilicueta, Coleman) · attacking fullback (Theo Hernández, Alexander-Arnold, Cancelo) |
| Midfielders | destroyer (Casemiro, Ndidi) · deep playmaker (Kroos, Modrić, Jorginho) · **wing-back** (Gosens, Hateboer, Trimmel) · advanced creator (De Bruyne, Müller, Fekir) |
| Forwards | pressing forward (Richarlison, Jota) · box striker (Kane, Lewandowski, Immobile) · wide creator (Messi, Salah, Mbappé) |

The wing-back archetype is a product of the multi-league data — back-3 systems are too rare in the PL for the pilot to have found it. Silhouette diagnostics prefer a coarser 6-archetype cut that merely rediscovers sub-positions; the finer cut is a deliberate interpretability choice, and its split-half stability improved markedly with the larger sample (ARI 0.62–0.92, vs 0.32–0.68 in the pilot).

### Coach-fit analysis

Each coach stint's squad composition (minutes-weighted archetype shares from per-match minutes under that coach) was joined to the M5 partial residuals: **1,475 of 1,475 stints matched, per-stint game counts agreeing with the Transfermarkt attribution at r = 1.000**. Archetypes are **lagged** to the player's most recent prior season — across leagues, so a Serie A → PL transfer arrives with his Serie A archetype — as an endogeneity guard; players with no prior big-5 season fall back to their current-season archetype, flagged (26.2% of classified minutes).

**Global test** (mixed model: residual ~ archetype shares + coach and club random effects, weighted by stint games):

- Composition shares vs null: **χ² = 21.34, df = 11, p = 0.030**
- Strict-lagged sensitivity (no fallback): **χ² = 30.02, p = 0.0016** — robust to the fallback choice and stronger without it

**Wide-creator share is the dominant coefficient in both specifications** (t = 3.19 / 3.30; +0.75 PPG per unit share): shifting 10 percentage points of outfield minutes from destroyers to wide creators associates with ≈ +2.8 points/season above squad-value expectation. The pilot's PL-only estimate (≈ +5 points) was roughly double — a small-sample overestimate — but the direction, ranking, and significance all strengthened with the full data. Every archetype's coefficient is non-negative relative to the destroyer reference: destroyer-heavy squads underperform their squad value most. Two readings remain consistent with the result: squads built around wide creators genuinely outperform, and/or the transfer market underprices wide creators relative to their contribution.

**Per-coach tests:** 149 coaches with ≥4 stints; 1,605 within-coach correlations between stint residuals and archetype shares; none survive BH FDR correction — even five leagues of data cannot power individual tests on 4–10 stints per coach, mirroring the M5 individual-significance result. Descriptive pairs that recur under both the fallback and strict specifications, with face validity: **Gian Piero Gasperini overperforms with more no-nonsense (man-marking) centre-backs** (strict r = 0.89 over 10 stints — his back-3 system in a nutshell), **Patrick Vieira with more destroyers** (r = 0.92/0.93), **Mauricio Pochettino underperforms with more pressing forwards** (r = −0.89 both runs), with Sergio González (+wide creators), Ivan Jurić (−advanced creators) and Oliver Glasner (−wide creators) also recurring. The pilot's PL-only pairs (Klopp + pressing forwards, Guardiola/Arteta + ball-playing CBs) remain in the underlying tables but with the reorganized big-5 archetype definitions.

---

## Part 7: Which Coach Should a Given Team Hire? (Coach Recommender)

**Finding: coach quality (the M5 BLUP) is a validated out-of-sample predictor for brand-new coach-club pairings; coach-specific player-type fit and formation-deployment forecasts are real machinery with strong mechanical validity, but did not improve hiring forecasts and ship as exploratory layers only.**

The recommender (design: `Docs/Coach_Recommender_Design.md`; implementation: `src/coach_recommender.R`) answers the conditional question "who is the best coach *for this squad*?" by decomposing predicted points into a deployed-value factor (can the coach's formations field this squad's value?) and a residual factor (coach quality + coach × player-type fit), with career-history plausibility filters on top.

### Formation profiles and rigidity

All 36,022 team-matches across the big-5 SofaScore dataset carry kickoff formations (22 distinct strings). Back-3/5 systems rose from 10.7% of matches in 2015/16 to ~36% by 2024/25 (Serie A 43%, La Liga 16%); genuine two-striker shapes are a third of all matches. Coach formation distributions are recency-weighted with a decay chosen out-of-sample (δ = 0.3 per season — what a coach plays at his *next* club is predicted best by his most recent seasons). A per-coach **rigidity** measure (formation entropy + cross-club persistence) has strong face validity: Vincenzo Italiano 0.99, Klopp 0.91, Sarri 0.85 among the most shape-rigid; Christian Streich, Davide Nicola, and Christophe Galtier among the most adaptive; Gasperini is 97% back-3.

### Deployed-value forecast (mechanically validated)

Squad players are mapped to formation slots via their archetypes (soft eligibility penalties, TM-position fallback), and a max-value XI is computed per formation; a coach's deployable value interpolates between "his shapes" and "the squad's best shape" by his rigidity. The **mechanical gate passed emphatically**: at 316 historical coach arrivals, a player's fit to the incoming coach's shapes predicts his minutes share beyond market value (t = 26.9; mean within-stint Spearman 0.52, positive in 100% of stints). The eligibility matrix tracks real deployment decisions.

### Coach-specific fit slopes (not significant)

The M6 global model was extended with shrunken per-coach random slopes on three composition axes fixed at Phase 0 (creators = F3+M4; spine = ball-players minus destroyers; wing-back share — the planned destroyer and build-up axes correlated at −0.87 and were merged pre-fit). **The slopes are not significant: LRT χ² = 2.65, df = 3, p = 0.449**; the wing-back slope variance shrank to zero. Individual coach × player-type fit remains beyond the data's resolution, consistent with the M6 per-coach FDR results.

### Payoff validation (pre-registered)

Leave-one-season-out over 2016/17–2024/25, forecasting stint PPG for the 785 **new coach-club pairings** (no stint at that club the season before), games-weighted RMSE, layers added one at a time. Primary framing uses only pre-hire information (raw squad value); the sensitivity framing conditions on realized minutes-weighted value.

| Layer added | Pre-hire RMSE | p (vs previous) | Realized RMSE | p |
|---|---|---|---|---|
| Value only | 0.3124 | — | 0.3016 | — |
| + coach quality BLUP | 0.3103 | 0.052 | 0.2992 | **0.016** |
| + global archetype effects | 0.3099 | 0.33 | 0.3000 | n.s. |
| + fit slopes + deployment | 0.3101 | n.s. | 0.3003 | n.s. |

Under the pre-registered acceptance rule (a layer ships in the headline score only if it does not hurt out-of-sample RMSE): **the quality layer ships** — knowing the coach's track record improves forecasts of new appointments, a stronger and better-targeted result than Part 4's all-teams test, and evidence the M5 BLUPs generalize to the hiring decision itself. The fit and deployment layers are a wash (−0.0003) and ship as **clearly-labeled exploratory columns**, not in the headline ranking. This asymmetry is itself informative: clubs appear to already hire for fit (survivorship pushes the measurable fit signal toward zero — we never observe the disastrous mismatches that were never hired).

### Similarity layer and plausibility filters

A descriptive companion ranks coaches by cosine similarity between the target squad's archetype mix and the compositions each coach has thrived with (profiles tilted toward overperforming stints; self-similarity gate: a coach's held-out stint ranks at the 82nd percentile against his own profile, median). For Manchester City's 2024/25 squad the strip surfaces Setién, Guardiola, Pochettino, Rose, and Arteta — possession-creator coaches, as it should.

Career-history **plausibility filters** (never mixed into the score) let a club cut the list by: has coached in this league / country, big-5 proven, similar club level (games- and recency-weighted squad-value percentile of clubs coached — Guardiola 100.0, Ferguson 98.9, journeyman firefighters ~50), recently active, and domestic coach (nationality scraped from TM profiles). Every scored suggestion appears on the club's team page for the 96 latest-season big-5 squads, ranked by the validated quality score with exploratory columns alongside; non-big-5 clubs get an honest note instead of a fake team-specific list.

---

## Part 8: What Are Coaches Good At, and What Makes Them Good? (Coach Descriptive Profile)

**Finding: a coach's overperformance splits cleanly and defensibly into an attacking and a defensive half, and the style of his teams can be described precisely — but that style is mostly the club's, not his, and *nothing* about it predicts coaching quality once club size is accounted for. The third independent attempt to find a signal beyond the quality BLUP, and the third to come back empty.**

Every coach page had answered *how good* with a single number and never said *good at what*. This part answers that (design: `Docs/Coach_Descriptive_Profile_Design.md`; implementation: `src/coach_strengths.R`, `src/coach_style.R`). It is built in three layers that sit at deliberately different points on the honesty gradient, and each is labeled with its own — the layers are **not** equally trustworthy and are not presented as if they were.

### Layer A: where the edge comes from (defensible — on the site)

The M3 model was re-fit on the **same right-hand side** (`log(norm_weighted_value)` + league + b-team) with goals-for-per-game and goals-against-per-game as the response, and the two head residuals attributed to coach stints through the identical M5 path — same coverage filter, same match-to-coach assignment, same games weighting, same BLUP shrinkage, same ≥3-stint FDR rule (reused verbatim, not re-implemented). Goals come from `matches.rds`, so this covers the full 2005–2024 span and all 14 leagues.

This makes no new attribution leap: it re-slices a residual the project already trusts, which is why it is the one layer stated plainly on coach pages ("this coach's edge is defensive").

- **Tie-back passes:** goal-difference edge vs the M4 points residual **r = 0.862** (top-5) / **0.872** (14-league), ≈ 0.59 points per goal of edge. At coach level the goal edge correlates **r = 0.823** with the published points BLUP.
- **The coach effect is stronger on goals than on points.** The 14-league LRT for coach variance gives **χ² = 160.2** for offence (p ≈ 1e-36) and 60.5 for defence, against **χ² = 28.5** for the points model. Goals-for is a lower-noise coach signal than points — worth knowing for any future model.
- Face-valid: Guardiola is top on both sides (+0.25 attack / +0.08 defence per game); Pulis and Bordalás anchor the defensive end; De Zerbi and Luis Enrique the attacking.
- **Simeone is the instructive case.** His *goal* edge is ≈ 0 (−0.03) despite a B grade: his overperformance is in converting goal difference into points, which the split describes but does not explain. His coach page says so where the contradiction would otherwise sit unexplained.

### The xG cut: process vs outcome (a recent-form lens — writeup only)

Splitting the goals cut again using SofaScore shot data yields four per-game measures: **creation** (xG-for above value expectation) and **prevention** (xG-against below it) as *process*, **finishing** (goals − xG) and **shot-stopping** (xG-against − goals-against) as *outcome*.

The **cross-source tie-back is the strongest check in this part**: the xG cut is built from SofaScore and the goals cut from Transfermarkt, and over 452 stints `creation + finishing` vs the goals cut's offensive residual gives **r = 0.949**, `prevention + shotstop` vs the defensive residual **r = 0.981**. Two independently-sourced pipelines agree — this is what would break first if the SofaScore→TM team map or the coach attribution were wrong.

The design *asserted* that process repeats and outcome doesn't; it is now tested (lag-1, same club, consecutive seasons, 165 pairs):

| measure | lag-1 r | reading |
|---|---|---|
| creation | **0.423** | the most repeatable — genuinely process |
| prevention | 0.271 | repeatable |
| finishing | 0.242 | **more persistent than assumed** |
| shot-stopping | **−0.005** | pure noise, exactly as predicted |

Finishing persisting at r = 0.24 rather than ~0 is most plausibly squad continuity (clubs keep their finishers) rather than coach skill — a reason to keep labelling finishing an unreliable *coach* signal, not to promote it. Squad value also predicts chance creation better than it predicts goals (R² 0.719 vs 0.641), consistent with goals being chances plus noise.

Two data defects had to be handled and are worth recording: **27 of 5,330 xG-era events carry a full complement of shots but are missing their goal shots entirely** (0.5%, all in 2023), which would understate creation and inflate finishing — so an event counts only if its shotmap reconciles with the scoreline on both sides; and own goals sit in the shotmap credited to the benefiting side with no xG, landing wholly in finishing, which is where they belong.

**This layer is not on the site.** Measured coverage is three seasons (2022–2024; 2021/22 is only ~40% covered and excluded), big-5 only: 452 stints, 57 coaches with ≥3 stints, none with ≥5, and **zero FDR-significant on any of the four measures**. It is a recent-form lens, never a career verdict, and a coach page is exactly where that distinction would be lost.

### Layer B: the style fingerprint (descriptive-clean — on the site, carefully labeled)

The M6 archetype recipe pointed at *team style* instead of player type: per-player-per-match → team-match → z-scored within league × season → coach-stint mean → games-weighted coach profile, over **36,018 team-matches** across all 50 big-5 league-seasons. Nine axes (possession, pressing intensity, directness, width, shot volume, chance quality, defensive solidity, set-piece reliance, lineup stability), each an **equal-weight mean of its members' z-scores** — deliberately not a PCA and not a fitted weighting: nothing here is trained against an outcome, so there is nothing to overfit and the axes stay readable.

It is literally what the teams did, so it carries no causal content. Face validity is strong on every axis (possession: Luis Enrique, Guardiola, Xavi top, Allardyce bottom; set-piece reliance: Thomas Frank, Brentford's known specialism; directness: Bordalás, Dyche). Two caricatures were corrected by the data:

- **"Guardiola presses high" resolves to *height*, not intensity.** He is ~0 on per-match pressing intensity and +1.5 SD on season-level pressing height — City make few defensive actions because opponents rarely hold the ball, yet win it high. The two measures correlate only r = 0.38 and are different traits.
- **"Simeone: low possession, low block" is not supported.** He is 74th percentile on possession and dead average on pressing height. What *is* supported is solidity (94th), narrowness (13th on width) and shot selection (84th on chance quality).

### The main Layer B result: team style is mostly the club's, not the coach's

The design treated coach-vs-squad as a caveat to bolt on. It is the finding. Per axis, a games-weighted variance decomposition (`axis ~ (1|coach) + (1|club)`), plus how much of the fingerprint **travels** when a coach changes club vs how much the club **keeps** when it changes coach:

| axis | coach var % | club var % | travels | persists | R² from squad archetype mix |
|---|---|---|---|---|---|
| possession | 11.6 | **69.2** | 0.55 | 0.82 | **0.69** |
| pressing intensity | **30.9** | 23.6 | 0.34 | 0.47 | 0.12 |
| directness | 24.8 | **52.1** | 0.52 | 0.71 | 0.51 |
| width | 29.8 | 34.6 | 0.44 | 0.50 | 0.39 |
| shot volume | 11.3 | **54.4** | 0.43 | 0.67 | 0.54 |
| chance quality | 13.8 | 27.6 | 0.29 | 0.36 | 0.11 |
| defensive solidity | 11.0 | **45.0** | 0.29 | 0.58 | 0.31 |
| set-piece reliance | 12.9 | 24.7 | 0.25 | 0.29 | 0.22 |
| lineup stability | **19.2** | 14.6 | **0.33** | 0.17 | 0.10 |

Club variance beats coach variance on **7 of 9 axes**. The squad's archetype mix *alone* explains 69% of possession, 54% of shot volume, 51% of directness. A club under two *different* coaches (possession r = 0.82) looks far more alike than a coach at two *different* clubs (r = 0.55), and after residualizing on the squad's archetype mix the travel correlations collapse (possession 0.55 → 0.17). **Consequently the site labels every radar as the style of the teams this coach ran — never "his style".**

**Two axes survive as genuinely the coach's**, and the site marks them:

- **Lineup stability** — the only axis where coach variance beats club, the only one that travels better than it persists, 10% personnel-explained, and it still travels after residualization. Rotation is a decision, not a squad property. The design's hunch that this is "a real coach signature nobody visualizes" is confirmed.
- **Pressing intensity** — the best tactical axis: highest coach share (30.9% vs the club's 23.6%), 12% personnel-explained, the only tactical axis still standing after residualization.

*Method caveat, stated because it cuts against the headline:* travel-vs-persist is not a like-for-like ownership contest — consecutive coaches at one club inherit nearly the same squad, so `r_club > r_coach` is expected under *any* model where the squad matters. The variance decomposition estimates both effects at once and is the better instrument; it agrees on 7 of 9, which is why the conclusion stands. Neither check is causal: coaches are hired by clubs that already suit them (inflating travel), and the archetype mix is partly one the coach shaped (so the residual strips out some of his own signature). These are bounds, not an identified split.

### Layer C: what makes coaches good? Nothing here does. (null — deliberately not on the site)

The literal question. The M5 quality BLUP was regressed on the nine style axes plus rigidity across the **231 coaches** with both a top-5 BLUP and a fingerprint, games-weighted, with families pre-specified from the Layer B result rather than chosen from the data.

**Every raw association is large and FDR-significant** — defensive solidity **+0.64**, shot volume +0.53, possession +0.52, chance quality +0.46, lineup stability −0.37, rigidity +0.25 (standardized). Taken at face value this is a rich "what makes coaches good" story, and it would have been the most shareable content the project ever produced. **All of it is artifact.** Four checks, each killing a different group:

| check | question it asks | casualties |
|---|---|---|
| consistency across 4 specs | same sign and significant in raw / squad-residualized / club-controlled / graded-only? | pressing, directness, width, set-piece reliance |
| separable from club level | can the axis be told apart from club size at all? | possession (**r = 0.86** with the coach's mean club value percentile), shot volume (0.81), solidity (0.74) |
| restates the outcome | is the axis built from the thing the BLUP measures? | chance quality (+ solidity, shot volume again) |
| within- vs between-coach | does the *same* coach do better when he does more of it? | **lineup stability — sign reverses** |

**Nothing survives.** Rigidity alone is unkilled (+0.155 club-controlled, q = 0.043) — and only because it is a career constant with no within-coach variation, so the decisive check *cannot run on it*. That is an untested predictor, not a validated one, and it is recorded as "between-coach only; untestable" rather than allowed to pass by default. Three traps are worth stating so nobody re-walks them:

- **The all-axes multivariable is a suppression trap.** It reports club level at β = **−0.60**, which reads as "big clubs underperform their value"; the bivariate is **+0.39**, the opposite. The tell that generalizes: possession's coefficient *rises* under a club control (0.517 → 0.568), which no genuine confound removal does. One axis + one control is the only interpretable spec.
- **Lineup stability is a Simpson's paradox** — and it is the phase 4 coach-owned axis, so it was the one most likely to be believed. Between coaches, rotators grade higher (−0.373, q < 0.0001, in all four specs). Within a coach, *stability* associates with better seasons (**+0.131**, p < 0.0001); within a club, +0.110. The between-coach version is club sorting: the heaviest rotators are Heynckes, Tuchel, Allegri and Luis Enrique, all at top clubs with European fixture loads.
- **Several "style" axes are performance restated.** Defensive solidity is built from shots conceded — a step on the path to conceding goals and dropping points. "Solid teams overperform" is a restatement, not a discovery.

**The confound the layer runs aground on** is worth stating on its own: `r(club_pct, blup) = **+0.39**` — coaches at bigger clubs grade higher (about +0.2–0.3 across the full coach population; +0.39 in this style-overlap subset). Whether that is better coaches being hired by bigger clubs, or the value model under-predicting big clubs, is what determines whether the *ranking* itself is trustworthy. For the ranking, this has since been **tested directly (2026-07-21) and resolved in favour of selection**: splitting club size into between- and within-coach parts, the between-coach slope is positive (+0.00087, t = 4.2 — the confound) but the **within-coach slope is negative** (−0.00085, t = −5.0; coach fixed-effects cross-check −0.00086, p = 1e-7). Mis-specification would require a *positive* within-coach slope — the same coach overperforming more once he moves to a bigger club — so its sign is wrong, and the correlation is composition (good coaches at big clubs, effect genuinely theirs). Refitting the BLUPs with a curvature-corrected (spline) value term leaves the ranking essentially unchanged (rank r = 0.98, Guardiola still #1) and shrinks the confound only 0.21 → 0.16. The one real residual is small: linear-in-log slightly under-predicts the single biggest club per league (top decile +0.08 PPG; the spline correction is out-of-sample-validated, 2.55% lower RMSE, p = 0.0017), inflating the grades of coaches *permanently* at elite clubs by ~0.02–0.04 PPG without reordering them. **None of this rescues Layer C:** the style axes remain near-proxies for club size and their causal content is not identifiable from between-coach correlations, which is a separate matter from whether the BLUP is a valid coach effect.

**There is therefore no Layer C block on the site** — only this null and the reason for it. The raw correlations are not shown as findings anywhere.

### Why the null is the most valuable thing here

This is the **third independent attempt to find something beyond the quality BLUP**, and the third to come back empty (a fourth, a different *outcome* rather than a decomposition, follows in Part 9):

| attempt | verdict |
|---|---|
| M6 coach-specific player-type fit (Part 6/7) | LRT p = 0.449 — not significant |
| Recommender payoff validation (Part 7) | only the quality layer improves hiring forecasts |
| Layer C style → quality (Part 8) | every association dies under scrutiny |
| Coach Development Effect (Part 9) | orthogonal to points, but does not repeat OOS (r ≈ 0) |

Four different research directions, four different data slices, one consistent answer: **the coach signal this project can measure is a single quality number, and attempts to decompose it — or to find a second, independent coach effect — have not survived validation.** That consistency is worth more than any of the correlations would have been — and it is the reason the site ranks and describes coaches but does not pretend to explain them.

---

## Part 9: Do Players Get More Valuable Under a Coach? (Coach Development Effect)

The rest of the project measures a coach against *points*. This part asks a different, euro-denominated question a sporting director cares about almost as much: **do players appreciate in market value faster than their own trajectory predicts under a given coach?** A €5m academy graduate sold for €40m is value the points table never records. It is the first genuinely *new outcome* the project has tried — not a re-slice of the points residual (Part 8) — so it was the best chance either to corroborate the quality signal from an independent direction or to expose that the two measure the same thing.

**Method (mirrors M3→M4→M5).** The response is log value growth `g = log(value_{t+1} / value_t)` for a player at the same club in consecutive seasons (34,653 player-seasons in the big-5, 80,033 across 14 leagues). A baseline expectation model regresses `g` on *confounders only* — a natural-spline age curve interacted with position group, a splined starting value (mean reversion), the player's own prior-season momentum, and league and season fixed effects — deliberately leaving every *mediator* (minutes, results, the player's own output) in the residual, because conditioning on something the coach causes would subtract the very effect being measured. The development residual is attributed to the coach(es) who ran the club that season (minutes-and-games-weighted through the M5 spine) and fed to a mixed model with **player, club, and coach** random effects. The player random effect is the metric's integrity: without it, a coach handed naturally-rising talents is simply credited for their trajectory.

**The baseline works and the residual is clean.** It captures the dominant age story exactly (teens gain ~+0.22 log-value/year, over-30s lose ~0.29), the residual is flat across age bins and starting-value deciles, and its extremes are the right players — the biggest over-expectation seasons are the canonical breakouts (Chiesa €0.1m→€10m at 17, Mainoo €0.8m→€50m, Aouar, Ekitiké), the biggest under-expectation ones are aging collapses. As a *player-development* residual it is trustworthy.

**As a coach metric it is a null.** Three pre-registered gates, and it fails the one that matters:

| gate | result | verdict |
|---|---|---|
| **Orthogonal to points** (is it just points in euros?) | cor(CDE, points BLUP) = 0.20–0.27; **93–96% of CDE variance is orthogonal** to the points BLUP | passes — genuinely a different axis |
| **Repeatability out-of-sample** (does a coach's effect in even seasons predict his effect in odd seasons?) | split-half r = **−0.07** (big-5) / **+0.05** (14-league); 95% CI [−0.01, 0.11], n = 792 | **fails — indistinguishable from zero in both cuts** |
| **Face validity** (do known developers surface?) | top of the list is journeyman coaches, not the Klopp/Ten Hag/Salzburg-type tenures predicted | weak |

The in-sample coach variance component looks impressive (18–22% of variance, LRT p < 1e-60) — and that is exactly the trap. It does not repeat within a coach's own career, so it is not a coach trait; it is *which players happened to blow up on his watch*. The decomposition confirms the mechanism: the **player random effect is the dominant component (44–62%)**, and once persistent per-player appreciation is properly accounted for, the coach-level signal that remains is noise. The result is robust to adding transfer movers (rank correlation 0.89–0.94 with the same-club-only ranking), so it is not an artefact of sample selection — the null itself is stable.

**Nothing about this ships to the site** (no "develops value" tag, no coach-page number), exactly as the design pre-committed for a failed validation. What ships is the honest finding: *player value growth is real and measurable, but it is an age-and-talent story, not a coaching one that this data can separate from luck.* The one durable by-product is the clean player-development residual (`player_dev_residuals_*.rds`), which characterises players, not coaches.

**Follow-up (does a pattern hide inside a subgroup, or at the club?).** Two natural rescues were tested and one returned something real:

- **Player type does not rescue the coach signal.** Restricting the repeatability test to young players (age ≤ 21, where development actually happens), to each position group, or to each of the 11 SofaScore archetypes leaves the coach effect null everywhere — young players are if anything slightly *negative* (r = −0.09 to −0.16, mean-reversion). Slicing does not turn luck into signal.
- **A clean descriptive by-product on archetypes.** Because the residual is already de-confounded for age, price and position, its mean *by archetype* reveals which player *types* appreciate beyond their trajectory: **attacking/creative roles most** (wide creator +0.07–0.08, deep playmaker/box striker/attacking fullback ≈ +0.04), **defensive fullbacks least** (−0.02), consistent across both cuts. This corroborates Part 6's finding that wide creators are the most valuable archetype per unit of squad value — from an entirely independent (value-growth) direction. It is a fact about player types, not coaches.
- **The one genuine coach-independent signal: clubs, but only in selling leagues.** Are teams consistent in growing players *across* managers? At the club level the answer is a qualified yes — and it is sharply split by league tier. A club's player-value-growth level under one manager predicts its level under the *next, different* manager with **r ≈ +0.10 (p = 0.0002)** for consecutive regimes (r ≈ +0.31 for a disjoint alternating split) — **but that entire signal lives outside the big five.** Big-5 clubs show none (consecutive-regime r = +0.005), while non-big-5 clubs — the Eredivisie/Liga Portugal/Championship-type development pipelines — carry all of it. It makes intuitive sense: selling-league clubs are built to appreciate and move on players regardless of who is in the dugout; big-5 clubs buy finished talent, so their players' value moves are idiosyncratic. (A first pass showed a spurious +0.40 driven by mid-season-change player-seasons being shared between two managers; collapsing each player-season to its primary coach removed the artifact and left the real, smaller selling-league effect.) The signal is a **club property, not a coach one, and modest even where it exists** — which is why it strengthens rather than undermines the CDE verdict: the part of player value growth that *does* repeat belongs to the club and its market, not the manager.

**Does the points grade then miss the coaches at these developmental clubs?** Checked directly, and no. Across 435 coaches with ≥ 100 games, the points BLUP is uncorrelated with how selling-league a coach's career is (r = −0.03; mean grade 75.7 for both tiers — no penalty for developmental-league work) and *positively*, not negatively, related to his value-growth (r = +0.20) — the opposite of what a systematic miss would produce. The top developmental environments are run by coaches the grade already rates highly (Urs Fischer A+, Warnock A+, Gasperini A-, Solbakken, Kek, Papszun). And the mechanism is explicit: a coach's own value-growth correlates 0.59 with the development level of the *clubs* he worked at, so what looks like "he develops players" is mostly "his clubs do." The residual "high-development-environment, low-grade" coaches (Kompany's relegated Burnley, Burley, Jokanović) are genuine points under-performers with noisy, non-repeatable personal value-growth — nothing the grade should have caught. The only honest gap is one of *attributability*, not bias: a sporting director hiring for a selling club gets no development signal from a points-only grade, because development is not a coach-attributable skill in this data — it belongs to the club.

---

## Part 10: Can the Model Beat the Betting Market? (Market Benchmark)

Every validation so far has been *internal* — leave-one-season-out, held-out coach-club pairings, the project scoring itself against its own squad-value baseline. The fair sceptical reply is: *"your baseline is your own model; show me you beat, or add to, the market."* The bookmakers' closing line is the aggregation of every serious model plus real money on the outcome — the toughest, most credible baseline available, and the one benchmark that already prices in **both** the squad and the manager. This part builds a leakage-free, walk-forward match forecaster from the project's validated pieces and tests it against that line. It was pre-registered as **confirmatory**: the metrics were fixed before the run, and a null — "the market already knows what we know" — was declared in advance to be a legitimate, on-brand result, not a failure.

**The data.** Results and closing odds come from football-data.co.uk for 13 of the project's 14 leagues (all but Croatia, which it does not carry) — 51,807 matches, 2012/13–2024/25, 99.9% carrying **Pinnacle** (the sharpest book) de-margined closing odds. Mapping football-data's abbreviated team names to Transfermarkt clubs is the real engineering cost; the crosswalk was verified not by name similarity but by reconciling each club's fd-derived season points against Transfermarkt's own match records — **99.7% exact outside Belgium** (100% for seven leagues), with Belgium's gap fully explained by Jupiler Pro League playoff fixtures football-data carries and the TM cache does not. The ingest and crosswalk (`src/source_odds.R`) are a clean, reusable external dataset now integrated into the project.

**Leakage is the whole game.** The forecaster uses only pre-match-known inputs: a **pre-season squad-value snapshot** (never the minutes-weighted value, which embeds realized in-season minutes) and the **coach quality BLUP refit on completed seasons strictly before the match** (an expanding-window re-run of the full M5 mixed model, 13 times; a coach with no prior history enters at the shrinkage prior, BLUP 0 — itself the honest forecast). Team strength enters a Dixon–Coles bivariate-Poisson goal model whose coefficients are themselves fit only on prior seasons; predictions are compared to the de-margined closing probabilities over the walk-forward test set (47,982 matches, 2013–2024). The evaluation is a McFadden conditional logit of the realized result on the market's implied probability plus the model's signal — a **significant coefficient on our signal after conditioning on the market is the honest, high-power test of whether we carry information the closing line underweights; it does not require beating the book.**

**The forecaster does not beat the market, and it does not add to it.** On the leakage-free model the market is sharper on every metric and in every one of the 11 leagues (pooled log-loss 0.978 vs 1.014). And conditioning on the market, the model's incremental coefficient is **+0.023 (z = 1.0, p = 0.31) — indistinguishable from zero.** The squad-value differential adds nothing beyond the line (p = 0.31); so does the model as a whole. This is the market-efficiency null, stated plainly: **the closing line already contains everything our pre-season squad-value forecast knows.**

**The coaching question — the one that most mattered — is a clean null too.** The market surely prices the squad; the open possibility was that it *mis*prices a new or low-profile manager, in which case the coach BLUP would be underpriced and carry incremental information. It does not. The as-of coach BLUP differential adds nothing beyond the market (coef −0.17, p = 0.51), nothing beyond market **and** value (p = 0.51), and — the pre-declared subgroup where mispricing was most plausible — **nothing even among low-profile / first-observed managers** (coef −0.41, p = 0.32, n = 36,425). The market already prices coaching quality as well as our model measures it. (Attempting instead to fold the coach term *into* the goal model produced a collinear, sign-flipping, fold-unstable coefficient — the BLUP is largely redundant with squad value for forecasting goals — which is why the forecaster is value-plus-home and the coach is tested as a separate incremental signal.)

**The leakage check is the sharpest lesson.** A first, *naive* version of the forecaster — using each season's **own** Transfermarkt squad value rather than the prior season's — looked like a striking win: its incremental coefficient beyond the market was **+0.224, p = 1 × 10⁻²¹.** It would have been the project's headline. It was an artefact. Transfermarkt's season valuation is updated *within* the season and has already absorbed that season's results, so a team overperforming carries an inflated value that correlates with outcomes by hindsight. Swapping in strictly pre-season (prior-season) value — the only change — collapsed the coefficient from +0.224 to +0.023 and the p-value from 10⁻²¹ to 0.31. The entire apparent edge was within-season leakage. It is preserved here deliberately, as a live demonstration of exactly the failure the design named "the whole game": against a near-efficient benchmark, a leakage of a few percent of variance is the difference between a spurious 10⁻²¹ and the truth.

**The P&L backtest corroborates.** A pre-registered flat-stake rule (bet every outcome whose model edge exceeds 5% at Pinnacle closing) on the leakage-free model returns **−6.4% ROI** (bootstrap 95% CI [−8.1%, −4.8%] — significantly *losing*), worsening to −9.9% once a realistic 5% price haircut acknowledges that a bettor rarely gets the closing line. Every odds bucket loses. A forecaster that carries no information beyond the market cannot beat the margin, and this one does not.

| test (leakage-free forecaster, 47,982 matches) | result | verdict |
|---|---|---|
| **Skill vs market** (log-loss) | market 0.978, model 1.014; market better in all 11 leagues | market is sharper |
| **Incremental info beyond market** (§4.2) | model coef +0.023, p = 0.31 | **null** |
| **Coach BLUP beyond market** (§4.3) | coef −0.17, p = 0.51 | **null** |
| **Coach BLUP, low-profile managers** (§4.3 subgroup) | coef −0.41, p = 0.32 | **null** |
| **P&L** (5% edge, Pinnacle closing) | ROI −6.4%, CI [−8.1%, −4.8%] | loses money |
| *naive current-season value (leakage)* | *incremental +0.224, p = 10⁻²¹* | *artefact — killed by the prior-value check* |

**What this adds to the project.** It is the first *external* validation the project has run, and it returns the fourth on-brand "the signal is real but not incrementally exploitable" result — joining coach × player-type fit (Part 6), the recommender's fit and deployment layers (Part 7), and player value growth (Part 9). The three previous nulls were measured against the project's own baselines; this one is measured against the sharpest baseline in existence, and it agrees. The honest reading is not that the coaching signal is fake — Parts 1–5 establish it is real, portable, and useful for forecasting a hire against a *squad-value* baseline — but that **the betting market has already discovered and priced it.** A near-efficient market pricing our signal is a form of external corroboration that the signal is real, and simultaneously the ceiling on its exploitability. Like the other nulls, nothing here ships to the site as an interactive surface; the verdict lives in this writeup, where a null belongs.

---

## Limitations

1. **Sample size for coach rankings:** Coach attribution (M4/M5) and the augmented model (Part 4) were computed on the original 5-league, 2015–2024 dataset. Re-running these on the expanded 15-league, 2005–2024 dataset would provide more stints per coach and sharpen individual rankings. *(M4/M5 have since been re-run on the expanded dataset — see Part 5. The Part 4 question — does coach identity improve out-of-sample prediction? — was re-tested on the expanded-era data in Part 7's payoff validation, on the harder target of new coach-club pairings, and holds: p = 0.016 in the realized-value framing.)*
2. **Serie A minutes-weighting:** The enhanced model underperforms the baseline for Serie A in-sample (RMSE 0.224 vs 0.246), suggesting the squad rotation pattern in Italian football weakens the minutes-weighting signal. Serie A is retained because it is a core European league and the contamination is modest.
3. **Early season data sparsity:** Transfermarkt market value coverage for smaller leagues before ~2010 is incomplete. Kalmar FF Allsvenskan 2005 is the most extreme case — 26 of 27 players had no market value recorded, producing an artefactual residual of +2.02 PPG. Early seasons in HNL, Allsvenskan, and similar leagues should be interpreted with caution.
4. **Excluded leagues:** Five leagues were dropped for structural data quality reasons (see Data section). The exclusions are principled but reduce generalisability to non-European football.
5. **Value endogeneity:** Transfermarkt market values partly reflect past performance. If strong coaching in year 1 raises squad values, the model's baseline rises in year 2, potentially compressing residuals for long-tenured coaches (unconfirmed).
6. **No season fixed effects:** the pooled model produces small systematic imbalances in some league-seasons.
7. **Attribution gaps (original 5-league analysis):** 226 matches (0.6%) had no coach coverage and were excluded from attribution. SC Freiburg 2018 has no coach data.
8. **Archetype analysis (Part 6):** per-coach findings are exploratory throughout — within-coach correlations on 4–10 stints cannot survive FDR even with 149 coaches across five leagues; only the global composition test is confirmatory. Archetype granularity (11 types) is an interpretability choice over silhouette diagnostics, with split-half stability 0.62–0.92; 26.2% of classified minutes rely on a current-season fallback (100% in 2015, which has no prior season) — the global result strengthens under the strict-lagged sensitivity, and per-coach pairs were only highlighted when they recur in both specifications. The 2015/16–2024/25 window and big-5 scope are set by SofaScore coverage.
9. **Descriptive profile (Part 8):** the three layers are not equally trustworthy and must not be read as one block. Layer A is a re-slice of the M4/M5 residual and is as trustworthy as the residual is — but goal difference maps to points monotonically and *noisily* (r = 0.86), so it characterises an edge without fully explaining it (Simeone: a B grade on a ≈ 0 goal edge). The xG cut spans only three big-5 seasons (2022–2024; 2021/22 excluded at ~40% coverage), has no coach with ≥5 stints and **nobody FDR-significant**, and is a recent-form lens, not a career verdict — it is deliberately kept off coach pages. Layer B is big-5 only (2015/16–2024/25), so coaches seen only in the Championship or Eredivisie get Layer A but no fingerprint, and no radar is fabricated for them; it describes the *team's* style, co-produced with the squad, and is only the coach's own on lineup stability and pressing intensity. Pressing *height* is season-level and cannot be split between two coaches of one team-season (58% of stints sit in a multi-coach season), so it ships flagged. Layer C is a **null**: every style→quality association fails at least one of four checks and none is shown as a finding. The site's style percentiles are ranked among the 256 coaches clearing a 38-game bar, so they differ slightly from percentiles quoted elsewhere against a ≥100-game reference class. The `club_pct ↔ BLUP` correlation that Layer C ran aground on was subsequently tested for the *ranking* (2026-07-21): the within-coach club-size slope is negative (−0.00085, t = −5.0), the wrong sign for value-model mis-specification, so the grades are a valid coach effect driven by selection rather than by the model under-predicting big clubs; the ranking is robust to a curvature-corrected value term (rank r = 0.98). The only real residual is a small linear-in-log under-prediction of the single biggest club per league (~0.02–0.04 PPG on permanent-elite coaches, order unaffected). This validates the ranking, not Layer C — style axes stay non-identifiable against club size.
10. **Coach Development Effect (Part 9):** the euro-value-growth metric is an **exploratory null** and appears nowhere on the site. The player-development *residual* it is built on is sound, but the coach-level effect does not repeat out-of-sample (split-half r ≈ 0 in both cuts), so no coach ranking or "develops value" descriptor is defensible. Two honest gaps remain unclosed and were flagged in the design: contract length remaining (a genuine value driver, not the coach's doing, absent from the cache — needs a scrape) is an omitted confounder, and the metric was never tied back to *realized transfer fees* (paper TM valuations vs actual money), which would need a new Transfermarkt transfer-history scrape. Neither would rescue a metric that already fails repeatability, but both are why even the in-sample decomposition is not over-read.
12. **Market benchmark (Part 10):** the leakage-free forecaster is deliberately simple — a pre-season squad-value snapshot plus a home effect in a Dixon–Coles goal model, with the coach BLUP as-of. The squad-value input is a *season-level* Transfermarkt valuation, not a matchday-frozen one, which is precisely why the prior-season variant (strictly pre-season, zero look-ahead) is the primary and the current-season variant is reported only as the leakage demonstration; a truly matchday-frozen value is not in the cache. The result is a null against the *closing* line — the hardest bar; the design's achievable-price rails (a 5% haircut, favourite/longshot buckets) are included precisely because closing prices are rarely obtainable, and they only widen the loss. Denmark and Poland (football-data's combined-file leagues) and pre-2012 seasons are not yet ingested (2012/13+ is the Pinnacle-clean primary window); Croatia is absent from the source. The coach term could not be stably fit *inside* the goal model (collinear with squad value), so its incremental value is tested directly rather than as a forecast-skill improvement — a conservative choice, not a limitation of the verdict, which is a clean null on every framing tried.
11. **Coach recommender (Part 7):** team-specific suggestions exist only for big-5 clubs with a latest-season squad; every other club gets the quality-only leaderboard. The fit and deployment columns are exploratory — mechanically valid but not validated as forecast improvements — and the validation universe (realized appointments) is survivorship-biased toward fits clubs already chose, so the measurable fit signal is conservative. Kickoff formations miss in-match shape changes. Plausibility filters are career-history proxies, not availability: contracts, wages, and willingness are unmodeled. Coach nationality coverage depends on a slow, resumable Transfermarkt profile scrape and may be partial at any given export.

---

## Conclusion

All parts of the hypothesis are supported. Minutes-weighted squad value is a meaningfully better predictor of final points than raw squad value — a finding that holds across 15 leagues and 20 seasons, with both leave-one-season-out (p < 0.0001) and leave-one-league-out (p = 0.0001) cross-validation tests significant. The residual from that model contains a real, portable coaching signal: coach variance is statistically significant (p = 0.0011) and exceeds club variance, meaning performance above expectation follows the manager more than it stays at the club. Most importantly, incorporating coach identity into the prediction model significantly reduces out-of-sample prediction error (p = 0.001), confirming that the coaching signal is not merely detectable after the fact but genuinely useful for forecasting.

The rankings are consistent with external assessments of coaching quality. Only Guardiola achieves individual statistical significance with the current data, but the global test establishes that the coaching signal is real. Re-running the coach attribution and augmented model on the expanded 15-league dataset would provide more stints per coach, sharpen individual rankings, and likely strengthen the predictive augmentation further.

Milestone 6 (Part 6) extends the picture from *how much* coaches outperform to *when*: performance above squad-value expectation is not neutral to squad composition. The mix of player types a coach inherits — measured from prior-season playing style, before the coach's own system can contaminate it — predicts the stint residual, a finding that replicated when the analysis grew from the PL pilot to all five leagues (p = 0.030; p = 0.0016 strict-lagged, with the wide-creator coefficient strengthening to t ≈ 3.3). Wide creators are the most valuable archetype per unit of squad value; destroyer-heavy squads underperform theirs most. Individual coach × player-type fits (Gasperini with man-marking centre-backs, Vieira with destroyers) are descriptively consistent across specifications but await more data for individual significance — the same sample-size frontier as the individual coach rankings.

The coach recommender (Part 7) turns the model toward the decision it was always about: hiring. Its pre-registered validation delivered a sharp verdict — the coach quality signal survives the hardest test available (forecasting brand-new coach-club pairings out-of-sample, p = 0.016), while coach-specific fit and formation-deployment forecasts, despite passing their mechanical checks convincingly, add nothing detectable to hiring forecasts and ship as exploratory context only. The honest summary for a sporting director: the model can tell you *who the good coaches are* with validated confidence, can describe *which squads they have thrived with*, and can flag *whether your squad's value fits their shapes* — but the last two are judgment aids, not predictions.

The descriptive profile (Part 8) asks the two questions a ranking never answers — *good at what?* and *what makes them good?* — and gets one clean answer and one instructive refusal. The first is defensible: overperformance splits into an attacking and a defensive half that ties back to the points residual at r = 0.86, and the coach effect turns out to be **stronger on goals than on points** (χ² = 160 vs 28), so every graded coach now carries an offence/defence tilt. The second does not survive contact with the data. Team style can be measured precisely, but it is mostly the *club's* — club variance beats coach variance on 7 of 9 axes and the squad's player-type mix alone explains 69% of possession — and every apparently large style→quality association (solidity +0.64, possession +0.52) dies under one of four checks, most of them because the style axes cannot be told apart from club size (possession correlates 0.86 with it). That makes four independent attempts to find a signal beyond the quality BLUP — coach × player-type fit, the recommender's fit and deployment layers, style, and a wholly separate euro-denominated outcome (player value growth, Part 9) — and four empty results. The last is the sharpest: player value growth is large, measurable, and 93–96% orthogonal to points, yet the coach's part of it does not repeat across his own career (split-half r ≈ 0), because it is an age-and-talent story the mixed model's player random effect (44–62% of variance) shows is not the coach's to claim.

The market benchmark (Part 10) closes the project with its first *external* test and a fifth null of a new kind. A leakage-free walk-forward forecaster built from the validated pieces was measured against bookmakers' closing odds — the sharpest baseline that exists, and one that already prices both squad and manager — and it neither beat the line nor added information to it (incremental p = 0.31; the coach term p = 0.51, and p = 0.32 even among the low-profile managers most likely to be mispriced). The one apparent win, a 10⁻²¹ edge, was a within-season valuation leak the pre-registered prior-season check dissolved to nothing — the project catching its own hand in the till, which is what a leakage rail is for. That a near-efficient market has already discovered and priced our coaching signal is not a refutation of it; Parts 1–5 stand. It is external corroboration that the signal is real, and the ceiling on exploiting it.

The project's honest final position is narrow and well-defended: **coaching quality is real, portable, measurable, useful for forecasting a hire against a squad-value baseline, and already priced by the market; it is a single number; and this data cannot yet say what it is made of.** Knowing precisely where the evidence stops — and building the rails that told us — is the result, not a shortfall of one.
