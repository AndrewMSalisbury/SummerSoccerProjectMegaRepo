source("coach_attribution.R")   # -> residual_analysis.R -> model_comparison.R ->
                                #    tabler.R; gives build_model_dataset(), the M5
                                #    attribution spine and xx_filter_value_coverage().
                                #    source_data.r must be sourced first (for xx_data_cache).

# =============================================================================
# Coach -> Player Value Growth (the "Coach Development Effect", CDE)
# Design: Docs/Coach_Value_Growth_Design.md
#
# A second, euro-denominated outcome axis for the project: do players appreciate
# in market value faster than their own trajectory predicts, and how much of that
# excess is attributable to the coach? Built on the exact M3 -> M4 -> M5 skeleton
# (baseline expectation model -> residual -> games/minutes-weighted mixed-model
# attribution with shrinkage) so it inherits the machinery and the discipline.
#
# HONESTY LABEL (design sec. 0): `exploratory` until it clears the pre-registered
# validation (design sec. 6). Value growth is NOT zero-sum (unlike points), it is
# mechanically entangled with the points BLUP (the market marks up players whose
# team overperformed), and it is overwhelmingly an age story. The baseline's job
# is to strip the age / mean-reversion / market confounds down to something that
# *might* be coaching; the validation's job is to test whether anything survives
# and whether it carries information beyond points. A null is a publishable,
# on-brand result here.
#
# This file is Phase 1 (design sec. 7): the player-season table + the two
# baseline expectation models (CDE-total and CDE-development) + the development
# residual. Coach attribution (Phase 2) reuses the M5 spine and lives below once
# Phase 1's residual is validated. `cvg_` prefix, pure cache-reader.
# =============================================================================

