source("coach_fit.R")   # -> coach_attribution.R chain, plus pa_read / ss_big5_leagues
                        #    and cf_season_match_coaches() for the phase-2 xG cut

# Layer A of the coach descriptive profile (Docs/Coach_Descriptive_Profile_Design.md,
# phase 1): splits the M4/M5 overperformance residual into an attacking and a
# defensive half by re-fitting the M3 model with goals scored / goals conceded
# per game as the response instead of points per game.
#
# Honesty label (design sec. 0): this layer re-slices a residual the project
# already trusts, on the same right-hand side. It makes no new attribution leap
# beyond the one M5 already makes, so an offence/defence tilt can be stated
# plainly. It is goals-based and therefore covers the full 2005-2024 span and
# all 14 leagues (no SofaScore dependency).
#
# Phase 2 (the xG cut — process vs outcome) is at the bottom of this file and
# is big-5 / 2022-2024 only: a recent-form lens layered on the full-span goals
# cut, not a career verdict.

# Leagues in each published cut. The top-5 cut is the five leagues the site
# grades separately because they share a competitive level; "14league" is the
# full active set (xx_all_leagues()).
cs_cut_leagues <- function(cut = c("top5", "14league")) {
  cut <- match.arg(cut)
  if (cut == "top5") {
    c(
      xx_league_id_PREMIER_LEAGUE,
      xx_league_id_LIGUE_1,
      xx_league_id_LA_LIGA,
      xx_league_id_SERIE_A,
      xx_league_id_BUNDESLIGA
    )
  } else {
    xx_all_leagues()
  }
}

# Goals scored and conceded per team-season, counting only the league's own
# matches (matches.rds is keyed by league_season_id, so the same competition
# scope as total_points from xx_team_points()).
cs_team_season_goals <- function(matches = xx_data_cache$matches) {
  bind_rows(
    matches |> select(team_season_id = home_team_id,
                      gf = home_team_goals, ga = away_team_goals),
    matches |> select(team_season_id = away_team_id,
                      gf = away_team_goals, ga = home_team_goals)
  ) |>
    filter(!is.na(gf), !is.na(ga)) |>
    group_by(team_season_id) |>
    summarize(goals_for = sum(gf), goals_against = sum(ga), .groups = "drop")
}

# Adds team_goals_for / team_goals_against to a matches table from the
# perspective of team_sid (the goals analogue of xx_match_points_for_team()).
cs_match_goals_for_team <- function(matches, team_sid) {
  matches |>
    mutate(
      team_goals_for = if_else(home_team_id == team_sid,
                               home_team_goals, away_team_goals),
      team_goals_against = if_else(home_team_id == team_sid,
                                   away_team_goals, home_team_goals)
    )
}

# The two head models. Same right-hand side as compute_residuals() — same
# predictors, same fit rows — so the goal residuals are directly comparable to
# the points residual they decompose.
#   off_resid = actual goals scored  - value-expected goals scored
#   def_resid = value-expected goals conceded - actual goals conceded
# Both are per game and signed so that positive = better than the squad's value
# predicts. Rows excluded by the log filter get NA, exactly as in M4.
cs_compute_head_residuals <- function(dataset, log_transform = TRUE) {
  d <- dataset |>
    left_join(cs_team_season_goals(), by = "team_season_id") |>
    mutate(
      goals_for_per_game     = goals_for     / games_played,
      goals_against_per_game = goals_against / games_played
    )

  n_missing <- sum(is.na(d$goals_for))
  if (n_missing > 0) {
    message(n_missing, " team-season(s) have no match goals and get NA head residuals.")
  }

  d_fit <- if (log_transform) {
    d |> filter(norm_weighted_value > 0, norm_total_value > 0,
                !is.na(goals_for_per_game))
  } else {
    d |> filter(!is.na(goals_for_per_game))
  }

  m_off <- lm(
    goals_for_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
    data = d_fit
  )
  m_def <- lm(
    goals_against_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
    data = d_fit
  )

  predict_onto <- function(model) {
    p <- suppressWarnings(predict(model, newdata = d))
    p[!is.finite(p)] <- NA
    p
  }

  out <- d |>
    mutate(
      predicted_gf_pg = predict_onto(m_off),
      predicted_ga_pg = predict_onto(m_def),
      off_resid = goals_for_per_game - predicted_gf_pg,
      def_resid = predicted_ga_pg - goals_against_per_game
    ) |>
    select(
      team_season_id, team_name, league, season,
      norm_weighted_value, games_played,
      goals_for, goals_against, goals_for_per_game, goals_against_per_game,
      predicted_gf_pg, predicted_ga_pg, off_resid, def_resid
    )

  cat("=== Head Models (same RHS as the M3/M4 points model) ===\n")
  cat("Fit rows:                ", nrow(d_fit), "\n")
  cat("Goals-for R^2:           ", round(summary(m_off)$r.squared, 4), "\n")
  cat("Goals-against R^2:       ", round(summary(m_def)$r.squared, 4), "\n")
  cat("NA off/def residuals:    ", sum(is.na(out$off_resid)), "\n")

  attr(out, "models") <- list(off = m_off, def = m_def)
  out
}

