source("coach_attribution.R")

# Fits the enhanced_fixed model spec on arbitrary data.
fit_enhanced_fixed <- function(data) {
  d <- data |> filter(norm_weighted_value > 0)
  lm(points_per_game ~ log(norm_weighted_value) + as.factor(league), data = d)
}

# Adds predicted_ppg and residual columns to a dataset using a pre-fitted lm.
# Returns a table compatible with build_coach_residuals() from coach_attribution.R.
build_residuals_tbl_from <- function(data, lm_model) {
  d <- data |> filter(norm_weighted_value > 0)
  d |>
    mutate(
      predicted_ppg = predict(lm_model, newdata = d),
      residual      = points_per_game - predicted_ppg
    )
}

# Fits the mixed-effects model on coach stints and returns coach BLUPs.
# Quiet — no console output — for use inside a CV loop.
# Returns a data frame with columns: coach_id, blup.
# Returns an empty frame if there is insufficient data to fit the model.
extract_coach_blups <- function(coach_residuals_tbl, min_games = 10, min_stints = 3) {
  if (!requireNamespace("lme4", quietly = TRUE)) stop("lme4 required: install.packages('lme4')")

  d <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg)) |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    group_by(coach_id) |>
    filter(sum(n_games) >= min_games, n() >= min_stints) |>
    ungroup()

  if (n_distinct(d$coach_id) < 2 || n_distinct(d$club_id) < 2) {
    return(data.frame(coach_id = character(), blup = numeric(), stringsAsFactors = FALSE))
  }

  m <- suppressWarnings(
    lme4::lmer(
      partial_residual_ppg ~ (1 | club_id) + (1 | coach_id),
      data    = d,
      REML    = TRUE,
      control = lme4::lmerControl(optimizer = "bobyqa")
    )
  )

  re <- lme4::ranef(m)$coach_id
  data.frame(
    coach_id = rownames(re),
    blup     = re[, 1],
    stringsAsFactors = FALSE
  )
}

# Returns games-per-coach for each team-season in team_season_ids.
# Uses the same date-bracket attribution logic as build_coach_residuals()
# but only counts games — no residuals needed.
get_coach_game_counts <- function(team_season_ids) {
  coaches <- xx_data_cache$coaches
  matches <- xx_data_cache$matches

  purrr::map_df(team_season_ids, function(team_sid) {
    team_matches <- matches |>
      filter(home_team_id == team_sid | away_team_id == team_sid) |>
      xx_match_points_for_team(team_sid)

    attributed <- xx_assign_matches_to_coaches(
      team_matches,
      coaches |> filter(team_season_id == team_sid)
    )

    attributed |>
      filter(!is.na(coach_id)) |>
      group_by(coach_id) |>
      summarize(n_games = n(), .groups = "drop") |>
      mutate(team_season_id = team_sid)
  })
}

# Returns a games-weighted BLUP per team-season using per-coach BLUPs from training.
# Coaches absent from blup_df (unseen in training) contribute BLUP = 0.
# Teams with no coach coverage at all also get weighted_blup = 0.
weighted_blup_per_team <- function(game_counts, blup_df) {
  if (nrow(blup_df) == 0 || nrow(game_counts) == 0) {
    return(data.frame(
      team_season_id = unique(game_counts$team_season_id),
      weighted_blup  = 0,
      stringsAsFactors = FALSE
    ))
  }

  game_counts |>
    left_join(blup_df |> select(coach_id, blup), by = "coach_id") |>
    mutate(blup = coalesce(blup, 0)) |>
    group_by(team_season_id) |>
    summarize(weighted_blup = sum(blup * n_games) / sum(n_games), .groups = "drop")
}

