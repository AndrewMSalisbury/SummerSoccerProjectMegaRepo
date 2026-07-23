# Prospective 2025/26 Forward Test (ft_ prefix)
# ------------------------------------------------------------------------------
# The cleanest possible "does the model work" test: the model is FROZEN at 2024
# (M3 coefficients + M5 coach BLUPs estimated only on seasons <= 2024), then used
# to predict the 2025/26 season -- a full holdout year the fit has never seen.
# Unlike leave-one-season-out CV, this is a genuine forward hold-out in time.
#
# Q1 (headline): does minutes-weighted squad value predict 2025 points out-of-time,
#     and does it still beat raw squad value on a brand-new season?
# Q2 (augmented): do the pre-computed coach BLUPs (<=2024) add prospective value --
#     i.e. do coaches the model already rated highly overperform in 2025? This is
#     the Part-4 augmented-model / Part-7 recommender question on a true future year.
#
# Pure cache/results reader. Requires 2025 data populated in the cache
# (xx_data_populate_league_seasons(2025)) and source_data.r + coach_attribution.R.

suppressMessages({ library(dplyr) })

ft_results_dir <- "data/results"

ft_metrics <- function(actual, pred) {
  ok <- is.finite(actual) & is.finite(pred)
  a <- actual[ok]; p <- pred[ok]
  sse <- sum((a - p)^2); sst <- sum((a - mean(a))^2)
  c(n = length(a),
    RMSE = sqrt(mean((a - p)^2)),
    MAE  = mean(abs(a - p)),
    R2   = 1 - sse / sst,
    cor  = cor(a, p))
}

ft_p <- function(p) if (p < 1e-4) sprintf("%.2e", p) else sprintf("%.4f", p)

