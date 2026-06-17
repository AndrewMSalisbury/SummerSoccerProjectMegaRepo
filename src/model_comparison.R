source("tabler.R")

# Assembles all league-seasons into one pooled data frame ready for regression.
# Squad values are normalized within each league-season (divided by the season mean)
# so that a value of 1.0 = league-average squad that season.
# Points are converted to points-per-game to make Bundesliga (34 games) comparable
# to the four 38-game leagues.
# Plots distributions and relationships to inform the log-transform decision.
# Top row: histograms of both metrics (raw then log).
# Bottom row: scatter vs points_per_game with regression line (raw then log).
# Look for: right skew in histograms and curvature in scatter plots as signals
# that log-transforming the predictors would improve model fit.
check_distributions <- function(dataset) {
  log_safe <- dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)
  n_dropped <- nrow(dataset) - nrow(log_safe)
  if (n_dropped > 0) message(n_dropped, " row(s) with non-positive normalized values excluded from log plots.")

  op <- par(mfrow = c(2, 4), mar = c(4, 4, 3, 1))
  on.exit(par(op))

  hist(dataset$norm_total_value,             breaks = 30, col = "steelblue", main = "Total value (raw)",     xlab = "norm_total_value")
  hist(dataset$norm_weighted_value,          breaks = 30, col = "steelblue", main = "Weighted value (raw)",  xlab = "norm_weighted_value")
  hist(log(log_safe$norm_total_value),       breaks = 30, col = "coral",     main = "Total value (log)",     xlab = "log(norm_total_value)")
  hist(log(log_safe$norm_weighted_value),    breaks = 30, col = "coral",     main = "Weighted value (log)",  xlab = "log(norm_weighted_value)")

  plot(dataset$norm_total_value, dataset$points_per_game,
       main = "Total value vs PPG (raw)", xlab = "norm_total_value", ylab = "PPG",
       pch = 16, col = rgb(0.2, 0.4, 0.8, 0.4))
  abline(lm(points_per_game ~ norm_total_value, dataset), col = "red", lwd = 2)

  plot(dataset$norm_weighted_value, dataset$points_per_game,
       main = "Weighted value vs PPG (raw)", xlab = "norm_weighted_value", ylab = "PPG",
       pch = 16, col = rgb(0.2, 0.4, 0.8, 0.4))
  abline(lm(points_per_game ~ norm_weighted_value, dataset), col = "red", lwd = 2)

  plot(log(log_safe$norm_total_value), log_safe$points_per_game,
       main = "Total value vs PPG (log)", xlab = "log(norm_total_value)", ylab = "PPG",
       pch = 16, col = rgb(0.8, 0.3, 0.1, 0.4))
  abline(lm(points_per_game ~ log(norm_total_value), log_safe), col = "red", lwd = 2)

  plot(log(log_safe$norm_weighted_value), log_safe$points_per_game,
       main = "Weighted value vs PPG (log)", xlab = "log(norm_weighted_value)", ylab = "PPG",
       pch = 16, col = rgb(0.8, 0.3, 0.1, 0.4))
  abline(lm(points_per_game ~ log(norm_weighted_value), log_safe), col = "red", lwd = 2)
}

# Fits all 6 models: 3 specs (baseline, enhanced, combined) x 2 approaches
# (PPG-only and PPG + league fixed effects).
# With log_transform = TRUE (recommended based on distribution check), both
# squad value predictors are log-transformed before fitting.
fit_models <- function(dataset, log_transform = TRUE) {
  d <- if (log_transform) {
    dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)
  } else {
    dataset
  }

  tv <- if (log_transform) "log(norm_total_value)"   else "norm_total_value"
  wv <- if (log_transform) "log(norm_weighted_value)" else "norm_weighted_value"

  f <- function(...) as.formula(paste("points_per_game ~", paste(..., sep = " + ")))

  list(
    baseline_ppg   = lm(f(tv,           "is_b_team"),                        data = d),
    enhanced_ppg   = lm(f(wv,           "is_b_team"),                        data = d),
    combined_ppg   = lm(f(tv, wv,       "is_b_team"),                        data = d),
    baseline_fixed = lm(f(tv,           "as.factor(league)", "is_b_team"),   data = d),
    enhanced_fixed = lm(f(wv,           "as.factor(league)", "is_b_team"),   data = d),
    combined_fixed = lm(f(tv, wv,       "as.factor(league)", "is_b_team"),   data = d)
  )
}