# Leave-one-season-out CV comparing two models:
#   enhanced:   enhanced_fixed (the M3 winning model, base)
#   augmented:  enhanced_fixed + games-weighted coach BLUP from training seasons
#
# For each held-out season:
#   1. Fit enhanced_fixed on the 9 training seasons
#   2. Build coach stints from training residuals (no leakage from test season)
#   3. Fit mixed model on training stints, extract coach BLUPs
#   4. Compute games-weighted BLUP for each test team-season (unseen coaches = 0)
#   5. Augmented prediction = base prediction + weighted BLUP
#
# Returns a data frame with one row per fold plus a MEAN summary row.
cv_augmented_by_season <- function(dataset, min_games = 10, min_stints = 3) {
  d    <- dataset |> filter(norm_weighted_value > 0)
  rmse <- function(a, p) sqrt(mean((a - p)^2, na.rm = TRUE))

  rows <- lapply(sort(unique(d$season)), function(s) {
    cat(sprintf("Fold %d ... ", s))
    train <- d |> filter(season != s)
    test  <- d |> filter(season == s)

    lm_model  <- fit_enhanced_fixed(train)
    base_pred <- predict(lm_model, newdata = test)

    train_res_tbl    <- build_residuals_tbl_from(train, lm_model)
    coach_res        <- build_coach_residuals(train_res_tbl)
    blup_df          <- extract_coach_blups(coach_res, min_games, min_stints)
    test_game_counts <- get_coach_game_counts(test$team_season_id)
    test_blups       <- weighted_blup_per_team(test_game_counts, blup_df)

    test_aug <- test |>
      mutate(base_pred = base_pred) |>
      left_join(test_blups, by = "team_season_id") |>
      mutate(
        weighted_blup  = coalesce(weighted_blup, 0),
        augmented_pred = base_pred + weighted_blup
      )

    enh_rmse <- rmse(test_aug$points_per_game, test_aug$base_pred)
    aug_rmse <- rmse(test_aug$points_per_game, test_aug$augmented_pred)
    cat(sprintf("%d training BLUPs | %d/%d test teams adjusted | RMSE %.4f -> %.4f\n",
                nrow(blup_df),
                sum(test_aug$weighted_blup != 0, na.rm = TRUE),
                nrow(test_aug),
                enh_rmse, aug_rmse))

    data.frame(
      fold        = s,
      n_test      = nrow(test_aug),
      n_adjusted  = sum(test_aug$weighted_blup != 0, na.rm = TRUE),
      enhanced    = round(enh_rmse, 4),
      augmented   = round(aug_rmse, 4),
      improvement = round(enh_rmse - aug_rmse, 4)
    )
  })

  result <- do.call(rbind, rows)
  mean_row <- data.frame(
    fold        = "MEAN",
    n_test      = NA_integer_,
    n_adjusted  = NA_integer_,
    enhanced    = round(mean(result$enhanced),    4),
    augmented   = round(mean(result$augmented),   4),
    improvement = round(mean(result$improvement), 4)
  )
  rbind(result, mean_row)
}

# Runs the full augmented model pipeline.
# Returns results invisibly; individual outputs accessible via the returned list.
run_augmented_model <- function(seasons = 2015:xx_last_data_season, min_games = 10, min_stints = 3) {
  sep <- function(t) cat("\n", strrep("=", 60), "\n", t, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD DATASET")
  dataset <- build_model_dataset(seasons)
  cat("Rows loaded:", nrow(dataset), "\n")
  cat("Leagues:    ", paste(sort(unique(dataset$league)), collapse = ", "), "\n")
  cat("Seasons:    ", min(dataset$season), "-", max(dataset$season), "\n")

  sep("STEP 2: LEAVE-ONE-SEASON-OUT CV WITH COACH BLUP")
  cat("Running", length(seasons), "folds.\n")
  cat("Each fold: lm on ~", length(seasons) - 1, "seasons, then mixed model on training stints.\n")
  cat("BLUPs are estimated from training seasons only — no data leakage.\n")
  cat("Unseen coaches in the test season default to BLUP = 0.\n\n")

  cv_results <- cv_augmented_by_season(dataset, min_games, min_stints)

  cat("\n")
  print(cv_results)

  sep("STEP 3: PAIRED T-TEST (enhanced vs augmented)")
  folds <- cv_results |>
    filter(fold != "MEAN") |>
    mutate(enhanced = as.numeric(enhanced), augmented = as.numeric(augmented))

  t_result <- t.test(folds$enhanced, folds$augmented, paired = TRUE, alternative = "greater")

  cat("H1: adding coach BLUP reduces prediction error (paired, one-tailed)\n\n")
  cat("  n folds:               ", nrow(folds), "\n")
  cat("  Mean RMSE (enhanced):  ", round(mean(folds$enhanced),  4), "\n")
  cat("  Mean RMSE (augmented): ", round(mean(folds$augmented), 4), "\n")
  cat("  Mean improvement:      ", round(mean(folds$improvement), 4), "\n")
  cat("  p-value:               ", round(t_result$p.value, 4), "\n")
  cat("  95% CI lower bound:    ", round(t_result$conf.int[1], 4), "\n\n")

  if (t_result$p.value < 0.05) {
    cat("Result: SIGNIFICANT — adding coach BLUP significantly reduces prediction error.\n")
  } else {
    cat("Result: not significant at p < 0.05 — improvement is directional only.\n")
    cat("  (This is expected given ~10 folds and modest coach variance of 8.5%.)\n")
  }

  sep("COMPLETE")
  invisible(list(
    dataset    = dataset,
    cv_results = cv_results,
    t_test     = t_result
  ))
}
