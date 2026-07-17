source("residual_analysis.R")

# Adds a team_points column to a matches table from the perspective of team_sid.
xx_match_points_for_team <- function(matches, team_sid) {
  matches |>
    mutate(
      team_points = case_when(
        home_team_id == team_sid & home_team_goals >  away_team_goals ~ 3L,
        home_team_id == team_sid & home_team_goals == away_team_goals ~ 1L,
        away_team_id == team_sid & away_team_goals >  home_team_goals ~ 3L,
        away_team_id == team_sid & away_team_goals == home_team_goals ~ 1L,
        TRUE ~ 0L
      )
    )
}

# Assigns each match to the coach whose [date_from, date_to] bracket covers match_date.
# date_from is inclusive; date_to is inclusive (NA = no upper bound).
# A match on a coach's exact date_from belongs to that coach.
# If two tenures overlap on a date (data error), the most recently appointed coach wins.
# Matches covered by no coach get NA for coach_id and coach_name.
xx_assign_matches_to_coaches <- function(team_matches, team_coaches) {
  if (nrow(team_coaches) == 0) {
    return(team_matches |> mutate(coach_id = NA_character_, coach_name = NA_character_))
  }

  attributed <- team_matches |>
    cross_join(team_coaches |> select(coach_id, coach_name, date_from, date_to)) |>
    filter(match_date >= date_from, is.na(date_to) | match_date <= date_to) |>
    group_by(match_id) |>
    slice_max(date_from, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(-date_from, -date_to)

  team_matches |>
    left_join(attributed |> select(match_id, coach_id, coach_name), by = "match_id")
}

# Builds a coach-stint level table with partial residuals.
# For each (coach, team-season), computes:
#   actual_ppg            = actual_points_in_stint / games_in_stint
#   partial_residual_ppg  = actual_ppg - predicted_ppg
# where predicted_ppg is the squad-value model's season-level prediction (constant
# within the season). Unattributed matches are excluded from both actual and expected.
# Stints where predicted_ppg is NA (6 imputation edge cases) propagate NA residuals.
# Reports attribution coverage derived from the built coach_residuals table.
# No re-processing — all counts are computed by comparing coach_residuals_tbl
# against the games_played totals in residuals_tbl.
validate_coach_coverage <- function(coach_residuals_tbl, residuals_tbl) {
  stint_summary <- coach_residuals_tbl |>
    group_by(team_season_id) |>
    summarize(
      n_coaches        = n(),
      attributed_games = sum(n_games),
      .groups          = "drop"
    )

  coverage <- residuals_tbl |>
    select(team_season_id, games_played) |>
    left_join(stint_summary, by = "team_season_id") |>
    mutate(
      has_coach        = !is.na(n_coaches),
      n_coaches        = coalesce(n_coaches, 0L),
      attributed_games = coalesce(attributed_games, 0L),
      dropped_games    = games_played - attributed_games
    )

  n_team_seasons   <- nrow(coverage)
  n_with_coach     <- sum(coverage$has_coach)
  n_multi_coach    <- sum(coverage$n_coaches > 1)
  total_games      <- sum(coverage$games_played)
  total_attributed <- sum(coverage$attributed_games)
  total_dropped    <- sum(coverage$dropped_games)

  cat("=== Coach Attribution Coverage ===\n")
  cat("Team-seasons in residuals table:  ", n_team_seasons, "\n")
  cat("Team-seasons with coach data:     ", n_with_coach,
      sprintf("(%0.1f%%)\n", 100 * n_with_coach / n_team_seasons))
  cat("Team-seasons with >1 coach:       ", n_multi_coach,
      sprintf("(%0.1f%%)\n", 100 * n_multi_coach / n_team_seasons))
  cat("\n")
  cat("Total match-slots:                ", total_games, "\n")
  cat("Attributed to a coach:            ", total_attributed,
      sprintf("(%0.1f%%)\n", 100 * total_attributed / total_games))
  cat("Dropped (no coach coverage):      ", total_dropped,
      sprintf("(%0.1f%%)\n", 100 * total_dropped / total_games))
  cat("\n")

  short_stints <- coach_residuals_tbl |>
    filter(n_games <= 5) |>
    arrange(n_games) |>
    select(coach_name, team_name, league, season, n_games)

  cat("Stints of <=5 games:              ", nrow(short_stints), "\n")
  if (nrow(short_stints) > 0) {
    print(head(short_stints, 15), n = Inf)
    if (nrow(short_stints) > 15) cat("... (", nrow(short_stints) - 15, "more not shown)\n")
  }

  invisible(list(
    n_team_seasons   = n_team_seasons,
    n_with_coach     = n_with_coach,
    n_multi_coach    = n_multi_coach,
    total_games      = total_games,
    total_attributed = total_attributed,
    total_dropped    = total_dropped,
    short_stints     = short_stints,
    coverage         = coverage
  ))
}

# Aggregates coach-stint table to one row per coach.
# Stints are games-weighted (2026-07-14, matching the mixed model): a 2-game
# caretaker spell should not count like a full season. Under the model's
# variance assumption Var(stint residual) = sigma2_game / n_games, the
# games-weighted mean is the minimum-variance estimate and its standard error
# is sqrt(sigma2_game / total_games), with sigma2_game estimated from the
# games-weighted squared deviations on n_stints - 1 df. sd_residual is the
# games-weighted SD of stint residuals (display only).
# n_clubs counts distinct clubs (Transfermarkt club URL, season stripped).
# sd_residual and se_residual are NA for coaches with only one stint.
# label names the residual's units in the histogram only — coach_strengths.R
# reuses this function for goals-per-game heads, which are not PPG.
compute_coach_stats <- function(coach_residuals_tbl, min_games = 10, min_stints = 1,
                                label = "PPG") {
  stats <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg)) |>
    group_by(coach_id, coach_name) |>
    summarize(
      n_stints      = n(),
      total_games   = sum(n_games),
      n_clubs       = n_distinct(sub("/saison_id/\\d+", "", team_season_id)),
      mean_residual = weighted.mean(partial_residual_ppg, n_games),
      sigma2_game   = sum(n_games * (partial_residual_ppg - mean_residual)^2) /
                        ifelse(n_stints > 1, n_stints - 1, NA_real_),
      sd_residual   = sqrt(sum(n_games * (partial_residual_ppg - mean_residual)^2) /
                             total_games * n_stints /
                             ifelse(n_stints > 1, n_stints - 1, NA_real_)),
      .groups       = "drop"
    ) |>
    mutate(se_residual = sqrt(sigma2_game / total_games)) |>
    select(-sigma2_game) |>
    filter(total_games >= min_games, n_stints >= min_stints) |>
    arrange(desc(mean_residual))

  cat("=== Coach-Level Statistics ===\n")
  cat("Min games threshold:   ", min_games, "\n")
  cat("Min stints threshold:  ", min_stints, "\n")
  cat("Coaches meeting threshold:", nrow(stats), "\n")
  cat("Coaches with 1 stint:  ", sum(stats$n_stints == 1), "\n")
  cat("Coaches with 3+ stints:", sum(stats$n_stints >= 3), "\n")
  cat("Coaches with 5+ stints:", sum(stats$n_stints >= 5), "\n")

  op <- par(mar = c(4, 4, 3, 1))
  on.exit(par(op))
  hist(stats$mean_residual, breaks = 30, col = "steelblue",
       main = paste0("Distribution of coach mean residuals (", label, ")"),
       xlab = paste0("Mean partial residual (", label, ")"))
  abline(v = 0, col = "red", lwd = 2, lty = 2)

  cols <- c("coach_name", "n_stints", "total_games", "n_clubs", "mean_residual", "sd_residual")
  cat("\n=== Top 15 ===\n")
  print(head(stats, 15) |> select(all_of(cols)), n = Inf)
  cat("\n=== Bottom 15 ===\n")
  print(tail(stats, 15) |> select(all_of(cols)), n = Inf)

  invisible(stats)
}