# Returns a comparison table of R², adjusted R², RMSE, and MAE for each model.
in_sample_metrics <- function(models) {
  rows <- lapply(names(models), function(name) {
    m   <- models[[name]]
    s   <- summary(m)
    res <- residuals(m)
    data.frame(
      model     = name,
      r2        = round(s$r.squared,     4),
      adj_r2    = round(s$adj.r.squared, 4),
      rmse      = round(sqrt(mean(res^2)), 4),
      mae       = round(mean(abs(res)),    4),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# For each season, trains on all other seasons and predicts the held-out season.
# Uses PPG-only model specs so results are comparable with cv_by_league.
cv_by_season <- function(dataset, log_transform = TRUE) {
  d <- if (log_transform) {
    dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)
  } else {
    dataset
  }

  tv <- if (log_transform) "log(norm_total_value)"    else "norm_total_value"
  wv <- if (log_transform) "log(norm_weighted_value)" else "norm_weighted_value"
  f  <- function(...) as.formula(paste("points_per_game ~", paste(..., sep = " + ")))
  rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2, na.rm = TRUE))

  rows <- lapply(sort(unique(d$season)), function(s) {
    train <- d |> filter(season != s)
    test  <- d |> filter(season == s)
    data.frame(
      fold     = s,
      baseline = rmse(test$points_per_game, predict(lm(f(tv,      "is_b_team"), data = train), test)),
      enhanced = rmse(test$points_per_game, predict(lm(f(wv,      "is_b_team"), data = train), test)),
      combined = rmse(test$points_per_game, predict(lm(f(tv, wv,  "is_b_team"), data = train), test))
    )
  })
  result <- do.call(rbind, rows)
  summary_row <- data.frame(fold = "MEAN",
                             baseline = round(mean(result$baseline), 4),
                             enhanced = round(mean(result$enhanced), 4),
                             combined = round(mean(result$combined), 4))
  rbind(result |> mutate(across(c(baseline, enhanced, combined), \(x) round(x, 4))),
        summary_row)
}

# For each league, trains on all other leagues and predicts the held-out league.
# League fixed effects cannot be used here — the held-out league is unseen at
# training time, so this CV always uses PPG-only specs.
cv_by_league <- function(dataset, log_transform = TRUE) {
  d <- if (log_transform) {
    dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)
  } else {
    dataset
  }

  tv <- if (log_transform) "log(norm_total_value)"    else "norm_total_value"
  wv <- if (log_transform) "log(norm_weighted_value)" else "norm_weighted_value"
  f  <- function(...) as.formula(paste("points_per_game ~", paste(..., sep = " + ")))
  rmse <- function(actual, predicted) sqrt(mean((actual - predicted)^2, na.rm = TRUE))

  rows <- lapply(sort(unique(d$league)), function(lg) {
    train <- d |> filter(league != lg)
    test  <- d |> filter(league == lg)
    f2 <- function(...) {
      terms <- c(..., if (any(train$is_b_team)) "is_b_team" else NULL)
      as.formula(paste("points_per_game ~", paste(terms, collapse = " + ")))
    }
    data.frame(
      fold     = lg,
      baseline = rmse(test$points_per_game, predict(lm(f2(tv),     data = train), test)),
      enhanced = rmse(test$points_per_game, predict(lm(f2(wv),     data = train), test)),
      combined = rmse(test$points_per_game, predict(lm(f2(tv, wv), data = train), test))
    )
  })
  result <- do.call(rbind, rows)
  summary_row <- data.frame(fold = "MEAN",
                             baseline = round(mean(result$baseline), 4),
                             enhanced = round(mean(result$enhanced), 4),
                             combined = round(mean(result$combined), 4))
  rbind(result |> mutate(across(c(baseline, enhanced, combined), \(x) round(x, 4))),
        summary_row)
}

