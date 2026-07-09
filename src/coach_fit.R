# coach_fit.R
#
# Milestone 6, steps 3-4: lagged archetype assignment, squad composition per
# coach stint, and the coach/player-type fit analysis.
#
# Functions use the cf_ prefix. Requires source_data.r to have been sourced
# first (for xx_data_cache and the league constants), same as the rest of the
# analysis chain.
#
# Analysis design (agreed 2026-07-09):
#   - a player's archetype for season t comes from their most recent *prior*
#     qualifying PL season (endogeneity guard); players new to the PL fall
#     back to their current-season archetype, flagged so a strict-lagged
#     sensitivity run can quantify what the fallback changes
#   - the outcome is the M5 coach-stint partial residual; composition shares
#     are computed from per-match minutes played under that specific coach
#   - goalkeepers are excluded from both archetypes and share denominators
#     (their minutes are near-constant across teams and carry no mix signal)

source("coach_attribution.R")
source("player_archetypes.R")
source("sofascore_crosswalk.r")
library(lme4)

# --- lagged archetype lookup -----------------------------------------------------

# One row per (player, season) in the pilot: the archetype the player carries
# into that season.
#   archetype    — lagged if available, else current-season (fallback), else NA
#   is_fallback  — TRUE where the current season had to stand in
# NA archetype = player never met the minutes threshold in any usable season
# ("unclassified"; mostly deep squad players and youth).
cf_player_archetypes <- function() {
  arch <- readRDS(file.path(pa_cache_dir, "archetypes.rds"))

  universe <- bind_rows(lapply(names(ss_pl_season_ids), function(yr) {
    pa_read("players", ss_pl_season_ids[[yr]]) |>
      transmute(player_ss_id, season_start_year = as.integer(yr))
  }))

  lagged <- universe |>
    inner_join(
      arch |> select(player_ss_id, arch_year = season_start_year, archetype),
      by = "player_ss_id", relationship = "many-to-many"
    ) |>
    filter(arch_year < season_start_year) |>
    group_by(player_ss_id, season_start_year) |>
    slice_max(arch_year, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(player_ss_id, season_start_year, lagged_archetype = archetype)

  universe |>
    left_join(lagged, by = c("player_ss_id", "season_start_year")) |>
    left_join(
      arch |> select(player_ss_id, season_start_year,
                     current_archetype = archetype),
      by = c("player_ss_id", "season_start_year")
    ) |>
    mutate(
      archetype   = coalesce(lagged_archetype, current_archetype),
      is_fallback = is.na(lagged_archetype) & !is.na(current_archetype)
    ) |>
    select(player_ss_id, season_start_year, archetype, is_fallback)
}

# --- per-match minutes under each coach --------------------------------------------

# For one pilot season: every (match, team, player) minutes record, with the
# TM team_season_id and the coach in charge on the match date.
cf_season_match_minutes <- function(year) {
  sid <- ss_pl_season_ids[[as.character(year)]]
  league_season_id <- xx_league_season_id(xx_league_id_PREMIER_LEAGUE, year)

  events <- pa_read("events", sid) |>
    filter(status_type == "finished") |>
    mutate(match_date = as.Date(as.POSIXct(start_timestamp,
                                           origin = "1970-01-01",
                                           tz = "Europe/London")))

  # SofaScore team -> TM team_season_id (token-overlap mapper from the
  # crosswalk module; duplicate mappings there are a hard error)
  ss_team_names <- events |>
    transmute(team_ss_id = home_team_ss_id, team_name = home_team_name) |>
    bind_rows(events |>
                transmute(team_ss_id = away_team_ss_id,
                          team_name = away_team_name)) |>
    distinct()
  tm_teams <- xx_data_cache$teams |>
    filter(league_season_id == !!league_season_id)
  team_map <- ss_crosswalk_team_map(ss_team_names$team_name, tm_teams) |>
    bind_cols(ss_team_names |> select(team_ss_id))

  # coach on the day, per (team_season_id, match): reuse the M5 date-bracket
  # rule verbatim so both sides of the join attribute matches identically
  team_matches <- events |>
    select(event_ss_id, match_date, home_team_ss_id, away_team_ss_id) |>
    pivot_longer(c(home_team_ss_id, away_team_ss_id), values_to = "team_ss_id") |>
    left_join(team_map |> select(team_ss_id, team_season_id), by = "team_ss_id") |>
    select(event_ss_id, match_date, team_ss_id, team_season_id)

  attributed <- team_matches |>
    group_by(team_season_id) |>
    group_modify(function(g, key) {
      xx_assign_matches_to_coaches(
        g |> mutate(match_id = event_ss_id),
        xx_data_cache$coaches |> filter(team_season_id == key$team_season_id)
      ) |> select(event_ss_id, match_date, team_ss_id, coach_id)
    }) |>
    ungroup()

  # match_stats$team_ss_id is the player's club at scrape time (SofaScore
  # embeds the current club in lineup responses), NOT the match team — derive
  # the match side from is_home + the event's home/away ids instead
  minutes <- pa_read("match_stats", sid) |>
    filter(stat_name == "minutesPlayed", position != "G") |>
    select(event_ss_id, player_ss_id, is_home, minutes = stat_value) |>
    inner_join(events |> select(event_ss_id, home_team_ss_id, away_team_ss_id),
               by = "event_ss_id") |>
    mutate(team_ss_id = ifelse(is_home, home_team_ss_id, away_team_ss_id)) |>
    select(event_ss_id, player_ss_id, team_ss_id, minutes)

  minutes |>
    inner_join(attributed, by = c("event_ss_id", "team_ss_id")) |>
    mutate(season_start_year = year)
}

# --- stint composition -----------------------------------------------------------

# Minutes-weighted archetype shares per (team_season_id, coach_id) stint.
#   use_fallback = FALSE reroutes fallback minutes into "unclassified" for the
#   strict-lagged sensitivity run.
# Shares are over outfield minutes and sum to 1 (archetypes + unclassified);
# fallback_share reports how much of the classified share rests on the
# current-season fallback.
cf_stint_composition <- function(use_fallback = TRUE) {
  archetypes <- cf_player_archetypes()
  if (!use_fallback) {
    archetypes <- archetypes |>
      mutate(archetype = ifelse(is_fallback, NA_character_, archetype))
  }

  minutes <- bind_rows(lapply(as.integer(names(ss_pl_season_ids)),
                              cf_season_match_minutes)) |>
    left_join(archetypes, by = c("player_ss_id", "season_start_year")) |>
    mutate(
      archetype   = coalesce(archetype, "unclassified"),
      is_fallback = coalesce(is_fallback, FALSE)
    )

  stint_games <- minutes |>
    filter(!is.na(coach_id)) |>
    group_by(team_season_id, coach_id, season_start_year) |>
    summarize(ss_games = n_distinct(event_ss_id),
              total_minutes = sum(minutes),
              fallback_share = sum(minutes[is_fallback]) / sum(minutes),
              .groups = "drop")

  shares <- minutes |>
    filter(!is.na(coach_id)) |>
    group_by(team_season_id, coach_id, archetype) |>
    summarize(m = sum(minutes), .groups = "drop") |>
    group_by(team_season_id, coach_id) |>
    mutate(share = m / sum(m)) |>
    ungroup() |>
    select(-m) |>
    pivot_wider(names_from = archetype, values_from = share,
                names_prefix = "share_", values_fill = 0)

  stint_games |> left_join(shares, by = c("team_season_id", "coach_id"))
}

cf_share_cols <- function(tbl) {
  setdiff(grep("^share_", names(tbl), value = TRUE), "share_unclassified")
}

# --- analysis table --------------------------------------------------------------

# Joins the M4/M5 residual pipeline (pooled 14-league model, PL stints kept)
# to the stint composition. Passing a precomputed coach_residuals table skips
# the slow model rebuild when iterating.
cf_build_analysis_table <- function(composition, coach_residuals = NULL) {
  if (is.null(coach_residuals)) {
    dataset       <- build_model_dataset(2005:2024)
    residuals_tbl <- compute_residuals(dataset)
    coach_residuals <- build_coach_residuals(residuals_tbl)
  }

  pl_stints <- coach_residuals |>
    filter(league == "premier-league", season %in% 2015:2024,
           !is.na(partial_residual_ppg)) |>
    # build_coach_residuals() emits one row per (team-season, coach), but its
    # date_from join duplicates that row when a coach had two tenure brackets
    # in the same season (sacked and re-appointed) — keep the earliest
    group_by(team_season_id, coach_id) |>
    slice_min(date_from, n = 1, with_ties = FALSE) |>
    ungroup()

  tbl <- pl_stints |>
    inner_join(composition, by = c("team_season_id", "coach_id")) |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))

  cat(sprintf(
    "PL stints 2015-2024: %d | joined to composition: %d | game-count agreement r = %.3f\n",
    nrow(pl_stints), nrow(tbl), cor(tbl$n_games, tbl$ss_games)
  ))
  tbl
}

