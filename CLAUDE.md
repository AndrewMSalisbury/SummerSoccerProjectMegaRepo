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
xx_data_populate_league_seasons(2015:2024)  # scrapes all 5 leagues for given years
```

To run the analysis:
```r
source("tabler.R")
all_correlations()   # computes rank-correlations across all cached league-seasons
```

**Scraping is slow by design.** `xx_raw_team_seasons()` sleeps 10 seconds per page and `xx_raw_team_player_info()` sleeps 15 seconds to avoid rate-limiting Transfermarkt. Never remove these delays.

## Architecture

The project has two layers:

### Data Layer (`src/source_data.r`)

All functions are prefixed `xx_`. There are two tiers:

- `xx_raw_*()` — scrapes directly from Transfermarkt. Always slow (has `Sys.sleep()`). Call these only when you need fresh data.
- `xx_data_*()` — checks the in-memory cache, then the RDS cache, then calls `xx_raw_*()` only if needed. These are the functions to use in analysis code.

The in-memory cache (`xx_data_cache`) is a named list initialized by `xx_init_data_cache()`, which is called automatically when the file is sourced. It is backed by RDS files in `data/cache/` (relative to project root, i.e., one level up from `src/`).

**IDs throughout the project are Transfermarkt URLs**, not opaque integers. A `league_season_id` is a full URL like `https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024`. A `team_season_id` is a team's Transfermarkt page URL for a specific season. A `player_id` is a player's Transfermarkt profile URL. This means joins between tables use URL string matching.

The five supported leagues are declared as constants (`xx_league_id_PREMIER_LEAGUE`, etc.) and collected by `xx_all_leagues()`.

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

Coach data (`coaches.rds`) does not yet exist and is the primary remaining data layer task (Milestone 5).

## Conventions

- All functions in `source_data.r` use the `xx_` prefix. Raw scrapers use `xx_raw_`, cached accessors use `xx_data_`, and helper/utility functions use `xx_`.
- Use the native pipe `|>` rather than `%>%` in new code (existing code mixes both).
- 2-space indentation (set in `.Rproj`).
- `src/workpad.r` is a scratch file for exploration — do not treat it as authoritative.
- `src/coach.r` is an older prototype referencing the `worldfootballR` package directly. `source_data.r` supersedes it with custom scraping that is more stable.
