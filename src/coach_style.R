source("coach_recommender.R")   # -> the coach_fit.R chain (pa_read,
                                #    ss_big5_leagues, cf_season_match_coaches,
                                #    coach_attribution.R), plus cr_rigidity() /
                                #    cr_build_coach_formations() for Layer C

# coach_style.R
#
# Layer B of the coach descriptive profile (Docs/Coach_Descriptive_Profile_Design.md,
# phase 3): the style fingerprint — "what does this coach's team actually do on
# the pitch?". Functions use the sy_ prefix. Pure cache-reader: no scraping, no
# chromote.
#
# Honesty label (design sec. 0): **descriptive-clean**. These axes are literally
# what the team did, z-scored against its contemporaries. There is no causal
# content and no attribution leap — but it is the *team's* style, jointly
# produced by the coach and the squad he was given (design sec. 5). Never state
# it as "this coach is a possession coach" in the abstract.
#
# Recipe (mirrors the M6 archetype layer, pointed at team style):
#   per-player-per-match  ->  team-match  ->  z-score within league x season
#   ->  coach-stint mean  ->  games-weighted coach profile
#
# Coverage: big-5 only, 2015/16-2024/25 (SofaScore match_stats). Coaches seen
# only outside the big 5 get Layer A but no fingerprint — say so, don't fabricate
# a radar (design sec. 8).
sy_seasons <- ss_seasons()

# --- data facts, all verified 2026-07-16 (do not re-derive from the docs) -----
#
# * match_stats$team_ss_id is the player's scrape-time club and agrees with the
#   actual match side only 41.5% of the time. The side MUST come from is_home +
#   the event's home/away ids. (Same caveat as elsewhere; it bites hardest here.)
# * `substitute == FALSE` identifies the starting XI exactly — 11 per side in
#   every one of PL 2023's 760 team-matches.
# * CLAUDE.md's "ballRecovery / outfielderBlocks exist only from 2023/24" is a
#   fact about the SEASON stats cache (stats_<sid>.rds). In match_stats,
#   `ballRecovery` is populated in all 50 league-seasons (PL 2015 mean 5.0 per
#   player-match). The design's inherited "do not use" therefore does not apply
#   to this layer, which reads match_stats.
# * The reverse trap: `possessionWonAttThird` — the design's pressing-HEIGHT
#   input — exists in the season cache but is ABSENT from match_stats entirely.
#   Height therefore cannot be attributed to a stint, only to a team-season; see
#   sy_season_pressing_height() and the blended flag.
# * Counting conventions drift over the decade (ballRecovery means 5.0 -> 3.8,
#   interceptions 2.2 -> 1.5). Z-scoring within league x season absorbs this,
#   which is exactly why the design insists on it.

sy_match_fields <- c(
  "totalPass", "accuratePass",
  "totalOppositionHalfPasses", "totalOwnHalfPasses",
  "totalLongBalls", "totalCross", "totalShots",
  "totalTackle", "interceptionWon", "fouls",
  "ballRecovery", "touches", "totalContest"
)

# Per (event, team) sums of the raw match_stats fields, with the match side
# derived from is_home + the event ids.
sy_season_team_stats <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  events <- pa_read("events", sid) |>
    filter(status_type == "finished") |>
    select(event_ss_id, home_team_ss_id, away_team_ss_id)

  agg <- pa_read("match_stats", sid) |>
    filter(stat_name %in% sy_match_fields) |>
    inner_join(events, by = "event_ss_id") |>
    mutate(team_ss_id = if_else(is_home, home_team_ss_id, away_team_ss_id)) |>
    group_by(event_ss_id, team_ss_id, stat_name) |>
    summarize(v = sum(stat_value, na.rm = TRUE), .groups = "drop") |>
    pivot_wider(names_from = stat_name, values_from = v, values_fill = 0)

  for (f in setdiff(sy_match_fields, names(agg))) agg[[f]] <- 0
  agg
}

# Per (event, team): set-piece share of shots and mean shot distance from the
# attacked goal. From the shotmap, which SofaScore is missing for a cluster of
# 2018/19 matches (~20-31 per league outside the PL) — those team-matches get NA
# and simply drop out of the stint mean for the shot-derived axes only.
#
# Shot coordinates put the ATTACKED GOAL AT (0, 50) (CLAUDE.md), so distance is
# measured from there, not from the origin. x and y are both 0-100 but span
# different physical distances (pitch ~105m long, ~68m wide), so they are scaled
# to metres before the distance — otherwise "distance from goal" is stretched
# across the pitch and a wide shot looks further out than it is.
sy_season_shot_features <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  events <- pa_read("events", sid) |>
    filter(status_type == "finished") |>
    select(event_ss_id, home_team_ss_id, away_team_ss_id)

  set_piece <- c("corner", "free-kick", "set-piece", "throw-in-set-piece")

  pa_read("shots", sid) |>
    inner_join(events, by = "event_ss_id") |>
    mutate(team_ss_id = if_else(is_home, home_team_ss_id, away_team_ss_id),
           dist = sqrt((x * 1.05)^2 + ((y - 50) * 0.68)^2)) |>
    group_by(event_ss_id, team_ss_id) |>
    summarize(
      set_piece_share = mean(situation %in% set_piece),
      shot_dist       = mean(dist, na.rm = TRUE),
      .groups         = "drop"
    )
}

# Per (event, team): share of the starting XI retained from the team's previous
# league match. The first match of a season has no predecessor and gets NA.
# Churn across a mid-season coach change is attributed to the incoming coach —
# picking a different XI than your predecessor is your choice, not his.
sy_season_xi_churn <- function(league_key, year, spine) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  events <- pa_read("events", sid) |>
    filter(status_type == "finished") |>
    select(event_ss_id, home_team_ss_id, away_team_ss_id)

  xi <- pa_read("match_stats", sid) |>
    filter(stat_name == "minutesPlayed", !substitute) |>
    distinct(event_ss_id, player_ss_id, is_home) |>
    inner_join(events, by = "event_ss_id") |>
    mutate(team_ss_id = if_else(is_home, home_team_ss_id, away_team_ss_id)) |>
    inner_join(spine |> distinct(event_ss_id, team_ss_id, match_date),
               by = c("event_ss_id", "team_ss_id"))

  xi |>
    group_by(event_ss_id, team_ss_id, match_date) |>
    summarize(xi_set = list(player_ss_id), .groups = "drop") |>
    arrange(team_ss_id, match_date) |>
    group_by(team_ss_id) |>
    mutate(xi_stability = vapply(seq_along(xi_set), function(i) {
      if (i == 1) return(NA_real_)
      length(intersect(xi_set[[i]], xi_set[[i - 1]])) / 11
    }, numeric(1))) |>
    ungroup() |>
    select(event_ss_id, team_ss_id, xi_stability)
}

# Season-level pressing HEIGHT: possessionWonAttThird per team, per match.
# Only available in the season stats cache, so it cannot be split between two
# coaches of the same team-season — rows where the club changed coach carry a
# blended value and are flagged (`height_blended`). Kept as a secondary
# descriptor, never mixed into the per-match axes.
#
# The blending is not a rare edge case: **58% of stints sit in a team-season with
# more than one coach**, and 128 of 337 profiles are more than half blended
# (games-weighted `height_blended_share`). For those coaches the height number is
# substantially the club's, not theirs. Surface the flag wherever height is shown.
sy_season_pressing_height <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  players <- pa_read("players", sid) |> select(player_ss_id, team_ss_id)

  pa_read("stats", sid) |>
    filter(stat_name == "possessionWonAttThird") |>
    inner_join(players, by = "player_ss_id") |>
    group_by(team_ss_id) |>
    summarize(poss_won_att3 = sum(stat_value, na.rm = TRUE), .groups = "drop") |>
    mutate(league = league_key, season_start_year = year)
}

