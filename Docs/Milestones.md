# Project Milestones

**Timeline:** May 27 – August 16 (gap: June 23 – July 3)

---

## Milestone 1: Data Foundation ✓
**Completed**

Player squad data and match results are confirmed clean and queryable across cached seasons. The pipeline can be re-run without manual intervention. A source for coach-team-season assignments is identified and integrated into the data layer.

---

## Milestone 2: Core Metric ✓
**Completed**

Minutes-weighted squad value is calculated for every team-season in the dataset. A sanity check confirms the metric behaves as expected (e.g., elite clubs score higher, clubs with injured starters score lower than their raw value suggests). The data pipeline runs end-to-end: scrape → clean → metric.

---

## Milestone 3: Model Comparison ✓
**Completed: June 5, 2026**

Both models rebuilt on a points-per-game basis with league fixed effects and log-transformed, normalized squad values. Minutes-weighted squad value (`enhanced_fixed`) outperforms raw squad value (`baseline_fixed`) on every in-sample metric and in 9/10 seasons and 4/5 leagues in cross-validation. Mean out-of-sample RMSE improvement ~0.013. Combined model overfits and is dropped. Winning model: `enhanced_fixed` (R² = 0.731, RMSE = 0.238). Two documented limitations: Serie A 2018 data quality issue, and near-but-not-quite p < 0.05 significance due to small fold counts. Full analysis pipeline in `src/model_comparison.R`, reproducible via `run_milestone3()`.

---

## Milestone 4: Residual Analysis ✓
**Completed: June 9, 2026**

Residuals from `enhanced_fixed` computed for all 976 team-seasons (6 NA due to imputation edge case). Distribution is approximately normal (SD = 0.238 PPG, mean = 0) with heavy tails driven by the 2018 data quality issue. No heteroskedasticity detected — rankings equally reliable across all squad value tiers. Lag-1 temporal persistence r = 0.25: modest club effect, meaningful year-to-year variation. Full pipeline in `src/residual_analysis.R`, reproducible via `run_milestone4()`.

---

*[ Gap: June 23 – July 3 ]*

---

## Milestone 5: Coach Attribution & Rankings
**Target: ~July 25**

Residuals are linked to the coaches responsible for each team-season. Coaches with multiple teams are analyzed for consistency of residuals across different environments. A defensible ranking of coaches by performance above expectation is produced, and findings clearly support, refute, or refine the original hypothesis.

---

## Milestone 6: Coach/Player-Type Fit ✓
**Completed: July 9, 2026 (PL pilot) / July 12, 2026 (all big-5 leagues)**

Direction chosen July 6 (the "Playing Style Analysis" branch): derive player archetypes from SofaScore data and test whether coaches systematically over/underperform — per the M4/M5 residual — depending on the player types at their disposal.

Delivered: 11 face-valid player archetypes from 17,219 player-seasons across all five major leagues (38 style features, k-means within position groups; the wing-back archetype only emerged with back-3-league data); lagged minutes-weighted squad composition per coach stint, with cross-league lagging (1,475 stints, 100% joined to M5 residuals). **Headline finding, replicated from the PL pilot at 5× the data: squad archetype mix predicts performance above squad-value expectation (LRT p = 0.030; strict-lagged sensitivity p = 0.0016), led by wide-creator share (t ≈ 3.3; +10pp of minutes ≈ +2.8 points/season).** Per-coach fits are descriptive only (0/1,605 survive FDR; Gasperini + man-marking CBs, Vieira + destroyers, Pochettino − pressing forwards recur across specifications). Full pipeline: `src/player_archetypes.R`, `src/coach_fit.R`; findings in `Docs/Summary_of_Findings.md` Part 6.

Optional remaining: 2025/26 pass-coordinate validation; website refresh with big-5 fit results.

Unchosen direction (dropped for scope): **Player Development Score** — coach impact on player transfer value growth.

---

## Coach Recommender ✓
**Completed: July 13, 2026**

