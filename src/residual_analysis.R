source("model_comparison.R")

# Fits enhanced_fixed on all rows where norm_weighted_value > 0, then generates
# predictions for every row in the dataset. Rows excluded by the log filter
# (non-positive norm_weighted_value) receive NA for predicted_ppg, residual,
# and residual_points.
compute_residuals <- function(dataset, log_transform = TRUE) {
  d_fit <- if (log_transform) {
    dataset |> filter(norm_weighted_value > 0, norm_total_value > 0)
  } else {
    dataset
  }

  model <- lm(
    points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
    data = d_fit
  )

  predicted <- suppressWarnings(predict(model, newdata = dataset))
  predicted[!is.finite(predicted)] <- NA

  n_na <- sum(is.na(predicted))
  if (n_na > 0) {
    message(n_na, " team-season(s) have NA residuals due to non-positive norm_weighted_value.")
  }

  dataset |>
    mutate(
      predicted_ppg   = predicted,
      residual        = points_per_game - predicted_ppg,
      residual_points = residual * games_played
    ) |>
    select(
      team_season_id, team_name, league, season,
      total_team_value, norm_weighted_value,
      total_points, games_played, points_per_game,
      predicted_ppg, residual, residual_points
    )
}

# Within each league-season, residuals should sum to ~0 because points are
# zero-sum within a season. Flags any league-season where the mean residual
# exceeds the threshold (default 0.05 PPG = ~1.9 points over a 38-game season).
# Uses mean rather than sum so the check is scale-invariant across 18- vs
# 20-team leagues.
validate_balance <- function(residuals_tbl, threshold = 0.05) {
  balance <- residuals_tbl |>
    group_by(league, season) |>
    summarize(
      n_teams       = n(),
      n_na          = sum(is.na(residual)),
      residual_sum  = round(sum(residual,  na.rm = TRUE), 4),
      residual_mean = round(mean(residual, na.rm = TRUE), 4),
      .groups = "drop"
    ) |>
    mutate(flagged = abs(residual_mean) > threshold) |>
    arrange(desc(abs(residual_mean)))

  n_flagged <- sum(balance$flagged)
  if (n_flagged == 0) {
    cat("All league-seasons pass the balance check (|mean residual| <=", threshold, "PPG).\n")
  } else {
    cat(n_flagged, "league-season(s) flagged (|mean residual| >", threshold, "PPG):\n")
    print(balance |> filter(flagged), n = Inf)
  }

  invisible(balance)
}

# Ranked table of the n largest and n smallest residuals by residual_points.
# residual_points (residual PPG × games played) is the primary sort since it
# is more interpretable than PPG alone.
top_performers <- function(residuals_tbl, n = 15) {
  clean <- residuals_tbl |>
    filter(!is.na(residual)) |>
    mutate(
      residual_points = round(residual_points, 2),
      residual        = round(residual, 4)
    )

  top <- clean |>
    arrange(desc(residual_points)) |>
    head(n) |>
    select(team_name, league, season, residual_points, residual)

  bottom <- clean |>
    arrange(residual_points) |>
    head(n) |>
    select(team_name, league, season, residual_points, residual)

  cat("=== Top", n, "Overperformers ===\n")
  print(top, n = Inf)
  cat("\n=== Top", n, "Underperformers ===\n")
  print(bottom, n = Inf)

  invisible(list(top = top, bottom = bottom))
}

# Histogram and Q-Q plot of all residuals, summary statistics, and top/bottom
# performers table. Excludes NA residuals throughout.
analyze_distribution <- function(residuals_tbl, n = 15) {
  clean <- residuals_tbl |> filter(!is.na(residual))
  r     <- clean$residual
  sd_r  <- sd(r)

  op <- par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
  on.exit(par(op))

  hist(r, breaks = 30, col = "steelblue",
       main = "Residual distribution", xlab = "Residual (PPG)")
  abline(v = 0, col = "red", lwd = 2, lty = 2)

  qqnorm(r, main = "Q-Q plot (residuals)",
         pch = 16, col = rgb(0.2, 0.4, 0.8, 0.4))
  qqline(r, col = "red", lwd = 2)

  cat("=== Residual Distribution Summary ===\n")
  cat("n:              ", length(r), "\n")
  cat("mean:           ", round(mean(r), 4), "\n")
  cat("sd:             ", round(sd_r,    4), "\n")
  cat("min:            ", round(min(r),  4), "\n")
  cat("max:            ", round(max(r),  4), "\n")
  cat("within ±1 SD:   ", round(mean(abs(r) <= sd_r) * 100, 1), "%\n")
  cat("outliers >2 SD: ", sum(abs(r) > 2 * sd_r), "\n\n")

  top_performers(residuals_tbl, n = n)
}