# Paired t-tests on per-fold RMSE: baseline vs enhanced.
# Tests whether the enhanced model's lower RMSE is statistically significant
# or could be due to chance. Runs on both CV strategies.
# With 20 leagues, this CV now has 20 folds and is a meaningful test.
significance_tests <- function(cv_season, cv_league) {
  season_folds <- cv_season |> filter(fold != "MEAN") |>
    mutate(baseline = as.numeric(baseline), enhanced = as.numeric(enhanced))
  league_folds <- cv_league |> filter(fold != "MEAN") |>
    mutate(baseline = as.numeric(baseline), enhanced = as.numeric(enhanced))

  season_test <- t.test(season_folds$baseline, season_folds$enhanced,
                        paired = TRUE, alternative = "greater")
  league_test <- t.test(league_folds$baseline, league_folds$enhanced,
                        paired = TRUE, alternative = "greater")

  cat("=== Paired t-test: Baseline vs Enhanced RMSE ===\n\n")

  cat("Leave-one-season-out (n =", nrow(season_folds), "folds):\n")
  cat("  Mean RMSE improvement (baseline - enhanced):",
      round(mean(season_folds$baseline - season_folds$enhanced), 4), "\n")
  cat("  p-value:                ", round(season_test$p.value, 4), "\n")
  cat("  95% CI lower bound:     ", round(season_test$conf.int[1], 4), "\n\n")

  cat("Leave-one-league-out (n =", nrow(league_folds), "folds):\n")
  cat("  Mean RMSE improvement (baseline - enhanced):",
      round(mean(league_folds$baseline - league_folds$enhanced), 4), "\n")
  cat("  p-value:                ", round(league_test$p.value, 4), "\n")
  cat("  95% CI lower bound:     ", round(league_test$conf.int[1], 4), "\n\n")

  season_sig <- season_test$p.value < 0.05
  league_sig <- league_test$p.value < 0.05

  cat("=== Conclusion ===\n")
  if (season_sig && league_sig) {
    cat("Both tests significant (p < 0.05). Enhanced model is the winner.\n")
  } else if (season_sig && !league_sig) {
    cat("Season CV significant; league CV not significant.\n")
    cat("Directional evidence favors enhanced across competitions.\n")
  } else if (!season_sig && league_sig) {
    cat("League CV significant; season CV not significant.\n")
  } else {
    cat("Neither test significant at p < 0.05. Improvement is directional only.\n")
  }

  invisible(list(season = season_test, league = league_test))
}