# Consistency check (design sec. 2.1): scoring more and conceding fewer goals
# than the squad's value predicts should track scoring more points than it
# predicts. Correlates the goal-difference overperformance (off_resid +
# def_resid, per game) against the M4 points residual (PPG). The map from goal
# difference to points is monotone but noisy, so ~0.8+ is the expectation, not
# 1.0 — the gap is reported, not hidden.
cs_validate_tieback <- function(head_tbl, residuals_tbl, threshold = 0.8) {
  d <- head_tbl |>
    mutate(gd_resid = off_resid + def_resid) |>
    inner_join(residuals_tbl |> select(team_season_id, residual),
               by = "team_season_id") |>
    filter(!is.na(gd_resid), !is.na(residual))

  r <- cor(d$gd_resid, d$residual)
  fit <- lm(residual ~ gd_resid, data = d)

  cat("=== Sanity Tie-Back: goal-difference edge vs points residual ===\n")
  cat("Team-seasons compared:      ", nrow(d), "\n")
  cat("Correlation:                ", round(r, 4), "\n")
  cat("Points per goal of edge:    ", round(coef(fit)[["gd_resid"]], 4), "\n")
  if (r >= threshold) {
    cat("Passes: the two head residuals reconstruct the points residual as expected.\n")
  } else {
    cat("BELOW the", threshold, "expectation — investigate before trusting the split.\n")
  }

  invisible(list(n = nrow(d), correlation = r, slope = coef(fit)[["gd_resid"]], data = d))
}

# Coach-stint goal residuals. Mirrors build_coach_residuals() exactly — same
# coverage filter, same match-to-coach attribution, same one-row-per-coach
# handling of re-appointments, same "difference the stint's actual against the
# season-level head prediction (constant within season)" logic — but aggregates
# goals for/against within the stint instead of points.
cs_build_coach_goal_residuals <- function(head_tbl, min_coverage = 80) {
  coaches <- xx_data_cache$coaches
  matches <- xx_data_cache$matches

  head_filtered <- xx_filter_value_coverage(head_tbl, min_coverage = min_coverage)

  purrr::map_df(head_filtered$team_season_id, function(team_sid) {
    meta <- head_tbl |> filter(team_season_id == team_sid)

    team_matches <- matches |>
      filter(home_team_id == team_sid | away_team_id == team_sid) |>
      cs_match_goals_for_team(team_sid)

    attributed <- xx_assign_matches_to_coaches(
      team_matches,
      coaches |> filter(team_season_id == team_sid)
    )

    coach_dates <- coaches |>
      filter(team_season_id == team_sid) |>
      arrange(date_from) |>
      distinct(coach_id, .keep_all = TRUE) |>
      select(coach_id, date_from)

    attributed |>
      filter(!is.na(coach_id)) |>
      group_by(coach_id, coach_name) |>
      summarize(
        n_games            = n(),
        goals_for          = sum(team_goals_for),
        goals_against      = sum(team_goals_against),
        .groups            = "drop"
      ) |>
      left_join(coach_dates, by = "coach_id") |>
      mutate(
        team_season_id  = team_sid,
        team_name       = meta$team_name,
        league          = meta$league,
        season          = meta$season,
        predicted_gf_pg = meta$predicted_gf_pg,
        predicted_ga_pg = meta$predicted_ga_pg,
        actual_gf_pg    = goals_for     / n_games,
        actual_ga_pg    = goals_against / n_games,
        off_resid       = actual_gf_pg - predicted_gf_pg,
        def_resid       = predicted_ga_pg - actual_ga_pg
      ) |>
      select(
        coach_id, coach_name,
        team_season_id, team_name, league, season,
        date_from, n_games, goals_for, goals_against,
        actual_gf_pg, actual_ga_pg, predicted_gf_pg, predicted_ga_pg,
        off_resid, def_resid
      )
  })
}