# One league-season of team-match style features, joined to the TM team_season_id
# and the coach in charge.
sy_season_team_matches <- function(league_key, year) {
  spine <- cf_season_match_coaches(league_key, year)

  base <- sy_season_team_stats(league_key, year) |>
    inner_join(spine |> select(event_ss_id, team_ss_id, team_season_id,
                               coach_id, match_date, league, season_start_year),
               by = c("event_ss_id", "team_ss_id"))

  opp <- base |>
    select(event_ss_id, team_ss_id,
           opp_passes = totalPass, opp_shots = totalShots) |>
    inner_join(base |> select(event_ss_id, team_ss_id),
               by = "event_ss_id", relationship = "many-to-many") |>
    filter(team_ss_id.x != team_ss_id.y) |>
    select(event_ss_id, team_ss_id = team_ss_id.y, opp_passes, opp_shots)

  shots <- sy_season_shot_features(league_key, year)
  opp_shot_dist <- shots |>
    select(event_ss_id, team_ss_id, shot_dist) |>
    inner_join(base |> select(event_ss_id, team_ss_id),
               by = "event_ss_id", relationship = "many-to-many") |>
    filter(team_ss_id.x != team_ss_id.y) |>
    select(event_ss_id, team_ss_id = team_ss_id.y, opp_shot_dist = shot_dist)

  churn <- sy_season_xi_churn(league_key, year, spine)

  base |>
    left_join(opp,           by = c("event_ss_id", "team_ss_id")) |>
    left_join(shots,         by = c("event_ss_id", "team_ss_id")) |>
    left_join(opp_shot_dist, by = c("event_ss_id", "team_ss_id")) |>
    left_join(churn,         by = c("event_ss_id", "team_ss_id")) |>
    mutate(
      def_actions = totalTackle + interceptionWon + fouls,
      # guard every ratio: a team can finish a match with 0 shots
      pass_share      = totalPass / na_if(totalPass + opp_passes, 0),
      pass_acc        = accuratePass / na_if(totalPass, 0),
      opp_half_share  = totalOppositionHalfPasses /
                          na_if(totalOppositionHalfPasses + totalOwnHalfPasses, 0),
      press_intensity = def_actions / na_if(opp_passes, 0),
      recoveries      = ballRecovery,
      long_ball_share = totalLongBalls / na_if(totalPass, 0),
      passes_per_shot = totalPass / na_if(totalShots, 0),
      cross_share     = totalCross / na_if(totalPass, 0),
      shot_volume     = totalShots,
      shots_conceded  = opp_shots
    ) |>
    select(event_ss_id, team_ss_id, team_season_id, coach_id, match_date,
           league, season_start_year,
           pass_share, pass_acc, opp_half_share, press_intensity, recoveries,
           long_ball_share, passes_per_shot, cross_share, shot_volume,
           shots_conceded, set_piece_share, shot_dist, opp_shot_dist,
           xi_stability)
}

# The style axes. Each is an equal-weight mean of its members' z-scores —
# deliberately NOT a PCA or a fitted weighting: nothing here is trained against
# an outcome, so there is nothing to overfit, and the axes stay interpretable.
# `sign = -1` flips a feature so that every axis reads "more of the named trait".
#
# PRESSING — read this before "fixing" the axis (verified 2026-07-16).
# `pressing` (per-match, PPDA proxy) and `pressing_height` (season-level) are
# different traits, not two attempts at one; they correlate only r = 0.38 across
# stints. Intensity is how hard you contest per opponent pass — Gasperini,
# Hütter, Bosz, Iraola, Mendilibar, Klopp top it, which is a good pressing list.
# Height is where you win the ball — Guardiola, Mendilibar, Xavi, Tuchel, Klopp
# top it; Nuno Espírito Santo and Aguirre sit at the bottom, as they should.
# **Guardiola scores ~0 on intensity and +1.5 on height, and that is correct**:
# City make few defensive actions because opponents seldom hold the ball, yet
# they win it high. The design (sec. 3.3) expects "Guardiola high on pressing" —
# that expectation resolves to height, not intensity. Do not collapse the two.
sy_axes <- list(
  possession = list(
    features = c(pass_share = 1, pass_acc = 1, opp_half_share = 1),
    label = "Possession / control"),
  pressing = list(
    features = c(press_intensity = 1, recoveries = 1),
    label = "Pressing intensity"),
  directness = list(
    features = c(long_ball_share = 1, passes_per_shot = -1),
    label = "Directness / tempo"),
  width = list(
    features = c(cross_share = 1),
    label = "Width"),
  shot_volume = list(
    features = c(shot_volume = 1),
    label = "Shot volume"),
  chance_quality = list(
    features = c(shot_dist = -1),
    label = "Chance quality"),
  defensive_solidity = list(
    features = c(shots_conceded = -1, opp_shot_dist = 1),
    label = "Defensive solidity"),
  set_piece_reliance = list(
    features = c(set_piece_share = 1),
    label = "Set-piece reliance"),
  lineup_stability = list(
    features = c(xi_stability = 1),
    label = "Lineup stability")
)

sy_axis_labels <- vapply(sy_axes, \(a) a$label, character(1))

# Every big-5 team-match, 2015-2024. Slow (~10-15 min: match_stats is the
# largest cache and the coach attribution runs per league-season). Cache it.
sy_build_team_matches <- function(seasons = sy_seasons) {
  out <- bind_rows(lapply(names(ss_big5_leagues), function(lg) {
    bind_rows(lapply(seasons, function(yr) {
      cat("  ", lg, yr, "\n")
      sy_season_team_matches(lg, yr)
    }))
  }))

  feats <- unique(unlist(lapply(sy_axes, \(a) names(a$features))))
  cat("\n=== Team-match style features built ===\n")
  cat("Team-matches:           ", nrow(out), "\n")
  cat("Unattributed to a coach:", sum(is.na(out$coach_id)),
      sprintf("(%.2f%%)\n", 100 * mean(is.na(out$coach_id))))
  cat("\nFeature completeness (%% of team-matches non-NA):\n")
  for (f in feats) {
    cat(sprintf("  %-18s %5.1f%%\n", f, 100 * mean(!is.na(out[[f]]))))
  }
  out
}

# Z-score each feature within league x season (design sec. 3.2: a coach is
# measured against his contemporaries, and nothing else), then compose the axes
# per team-match as the equal-weight mean of their members' z-scores.
sy_zscore_and_compose <- function(team_matches) {
  feats <- unique(unlist(lapply(sy_axes, \(a) names(a$features))))

  z <- team_matches |>
    group_by(league, season_start_year) |>
    mutate(across(all_of(feats),
                  \(v) (v - mean(v, na.rm = TRUE)) / sd(v, na.rm = TRUE))) |>
    ungroup()

  for (ax in names(sy_axes)) {
    members <- sy_axes[[ax]]$features
    mat <- vapply(names(members), function(f) z[[f]] * members[[f]],
                  numeric(nrow(z)))
    z[[ax]] <- rowMeans(matrix(mat, nrow = nrow(z)), na.rm = TRUE)
    z[[ax]][is.nan(z[[ax]])] <- NA_real_
  }
  z |> select(event_ss_id, team_ss_id, team_season_id, coach_id, match_date,
              league, season_start_year, all_of(names(sy_axes)))
}