# Three sub-checks to confirm the result isn't driven by a specific slice of data:
# 1. Per-league: does enhanced beat baseline within each league individually?
# 2. Early (2015-2019) vs recent (2020-2024): does the result hold across time?
# 3. 10% threshold: pass a dataset built with build_model_dataset(min_minutes_pct = 0.10)
#    as dataset_filtered to check if restricting to players with meaningful minutes sharpens the signal.
sensitivity_analysis <- function(dataset, dataset_filtered = NULL, log_transform = TRUE) {
  prep <- function(d) {
    if (log_transform) d |> filter(norm_total_value > 0, norm_weighted_value > 0) else d
  }
  tv   <- if (log_transform) "log(norm_total_value)"    else "norm_total_value"
  wv   <- if (log_transform) "log(norm_weighted_value)" else "norm_weighted_value"
  f    <- function(...) as.formula(paste("points_per_game ~", paste(..., sep = " + ")))
  rmse <- function(actual, pred) sqrt(mean((actual - pred)^2, na.rm = TRUE))

  compare <- function(d) {
    m_base <- lm(f(tv), data = d)
    m_enh  <- lm(f(wv), data = d)
    list(baseline = rmse(d$points_per_game, predict(m_base)),
         enhanced = rmse(d$points_per_game, predict(m_enh)))
  }

  d <- prep(dataset)

  # 1. Per-league
  cat("=== 1. Per-League In-Sample RMSE ===\n")
  league_rows <- lapply(sort(unique(d$league)), function(lg) {
    r <- compare(d |> filter(league == lg))
    data.frame(league = lg,
               baseline = round(r$baseline, 4),
               enhanced = round(r$enhanced, 4),
               improvement = round(r$baseline - r$enhanced, 4),
               enhanced_wins = r$enhanced < r$baseline)
  })
  print(do.call(rbind, league_rows))

  # 2. Historical vs modern
  cat("\n=== 2. Historical (2005-2014) vs Modern (2015-2024) ===\n")
  for (rng in list(c(2005L, 2014L), c(2015L, 2024L))) {
    r <- compare(d |> filter(season >= rng[1], season <= rng[2]))
    cat(sprintf("  %d-%d  baseline=%.4f  enhanced=%.4f  improvement=%.4f\n",
                rng[1], rng[2], r$baseline, r$enhanced, r$baseline - r$enhanced))
  }

  # 3. 10% minutes threshold
  cat("\n=== 3. 10% Minutes Threshold ===\n")
  if (is.null(dataset_filtered)) {
    cat("  No filtered dataset provided. Run:\n")
    cat("    dataset_filtered <- build_model_dataset(min_minutes_pct = 0.10)\n")
    cat("  then re-run sensitivity_analysis(dataset, dataset_filtered).\n")
  } else {
    df <- prep(dataset_filtered)
    r_full <- compare(d)
    r_filt <- compare(df)
    cat(sprintf("  Full dataset:         baseline=%.4f  enhanced=%.4f  improvement=%.4f\n",
                r_full$baseline, r_full$enhanced, r_full$baseline - r_full$enhanced))
    cat(sprintf("  10%% threshold (%d rows): baseline=%.4f  enhanced=%.4f  improvement=%.4f\n",
                nrow(df), r_filt$baseline, r_filt$enhanced, r_filt$baseline - r_filt$enhanced))
    if ((r_filt$baseline - r_filt$enhanced) > (r_full$baseline - r_full$enhanced)) {
      cat("  Signal sharpened with threshold.\n")
    } else {
      cat("  Signal did not sharpen with threshold.\n")
    }
  }
}

# Diagnostic plots for the winning model:
#   1. Residuals vs fitted  — check for heteroskedasticity
#   2. Q-Q plot             — check for normality of residuals
#   3. Cook's distance      — identify unduly influential observations
# Prints a table of flagged observations (Cook's D > 4/n) with team labels.
residual_diagnostics <- function(model, dataset, log_transform = TRUE) {
  d <- if (log_transform) {
    dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)
  } else {
    dataset
  }

  res    <- residuals(model)
  fit    <- fitted(model)
  cooks  <- cooks.distance(model)
  thresh <- 4 / length(cooks)

  op <- par(mfrow = c(1, 3), mar = c(4, 4, 3, 1))
  on.exit(par(op))

  plot(fit, res,
       main = "Residuals vs Fitted", xlab = "Fitted values", ylab = "Residuals",
       pch = 16, col = rgb(0.2, 0.4, 0.8, 0.4))
  abline(h = 0, col = "red", lwd = 2)

  qqnorm(res, main = "Q-Q Plot", pch = 16, col = rgb(0.2, 0.4, 0.8, 0.4))
  qqline(res, col = "red", lwd = 2)

  plot(cooks, type = "h",
       main = "Cook's Distance", xlab = "Observation", ylab = "Cook's D",
       col = ifelse(cooks > thresh, "red", "steelblue"))
  abline(h = thresh, col = "red", lty = 2)

  influential <- which(cooks > thresh)
  cat("\n", length(influential), " observations with Cook's D > 4/n (threshold = ",
      round(thresh, 4), "):\n", sep = "")
  flagged <- if (length(influential) > 0) {
    d[influential, ] |>
      select(team_name, league, season) |>
      mutate(cooks_d  = round(cooks[influential], 4),
             residual = round(res[influential],   4)) |>
      arrange(desc(cooks_d))
  } else {
    data.frame()
  }
  print(flagged, n = Inf)
  invisible(flagged)
}