# Fits the M5 mixed model to one head's stint residuals. Reuses
# fit_mixed_model() verbatim (variance components, LRT, games weighting, BLUP
# shrinkage) by presenting the head residual under the column name it expects —
# the units are goals per game here, not points per game.
#
# The 14-league offence fit emits lme4's "failed to converge with max|grad| =
# 0.0028 (tol = 0.002)" warning. It is the known false positive: refitting with
# bobyqa converges cleanly to the same optimum (logLik -1517.085 either way,
# variance components equal to 5 dp, BLUP correlation 1.0, LRT chi-sq 160.215
# both ways — verified 2026-07-16). Do not switch optimizers to silence it.
cs_fit_head_blups <- function(stints, response, min_games = 10, min_stints = 3) {
  d <- stints |>
    rename(partial_residual_ppg = all_of(response)) |>
    filter(!is.na(partial_residual_ppg))
  fit_mixed_model(d, min_games = min_games, min_stints = min_stints)
}

# Games-weighted per-coach mean of one head residual plus the >= 3-stint
# significance test, reusing the M5 helpers (same weighted mean/SE and BH FDR).
cs_head_stats <- function(stints, response, label, min_games = 10) {
  d <- stints |>
    rename(partial_residual_ppg = all_of(response)) |>
    filter(!is.na(partial_residual_ppg))
  compute_coach_stats(d, min_games = min_games, min_stints = 1, label = label) |>
    add_significance()
}

# One row per coach: the offence and defence BLUPs and their games-weighted
# mean/significance counterparts.
#   tilt = off_blup - def_blup  (positive = the edge is attacking)
#   edge = off_blup + def_blup  (total goal-difference edge per game)
# Coaches are those the mixed model retains (min_games / min_stints); the two
# heads share that filter, so the BLUP tables align one-to-one.
cs_combine_strengths <- function(off_fit, def_fit, off_stats, def_stats) {
  blups <- off_fit$coach_blups |>
    select(coach_id, coach_name, n_stints, total_games, n_clubs,
           off_blup = blup) |>
    inner_join(def_fit$coach_blups |> select(coach_id, def_blup = blup),
               by = "coach_id") |>
    mutate(tilt = off_blup - def_blup, edge = off_blup + def_blup)

  means <- off_stats |>
    select(coach_id, off_mean = mean_residual, off_p_adj = p_adj,
           off_significant = significant) |>
    full_join(
      def_stats |> select(coach_id, def_mean = mean_residual, def_p_adj = p_adj,
                          def_significant = significant),
      by = "coach_id"
    )

  out <- blups |>
    left_join(means, by = "coach_id") |>
    arrange(desc(edge)) |>
    as_tibble()

  cat("=== Coach Strengths (offence/defence tilt) ===\n")
  cat("Coaches with both BLUPs:", nrow(out), "\n")
  cat("Tilt correlation (off vs def BLUP):",
      round(cor(out$off_blup, out$def_blup), 4), "\n\n")

  cat("=== Most attacking edge (top 10 by off_blup) ===\n")
  print(out |> arrange(desc(off_blup)) |>
          select(coach_name, total_games, off_blup, def_blup, tilt) |> head(10), n = Inf)
  cat("\n=== Most defensive edge (top 10 by def_blup) ===\n")
  print(out |> arrange(desc(def_blup)) |>
          select(coach_name, total_games, off_blup, def_blup, tilt) |> head(10), n = Inf)

  out
}

# Writes coach_strengths_<cut>.rds (per-coach offence/defence) and
# coach_goal_residuals_<cut>.rds (the stint table behind it), analogous to the
# existing coach_blups_*/coach_residuals_* pairs. Re-run whenever M4/M5 is refit.
cs_save_results <- function(strengths, stints, cut, results_dir = "data/results") {
  saveRDS(strengths, file.path(results_dir, paste0("coach_strengths_", cut, ".rds")))
  saveRDS(stints,    file.path(results_dir, paste0("coach_goal_residuals_", cut, ".rds")))
  cat("Wrote coach_strengths_", cut, ".rds (", nrow(strengths), " coaches) and ",
      "coach_goal_residuals_", cut, ".rds (", nrow(stints), " stints).\n", sep = "")
  invisible(strengths)
}

