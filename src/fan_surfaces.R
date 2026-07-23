# Fan-facing surfaces (fs_ prefix) -- pure results readers, no scrape, no model refit.
#
#  1. Deserved table  -- the standings each team "should" have finished on, from the
#     enhanced M3 model's expected points (squad value -> PPG), next to where they
#     actually finished. Over/under-achievement is exactly the M4/M5 residual, shown
#     as a league table: the core project finding made visceral for fans.
#
#  2. Player-development leaderboard -- who appreciated in market value fastest ABOVE
#     their own age/price/position/momentum trajectory. Reads the clean player_dev
#     residual (the one sound by-product of the CDE null); descriptive, scout-relevant.

suppressMessages({ library(dplyr) })

fs_results_dir <- "data/results"

# --- 1. Deserved table --------------------------------------------------------
fs_deserved_table <- function(cut = "14league") {
  r <- readRDS(file.path(fs_results_dir, sprintf("residuals_%s.rds", cut)))
  r |>
    filter(!is.na(predicted_ppg), !is.na(total_points)) |>
    mutate(expected_points = predicted_ppg * games_played) |>
    group_by(league, season) |>
    mutate(
      actual_rank   = rank(-total_points, ties.method = "min"),
      expected_rank = rank(-expected_points, ties.method = "min"),
      rank_delta    = expected_rank - actual_rank,   # +ve = finished higher than deserved
      over_points   = total_points - expected_points # +ve = overachieved (coaching + luck)
    ) |>
    ungroup() |>
    mutate(
      team = team_name,
      expected_points = round(expected_points, 1),
      over_points     = round(over_points, 1)
    ) |>
    select(league, season, team, team_season_id,
           actual_rank, actual_points = total_points, expected_rank, expected_points,
           rank_delta, over_points, residual_ppg = residual) |>
    arrange(league, season, actual_rank)
}

# Pretty-print one league-season's deserved table
fs_show_table <- function(dt, lg, yr) {
  d <- dt |> filter(league == lg, season == yr) |> arrange(actual_rank)
  cat(sprintf("\n=== %s %d/%d -- actual vs deserved ===\n", lg, yr, (yr %% 100) + 1))
  out <- d |> transmute(
    Pos = actual_rank, Team = team, Pts = actual_points,
    xRank = expected_rank, xPts = expected_points,
    `+/-Pos` = sprintf("%+d", rank_delta), `+/-Pts` = sprintf("%+.1f", over_points))
  print(as.data.frame(out), row.names = FALSE)
}

# Biggest over/under-achievers across the whole dataset
fs_deserved_extremes <- function(dt, n = 15) {
  cat("\n=== Biggest OVER-achievers (points above squad-value expectation) ===\n")
  print(as.data.frame(dt |> arrange(desc(over_points)) |>
    transmute(season, league, team, Pos = actual_rank, xRank = expected_rank,
              `+/-Pos` = rank_delta, over_points) |> head(n)), row.names = FALSE)
  cat("\n=== Biggest UNDER-achievers ===\n")
  print(as.data.frame(dt |> arrange(over_points) |>
    transmute(season, league, team, Pos = actual_rank, xRank = expected_rank,
              `+/-Pos` = rank_delta, over_points) |> head(n)), row.names = FALSE)
}

# --- 2. Player-development leaderboard ----------------------------------------
# dev_resid = log value growth above the age/price/position/momentum baseline.
# Restricts to players with real minutes and a non-trivial starting value so the
# multiple isn't dominated by academy-noise; dev_resid itself already de-trends value.
fs_dev_leaderboard <- function(cut = "14league", min_minutes = 1500,
                               min_value = 1e6, min_season = NULL) {
  pd <- readRDS(file.path(fs_results_dir, sprintf("player_dev_residuals_%s.rds", cut)))
  d <- pd |>
    filter(has_minutes, minutes_played >= min_minutes, value_t >= min_value,
           !is.na(dev_resid), !is.na(value_next))
  if (!is.null(min_season)) d <- d |> filter(season >= min_season)
  d |>
    mutate(
      club = sub("^https://www.transfermarkt.com/", "", club_id),
      club = sub("/startseite.*$", "", club),
      multiple = round(value_next / value_t, 2),
      value_t_m = round(value_t / 1e6, 1),
      value_next_m = round(value_next / 1e6, 1),
      dev_resid = round(dev_resid, 3)
    ) |>
    arrange(desc(dev_resid)) |>
    select(player_id, player_name, position_group, age = player_age, club, league, season,
           value_t_m, value_next_m, multiple, dev_resid)
}

fs_show_dev <- function(lb, n = 25, label = "") {
  cat(sprintf("\n=== Top %d over-appreciating players %s ===\n", n, label))
  cat("(value_t_m -> value_next_m in EUR millions; dev_resid = log-growth above age/price/position baseline)\n")
  print(as.data.frame(head(lb, n)), row.names = FALSE)
}

# by archetype/position summary already exists in the CDE writeup; here a by-position mean
fs_dev_by_position <- function(lb) {
  lb |> group_by(position_group) |>
    summarize(n = n(), mean_dev = round(mean(dev_resid), 3),
              median_multiple = median(multiple), .groups = "drop")
}

run_fan_surfaces <- function(save = TRUE) {
  dt <- fs_deserved_table("14league")
  fs_show_table(dt, "premier-league", 2015)   # Leicester's miracle
  fs_show_table(dt, "premier-league", 2023)
  fs_deserved_extremes(dt)

  lb      <- fs_dev_leaderboard("14league")
  lb_recent <- fs_dev_leaderboard("14league", min_season = 2020)
  fs_show_dev(lb, 25, "(all seasons, 14 leagues)")
  fs_show_dev(lb_recent, 20, "(2020+)")
  cat("\n=== Player development by position ===\n")
  print(as.data.frame(fs_dev_by_position(lb)), row.names = FALSE)

  if (save) {
    saveRDS(list(deserved = dt, dev_leaderboard = lb), file.path(fs_results_dir, "fan_surfaces.rds"))
    cat("\nSaved data/results/fan_surfaces.rds\n")
  }
  invisible(list(deserved = dt, dev = lb))
}