# Checks whether residual magnitude varies systematically with squad value.
# A significant negative slope means richer squads have smaller residuals —
# the model is more confident for elite clubs, which would mean coach rankings
# are less reliable at the top end.
check_heteroskedasticity <- function(residuals_tbl) {
  clean <- residuals_tbl |>
    filter(!is.na(residual), norm_weighted_value > 0) |>
    mutate(abs_residual = abs(residual))

  model <- lm(abs_residual ~ log(norm_weighted_value), data = clean)
  s       <- summary(model)
  coef_val <- coef(model)["log(norm_weighted_value)"]
  p_val    <- s$coefficients["log(norm_weighted_value)", "Pr(>|t|)"]

  op <- par(mar = c(4, 4, 3, 1))
  on.exit(par(op))

  plot(log(clean$norm_weighted_value), clean$abs_residual,
       main = "|Residual| vs log(norm_weighted_value)",
       xlab = "log(norm_weighted_value)", ylab = "|Residual| (PPG)",
       pch = 16, col = rgb(0.2, 0.4, 0.8, 0.3))
  abline(model, col = "red", lwd = 2)

  cat("=== Heteroskedasticity Check ===\n")
  cat("Regression: |residual| ~ log(norm_weighted_value)\n")
  cat("Coefficient:", round(coef_val, 4), "\n")
  cat("p-value:    ", round(p_val,    4), "\n\n")

  if (p_val < 0.05 && coef_val < 0) {
    cat("Significant negative slope: richer squads have smaller residuals.\n")
    cat("Implication: coach rankings are less reliable for elite clubs.\n")
  } else if (p_val < 0.05 && coef_val > 0) {
    cat("Significant positive slope: richer squads have larger residuals.\n")
  } else {
    cat("No significant relationship detected.\n")
    cat("Residual variance is consistent across the squad value range.\n")
  }

  invisible(model)
}

# For each team, pairs residual(t) with residual(t+1) for consecutive seasons.
# Teams are identified by stripping the /saison_id/YYYY suffix from team_season_id
# so the same club is recognised across seasons regardless of which league it was in.
# Reports the overall lag-1 correlation and per-team correlations for teams with
# >= 3 consecutive pairs. High persistence suggests a stable club effect; low
# persistence suggests the residual is more volatile and more likely coach-driven.
temporal_persistence <- function(residuals_tbl) {
  clean <- residuals_tbl |>
    filter(!is.na(residual)) |>
    mutate(team_id = sub("/saison_id/\\d+", "", team_season_id))

  pairs <- clean |>
    arrange(team_id, season) |>
    group_by(team_id, team_name) |>
    mutate(
      residual_next = lead(residual),
      season_next   = lead(season)
    ) |>
    filter(!is.na(residual_next), season_next == season + 1) |>
    ungroup()

  cat("=== Temporal Persistence Analysis ===\n")
  cat("Consecutive season pairs:", nrow(pairs), "\n")
  cat("Teams with >=1 pair:     ", n_distinct(pairs$team_id), "\n\n")

  overall_cor  <- cor(pairs$residual, pairs$residual_next, use = "complete.obs")
  overall_test <- cor.test(pairs$residual, pairs$residual_next)
  cat("Overall lag-1 correlation:", round(overall_cor,              4), "\n")
  cat("p-value:                  ", round(overall_test$p.value,     4), "\n")
  cat("95% CI:                   [", round(overall_test$conf.int[1], 4),
      ",", round(overall_test$conf.int[2], 4), "]\n\n")

  per_team <- pairs |>
    group_by(team_id, team_name) |>
    filter(n() >= 3) |>
    summarize(
      n_pairs       = n(),
      correlation   = round(cor(residual, residual_next, use = "complete.obs"), 4),
      mean_residual = round(mean(residual), 3),
      .groups = "drop"
    )

  cat("Teams with >=3 pairs:", nrow(per_team), "\n\n")

  op <- par(mar = c(4, 4, 3, 1))
  on.exit(par(op))

  hist(per_team$correlation, breaks = 20, col = "steelblue",
       main = "Per-team lag-1 residual correlations",
       xlab = "Correlation (residual t vs t+1)")
  abline(v = 0,           col = "red",        lwd = 2, lty = 2)
  abline(v = overall_cor, col = "darkorange",  lwd = 2)
  legend("topright", legend = c("r = 0", "overall r"),
         col = c("red", "darkorange"), lwd = 2, lty = c(2, 1), bty = "n")

  cat("=== Top 10 Most Persistent Teams ===\n")
  print(per_team |> arrange(desc(correlation)) |>
          select(team_name, n_pairs, correlation, mean_residual) |>
          head(10), n = Inf)

  invisible(list(pairs = pairs, per_team = per_team, overall_cor = overall_cor))
}