# Runs the full Layer A (goals) pipeline for one published cut and saves the
# results. Mirrors run_milestone4()/run_milestone5(): builds the dataset, fits
# the two head models, checks the tie-back to the points residual, attributes
# to coach stints, and fits the two mixed models.
run_coach_strengths <- function(cut = c("top5", "14league"),
                                seasons      = 2005:xx_last_data_season,
                                min_coverage = 80,
                                min_games    = 10,
                                min_stints   = 3,
                                results_dir  = "data/results",
                                save         = TRUE) {
  cut <- match.arg(cut)
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep(paste("STEP 1: BUILD DATASET —", cut))
  dataset <- build_model_dataset(seasons, leagues = cs_cut_leagues(cut))
  cat("Rows loaded:", nrow(dataset), "\n")

  sep("STEP 2: HEAD MODELS (goals for / goals against)")
  head_tbl <- cs_compute_head_residuals(dataset)

  sep("STEP 3: TIE-BACK TO THE POINTS RESIDUAL")
  points_tbl <- compute_residuals(dataset)
  tieback    <- cs_validate_tieback(head_tbl, points_tbl)

  sep("STEP 4: ATTRIBUTE TO COACH STINTS")
  stints <- cs_build_coach_goal_residuals(head_tbl, min_coverage = min_coverage)
  cat("Stints built:  ", nrow(stints), "\n")
  cat("Unique coaches:", n_distinct(stints$coach_id), "\n")

  sep("STEP 5: PER-COACH MEANS & SIGNIFICANCE — OFFENCE")
  off_stats <- cs_head_stats(stints, "off_resid", label = "goals scored per game",
                             min_games = min_games)

  sep("STEP 6: PER-COACH MEANS & SIGNIFICANCE — DEFENCE")
  def_stats <- cs_head_stats(stints, "def_resid", label = "goals prevented per game",
                             min_games = min_games)

  sep("STEP 7: MIXED MODEL — OFFENCE")
  off_fit <- cs_fit_head_blups(stints, "off_resid", min_games = min_games,
                              min_stints = min_stints)

  sep("STEP 8: MIXED MODEL — DEFENCE")
  def_fit <- cs_fit_head_blups(stints, "def_resid", min_games = min_games,
                              min_stints = min_stints)

  sep("STEP 9: COMBINE")
  strengths <- cs_combine_strengths(off_fit, def_fit, off_stats, def_stats)

  if (save) cs_save_results(strengths, stints, cut, results_dir = results_dir)

  sep(paste("COACH STRENGTHS COMPLETE —", cut))
  cat("Tie-back correlation:   ", round(tieback$correlation, 4), "\n")
  cat("Offence coach var p (LRT):", round(off_fit$lrt$p, 4), "\n")
  cat("Defence coach var p (LRT):", round(def_fit$lrt$p, 4), "\n")
  cat("Coaches with a tilt:    ", nrow(strengths), "\n")

  invisible(list(
    dataset   = dataset,
    head_tbl  = head_tbl,
    tieback   = tieback,
    stints    = stints,
    off_stats = off_stats,
    def_stats = def_stats,
    off_fit   = off_fit,
    def_fit   = def_fit,
    strengths = strengths
  ))
}

# =============================================================================
# Phase 2 — the xG cut: process (creation) vs outcome (finishing)
# =============================================================================
#
# Splits the goals cut again: how much of a coach's attacking edge is chance
# quality he manufactures (repeatable process) versus finishing that may
# regress (outcome)? Four per-game measures, all signed positive = better:
#
#   creation   = team xG-for above value expectation        (process, attack)
#   prevention = value-expected xG-against - actual         (process, defence)
#   finishing  = actual goals-for - xG-for                  (outcome, attack)
#   shotstop   = xG-against - actual goals-against          (outcome, defence)
#
# creation/prevention need a head model (they are measured against what the
# squad's value predicts); finishing/shotstop do not — they are within-team
# differences between what happened and what the chances were worth.
#
# COVERAGE (verified 2026-07-16, not merely inherited from the design doc):
# xG is ~99-100% complete for big-5 2022/23-2024/25 and only ~40% in 2021/22
# (the design's "present but partial mid-2021/22"), 0% before. 2021 is therefore
# EXCLUDED — partial coverage would understate team xG on a non-random subset of
# matches. This layer is a recent-form lens over 3 seasons of the big 5, never a
# career verdict, and must be labelled as such wherever it is shown.
cs_xg_seasons <- 2022:xx_last_data_season

