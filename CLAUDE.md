# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Purpose

This is an R project that tests whether a minutes-weighted squad value metric predicts a football team's final points more accurately than raw squad value. The residual from the better model is then attributed to coaching quality to produce a ranking of coaches. See `Docs/Goals_V6.md` for goals, `Docs/Hypothesis.md` for the hypothesis, `Docs/Milestones.md` for the project timeline, and `Docs/Plan.md` for the granular working plan.

## Running Code

Open `src/fbcoach.Rproj` in RStudio to set the working directory to `src/`. All file paths in the source files assume this working directory. There is no build system or test runner — files are sourced directly in RStudio.

To load the data layer:
```r
source("source_data.r")   # auto-initializes the in-memory cache
```

To populate the local cache for a set of seasons:
```r
xx_data_populate_league_seasons(2015:2024)  # scrapes all 20 leagues for given years
```

To run the analysis:
```r
source("tabler.R")
all_correlations()   # computes rank-correlations across all cached league-seasons
```

**Scraping is slow by design.** `xx_raw_team_player_info()` sleeps 3+2 seconds per team, `xx_raw_team_season_coach()` and `xx_raw_team_seasons()` sleep 2 seconds each, and `xx_raw_league_season_matches()` sleeps 2 seconds. Never remove these delays.

## Architecture

The project has three layers: the Transfermarkt data layer, the SofaScore data layer (added for Milestone 6), and the analysis layer.

### Data Layer (`src/source_data.r`)

All functions are prefixed `xx_`. There are two tiers:

- `xx_raw_*()` — scrapes directly from Transfermarkt. Always slow (has `Sys.sleep()`). Call these only when you need fresh data.
- `xx_data_*()` — checks the in-memory cache, then the RDS cache, then calls `xx_raw_*()` only if needed. These are the functions to use in analysis code.

The in-memory cache (`xx_data_cache`) is a named list initialized by `xx_init_data_cache()`, which is called automatically when the file is sourced. It is backed by RDS files in `src/data/cache/` (i.e., `data/cache/` relative to the `src/` working directory). All data reads and writes go to `src/data/` and nowhere else.

**IDs throughout the project are Transfermarkt URLs**, not opaque integers. A `league_season_id` is a full URL like `https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024`. A `team_season_id` is a team's Transfermarkt page URL for a specific season. A `player_id` is a player's Transfermarkt profile URL. This means joins between tables use URL string matching.

Twenty league constants are declared (`xx_league_id_PREMIER_LEAGUE`, `xx_league_id_PRO_LEAGUE`, etc.), but `xx_all_leagues()` returns only 14 — six were excluded for data quality reasons:

- **Argentine Liga Profesional** (`AR1N`): Transfermarkt ignores `saison_id` for this league and returns 2024 squad data for every historical season (confirmed corruption).
- **J1 League** (`JAP1`): missing match cache for 2014–2015, sparse market value data in early seasons.
- **Liga MX** (`MEX1`): captures only one tournament (Clausura) per season, not a full-season equivalent.
- **Brazilian Série A** (`BRA1`) and **MLS** (`MLS1`): minutes-weighted metric actively hurts predictions — multi-competition squad rotation (Brazil) and salary cap roster construction (MLS) break the assumption that league minutes reflect squad deployment.
- **Allsvenskan** (`SE1`): market value coverage catastrophically sparse in early seasons (23.6% of minutes valued in 2005) and never exceeds ~94% even in modern seasons — the metric is unreliable across the full time span.

The 14 active leagues are: Premier League, La Liga, Ligue 1, Serie A, Bundesliga, Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, HNL, Süper Lig, LaLiga 2. League-season URLs are constructed directly from the base constant (`paste0(league_id, "/plus/?saison_id=", year)`) and do not depend on the worldfootballR CSV.

### SofaScore Data Layer (`src/source_sofascore.r`, `src/sofascore_crosswalk.r`)

Added for the Milestone 6 coach/player-type fit analysis. Functions use the `ss_` prefix with the same two tiers as `source_data.r`: `ss_raw_*` scrapes, `ss_data_*` reads the RDS cache first. Caches live in `data/cache/sofascore/`, one file per SofaScore season id (the PL 2015/16–2024/25 ids are in `ss_pl_season_ids`; all big-5 league ids are in `ss_big5_leagues`).