# Adds significance columns to a coach_stats table.
# One-sample t-test (H0: mean_residual = 0) from the summary stats already in
# coach_stats. With the games-weighted mean/SE this is a weighted one-sample
# t-test on n_stints - 1 df (the unweighted version was equivalent to t.test()
# on raw stints).
# Coaches with n_stints < 3 cannot be tested and receive NA for all test
# columns: on df = 1 the SE estimate can collapse to ~0 when a coach's two
# stints agree by luck, producing absurd significance claims; requiring 3+
# stints (df >= 2) matches the mixed model's min_stints convention.
# p_adj is Benjamini-Hochberg FDR correction across all testable coaches.
add_significance <- function(coach_stats, alpha = 0.05) {
  result <- coach_stats |>
    mutate(
      t_stat   = mean_residual / se_residual,
      df       = n_stints - 1,
      untestable = n_stints < 3 | is.na(se_residual) | se_residual == 0,
      p_value  = if_else(untestable, NA_real_, 2 * pt(-abs(t_stat), df = df)),
      ci_lower = if_else(untestable, NA_real_, mean_residual - qt(0.975, df = pmax(df, 1)) * se_residual),
      ci_upper = if_else(untestable, NA_real_, mean_residual + qt(0.975, df = pmax(df, 1)) * se_residual)
    ) |>
    select(-untestable) |>
    mutate(
      p_adj       = p.adjust(p_value, method = "BH"),
      significant = !is.na(p_adj) & p_adj < alpha
    ) |>
    select(-t_stat, -df) |>
    arrange(desc(mean_residual))

  n_testable    <- sum(!is.na(result$p_value))
  n_significant <- sum(result$significant, na.rm = TRUE)

  cat("=== Significance Testing (FDR alpha =", alpha, ") ===\n")
  cat("Coaches tested (n_stints >= 3): ", n_testable, "\n")
  cat("Significant after FDR:          ", n_significant, "\n\n")

  sig <- result |>
    filter(significant) |>
    select(coach_name, n_stints, total_games, n_clubs,
           mean_residual, ci_lower, ci_upper, p_adj)

  cat("=== Significant coaches ===\n")
  print(sig, n = Inf)

  invisible(result)
}