# Horizontal bar chart of residuals for a single league-season, sorted low to
# high, colored by sign (blue = overperform, red = underperform).
plot_league_season_bars <- function(residuals_tbl, league_name, season_year) {
  d <- residuals_tbl |>
    filter(league == league_name, season == season_year, !is.na(residual)) |>
    arrange(residual)

  if (nrow(d) == 0) stop("No data for ", league_name, " ", season_year)

  colors <- ifelse(d$residual >= 0, "steelblue", "tomato")

  op <- par(mar = c(4, 12, 3, 2))
  on.exit(par(op))

  barplot(d$residual,
          names.arg = d$team_name,
          horiz     = TRUE,
          col       = colors,
          border    = NA,
          main      = paste0(league_name, " ", season_year, " — Residuals (PPG)"),
          xlab      = "Residual (PPG)",
          las       = 1,
          cex.names = 0.8)
  abline(v = 0, col = "black", lwd = 1)
}

# One heatmap per league for teams present in >= min_seasons in that league.
# Teams are sorted by mean residual (highest at top). Uses base R image().
# NA cells (team absent from a season) appear as white.
plot_team_heatmap <- function(residuals_tbl, min_seasons = 5) {
  pal <- colorRampPalette(c("tomato", "white", "steelblue"))(101)

  for (lg in sort(unique(residuals_tbl$league))) {
    d_lg <- residuals_tbl |> filter(league == lg)

    keep <- d_lg |>
      filter(!is.na(residual)) |>
      group_by(team_name) |>
      summarize(n = n_distinct(season), .groups = "drop") |>
      filter(n >= min_seasons) |>
      pull(team_name)

    d <- d_lg |> filter(team_name %in% keep)

    seasons <- sort(unique(d$season))

    # ascending mean residual so image() puts highest at the top (y increases upward)
    team_order <- d |>
      group_by(team_name) |>
      summarize(mean_r = mean(residual, na.rm = TRUE), .groups = "drop") |>
      arrange(mean_r) |>
      pull(team_name)

    mat <- matrix(NA_real_,
                  nrow = length(team_order),
                  ncol = length(seasons),
                  dimnames = list(team_order, as.character(seasons)))
    for (i in seq_len(nrow(d))) {
      mat[d$team_name[i], as.character(d$season[i])] <- d$residual[i]
    }

    lim    <- max(abs(mat), na.rm = TRUE)
    breaks <- seq(-lim, lim, length.out = 102)

    dev.new()
    par(mar = c(3, 8, 3, 4))
    image(x = seq_along(seasons),
          y = seq_along(team_order),
          z = t(mat),
          col    = pal,
          breaks = breaks,
          axes   = FALSE,
          main   = paste0(lg, " — Residuals by team-season (PPG)"),
          xlab   = "",
          ylab   = "")
    axis(1, at = seq_along(seasons), labels = seasons, cex.axis = 0.85)
    axis(2, at = seq_along(team_order), labels = team_order, las = 1, cex.axis = 0.75)
    box()
  }
}

