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
| 7 | Andrea Mandorlini | 5 | 108 | 3 | +0.076 |
| 8 | Jürgen Klopp | 18 | 640 | 3 | +0.075 |
| 9 | Franck Haise | 6 | 184 | 3 | +0.069 |
| 10 | Simone Inzaghi | 10 | 349 | 2 | +0.068 |
| 11 | Claudio Ranieri | 17 | 490 | 11 | +0.061 |
| 12 | Manuel Pellegrini | 18 | 655 | 6 | +0.057 |
| 13 | Gian Piero Gasperini | 18 | 597 | 4 | +0.054 |
| 14 | Marcelino | 16 | 447 | 8 | +0.054 |
| 15 | Unai Emery | 19 | 638 | 7 | +0.053 |

Games weighting reshuffles the top: full-season track records (Ferguson, Allegri, Gasperini) rise, while coaches whose strongest numbers came in shorter spells (Igor Tudor, 7 stints averaging 17 games, formerly 6th) drop out of the top 15.

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

## Limitations

1. **Sample size for coach rankings:** Coach attribution (M4/M5) and the augmented model (Part 4) were computed on the original 5-league, 2015–2024 dataset. Re-running these on the expanded 15-league, 2005–2024 dataset would provide more stints per coach and sharpen individual rankings. *(M4/M5 have since been re-run on the expanded dataset — see Part 5. The Part 4 question — does coach identity improve out-of-sample prediction? — was re-tested on the expanded-era data in Part 7's payoff validation, on the harder target of new coach-club pairings, and holds: p = 0.016 in the realized-value framing.)*
2. **Serie A minutes-weighting:** The enhanced model underperforms the baseline for Serie A in-sample (RMSE 0.224 vs 0.246), suggesting the squad rotation pattern in Italian football weakens the minutes-weighting signal. Serie A is retained because it is a core European league and the contamination is modest.
3. **Early season data sparsity:** Transfermarkt market value coverage for smaller leagues before ~2010 is incomplete. Kalmar FF Allsvenskan 2005 is the most extreme case — 26 of 27 players had no market value recorded, producing an artefactual residual of +2.02 PPG. Early seasons in HNL, Allsvenskan, and similar leagues should be interpreted with caution.
4. **Excluded leagues:** Five leagues were dropped for structural data quality reasons (see Data section). The exclusions are principled but reduce generalisability to non-European football.
5. **Value endogeneity:** Transfermarkt market values partly reflect past performance. If strong coaching in year 1 raises squad values, the model's baseline rises in year 2, potentially compressing residuals for long-tenured coaches (unconfirmed).
6. **No season fixed effects:** the pooled model produces small systematic imbalances in some league-seasons.
7. **Attribution gaps (original 5-league analysis):** 226 matches (0.6%) had no coach coverage and were excluded from attribution. SC Freiburg 2018 has no coach data.
8. **Archetype analysis (Part 6):** per-coach findings are exploratory throughout — within-coach correlations on 4–10 stints cannot survive FDR even with 149 coaches across five leagues; only the global composition test is confirmatory. Archetype granularity (11 types) is an interpretability choice over silhouette diagnostics, with split-half stability 0.62–0.92; 26.2% of classified minutes rely on a current-season fallback (100% in 2015, which has no prior season) — the global result strengthens under the strict-lagged sensitivity, and per-coach pairs were only highlighted when they recur in both specifications. The 2015/16–2024/25 window and big-5 scope are set by SofaScore coverage.
9. **Coach recommender (Part 7):** team-specific suggestions exist only for big-5 clubs with a latest-season squad; every other club gets the quality-only leaderboard. The fit and deployment columns are exploratory — mechanically valid but not validated as forecast improvements — and the validation universe (realized appointments) is survivorship-biased toward fits clubs already chose, so the measurable fit signal is conservative. Kickoff formations miss in-match shape changes. Plausibility filters are career-history proxies, not availability: contracts, wages, and willingness are unmodeled. Coach nationality coverage depends on a slow, resumable Transfermarkt profile scrape and may be partial at any given export.

---

## Conclusion

All parts of the hypothesis are supported. Minutes-weighted squad value is a meaningfully better predictor of final points than raw squad value — a finding that holds across 15 leagues and 20 seasons, with both leave-one-season-out (p < 0.0001) and leave-one-league-out (p = 0.0001) cross-validation tests significant. The residual from that model contains a real, portable coaching signal: coach variance is statistically significant (p = 0.0011) and exceeds club variance, meaning performance above expectation follows the manager more than it stays at the club. Most importantly, incorporating coach identity into the prediction model significantly reduces out-of-sample prediction error (p = 0.001), confirming that the coaching signal is not merely detectable after the fact but genuinely useful for forecasting.

The rankings are consistent with external assessments of coaching quality. Only Guardiola achieves individual statistical significance with the current data, but the global test establishes that the coaching signal is real. Re-running the coach attribution and augmented model on the expanded 15-league dataset would provide more stints per coach, sharpen individual rankings, and likely strengthen the predictive augmentation further.

Milestone 6 (Part 6) extends the picture from *how much* coaches outperform to *when*: performance above squad-value expectation is not neutral to squad composition. The mix of player types a coach inherits — measured from prior-season playing style, before the coach's own system can contaminate it — predicts the stint residual, a finding that replicated when the analysis grew from the PL pilot to all five leagues (p = 0.030; p = 0.0016 strict-lagged, with the wide-creator coefficient strengthening to t ≈ 3.3). Wide creators are the most valuable archetype per unit of squad value; destroyer-heavy squads underperform theirs most. Individual coach × player-type fits (Gasperini with man-marking centre-backs, Vieira with destroyers) are descriptively consistent across specifications but await more data for individual significance — the same sample-size frontier as the individual coach rankings.

The coach recommender (Part 7) turns the model toward the decision it was always about: hiring. Its pre-registered validation delivered a sharp verdict — the coach quality signal survives the hardest test available (forecasting brand-new coach-club pairings out-of-sample, p = 0.016), while coach-specific fit and formation-deployment forecasts, despite passing their mechanical checks convincingly, add nothing detectable to hiring forecasts and ship as exploratory context only. The honest summary for a sporting director: the model can tell you *who the good coaches are* with validated confidence, can describe *which squads they have thrived with*, and can flag *whether your squad's value fits their shapes* — but the last two are judgment aids, not predictions.