# Fits a mixed-effects model decomposing partial_residual_ppg into club and coach
# variance components. Uses ML (not REML) for the LRT comparison.
# Coach BLUPs (Best Linear Unbiased Predictors) serve as shrinkage-adjusted
# rankings — sparse coaches are automatically pulled toward zero.
#
# Stints are weighted by n_games (2026-07-14): a per-game residual over 2 games
# has ~19x the sampling variance of one over 38, and unweighted fits let brief
# caretaker stints count like full seasons. The estimated variance function is
# Var(stint) = 0.014 + 1.50/n — match noise dwarfs the stint-level shock, so
# inverse-variance weights are ~proportional to n_games (saturating n/(n+k)
# weights with the fitted k = 110 give a rank correlation of 0.998 with plain
# n_games and were less stable). Games-weighted BLUPs also predicted held-out
# stints better than unweighted in an even/odd-season split test, and match the
# games-weighted quality refits validated by cr_payoff_validation(). Caveat:
# stint length is itself an outcome of performance (sackings), so weighting
# slightly downweights each coach's truncated bad spells; the OOS test says the
# noise reduction outweighs that selection tilt.
fit_mixed_model <- function(coach_residuals_tbl, min_games = 10, min_stints = 3) {
  if (!requireNamespace("lme4", quietly = TRUE)) stop("lme4 required: install.packages('lme4')")

  d <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg)) |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    group_by(coach_id) |>
    filter(sum(n_games) >= min_games, n() >= min_stints) |>
    ungroup()

  cat("Observations:   ", nrow(d), "\n")
  cat("Unique coaches: ", n_distinct(d$coach_id), "\n")
  cat("Unique clubs:   ", n_distinct(d$club_id), "\n\n")

  m_null <- lme4::lmer(partial_residual_ppg ~ (1 | club_id),
                       data = d, weights = n_games, REML = FALSE)
  m_full <- lme4::lmer(partial_residual_ppg ~ (1 | club_id) + (1 | coach_id),
                       data = d, weights = n_games, REML = FALSE)

  ll_null  <- as.numeric(stats::logLik(m_null))
  ll_full  <- as.numeric(stats::logLik(m_full))
  df_null  <- attr(stats::logLik(m_null), "df")
  df_full  <- attr(stats::logLik(m_full), "df")
  chi_sq   <- 2 * (ll_full - ll_null)
  df_lrt   <- df_full - df_null
  p_lrt    <- pchisq(chi_sq, df = df_lrt, lower.tail = FALSE)

  vc_raw    <- as.data.frame(lme4::VarCorr(m_full))
  vc        <- vc_raw[, c("grp", "vcov", "sdcor")]
  # with weights = n_games the residual vcov is per-game: Var(stint) = vcov/n.
  # For the shares, put the residual on the stint scale at the mean stint length.
  vc$vcov_stint <- ifelse(vc$grp == "Residual", vc$vcov / mean(d$n_games), vc$vcov)
  vc$pct_variance <- round(100 * vc$vcov_stint / sum(vc$vcov_stint), 1)

  cat("=== Variance Components ===\n")
  cat("  (residual vcov is per-game; %% shares use the stint-scale residual\n")
  cat(sprintf("   at the mean stint length of %.1f games)\n", mean(d$n_games)))
  for (i in seq_len(nrow(vc))) {
    cat(sprintf("  %-12s  var = %.4f  sd = %.4f  (%0.1f%% of total)\n",
                vc$grp[i], vc$vcov[i], vc$sdcor[i], vc$pct_variance[i]))
  }
  cat("\n=== Likelihood Ratio Test (coach variance = 0) ===\n")
  cat(sprintf("  Chi-sq = %.3f  df = %d  p = %.4f\n", chi_sq, df_lrt, p_lrt))

  re        <- lme4::ranef(m_full)$coach_id
  blup_df   <- data.frame(
    coach_id = rownames(re),
    blup     = re[, 1],
    stringsAsFactors = FALSE
  )

  coach_meta <- d |>
    group_by(coach_id) |>
    summarize(
      coach_name  = coach_name[1],
      n_stints    = n(),
      total_games = sum(n_games),
      n_clubs     = n_distinct(club_id),
      .groups     = "drop"
    )

  coach_blups <- merge(blup_df, coach_meta, by = "coach_id", all.x = TRUE)
  coach_blups <- coach_blups[order(-coach_blups$blup), ]

  cols <- c("coach_name", "n_stints", "total_games", "n_clubs", "blup")
  cat("\n=== Top 15 (BLUP) ===\n")
  print(head(coach_blups[, cols], 15), row.names = FALSE)
  cat("\n=== Bottom 15 (BLUP) ===\n")
  print(tail(coach_blups[, cols], 15), row.names = FALSE)

  invisible(list(
    model_null     = m_null,
    model_full     = m_full,
    lrt            = list(chi_sq = chi_sq, df = df_lrt, p = p_lrt),
    var_components = vc,
    coach_blups    = coach_blups
  ))
}

