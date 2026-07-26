source("coach_attribution.R")

# Identifies consecutive coach pairs within team-seasons where the incoming
# coach was appointed mid-season (days_into_season >= min_days_into_season).
# Returns a paired table: one row per change event with outgoing and incoming
# partial_residual_ppg for the same team-season.
build_midseason_pairs <- function(coach_residuals_tbl,
                                  min_days_into_season = 20,
                                  min_incoming_games   = 10,
                                  min_outgoing_games   = 5) {
  matches <- xx_data_cache$matches

  first_match_dates <- bind_rows(
    matches |> select(team_season_id = home_team_id, match_date),
    matches |> select(team_season_id = away_team_id,  match_date)
  ) |>
    filter(!is.na(match_date)) |>
    group_by(team_season_id) |>
    summarize(first_match_date = min(match_date), .groups = "drop")

  stints <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg), !is.na(date_from)) |>
    left_join(first_match_dates, by = "team_season_id") |>
    mutate(days_into_season = as.numeric(date_from - first_match_date)) |>
    group_by(team_season_id) |>
    filter(n() >= 2) |>
    arrange(date_from) |>
    mutate(stint_order = row_number()) |>
    ungroup()

  # Build consecutive (outgoing, incoming) pairs within each team-season
  out_cols <- c("team_season_id", "team_name", "league", "season", "stint_order",
                "coach_id", "coach_name", "days_into_season", "n_games",
                "actual_ppg", "partial_residual_ppg")

  outgoing <- stints |>
    select(all_of(out_cols)) |>
    rename(
      out_stint_order   = stint_order,
      out_coach_id      = coach_id,
      out_coach_name    = coach_name,
      out_days_into     = days_into_season,
      out_n_games       = n_games,
      out_actual_ppg    = actual_ppg,
      out_residual      = partial_residual_ppg
    )

  incoming <- stints |>
    select(all_of(out_cols)) |>
    rename(
      in_stint_order   = stint_order,
      in_coach_id      = coach_id,
      in_coach_name    = coach_name,
      in_days_into     = days_into_season,
      in_n_games       = n_games,
      in_actual_ppg    = actual_ppg,
      in_residual      = partial_residual_ppg
    ) |>
    mutate(out_stint_order = in_stint_order - 1)

  pairs <- outgoing |>
    inner_join(
      incoming |> select(-team_name, -league, -season),
      by = c("team_season_id", "out_stint_order")
    ) |>
    filter(
      in_days_into  >= min_days_into_season,
      in_n_games    >= min_incoming_games,
      out_n_games   >= min_outgoing_games
    ) |>
    mutate(improvement = in_residual - out_residual)

  pairs
}