# Coach-stint style = the mean of the stint's team-match axis scores.
sy_build_coach_stints <- function(composed) {
  composed |>
    filter(!is.na(coach_id)) |>
    group_by(coach_id, team_season_id, league, season_start_year) |>
    summarize(n_games = n(),
              across(all_of(names(sy_axes)), \(v) mean(v, na.rm = TRUE)),
              .groups = "drop") |>
    mutate(across(all_of(names(sy_axes)), \(v) ifelse(is.nan(v), NA_real_, v)))
}

# Season-level pressing height, z-scored within league x season and attached to
# the stints it can be attached to. Flagged as blended wherever the team-season
# had more than one coach — the value is then the club's, not the coach's.
sy_add_pressing_height <- function(stints, seasons = sy_seasons) {
  height <- bind_rows(lapply(names(ss_big5_leagues), function(lg) {
    bind_rows(lapply(seasons, function(yr) sy_season_pressing_height(lg, yr)))
  }))

  maps <- bind_rows(lapply(names(ss_big5_leagues), function(lg) {
    bind_rows(lapply(seasons, function(yr) {
      cf_season_match_coaches(lg, yr) |>
        distinct(team_ss_id, team_season_id, league, season_start_year)
    }))
  }))

  h <- height |>
    inner_join(maps, by = c("team_ss_id", "league", "season_start_year")) |>
    group_by(league, season_start_year) |>
    mutate(pressing_height = (poss_won_att3 - mean(poss_won_att3, na.rm = TRUE)) /
             sd(poss_won_att3, na.rm = TRUE)) |>
    ungroup() |>
    select(team_season_id, pressing_height)

  n_coaches <- stints |> count(team_season_id, name = "n_coaches")

  stints |>
    left_join(h, by = "team_season_id") |>
    left_join(n_coaches, by = "team_season_id") |>
    mutate(height_blended = n_coaches > 1) |>
    select(-n_coaches)
}

# Games-weighted coach profile across all his stints, consistent with the M5
# weighting convention. n_seasons/n_clubs are the coverage facts a reader needs
# to judge a radar. pressing_height is games-weighted over the stints that have
# it, and `height_blended_share` reports how much of that came from team-seasons
# the coach shared with someone else.
sy_coach_profiles <- function(stints, min_games = 19) {
  axes <- names(sy_axes)

  prof <- stints |>
    group_by(coach_id) |>
    summarize(
      n_stints    = n(),
      total_games = sum(n_games),
      n_clubs     = n_distinct(sub("/saison_id/\\d+", "", team_season_id)),
      n_seasons   = n_distinct(season_start_year),
      leagues     = paste(sort(unique(league)), collapse = ", "),
      across(all_of(axes), \(v) weighted.mean(v, n_games, na.rm = TRUE)),
      pressing_height = weighted.mean(pressing_height, n_games, na.rm = TRUE),
      height_blended_share = weighted.mean(as.numeric(height_blended), n_games,
                                           na.rm = TRUE),
      .groups = "drop"
    ) |>
    mutate(across(all_of(c(axes, "pressing_height")),
                  \(v) ifelse(is.nan(v), NA_real_, v))) |>
    left_join(xx_data_cache$coaches |> distinct(coach_id, coach_name),
              by = "coach_id") |>
    relocate(coach_name, .after = coach_id)

  kept <- prof |> filter(total_games >= min_games)

  cat("=== Coach style profiles ===\n")
  cat("Coaches with any big-5 match:", nrow(prof), "\n")
  cat("With >=", min_games, "games (kept):", nrow(kept), "\n")
  cat("Median games:", median(kept$total_games), "\n")
  kept
}

# Sanity: the axes should not all be the same thing wearing different hats.
sy_axis_correlations <- function(stints) {
  axes <- names(sy_axes)
  m <- cor(stints[, axes], use = "pairwise.complete.obs")
  cat("=== Axis correlations across coach stints ===\n")
  print(round(m, 2))
  pairs <- which(abs(m) > 0.8 & upper.tri(m), arr.ind = TRUE)
  if (nrow(pairs) > 0) {
    cat("\nNOTE: |r| > 0.8 axis pairs (near-duplicates):\n")
    for (i in seq_len(nrow(pairs))) {
      cat(sprintf("  %s <-> %s : %.2f\n", axes[pairs[i, 1]], axes[pairs[i, 2]],
                  m[pairs[i, 1], pairs[i, 2]]))
    }
  } else {
    cat("\nNo axis pair exceeds |r| = 0.8 — the axes carry distinct information.\n")
  }
  invisible(m)
}

# Face validity against the design's own stated expectations (sec. 3.3):
# Guardiola high possession + pressing; Simeone low possession + high solidity.
sy_face_check <- function(profiles) {
  who <- c("Pep Guardiola", "Diego Simeone", "Jürgen Klopp", "José Mourinho",
           "Marcelo Bielsa", "Tony Pulis", "Antonio Conte", "Maurizio Sarri",
           "Sean Dyche", "Roberto De Zerbi")
  d <- profiles |>
    filter(coach_name %in% who) |>
    select(coach_name, total_games, possession, pressing, directness,
           defensive_solidity, lineup_stability, pressing_height) |>
    arrange(desc(possession))
  cat("=== Face validity (axis units = SD vs contemporaries) ===\n")
  print(as.data.frame(d), row.names = FALSE, digits = 2)
  invisible(d)
}

# Writes coach_style.rds (per-coach profiles + the stint table + axis metadata),
# per design sec. 6. Consumed by site_export.R once phase 6 lands.
sy_save_results <- function(profiles, stints, results_dir = "data/results") {
  out <- list(
    profiles = profiles,
    stints   = stints,
    axes     = sy_axis_labels,
    meta     = list(
      seasons     = range(sy_seasons),
      leagues     = names(ss_big5_leagues),
      built_at    = Sys.Date(),
      label       = "descriptive-clean: what the team did, z-scored within league x season; team style, not coach style in the abstract (design sec. 5)"
    )
  )
  saveRDS(out, file.path(results_dir, "coach_style.rds"))
  cat("Wrote coach_style.rds (", nrow(profiles), " coaches, ",
      nrow(stints), " stints).\n", sep = "")
  invisible(out)
}