# Per (event, team) xG and goals for one big-5 league-season, joined to the TM
# team_season_id and the coach in charge via cf_season_match_coaches() (which
# carries the playoff filter and the greedy one-to-one team map).
#
# COVERAGE RULE: an event counts only if (a) it carries xG at all, and (b) its
# shotmap accounts for every goal in the scoreline, on both sides. (b) is not
# paranoia — 27 of the 5,330 xG-era events (0.5%, all in 2023, every league
# affected) carry a full complement of ~21 shots but are missing their goal
# shots entirely. In those matches xG loses exactly the chances that scored
# while the scoreline keeps the goals, which would understate creation and
# inflate finishing precisely where it is most visible. Verified 2026-07-16;
# a reconciliation check that conditions on events *having* goal shots will
# report a clean bill of health and miss this.
#
# Both xG and goals are then counted on that same surviving match set —
# otherwise finishing (= goals - xG) would compare totals drawn from different
# matches.
#
# The shooting team comes from shots$is_home + the event's home/away ids. Note
# SofaScore records an own goal in the shotmap credited to the *benefiting* side
# (is_home = beneficiary) but named for the defender who scored it, with no xG
# and coordinates on the goal line. Aggregating by is_home is therefore correct
# at team level, and own goals land wholly in the finishing/shotstop term — which
# is where they belong: an own goal is the definition of an unrepeatable outcome.
cs_season_team_xg <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]

  spine  <- cf_season_match_coaches(league_key, year)
  shots  <- pa_read("shots", sid)
  events <- pa_read("events", sid) |> filter(status_type == "finished")

  # NB: never name an output the same as an input inside summarize() — the new
  # column shadows the original for later expressions in the same call, which
  # silently turned own_goals into 0 when xg was aggregated first.
  per_side <- shots |>
    inner_join(events |> select(event_ss_id, home_team_ss_id, away_team_ss_id),
               by = "event_ss_id") |>
    mutate(team_ss_id = if_else(is_home, home_team_ss_id, away_team_ss_id)) |>
    group_by(event_ss_id, team_ss_id) |>
    summarize(
      xg_sum    = sum(xg, na.rm = TRUE),
      n_shots   = n(),
      sm_goals  = sum(shot_type == "goal"),
      own_goals = sum(shot_type == "goal" & is.na(xg)),
      has_xg    = any(!is.na(xg)),
      .groups   = "drop"
    )

  sides <- bind_rows(
    events |> transmute(event_ss_id, team_ss_id = home_team_ss_id,
                        opp_ss_id = away_team_ss_id,
                        goals_for = home_goals, goals_against = away_goals),
    events |> transmute(event_ss_id, team_ss_id = away_team_ss_id,
                        opp_ss_id = home_team_ss_id,
                        goals_for = away_goals, goals_against = home_goals)
  ) |>
    left_join(per_side, by = c("event_ss_id", "team_ss_id")) |>
    left_join(per_side |> select(event_ss_id, opp_ss_id = team_ss_id,
                                 xg_against = xg_sum, shots_against = n_shots,
                                 sm_goals_against = sm_goals),
              by = c("event_ss_id", "opp_ss_id")) |>
    # a team that took no shots in a covered match is a legitimate zero
    mutate(across(c(xg_sum, n_shots, sm_goals, own_goals,
                    xg_against, shots_against, sm_goals_against),
                  \(v) coalesce(v, 0)),
           has_xg = coalesce(has_xg, FALSE)) |>
    rename(xg_for = xg_sum, shots_for = n_shots, sm_goals_for = sm_goals)

  covered <- sides |>
    group_by(event_ss_id) |>
    summarize(ok = any(has_xg) & all(sm_goals_for == goals_for), .groups = "drop") |>
    filter(ok) |>
    pull(event_ss_id)

  sides |>
    filter(event_ss_id %in% covered) |>
    select(-has_xg) |>
    inner_join(spine |> select(event_ss_id, team_ss_id, team_season_id,
                               coach_id, match_date, league, season_start_year),
               by = c("event_ss_id", "team_ss_id"))
}

# Every big-5 xG-era team-match. Slow (~2 min: coach attribution per season).
# Reports what the coverage rule dropped per season so the exclusions stay
# visible instead of silently shrinking the denominator.
cs_build_team_xg <- function(seasons = cs_xg_seasons) {
  out <- bind_rows(lapply(names(ss_big5_leagues), function(lg) {
    bind_rows(lapply(seasons, function(yr) {
      cat("  ", lg, yr, "\n")
      cs_season_team_xg(lg, yr)
    }))
  }))

  stopifnot(all(out$sm_goals_for == out$goals_for))  # the coverage rule's promise

  cat("\n=== Team-match xG built ===\n")
  cat("Team-matches:           ", nrow(out), "\n")
  cat("Distinct events:        ", n_distinct(out$event_ss_id), "\n")
  cat("Own goals (no xG):      ", sum(out$own_goals),
      sprintf("(%.1f%% of goals — they carry no xG and so land in finishing)\n",
              100 * sum(out$own_goals) / sum(out$goals_for)))
  cat("Unattributed to a coach:", sum(is.na(out$coach_id)),
      sprintf("(%.2f%%)\n", 100 * mean(is.na(out$coach_id))))

  cat("\nEvents kept per league-season (vs the league's finished events):\n")
  kept <- out |>
    distinct(league, season_start_year, event_ss_id) |>
    count(league, season_start_year, name = "events_kept")
  print(as.data.frame(kept), row.names = FALSE)
  out
}