# Tests whether mid-season incoming coaches outperform the coaches they replaced.
# Uses paired t-test and Wilcoxon signed-rank test on (incoming - outgoing) residual.
# Prints a summary and produces two plots.
analyze_midseason_replacements <- function(residuals_tbl      = NULL,
                                           min_days_into_season = 20,
                                           min_incoming_games   = 10,
                                           min_outgoing_games   = 5) {
  if (is.null(residuals_tbl)) {
    dataset       <- build_model_dataset(2015:xx_last_data_season)
    residuals_tbl <- compute_residuals(dataset)
  }

  coach_res <- build_coach_residuals(residuals_tbl)
  pairs     <- build_midseason_pairs(coach_res,
                                     min_days_into_season = min_days_into_season,
                                     min_incoming_games   = min_incoming_games,
                                     min_outgoing_games   = min_outgoing_games)

  n          <- nrow(pairs)
  n_improved <- sum(pairs$improvement > 0)
  mean_out   <- mean(pairs$out_residual)
  mean_in    <- mean(pairs$in_residual)
  mean_diff  <- mean(pairs$improvement)

  cat("=== Mid-Season Replacement Analysis ===\n")
  cat(sprintf("Min days into season (incoming): %d\n", min_days_into_season))
  cat(sprintf("Min games for incoming coach:    %d\n", min_incoming_games))
  cat(sprintf("Min games for outgoing coach:    %d\n", min_outgoing_games))
  cat(sprintf("\nChange events analyzed:          %d\n", n))
  cat(sprintf("Unique team-seasons:             %d\n", n_distinct(pairs$team_season_id)))
  cat(sprintf("\nMean outgoing residual (PPG):    %+.4f\n", mean_out))
  cat(sprintf("Mean incoming residual (PPG):    %+.4f\n", mean_in))
  cat(sprintf("Mean improvement (PPG):          %+.4f\n", mean_diff))
  cat(sprintf("Incoming > outgoing:             %d / %d  (%.1f%%)\n",
              n_improved, n, 100 * n_improved / n))

  cat("\n=== Paired t-test (H0: improvement = 0) ===\n")
  t_res <- t.test(pairs$in_residual, pairs$out_residual, paired = TRUE)
  cat(sprintf("  t = %.3f,  df = %d,  p = %.4f\n",
              t_res$statistic, t_res$parameter, t_res$p.value))
  cat(sprintf("  95%% CI: [%+.4f, %+.4f]\n",
              t_res$conf.int[1], t_res$conf.int[2]))

  cat("\n=== Wilcoxon signed-rank test ===\n")
  w_res <- wilcox.test(pairs$in_residual, pairs$out_residual, paired = TRUE)
  cat(sprintf("  V = %.0f,  p = %.4f\n", w_res$statistic, w_res$p.value))

  # Plot 1: scatter — outgoing vs incoming residual per change event
  op <- par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
  on.exit(par(op))

  lim <- range(c(pairs$out_residual, pairs$in_residual))
  plot(pairs$out_residual, pairs$in_residual,
       pch = 16, col = adjustcolor("steelblue", 0.5),
       xlim = lim, ylim = lim,
       xlab = "Outgoing coach residual (PPG)",
       ylab = "Incoming coach residual (PPG)",
       main = "Outgoing vs Incoming: same team-season")
  abline(0, 1, col = "red", lty = 2, lwd = 1.5)
  abline(h = 0, v = 0, col = "grey70", lty = 3)
  text(lim[1] + 0.05, lim[2] - 0.05,
       sprintf("%.1f%% improved\np = %.3f", 100 * n_improved / n, t_res$p.value),
       adj = c(0, 1), cex = 0.85)

  # Plot 2: distribution of improvement (incoming - outgoing)
  hist(pairs$improvement, breaks = 30, col = "steelblue", border = "white",
       main = "Distribution of improvement (incoming − outgoing)",
       xlab = "Residual improvement (PPG)")
  abline(v = 0,         col = "red",    lty = 2, lwd = 2)
  abline(v = mean_diff, col = "orange", lty = 1, lwd = 2)
  legend("topright",
         legend = c("zero", sprintf("mean = %+.3f", mean_diff)),
         col    = c("red", "orange"), lty = c(2, 1), lwd = 2, cex = 0.85)

  cat("\n=== Top 10 most-improved changes ===\n")
  top10 <- pairs |>
    arrange(desc(improvement)) |>
    select(team_name, season, league, out_coach_name, out_n_games, out_residual,
           in_coach_name, in_n_games, in_residual, improvement) |>
    head(10)
  print(top10, n = Inf)

  cat("\n=== Bottom 10 (biggest declines) ===\n")
  bot10 <- pairs |>
    arrange(improvement) |>
    select(team_name, season, league, out_coach_name, out_n_games, out_residual,
           in_coach_name, in_n_games, in_residual, improvement) |>
    head(10)
  print(bot10, n = Inf)

  invisible(pairs)
}