# =============================================================================
# Phase 4 — coach vs squad (design sec. 5)
# =============================================================================
#
# Layer B measures the TEAM's style, which the coach and his players produce
# jointly. Section 5 proposes two partial mitigations; this section builds both,
# plus the complement that makes the first one interpretable.
#
#   1. Does the signature TRAVEL? For coaches with >= 2 clubs, correlate their
#      style at club A with their style at club B.
#   2. Does the CLUB carry it instead? The complement: for clubs with >= 2
#      coaches, correlate the club's style under coach 1 with coach 2. Comparing
#      (1) against (2) is what makes either number mean anything — a high
#      cross-club correlation is only evidence for the coach if the cross-coach
#      correlation within a club is lower.
#   3. Variance decomposition — the principled version of 1-vs-2: fit
#      axis ~ (1|coach) + (1|club) and read the shares, exactly as M5 does for
#      the points residual.
#   4. Style residualized on the squad's archetype mix — "more possession than
#      this squad's personnel would predict" — then re-run 1-3 on the residuals.
#
# NONE of this fully separates coach from squad, and the design says to say so:
# coaches are hired by clubs whose style already suits them, so cross-club
# persistence is inflated by selection; and the archetype mix a coach is given is
# partly a mix he asked for, so residualizing on it removes some of his own
# signature along with the squad's. These are bounds and hints, not an identified
# causal split.
#
# ---------------------------------------------------------------------------
# WHAT THIS FOUND (2026-07-16) — binding on how Layer B may be presented.
#
# **Team style is mostly the CLUB's, not the coach's.** Club variance exceeds
# coach variance on 7 of 9 axes, often by a lot (possession 69% club vs 12%
# coach), and the squad's archetype mix alone explains 69% of possession, 54% of
# shot volume and 51% of directness. A club under two DIFFERENT coaches (r =
# 0.82 on possession) looks far more alike than a coach at two DIFFERENT clubs
# (r = 0.55). So a radar must be labelled as *the style of the teams this coach
# ran* — never "his style" in the abstract. The design's sec. 5 caveat is not
# boilerplate; it is the main result.
#
# Two axes survive as genuinely the coach's:
#   * lineup_stability — coach 19.2% > club 14.6% variance, travels better than
#     it persists (0.33 vs 0.17, the only axis where that is true), only 10% of
#     it is explained by personnel, and it still travels after residualizing
#     (0.25 vs 0.11). Rotation is a decision, not a squad property. The design
#     called this one "a real coach signature nobody visualizes" — correct.
#   * pressing — the best tactical axis: highest coach share (30.9%, above club's
#     23.6%), only 12% personnel-explained, and the only tactical axis still
#     standing after residualization (0.34 vs 0.33).
# ---------------------------------------------------------------------------

# Compact per-axis variance decomposition: coach vs club, games-weighted like the
# rest of the project. Returns one row per axis rather than fit_mixed_model()'s
# full printout, which would be 9 BLUP tables of noise here.
sy_axis_varcomp <- function(stints, axis) {
  d <- stints |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    filter(!is.na(.data[[axis]]))
  names(d)[names(d) == axis] <- "y"

  m_full <- lme4::lmer(y ~ (1 | club_id) + (1 | coach_id), data = d,
                       weights = n_games, REML = FALSE,
                       control = lme4::lmerControl(optimizer = "bobyqa"))
  m_null <- lme4::lmer(y ~ (1 | club_id), data = d,
                       weights = n_games, REML = FALSE,
                       control = lme4::lmerControl(optimizer = "bobyqa"))

  vc <- as.data.frame(lme4::VarCorr(m_full))
  v <- setNames(vc$vcov, vc$grp)
  # with weights = n_games the residual is per-game; put it on the stint scale
  # at the mean stint length so the shares are comparable (as fit_mixed_model does)
  v[["Residual"]] <- v[["Residual"]] / mean(d$n_games)
  tot <- sum(v)

  chi <- 2 * (as.numeric(logLik(m_full)) - as.numeric(logLik(m_null)))

  data.frame(
    axis      = axis,
    coach_pct = round(100 * v[["coach_id"]] / tot, 1),
    club_pct  = round(100 * v[["club_id"]]  / tot, 1),
    resid_pct = round(100 * v[["Residual"]] / tot, 1),
    coach_chisq = round(chi, 1),
    coach_p   = signif(pchisq(chi, 1, lower.tail = FALSE), 3),
    stringsAsFactors = FALSE
  )
}

sy_variance_decomposition <- function(stints, axes = names(sy_axes)) {
  out <- do.call(rbind, lapply(axes, \(a) sy_axis_varcomp(stints, a)))
  cat("=== Variance decomposition per axis (games-weighted) ===\n")
  cat("coach_pct > club_pct means the signature travels with the coach.\n\n")
  print(out, row.names = FALSE)
  invisible(out)
}

# (1) Does the signature travel? Club-level style per coach, then correlate a
# coach's first club against his second. (2) Its complement: club style per
# coach, then correlate a club's first coach against its second.
# min_games guards against club/coach cells that are a handful of matches.
#
# READ THE ASYMMETRY BEFORE QUOTING THESE NUMBERS. The two correlations are not
# a like-for-like ownership contest: consecutive coaches at one club inherit
# nearly the same squad, while a coach's two clubs have entirely different
# squads. So r_club_persists > r_coach_travels is expected under ANY model in
# which the squad matters at all, and on its own it does not prove the coach is
# irrelevant. Treat this pair as an upper bound on club-ness / lower bound on
# coach-ness, and let sy_variance_decomposition() — which estimates both effects
# simultaneously — carry the verdict. (As of 2026-07-16 the two agree on 7 of 9
# axes, which is why the conclusion stands.)
sy_persistence_pair <- function(stints, axes = names(sy_axes), min_games = 19) {
  cells <- stints |>
    mutate(club_id = sub("/saison_id/\\d+", "", team_season_id)) |>
    group_by(coach_id, club_id) |>
    summarize(games = sum(n_games),
              first_season = min(season_start_year),
              across(all_of(axes), \(v) weighted.mean(v, n_games, na.rm = TRUE)),
              .groups = "drop") |>
    filter(games >= min_games)

  # take the first two qualifying cells per grouping key, ordered by season
  first_two <- function(d, key) {
    d |>
      group_by(across(all_of(key))) |>
      arrange(first_season, .by_group = TRUE) |>
      mutate(idx = row_number()) |>
      filter(n() >= 2, idx <= 2) |>
      ungroup()
  }

  corr_over <- function(d, key, label) {
    ft <- first_two(d, key)
    rows <- lapply(axes, function(a) {
      w <- ft |> select(all_of(key), idx, val = all_of(a)) |>
        pivot_wider(names_from = idx, values_from = val, names_prefix = "v") |>
        filter(!is.na(v1), !is.na(v2))
      if (nrow(w) < 10) return(data.frame(axis = a, n = nrow(w), r = NA_real_))
      ct <- cor.test(w$v1, w$v2)
      data.frame(axis = a, n = nrow(w), r = round(unname(ct$estimate), 3),
                 p = signif(ct$p.value, 3))
    })
    out <- do.call(rbind, rows)
    names(out)[names(out) == "r"] <- label
    out
  }

  travels <- corr_over(cells, "coach_id", "r_coach_travels")
  clubby  <- corr_over(cells, "club_id",  "r_club_persists")

  out <- travels |>
    select(axis, n_coaches = n, r_coach_travels) |>
    left_join(clubby |> select(axis, n_clubs = n, r_club_persists), by = "axis") |>
    mutate(verdict = case_when(
      is.na(r_coach_travels) | is.na(r_club_persists) ~ "insufficient",
      r_coach_travels > r_club_persists + 0.1 ~ "coach",
      r_club_persists > r_coach_travels + 0.1 ~ "club",
      TRUE ~ "tied"
    ))

  cat("=== Does the fingerprint travel with the coach, or stay with the club? ===\n")
  cat("r_coach_travels: same coach, his 1st vs 2nd club (n = coaches with 2+ clubs)\n")
  cat("r_club_persists: same club, its 1st vs 2nd coach (n = clubs with 2+ coaches)\n\n")
  print(as.data.frame(out), row.names = FALSE)
  invisible(out)
}

