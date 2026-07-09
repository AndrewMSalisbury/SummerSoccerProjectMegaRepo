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

Twenty league constants are declared (`xx_league_id_PREMIER_LEAGUE`, `xx_league_id_PRO_LEAGUE`, etc.), but `xx_all_leagues()` returns only 15 — five were excluded for data quality reasons:

- **Argentine Liga Profesional** (`AR1N`): Transfermarkt ignores `saison_id` for this league and returns 2024 squad data for every historical season (confirmed corruption).
- **J1 League** (`JAP1`): missing match cache for 2014–2015, sparse market value data in early seasons.
- **Liga MX** (`MEX1`): captures only one tournament (Clausura) per season, not a full-season equivalent.
- **Brazilian Série A** (`BRA1`) and **MLS** (`MLS1`): minutes-weighted metric actively hurts predictions — multi-competition squad rotation (Brazil) and salary cap roster construction (MLS) break the assumption that league minutes reflect squad deployment.

The 15 active leagues are: Premier League, La Liga, Ligue 1, Serie A, Bundesliga, Championship, Liga Portugal, Jupiler Pro League, Eredivisie, Danish Superliga, Ekstraklasa, Allsvenskan, HNL, Süper Lig, LaLiga 2. League-season URLs are constructed directly from the base constant (`paste0(league_id, "/plus/?saison_id=", year)`) and do not depend on the worldfootballR CSV.

### SofaScore Data Layer (`src/source_sofascore.r`, `src/sofascore_crosswalk.r`)

Added for the Milestone 6 coach/player-type fit analysis. Functions use the `ss_` prefix with the same two tiers as `source_data.r`: `ss_raw_*` scrapes, `ss_data_*` reads the RDS cache first. Caches live in `data/cache/sofascore/`, one file per SofaScore season id (the PL 2015/16–2024/25 ids are in `ss_pl_season_ids`).

**SofaScore rejects plain HTTP clients by TLS fingerprint** (R httr/curl get HTTP 403 regardless of headers), so every request goes through headless Chrome via `{chromote}` — Chrome must be installed. **Politeness is mandatory:** 4–7s jittered sleep per request, 90s rest every 250 requests, 10-minute backoff on 403/429, abort after 3 consecutive failures with progress saved (fully resumable). A one-off ~70-request burst once earned a ~24-hour IP block; steady pacing has never been blocked. Never remove these delays. Only HTTP 404 is recorded as permanently missing; other failures are retried on the next populate run.

SofaScore ids are opaque integers, not URLs — columns holding them are suffixed `_ss_id`. `ss_build_crosswalk(season_ss_id, league_season_id)` in `sofascore_crosswalk.r` links SofaScore player ids to Transfermarkt `player_id` URLs (99.2–100% matched on the pilot; unmatched rows are youth players absent from TM squad pages).

Data coverage limits (verified): per-match player statistics, formations, and shot coordinates go back to 2015/16; **xG exists from mid-2021/22** (complete from 2022/23); per-pass/dribble coordinate charts (`ss_raw_player_event_breakdown()`, the `rating-breakdown` endpoint) exist **only from 2025/26** and are not part of the pilot dataset.

To run or resume the pilot scrape (idempotent, resumes wherever it stopped):
```r
source("source_sofascore.r")
ss_data_populate_pl_pilot()
```

### Analysis Layer (`src/tabler.R`)

Builds on the data layer to produce per-team metrics and model comparisons:

- `league_season_team_chart(league_season_id)` — returns a table of all teams in a league-season with `total_team_value` (raw squad value), `weighted_team_value` (minutes-weighted), ranks for each, and actual `total_points`.
- `league_season_correlations(league_season_id)` — returns Pearson rank-correlations of both metrics against points rank. **This function is the current target of Milestone 3:** it will be replaced with a points-based regression comparison (see `Docs/Plan.md`).
- `all_correlations()` — iterates over all leagues × seasons and aggregates correlation results.

The `weighted_team_value` formula: for each player, `player_market_value_euro × percent_minutes_played`, summed per team. When a team has no minutes data (weighted value = 0), the value is imputed from a within-season regression against `total_team_value`.

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

## Conventions

- All functions in `source_data.r` use the `xx_` prefix. Raw scrapers use `xx_raw_`, cached accessors use `xx_data_`, and helper/utility functions use `xx_`.
- SofaScore functions (`source_sofascore.r`, `sofascore_crosswalk.r`) use the `ss_` prefix with the same raw/data tier split.
- Use the native pipe `|>` rather than `%>%` in new code (existing code mixes both).
- 2-space indentation (set in `.Rproj`).
- `src/workpad.r` is a scratch file for exploration — do not treat it as authoritative.
- `src/coach.r` is an older prototype referencing the `worldfootballR` package directly. `source_data.r` supersedes it with custom scraping that is more stable.