# Team-season xG head models. Same right-hand side as the goals heads, fit on
# the xG-era rows only (xG does not exist earlier, so this model cannot borrow
# strength from the full span). is_b_team is dropped when it does not vary —
# no big-5 top division contains a B team — mirroring cv_by_league()'s handling.
cs_compute_xg_head_residuals <- function(dataset, team_xg) {
  ts <- team_xg |>
    group_by(team_season_id) |>
    summarize(
      n_xg_matches  = n(),
      xg_for        = sum(xg_for),
      xg_against    = sum(xg_against),
      goals_for_xg  = sum(goals_for),
      goals_against_xg = sum(goals_against),
      .groups = "drop"
    )

  d <- dataset |>
    inner_join(ts, by = "team_season_id") |>
    filter(norm_weighted_value > 0, norm_total_value > 0) |>
    mutate(
      xg_for_pg     = xg_for     / n_xg_matches,
      xg_against_pg = xg_against / n_xg_matches
    )

  rhs <- c("log(norm_weighted_value)", "as.factor(league)",
           if (length(unique(d$is_b_team)) > 1) "is_b_team")
  f <- function(y) as.formula(paste(y, "~", paste(rhs, collapse = " + ")))

  m_xgf <- lm(f("xg_for_pg"),     data = d)
  m_xga <- lm(f("xg_against_pg"), data = d)

  out <- d |>
    mutate(
      predicted_xgf_pg = predict(m_xgf, newdata = d),
      predicted_xga_pg = predict(m_xga, newdata = d)
    ) |>
    select(team_season_id, team_name, league, season, games_played,
           n_xg_matches, xg_for, xg_against, goals_for_xg, goals_against_xg,
           xg_for_pg, xg_against_pg, predicted_xgf_pg, predicted_xga_pg)

  cat("=== xG Head Models (xG-era rows only) ===\n")
  cat("Team-seasons:      ", nrow(d), "\n")
  cat("Matches per season:", round(mean(d$n_xg_matches), 1),
      sprintf("(of %.1f league games — the gap is uncovered matches)\n",
              mean(d$games_played)))
  cat("xG-for R^2:        ", round(summary(m_xgf)$r.squared, 4), "\n")
  cat("xG-against R^2:    ", round(summary(m_xga)$r.squared, 4), "\n")

  attr(out, "models") <- list(xgf = m_xgf, xga = m_xga)
  out
}

# Coach-stint xG residuals. Aggregates the team-matches within each (coach,
# team-season) and differences against the season-level head predictions,
# exactly as the goals cut does.
cs_build_coach_xg_residuals <- function(team_xg, xg_head_tbl) {
  team_xg |>
    filter(!is.na(coach_id)) |>
    # team_xg$league is the SofaScore key ("premier_league"); take the TM league
    # name and season from the head table instead, as the rest of the project uses
    select(event_ss_id, team_season_id, coach_id,
           xg_for, xg_against, goals_for, goals_against) |>
    inner_join(xg_head_tbl |> select(team_season_id, team_name, league, season,
                                     predicted_xgf_pg, predicted_xga_pg),
               by = "team_season_id") |>
    group_by(coach_id, team_season_id, team_name, league, season,
             predicted_xgf_pg, predicted_xga_pg) |>
    summarize(
      n_games       = n(),
      xg_for        = sum(xg_for),
      xg_against    = sum(xg_against),
      goals_for     = sum(goals_for),
      goals_against = sum(goals_against),
      .groups       = "drop"
    ) |>
    mutate(
      xg_for_pg        = xg_for        / n_games,
      xg_against_pg    = xg_against    / n_games,
      creation_resid   = xg_for_pg - predicted_xgf_pg,
      prevention_resid = predicted_xga_pg - xg_against_pg,
      finishing_resid  = (goals_for - xg_for) / n_games,
      shotstop_resid   = (xg_against - goals_against) / n_games
    ) |>
    left_join(
      # canonicalised first: a coach_id carrying two name spellings (Transfermarkt
      # re-spelled Ivan Juric as "Ivan Jurić" in 2025/26) would otherwise make
      # this a one-to-many join and silently duplicate his stint rows
      xx_canonical_coach_names(xx_data_cache$coaches) |>
        distinct(coach_id, coach_name),
      by = "coach_id"
    ) |>
    select(coach_id, coach_name, team_season_id, team_name, league, season,
           n_games, xg_for, xg_against, goals_for, goals_against,
           xg_for_pg, xg_against_pg, predicted_xgf_pg, predicted_xga_pg,
           creation_resid, prevention_resid, finishing_resid, shotstop_resid)
}