# (4) Style residualized on the squad's archetype mix: how much of each axis is
# predictable from the player types the coach was given, and what is left when
# that is removed? The R^2 is itself the sec. 5 statistic — it puts a number on
# how much of "style" is personnel.
#
# Caveat that must travel with this: the mix is partly one the coach requested or
# shaped, so the residual strips out some of his own signature too. It is a
# lower bound on the coach's contribution, not a clean one.
sy_residualize_on_archetypes <- function(stints, composition = NULL,
                                         axes = names(sy_axes)) {
  if (is.null(composition)) composition <- cf_stint_composition()

  # composition carries its own season_start_year; drop it so the join does not
  # produce .x/.y columns and strand the season key the travel test needs
  d <- stints |>
    inner_join(composition |> select(-any_of("season_start_year")),
               by = c("coach_id", "team_season_id"))
  shares <- cf_share_cols(d)
  cat("=== Style residualized on squad archetype mix ===\n")
  cat("Stints matched to a composition:", nrow(d), "of", nrow(stints), "\n")
  cat("Archetype share predictors:", length(shares), "\n\n")

  r2 <- lapply(axes, function(a) {
    f <- as.formula(paste(a, "~", paste(shares, collapse = " + ")))
    m <- lm(f, data = d, weights = n_games)
    d[[paste0(a, "_resid")]] <<- d[[a]] - predict(m, newdata = d)
    data.frame(axis = a, r2_archetype = round(summary(m)$r.squared, 3))
  })
  r2 <- do.call(rbind, r2)

  cat("Share of each style axis explained by the squad's archetype mix:\n")
  print(r2, row.names = FALSE)

  list(data = d, r2 = r2)
}

# Runs the sec. 5 checks and, crucially, re-runs the travel test on the
# archetype-residualized axes: does the signature still travel once the personnel
# he was handed is accounted for?
run_coach_vs_squad <- function(stints = NULL, composition = NULL,
                               min_games = 19, results_dir = "data/results",
                               save = TRUE) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")
  if (is.null(stints)) stints <- readRDS(file.path(results_dir, "coach_style.rds"))$stints
  axes <- names(sy_axes)

  sep("STEP 1: VARIANCE DECOMPOSITION (coach vs club)")
  vc <- sy_variance_decomposition(stints, axes)

  sep("STEP 2: DOES IT TRAVEL? (cross-club vs cross-coach)")
  pers <- sy_persistence_pair(stints, axes, min_games = min_games)

  sep("STEP 3: RESIDUALIZE ON SQUAD ARCHETYPE MIX")
  res <- sy_residualize_on_archetypes(stints, composition, axes)

  sep("STEP 4: DOES IT STILL TRAVEL AFTER REMOVING THE SQUAD'S PERSONNEL?")
  resid_axes <- paste0(axes, "_resid")
  pers_resid <- sy_persistence_pair(res$data, resid_axes, min_games = min_games) |>
    mutate(axis = sub("_resid$", "", axis)) |>
    select(axis, r_coach_travels_resid = r_coach_travels,
           r_club_persists_resid = r_club_persists)

  sep("SUMMARY")
  summary_tbl <- vc |>
    select(axis, coach_pct, club_pct) |>
    left_join(pers |> select(axis, n_coaches, r_coach_travels, r_club_persists,
                             verdict), by = "axis") |>
    left_join(pers_resid, by = "axis") |>
    left_join(res$r2, by = "axis")
  print(as.data.frame(summary_tbl), row.names = FALSE)

  out <- list(varcomp = vc, persistence = pers, persistence_resid = pers_resid,
              archetype_r2 = res$r2, summary = summary_tbl,
              residualized = res$data,
              label = paste("descriptive; neither check identifies a causal",
                            "coach effect — coaches are hired by clubs that suit",
                            "them (inflating travel), and the archetype mix is",
                            "partly one the coach shaped (deflating the residual)"))
  if (save) {
    saveRDS(out, file.path(results_dir, "coach_style_vs_squad.rds"))
    cat("\nWrote coach_style_vs_squad.rds\n")
  }
  invisible(out)
}

# =============================================================================
# Layer C — style -> quality (design sec. 4). EXPLORATORY.
# =============================================================================
#
# "What tends to make coaches good?": the M5 quality BLUP regressed on the
# Layer B axes + formation rigidity, across coaches.
#
# **Phase 4 is binding on how this is read, and it is not a footnote.** Seven of
# the nine axes are mostly the CLUB's property, not the coach's (possession is
# 69% club variance vs 12% coach; the squad's archetype mix alone explains 69%
# of it). Regressing the BLUP on those axes is therefore close to regressing it
# on club identity, and the BLUP conditions on squad *value* but not squad
# *style* — exactly the gap a style association would slip through. So the
# families below are pre-specified, not data-chosen:
#
#   PRIMARY   lineup_stability, pressing, rigidity — the coach-owned axes.
#             Phase 4: coach variance > club variance for both axes, ~10-12%
#             personnel-explained, both survive residualization. Rigidity is a
#             pure formation-choice trait, never a team-performance measure.
#   SECONDARY the other 7 axes — reported for completeness and heavily
#             confounded. A "finding" here is as likely to be about the clubs
#             that play that way as about the coaches who choose it.
#
# FDR runs WITHIN each family (BH), so the primary result is not diluted by
# seven predictors we already expect to be confounded, and the secondary set
# cannot borrow the primary's credibility.
#
# Three specifications, all reported (never just the flattering one):
#   raw       axes as-is
#   resid     axes residualized on the squad's archetype mix (phase 4's
#             "more possession than this squad's personnel predicts")
#   +club     raw axes + the coach's mean club value percentile, to absorb the
#             sorting of better coaches into differently-built clubs
#
# Nothing here is causal. Every result is "coaches who do X *tend to* grade
# higher", never "doing X makes a coach better".
sy_sq_primary   <- c("lineup_stability", "pressing", "rigidity")
sy_sq_secondary <- setdiff(names(sy_axes), sy_sq_primary)

# Formation rigidity per coach, in [0, 1] (cr_rigidity). delta = 0.3 is the
# recency decay the recommender selected out-of-sample — reused, not re-tuned.
sy_coach_rigidity <- function(delta = 0.3, coach_formations = NULL) {
  if (is.null(coach_formations)) coach_formations <- cr_build_coach_formations()
  cr_rigidity(coach_formations, delta) |>
    select(coach_id, rigidity, n_matches_form = n_matches)
}

# The coach's mean club level: squad value percentile within league-season,
# games-weighted across his style stints. The control for "better coaches are
# hired by bigger clubs".
sy_club_level <- function(stints, results_dir = "data/results") {
  res <- readRDS(file.path(results_dir, "residuals_14league.rds"))
  lvl <- res |>
    group_by(league, season) |>
    mutate(club_pct = 100 * (rank(total_team_value) - 1) / (n() - 1)) |>
    ungroup() |>
    select(team_season_id, club_pct)

  stints |>
    left_join(lvl, by = "team_season_id") |>
    filter(!is.na(club_pct)) |>
    group_by(coach_id) |>
    summarize(club_pct = weighted.mean(club_pct, n_games), .groups = "drop")
}