"Who is the best coach *for this team*?" — a scoring system combining M5 coach quality, shrunken coach × player-type fit slopes (M6 axes), and a formation-based deployed-value forecast (recency-weighted formation profiles, rigidity, archetype → slot eligibility), plus career-history plausibility filters (league/country/big-5/club level/recency/nationality) and a descriptive "coaches who thrived with squads like this" similarity layer. Pre-registered payoff validation on 785 new coach-club pairings delivered the verdict: **coach quality is a validated out-of-sample hiring signal (p = 0.016, realized framing — also closing the Part 4 limitation); fit and deployment layers pass their mechanical checks (fit → minutes t = 26.9) but do not improve hiring forecasts and ship as clearly-labeled exploratory columns.** Suggestions live on all 96 latest-season big-5 team pages. Design: `Docs/Coach_Recommender_Design.md`; pipeline: `src/coach_recommender.R`; findings: `Summary_of_Findings.md` Part 7.

---

## Team Builder ✓
**Completed: July 14, 2026**

A site page (`site/builder.html`) where the user assembles a custom XI — any of the 22 observed formations drawn on an SVG pitch, click-a-circle player picking from all 5,570 big-5 players (17k+ player-seasons, 2015/16–2024/25, cross-era teams allowed), eligibility from the recommender's validated archetype→slot matrix (Natural/Capable/Stretch tiers) — and gets the team-page coach-similarity grid computed in the browser against the built XI (verified numerically identical to the R implementation). Plausibility chips work through an optional league-context selector; builds serialize into the URL. Player headshots come from a new resumable TM scrape. Deliberately shows no predicted points for fantasy XIs (outside the M3 model's support); the similarity grid keeps its descriptive labeling. Design: `Docs/Team_Builder_Design.md`; session log: `Docs/Session_Log_2026-07-14b.md`.

---

## Squad-Fit Gap ✓
**Completed: July 15, 2026**

A per-(coach, team) diagnostic embedded as an expandable "Squad fit" panel on each big-5 team page's coach-similarity cards: which of the squad's value a candidate coach's usual formations leave idle (bench players worth more than the cheapest starter his shape fields, rolled up by player archetype) and which positions those shapes can only fill with a poor positional match. Built entirely on the recommender's validated best-XI/eligibility machinery (`cr_best_xi_assign`, `cr_squad_fit`) — no new model, and deliberately no points claim (it explains the exploratory deployment layer in € and slots). Coach-differentiating and face-valid: a back-3/wing-back coach at Man City strands €100–193m of wide-creator value, a possession coach much less. Design: `Docs/Squad_Fit_Gap_Design.md`; session log: `Docs/Session_Log_2026-07-15.md`. Team-builder version deferred.

---

## Coach Descriptive Profile ✓
**Completed: July 16, 2026**

Moves the site beyond *ranking* coaches to *characterizing* them, in three layers at deliberately different points on the honesty gradient. **Layer A (defensible):** the M4/M5 overperformance residual split into an attacking and a defensive half by re-fitting M3 with goals-for/against on the same right-hand side and attributing through the identical M5 path — full 2005–2024 span, all 14 leagues; ties back to the points residual at r = 0.862 and reveals that **the coach effect is stronger on goals than on points** (LRT χ² = 160.2 vs 28.5). An xG cut splits it again into process (creation, lag-1 r = 0.42) and outcome (shot-stopping, r = −0.005), validated across sources against the TM-built goals cut at r = 0.949/0.981. **Layer B (descriptive-clean):** a nine-axis style fingerprint over 36,018 big-5 team-matches — whose main result is that team style is mostly the *club's*: club variance beats coach variance on 7 of 9 axes and the squad's archetype mix alone explains 69% of possession, leaving only **lineup stability** and **pressing intensity** as genuinely the coach's. **Layer C (null):** every style→quality association is large and FDR-significant and *none* survives four checks — the strong axes are inseparable from club size (possession r = 0.86 with club value percentile), several restate the outcome, and lineup stability reverses sign within-coach. The third independent attempt to find a signal beyond the quality BLUP, and the third to come back empty.

Shipped to coach pages: the goals cut and the style fingerprint, each carrying its layer's label. Held back by design: the xG cut (3 seasons, nobody significant — a lens, not a verdict) and Layer C (a null; its raw correlations must never render as findings). Design: `Docs/Coach_Descriptive_Profile_Design.md`; pipeline: `src/coach_strengths.R`, `src/coach_style.R`; findings: `Summary_of_Findings.md` Part 8; session logs: `Docs/Session_Log_2026-07-16.md` (analysis), `Docs/Session_Log_2026-07-16b.md` (site).