build_model_dataset <- function(seasons = 2005:2024, min_minutes_pct = 0, leagues = xx_all_leagues()) {
  all_rows <- data.frame()
  for (league_id in leagues) {
    league_name <- strsplit(league_id, split = "/")[[1]][4]
    for (season in seasons) {
      league_season_id <- xx_league_season_id(league_id, season)
      chart <- tryCatch(
        league_season_team_chart(league_season_id, min_minutes_pct = min_minutes_pct),
        error = function(e) {
          warning("Skipping ", league_name, " ", season, ": ", e$message)
          NULL
        }
      )
      if (is.null(chart) || nrow(chart) == 0) next

      chart$league  <- league_name
      chart$season  <- season
      chart$norm_total_value    <- chart$total_team_value    / mean(chart$total_team_value,    na.rm = TRUE)
      chart$norm_weighted_value <- chart$weighted_team_value / mean(chart$weighted_team_value, na.rm = TRUE)
      chart$points_per_game     <- chart$total_points / chart$games_played
      chart$is_b_team           <- grepl(" B$|Castilla|Bilbao Athletic|Mestalla|Fabril|Sevilla Atlético", chart$team_name)

      all_rows <- rbind(all_rows, chart)
    }
  }
  if (nrow(all_rows) == 0) stop("No league-seasons loaded. Ensure source_data.r is sourced and the cache is populated.")
  all_rows |>
    select(team_season_id, team_name, league, season,
           total_team_value, weighted_team_value,
           norm_total_value, norm_weighted_value,
           total_points, games_played, points_per_game,
           total_value_rank, weighted_value_rank, points_rank,
           is_b_team)
}

# Runs the full Milestone 3 analysis pipeline in order.
# Returns a named list of all results invisibly so individual outputs can be
# inspected after the run (e.g. results$metrics, results$flagged).
# log_transform is pre-decided as TRUE based on the distribution check.
# run_threshold_check = TRUE rebuilds the dataset with a 10% minutes filter
# (slow — adds one full build_model_dataset pass).
run_milestone3 <- function(seasons = 2005:2024,
                           log_transform = TRUE,
                           run_threshold_check = FALSE) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD DATASET")
  dataset <- build_model_dataset(seasons)
  cat("Rows loaded:", nrow(dataset), "\n")
  cat("Leagues:    ", paste(sort(unique(dataset$league)), collapse = ", "), "\n")
  cat("Seasons:    ", min(dataset$season), "-", max(dataset$season), "\n")

  sep("STEP 2: DISTRIBUTION CHECK")
  cat("Log-transform decision: TRUE (pre-confirmed — see session log 2026-06-05)\n")
  cat("Generating plots...\n")
  check_distributions(dataset)

  sep("STEP 3: FIT MODELS")
  models <- fit_models(dataset, log_transform = log_transform)
  cat("Models fit: ", paste(names(models), collapse = ", "), "\n")

  sep("STEP 4: IN-SAMPLE METRICS")
  metrics <- in_sample_metrics(models)
  print(metrics)

  sep("STEP 5: LEAVE-ONE-SEASON-OUT CV")
  cv_season <- cv_by_season(dataset, log_transform = log_transform)
  print(cv_season)

  sep("STEP 6: LEAVE-ONE-LEAGUE-OUT CV")
  cv_league <- cv_by_league(dataset, log_transform = log_transform)
  print(cv_league)

  sep("STEP 7: SIGNIFICANCE TESTS")
  significance_tests(cv_season, cv_league)

  sep("STEP 8: SENSITIVITY ANALYSIS")
  dataset_filtered <- if (run_threshold_check) {
    cat("Building 10% threshold dataset (this takes a few minutes)...\n")
    build_model_dataset(seasons, min_minutes_pct = 0.10)
  } else {
    cat("Skipping threshold rebuild (pass run_threshold_check = TRUE to include).\n")
    NULL
  }
  sensitivity_analysis(dataset, dataset_filtered, log_transform = log_transform)

  sep("STEP 9: RESIDUAL DIAGNOSTICS (enhanced_fixed)")
  flagged <- residual_diagnostics(models$enhanced_fixed, dataset, log_transform = log_transform)

  sep("MILESTONE 3 COMPLETE")
  cat("Winning model: enhanced_fixed\n")
  cat("  enhanced_fixed R²:   ", metrics[metrics$model == "enhanced_fixed", "r2"],   "\n")
  cat("  enhanced_fixed RMSE: ", metrics[metrics$model == "enhanced_fixed", "rmse"], "\n")
  enh_row <- cv_season[cv_season$fold == "MEAN", ]
  cat("  Out-of-sample RMSE (season CV): ", as.numeric(enh_row$enhanced), "\n")

  invisible(list(
    dataset   = dataset,
    models    = models,
    metrics   = metrics,
    cv_season = cv_season,
    cv_league = cv_league,
    flagged   = flagged
  ))
}