# Tests whether partial_residual_ppg declines over successive seasons at the same club.
# days_into_season = date_from minus the team's first match date that season.
# Negative values mean the coach was appointed before the season started.
# max_days_into_season = 30 captures pre-season and very early appointments.
# min_days_into_season = 31 captures mid-season changes only.
# tenure_year counts seasons within the filtered population only.
test_tenure_effect <- function(coach_residuals_tbl,
                               min_days_into_season = -Inf,
                               max_days_into_season =  Inf) {
  matches <- xx_data_cache$matches

  first_match_dates <- bind_rows(
    matches |> select(team_season_id = home_team_id, match_date),
    matches |> select(team_season_id = away_team_id,  match_date)
  ) |>
    filter(!is.na(match_date)) |>
    group_by(team_season_id) |>
    summarize(first_match_date = min(match_date), .groups = "drop")

  d <- coach_residuals_tbl |>
    filter(!is.na(partial_residual_ppg), !is.na(date_from)) |>
    left_join(first_match_dates, by = "team_season_id") |>
    mutate(days_into_season = as.numeric(date_from - first_match_date)) |>
    filter(days_into_season >= min_days_into_season,
           days_into_season <= max_days_into_season) |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    arrange(coach_id, club_id, season) |>
    group_by(coach_id, club_id) |>
    mutate(tenure_year = row_number()) |>
    ungroup()

  label <- sprintf("days_into_season in [%s, %s]",
                   ifelse(is.infinite(min_days_into_season), "-Inf", min_days_into_season),
                   ifelse(is.infinite(max_days_into_season),  "Inf", max_days_into_season))
  cat(sprintf("Stints (%s): %d\n\n", label, nrow(d)))

  by_year <- d |>
    group_by(tenure_year) |>
    summarize(
      n             = n(),
      mean_residual = mean(partial_residual_ppg),
      se            = sd(partial_residual_ppg) / sqrt(n),
      .groups       = "drop"
    ) |>
    filter(n >= 10)

  cat("=== Mean Residual by Tenure Year (n >= 10) ===\n")
  print(as.data.frame(by_year), row.names = FALSE)

  op <- par(mar = c(4, 4, 3, 1))
  on.exit(par(op))

  plot(by_year$tenure_year, by_year$mean_residual,
       type = "b", pch = 16, col = "steelblue", ylim = range(c(0, by_year$mean_residual + 1.96 * by_year$se, by_year$mean_residual - 1.96 * by_year$se)),
       xlab = "Tenure year at club", ylab = "Mean partial residual (PPG)",
       main = "Residual by tenure year (raw means ± 95% CI)")
  abline(h = 0, col = "red", lty = 2, lwd = 1.5)
  arrows(by_year$tenure_year,
         by_year$mean_residual - 1.96 * by_year$se,
         by_year$tenure_year,
         by_year$mean_residual + 1.96 * by_year$se,
         length = 0.05, angle = 90, code = 3, col = "steelblue")

  if (!requireNamespace("lme4", quietly = TRUE)) stop("lme4 required")
  model <- lme4::lmer(
    partial_residual_ppg ~ tenure_year + (1 | coach_id) + (1 | club_id),
    data = d, REML = FALSE
  )
  s         <- summary(model)
  coef_val  <- s$coefficients["tenure_year", "Estimate"]
  se_val    <- s$coefficients["tenure_year", "Std. Error"]
  t_val     <- s$coefficients["tenure_year", "t value"]

  # lmer does not provide p-values by default; use normal approximation (large n)
  p_val     <- 2 * pnorm(-abs(t_val))

  cat("\n=== Mixed model: residual ~ tenure_year + (1|coach) + (1|club) ===\n")
  cat(sprintf("  tenure_year coef: %+.4f\n", coef_val))
  cat(sprintf("  SE:               %.4f\n",  se_val))
  cat(sprintf("  t:                %.3f\n",  t_val))
  cat(sprintf("  p (normal approx):%.4f\n",  p_val))
  if (p_val < 0.05) {
    cat(sprintf("  Significant: residuals %s by %.3f PPG per season of tenure.\n",
                ifelse(coef_val < 0, "decline", "increase"), abs(coef_val)))
  } else {
    cat("  Not significant: no clear within-tenure trend.\n")
  }

  invisible(list(by_year = by_year, model = model,
                 coef = coef_val, se = se_val, p = p_val))
}