# One coach-level table: BLUP + raw axes + residualized axes + rigidity + club
# level. `cut` picks the M5 cut for the response; style is big-5 only, so top5
# is the natural pairing (14league would score a coach on a BLUP earned partly
# in leagues the fingerprint cannot see).
sy_style_quality_data <- function(cut = "top5", style = NULL, rigidity = NULL,
                                  composition = NULL, delta = 0.3,
                                  results_dir = "data/results") {
  if (is.null(style)) style <- readRDS(file.path(results_dir, "coach_style.rds"))
  if (is.null(rigidity)) rigidity <- sy_coach_rigidity(delta)
  axes <- names(sy_axes)

  # residualized axes: stint level (that is where the composition lives), then
  # games-weighted up to the coach, mirroring sy_coach_profiles()
  rz <- sy_residualize_on_archetypes(style$stints, composition, axes)
  resid_prof <- rz$data |>
    group_by(coach_id) |>
    summarize(across(all_of(paste0(axes, "_resid")),
                     \(v) weighted.mean(v, n_games, na.rm = TRUE)),
              .groups = "drop")

  blups <- readRDS(file.path(results_dir, paste0("coach_blups_", cut, ".rds")))
  grades <- readRDS(file.path(results_dir, paste0("coach_grades_", cut, ".rds")))

  d <- blups |>
    select(coach_id, coach_name, blup, total_games, n_stints, n_clubs) |>
    inner_join(style$profiles |> select(coach_id, all_of(axes),
                                        style_games = total_games),
               by = "coach_id") |>
    left_join(resid_prof, by = "coach_id") |>
    left_join(rigidity, by = "coach_id") |>
    left_join(sy_club_level(style$stints, results_dir), by = "coach_id") |>
    mutate(graded = coach_id %in% grades$coach_id)

  cat("\n=== Layer C sample (cut:", cut, ") ===\n")
  cat("Coaches with both a BLUP and a fingerprint:", nrow(d), "\n")
  cat("  of which graded (>= 109 games or FDR-significant):", sum(d$graded), "\n")
  cat("  missing rigidity:", sum(is.na(d$rigidity)),
      " missing club level:", sum(is.na(d$club_pct)), "\n")
  cat("Career games (BLUP cut): median", median(d$total_games),
      " range", min(d$total_games), "-", max(d$total_games), "\n")
  d
}

# Weighted Pearson correlation.
sy_weighted_cor <- function(x, y, w) {
  ok <- !is.na(x) & !is.na(y) & !is.na(w)
  x <- x[ok]; y <- y[ok]; w <- w[ok]
  mx <- weighted.mean(x, w); my <- weighted.mean(y, w)
  cov <- sum(w * (x - mx) * (y - my))
  sx <- sqrt(sum(w * (x - mx)^2)); sy <- sqrt(sum(w * (y - my)^2))
  cov / (sx * sy)
}

# Marginal association of each predictor with the BLUP, one at a time.
# Weighted by career games: a BLUP from 600 games is a far more precise
# measurement of the coach than one from 20, and M5 weights by games throughout.
sy_sq_univariate <- function(d, preds, label, family) {
  out <- lapply(preds, function(p) {
    dd <- d[stats::complete.cases(d[, c("blup", p, "total_games")]), ]
    r <- sy_weighted_cor(dd[[p]], dd$blup, dd$total_games)
    m <- lm(as.formula(paste("blup ~", p)), data = dd, weights = total_games)
    cf <- summary(m)$coefficients
    data.frame(predictor = p, family = family, n = nrow(dd),
               r = round(r, 3),
               beta_sd = round(coef(m)[[2]] * sd(dd[[p]]) / sd(dd$blup), 3),
               p = cf[2, 4])
  })
  do.call(rbind, out)
}

# THE HEADLINE SPECIFICATION: one axis at a time, with the club-level control.
#
# Why not the all-axes multivariable? Because the axes are near-proxies for club
# size (verified 2026-07-16: possession correlates r = +0.86 with the coach's
# mean club value percentile, shot volume +0.81, defensive solidity +0.74), and
# they are collinear with each other (possession/shot volume r = 0.89). Throwing
# all ten plus the control into one weighted OLS produces textbook suppression,
# not insight: club_pct flips from r = +0.39 bivariate to beta = -0.60 partial,
# which would read as "big clubs underperform" and is an artifact. One axis at a
# time with one control is the spec that can actually be interpreted.
sy_sq_club_control <- function(d, preds, family_of) {
  out <- lapply(preds, function(p) {
    dd <- d[stats::complete.cases(d[, c("blup", p, "club_pct", "total_games")]), ]
    sdr <- sd(dd[[p]]) / sd(dd$blup)
    m1 <- lm(as.formula(paste("blup ~", p)), data = dd, weights = total_games)
    m2 <- lm(as.formula(paste("blup ~", p, "+ club_pct")), data = dd,
             weights = total_games)
    data.frame(predictor = p, family = family_of(p), n = nrow(dd),
               r_club = round(sy_weighted_cor(dd[[p]], dd$club_pct,
                                              dd$total_games), 3),
               beta_alone = round(coef(m1)[[2]] * sdr, 3),
               beta_club = round(coef(m2)[[2]] * sdr, 3),
               p = summary(m2)$coefficients[2, 4])
  })
  do.call(rbind, out)
}

# How much of each axis is just performance restated? The BLUP measures points
# above value expectation; an axis like defensive_solidity is built from shots
# CONCEDED, which is a step on the causal path to conceding goals and dropping
# points. So "solid teams grade higher" is partly a restatement, not a finding.
# This reports the stint-level overlap with the very residual Layer C explains.
sy_sq_outcome_overlap <- function(style_stints, cut = "top5",
                                  results_dir = "data/results",
                                  axes = names(sy_axes)) {
  cr <- readRDS(file.path(results_dir, paste0("coach_residuals_", cut, ".rds")))
  j <- style_stints |>
    inner_join(cr |> select(coach_id, team_season_id, partial_residual_ppg),
               by = c("coach_id", "team_season_id"))
  out <- data.frame(
    axis = axes,
    r_stint_residual = vapply(axes, \(a) round(
      sy_weighted_cor(j[[a]], j$partial_residual_ppg, j$n_games), 3), numeric(1)),
    row.names = NULL)
  cat("Stints joined to their own M5 points residual:", nrow(j), "\n")
  cat("An axis with a large |r| here is partly measuring the outcome the BLUP\n")
  cat("measures — read its Layer C association as restatement, not discovery.\n\n")
  out |> arrange(desc(abs(r_stint_residual)))
}

# THE CHECK THAT DECIDES LAYER C. A coach-level regression sees only the
# BETWEEN-coach contrast ("coaches who rotate more grade higher"), which is
# exactly the contrast confounded by club sorting. Splitting each axis into a
# coach mean + a within-coach deviation asks the same question two ways:
#
#   between  do coaches who habitually do X grade higher?  (confounded)
#   within   when the SAME coach does more X than usual, does he do better?
#
# If the two disagree in sign, the coach-level association is a compositional
# artifact (Simpson's paradox) and must not be reported as a style effect.
# The club control is levelled the same way — controlling a between-coach term
# with a per-stint covariate mixes levels and mis-estimates it.
sy_sq_within_between <- function(style_stints, cut = "top5",
                                 results_dir = "data/results",
                                 axes = names(sy_axes)) {
  cr <- readRDS(file.path(results_dir, paste0("coach_residuals_", cut, ".rds")))
  res <- readRDS(file.path(results_dir, "residuals_14league.rds")) |>
    group_by(league, season) |>
    mutate(club_pct = 100 * (rank(total_team_value) - 1) / (n() - 1)) |>
    ungroup() |>
    select(team_season_id, club_pct)

  j <- style_stints |>
    inner_join(cr |> select(coach_id, team_season_id, partial_residual_ppg),
               by = c("coach_id", "team_season_id")) |>
    left_join(res, by = "team_season_id") |>
    filter(!is.na(club_pct)) |>
    group_by(coach_id) |>
    mutate(club_coach = weighted.mean(club_pct, n_games),
           club_within = club_pct - club_coach) |>
    ungroup()

  cat("Stints:", nrow(j), " coaches:", n_distinct(j$coach_id), "\n\n")
  out <- lapply(axes, function(a) {
    k <- j |> group_by(coach_id) |>
      mutate(ax_coach = weighted.mean(.data[[a]], n_games),
             ax_within = .data[[a]] - ax_coach) |> ungroup()
    m <- lm(partial_residual_ppg ~ ax_coach + ax_within + club_coach +
              club_within, data = k, weights = n_games)
    cf <- summary(m)$coefficients
    data.frame(axis = a,
               beta_between = round(cf["ax_coach", 1], 4),
               p_between    = round(cf["ax_coach", 4], 4),
               beta_within  = round(cf["ax_within", 1], 4),
               p_within     = round(cf["ax_within", 4], 4),
               sign_flip = sign(cf["ax_coach", 1]) != sign(cf["ax_within", 1]))
  })
  do.call(rbind, out) |> arrange(p_between)
}

