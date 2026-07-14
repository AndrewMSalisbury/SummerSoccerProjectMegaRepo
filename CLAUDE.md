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

Later milestones build on this in a source chain — `coach_attribution.R` → `residual_analysis.R` → `model_comparison.R` → `tabler.R` (with `source_data.r` sourced manually first): `model_comparison.R` (M3, `run_milestone3()`), `residual_analysis.R` (M4, `run_milestone4()`), `coach_attribution.R` (M5, `run_milestone5()`), `augmented_model.R` (coach BLUP CV). The M5 mixed model weights stints by `n_games` (since 2026-07-14): short caretaker stints carry far noisier per-game residuals, and games-weighted BLUPs predicted held-out stints better than unweighted ones. Its residual variance component is therefore per-game — the recommender's posterior-SD constants in `cr_build_scorer()` must be refreshed whenever M5 is refit.

### M6 Archetype Layer (`src/player_archetypes.R`, `src/coach_fit.R`)

The Milestone 6 coach/player-type fit analysis. Pure cache-readers (no scraping, no chromote):

- `player_archetypes.R` (`pa_` prefix) — per-player-season style features from the SofaScore caches (all big-5 leagues) and k-means archetype clustering within D/M/F position groups (11 archetypes, labels in `pa_archetype_labels` — big-5 semantics as of 2026-07-12, incl. the wing-back archetype). `run_archetypes()` rebuilds `data/cache/sofascore/archetypes.rds`. Features are style-only (no goals/ratings/xG) and z-scored within league × season × position group.
- `coach_fit.R` (`cf_` prefix) — lagged archetype assignment (cross-league; current-season fallback for players new to the big-5, flagged), minutes-weighted archetype shares per coach stint, join to M5 partial residuals, global mixed model + per-coach tests + strict-lagged sensitivity. `cf_run_analysis()` runs everything; sources `coach_attribution.R`, `player_archetypes.R`, `sofascore_crosswalk.r`.

Data conventions that will bite if forgotten: SofaScore **shot coordinates put the attacked goal at (0, 50)** (heatmaps attack toward x = 100); **`match_stats$team_ss_id` is the player's club at scrape time, not the match team** — derive the match side from `is_home` + the event's home/away ids; season stat fields `outfielderBlocks`/`ballRecovery` exist only from 2023/24 and must not be used as features; **one SofaScore team id can carry several name spellings within a season** and league events include relegation playoffs against lower-division clubs — team mapping goes through `ss_crosswalk_team_map()` (greedy one-to-one), never plain best-overlap.

### Coach Recommender (`src/coach_recommender.R`)

Answers "who is the best coach for this team?" (design: `Docs/Coach_Recommender_Design.md`). `cr_` prefix, pure cache/results reader, sources the `coach_fit.R` chain. Key pieces: hand-mapped slots for all 22 observed formation strings (`cr_formation_slots`); recency-weighted coach formation profiles (δ = 0.3, chosen out-of-sample) + rigidity; archetype → slot eligibility matrix with TM-position fallback and a greedy+swaps max-value XI (`cr_best_xi_value`); random-slope fit model on three composition axes (creators / spine / wing-back — NOT significant, LRT p = 0.449, kept under shrinkage); `cr_score_team()` decomposes uplift into quality / fit / deployment; `cr_payoff_validation()` is the pre-registered LOSO test.

**Payoff verdict (2026-07-13, binding on what the site presents):** only the quality BLUP is validated out-of-sample on new coach-club pairings (p = 0.016 realized framing); fit + deployment are exploratory and must always be labeled as such. `cr_save_results(scorer, payoff_folds)` writes `data/results/recommender.rds` (per-team suggestions for latest-season big-5 squads + career facts + meta) for the site exporter. Career facts feed the plausibility filter chips; coach nationality comes from `xx_data_populate_coach_nationalities()` in `source_data.r` (resumable TM profile scrape, priority-ordered to ranked coaches; TM intermittently 502s this page type — the populate backs off and can be re-run).

### Website Layer (`src/site_export.R`, `site/`)

A static presentation site lives in `site/` at the repo root — the one place the R code writes outside `src/data/` (it is a publishing target, not analysis data). Design: `Docs/Website_Design.md`; build plan: `Docs/Website_Implementation_Plan.md`.

- `export_site_data()` (`se_` prefix, working dir `src/`) regenerates everything under `site/data/` (per-coach/team/league JSON keyed by TM numeric ids, leaderboard, search index, meta), `site/assets/` (coach images + club crests copied from `data/images/`), and `site/writeup.html` (converted from `Docs/Summary_of_Findings.md` via `{commonmark}`). It wipes and rebuilds those paths; never edit them by hand. Hand-written files (`*.html` except writeup, `css/`, `js/`) are never touched.
- Export inputs: `data/results/*.rds` — including `coach_grades_*.rds` (written by `save_coach_grades()` in `coach_attribution.R`), `archetype_fit.rds` (written by `cf_save_results()` in `coach_fit.R`), and `recommender.rds` (written by `cr_save_results()` in `coach_recommender.R` — feeds the team-page "Suggested coaches" section; teams without an entry get a note card). Re-run those savers after re-running M5/M6/recommender before exporting.
- **jsonlite gotcha:** the export uses `auto_unbox = TRUE`, so any vector that can be length 1 but must stay a JSON array needs `I()` (see `leagues`, `seasons` in the exporters) or the frontend crashes on `.join`/iteration.
- Club crests: `xx_raw_team_crest()` / `xx_data_populate_team_crests()` in `source_data.r` download from the TM image CDN (`wappen/head/<id>.png` — no page scrape). 404 on both URL variants is recorded as permanently missing in `data/cache/team_crests.rds`; transient failures (including empty 200s) retry on the next run. All 496 active-league clubs are downloaded.
- The frontend is dependency-free vanilla JS (ES modules, hand-rolled SVG charts, light/dark via CSS custom properties). Pages fetch JSON, so serve the folder (`python -m http.server` in `site/`) rather than opening `file://`. Grades never render without their cut label ("Top-5 leagues" / "All leagues") — the two cuts use separate grading curves.

## Data Schemas

| Cache file | Key columns |
|---|---|
| `leagues.rds` | `league_id`, `league_name`, `league_season_id`, `season_start_year` |
| `teams.rds` | `league_season_id`, `team_season_id`, `team_name` |
| `players.rds` | `team_season_id`, `player_id`, `player_name`, `player_age`, `player_position`, `minutes_played`, `percent_minutes_played`, `player_market_value_euro` |
| `matches.rds` | `league_season_id`, `match_id`, `home_team_id`, `away_team_id`, `home_team_goals`, `away_team_goals` |

Coach data (`coaches.rds`) exists and is populated for the original 5-league, 2015–2024 dataset. It has not yet been populated for the expanded 15-league dataset.

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