# Drops team-seasons where less than min_coverage% of minutes were played by
# players carrying a market value — the residual is unreliable when the squad
# is largely unvalued. Extracted from build_coach_residuals() (2026-07-16) so
# the Layer A goal models in coach_strengths.R filter on identical rows.
xx_filter_value_coverage <- function(team_season_tbl, min_coverage = 80) {
  coverage <- xx_data_cache$players |>
    group_by(team_season_id) |>
    summarize(
      total_minutes  = sum(minutes_played, na.rm = TRUE),
      valued_minutes = sum(minutes_played[!is.na(player_market_value_euro)], na.rm = TRUE),
      pct_covered    = 100 * valued_minutes / total_minutes,
      .groups        = "drop"
    )

  filtered <- team_season_tbl |>
    left_join(coverage, by = "team_season_id") |>
    filter(is.na(pct_covered) | pct_covered >= min_coverage)

  n_dropped <- nrow(team_season_tbl) - nrow(filtered)
  cat(sprintf(
    "Coverage filter (>= %d%%): %d team-season(s) dropped, %d retained.\n",
    min_coverage, n_dropped, nrow(filtered)
  ))

  filtered
}

build_coach_residuals <- function(residuals_tbl, min_coverage = 80) {
  coaches <- xx_data_cache$coaches
  matches <- xx_data_cache$matches

  residuals_filtered <- xx_filter_value_coverage(residuals_tbl, min_coverage = min_coverage)

  purrr::map_df(residuals_filtered$team_season_id, function(team_sid) {
    meta <- residuals_tbl |> filter(team_season_id == team_sid)

    team_matches <- matches |>
      filter(home_team_id == team_sid | away_team_id == team_sid) |>
      xx_match_points_for_team(team_sid)

    attributed <- xx_assign_matches_to_coaches(
      team_matches,
      coaches |> filter(team_season_id == team_sid)
    )

    # one row per coach: a sacked-and-reappointed coach has two tenure
    # brackets in coaches.rds, and joining both would duplicate the stint
    # row (the attribution above already totals all their matches once) —
    # keep the earliest date_from
    coach_dates <- coaches |>
      filter(team_season_id == team_sid) |>
      arrange(date_from) |>
      distinct(coach_id, .keep_all = TRUE) |>
      select(coach_id, date_from)

    attributed |>
      filter(!is.na(coach_id)) |>
      group_by(coach_id, coach_name) |>
      summarize(
        n_games       = n(),
        actual_points = sum(team_points),
        .groups       = "drop"
      ) |>
      left_join(coach_dates, by = "coach_id") |>
      mutate(
        team_season_id       = team_sid,
        team_name            = meta$team_name,
        league               = meta$league,
        season               = meta$season,
        predicted_ppg        = meta$predicted_ppg,
        actual_ppg           = actual_points / n_games,
        partial_residual_ppg = actual_ppg - predicted_ppg
      ) |>
      select(
        coach_id, coach_name,
        team_season_id, team_name, league, season,
        date_from, n_games, actual_points, actual_ppg,
        predicted_ppg, partial_residual_ppg
      )
  })
}