# Tests whether incoming coaches post higher residuals in their replacement season
# than they do in their other (non-replacement) stints — using each coach as their
# own control. This separates the team's natural rebound (regression to the mean)
# from any genuine new-coach effect.
#
# For each incoming coach with at least one non-replacement stint:
#   bounce = mean(replacement residuals) - mean(other residuals)
# A positive mean bounce means coaches systematically outperform their own baseline
# when taking over a struggling team mid-season.
test_replacement_bounce <- function(pairs, coach_residuals_tbl) {
  # Mark which stints are mid-season replacements (incoming role in pairs)
  replacement_keys <- pairs |>
    select(team_season_id, coach_id = in_coach_id) |>
    distinct() |>
    mutate(is_replacement = TRUE)

  all_stints <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg)) |>
    left_join(replacement_keys, by = c("team_season_id", "coach_id")) |>
    mutate(is_replacement = coalesce(is_replacement, FALSE))

  replacement_coach_ids <- unique(pairs$in_coach_id)

  # Keep only coaches who appear in both contexts
  comparison <- all_stints |>
    filter(coach_id %in% replacement_coach_ids) |>
    group_by(coach_id, coach_name) |>
    filter(any(is_replacement), any(!is_replacement)) |>
    summarize(
      mean_replacement = mean(partial_residual_ppg[is_replacement]),
      mean_other       = mean(partial_residual_ppg[!is_replacement]),
      n_replacement    = sum(is_replacement),
      n_other          = sum(!is_replacement),
      bounce           = mean_replacement - mean_other,
      .groups          = "drop"
    ) |>
    arrange(desc(bounce))

  n_coaches   <- nrow(comparison)
  mean_bounce <- mean(comparison$bounce)
  n_positive  <- sum(comparison$bounce > 0)

  cat("=== New-Coach Bounce Test ===\n")
  cat(sprintf("Coaches with both replacement and other stints: %d\n\n", n_coaches))
  cat(sprintf("Mean replacement residual (PPG):  %+.4f\n", mean(comparison$mean_replacement)))
  cat(sprintf("Mean baseline residual (PPG):     %+.4f\n", mean(comparison$mean_other)))
  cat(sprintf("Mean bounce (PPG):                %+.4f\n", mean_bounce))
  cat(sprintf("Coaches with positive bounce:     %d / %d  (%.1f%%)\n",
              n_positive, n_coaches, 100 * n_positive / n_coaches))

  cat("\n=== Paired t-test (H0: bounce = 0) ===\n")
  t_res <- t.test(comparison$mean_replacement, comparison$mean_other, paired = TRUE)
  cat(sprintf("  t = %.3f,  df = %d,  p = %.4f\n",
              t_res$statistic, t_res$parameter, t_res$p.value))
  cat(sprintf("  95%% CI: [%+.4f, %+.4f]\n",
              t_res$conf.int[1], t_res$conf.int[2]))

  cat("\n=== Wilcoxon signed-rank test ===\n")
  w_res <- wilcox.test(comparison$mean_replacement, comparison$mean_other, paired = TRUE)
  cat(sprintf("  V = %.0f,  p = %.4f\n", w_res$statistic, w_res$p.value))

  # Scatter: baseline vs replacement residual per coach
  op <- par(mfrow = c(1, 2), mar = c(4, 4, 3, 1))
  on.exit(par(op))

  lim <- range(c(comparison$mean_other, comparison$mean_replacement))
  plot(comparison$mean_other, comparison$mean_replacement,
       pch = 16, col = adjustcolor("steelblue", 0.6),
       xlim = lim, ylim = lim,
       xlab = "Coach baseline residual (other stints, PPG)",
       ylab = "Coach residual in replacement season (PPG)",
       main = "Bounce: replacement vs own baseline")
  abline(0, 1, col = "red",   lty = 2, lwd = 1.5)
  abline(h = 0, v = 0, col = "grey70", lty = 3)
  text(lim[1] + 0.02, lim[2] - 0.02,
       sprintf("%.1f%% above baseline\np = %.3f", 100 * n_positive / n_coaches, t_res$p.value),
       adj = c(0, 1), cex = 0.85)

  # Distribution of per-coach bounce
  hist(comparison$bounce, breaks = 25, col = "steelblue", border = "white",
       main = "Per-coach bounce (replacement − baseline)",
       xlab = "Bounce (PPG)")
  abline(v = 0,           col = "red",    lty = 2, lwd = 2)
  abline(v = mean_bounce, col = "orange", lty = 1, lwd = 2)
  legend("topright",
         legend = c("zero", sprintf("mean = %+.3f", mean_bounce)),
         col    = c("red", "orange"), lty = c(2, 1), lwd = 2, cex = 0.85)

  cat("\n=== Top 10 largest bounces ===\n")
  print(head(comparison, 10) |>
    select(coach_name, n_replacement, mean_replacement, n_other, mean_other, bounce),
    n = Inf)

  cat("\n=== Bottom 10 (negative bounce) ===\n")
  print(tail(comparison, 10) |>
    select(coach_name, n_replacement, mean_replacement, n_other, mean_other, bounce),
    n = Inf)

  invisible(comparison)
}