# Tests whether leagues with lower average squad value have worse model fit.
# Fits enhanced_fixed on the full dataset, then computes per-league RMSE and R²
# from residuals and joins to mean squad value per league.
# Prints a sorted table and two scatter plots (RMSE and R² vs log squad value).
# Returns the joined data frame invisibly.
league_value_fit_diagnostic <- function(dataset = NULL) {
  if (is.null(dataset)) dataset <- build_model_dataset()

  league_values <- dataset |>
    dplyr::group_by(league) |>
    dplyr::summarise(
      mean_squad_value_M = mean(total_team_value, na.rm = TRUE) / 1e6,
      n = dplyr::n(),
      .groups = "drop"
    )

  d <- dataset |> dplyr::filter(norm_weighted_value > 0)
  model <- lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team, data = d)
  d$resid <- residuals(model)

  league_fit <- d |>
    dplyr::group_by(league) |>
    dplyr::summarise(
      rmse = sqrt(mean(resid^2)),
      r2   = 1 - sum(resid^2) / sum((points_per_game - mean(points_per_game))^2),
      .groups = "drop"
    )

  result <- league_fit |>
    dplyr::left_join(league_values, by = "league") |>
    dplyr::arrange(mean_squad_value_M)

  print(result, n = nrow(result))

  cat(sprintf("\nCorr (log squad value vs RMSE): %.3f\n", cor(log(result$mean_squad_value_M), result$rmse)))
  cat(sprintf("Corr (log squad value vs R²):   %.3f\n", cor(log(result$mean_squad_value_M), result$r2)))

  op <- par(mfrow = c(1, 2), mar = c(5, 4, 3, 1))
  on.exit(par(op))

  plot(log(result$mean_squad_value_M), result$rmse,
       xlab = "log(mean squad value, €M)", ylab = "In-sample RMSE",
       main = "Squad Value vs RMSE", pch = 16, col = "steelblue")
  text(log(result$mean_squad_value_M), result$rmse,
       labels = result$league, cex = 0.65, pos = 4)

  plot(log(result$mean_squad_value_M), result$r2,
       xlab = "log(mean squad value, €M)", ylab = "In-sample R²",
       main = "Squad Value vs R²", pch = 16, col = "coral")
  text(log(result$mean_squad_value_M), result$r2,
       labels = result$league, cex = 0.65, pos = 4)

  invisible(result)
}