# All predictors at once, weighted OLS, standardized coefficients.
# KEPT FOR THE RECORD, NOT FOR READING: see sy_sq_club_control() above — the
# collinearity makes these coefficients suppression artifacts.
sy_sq_multivariable <- function(d, preds, label, controls = character(0)) {
  rhs <- paste(c(preds, controls), collapse = " + ")
  dd <- d[stats::complete.cases(d[, c("blup", preds, controls, "total_games")]), ]
  m <- lm(as.formula(paste("blup ~", rhs)), data = dd, weights = total_games)
  cf <- summary(m)$coefficients
  keep <- setdiff(rownames(cf), "(Intercept)")
  out <- data.frame(
    predictor = keep,
    beta_sd = round(cf[keep, 1] * vapply(keep, \(k) sd(dd[[k]]), numeric(1)) /
                      sd(dd$blup), 3),
    p = cf[keep, 4],
    row.names = NULL)
  cat("\n--- multivariable:", label, "--- n =", nrow(dd),
      " adj R2 =", round(summary(m)$adj.r.squared, 3), "\n")
  attr(out, "model") <- m
  out
}

# Ridge, coded here rather than pulled in: glmnet is not installed and this is
# a stability check, not the headline. Weighted, standardized predictors,
# k-fold CV over a lambda grid. Reports coefficients on the SD scale.
sy_ridge_cv <- function(d, preds, label, lambdas = 10^seq(-3, 3, length.out = 60),
                        k = 10, seed = 42) {
  dd <- d[stats::complete.cases(d[, c("blup", preds, "total_games")]), ]
  X <- scale(as.matrix(dd[, preds]))
  y <- as.numeric(scale(dd$blup))
  w <- dd$total_games / mean(dd$total_games)

  fit <- function(X, y, w, lam) {
    XtW <- t(X) * rep(w, each = ncol(X))
    solve(XtW %*% X + lam * diag(ncol(X)), XtW %*% y)
  }

  set.seed(seed)
  folds <- sample(rep_len(1:k, nrow(X)))
  cv <- vapply(lambdas, function(lam) {
    err <- vapply(1:k, function(f) {
      tr <- folds != f; te <- !tr
      b <- fit(X[tr, , drop = FALSE], y[tr], w[tr], lam)
      sum(w[te] * (y[te] - X[te, , drop = FALSE] %*% b)^2) / sum(w[te])
    }, numeric(1))
    mean(err)
  }, numeric(1))

  best <- lambdas[which.min(cv)]
  b <- fit(X, y, w, best)
  cat("\n--- ridge:", label, "--- n =", nrow(X),
      " lambda =", signif(best, 3),
      " CV MSE =", round(min(cv), 3),
      " (null 1.0; > 1 means the axes do not predict the BLUP)\n")
  data.frame(predictor = preds, beta_ridge = round(as.numeric(b), 3))
}

# FDR within family (BH), mirroring M6's multiplicity discipline.
sy_sq_fdr <- function(tbl) {
  tbl |>
    group_by(family) |>
    mutate(q = p.adjust(p, "BH"),
           sig = q < 0.05) |>
    ungroup() |>
    mutate(p = round(p, 4), q = round(q, 4)) |>
    arrange(family, p)
}