# Tests whether the new-coach bounce decays in subsequent full seasons.
# Year 0 = the replacement (partial) season.
# Year 1 = first full season at the same club after taking over.
# Year 2 = second full season, etc.
# Uses season delta (season - replacement_season) to assign year, so gaps
# (coach left and returned) fall at the correct distance rather than being
# forced into consecutive slots.
test_bounce_decay <- function(pairs, coach_residuals_tbl) {
  replacements <- pairs |>
    select(coach_id = in_coach_id, coach_name = in_coach_name,
           team_season_id, replacement_season = season) |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    select(-team_season_id) |>
    distinct() |>
    group_by(coach_id, club_id) |>
    slice_min(replacement_season, n = 1, with_ties = FALSE) |>
    ungroup()

  all_stints <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg)) |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id))

  decay_data <- replacements |>
    inner_join(
      all_stints |> select(coach_id, club_id, season, n_games, partial_residual_ppg),
      by = c("coach_id", "club_id")
    ) |>
    mutate(year = season - replacement_season) |>
    filter(year >= 0)

  by_year <- decay_data |>
    group_by(year) |>
    summarize(
      n             = n(),
      mean_residual = mean(partial_residual_ppg),
      se            = sd(partial_residual_ppg) / sqrt(n),
      .groups       = "drop"
    ) |>
    filter(n >= 15)

  cat("=== Bounce Decay by Year Since Replacement ===\n")
  cat("(Year 0 = replacement/partial season)\n\n")
  print(as.data.frame(by_year), row.names = FALSE, digits = 4)

  # Paired test: year 0 vs year 1 for coaches who have both
  y0 <- decay_data |> filter(year == 0) |>
    select(coach_id, club_id, replacement_season, res_y0 = partial_residual_ppg)
  y1 <- decay_data |> filter(year == 1) |>
    select(coach_id, club_id, replacement_season, res_y1 = partial_residual_ppg)

  paired <- inner_join(y0, y1, by = c("coach_id", "club_id", "replacement_season"))

  cat(sprintf("\n=== Paired test: year 0 vs year 1 (n = %d coaches) ===\n", nrow(paired)))
  if (nrow(paired) >= 5) {
    t_res <- t.test(paired$res_y1, paired$res_y0, paired = TRUE)
    cat(sprintf("  Mean year 0: %+.4f\n", mean(paired$res_y0)))
    cat(sprintf("  Mean year 1: %+.4f\n", mean(paired$res_y1)))
    cat(sprintf("  Mean change: %+.4f\n", mean(paired$res_y1 - paired$res_y0)))
    cat(sprintf("  t = %.3f,  df = %d,  p = %.4f\n",
                t_res$statistic, t_res$parameter, t_res$p.value))
    cat(sprintf("  95%% CI: [%+.4f, %+.4f]\n",
                t_res$conf.int[1], t_res$conf.int[2]))
  } else {
    cat("  Too few matched pairs to test.\n")
  }

  # Mixed model: year as linear predictor, coach and club as random effects
  if (requireNamespace("lme4", quietly = TRUE) && nrow(decay_data) >= 20) {
    m <- lme4::lmer(
      partial_residual_ppg ~ year + (1 | coach_id) + (1 | club_id),
      data = decay_data, REML = FALSE
    )
    s       <- summary(m)
    coef_yr <- s$coefficients["year", "Estimate"]
    se_yr   <- s$coefficients["year", "Std. Error"]
    t_yr    <- s$coefficients["year", "t value"]
    p_yr    <- 2 * pnorm(-abs(t_yr))
    cat(sprintf("\n=== Mixed model: residual ~ year + (1|coach) + (1|club) ===\n"))
    cat(sprintf("  year coef: %+.4f  SE: %.4f  t: %.3f  p: %.4f\n",
                coef_yr, se_yr, t_yr, p_yr))
    if (p_yr < 0.05) {
      cat(sprintf("  Significant: residuals %s by %.3f PPG per season.\n",
                  ifelse(coef_yr < 0, "decline", "increase"), abs(coef_yr)))
    } else {
      cat("  Not significant: no clear linear decay trend.\n")
    }
  }

  # Plot: mean residual by year with 95% CI
  op <- par(mar = c(4, 4, 3, 1))
  on.exit(par(op))

  ylim <- range(c(by_year$mean_residual + 1.96 * by_year$se,
                  by_year$mean_residual - 1.96 * by_year$se, 0))
  plot(by_year$year, by_year$mean_residual,
       type = "b", pch = 16, col = "steelblue",
       ylim = ylim,
       xlab = "Year since replacement (0 = replacement season)",
       ylab = "Mean partial residual (PPG)",
       main = "Bounce decay: residual by year at club post-replacement")
  abline(h = 0, col = "red", lty = 2, lwd = 1.5)
  arrows(by_year$year,
         by_year$mean_residual - 1.96 * by_year$se,
         by_year$year,
         by_year$mean_residual + 1.96 * by_year$se,
         length = 0.05, angle = 90, code = 3, col = "steelblue")
  text(by_year$year, by_year$mean_residual + 1.96 * by_year$se + 0.01,
       paste0("n=", by_year$n), cex = 0.75, col = "grey40")

  invisible(decay_data)
}