# The design asserts creation is repeatable process and finishing is not. That
# is testable rather than assertable: correlate each measure for the same club
# in consecutive seasons. Expect creation to persist and finishing to sit near
# zero — if finishing persisted, the process/outcome framing would be wrong.
cs_xg_repeatability <- function(xg_head_tbl, team_xg) {
  ts <- team_xg |>
    group_by(team_season_id) |>
    summarize(n_games = n(), xg_for = sum(xg_for), xg_against = sum(xg_against),
              goals_for = sum(goals_for), goals_against = sum(goals_against),
              .groups = "drop")

  d <- xg_head_tbl |>
    left_join(ts |> select(team_season_id, goals_for, goals_against),
              by = "team_season_id") |>
    mutate(
      club_id          = sub("/saison_id/\\d+", "", team_season_id),
      creation_resid   = xg_for_pg - predicted_xgf_pg,
      prevention_resid = predicted_xga_pg - xg_against_pg,
      finishing_resid  = (goals_for - xg_for) / n_xg_matches,
      shotstop_resid   = (xg_against - goals_against) / n_xg_matches
    )

  measures <- c("creation_resid", "prevention_resid",
                "finishing_resid", "shotstop_resid")
  rows <- lapply(measures, function(m) {
    pairs <- d |>
      arrange(club_id, season) |>
      group_by(club_id) |>
      mutate(next_val = lead(.data[[m]]), next_season = lead(season)) |>
      filter(!is.na(next_val), next_season == season + 1) |>
      ungroup()
    ct <- cor.test(pairs[[m]], pairs$next_val)
    data.frame(
      measure = sub("_resid", "", m),
      n_pairs = nrow(pairs),
      lag1_r  = round(unname(ct$estimate), 3),
      p_value = signif(ct$p.value, 3),
      ci_low  = round(ct$conf.int[1], 3),
      ci_high = round(ct$conf.int[2], 3)
    )
  })
  out <- do.call(rbind, rows)

  cat("=== Repeatability: same club, consecutive seasons (lag-1) ===\n")
  cat("Tests the design's process-vs-outcome premise. Expect creation and\n")
  cat("prevention to persist; finishing and shot-stopping should not.\n\n")
  print(out, row.names = FALSE)

  invisible(out)
}

# Cross-source tie-back. The xG cut is built from SofaScore events; the goals
# cut from Transfermarkt matches. By construction
#   creation + finishing = goals-for per game - value-expected xG-for per game
# which should track the goals cut's off_resid closely (they differ only by
# expected-goals vs expected-xG on the same right-hand side, and by the goals
# model's wider fit span). A weak correlation here means the SofaScore -> TM
# team map or the coach attribution is broken, not that the metric is subtle.
cs_validate_xg_tieback <- function(xg_stints, goal_stints) {
  d <- xg_stints |>
    mutate(xg_off = creation_resid + finishing_resid,
           xg_def = prevention_resid + shotstop_resid) |>
    inner_join(
      goal_stints |> select(coach_id, team_season_id,
                            goals_off = off_resid, goals_def = def_resid),
      by = c("coach_id", "team_season_id")
    ) |>
    filter(!is.na(goals_off), !is.na(goals_def))

  r_off <- cor(d$xg_off, d$goals_off)
  r_def <- cor(d$xg_def, d$goals_def)

  cat("=== Cross-source tie-back: SofaScore xG cut vs TM goals cut ===\n")
  cat("Stints matched:                  ", nrow(d), "\n")
  cat("creation+finishing vs off_resid: ", round(r_off, 4), "\n")
  cat("prevention+shotstop vs def_resid:", round(r_def, 4), "\n")
  if (min(r_off, r_def) >= 0.9) {
    cat("Passes: the two independently-sourced pipelines agree.\n")
  } else {
    cat("LOW — check the SofaScore->TM team map and coach attribution.\n")
  }
  invisible(list(n = nrow(d), r_off = r_off, r_def = r_def))
}