# Runs Layer C end to end.
run_style_quality <- function(cut = "top5", d = NULL, composition = NULL,
                              delta = 0.3, results_dir = "data/results",
                              save = TRUE) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")
  axes <- names(sy_axes)
  preds <- c(axes, "rigidity")

  sep("STEP 1: ASSEMBLE COACH-LEVEL TABLE")
  if (is.null(d)) d <- sy_style_quality_data(cut, composition = composition,
                                             delta = delta,
                                             results_dir = results_dir)

  sep("STEP 2: MARGINAL ASSOCIATIONS (raw axes), FDR within family")
  uni <- rbind(
    sy_sq_univariate(d, sy_sq_primary, "raw", "primary"),
    sy_sq_univariate(d, sy_sq_secondary, "raw", "secondary")) |>
    sy_sq_fdr()
  print(as.data.frame(uni), row.names = FALSE)

  sep("STEP 3: SAME, ON SQUAD-RESIDUALIZED AXES")
  # rigidity is already a coach-choice trait, not a team measure — it has no
  # squad-residualized counterpart, so it enters unchanged
  rz_pred <- c(paste0(setdiff(preds, "rigidity"), "_resid"), "rigidity")
  rz_primary <- c(paste0(setdiff(sy_sq_primary, "rigidity"), "_resid"), "rigidity")
  uni_rz <- rbind(
    sy_sq_univariate(d, rz_primary, "resid", "primary"),
    sy_sq_univariate(d, paste0(sy_sq_secondary, "_resid"), "resid", "secondary")) |>
    sy_sq_fdr()
  print(as.data.frame(uni_rz), row.names = FALSE)

  sep("STEP 4: HEADLINE — ONE AXIS AT A TIME + CLUB-LEVEL CONTROL")
  family_of <- function(p) ifelse(p %in% sy_sq_primary, "primary", "secondary")
  cc <- sy_sq_club_control(d, preds, family_of) |> sy_sq_fdr()
  cat("r(club_pct, blup) bivariate =",
      round(sy_weighted_cor(d$club_pct, d$blup, d$total_games), 3),
      "- POSITIVE: coaches at bigger clubs grade higher. Whether that is better\n")
  cat("coaches being hired by bigger clubs or the value model under-predicting\n")
  cat("them, the BLUP cannot say — which is why every axis needs this control.\n\n")
  print(as.data.frame(cc), row.names = FALSE)

  sep("STEP 4b: HOW MUCH OF EACH AXIS IS THE OUTCOME RESTATED?")
  style_stints <- readRDS(file.path(results_dir, "coach_style.rds"))$stints
  overlap <- sy_sq_outcome_overlap(style_stints, cut, results_dir)
  print(overlap, row.names = FALSE)

  sep("STEP 4c: WITHIN-COACH vs BETWEEN-COACH (the decisive check)")
  wb <- sy_sq_within_between(style_stints, cut, results_dir)
  print(wb, row.names = FALSE)
  cat("\nSign flips (coach-level association contradicts the within-coach one):",
      paste(wb$axis[wb$sign_flip], collapse = ", "), "\n")

  sep("STEP 5: MULTIVARIABLE (all axes together) — RECORD ONLY, NOT INTERPRETABLE")
  mv_raw <- sy_sq_multivariable(d, preds, "raw axes") |>
    mutate(family = ifelse(predictor %in% sy_sq_primary, "primary", "secondary")) |>
    sy_sq_fdr()
  print(as.data.frame(mv_raw), row.names = FALSE)

  mv_club <- sy_sq_multivariable(d, preds, "raw axes + club level",
                                 controls = "club_pct") |>
    mutate(family = ifelse(predictor %in% sy_sq_primary, "primary",
                           ifelse(predictor == "club_pct", "control", "secondary"))) |>
    sy_sq_fdr()
  print(as.data.frame(mv_club), row.names = FALSE)

  mv_rz <- sy_sq_multivariable(d, rz_pred, "squad-residualized axes") |>
    mutate(family = ifelse(predictor %in% rz_primary, "primary", "secondary")) |>
    sy_sq_fdr()
  print(as.data.frame(mv_rz), row.names = FALSE)

  sep("STEP 6: RIDGE (stability under collinearity)")
  ridge_raw <- sy_ridge_cv(d, preds, "raw axes")
  print(ridge_raw, row.names = FALSE)

  sep("STEP 7: SENSITIVITY — GRADED COACHES ONLY")
  # the site's certification bar: >= 109 games or FDR-significant. If a finding
  # lives only in the thin-record coaches whose BLUPs are shrunk to ~0, it is
  # not a finding.
  dg <- d |> filter(graded)
  uni_g <- rbind(
    sy_sq_univariate(dg, sy_sq_primary, "graded", "primary"),
    sy_sq_univariate(dg, sy_sq_secondary, "graded", "secondary")) |>
    sy_sq_fdr()
  print(as.data.frame(uni_g), row.names = FALSE)

  sep("SUMMARY: EVERY PREDICTOR ACROSS SPECIFICATIONS")
  # A finding has to hold in all four columns to be worth reporting: raw,
  # squad-residualized, club-controlled, and graded-coaches-only. Anything that
  # appears in one column and not the others is a specification artifact.
  spec <- function(tbl, nm, col = "beta_sd") tbl |>
    transmute(predictor = sub("_resid$", "", predictor), !!nm := .data[[col]],
              !!paste0(nm, "_q") := q)
  summary_tbl <- spec(uni, "raw") |>
    full_join(spec(uni_rz, "resid"), by = "predictor") |>
    full_join(spec(cc, "club", "beta_club"), by = "predictor") |>
    full_join(spec(uni_g, "graded"), by = "predictor") |>
    left_join(overlap |> rename(predictor = axis), by = "predictor") |>
    left_join(cc |> select(predictor, r_club), by = "predictor") |>
    left_join(wb |> select(predictor = axis, beta_within, p_within, sign_flip),
              by = "predictor") |>
    mutate(
      family = family_of(predictor),
      # rigidity is a career constant, so it has no within-coach variation and
      # cannot be checked this way — which makes it MORE exposed to confounding,
      # not less. Absence of a failed check is not a passed check, so the two
      # are tracked separately and `robust` requires the check to have RUN.
      level_checked = !is.na(sign_flip),
      level_consistent = !(sign_flip %in% TRUE),
      # an axis correlated |r| > 0.6 with club level cannot be separated FROM
      # club level by controlling for it — the partial is a collinearity
      # artifact, not an estimate. (Tell: possession's beta RISES under the
      # control, 0.517 -> 0.568, which no real confound removal would do.)
      club_separable = is.na(r_club) | abs(r_club) <= 0.6,
      # an axis built from shots for/against partly restates the very points
      # residual the BLUP measures — association there is not discovery
      restates_outcome = !is.na(r_stint_residual) & abs(r_stint_residual) >= 0.2,
      consistent = raw_q < 0.05 & resid_q < 0.05 & club_q < 0.05 &
                   graded_q < 0.05 &
                   sign(raw) == sign(club) & sign(raw) == sign(resid),
      robust = consistent & club_separable & !restates_outcome &
               level_consistent & level_checked,
      # why each predictor fails, in the order the checks are applied
      verdict = case_when(
        !consistent                    ~ "not consistent across specs",
        !club_separable                ~ "inseparable from club level",
        restates_outcome               ~ "restates the outcome",
        !level_consistent              ~ "contradicted within-coach",
        !level_checked                 ~ "between-coach only; untestable",
        TRUE                           ~ "survives (exploratory)")) |>
    arrange(family, desc(abs(club)))
  print(as.data.frame(summary_tbl |> select(predictor, family, raw, club, club_q,
                                            beta_within, p_within, verdict)),
        row.names = FALSE)
  cat("\n")
  for (v in unique(summary_tbl$verdict)) {
    cat(sprintf("  %-32s %s\n", paste0(v, ":"),
                paste(summary_tbl$predictor[summary_tbl$verdict == v],
                      collapse = ", ")))
  }
  survivors <- summary_tbl$predictor[summary_tbl$robust %in% TRUE]
  cat("\nSURVIVING EVERY CHECK:",
      if (length(survivors)) paste(survivors, collapse = ", ") else
        "NONE — Layer C finds no defensible style->quality association.", "\n")

  out <- list(
    data = d, univariate = uni, univariate_resid = uni_rz,
    club_control = cc, outcome_overlap = overlap,
    multivariable = mv_raw, multivariable_club = mv_club,
    multivariable_resid = mv_rz, ridge = ridge_raw,
    univariate_graded = uni_g, summary = summary_tbl,
    families = list(primary = sy_sq_primary, secondary = sy_sq_secondary),
    within_between = wb,
    survivors = survivors,
    meta = list(cut = cut, delta = delta, n = nrow(d),
                n_graded = sum(d$graded),
                generated = format(Sys.Date(), "%Y-%m-%d")),
    label = paste("EXPLORATORY, and the result is NULL. Every raw association",
                  "here is large and significant, and every one of them fails a",
                  "check: the strong axes are inseparable from club level",
                  "(possession r = 0.86 with club value percentile) and/or",
                  "restate the outcome the BLUP measures (defensive solidity is",
                  "built from shots conceded); lineup stability reverses sign",
                  "within-coach; rigidity alone is left, and it is a career",
                  "constant that cannot be tested within-coach at all. Do not",
                  "present a style->quality story from this layer."))
  if (save) {
    saveRDS(out, file.path(results_dir, paste0("coach_style_quality_", cut, ".rds")))
    cat("\nWrote coach_style_quality_", cut, ".rds\n", sep = "")
  }
  invisible(out)
}

# Runs the full Layer B pipeline. team_matches can be passed back in to skip the
# slow rebuild when iterating on the axes.
run_coach_style <- function(seasons      = sy_seasons,
                            min_games    = 19,
                            results_dir  = "data/results",
                            save         = TRUE,
                            team_matches = NULL) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n", strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: BUILD TEAM-MATCH STYLE FEATURES")
  if (is.null(team_matches)) team_matches <- sy_build_team_matches(seasons)

  sep("STEP 2: Z-SCORE WITHIN LEAGUE x SEASON & COMPOSE AXES")
  composed <- sy_zscore_and_compose(team_matches)
  cat("Composed rows:", nrow(composed), "\n")

  sep("STEP 3: COACH-STINT STYLE")
  stints <- sy_build_coach_stints(composed) |> sy_add_pressing_height(seasons)
  cat("Stints:", nrow(stints), " coaches:", n_distinct(stints$coach_id), "\n")

  sep("STEP 4: AXIS CORRELATIONS")
  cors <- sy_axis_correlations(stints)

  sep("STEP 5: COACH PROFILES")
  profiles <- sy_coach_profiles(stints, min_games = min_games)

  sep("STEP 6: FACE VALIDITY")
  face <- sy_face_check(profiles)

  if (save) sy_save_results(profiles, stints, results_dir = results_dir)

  sep("LAYER B COMPLETE")
  cat("Coaches with a fingerprint:", nrow(profiles), "\n")

  invisible(list(team_matches = team_matches, composed = composed,
                 stints = stints, profiles = profiles,
                 correlations = cors, face = face))
}