**SofaScore rejects plain HTTP clients by TLS fingerprint** (R httr/curl get HTTP 403 regardless of headers), so every request goes through headless Chrome via `{chromote}` — Chrome must be installed. **Politeness is mandatory:** 2–3s jittered sleep per request (lowered from the pilot's 4–7s on 2026-07-09 for the big-5 expansion; steady 2–3.5s was never punished in testing), 90s rest every 250 requests, 10-minute backoff on 403/429, abort after 3 consecutive failures with progress saved (fully resumable). A one-off ~70-request burst once earned a ~24-hour IP block; steady pacing has never been blocked. Never remove these delays; if a run starts hitting 403s, raise the pacing back to 4–7s before resuming. Only HTTP 404 is recorded as permanently missing; other failures are retried on the next populate run.

SofaScore ids are opaque integers, not URLs — columns holding them are suffixed `_ss_id`. `ss_build_crosswalk(season_ss_id, league_season_id)` in `sofascore_crosswalk.r` links SofaScore player ids to Transfermarkt `player_id` URLs (99.2–100% matched on the pilot; unmatched rows are youth players absent from TM squad pages).

Data coverage limits (verified): per-match player statistics, formations, and shot coordinates go back to 2015/16; **xG exists from mid-2021/22** (complete from 2022/23); per-pass/dribble coordinate charts (`ss_raw_player_event_breakdown()`, the `rating-breakdown` endpoint) exist **only from 2025/26** and are not part of the pilot dataset.

To run or resume a scrape (idempotent, resumes wherever it stopped):
```r
source("source_sofascore.r")
ss_data_populate_pl_pilot()   # PL only (complete)
ss_data_populate_big5()       # all big-5 leagues 2015/16-2024/25 (complete 2026-07-12)
```

Big-5 coverage notes (verified 2026-07-12): all 50 league-seasons complete. Events include relegation playoffs where a league has them (Bundesliga 308 = 306 + 2 playoff matches); Ligue 1 2019/20 has only 279 matches (COVID abandonment). Shotmaps have a permanent SofaScore coverage hole clustered in 2018/19 (~20–31 missing matches per league outside the PL, recorded as 404).

### Analysis Layer (`src/tabler.R`)

Builds on the data layer to produce per-team metrics and model comparisons:

- `league_season_team_chart(league_season_id)` — returns a table of all teams in a league-season with `total_team_value` (raw squad value), `weighted_team_value` (minutes-weighted), ranks for each, and actual `total_points`.
- `league_season_correlations(league_season_id)` — returns Pearson rank-correlations of both metrics against points rank. **This function is the current target of Milestone 3:** it will be replaced with a points-based regression comparison (see `Docs/Plan.md`).
- `all_correlations()` — iterates over all leagues × seasons and aggregates correlation results.

The `weighted_team_value` formula: for each player, `player_market_value_euro × percent_minutes_played`, summed per team. When a team has no minutes data (weighted value = 0), the value is imputed from a within-season regression against `total_team_value`.

Later milestones build on this in a source chain — `coach_attribution.R` → `residual_analysis.R` → `model_comparison.R` → `tabler.R` (with `source_data.r` sourced manually first): `model_comparison.R` (M3, `run_milestone3()`), `residual_analysis.R` (M4, `run_milestone4()`), `coach_attribution.R` (M5, `run_milestone5()`), `augmented_model.R` (coach BLUP CV). All of M5 weights stints by `n_games` (since 2026-07-14): short caretaker stints carry far noisier per-game residuals, and games-weighted BLUPs predicted held-out stints better than unweighted ones. This covers the mixed model, the per-coach mean residuals, and the significance t-tests (which require ≥ 3 stints — df = 1 SEs can collapse when two stints agree by luck). The mixed model's residual variance component is therefore per-game — the recommender's posterior-SD constants in `cr_build_scorer()` must be refreshed whenever M5 is refit. Separately, `save_coach_grades()` applies a **display certification bar** (≥ 109 career games in the cut, or FDR-significant): sub-bar coaches keep their BLUP and stay in the mixed model but get no grade, no leaderboard slot, and no recommender-pool entry (the pool in `cr_score_team()` filters to graded coaches). The bar is presentational — every score-side penalty for thin/selection-flattered records (weight floors, truncation-share and gap penalties) tested worse out-of-sample, so the ranking math must not be "corrected" for it.

### Coach Strengths Layer (`src/coach_strengths.R`)

Layer A of the coach descriptive profile (design: `Docs/Coach_Descriptive_Profile_Design.md`;
phase 1 shipped 2026-07-16; **the goals cut is on coach pages** since phase 6 —
the xG cut is writeup-only, see below). `cs_` prefix, pure
cache-reader. Splits the M4/M5 overperformance residual into an attacking and a defensive
half by re-fitting the M3 model with goals-for-per-game / goals-against-per-game as the
response on the **same right-hand side**, then attributing to coach stints through the M5
path. Goals-based, so it covers the full 2005–2024 span and all 14 leagues (no SofaScore
dependency). `run_coach_strengths("top5" | "14league")` runs everything and writes
`data/results/coach_strengths_<cut>.rds` (per coach: `off_blup`, `def_blup`, `tilt` =
off − def, `edge` = off + def, plus games-weighted means + FDR significance) and
`coach_goal_residuals_<cut>.rds` (the stint table). Re-run after any M4/M5 refit.

Because `cs_fit_head_blups()` / `cs_head_stats()` reuse `fit_mixed_model()`,
`compute_coach_stats()`, and `add_significance()` verbatim (by renaming the head residual
to the column those functions expect), the games weighting, BLUP shrinkage and ≥3-stint FDR
rule are the M5 ones by construction — don't fork them. `xx_filter_value_coverage()` in
`coach_attribution.R` is the shared coverage filter for the same reason. **Honesty label
(design §0): defensible** — it re-slices a residual the project already trusts and makes no
new attribution leap, so an offence/defence tilt can be stated plainly (unlike the fit and
style layers). The 14-league offence fit emits an lme4 `max|grad|` convergence warning that
is a verified false positive (bobyqa reaches the identical optimum) — do not switch
optimizers to silence it.

**The xG cut** (phase 2, same file, shipped 2026-07-16): `run_coach_xg_strengths()` splits
the goals cut into process and outcome — `creation` (xG-for above value expectation) and
`prevention` (head-modelled) vs `finishing` (goals − xG) and `shotstop` (xG-against −
goals-against, within-team). Writes `coach_xg_strengths.rds` + `coach_xg_residuals.rds`
(no cut suffix — xG is big-5 only). Reads SofaScore shots and joins through
`cf_season_match_coaches()`. Facts that will bite if forgotten, all verified 2026-07-16:

- **xG era = 2022–2024 only** (`cs_xg_seasons`). 2021/22 is ~40% covered, not "partial but
  usable", and is excluded; nothing before has xG.
- **An event counts only if its shotmap reconciles with the scoreline on both sides.** 27 of
  5,330 xG-era events (0.5%, all 2023) carry ~21 shots but are missing their goal shots —
  including them understates creation and inflates finishing. A reconciliation check that
  conditions on events *having* goal shots will not catch this.
- `shots` carries its own `is_home`, so the shooting team comes from the event's home/away
  ids — the `match_stats$team_ss_id` caveat does not apply. **Own goals** sit in the shotmap
  credited to the *benefiting* side, named for the defender, with no xG; they land in
  finishing by construction, which is correct.
- **3 seasons is a hard ceiling:** 452 stints, 57 coaches with ≥3 stints, none with ≥5,
  **zero FDR-significant**. Never present this layer as a career verdict; it is a recent-form
  lens over the big 5 and needs a games bar for any ranking.
- Repeatability (lag-1, same club): creation 0.42, prevention 0.27, finishing 0.24,
  shot-stopping −0.005. Finishing persists more than the design assumed (squad continuity,
  not coach skill) — keep labelling it an unreliable coach signal.
- Cross-source tie-back (SofaScore xG vs TM goals cut): r = 0.949 / 0.981 over 452 stints.
  This is the check that breaks first if the SofaScore→TM team map or attribution regresses.

### Coach Style Layer (`src/coach_style.R`)

Layers B and C of the coach descriptive profile (design: `Docs/Coach_Descriptive_Profile_Design.md`;
phases 3–5 shipped 2026-07-16; **Layer B is on coach pages** since phase 6, Layer C
deliberately is not). `sy_` prefix, pure
cache-reader. Sources `coach_recommender.R` (not `coach_fit.R` directly) for `cr_rigidity()`
/ `cr_build_coach_formations()`, which Layer C needs. The M6 archetype recipe pointed at
*team style* instead of player type:
per-player-per-match → team-match → z-score within league × season → coach-stint mean →
games-weighted coach profile. `run_coach_style()` writes `data/results/coach_style.rds`
(`$profiles`, `$stints`, `$axes`, `$meta`). Big-5 only, 2015/16–2024/25 — coaches seen only
outside the big 5 get Layer A but **no fingerprint; don't fabricate a radar**.

Nine axes, each an **equal-weight mean of its members' z-scores** (not a PCA, not a fitted
weighting — nothing is trained against an outcome here, so there's nothing to overfit):
possession, pressing intensity, directness, width, shot volume, chance quality, defensive
solidity, set-piece reliance, lineup stability. **Honesty label (design §0):
descriptive-clean** — it is literally what the team did, with no causal content — but it is
the *team's* style, co-produced with the squad (design §5); never "X is a possession coach"
in the abstract.

**Phase 4 (`run_coach_vs_squad()` → `coach_style_vs_squad.rds`) is binding on how this may
be presented.** Team style is mostly the **club's**, not the coach's: club variance exceeds
coach variance on **7 of 9 axes** (possession 69% club vs 12% coach), the squad's archetype
mix alone explains 69% of possession / 54% of shot volume / 51% of directness, and a club
under two *different* coaches (possession r = 0.82) looks more alike than a coach at two
*different* clubs (r = 0.55). **A radar must be labelled as the style of the teams this coach
ran — never "his style".** Only two axes survive as genuinely the coach's: **lineup
stability** (coach 19.2% > club 14.6%, the only axis that travels better than it persists,
10% personnel-explained, survives residualization) and **pressing intensity** (coach 30.9% >
club 23.6%, 12% personnel-explained). Everything else collapses once the squad's archetype
mix is removed (possession travel 0.55 → 0.17). Method caveat that cuts against the headline:
the travel-vs-persist pair is not like-for-like (consecutive coaches at a club inherit the
same squad), so the variance decomposition carries the verdict — it agrees on 7 of 9.
**Display note:** axis units are SDs of team-matches, so coach means compress toward 0
(Simeone's 92nd-pct solidity is only +0.28 SD) — map to percentile among coaches, not raw SD.

**Layer C (`run_style_quality()` → `coach_style_quality_top5.rds`, phase 5, shipped
2026-07-16) is a NULL, and that is binding.** It regresses the M5 quality BLUP on the
nine axes + `cr_rigidity` across 231 coaches (games-weighted). Every raw association is
large and FDR-significant — defensive solidity +0.64, possession +0.52, lineup stability
−0.37 — and **not one survives**. Four checks, each killing a different group: consistency
across 4 specs (kills pressing, directness, width, set-pieces); separability from club
size (kills possession — **r = 0.86 with the coach's mean club value percentile** — shot
volume, solidity); outcome restatement (kills chance quality; solidity is built from shots
conceded); and **within- vs between-coach** (kills lineup stability, which *reverses sign*:
−0.37 between coaches but **+0.13 within** a coach and +0.11 within a club — the between
version is club sorting, the big rotators being Heynckes/Tuchel/Allegri at European-fixture
clubs). Only rigidity is unkilled, and only because a career constant has no within-coach
variation to test — recorded as "between-coach only; untestable", not as a pass. Traps to
not re-walk: the all-axes multivariable is a **suppression trap** (`club_pct` flips from
r = +0.39 bivariate to β = −0.60 partial, reading as "big clubs underperform"; the tell is
possession's β *rising* under a club control, 0.517 → 0.568), so one axis + one control is
the only interpretable spec; and `r(club_pct, blup) = +0.39` means Layer C's style axes
cannot be told apart from club size. **Do not ship a style→quality story or "re-examine"
these correlations without redoing all four checks.** glmnet is not installed;
`sy_ridge_cv()` is a dependency-free weighted ridge used as a stability check only.

For the **ranking** (as opposed to Layer C), the `club_pct ↔ BLUP` correlation was tested
directly and resolved (2026-07-21, `Docs/Session_Log_2026-07-21.md`; writeup Part 8): it is
**benign selection, not value-model mis-specification.** The within-coach club-size slope is
**negative** (−0.00085, t = −5.0; coach-FE cross-check p = 1e-7) — the wrong sign for
mis-specification (which needs the *same* coach to overperform more at a bigger club), so the
grades are a valid coach effect. The BLUPs are robust to a curvature-corrected (spline) value
term (rank r = 0.98, Guardiola still #1); the confound shrinks only 0.21 → 0.16. The one real
residual is a small, OOS-validated (LOSO 2.55%, p = 0.0017) linear-in-log under-prediction of
the single biggest club per league, inflating permanent-elite coaches' grades ~0.02–0.04 PPG
without reordering. Adopting the spline was declined (document-only) — it re-plumbs M4→M5→
strengths→style→recommender→grades→site for a ~0.005 PPG average BLUP move. This resolves
the "most load-bearing untested claim" flagged in the 2026-07-16b log; do not re-open it as
untested.

Field-availability facts, verified 2026-07-16 — the two caches disagree and the docs
are easy to misread:

- **CLAUDE.md's "`outfielderBlocks`/`ballRecovery` only from 2023/24" is true of the SEASON
  cache (`stats_<sid>.rds`) only.** In `match_stats` `ballRecovery` is populated in all 50
  league-seasons, so this layer uses it. The design's inherited "do not use" doesn't apply.
- **The reverse trap: `possessionWonAttThird` is absent from `match_stats` entirely** (season
  cache only). So pressing *height* cannot be attributed to a stint — the per-match axis is
  pressing **intensity** (a PPDA proxy), and `pressing_height` ships as a season-level
  secondary descriptor with a `height_blended` flag wherever the team-season had >1 coach.
- `match_stats$team_ss_id` matches the real match side only **41.5%** of the time — always
  derive the side from `is_home` + the event's home/away ids. `substitute == FALSE` gives the
  starting XI exactly (11 per side).
- Counting conventions drift over the decade (ballRecovery 5.0 → 3.8 per player-match,
  interceptions 2.2 → 1.5). Z-scoring within league × season absorbs it — that's why the
  design insists on it, so don't z-score across seasons.
- Shot coordinates: attacked goal at (0, 50), and x/y are both 0–100 but span different
  physical distances — scale to metres (×1.05, ×0.68) before computing shot distance.

### Coach Value Growth Layer (`src/coach_value_growth.R`)

The Coach Development Effect (CDE): a second, euro-denominated outcome axis —
*do players appreciate in market value faster than their own trajectory predicts
under a coach?* (design: `Docs/Coach_Value_Growth_Design.md`; built 2026-07-21).
`cvg_` prefix, pure cache-reader, sources `coach_attribution.R` (for
`build_model_dataset()` + the M5 spine). Mirrors M3→M4→M5: a baseline
expectation model on log value growth `g = log(value_{t+1}/value_t)` for same-club
consecutive-season valued pairs (confounders only — splined age×position, splined
starting value, prior momentum, league/season FE; every mediator left in the
residual), attributed to coaches through the M5 games-split spine, then a mixed
model with **player + club + coach** random effects. `cvg_run_all("top5" |
"14league")` runs Phases 1–4 + validation; writes `player_dev_residuals_<cut>.rds`
(the clean *player*-development residual — the one keepable by-product),
`coach_value_growth_<cut>.rds`, `cde_coach_stints_<cut>.rds`.

**Binding verdict: this is an exploratory NULL (#4, after M6 fit, recommender
fit/deployment, Layer C) and appears NOWHERE on the site.** It *passes* the
reflection test (93–96% of CDE variance orthogonal to the points BLUP, so it is
not points re-expressed) but **fails repeatability out-of-sample** — even/odd
season split-half r = −0.07 (top5) / +0.05 (14-league), indistinguishable from
zero — so the coach-level effect is not a stable trait. The player RE dominates
the variance (44–62%): the metric measures *which players happened to blow up on
a coach's watch*, which is luck. Stable to adding movers (Spearman 0.89–0.94), so
the null itself is robust. Facts that will bite if forgotten: the value snapshot
is a single **season-level** number (89% of mid-season movers carry an identical
value on both clubs' pages — verified), which is why a games-split attribution,
not a within-season stamp, is correct; `log(value_t)` is **splined** (a change
from design §3.2a — the linear term left a "coaches of cheap squads" U-shape);
minutes weighting uses `pct_minutes` (league-normalised), never raw
`minutes_played` (mixes competitions). The transfer-fee external tie-back (§7) and
the contract-length confound (§5.8) are documented open gaps, deliberately not
closed — pointless for a metric that fails repeatability. **Do not re-open CDE as
a coach ranking without a new outcome or a repeatability pass; the writeup Part 9
carries it as a null.**

Follow-up exploration (2026-07-21, `cvg_explore()`; exploratory, no site output):
slicing does not rescue the coach signal — it stays null in every age band,
position, and SofaScore archetype (young ≤21 slightly negative). A clean
descriptive by-product: attacking/creative archetypes over-appreciate beyond the
age/price/position baseline (wide creator +0.07, deep playmaker/box striker ≈
+0.04, defensive fullback −0.02), corroborating M6 from the value-growth side. The
one real coach-independent signal is **club consistency across managers, and only
in selling leagues** — consecutive-regime r ≈ +0.10 (p = 2e-4) driven entirely by
non-big-5 clubs (Eredivisie/Portugal/Championship pipelines; big-5 regime r =
+0.005). **METHOD TRAP:** the naive club cross-coach test gives a spurious +0.40
because a mid-season-change player-season is shared between two managers (30% of
seasons split) — always collapse to the primary coach (`cvg_primary_coach()`)
first. The club signal needs the 14-league sample; top5-only is underpowered.

### M6 Archetype Layer (`src/player_archetypes.R`, `src/coach_fit.R`)

The Milestone 6 coach/player-type fit analysis. Pure cache-readers (no scraping, no chromote):

- `player_archetypes.R` (`pa_` prefix) — per-player-season style features from the SofaScore caches (all big-5 leagues) and k-means archetype clustering within D/M/F position groups (11 archetypes, labels in `pa_archetype_labels` — big-5 semantics as of 2026-07-12, incl. the wing-back archetype). `run_archetypes()` rebuilds `data/cache/sofascore/archetypes.rds`. Features are style-only (no goals/ratings/xG) and z-scored within league × season × position group.
- `coach_fit.R` (`cf_` prefix) — lagged archetype assignment (cross-league; current-season fallback for players new to the big-5, flagged), minutes-weighted archetype shares per coach stint, join to M5 partial residuals, global mixed model + per-coach tests + strict-lagged sensitivity. `cf_run_analysis()` runs everything; sources `coach_attribution.R`, `player_archetypes.R`, `sofascore_crosswalk.r`. It also owns the SofaScore↔TM↔coach join spine used by the layers above it: `cf_season_match_minutes()` and `cf_season_match_coaches()` (the latter lived in `coach_recommender.R` as `cr_season_match_coaches` until 2026-07-16) — both carry the relegation-playoff filter and the greedy one-to-one team map.

Data conventions that will bite if forgotten: SofaScore **shot coordinates put the attacked goal at (0, 50)** (heatmaps attack toward x = 100); **`match_stats$team_ss_id` is the player's club at scrape time, not the match team** — derive the match side from `is_home` + the event's home/away ids; season stat fields `outfielderBlocks`/`ballRecovery` exist only from 2023/24 and must not be used as features; **one SofaScore team id can carry several name spellings within a season** and league events include relegation playoffs against lower-division clubs — team mapping goes through `ss_crosswalk_team_map()` (greedy one-to-one), never plain best-overlap.

### Coach Recommender (`src/coach_recommender.R`)

Answers "who is the best coach for this team?" (design: `Docs/Coach_Recommender_Design.md`). `cr_` prefix, pure cache/results reader, sources the `coach_fit.R` chain. Key pieces: hand-mapped slots for all 22 observed formation strings (`cr_formation_slots`); recency-weighted coach formation profiles (δ = 0.3, chosen out-of-sample) + rigidity; archetype → slot eligibility matrix with TM-position fallback and a greedy+swaps max-value XI (`cr_best_xi_value`); random-slope fit model on three composition axes (creators / spine / wing-back — NOT significant, LRT p = 0.449, kept under shrinkage); `cr_score_team()` decomposes uplift into quality / fit / deployment; `cr_payoff_validation()` is the pre-registered LOSO test.

**Squad-fit gap diagnostic** (`cr_squad_fit`, design: `Docs/Squad_Fit_Gap_Design.md`, added 2026-07-15): per (coach, team), which of the squad's value the coach's usual shapes leave idle (bench players worth more than the cheapest starter they field **and startable by at least one of the 22 shapes** — `cr_startable_players()`, see below — rolled up by archetype) and which positions can only be filled by a stretch player — explains the deployment layer in € and slots, **never in points** (inherits its exploratory label). `cr_best_xi_value` was refactored to wrap `cr_best_xi_assign` (returns the XI + bench, not just the total). Ships in `recommender.rds` per team keyed by coach, rendered in a **right-side pop-up drawer** opened by clicking a team-page similarity card (`se_squad_fit` in `site_export.R`, `team.js`; drawer is a full-height overlay above the sticky header, closes on Escape/backdrop/×, and normal click opens it while ctrl/⌘/middle-click still follows the card link to the coach profile). The computed `gap_pct`/`gap_eur` scalar is deliberately **not displayed** (QA showed it mis-orders the value-max anchor and doesn't reconcile with the strand list — see design §3.5); the panel leads with the coherent strand/gap lists.

**The strand's `startable` filter is load-bearing (design §3.3a, added 2026-07-16).** The max-value XI is near formation-invariant (any two of the 22 shapes share 8–10 of 10 outfield starters; on Man City 24 of 36 players start in *no* shape), and `rep_w` sums to 1 — so a player benched in every shape contributes his **full value identically to every coach**. That put a flat "destroyer €40m" on all 81 Man City coaches and made 88.9% of a team's coaches share the same top strand label. `cr_startable_players(squad)` (players making the best XI in **≥1 of the 22 shapes**, computed once per team in `cr_save_results` and passed in) restricts the strand to players some shape would field; top-label agreement fell to 77.8%. **Never narrow that quantifier to the coach's own repertoire** — a player Guardiola benches but Allegri starts *is* stranded by Guardiola, and that contrast is the whole coach-specific signal. Residual ~78% sameness is real (the same expensive attackers genuinely sit outside most shapes) — it is a partial fix, not a solved problem. On squads near the €5m `strand_floor` the strand can now empty entirely (Venezia: 70 of 81 drawers), which is correct — the old numbers there were all depth players — and `team.js` already degrades to a "Natural fits across the pitch…" line. The drawer also carries a **descriptive coach dossier** (added 2026-07-16): `cr_coach_dossier(scorer, coach_ids)` ships per-coach preferred formations (top recency-weighted shapes from `scorer$profiles`), rigidity, career span (first/last season, total games, stints), and clubs coached (14-league history, most recent first) in `recommender.rds$dossier` — restricted to the 81-coach similarity pool to stay lean; `se_coach_dossier()` formats it onto each similar-coach entry as `career`, rendered above the squad-fit section (stat tiles, formation meter bars, club chips). The **coach page** also shows a "Preferred formations" card (`se_coach_formations()` → `coach.js renderFormations`, added 2026-07-16) reading the same dossier — top-5 recency-weighted shapes as meter bars + a rigidity descriptor; only the ~81 pool coaches have it, others omit the card. `cr_coach_dossier` stores 5 formations (the drawer slices to 3).

**Payoff verdict (2026-07-13, binding on what the site presents):** only the quality BLUP is validated out-of-sample on new coach-club pairings (p = 0.016 realized framing); fit + deployment are exploratory and must always be labeled as such. `cr_save_results(scorer, payoff_folds)` writes `data/results/recommender.rds` (per-team suggestions for latest-season big-5 squads + career facts + meta + the `builder` component: the 81-coach similarity-profile pool and the model constants the team-builder page needs — formation slots, eligibility matrices, archetype labels) for the site exporter. Career facts feed the plausibility filter chips; coach nationality comes from `xx_data_populate_coach_nationalities()` in `source_data.r` (resumable TM profile scrape, priority-ordered to ranked coaches; TM intermittently 502s this page type — the populate backs off and can be re-run).

### Market Benchmark Layer (`src/source_odds.R`, `src/market_benchmark.R`)

The project's first **external** validation (design: `Docs/Market_Benchmark_Design.md`;
built 2026-07-22, session log `Docs/Session_Log_2026-07-22.md`; writeup Part 10). A
leakage-free walk-forward match forecaster tested against bookmaker **closing odds**.

- **`source_odds.R`** (`od_` prefix, two tiers like `source_data.r`) — ingests
  football-data.co.uk CSVs to `data/cache/odds/`, builds a verified team-name → TM
  crosswalk, and emits a matches table joined to TM `team_season_id`s with de-margined
  closing probs. 13 of 14 site leagues (11 in the main `mmz4281/<SSSS>/<div>.csv` files —
  E0→GB1, E1→GB2, SP1→ES1, SP2→ES2, I1→IT1, D1→L1, F1→FR1, P1→PO1, N1→NL1, B1→BE1, T1→TR1;
  Denmark/Poland are `new/`-format combined files, **not yet wired**; Croatia absent).
  `od_data_populate(2012:2024)` caches ~143 CSVs (idempotent). Odds coalesce Pinnacle
  closing (PSC) → Pinnacle (PS) → Bet365 closing → Bet365; **PSCH/D/A is present in every
  2012–2024 file** — 51,807 matches, 99.9% Pinnacle-closing.
- **The crosswalk is load-bearing and verified by reconciliation, not name score.**
  football-data uses stable abbreviations ("Ath Madrid", "Sp Lisbon"), so `od_build_matches`
  maps names by a **within-season greedy one-to-one assignment** (the ~20 clubs are a
  bijection — even a mediocre scorer resolves under the constraint) built **per season**,
  NOT the cross-season stable map (which collides two fd names onto one verein — it doubled
  RAEC Mons 2012 to 60 games). `od_reconcile()` checks fd-derived season points against
  `matches.rds`: **99.7% exact outside Belgium (100% for D1/E0/E1/N1/P1/SP1/T1)**; every
  miss is a fixture-count difference (Belgian Jupiler playoffs fd carries and TM doesn't;
  fd missing ~2 Portugal fixtures some seasons), never a misidentification. `od_name_overrides`
  is empty — the bijection needed none. Verein ids and season are extracted from
  `team_season_id` by string split (`od_verein_id`), avoiding regex backreferences.
- **`market_benchmark.R`** (`mb_` prefix) — `mb_prepare()` (cached `mb_prep.rds`: the M3
  dataset + model-independent coach-stint actuals); `mb_asof_blups(cutoff)` refits the full
  M5 mixed model on completed seasons **strictly before cutoff** (leakage-free — prior
  seasons are done), one table per cutoff 2012–2024, cached `mb_asof_blups.rds`; a
  Dixon–Coles bivariate-Poisson goal model (`mb_fit_dc` joint MLE, or the ~50×-faster
  `mb_fit_dc_glm` stacked-Poisson GLM + 1-D rho, **numerically identical** — use the GLM);
  `mb_walkforward` (expanding-window per test season); `mb_evaluate` (McFadden conditional
  logit `mb_condlogit` of result on market prob + model signal, plus log-loss/Brier);
  `mb_pnl` (§4.4 backtest — bootstrap CI, favourite/longshot buckets, achievable-price
  haircut). `mb_run(value_mode="prior")` writes `data/results/market_benchmark.rds`.
- **Leakage is the whole game (design §3.2), and the audit is the headline.** The strength
  input must be a **pre-season** value: `value_mode="prior"` (the club's prior-season
  `total_team_value`, current-season fallback for promoted) is the primary; **never the
  minutes-weighted value** (embeds realized minutes). `value_mode="current"` is kept ONLY
  as the leakage demo: it showed a spurious incremental **+0.224, p = 10⁻²¹** beyond the
  market that **collapsed to +0.023, p = 0.31** under prior-season value — TM's season
  valuation has absorbed in-season results. Do not present the current-value numbers (incl.
  its favourite-side P&L edge) as real.
- **Verdict — a clean null (binding).** Leakage-free: the forecaster is strictly worse than
  the closing line (log-loss 1.014 vs 0.978, market better in all 11 leagues) and adds
  nothing beyond it — value p = 0.31, **coach BLUP p = 0.51**, and p = 0.32 even in the
  pre-declared low-profile-manager subgroup; P&L −6.4% ROI at closing (CI excludes 0),
  −9.9% at achievable prices. The market already prices both squad value and coaching
  quality. **The coach term would not stably fit *inside* the DC goal model** (collinear
  with value, sign-flipping, b ∈ ~[0,1.2]) — so the forecaster is value+home and the coach
  is tested as a separate incremental signal, not as forecast skill. **No site surface** —
  a null lives in the writeup (Part 10), like the CDE (Part 9) and Layer C.

### Validation & Fan-Surface Layer (`src/event_study.R`, `src/forward_test.R`, `src/fan_surfaces.R`)

Built 2026-07-22 (session log `Docs/Session_Log_2026-07-22b.md`; writeup Parts 11–12).
Three pure cache/results readers; the first two are **positive** validations of the coach
grade, the third ships fan surfaces. Unlike Parts 6–10 these are not nulls.

- **`event_study.R`** (`es_`) — manager-change **event study**: a within-club
  first-difference test that the grade of *who a club hires* predicts his
  performance-above-squad-value at the new club. Reads `mb_prep.rds` (stints) +
  `mb_asof_blups.rds` (leakage-free as-of BLUPs; `es_load()` extends the cached
  2012–2024 set back to 2008 via `mb_asof_blups()` and re-saves). **Leakage rule: as-of
  cutoff = the outgoing coach's season**, which uniformly excludes both the before-
  (`resid_out`) and after- (`resid_in`) residuals from both grades. **The validated
  headline is the LEVEL spec** `resid_in ~ blup_in + resid_out` (+1.10, p=0.004;
  club-clustered mixed +0.91, p=0.006; strongest for mid-season hires p=0.003). **The
  DIFFERENCE spec** `dperf ~ dgrade` is a **confounded null** (selection × RTM: clubs
  fire a well-graded coach during an unlucky dip that reverts) — reported only to explain
  the divergence; do not present it as the finding. Full sample (unproven coach → BLUP 0)
  is primary; the both-graded subset (n=610) is an underpowered robustness check.
  `es_sacking_efficiency()`: 16.4% of mid-season sackings fired an overperformer;
  firing the overperformer backfires (replacement dperf −0.16 vs +0.35 after a
  defensible sacking) — surfaces Eustace-for-Rooney, Rowett-for-Zola from the residual.
  `run_event_study()` → `event_study.rds`.
- **`forward_test.R`** (`ft_`) — the **2025/26 forward test**: model frozen at 2024
  (M3 coefficients + M5 BLUPs on ≤2024), predict the freshly-scraped 2025/26 holdout it
  never saw. **Requires `xx_data_populate_league_seasons(2025)` first** (14 leagues, 252
  teams; game counts match the 2023 reference per league). Reads `mb_prep.rds` (train) +
  `ds_2025.rds` (holdout, built once by `build_model_dataset(2025)`). **Q1**: enhanced
  model generalizes out-of-time (R² 0.72, still beats raw value by 0.013 PPG) — an
  out-of-time test of the model *structure* (uses realized minutes; the pre-season
  forecast is Part 10, not this). **Q2**: prior coach BLUPs predict 2025 overperformance
  (`partial_residual ~ prior_blup` +1.90, p=0.0024; graded-only p=0.0036) — a true future
  holdout, zero leakage, the cleanest single validation of the coaching signal.
  `run_forward_test()` → `forward_test.rds`. This test is designed to **re-run each new
  season** as a rolling scorecard (re-scrape the year, re-run).
- **`fan_surfaces.R`** (`fs_`) — **deserved table** (`fs_deserved_table()`: expected
  standings from the enhanced model vs actual, per league-season; over/under = the M4/M5
  residual as a table) and **player-development leaderboard** (`fs_dev_leaderboard()`:
  ranks `dev_resid` from `player_dev_residuals_*.rds`, the clean Part-9 by-product; it
  describes **players not coaches** — never draw a coach ranking from it). **`pct_minutes`
  in the player-dev cache is share-of-team-minutes (max ~0.092), NOT a 0–1 season share —
  threshold on raw `minutes_played`.** `run_fan_surfaces()` → `fan_surfaces.rds`.

Three concordant validations of the coach grade now exist on independent designs: the
recommender payoff (Part 7, p=0.016), the event study (Part 11a, p=0.004), and the forward
test (Part 11b, p=0.0024). Re-run all three savers after any M4/M5 refit before exporting.

### Website Layer (`src/site_export.R`, `site/`)

A static presentation site lives in `site/` at the repo root — the one place the R code writes outside `src/data/` (it is a publishing target, not analysis data). Design: `Docs/Website_Design.md`; build plan: `Docs/Website_Implementation_Plan.md`.

- `export_site_data()` (`se_` prefix, working dir `src/`) regenerates everything under `site/data/` (per-coach/team/league JSON keyed by TM numeric ids, leaderboard, search index, meta), `site/assets/` (coach images + club crests copied from `data/images/`), and `site/writeup.html` (converted via `{commonmark}` from **`Docs/How_It_Works.md`** — the plain-language guide, since 2026-07-23; it was `Docs/Summary_of_Findings.md` before that). It wipes and rebuilds those paths; never edit them by hand. Hand-written files (`*.html` except writeup, `css/`, `js/`, `img/`) are never touched.
- **The logo lives in `site/img/logo.svg`, deliberately not `site/assets/`** (which is wiped on every export). It is the "Residual S" mark — two tapered wedges, the lower one the upper rotated 180°, filled with the two masthead-gradient stops. That file is the **favicon** (linked from every page's `<head>`, including the writeup template in `se_write_writeup()`). On-page uses are **inline SVG instead**, via `logoMark(size)` in `components.js` (header lockup at 18px, home hero at 46px): an external `<img>` cannot read `--series-1`/`--series-2`, so it would not track the light/dark theme the way the mark it replaced did.
- **`Summary_of_Findings.md` therefore has no published surface.** The convention "a null lives in the writeup, not on the site" (xG cut, Layer C, CDE Part 9, market benchmark Part 10) now means *documented in the repo*, not *reachable by a reader* — the site's honesty gradient survives in `How_It_Works.md` ("How much to trust each number", "What the model does not do"), the statistics do not. Site copy links to `writeup.html` as "how it works" with **no part anchors**; do not add deep links to writeup parts unless the technical document is republished as its own page. `Docs/Website_Design.md` still describes the writeup page as-designed (a `Summary_of_Findings` rendering) and is stale on this point.
- Export inputs: `data/results/*.rds` — including `coach_grades_*.rds` (written by `save_coach_grades()` in `coach_attribution.R`), `archetype_fit.rds` (written by `cf_save_results()` in `coach_fit.R`), `coach_strengths_{top5,14league}.rds` + `coach_style.rds` (the descriptive profile, below), and `recommender.rds` (written by `cr_save_results()` in `coach_recommender.R` — feeds the team-page "Suggested coaches" section; teams without an entry get a note card). Re-run those savers after re-running M5/M6/recommender before exporting.
- **Descriptive profile on coach pages** (phase 6, shipped 2026-07-16, design `Docs/Coach_Descriptive_Profile_Design.md` §6): two cards, both **gated by the honesty label of their layer, not by what the data allows**:
  - "Where his edge comes from" (`se_coach_strengths()` → `coach.js renderStrengths` → `charts.js strengthBars`) — the Layer A goals cut. Read from the **same cut as the headline grade** and shown **only for graded coaches** (545): it re-slices the BLUP, so it inherits the grade's display certification bar rather than inventing its own. `STRENGTH_DOMAIN` (±0.26 goals/game) is a **fixed** x domain shared by both rows and every coach — defence bars are visibly shorter than attack for nearly everyone because the coach effect really is stronger on goals scored (LRT χ² = 160 vs 60); do not give the rows separate axes to "fix" it. `edgeNote()` fires when the goal edge and the BLUP disagree in sign (Simeone: B grade, −0.03 goal edge) — without it the lede flatly contradicts the grade card above it.
  - "Style of the teams he coached" (`se_coach_style()` → `renderStyle` → `styleBars`) — Layer B, for the 256 coaches with ≥ `se_style_min_games` (38) of big-5 style data. Carries a separate inset **pressing-height block** (`renderPressingHeight` → `charts.js spectrumBar`, a named-pole percentile scale "Deep block ↔ High press"): it is inset because it is measured per *season*, not per match, so unlike the nine axes it cannot always be pinned to the coach rather than his club (`blended` flag, 56 of 256). **Do not draw it on a pitch** — the stat is the share of possession won in the attacking third *ranked against other coaches*, so a marker at a pitch position would claim a physical location the data does not contain. **Percentile, never raw SD** (design §3.3: coach means compress toward 0, so raw SD renders every fingerprint flat); percentiles are ranked *within* the same ≥38-game set that is displayed, so they differ slightly from the ≥100-game percentiles quoted in the design doc/session logs. **One hue, not the site's pos/neg pair** — these axes have no good/bad polarity and the diverging ramp would invent a verdict. The title, the `coach_owned` dots (lineup stability + pressing intensity only) and the footnote are all load-bearing per design §5: club identity beats coach on 7 of 9 axes, so the card may never say "his style".
  - **The xG cut and Layer C are deliberately absent.** xG is 3 big-5 seasons with zero FDR-significant coaches — a recent-form lens a coach page would flatten into a career verdict. Layer C is a null; its raw correlations must never render as findings. Both live in the writeup (Part 8) instead.
- **jsonlite gotcha:** the export uses `auto_unbox = TRUE`, so any vector that can be length 1 but must stay a JSON array needs `I()` (see `leagues`, `seasons` in the exporters) or the frontend crashes on `.join`/iteration.
- Club crests: `xx_raw_team_crest()` / `xx_data_populate_team_crests()` in `source_data.r` download from the TM image CDN (`wappen/head/<id>.png` — no page scrape). 404 on both URL variants is recorded as permanently missing in `data/cache/team_crests.rds`; transient failures (including empty 200s) retry on the next run. All 496 active-league clubs are downloaded.
- The frontend is dependency-free vanilla JS (ES modules, hand-rolled SVG charts, light/dark via CSS custom properties). Pages fetch JSON, so serve the folder (`python -m http.server` in `site/`) rather than opening `file://`. Grades never render without their cut label ("Top-5 leagues" / "All leagues") — the two cuts use separate grading curves.
- **Team builder** (`site/builder.html` + `js/builder.js`, design: `Docs/Team_Builder_Design.md`): build a custom XI on a drawn pitch (any of the 22 formations, click-to-pick from all big-5 player-seasons 2015/16–2024/25) and get the similarity-based coach suggestions computed client-side — cosine similarity on archetype shares + the 85/15 quality blend, numerically identical to `se_suggestions()` (verified against an R fixture). `se_export_builder()` writes `site/data/builder/{players,coaches,meta}.json`; formation pitch coordinates live in `se_formation_layouts` (site_export.R) and are validated against `cr_formation_slots` at export. Player photos: `xx_raw_player_image_url()` / `xx_data_populate_player_images()` in `source_data.r` (resumable, priority-ordered by career minutes, NULL/NA fetch-vs-missing semantics like the nationality scraper; lookup `data/cache/player_images.rds`, files `data/images/players/<id>`). The builder never shows predicted points for a fantasy XI (outside the M3 model's support) and carries the same descriptive-similarity labeling as team pages.
- **Fan/validation surfaces** (Parts 11–12, shipped 2026-07-22): the deserved table rides on the existing league standings as a "Deserved" column (expected rank + position swing, `se_export_leagues`); `site/players.html` + `js/players.js` (`se_export_players()`) is the player-development leaderboard; `site/validation.html` + `js/validation.js` (`se_export_validation()`) is the "Does it work?" report card (forward test + event study + the Part-7 payoff). Both new pages are linked from the header nav in `components.js`.
  - The players page leads with **`charts.js growthCurves()`** — the CDE baseline as an age curve per position, i.e. the expectation the leaderboard's residual is measured against. `se_growth_curves()` **refits the CDE-total baseline from `player_dev_residuals_<cut>.rds`** (every RHS column is in that file) and **asserts it still reproduces the stored `pred_total`** — the check that fires if `cvg_fit_baselines()`'s spec ever changes. Curves are **standardized (g-computation)**: age and position are overwritten on a fixed sample of real player-seasons, so a position gap is an age × role effect and not a price-mix difference; the consequence to keep in the footnote is that the curve runs *below* what real teenagers average, because they also start cheaper.
  - The validation page's lede is the **three-validation block** (`renderValidations()` → `.val-card`): per card, a design-type chip in the eyebrow (out-of-sample forecast / natural experiment / future holdout), the question, a short **"What the test does"** paragraph (the data, the mechanic, what is withheld), the result *in points per 38-game season per SD of grade* with the p-value as a chip, a one-clause caveat, and a plain-language "What this means" + writeup deep link. **Tests 1 and 2 are the pair readers conflate** — both are "does the grade predict hires?" — so the chips separate them and test 2's copy *opens* by naming the difference (test 1 pools appointments across hundreds of clubs; test 2 holds one club fixed across a single swap). Do not compress this back to one line per test: a shorter draft was tried and the two hiring tests became indistinguishable. The "Why it takes three" card carries the point that each design is vulnerable to something the other two are not. Effect sizes are computed at export (`pts_per_sd`), and the Part-7 payoff numbers are derived from `recommender.rds$meta$payoff` — **the published p = 0.016 is the one-sided paired test** across LOSO folds, matching the pre-registered directional acceptance rule (two-sided would be 0.031 — the wrong test, not a stricter one). **Caveats stay on the cards, never demoted to a footnote:** the realized-vs-pre-hire framing (p = 0.052), the confounded grade-*gap* null, and the single-season limit.
  - **"Inside test 3" is two scatters, one per question the forward test asks** (added 2026-07-23), because the section's job is to *show* the result the card above states.
    - `charts.js expectedVsActual()` is **Q1**: all 252 holdout clubs, expected vs actual, against a y = x reference. **Both axes share one domain** (a squashed axis would fake a tighter fit) and the unit is **PPG, never total points**, since the 14 leagues play 22–46 games. Dots take the site's `--pos`/`--neg` pair — a polarity encoding (which side of the line), not a ramp — revalidated in both modes (worst CVD ΔE 21.6 light / 19.2 dark).
    - `charts.js gradeVsOutcome()` is **Q2**: one dot per 2025/26 stint, prior grade against realized overperformance, and it must carry **all three of** the raw stints (**area = games played**, since a 6-game caretaker residual spans ±1.9 PPG against ±1.0 for 10+ games and equal dots would invite reading the noisiest points hardest), the games-weighted fit line, and the **tertile means** — *not* quartiles, whose Q3/Q4 difference (0.117 vs 0.060) sits inside its own SEs and reads as a real dip. **The chart is deliberately unflattering: r = 0.166.** Without the group means a validated result looks like a null; without the "cloud is wide / single dots mean little" footnote the trend line oversells it. Group SEs (~0.03 against a ±1.9 axis) render as 2px stubs, so **error bars are stated in words, never drawn** — do not "restore" them. Only the 219 graded stints are plotted (the 216 first-timers would pile into a stripe at x = 0), so the chart quotes the **graded-only p = 0.0036** and names the headline p = 0.0024 as the all-stints figure — keep those two apart.
    - **Everything in this section must be evidence, not colour.** The "who over/underperformed most in 2025/26" leaderboards (teams *and* coaches) were cut on 2026-07-23 for exactly that reason — the page argues that the model works, and a list of names does not. That material already lives on the league pages (deserved table) and coach pages; do not re-add it here.
    - Shared idiom: direct labels get a hairline leader to their dot plus a `paint-order: stroke` surface halo (a floating name in a 200-point cloud is ambiguous, and an unhaloed one is unreadable where it crosses a mark); label sets thin below 560px, and `gradeVsOutcome` picks its two by *separation* (best-graded + biggest overperformer), never the first few in the array.
  - **Four-series colour is `CAT4` in `charts.js`, and the ORDER is load-bearing** — blue → orange → aqua → yellow (`--series-1/-3/-2/-4`) is the reference palette's validated slot sequence, the only thing that keeps the adjacent pairs colourblind-separable (worst adjacent ΔE 9.1 light / 8.4 dark; the same four hues **fail** the all-pairs gate, so never re-order or cycle them, and never use this set for a scatter). Aqua and yellow sit below 3:1 on the light surface, which is why every curve also carries a direct end label in the right gutter.

## Data Schemas

| Cache file | Key columns |
|---|---|
| `leagues.rds` | `league_id`, `league_name`, `league_season_id`, `season_start_year` |
| `teams.rds` | `league_season_id`, `team_season_id`, `team_name` |
| `players.rds` | `team_season_id`, `player_id`, `player_name`, `player_age`, `player_position`, `minutes_played`, `percent_minutes_played`, `player_market_value_euro` |
| `matches.rds` | `league_season_id`, `match_id`, `home_team_id`, `away_team_id`, `home_team_goals`, `away_team_goals` |

Coach data (`coaches.rds` — `team_season_id`, `coach_id`, `coach_name`, `date_from`, `date_to`) is populated for the **full 14-league, 2005–2024 dataset** (13,907 stint rows covering 5,078 of 5,080 team-seasons, ~695–775 stints/yr), plus the 2025/26 forward-test season (470 stints). Verified 2026-07-22 and re-checked 2026-07-24 — the old "5-league, 2015–2024 only" note was stale.

SofaScore caches (`data/cache/sofascore/`, one file per season id, populated for PL 2015/16–2024/25):

| Cache file | Key columns |
|---|---|
| `players_<sid>.rds` | `season_ss_id`, `player_ss_id`, `player_name`, `team_ss_id`, `team_name` |
| `stats_<sid>.rds` | `player_ss_id`, `stat_name`, `stat_value` (long; ~110 season stats) |
| `heatmap_<sid>.rds` | `player_ss_id`, `x`, `y`, `count` (0–100 pitch grid) |
| `events_<sid>.rds` | `event_ss_id`, teams, goals, `start_timestamp`, `round`, `has_xg` |
| `formations_<sid>.rds` | `event_ss_id`, `is_home`, `formation` |
| `match_stats_<sid>.rds` | `event_ss_id`, `player_ss_id`, `position`, `substitute`, `stat_name`, `stat_value` |
| `shots_<sid>.rds` | `event_ss_id`, `player_ss_id`, `x`, `y`, `xg`, `body_part`, `situation`, `shot_type` |
| `crosswalk_<sid>.rds` | `player_ss_id` ↔ `player_id` (TM URL), `method` |
| `status_<sid>.rds`, `match_status_<sid>.rds` | scrape bookkeeping — do not edit |
| `archetypes.rds` | `player_ss_id`, `season_start_year`, `position_group`, `archetype`, `archetype_label` (all seasons in one file; rebuilt by `run_archetypes()`) |

## Conventions

- All functions in `source_data.r` use the `xx_` prefix. Raw scrapers use `xx_raw_`, cached accessors use `xx_data_`, and helper/utility functions use `xx_`.
- SofaScore functions (`source_sofascore.r`, `sofascore_crosswalk.r`) use the `ss_` prefix with the same raw/data tier split.
- M6 analysis functions use the `pa_` prefix (`player_archetypes.R`) and `cf_` prefix (`coach_fit.R`).
- Use the native pipe `|>` rather than `%>%` in new code (existing code mixes both).
- 2-space indentation (set in `.Rproj`).
- `src/workpad.r` is a scratch file for exploration — do not treat it as authoritative.
- `src/coach.r` is an older prototype referencing the `worldfootballR` package directly. `source_data.r` supersedes it with custom scraping that is more stable.