---

## Market Benchmark ✓
**Completed: July 22, 2026**

The project's first **external** validation: a leakage-free, walk-forward match forecaster
(pre-season squad value + home + as-of coach quality BLUP, in a Dixon–Coles goal model)
tested against bookmakers' **closing odds** — the sharpest baseline that exists, already
pricing both squad and manager. New data + analysis layers (`src/source_odds.R`,
`src/market_benchmark.R`): football-data.co.uk ingest for 13 of 14 leagues (51,807 matches
2012–2024, 99.9% Pinnacle-closing), a team crosswalk verified by points reconciliation
against TM's own records (99.7% exact outside Belgium), and the M5 mixed model refit
as-of each season for leakage-free coach ratings. **Verdict: a clean, pre-registered null.**
The leakage-free forecaster is strictly worse than the closing line (log-loss 1.014 vs
0.978) and adds nothing beyond it — value p = 0.31, coach BLUP p = 0.51, and p = 0.32 even
for the low-profile managers most likely to be mispriced; a P&L backtest loses 6–10%. The
one apparent win (+0.224, p = 10⁻²¹) was within-season valuation leakage the pre-registered
prior-season check dissolved — a live demonstration of the design's dominant risk. The
market has already discovered and priced the coaching signal: external corroboration that
it is real, and the ceiling on exploiting it. The fourth on-brand "real but not
incrementally exploitable" result. Design: `Docs/Market_Benchmark_Design.md`; findings:
`Summary_of_Findings.md` Part 10; session log: `Docs/Session_Log_2026-07-22.md`. Nulls
follow project convention — writeup only, no site surface.

---

## Validation & Fan Surfaces ✓
**Completed: July 22, 2026**

Four new directions, all returning **positive** results — a rare non-null batch. Two are
independent validations of the coach quality grade on designs no earlier test used, and
two are fan-facing surfaces built from existing by-products. **(11a) Manager-change event
study:** a within-club first-difference test over 2,899 changes (2005–2024, 14 leagues,
leakage-clean via as-of BLUPs) showing the grade of *who a club hires* predicts his
performance-above-squad-value at the new club (+1.10, p=0.004; club-clustered p=0.006),
strongest for mid-season crisis hires — while the naive incoming-vs-outgoing *gap* is a
confounded null (selection × regression-to-the-mean). Its sacking-efficiency extension
finds 16.4% of mid-season sackings fire an overperformer and that doing so backfires,
surfacing Eustace-for-Rooney and Rowett-for-Zola from the residual alone. **(11b) 2025/26
forward test:** the model frozen at 2024 predicts the freshly-scraped 2025/26 holdout it
never saw — the enhanced model generalizes out-of-time (R² 0.72, still beats raw value by
0.013 PPG) and the prior coach BLUPs predict the future season's overperformance
(p=0.0024, zero leakage) — the cleanest single validation in the project, and designed to
re-run each new season. **(12) Fan surfaces:** a "deserved table" (residual as league
standings — Leicester 2015/16 deserved 10th) and a player-development leaderboard (the
clean CDE by-product; Ederson, de Jong, Vardy). With the recommender payoff (Part 7), the
grade now has three concordant validations on independent designs. Pipeline:
`src/event_study.R`, `src/forward_test.R`, `src/fan_surfaces.R`; findings:
`Summary_of_Findings.md` Parts 11–12; session log: `Docs/Session_Log_2026-07-22b.md`.

---

## Website ✓
**Completed: July 10, 2026**

Static presentation site (`site/`) covering every published result: a page per coach (2,341 — career PPG chart with club crests as clickable data points, grades/BLUPs from both ranking cuts, player-type fit), per club (496 — sortable coach history, actual-vs-expected seasons, squad value trends), and per league (14 — season selector, standings sortable by points or overperformance, diverging residual chart), plus the full writeup and a searchable leaderboard home page. Design in `Docs/Website_Design.md`, build plan in `Docs/Website_Implementation_Plan.md`. Regenerate data with `export_site_data()` (`src/site_export.R`); serve locally per `site/README.md`. Club crests scraped for all 496 clubs (`xx_data_populate_team_crests()`).