# Per-coach xG-era table: games-weighted means + the >= 3-stint FDR test for
# each of the four measures, reusing the M5 helpers as the goals cut does.
# Means are primary here: with only three seasons most coaches have 1-3 stints,
# so mixed-model BLUPs would be shrunk almost to nothing and the club/coach
# split is barely identified.
cs_coach_xg_strengths <- function(xg_stints, min_games = 10) {
  measures <- c(creation = "creation_resid", prevention = "prevention_resid",
                finishing = "finishing_resid", shotstop = "shotstop_resid")
  labels <- c(creation = "xG created per game", prevention = "xG prevented per game",
              finishing = "goals - xG per game", shotstop = "xG - goals conceded per game")

  parts <- lapply(names(measures), function(nm) {
    cat("\n---", nm, "---\n")
    st <- cs_head_stats(xg_stints, measures[[nm]], label = labels[[nm]],
                        min_games = min_games)
    st |>
      select(coach_id, coach_name, n_stints, total_games, n_clubs,
             mean_residual, p_adj, significant) |>
      rename_with(\(x) paste0(nm, "_", x), c(mean_residual, p_adj, significant))
  })

  out <- Reduce(function(a, b) {
    full_join(a, b |> select(-coach_name, -n_stints, -total_games, -n_clubs),
              by = "coach_id")
  }, parts) |>
    arrange(desc(creation_mean_residual)) |>
    as_tibble()

  cat("\n=== Coach xG Strengths (big-5, 2022-2024 only) ===\n")
  cat("Coaches:", nrow(out), "\n")
  cat("Creation vs finishing correlation:",
      round(cor(out$creation_mean_residual, out$finishing_mean_residual), 3),
      "(near zero = the two axes carry independent information)\n")

  # Display bar for the console preview only — the saved table keeps every
  # coach. Over a 3-season window a 10-game record is nearly all noise, and an
  # unfiltered "top 10" would be a list of caretakers.
  shown <- out |> filter(total_games >= 38)
  cat("\n=== Top 10 by creation (>= 38 games in the xG era;",
      nrow(shown), "of", nrow(out), "coaches clear that bar) ===\n")
  print(shown |> arrange(desc(creation_mean_residual)) |>
          select(coach_name, total_games, creation_mean_residual,
                 finishing_mean_residual, prevention_mean_residual,
                 shotstop_mean_residual) |> head(10), n = Inf)
  cat("\n=== Bottom 10 by creation (same bar) ===\n")
  print(shown |> arrange(creation_mean_residual) |>
          select(coach_name, total_games, creation_mean_residual,
                 finishing_mean_residual, prevention_mean_residual,
                 shotstop_mean_residual) |> head(10), n = Inf)

  out
}

# Writes coach_xg_strengths.rds (per coach) and coach_xg_residuals.rds (stints).
# No cut suffix: the xG data is big-5 only, so this layer has one population.
cs_save_xg_results <- function(strengths, stints, results_dir = "data/results") {
  saveRDS(strengths, file.path(results_dir, "coach_xg_strengths.rds"))
  saveRDS(stints,    file.path(results_dir, "coach_xg_residuals.rds"))
  cat("Wrote coach_xg_strengths.rds (", nrow(strengths), " coaches) and ",
      "coach_xg_residuals.rds (", nrow(stints), " stints).\n", sep = "")
  invisible(strengths)
}

# Runs the phase-2 xG pipeline. Big-5, 2022-2024 (see cs_xg_seasons).
run_coach_xg_strengths <- function(seasons     = cs_xg_seasons,
                                   min_games   = 10,
                                   results_dir = "data/results",
                                   save        = TRUE,
                                   team_xg     = NULL) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD TEAM-MATCH xG (big-5, xG era)")
  if (is.null(team_xg)) team_xg <- cs_build_team_xg(seasons)

  sep("STEP 2: xG HEAD MODELS")
  dataset  <- build_model_dataset(seasons, leagues = cs_cut_leagues("top5"))
  xg_head  <- cs_compute_xg_head_residuals(dataset, team_xg)

  sep("STEP 3: REPEATABILITY (process vs outcome)")
  repeatability <- cs_xg_repeatability(xg_head, team_xg)

  sep("STEP 4: COACH-STINT xG RESIDUALS")
  xg_stints <- cs_build_coach_xg_residuals(team_xg, xg_head)
  cat("Stints:        ", nrow(xg_stints), "\n")
  cat("Unique coaches:", n_distinct(xg_stints$coach_id), "\n")

  sep("STEP 5: CROSS-SOURCE TIE-BACK TO THE GOALS CUT")
  goal_path <- file.path(results_dir, "coach_goal_residuals_top5.rds")
  tieback <- if (file.exists(goal_path)) {
    cs_validate_xg_tieback(xg_stints, readRDS(goal_path))
  } else {
    cat("Skipped:", goal_path, "not found — run run_coach_strengths('top5') first.\n")
    NULL
  }

  sep("STEP 6: PER-COACH MEANS & SIGNIFICANCE")
  strengths <- cs_coach_xg_strengths(xg_stints, min_games = min_games)

  if (save) cs_save_xg_results(strengths, xg_stints, results_dir = results_dir)

  sep("xG CUT COMPLETE")
  cat("Team-matches:", nrow(team_xg), " stints:", nrow(xg_stints),
      " coaches:", nrow(strengths), "\n\n")
  print(repeatability, row.names = FALSE)

  invisible(list(
    team_xg       = team_xg,
    xg_head       = xg_head,
    repeatability = repeatability,
    xg_stints     = xg_stints,
    tieback       = tieback,
    strengths     = strengths
  ))
}