# --- models ----------------------------------------------------------------------

# Global test: does squad archetype mix explain stint residuals at all, after
# coach and club random effects? share_M1 (deep playmaker, the modal
# archetype) is the reference category — each coefficient reads as the effect
# of moving minutes from deep playmakers to that type. LRT vs the no-shares
# null (both fitted with ML).
cf_global_model <- function(tbl, reference = "share_M1") {
  cols <- setdiff(cf_share_cols(tbl), reference)
  rhs  <- paste(c(cols, "fallback_share",
                  "(1 | coach_id)", "(1 | club_id)"), collapse = " + ")

  # bobyqa avoids a marginal convergence warning the default optimizer throws
  # on the strict-lagged variant
  ctrl <- lmerControl(optimizer = "bobyqa")
  full <- lmer(as.formula(paste("partial_residual_ppg ~", rhs)),
               data = tbl, weights = n_games, REML = FALSE, control = ctrl)
  null <- lmer(partial_residual_ppg ~ (1 | coach_id) + (1 | club_id),
               data = tbl, weights = n_games, REML = FALSE, control = ctrl)
  lrt <- anova(null, full)

  cat("=== Global: composition shares vs null ===\n")
  cat(sprintf("LRT: Chi-sq = %.3f  df = %d  p = %.4f\n\n",
              lrt$Chisq[2], lrt$Df[2], lrt$`Pr(>Chisq)`[2]))
  coefs <- summary(full)$coefficients
  print(round(coefs[order(-abs(coefs[, "t value"])), ], 3))

  invisible(list(full = full, null = null, lrt = lrt))
}