run_forward_test <- function(save = TRUE) {
  # --- assemble train (<=2024) + 2025 holdout, identical schema/normalization ----
  prep <- readRDS(file.path(ft_results_dir, "mb_prep.rds"))
  ds25 <- readRDS(file.path(ft_results_dir, "ds_2025.rds"))
  full <- bind_rows(prep$ds |> select(all_of(names(ds25))), ds25)

  train <- full |> filter(season <= 2024, norm_weighted_value > 0, norm_total_value > 0)
  test  <- full |> filter(season == 2025, norm_weighted_value > 0, norm_total_value > 0)
  cat(sprintf("Train team-seasons (<=2024): %d   Holdout 2025/26: %d (%d leagues)\n",
              nrow(train), nrow(test), n_distinct(test$league)))

  # --- Q1: frozen M3 predicts the holdout year -----------------------------------
  m_base <- lm(points_per_game ~ log(norm_total_value)    + as.factor(league) + is_b_team, data = train)
  m_enh  <- lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team, data = train)
  test$pred_base <- as.numeric(predict(m_base, test))
  test$pred_enh  <- as.numeric(predict(m_enh,  test))

  mb <- ft_metrics(test$points_per_game, test$pred_base)
  me <- ft_metrics(test$points_per_game, test$pred_enh)
  cat("\n=== Q1. Frozen model -> 2025/26 holdout (PPG) ===\n")
  cat(sprintf("  %-26s RMSE %.4f  MAE %.4f  R2 %.3f  cor %.3f\n",
              "baseline (raw value)",     mb["RMSE"], mb["MAE"], mb["R2"], mb["cor"]))
  cat(sprintf("  %-26s RMSE %.4f  MAE %.4f  R2 %.3f  cor %.3f\n",
              "enhanced (minutes-wtd)",   me["RMSE"], me["MAE"], me["R2"], me["cor"]))
  cat(sprintf("  enhanced beats baseline on holdout RMSE by %.4f PPG\n", mb["RMSE"] - me["RMSE"]))
  cat(sprintf("  (reference: published LOSO-CV enhanced RMSE ~0.262; in-sample ~0.255)\n"))
  # points-scale readout
  test$pred_enh_pts <- test$pred_enh * test$games_played
  cat(sprintf("  mean absolute points error (enhanced): %.1f pts / team-season\n",
              mean(abs(test$total_points - test$pred_enh_pts), na.rm = TRUE)))

  # --- Q2: do prior (<=2024) coach BLUPs predict 2025 overperformance? -----------
  cb <- readRDS(file.path(ft_results_dir, "coach_blups_14league.rds")) |>
    select(coach_id, prior_blup = blup)

  res25 <- test |>
    mutate(predicted_ppg = pred_enh,
           residual = points_per_game - predicted_ppg,
           residual_points = residual * games_played) |>
    select(team_season_id, team_name, league, season, total_team_value,
           norm_weighted_value, total_points, games_played, points_per_game,
           predicted_ppg, residual, residual_points)

  st25 <- build_coach_residuals(res25) |>
    left_join(cb, by = "coach_id") |>
    mutate(has_prior = !is.na(prior_blup),
           prior_blup = coalesce(prior_blup, 0))

  cat(sprintf("\n=== Q2. Prior coach BLUP -> 2025 overperformance ===\n"))
  cat(sprintf("  2025 coach stints: %d  (with prior track-record BLUP: %d, %.0f%%)\n",
              nrow(st25), sum(st25$has_prior), 100 * mean(st25$has_prior)))

  # stint-level prospective test (games-weighted)
  mA <- lm(partial_residual_ppg ~ prior_blup, data = st25, weights = n_games)
  sA <- coef(summary(mA))
  cat("  --- stint level: partial_residual_ppg ~ prior_blup (games-weighted) ---\n")
  cat(sprintf("    slope = %+.3f  (SE %.3f, t %.2f, p %s)   cor = %+.3f\n",
              sA["prior_blup", 1], sA["prior_blup", 2], sA["prior_blup", 3],
              ft_p(sA["prior_blup", 4]),
              cor(st25$partial_residual_ppg, st25$prior_blup)))
  # graded-only (established coaches) sensitivity
  stg <- st25 |> filter(has_prior)
  if (nrow(stg) >= 20) {
    mg <- lm(partial_residual_ppg ~ prior_blup, data = stg, weights = n_games)
    sg <- coef(summary(mg))
    cat(sprintf("    [graded coaches only, n=%d] slope %+.3f (t %.2f, p %s)\n",
                nrow(stg), sg["prior_blup", 1], sg["prior_blup", 3], ft_p(sg["prior_blup", 4])))
  }

  # team-season level: does adding the games-weighted prior BLUP lower holdout RMSE?
  tw <- st25 |> group_by(team_season_id) |>
    summarize(tw_blup = sum(n_games * prior_blup) / sum(n_games), .groups = "drop")
  test2 <- test |> left_join(tw, by = "team_season_id") |>
    mutate(tw_blup = coalesce(tw_blup, 0),
           pred_aug = pred_enh + tw_blup)
  m_noaug <- ft_metrics(test2$points_per_game, test2$pred_enh)
  m_aug   <- ft_metrics(test2$points_per_game, test2$pred_aug)
  cat("  --- team-season level: does +coach BLUP improve the 2025 forecast? ---\n")
  cat(sprintf("    enhanced alone     RMSE %.4f  R2 %.3f\n", m_noaug["RMSE"], m_noaug["R2"]))
  cat(sprintf("    enhanced + BLUP    RMSE %.4f  R2 %.3f   (%s by %.4f)\n",
              m_aug["RMSE"], m_aug["R2"],
              ifelse(m_aug["RMSE"] < m_noaug["RMSE"], "improved", "worsened"),
              abs(m_noaug["RMSE"] - m_aug["RMSE"])))

  # --- Bonus: 2025 deserved table + who beat expectation --------------------------
  dt25 <- res25 |>
    mutate(expected_points = predicted_ppg * games_played) |>
    group_by(league) |>
    mutate(actual_rank = rank(-total_points, ties.method = "min"),
           expected_rank = rank(-expected_points, ties.method = "min"),
           rank_delta = expected_rank - actual_rank,
           over_points = total_points - expected_points) |>
    ungroup() |> arrange(desc(over_points))
  cat("\n=== 2025/26 biggest OVER-achievers vs squad value ===\n")
  print(as.data.frame(dt25 |> transmute(league, team = team_name, pts = total_points,
    xPts = round(expected_points, 1), `+/-Pos` = rank_delta,
    over = round(over_points, 1)) |> head(12)), row.names = FALSE)
  cat("\n=== 2025/26 biggest UNDER-achievers ===\n")
  print(as.data.frame(dt25 |> arrange(over_points) |> transmute(league, team = team_name,
    pts = total_points, xPts = round(expected_points, 1), `+/-Pos` = rank_delta,
    over = round(over_points, 1)) |> head(12)), row.names = FALSE)

  cat("\n=== Coaches who beat expectation most in 2025/26 (>= 20 games) ===\n")
  print(as.data.frame(st25 |> filter(n_games >= 20) |> arrange(desc(partial_residual_ppg)) |>
    transmute(coach_name, team = team_name, league, n_games,
              resid_ppg = round(partial_residual_ppg, 3),
              prior_blup = round(prior_blup, 3)) |> head(12)), row.names = FALSE)

  if (save) {
    saveRDS(list(holdout = test2, stints = st25, deserved_2025 = dt25,
                 q1_base = mb, q1_enh = me, q2_stint = sA, q2_rmse = c(m_noaug, m_aug)),
            file.path(ft_results_dir, "forward_test.rds"))
    cat("\nSaved data/results/forward_test.rds\n")
  }
  invisible(test2)
}