# For the top and bottom n team-seasons by residual_points, reports the
# percentage of minutes played by players who have a non-NA market value.
# Low coverage is the primary explanation for spuriously large residuals in
# early seasons of smaller leagues where Transfermarkt data is sparse.
minutes_coverage <- function(residuals_tbl, n = 15) {
  clean <- residuals_tbl |> filter(!is.na(residual))

  top_ids    <- clean |> arrange(desc(residual_points)) |> head(n) |> pull(team_season_id)
  bottom_ids <- clean |> arrange(residual_points)       |> head(n) |> pull(team_season_id)
  ids        <- unique(c(top_ids, bottom_ids))

  coverage <- xx_data_cache$players |>
    filter(team_season_id %in% ids) |>
    group_by(team_season_id) |>
    summarize(
      total_minutes  = sum(minutes_played, na.rm = TRUE),
      valued_minutes = sum(minutes_played[!is.na(player_market_value_euro)], na.rm = TRUE),
      pct_covered    = round(100 * valued_minutes / total_minutes, 1),
      .groups = "drop"
    )

  joined <- clean |>
    filter(team_season_id %in% ids) |>
    left_join(coverage, by = "team_season_id") |>
    select(team_name, league, season, residual_points, residual, pct_covered)

  cat("=== Top", n, "Overperformers — Minutes Coverage ===\n")
  print(joined |> arrange(desc(residual_points)) |> head(n), n = Inf)
  cat("\n=== Top", n, "Underperformers — Minutes Coverage ===\n")
  print(joined |> arrange(residual_points) |> head(n), n = Inf)

  invisible(joined)
}

# Runs the full Milestone 4 pipeline in order. Returns all results invisibly.
run_milestone4 <- function(seasons = 2005:xx_last_data_season, log_transform = TRUE, leagues = xx_all_leagues()) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD DATASET & COMPUTE RESIDUALS")
  dataset       <- build_model_dataset(seasons, leagues = leagues)
  cat("Rows loaded:", nrow(dataset), "\n")
  residuals_tbl <- compute_residuals(dataset, log_transform = log_transform)
  cat("NA residuals:", sum(is.na(residuals_tbl$residual)), "\n")

  sep("STEP 2: VALIDATE RESIDUAL BALANCE")
  balance <- validate_balance(residuals_tbl)

  sep("STEP 3: RESIDUAL DISTRIBUTION & TOP PERFORMERS")
  performers <- analyze_distribution(residuals_tbl)

  sep("STEP 4: HETEROSKEDASTICITY CHECK")
  check_heteroskedasticity(residuals_tbl)

  sep("STEP 5: TEMPORAL PERSISTENCE")
  persistence <- temporal_persistence(residuals_tbl)

  sep("STEP 6: VISUALIZATIONS")
  cat("Bar chart — premier-league 2023 (call plot_league_season_bars() for others):\n")
  plot_league_season_bars(residuals_tbl, "premier-league", 2023)
  cat("Team heatmaps (all leagues):\n")
  plot_team_heatmap(residuals_tbl)

  sep("MILESTONE 4 COMPLETE")
  cat("Residuals table:    ", nrow(residuals_tbl), "rows\n")
  cat("NA residuals:       ", sum(is.na(residuals_tbl$residual)), "\n")
  cat("Balance flags:      ", sum(balance$flagged), "league-season(s)\n")
  cat("Overall lag-1 r:    ", round(persistence$overall_cor, 4), "\n")
  cat("Top overperformer:  ", performers$top$team_name[1],
      performers$top$season[1], "(+", performers$top$residual_points[1], "pts)\n")
  cat("Top underperformer: ", performers$bottom$team_name[1],
      performers$bottom$season[1], "(", performers$bottom$residual_points[1], "pts)\n")

  invisible(list(
    dataset       = dataset,
    residuals_tbl = residuals_tbl,
    balance       = balance,
    performers    = performers,
    persistence   = persistence
  ))
}