# Converts BLUP rankings to a 0-100 numeric score and letter grade.
# The mean BLUP maps to mean_score (default 75 = C+) and each SD of BLUPs
# maps to sd_score points (default 10), so the numeric distribution is a
# bell curve centred at 75. Standard US letter grade cutoffs are applied.
# Pass m5$mixed$coach_blups as input.
grade_coaches <- function(coach_blups, mean_score = 75, sd_score = 10) {
  coach_blups <- dplyr::as_tibble(coach_blups)
  z_mean <- mean(coach_blups$blup)
  z_sd   <- sd(coach_blups$blup)

  to_letter <- function(s) {
    dplyr::case_when(
      s >= 97 ~ "A+",
      s >= 93 ~ "A",
      s >= 90 ~ "A-",
      s >= 87 ~ "B+",
      s >= 83 ~ "B",
      s >= 80 ~ "B-",
      s >= 77 ~ "C+",
      s >= 73 ~ "C",
      s >= 70 ~ "C-",
      s >= 67 ~ "D+",
      s >= 63 ~ "D",
      s >= 60 ~ "D-",
      TRUE    ~ "F"
    )
  }

  result <- coach_blups |>
    dplyr::mutate(
      numeric_grade = pmin(100, pmax(0, round(mean_score + ((blup - z_mean) / z_sd) * sd_score, 1))),
      letter_grade  = to_letter(numeric_grade)
    ) |>
    dplyr::arrange(desc(numeric_grade))

  cat("=== Coach Grades (mean =", mean_score, ", SD =", sd_score, ") ===\n")
  print(result |> dplyr::select(coach_name, n_stints, total_games, n_clubs,
                                 blup, numeric_grade, letter_grade), n = Inf)

  cat("\n=== Grade Distribution ===\n")
  dist <- result |>
    dplyr::count(letter_grade) |>
    dplyr::mutate(pct = round(100 * n / sum(n), 1)) |>
    dplyr::arrange(desc(letter_grade))
  print(dist, n = Inf)

  invisible(result)
}