# The published cuts, defined the same way the rest of the pipeline defines them
# (via the league-id constants, NOT via the ambiguous league_name strings in
# leagues.rds where Brazil's "Serie A" collides with Italy's). top5 first for a
# clean read, then the full 14-league set (design sec. 7).
cvg_cut_leagues <- function(cut = c("top5", "14league")) {
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

# Maps Transfermarkt's fine-grained player_position to the four position groups
# the age curve is allowed to differ across. Keepers get their own group because
# their value curve peaks far later than an outfielder's (design sec. 3.2); the
# three outfield groups follow the D/M/F split used by the archetype layer.
# Anything unmapped (a handful of generic "Midfield"/"Attack"/"Defender" tags are
# folded into their group; truly blank positions return NA and are dropped).
cvg_position_group <- function(pos) {
  dplyr::case_when(
    pos == "Goalkeeper" ~ "GK",
    pos %in% c("Centre-Back", "Right-Back", "Left-Back", "Defender", "Sweeper") ~ "DEF",
    pos %in% c("Central Midfield", "Defensive Midfield", "Attacking Midfield",
               "Right Midfield", "Left Midfield", "Midfield") ~ "MID",
    pos %in% c("Centre-Forward", "Right Winger", "Left Winger", "Second Striker",
               "Attack") ~ "FWD",
    TRUE ~ NA_character_
  )
}

# Builds the full same-club value trajectory from the players cache, then
# restricts the fit population to player-seasons whose season-t team-season is in
# the chosen cut.
#
# WHY compute the trajectory on the whole cache but fit on the cut: value_{t+1}
# (and the prior-season value that feeds `prior_growth`) must come from wherever
# the club was scraped, including the season *after* a relegation out of the cut.
# Building the (t-1, t, t+1) trajectory on the full cache keeps those pairs;
# restricting the fit rows to the cut's season-t team-seasons keeps the league
# fixed effect well-defined and the population identical to M3/M4/M5's. A pair is
# same-club when consecutive seasons share the club_id (team URL minus the
# /saison_id suffix) under the same player_id.
#
# Response g = log(value_{t+1} / value_t). Rows need a valued snapshot at both
# boundaries; value_t below `min_value` (TM's noisy valuation floor) is dropped
# because a tiny denominator inflates g without signal.
cvg_build_player_seasons <- function(cut = c("top5", "14league"),
                                     seasons   = 2005:xx_last_data_season,
                                     min_value = 25000) {
  cut <- match.arg(cut)

  # canonical (team_season_id, league, season) membership for the cut — same
  # construction the points model uses, so league/season factors line up exactly
  cut_ts <- build_model_dataset(seasons, leagues = cvg_cut_leagues(cut)) |>
    select(team_season_id, team_name, league, season)

  traj <- xx_data_cache$players |>
    filter(!is.na(player_market_value_euro), player_market_value_euro > 0) |>
    mutate(
      club_id = sub("/saison_id/\\d+$", "", team_season_id),
      season  = as.integer(sub(".*/saison_id/(\\d+).*", "\\1", team_season_id))
    ) |>
    arrange(club_id, player_id, season) |>
    group_by(club_id, player_id) |>
    mutate(
      value_next   = lead(player_market_value_euro),
      season_next  = lead(season),
      value_prev   = lag(player_market_value_euro),
      season_prev  = lag(season)
    ) |>
    ungroup()

  base <- traj |>
    # same-club consecutive-season pair with valued endpoints above the floor
    filter(
      !is.na(value_next), season_next == season + 1,
      player_market_value_euro >= min_value, value_next >= min_value
    ) |>
    inner_join(cut_ts, by = c("team_season_id", "season")) |>
    mutate(
      position_group = cvg_position_group(player_position),
      g              = log(value_next / player_market_value_euro),
      log_value_t    = log(player_market_value_euro),
      # lagged momentum: only a genuine same-club consecutive prior season counts
      has_prior      = !is.na(value_prev) & season_prev == season - 1,
      prior_growth   = if_else(has_prior,
                               log(player_market_value_euro / value_prev), 0),
      has_minutes    = !is.na(percent_minutes_played),
      pct_minutes    = if_else(has_minutes, percent_minutes_played, 0)
    ) |>
    filter(!is.na(player_age), !is.na(position_group))

  cat("=== CDE player-season base (", cut, ") ===\n", sep = "")
  cat("Same-club valued pairs in cut:  ", nrow(base), "\n")
  cat("Distinct players:               ", n_distinct(base$player_id), "\n")
  cat("Distinct clubs:                 ", n_distinct(base$club_id), "\n")
  cat("Season range:                   ", min(base$season), "-", max(base$season), "\n")
  cat("With prior-growth momentum:     ", sum(base$has_prior),
      sprintf("(%.1f%%)\n", 100 * mean(base$has_prior)))
  cat("With minutes:                   ", sum(base$has_minutes),
      sprintf("(%.1f%%)\n", 100 * mean(base$has_minutes)))
  cat("Position groups:                ",
      paste(names(table(base$position_group)), table(base$position_group),
            sep = ":", collapse = "  "), "\n")

  base
}

# The two baseline expectation models (the "M3 analog", design sec. 3.2-3.3).
# Both regress log value growth `g` on confounders only; every mediator (minutes
# in the -total model, results, player output) stays in the residual by design.
# The residual dev_resid = g - g_hat is the player-development residual.
#
#   CDE-total       : baseline EXCLUDES minutes -> credits the coach for both
#                     trusting the player with minutes and improving him per minute.
#   CDE-development : baseline INCLUDES a minutes spline -> credits only growth
#                     beyond what the playing time alone explains.
# The gap between the two is the opportunity channel (design sec. 3.3).
#
# ns(age) is interacted with position_group because the curves differ in shape
# (keepers peak late, forwards are front-loaded). log(value_t) is ALSO splined:
# with a linear term the residual retained a mild U-shape across starting-value
# deciles (cheapest and priciest players grew a little more than the line
# predicted) — the exact "coaches of cheap squads" confound design sec. 5.2
# warns about. ns(log_value_t) is still a confounder-only control (starting
# price is not the coach's doing), so it flattens that curve without touching a
# mediator. prior_growth carries a missing-indicator (has_prior) so
# first-observed players are kept rather than dropped. factor(league)/
# factor(season) absorb market size and inflation.
cvg_fit_baselines <- function(base, age_df = 5, value_df = 4, min_df = 3) {
  f_total <- g ~ splines::ns(player_age, age_df) * position_group +
    splines::ns(log_value_t, value_df) + prior_growth + has_prior +
    factor(league) + factor(season)

  f_dev <- update(
    f_total,
    . ~ . + splines::ns(pct_minutes, min_df) + has_minutes
  )

  m_total <- lm(f_total, data = base)
  m_dev   <- lm(f_dev,   data = base)

  out <- base |>
    mutate(
      pred_total     = as.numeric(predict(m_total)),
      pred_dev       = as.numeric(predict(m_dev)),
      dev_resid      = g - pred_total,   # CDE-total residual (headline)
      dev_resid_dev  = g - pred_dev      # CDE-development residual
    )

  cat("=== Baseline expectation models ===\n")
  cat("Rows fit:                 ", nrow(base), "\n")
  cat("CDE-total  R^2:           ", round(summary(m_total)$r.squared, 4), "\n")
  cat("CDE-develop R^2:          ", round(summary(m_dev)$r.squared, 4), "\n")
  cat("Residual SD (total):      ", round(sd(out$dev_resid), 4), "\n")
  cat("Mean |g|:                 ", round(mean(abs(out$g)), 4), "\n")

  attr(out, "models") <- list(total = m_total, dev = m_dev)
  out
}

# Confound sanity checks (design sec. 5.1-5.2): after the baseline, the
# development residual must be ~uncorrelated with the confounders the baseline
# was built to absorb. A residual that still trends in age means the age spline
# (or its position interaction) is under-fit; one that trends in starting value
# means mean reversion is under-controlled and CDE would just be "coaches of
# cheap squads". These are diagnostics on the *residual*, not new controls.
cvg_check_confounds <- function(fit) {
  r <- fit$dev_resid
  cat("=== Residual confound checks (should all be ~0) ===\n")
  cat("cor(dev_resid, age):          ", round(cor(r, fit$player_age), 4), "\n")
  cat("cor(dev_resid, log_value_t):  ", round(cor(r, fit$log_value_t), 4), "\n")
  cat("cor(dev_resid, prior_growth): ", round(cor(r, fit$prior_growth), 4), "\n")
  cat("cor(dev_resid, pct_minutes):  ", round(cor(r, fit$pct_minutes), 4),
      "  (non-zero is expected — minutes is a mediator left in CDE-total)\n\n")

  cat("Mean residual by age bin (want ~0 everywhere):\n")
  ab <- fit |>
    mutate(agebin = cut(player_age, c(15, 19, 21, 23, 25, 27, 29, 31, 40))) |>
    group_by(agebin) |>
    summarize(n = n(), mean_resid = round(mean(dev_resid), 4), .groups = "drop")
  print(as.data.frame(ab), row.names = FALSE)

  cat("\nMean residual by starting-value decile (want ~0 everywhere):\n")
  vb <- fit |>
    mutate(vdec = dplyr::ntile(log_value_t, 10)) |>
    group_by(vdec) |>
    summarize(n = n(), mean_resid = round(mean(dev_resid), 4),
              mean_logv = round(mean(log_value_t), 2), .groups = "drop")
  print(as.data.frame(vb), row.names = FALSE)

  invisible(list(age_bins = ab, value_deciles = vb))
}

# Face validity on the raw residual (design sec. 7, Phase 1): the biggest
# over-expectation player-seasons should read as genuine breakouts (a young
# player whose value multiplied beyond his age/price trajectory), the biggest
# under-expectation ones as genuine collapses. This is a smell test on the
# residual before any coach is attributed anything.
cvg_face_check <- function(fit, n = 20) {
  show <- fit |>
    transmute(
      player_name, position_group, season,
      age = player_age,
      value_t_m  = round(player_market_value_euro / 1e6, 2),
      value_t1_m = round(value_next / 1e6, 2),
      g          = round(g, 2),
      dev_resid  = round(dev_resid, 2),
      club = sub("^https://www.transfermarkt.com/([^/]+)/.*", "\\1", club_id)
    )

  cat("=== Top", n, "over-expectation player-seasons ===\n")
  print(show |> arrange(desc(dev_resid)) |> head(n), n = Inf)
  cat("\n=== Top", n, "under-expectation player-seasons ===\n")
  print(show |> arrange(dev_resid) |> head(n), n = Inf)
  invisible(show)
}

# Writes the Phase 1 deliverable: the validated development residual, one row per
# player-season, both minutes variants, plus every column Phase 2's coach
# attribution needs (club_id, team_season_id, season, minutes weights). Re-run
# after any change to the baseline. No coach is attributed anything here.
cvg_save_residuals <- function(fit, cut, results_dir = "data/results") {
  out <- fit |>
    select(
      player_id, player_name, position_group, player_age,
      club_id, team_season_id, league, season,
      value_t = player_market_value_euro, value_next,
      minutes_played, pct_minutes, has_minutes,
      g, prior_growth, has_prior, log_value_t,
      pred_total, pred_dev, dev_resid, dev_resid_dev
    )
  # cvg_fit_baselines() stashes the two lm objects on attr(fit, "models") for
  # inspection; those carry a full 34k-row model frame + QR each, so strip them
  # before serialising or the residual file balloons to ~90 MB.
  attr(out, "models") <- NULL
  path <- file.path(results_dir, paste0("player_dev_residuals_", cut, ".rds"))
  saveRDS(out, path)
  cat("Wrote", path, "(", nrow(out), "player-seasons ).\n")
  invisible(out)
}

# Runs Phase 1 end to end for one cut: base table -> baselines -> confound
# checks -> face validity -> save. Deliverable: player_dev_residuals_<cut>.rds.
cvg_run_phase1 <- function(cut = c("top5", "14league"),
                           seasons     = 2005:xx_last_data_season,
                           min_value   = 25000,
                           results_dir = "data/results",
                           save        = TRUE) {
  cut <- match.arg(cut)
  sep <- function(t) cat("\n", strrep("=", 62), "\n", t, "\n", strrep("=", 62), "\n\n", sep = "")

  sep(paste("PHASE 1 — BUILD PLAYER-SEASON BASE —", cut))
  base <- cvg_build_player_seasons(cut, seasons = seasons, min_value = min_value)

  sep("PHASE 1 — FIT BASELINE EXPECTATION MODELS")
  fit <- cvg_fit_baselines(base)

  sep("PHASE 1 — CONFOUND SANITY CHECKS")
  confounds <- cvg_check_confounds(fit)

  sep("PHASE 1 — FACE VALIDITY")
  face <- cvg_face_check(fit)

  resid <- if (save) cvg_save_residuals(fit, cut, results_dir = results_dir) else NULL

  sep(paste("PHASE 1 COMPLETE —", cut))
  cat("Player-seasons:      ", nrow(fit), "\n")
  cat("CDE-total R^2:       ", round(summary(attr(fit, "models")$total)$r.squared, 4), "\n")
  cat("Residual SD:         ", round(sd(fit$dev_resid), 4), "\n")

  invisible(list(base = base, fit = fit, confounds = confounds,
                 face = face, residuals = resid))
}

# =============================================================================
# Phase 2 — coach attribution + the CDE BLUP (the "M4->M5" analog)
# =============================================================================

# Per-team-season coach game-shares, from the M5 attribution spine
# (xx_assign_matches_to_coaches): the fraction of the team's attributed league
# matches each coach was in charge for. For a single-coach season the share is 1;
# a mid-season change splits it. Matches with no coach bracket are excluded and
# the shares renormalise over the attributed matches. This is the games-share
# fallback the design (sec. 3.4) specifies, used because the value snapshot is a
# single season-level number (verified Phase 1) and cannot resolve *which*
# coach's spell a mark was set in.
cvg_coach_game_shares <- function(team_sids) {
  coaches <- xx_data_cache$coaches
  matches <- xx_data_cache$matches

  purrr::map_df(team_sids, function(team_sid) {
    team_matches <- matches |>
      filter(home_team_id == team_sid | away_team_id == team_sid)

    attributed <- xx_assign_matches_to_coaches(
      team_matches,
      coaches |> filter(team_season_id == team_sid)
    )

    attributed |>
      filter(!is.na(coach_id)) |>
      group_by(coach_id, coach_name) |>
      summarize(coach_games = n(), .groups = "drop") |>
      mutate(team_season_id = team_sid,
             game_share     = coach_games / sum(coach_games))
  })
}

# Explodes each player-season into one row per coach who ran the club that
# season, carrying the development residual and an exposure weight
#   weight = pct_minutes * game_share
# pct_minutes is the player's share of league team-minutes (0-0.091, ever-present),
# so it is league-normalised exposure (raw minutes_played mixes competitions);
# game_share splits a multi-coach season. A player who never played (pct 0) gets
# weight 0 and drops out. This is the mixed model's input.
cvg_attribute <- function(fit_or_resid) {
  shares <- cvg_coach_game_shares(unique(fit_or_resid$team_season_id))

  attr_tbl <- fit_or_resid |>
    filter(has_minutes, pct_minutes > 0) |>
    # one player-season legitimately maps to several coach rows (a split season),
    # and one coach row to several players — the expansion is intended
    inner_join(shares, by = "team_season_id", relationship = "many-to-many") |>
    mutate(weight = pct_minutes * game_share) |>
    select(player_id, player_name, player_age, position_group, coach_id, coach_name,
           club_id, team_season_id, team_name, league, season,
           coach_games, pct_minutes, weight, dev_resid, dev_resid_dev)

  cat("=== Coach attribution ===\n")
  cat("Player-coach rows:      ", nrow(attr_tbl), "\n")
  cat("Distinct coaches:       ", n_distinct(attr_tbl$coach_id), "\n")
  cat("Distinct player-seasons:", n_distinct(paste(attr_tbl$player_id, attr_tbl$team_season_id)), "\n")
  multi <- attr_tbl |> count(player_id, team_season_id) |> filter(n > 1)
  cat("Player-seasons split across >1 coach:", nrow(multi),
      sprintf("(%.1f%%)\n", 100 * nrow(multi) / n_distinct(paste(attr_tbl$player_id, attr_tbl$team_season_id))))
  attr_tbl
}

# The CDE mixed model (design sec. 3.5). The (1|player_id) random effect is the
# metric's integrity, NOT optional: the same player recurs under many coaches and
# carries persistent, unmodelled appreciation (a generational talent rises under
# whoever coaches him). Without it a coach handed rising talents is credited for
# their trajectory; with it the coach BLUP is identified from players who deviate
# from their OWN trend under this coach vs others. club RE absorbs a club's
# development environment. Weighted by exposure; ML for the LRT.
#
# Fits one response (dev_resid = CDE-total, or dev_resid_dev = CDE-development).
# Coaches are kept if they have >= min_stints team-seasons and >= min_games total
# attributed games (the shrinkage handles the rest); the bar mirrors M5.
cvg_fit_cde <- function(attr_tbl, response = "dev_resid",
                        min_games = 10, min_stints = 3, label = "CDE") {
  if (!requireNamespace("lme4", quietly = TRUE)) stop("lme4 required")

  coach_tot <- attr_tbl |>
    group_by(coach_id) |>
    summarize(n_stints    = n_distinct(team_season_id),
              total_games = sum(coach_games[!duplicated(team_season_id)]),
              .groups = "drop") |>
    filter(n_stints >= min_stints, total_games >= min_games)

  d <- attr_tbl |>
    filter(coach_id %in% coach_tot$coach_id) |>
    rename(resp = all_of(response)) |>
    filter(!is.na(resp), weight > 0)

  cat(sprintf("=== CDE mixed model (%s: %s) ===\n", label, response))
  cat("Observations (player-coach rows):", nrow(d), "\n")
  cat("Coaches:", n_distinct(d$coach_id), " players:", n_distinct(d$player_id),
      " clubs:", n_distinct(d$club_id), "\n")

  m_full <- lme4::lmer(resp ~ (1 | player_id) + (1 | club_id) + (1 | coach_id),
                       data = d, weights = weight, REML = FALSE,
                       control = lme4::lmerControl(optimizer = "bobyqa"))
  m_null <- lme4::lmer(resp ~ (1 | player_id) + (1 | club_id),
                       data = d, weights = weight, REML = FALSE,
                       control = lme4::lmerControl(optimizer = "bobyqa"))

  chi_sq <- 2 * as.numeric(stats::logLik(m_full) - stats::logLik(m_null))
  df_lrt <- attr(stats::logLik(m_full), "df") - attr(stats::logLik(m_null), "df")
  p_lrt  <- pchisq(chi_sq, df = df_lrt, lower.tail = FALSE)

  vc <- as.data.frame(lme4::VarCorr(m_full))[, c("grp", "vcov", "sdcor")]
  vc$pct <- round(100 * vc$vcov / sum(vc$vcov), 1)
  cat("Variance components (grp / var / sd / %):\n")
  for (i in seq_len(nrow(vc)))
    cat(sprintf("  %-10s %.4f  %.4f  %4.1f%%\n", vc$grp[i], vc$vcov[i], vc$sdcor[i], vc$pct[i]))
  cat(sprintf("LRT coach effect: chi-sq = %.2f  df = %d  p = %.4g\n", chi_sq, df_lrt, p_lrt))

  re <- lme4::ranef(m_full)$coach_id
  blups <- data.frame(coach_id = rownames(re), cde = re[, 1],
                      stringsAsFactors = FALSE) |>
    left_join(coach_tot, by = "coach_id") |>
    # one row per id: a coach_id carrying two name spellings would make this a
    # one-to-many join and duplicate his BLUP row (see xx_canonical_coach_names)
    left_join(attr_tbl |> distinct(coach_id, coach_name) |>
                group_by(coach_id) |> slice(1) |> ungroup(), by = "coach_id") |>
    mutate(n_clubs = NA_integer_) |>
    arrange(desc(cde))

  nclub <- d |> group_by(coach_id) |> summarize(n_clubs = n_distinct(club_id), .groups = "drop")
  blups <- blups |> select(-n_clubs) |> left_join(nclub, by = "coach_id")

  list(model = m_full, lrt = list(chi_sq = chi_sq, df = df_lrt, p = p_lrt),
       var_components = vc, blups = blups)
}

# Coach-stint table (one row per coach x team-season) with an exposure-weighted
# development residual, so the M5 significance helpers (compute_coach_stats +
# add_significance: games-weighted mean, >=3-stint FDR t-test) can be reused
# verbatim by presenting the stint residual under the name they expect. n_games
# is the coach's attributed games in that team-season (the M5 weight).
cvg_coach_stints <- function(attr_tbl, response = "dev_resid") {
  attr_tbl |>
    rename(resp = all_of(response)) |>
    group_by(coach_id, coach_name, team_season_id, team_name, league, season) |>
    summarize(
      n_games              = first(coach_games),
      partial_residual_ppg = weighted.mean(resp, weight),
      .groups              = "drop"
    )
}

# =============================================================================
# Validation (design sec. 6) — pre-registered, read before any ranking
# =============================================================================

# The reflection test (design sec. 5.4), the make-or-break one. Market value is
# marked up *because* the team overperformed under the coach, so CDE and the
# points BLUP are mechanically entangled. Correlate CDE with the points BLUP and
# report the residual (orthogonal) signal. If nothing survives, CDE is points
# re-expressed in euros and must be reported as such; if a component survives,
# THAT is the genuinely new information (development independent of results).
cvg_validate_points <- function(cde_blups, cut, results_dir = "data/results") {
  pts <- readRDS(file.path(results_dir, paste0("coach_blups_", cut, ".rds"))) |>
    select(coach_id, points_blup = blup)
  d <- cde_blups |> inner_join(pts, by = "coach_id")

  r  <- cor(d$cde, d$points_blup)
  fit <- lm(cde ~ points_blup, data = d)
  d$cde_orth <- residuals(fit)
  share_orth <- var(d$cde_orth) / var(d$cde)

  cat("=== Reflection test: CDE vs points BLUP ===\n")
  cat("Coaches matched:            ", nrow(d), "\n")
  cat("cor(CDE, points BLUP):      ", round(r, 4), "\n")
  cat("R^2 (points explains CDE):  ", round(r^2, 4), "\n")
  cat("Orthogonal variance share:  ", round(share_orth, 4),
      "  (fraction of CDE NOT explained by points)\n")
  if (r^2 > 0.8) {
    cat("VERDICT: CDE is largely points re-expressed — report as such, not as new signal.\n")
  } else {
    cat("VERDICT: a substantial CDE component is orthogonal to points — a genuinely new axis.\n")
  }
  invisible(list(n = nrow(d), r = r, share_orth = share_orth, data = d))
}

# Repeatability OOS (design sec. 6). Split each coach's stints into even/odd
# seasons, take the exposure-weighted mean development residual in each half, and
# correlate across coaches with enough data in both halves. A metric that does
# not repeat across a coach's own career is noise, not a coach trait.
cvg_repeatability <- function(attr_tbl, response = "dev_resid", min_games_half = 500) {
  d <- attr_tbl |>
    rename(resp = all_of(response)) |>
    mutate(half = if_else(season %% 2 == 0, "even", "odd"))

  halves <- d |>
    group_by(coach_id, coach_name, half) |>
    summarize(mean_resid = weighted.mean(resp, weight),
              exposure   = sum(weight), n = n(), .groups = "drop")

  wide <- halves |>
    tidyr::pivot_wider(id_cols = c(coach_id, coach_name),
                       names_from = half,
                       values_from = c(mean_resid, exposure, n)) |>
    filter(!is.na(mean_resid_even), !is.na(mean_resid_odd),
           n_even >= 8, n_odd >= 8)

  ct <- cor.test(wide$mean_resid_even, wide$mean_resid_odd)
  cat("=== Repeatability (even vs odd seasons) ===\n")
  cat("Coaches with both halves:", nrow(wide), "\n")
  cat("Split-half correlation:  ", round(unname(ct$estimate), 4),
      sprintf(" (p = %.3g, 95%% CI [%.3f, %.3f])\n",
              ct$p.value, ct$conf.int[1], ct$conf.int[2]))
  if (ct$estimate > 0.2 && ct$p.value < 0.05) {
    cat("VERDICT: CDE repeats within a coach's career — carries a stable signal.\n")
  } else {
    cat("VERDICT: CDE does not repeat — treat as noise (on-brand null).\n")
  }
  invisible(list(cor = unname(ct$estimate), p = ct$p.value, data = wide))
}

# Face validity (design sec. 6): known academy/development tenures should surface
# high, buy-it-ready galactico spells lower. A smell test on the ranked BLUP.
cvg_face_coaches <- function(cde_tbl, n = 20) {
  cat("=== Top", n, "coaches by CDE-total ===\n")
  print(cde_tbl |> arrange(desc(cde_total)) |>
          select(coach_name, n_stints, total_games, n_clubs,
                 cde_total, cde_dev, opportunity) |> head(n), n = Inf)
  cat("\n=== Bottom", n, "coaches by CDE-total ===\n")
  print(cde_tbl |> arrange(cde_total) |>
          select(coach_name, n_stints, total_games, n_clubs,
                 cde_total, cde_dev, opportunity) |> head(n), n = Inf)
}

# Assembles the per-coach CDE table: both BLUPs (total + development), the
# Phase-3 opportunity gap (total - development = value grown by giving minutes
# rather than by per-minute improvement), and the M5-style games-weighted stint
# mean + >=3-stint FDR significance for CDE-total.
cvg_combine <- function(cde_total, cde_dev, stint_stats) {
  cde_total$blups |>
    select(coach_id, coach_name, n_stints, total_games, n_clubs, cde_total = cde) |>
    inner_join(cde_dev$blups |> select(coach_id, cde_dev = cde), by = "coach_id") |>
    mutate(opportunity = cde_total - cde_dev) |>
    left_join(stint_stats |> select(coach_id, mean_resid = mean_residual,
                                    p_adj, significant),
              by = "coach_id") |>
    arrange(desc(cde_total)) |>
    as_tibble()
}

cvg_save_cde <- function(cde_tbl, stints, cut, results_dir = "data/results") {
  saveRDS(cde_tbl, file.path(results_dir, paste0("coach_value_growth_", cut, ".rds")))
  saveRDS(stints,  file.path(results_dir, paste0("cde_coach_stints_", cut, ".rds")))
  cat("Wrote coach_value_growth_", cut, ".rds (", nrow(cde_tbl), " coaches) and ",
      "cde_coach_stints_", cut, ".rds (", nrow(stints), " stints).\n", sep = "")
  invisible(cde_tbl)
}

# =============================================================================
# Phase 4 — cross-club robustness (movers)
# =============================================================================

# Same as cvg_build_player_seasons but keeps MOVER pairs: the player is at a
# different club in t+1 (a transfer). The season-t growth window is attributed to
# the *selling* club's season-t coach (design sec. 5.5), so the base row is the
# season-t (selling) team-season exactly as in the same-club build. Used only to
# test whether CDE is stable when movers are added — movers carry transfer-driven
# value jumps and a survivorship tilt, so they are a robustness pass, not the
# headline sample.
cvg_build_movers <- function(cut = c("top5", "14league"),
                             seasons = 2005:xx_last_data_season, min_value = 25000) {
  cut <- match.arg(cut)
  cut_ts <- build_model_dataset(seasons, leagues = cvg_cut_leagues(cut)) |>
    select(team_season_id, team_name, league, season)

  traj <- xx_data_cache$players |>
    filter(!is.na(player_market_value_euro), player_market_value_euro > 0) |>
    mutate(club_id = sub("/saison_id/\\d+$", "", team_season_id),
           season  = as.integer(sub(".*/saison_id/(\\d+).*", "\\1", team_season_id))) |>
    arrange(player_id, season) |>
    group_by(player_id) |>
    mutate(value_next  = lead(player_market_value_euro),
           season_next = lead(season),
           club_next   = lead(club_id),
           value_prev  = lag(player_market_value_euro),
           season_prev = lag(season),
           club_prev   = lag(club_id)) |>
    ungroup()

  traj |>
    filter(!is.na(value_next), season_next == season + 1, club_next != club_id,
           player_market_value_euro >= min_value, value_next >= min_value) |>
    inner_join(cut_ts, by = c("team_season_id", "season")) |>
    mutate(
      position_group = cvg_position_group(player_position),
      g              = log(value_next / player_market_value_euro),
      log_value_t    = log(player_market_value_euro),
      has_prior      = !is.na(value_prev) & season_prev == season - 1 & club_prev == club_id,
      prior_growth   = if_else(has_prior, log(player_market_value_euro / value_prev), 0),
      has_minutes    = !is.na(percent_minutes_played),
      pct_minutes    = if_else(has_minutes, percent_minutes_played, 0)
    ) |>
    filter(!is.na(player_age), !is.na(position_group))
}

# Refits the baseline + CDE on same-club UNION movers and rank-correlates the
# CDE-total BLUP against the same-club-only fit. Stability => the same-club
# attribution is not an artefact of dropping transfers (design sec. 5.5).
cvg_robustness_movers <- function(base_same, cde_same_blups, cut) {
  movers <- cvg_build_movers(cut)
  cat("Mover pairs added:", nrow(movers), "\n")

  combined <- bind_rows(
    base_same  |> mutate(is_mover = FALSE),
    movers     |> mutate(is_mover = TRUE)
  )
  # refit baseline on the union so the movers' growth is de-confounded on the
  # same right-hand side, then attribute
  fit_c <- cvg_fit_baselines(combined)
  attr_c <- cvg_attribute(fit_c)
  cde_c  <- cvg_fit_cde(attr_c, "dev_resid", label = "CDE-total (with movers)")

  cmp <- cde_same_blups |> select(coach_id, cde_same = cde) |>
    inner_join(cde_c$blups |> select(coach_id, cde_movers = cde), by = "coach_id")
  r_p <- cor(cmp$cde_same, cmp$cde_movers)
  r_s <- cor(cmp$cde_same, cmp$cde_movers, method = "spearman")
  cat("=== Robustness: same-club vs +movers CDE ===\n")
  cat("Coaches compared:", nrow(cmp), "\n")
  cat("Pearson r:", round(r_p, 4), "  Spearman rho:", round(r_s, 4), "\n")
  if (r_s > 0.85) cat("VERDICT: CDE is stable to adding movers.\n")
  else cat("VERDICT: CDE shifts when movers are added — attribution is sample-sensitive.\n")
  invisible(list(pearson = r_p, spearman = r_s, data = cmp, cde_movers = cde_c))
}

# Runs Phases 2-4 + validation for one cut on top of a Phase-1 fit. Saves
# coach_value_growth_<cut>.rds. Returns everything for inspection.
cvg_run_phase2 <- function(phase1,
                           cut,
                           min_games   = 10,
                           min_stints  = 3,
                           results_dir = "data/results",
                           save        = TRUE,
                           run_movers  = TRUE) {
  sep <- function(t) cat("\n", strrep("=", 62), "\n", t, "\n", strrep("=", 62), "\n\n", sep = "")

  sep(paste("PHASE 2 — ATTRIBUTE TO COACHES —", cut))
  attr_tbl <- cvg_attribute(phase1$fit)

  sep("PHASE 2 — CDE-TOTAL MIXED MODEL")
  cde_total <- cvg_fit_cde(attr_tbl, "dev_resid", min_games, min_stints, "CDE-total")

  sep("PHASE 2 — CDE-DEVELOPMENT MIXED MODEL")
  cde_dev <- cvg_fit_cde(attr_tbl, "dev_resid_dev", min_games, min_stints, "CDE-development")

  sep("PHASE 2 — STINT MEANS + FDR SIGNIFICANCE (CDE-total)")
  stints <- cvg_coach_stints(attr_tbl, "dev_resid")
  stint_stats <- compute_coach_stats(stints, min_games = min_games, min_stints = 1,
                                     label = "log value growth") |>
    add_significance()

  sep("PHASE 2 — COMBINE")
  cde_tbl <- cvg_combine(cde_total, cde_dev, stint_stats)

  sep("VALIDATION — REFLECTION TEST (vs points BLUP)")
  vpoints <- cvg_validate_points(cde_total$blups, cut, results_dir)

  sep("VALIDATION — REPEATABILITY OOS")
  vrepeat <- cvg_repeatability(attr_tbl, "dev_resid")

  sep("VALIDATION — FACE VALIDITY")
  cvg_face_coaches(cde_tbl)

  movers <- NULL
  if (run_movers) {
    sep("PHASE 4 — CROSS-CLUB ROBUSTNESS (MOVERS)")
    movers <- cvg_robustness_movers(phase1$fit, cde_total$blups, cut)
  }

  if (save) cvg_save_cde(cde_tbl, stints, cut, results_dir)

  sep(paste("PHASE 2-4 COMPLETE —", cut))
  cat("Coaches with CDE:        ", nrow(cde_tbl), "\n")
  cat("Coach-effect LRT p:      ", signif(cde_total$lrt$p, 3), "\n")
  cat("cor(CDE, points BLUP):   ", round(vpoints$r, 3),
      sprintf(" (orthogonal share %.2f)\n", vpoints$share_orth))
  cat("Repeatability r:         ", round(vrepeat$cor, 3), "\n")
  if (run_movers) cat("Mover-robustness Spearman:", round(movers$spearman, 3), "\n")

  invisible(list(attr = attr_tbl, cde_total = cde_total, cde_dev = cde_dev,
                 stint_stats = stint_stats, cde_tbl = cde_tbl,
                 vpoints = vpoints, vrepeat = vrepeat, movers = movers))
}

# Full pipeline for one cut: Phase 1 then Phases 2-4 + validation.
cvg_run_all <- function(cut = c("top5", "14league"),
                        seasons = 2005:xx_last_data_season, results_dir = "data/results",
                        save = TRUE, run_movers = TRUE) {
  cut <- match.arg(cut)
  p1 <- cvg_run_phase1(cut, seasons = seasons, results_dir = results_dir, save = save)
  p2 <- cvg_run_phase2(p1, cut, results_dir = results_dir, save = save, run_movers = run_movers)
  invisible(c(list(phase1 = p1), p2))
}

# =============================================================================
# Follow-up exploration (2026-07-21): where does the development signal live, and
# does a pattern appear inside a player type?
#
# The headline CDE null (coach-level, does not repeat OOS) is a coach verdict. It
# leaves two open questions the mixed model's variance components only hint at:
#   1. Does the signal live at the CLUB instead? (club var was 12-19% in-sample)
#   2. Does a repeatable signal appear if we restrict to a player type (young
#      players, a position, a SofaScore archetype) rather than averaging over all?
# All of this is EXPLORATORY (same label as the CDE null) — a repeatable club or
# subgroup pattern would be a finding, but it is read against the same OOS bar.
# =============================================================================

# Generic even/odd-season split-half repeatability at an arbitrary grouping level
# (coach_id or club_id). Weighted mean development residual in even vs odd seasons,
# correlated across groups with enough player-seasons in both halves. This is the
# same honest OOS test the CDE null used, pointed at any level.
cvg_split_half <- function(tbl, group, response = "dev_resid",
                           weight_col = "weight", min_half = 8, label = group) {
  d <- tbl |>
    rename(grp = all_of(group), resp = all_of(response), w = all_of(weight_col)) |>
    filter(!is.na(resp), w > 0) |>
    mutate(half = if_else(season %% 2 == 0, "even", "odd"))

  halves <- d |>
    group_by(grp, half) |>
    summarize(m = weighted.mean(resp, w), n = n(), .groups = "drop")

  wide <- halves |>
    tidyr::pivot_wider(id_cols = grp, names_from = half, values_from = c(m, n)) |>
    filter(!is.na(m_even), !is.na(m_odd), n_even >= min_half, n_odd >= min_half)

  ct <- cor.test(wide$m_even, wide$m_odd)
  cat(sprintf("  %-26s groups = %4d   split-half r = %+.3f  (p = %.3g, CI [%+.2f, %+.2f])\n",
              label, nrow(wide), unname(ct$estimate), ct$p.value,
              ct$conf.int[1], ct$conf.int[2]))
  invisible(list(label = label, n = nrow(wide), r = unname(ct$estimate),
                 p = ct$p.value, ci = ct$conf.int, data = wide))
}

# Reduces the exploded player-coach attribution to ONE row per player-season, its
# PRIMARY coach (largest exposure weight that season). Needed for the cross-coach
# club test: a mid-season-change player-season otherwise contributes the SAME
# dev_resid to two coaches, and if they fall in different comparison groups that
# shared value inflates the correlation mechanically. Primary-coach collapse makes
# the coach groups disjoint in player-seasons.
cvg_primary_coach <- function(attr_tbl) {
  attr_tbl |>
    filter(!is.na(dev_resid), weight > 0) |>
    group_by(player_id, team_season_id) |>
    slice_max(weight, n = 1, with_ties = FALSE) |>
    ungroup()
}

# Question 1, the decisive club test: are teams consistent in growing players
# EVEN ACROSS COACHES? For each club, order its coaches by first season and split
# them into two alternating sets (A = 1st,3rd,5th... coach; B = 2nd,4th...), so
# the two sets are DIFFERENT coaches from DIFFERENT periods. Correlate the club's
# weighted-mean development residual under set A against set B across all clubs
# with a coach in each set. A positive correlation means the club grows players
# consistently as managers come and go — development as a club property, the
# natural complement to the coach null. Player-seasons are collapsed to their
# primary coach first (cvg_primary_coach) so a split season cannot appear in both
# groups; a per-coach floor (min_coach_n) keeps each club-coach cell from being a
# single noisy player-season.
cvg_club_cross_coach <- function(attr_tbl, min_coach_n = 3) {
  cc <- cvg_primary_coach(attr_tbl) |>
    group_by(club_id, coach_id) |>
    summarize(m = weighted.mean(dev_resid, weight), w = sum(weight),
              first_season = min(season), n = n(), .groups = "drop") |>
    filter(n >= min_coach_n) |>
    arrange(club_id, first_season) |>
    group_by(club_id) |>
    mutate(grp = if_else(row_number() %% 2 == 1, "A", "B")) |>
    ungroup()

  cg <- cc |>
    group_by(club_id, grp) |>
    summarize(m = weighted.mean(m, w), ncoach = n(), .groups = "drop") |>
    tidyr::pivot_wider(id_cols = club_id, names_from = grp,
                       values_from = c(m, ncoach)) |>
    filter(!is.na(m_A), !is.na(m_B))

  ct <- cor.test(cg$m_A, cg$m_B)
  cat("=== Club consistency across coaching changes ===\n")
  cat("Clubs with coaches in both alternating sets:", nrow(cg), "\n")
  cat(sprintf("Cross-coach-set correlation: r = %+.3f  (p = %.3g, 95%% CI [%+.2f, %+.2f])\n",
              unname(ct$estimate), ct$p.value, ct$conf.int[1], ct$conf.int[2]))
  if (ct$estimate > 0.2 && ct$p.value < 0.05)
    cat("VERDICT: clubs DO grow players consistently across coaches — a club property.\n")
  else
    cat("VERDICT: no consistent club development signal across coaches either.\n")
  invisible(list(n = nrow(cg), r = unname(ct$estimate), p = ct$p.value, data = cg))
}

# Cleaner cross-check on the same question: consecutive-coach persistence. Order a
# club's coaches by first season, take each coach's primary-attribution mean
# development residual, and correlate regime k against regime k+1 across all
# consecutive same-club coach pairs. A positive lag-1 correlation means that when
# a club changes manager, its player-development level carries over to the next
# manager — the club sets the level, not the coach. Uses primary-coach collapse so
# a handover season is not shared between the two regimes.
cvg_club_regime_persistence <- function(attr_tbl, min_coach_n = 3) {
  cc <- cvg_primary_coach(attr_tbl) |>
    group_by(club_id, coach_id) |>
    summarize(m = weighted.mean(dev_resid, weight), n = n(),
              first_season = min(season), .groups = "drop") |>
    filter(n >= min_coach_n) |>
    arrange(club_id, first_season) |>
    group_by(club_id) |>
    mutate(m_next = lead(m)) |>
    filter(!is.na(m_next)) |>
    ungroup()

  ct <- cor.test(cc$m, cc$m_next)
  cat("=== Consecutive-coach persistence (regime k vs k+1, same club) ===\n")
  cat("Consecutive same-club coach pairs:", nrow(cc), "\n")
  cat(sprintf("Lag-1 correlation: r = %+.3f  (p = %.3g, 95%% CI [%+.2f, %+.2f])\n",
              unname(ct$estimate), ct$p.value, ct$conf.int[1], ct$conf.int[2]))
  invisible(list(n = nrow(cc), r = unname(ct$estimate), p = ct$p.value, data = cc))
}

# Question 2a: does a repeatable coach signal appear inside an age band or a
# position group, rather than averaging over everyone? Runs the coach split-half
# within each subset. (Also reports the club split-half within young players, the
# most development-relevant slice.)
cvg_subgroup_repeat <- function(attr_tbl) {
  bands <- list(
    "age <= 21 (developing)" = attr_tbl |> filter(player_age <= 21),
    "age 22-28 (prime)"      = attr_tbl |> filter(player_age >= 22, player_age <= 28),
    "age >= 29 (veteran)"    = attr_tbl |> filter(player_age >= 29)
  )
  cat("=== Coach split-half repeatability by age band ===\n")
  age_out <- lapply(names(bands), function(nm)
    cvg_split_half(bands[[nm]], "coach_id", label = nm))

  cat("\n=== Coach split-half repeatability by position group ===\n")
  pos_out <- lapply(sort(unique(attr_tbl$position_group)), function(pg)
    cvg_split_half(attr_tbl |> filter(position_group == pg), "coach_id",
                   label = paste0("pos = ", pg)))

  cat("\n=== Within young players (age <= 21): coach vs club ===\n")
  young <- attr_tbl |> filter(player_age <= 21)
  cvg_split_half(young, "coach_id", label = "young / coach")
  cvg_split_half(young, "club_id",  label = "young / club")

  invisible(list(age = age_out, pos = pos_out))
}

# Builds a stable (player_id, season) -> SofaScore archetype map by unioning the
# per-season crosswalks (player_ss_id <-> player_id) and joining the archetype
# cache. Big-5, 2015/16-2024/25 only (SofaScore coverage).
cvg_archetype_map <- function(cache_dir = "data/cache/sofascore") {
  xw_files <- list.files(cache_dir, pattern = "^crosswalk_", full.names = TRUE)
  xw <- purrr::map_df(xw_files, ~ readRDS(.x) |>
                        select(player_ss_id, player_id)) |>
    filter(!is.na(player_id)) |>
    distinct(player_ss_id, player_id)

  readRDS(file.path(cache_dir, "archetypes.rds")) |>
    select(player_ss_id, season = season_start_year, archetype_label) |>
    inner_join(xw, by = "player_ss_id") |>
    distinct(player_id, season, archetype_label)
}

# Question 2b: SofaScore archetypes. (a) Which player types appreciate MORE than
# the age/price/position baseline predicts (a descriptive, coach-free read on the
# development residual)? (b) Does the coach signal repeat within the biggest
# archetypes? Restricted to the big-5 archetype-matched subset of the CDE fit.
cvg_archetype_analysis <- function(fit, attr_tbl, min_half = 6) {
  amap <- cvg_archetype_map()
  d <- fit |> inner_join(amap, by = c("player_id", "season"))
  cat("=== Archetype-matched player-seasons:", nrow(d), "of", nrow(fit), "===\n\n")

  by_arch <- d |>
    group_by(archetype_label) |>
    summarize(n = n(),
              mean_dev = weighted.mean(dev_resid, pmax(pct_minutes, 1e-6)),
              median_g = median(g), .groups = "drop") |>
    arrange(desc(mean_dev))
  cat("Mean development residual by archetype (weighted; +ve = appreciates beyond baseline):\n")
  print(as.data.frame(by_arch |> mutate(across(c(mean_dev, median_g), \(x) round(x, 3)))),
        row.names = FALSE)

  attr_arch <- attr_tbl |> inner_join(amap, by = c("player_id", "season"))
  big <- by_arch |> filter(n >= 800) |> pull(archetype_label)
  cat("\nCoach split-half repeatability within the largest archetypes:\n")
  arch_rep <- lapply(big, function(a)
    cvg_split_half(attr_arch |> filter(archetype_label == a), "coach_id",
                   min_half = min_half, label = a))

  cat("\nClub split-half within the archetype-matched subset:\n")
  cvg_split_half(attr_arch, "club_id", min_half = min_half, label = "all archetypes / club")

  invisible(list(by_archetype = by_arch, arch_rep = arch_rep, matched = d))
}

# Runs the whole follow-up exploration on top of a Phase-1 fit + attribution.
cvg_explore <- function(phase1, attr_tbl, cut) {
  sep <- function(t) cat("\n", strrep("=", 62), "\n", t, "\n", strrep("=", 62), "\n\n", sep = "")
  fit <- phase1$fit

  sep(paste("WHERE DOES THE SIGNAL LIVE — coach vs club —", cut))
  cat("Even/odd split-half repeatability (weighted mean dev_resid):\n")
  coach_rep <- cvg_split_half(attr_tbl, "coach_id", label = "coach")
  club_rep  <- cvg_split_half(attr_tbl, "club_id",  label = "club")

  sep("CLUB CONSISTENCY ACROSS COACHING CHANGES")
  cross <- cvg_club_cross_coach(attr_tbl)
  cat("\n")
  regime <- cvg_club_regime_persistence(attr_tbl)

  sep("DOES A PATTERN APPEAR INSIDE A PLAYER TYPE?")
  subs <- cvg_subgroup_repeat(attr_tbl)

  arch <- NULL
  if (cut == "top5" || cut == "14league") {
    sep("SOFASCORE ARCHETYPES (big-5 2015-2024 subset)")
    arch <- tryCatch(cvg_archetype_analysis(fit, attr_tbl),
                     error = function(e) { cat("archetype join skipped:", conditionMessage(e), "\n"); NULL })
  }

  invisible(list(coach_rep = coach_rep, club_rep = club_rep, cross = cross,
                 regime = regime, subgroups = subs, archetypes = arch))
}