# Per-coach descriptive tests: for coaches with >= min_stints PL stints, the
# correlation between their stint residuals and each archetype share. These
# are within-coach correlations (each coach is their own baseline), BH
# FDR-corrected across all (coach, archetype) pairs. With 4-10 stints per
# coach these are exploratory by construction — reported as descriptive
# findings, not confirmatory tests.
cf_per_coach_tests <- function(tbl, min_stints = 4) {
  cols <- cf_share_cols(tbl)

  eligible <- tbl |>
    group_by(coach_id, coach_name) |>
    filter(n() >= min_stints) |>
    ungroup()
  cat(sprintf("Coaches with >= %d stints: %d\n", min_stints,
              n_distinct(eligible$coach_id)))

  results <- eligible |>
    group_by(coach_id, coach_name) |>
    group_modify(function(g, key) {
      bind_rows(lapply(cols, function(col) {
        if (sd(g[[col]]) == 0) return(NULL)
        ct <- cor.test(g$partial_residual_ppg, g[[col]])
        data.frame(archetype = sub("^share_", "", col),
                   n_stints = nrow(g), r = unname(ct$estimate),
                   p = ct$p.value)
      }))
    }) |>
    ungroup() |>
    mutate(
      archetype_label = unname(pa_archetype_labels[archetype]),
      p_adj = p.adjust(p, method = "BH")
    ) |>
    arrange(p)

  cat(sprintf("Tests run: %d | significant after BH FDR (q < 0.10): %d\n\n",
              nrow(results), sum(results$p_adj < 0.10)))
  print(results |> head(15) |>
          select(coach_name, archetype, archetype_label, n_stints, r, p, p_adj),
        n = 15)
  invisible(results)
}

# --- orchestrator ----------------------------------------------------------------

# Full Milestone 6 analysis: composition, join, global model, per-coach tests,
# and the strict-lagged sensitivity re-run.
cf_run_analysis <- function(min_stints = 4) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n",
                             strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: STINT COMPOSITION (with current-season fallback)")
  composition <- cf_stint_composition(use_fallback = TRUE)
  cat("Stints with composition:", nrow(composition), "\n")
  cat(sprintf("Mean fallback share: %.1f%% | mean unclassified share: %.1f%%\n",
              100 * mean(composition$fallback_share),
              100 * mean(composition$share_unclassified)))

  sep("STEP 2: JOIN TO M5 PARTIAL RESIDUALS")
  tbl <- cf_build_analysis_table(composition)

  sep("STEP 3: GLOBAL MODEL")
  global <- cf_global_model(tbl)

  sep("STEP 4: PER-COACH TESTS")
  per_coach <- cf_per_coach_tests(tbl, min_stints = min_stints)

  sep("STEP 5: SENSITIVITY — STRICT LAGGED (no fallback)")
  composition_strict <- cf_stint_composition(use_fallback = FALSE)
  cat(sprintf("Mean unclassified share (strict): %.1f%%\n",
              100 * mean(composition_strict$share_unclassified)))
  tbl_strict <- cf_build_analysis_table(
    composition_strict,
    coach_residuals = tbl |> select(-starts_with("share_"), -fallback_share,
                                    -ss_games, -total_minutes, -club_id,
                                    -season_start_year)
  )
  global_strict <- cf_global_model(tbl_strict)
  per_coach_strict <- cf_per_coach_tests(tbl_strict, min_stints = min_stints)

  invisible(list(
    composition = composition, tbl = tbl,
    global = global, per_coach = per_coach,
    tbl_strict = tbl_strict, global_strict = global_strict,
    per_coach_strict = per_coach_strict
  ))
}