# Grades both saved BLUP cuts and writes coach_grades_top5.rds /
# coach_grades_14league.rds to data/results/ for the website export
# (Docs/Website_Design.md sec. 6.2, Website_Implementation_Plan.md Phase 0.1).
# rank is the coach's position within the cut, ordered by BLUP descending.
#
# min_games_graded is a display certification bar, not a model input: coaches
# below it keep their BLUP (and stay in the mixed model) but receive no grade,
# no leaderboard slot, and no recommender-pool entry. Added 2026-07-14 after
# the weighting review: thin records whose good long stints survive while bad
# short stints are (correctly) down-weighted can rank high on a BLUP the data
# can't distinguish from luck, and every score-side penalty we tested degraded
# out-of-sample prediction. The grade curve is re-fit on the survivors.
# Exemption: coaches significant after FDR (coach_ranked_<cut>.rds) are graded
# regardless of games — significance is itself sufficient evidence, and the
# bar exists to filter records the data can't distinguish from luck. As of
# 2026-07-14 the exemption re-admits exactly one coach (Xavi, 103 games).
save_coach_grades <- function(results_dir = "data/results", min_games_graded = 109) {
  cuts <- c(top5 = "coach_blups_top5.rds", `14league` = "coach_blups_14league.rds")
  out <- lapply(names(cuts), function(cut) {
    blups <- readRDS(file.path(results_dir, cuts[[cut]]))
    ranked <- readRDS(file.path(results_dir, paste0("coach_ranked_", cut, ".rds")))
    sig_ids <- ranked$coach_id[!is.na(ranked$significant) & ranked$significant]
    eligible <- blups |>
      dplyr::filter(total_games >= min_games_graded | coach_id %in% sig_ids)
    cat(sprintf("[%s] certification bar >= %d games (or FDR-significant): grading %d of %d coaches\n",
                cut, min_games_graded, nrow(eligible), nrow(blups)))
    graded <- grade_coaches(eligible) |>
      dplyr::mutate(rank = dplyr::row_number()) |>
      dplyr::select(coach_id, coach_name, blup, numeric_grade, letter_grade,
                    rank, n_stints, total_games, n_clubs)
    saveRDS(graded, file.path(results_dir, paste0("coach_grades_", cut, ".rds")))
    graded
  })
  names(out) <- names(cuts)
  invisible(out)
}

# Runs the full Milestone 5 pipeline in order.
# residuals_tbl should come from run_milestone4() or compute_residuals().
# min_coverage: drop team-seasons where <X% of minutes have valued players (default 80).
# min_games / min_stints: thresholds for coach stats and mixed model.
run_milestone5 <- function(residuals_tbl,
                           min_coverage = 80,
                           min_games    = 10,
                           min_stints   = 3) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD COACH RESIDUALS")
  coach_residuals <- build_coach_residuals(residuals_tbl, min_coverage = min_coverage)
  cat("Stints built:", nrow(coach_residuals), "\n")
  cat("Unique coaches:", n_distinct(coach_residuals$coach_id), "\n")

  sep("STEP 2: VALIDATE COACH COVERAGE")
  coverage <- validate_coach_coverage(coach_residuals, residuals_tbl)

  sep("STEP 3: COACH-LEVEL STATISTICS")
  coach_stats <- compute_coach_stats(coach_residuals, min_games = min_games, min_stints = 1)

  sep("STEP 4: SIGNIFICANCE TESTING")
  coach_ranked <- add_significance(coach_stats)

  sep("STEP 5: MIXED-EFFECTS MODEL")
  mixed <- fit_mixed_model(coach_residuals, min_games = min_games, min_stints = min_stints)

  sep("MILESTONE 5 COMPLETE")
  n_sig <- sum(coach_ranked$significant, na.rm = TRUE)
  cat("Coaches ranked (min", min_games, "games):", nrow(coach_stats), "\n")
  cat("Significant after FDR:              ", n_sig, "\n")
  cat("Coach variance p (LRT):             ", round(mixed$lrt$p, 4), "\n")
  top1 <- mixed$coach_blups[1, ]
  cat("Top coach (BLUP):                   ", top1$coach_name,
      sprintf("(+%.3f PPG, %d stints)\n", top1$blup, top1$n_stints))

  invisible(list(
    coach_residuals = coach_residuals,
    coverage        = coverage,
    coach_stats     = coach_stats,
    coach_ranked    = coach_ranked,
    mixed           = mixed
  ))
}
