# Manager-Change Event Study (es_ prefix)
# ------------------------------------------------------------------------------
# Validates the coach quality grade (M5 BLUP) as a *hiring decision* signal, using
# a within-club first-difference design that sweeps out the club's squad-value level.
#
# For every manager change at a club (mid-season OR between adjacent seasons), we ask:
# does the model's grade GAP between the incoming and outgoing coach -- known BEFORE
# the change -- predict the CHANGE in performance-above-squad-value-expectation?
#
#   dgrade = blup_in - blup_out   (leakage-free as-of BLUP, cutoff = outgoing season)
#   dperf  = resid_in - resid_out (change in partial-residual PPG)
#
# Leakage discipline: the as-of BLUP at cutoff = season_prev is refit on seasons
# strictly BEFORE the outgoing coach's final season, so it contains neither the
# "before" residual (resid_out) nor the "after" residual (resid_in). dgrade is thus
# purely prior information and non-circular with dperf.
#
# Confound: clubs change managers when underperforming, so resid_out is typically
# negative and dperf bounces up by regression to the mean regardless of who arrives.
# The primary test controls for resid_out; the dgrade slope net of it is the signal.
#
# Pure cache/results reader. Inputs: data/results/mb_prep.rds (M3 dataset + per-stint
# residuals) and data/results/mb_asof_blups.rds (leakage-free as-of BLUPs 2012-2024).
# Sources market_benchmark.R only to extend the as-of BLUP set to earlier cutoffs.

suppressMessages({
  library(dplyr)
})

es_results_dir <- "data/results"

# club_id strips the season from a team_season_id (same convention as M5).
es_club_id <- function(team_season_id) sub("/saison_id/\\d+", "", team_season_id)

# Load stints + as-of BLUPs, extending the as-of set to cover earlier cutoffs so
# the event sample spans the full 2005-2024 era rather than only the 2012+ odds window.
es_load <- function(min_asof_cutoff = 2008) {
  prep <- readRDS(file.path(es_results_dir, "mb_prep.rds"))
  asof <- readRDS(file.path(es_results_dir, "mb_asof_blups.rds"))

  need <- setdiff(as.character(min_asof_cutoff:2024), names(asof))
  if (length(need) > 0) {
    message("Computing as-of BLUPs for earlier cutoffs: ", paste(need, collapse = ", "))
    source("market_benchmark.R")
    for (s in need) {
      asof[[s]] <- mb_asof_blups(prep, cutoff = as.integer(s))
    }
    saveRDS(asof, file.path(es_results_dir, "mb_asof_blups.rds"))
  }
  list(stints = prep$stints, asof = asof)
}

# Look up an as-of BLUP for one coach at one cutoff; NA if the coach is absent
# (too little prior history / unseen -> the model's prior is BLUP 0).
es_asof_blup <- function(asof, cutoff, coach_id) {
  tbl <- asof[[as.character(cutoff)]]
  if (is.null(tbl)) return(NA_real_)
  tbl$blup[match(coach_id, tbl$coach_id)]
}

# Build the change-event table from consecutive coach spells at each club.
es_build_events <- function(stints, asof,
                            min_out_games = 5, min_in_games = 8) {
  s <- stints |>
    filter(!is.na(partial_residual_ppg), !is.na(date_from), !is.na(coach_id)) |>
    mutate(club_id = es_club_id(team_season_id)) |>
    arrange(club_id, season, date_from)

  # consecutive (previous, current) pairs within each club timeline
  s <- s |>
    group_by(club_id) |>
    mutate(
      prev_coach_id   = lag(coach_id),
      prev_coach_name = lag(coach_name),
      prev_season     = lag(season),
      prev_team_sid   = lag(team_season_id),
      prev_resid      = lag(partial_residual_ppg),
      prev_games      = lag(n_games),
      prev_actual_ppg = lag(actual_ppg)
    ) |>
    ungroup()

  ev <- s |>
    filter(!is.na(prev_coach_id), coach_id != prev_coach_id) |>
    mutate(
      event_type = case_when(
        team_season_id == prev_team_sid ~ "midseason",
        season == prev_season + 1       ~ "between",
        TRUE                            ~ "gap"
      )
    ) |>
    filter(event_type %in% c("midseason", "between")) |>
    # cutoff = outgoing coach's season: excludes both before- and after-residuals
    mutate(
      cutoff   = prev_season,
      blup_out = mapply(function(cf, id) es_asof_blup(asof, cf, id), cutoff, prev_coach_id),
      blup_in  = mapply(function(cf, id) es_asof_blup(asof, cf, id), cutoff, coach_id),
      dgrade   = blup_in - blup_out,
      dperf    = partial_residual_ppg - prev_resid,
      resid_out = prev_resid,
      resid_in  = partial_residual_ppg,
      wt        = pmin(n_games, prev_games)
    ) |>
    filter(prev_games >= min_out_games, n_games >= min_in_games) |>
    select(club_id, team_season_id, team_name, league, season, cutoff, event_type,
           out_coach_id = prev_coach_id, out_coach_name = prev_coach_name,
           in_coach_id = coach_id, in_coach_name = coach_name,
           out_games = prev_games, in_games = n_games,
           resid_out, resid_in, dperf,
           blup_out, blup_in, dgrade, wt)

  ev
}

# fmt helper
es_p <- function(p) if (p < 1e-4) sprintf("%.2e", p) else sprintf("%.4f", p)

# Analyse: does dgrade predict dperf, net of regression to the mean?
es_analyze <- function(ev, require_both_blup = TRUE) {
  cat("=== Manager-Change Event Study ===\n")
  cat(sprintf("Raw change events (>= game thresholds): %d\n", nrow(ev)))
  cat(sprintf("  midseason: %d   between-season: %d\n",
              sum(ev$event_type == "midseason"), sum(ev$event_type == "between")))
  cat(sprintf("Both coaches have a real as-of BLUP:    %d (%.0f%%)\n",
              sum(!is.na(ev$dgrade)), 100 * mean(!is.na(ev$dgrade))))

  d <- if (require_both_blup) ev |> filter(!is.na(dgrade)) else
    ev |> mutate(across(c(blup_out, blup_in), ~coalesce(.x, 0)),
                 dgrade = blup_in - blup_out)

  cat(sprintf("\nAnalysed events: %d   clubs: %d   seasons: %d-%d\n",
              nrow(d), n_distinct(d$club_id), min(d$season), max(d$season)))
  cat(sprintf("mean dgrade = %+.4f   mean dperf = %+.4f   mean resid_out = %+.4f\n",
              mean(d$dgrade), mean(d$dperf), mean(d$resid_out)))
  cat(sprintf("SD: dgrade %.3f  blup_in %.3f  blup_out %.3f  |  dperf %.3f  resid_in %.3f  resid_out %.3f\n",
              sd(d$dgrade), sd(d$blup_in), sd(d$blup_out), sd(d$dperf), sd(d$resid_in), sd(d$resid_out)))

  # 1. Raw association
  r_raw <- cor(d$dgrade, d$dperf)
  m1 <- lm(dperf ~ dgrade, data = d)
  cat("\n--- 1. Raw: dperf ~ dgrade ---\n")
  cat(sprintf("  slope = %+.3f  (SE %.3f, t %.2f, p %s)   r = %+.3f\n",
              coef(summary(m1))["dgrade", 1], coef(summary(m1))["dgrade", 2],
              coef(summary(m1))["dgrade", 3], es_p(coef(summary(m1))["dgrade", 4]), r_raw))

  # 2. NAIVE difference spec (confounded by selection x RTM -- see note below).
  # Kept as the intuitive-but-wrong comparison: the grade GAP over the sacked coach.
  m2 <- lm(dperf ~ dgrade + resid_out, data = d)
  s2 <- coef(summary(m2))
  cat("\n--- 2. NAIVE (confounded): dperf ~ dgrade + resid_out (RTM control) ---\n")
  cat(sprintf("  dgrade    = %+.3f  (SE %.3f, t %.2f, p %s)\n",
              s2["dgrade", 1], s2["dgrade", 2], s2["dgrade", 3], es_p(s2["dgrade", 4])))
  cat(sprintf("  resid_out = %+.3f  (SE %.3f, t %.2f, p %s)  [<0 = mean reversion]\n",
              s2["resid_out", 1], s2["resid_out", 2], s2["resid_out", 3], es_p(s2["resid_out", 4])))

  # 2b. PRIMARY (validated): does WHO you hire predict how they do, given where the
  # club was? Uses blup_in's full range. Clean because the naive gap spec is confounded
  # by selection x RTM: clubs fire a well-graded coach during an unlucky dip (high
  # blup_out, low resid_out) that then reverts, forcing a spurious negative dgrade<->dperf.
  # The outgoing coach's quality is irrelevant once he is gone; only who arrives matters.
  m2b <- lm(resid_in ~ blup_in + resid_out, data = d)
  s2b <- coef(summary(m2b))
  cat("\n--- 2b. PRIMARY (validated): resid_in ~ blup_in + resid_out (the hiring question) ---\n")
  cat(sprintf("  blup_in   = %+.3f  (SE %.3f, t %.2f, p %s)\n",
              s2b["blup_in", 1], s2b["blup_in", 2], s2b["blup_in", 3], es_p(s2b["blup_in", 4])))
  cat(sprintf("  resid_out = %+.3f  (SE %.3f, t %.2f, p %s)\n",
              s2b["resid_out", 1], s2b["resid_out", 2], s2b["resid_out", 3], es_p(s2b["resid_out", 4])))
  if (requireNamespace("lme4", quietly = TRUE)) {
    mmb <- lme4::lmer(resid_in ~ blup_in + resid_out + (1 | club_id),
                      data = d, weights = wt, REML = FALSE)
    smb <- summary(mmb)$coefficients
    cat(sprintf("  [mixed +(1|club), wt] blup_in = %+.3f  (t %.2f, p %s)\n",
                smb["blup_in", 1], smb["blup_in", "t value"],
                es_p(2 * pnorm(-abs(smb["blup_in", "t value"])))))
  }
  cat(sprintf("  effect of +1 SD of blup_in (%.3f): %+.3f PPG (~%+.1f pts/38-game season)\n",
              sd(d$blup_in), s2b["blup_in", 1] * sd(d$blup_in),
              s2b["blup_in", 1] * sd(d$blup_in) * 38))
  for (et in c("midseason", "between")) {
    de <- d |> filter(event_type == et)
    if (nrow(de) < 20) next
    mb_et <- coef(summary(lm(resid_in ~ blup_in + resid_out, data = de)))
    cat(sprintf("    %-10s n=%4d  blup_in %+.3f (t %.2f, p %s)\n",
                et, nrow(de), mb_et["blup_in", 1], mb_et["blup_in", 3], es_p(mb_et["blup_in", 4])))
  }

  # 3. Mixed model with club random effect + games weighting
  mm_p <- NA
  if (requireNamespace("lme4", quietly = TRUE)) {
    mm <- lme4::lmer(dperf ~ dgrade + resid_out + (1 | club_id),
                     data = d, weights = wt, REML = FALSE)
    sm <- summary(mm)$coefficients
    t_dg <- sm["dgrade", "t value"]
    mm_p <- 2 * pnorm(-abs(t_dg))
    cat("\n--- 3. Mixed: dperf ~ dgrade + resid_out + (1|club), games-weighted ---\n")
    cat(sprintf("  dgrade = %+.3f  (SE %.3f, t %.2f, p %s)\n",
                sm["dgrade", 1], sm["dgrade", 2], t_dg, es_p(mm_p)))
  }

  # 4. By event type
  cat("\n--- 4. By event type (dperf ~ dgrade + resid_out) ---\n")
  for (et in c("midseason", "between")) {
    de <- d |> filter(event_type == et)
    if (nrow(de) < 20) next
    me <- lm(dperf ~ dgrade + resid_out, data = de)
    se <- coef(summary(me))
    cat(sprintf("  %-10s n=%4d  dgrade %+.3f (t %.2f, p %s)\n",
                et, nrow(de), se["dgrade", 1], se["dgrade", 3], es_p(se["dgrade", 4])))
  }

  # 5. Directional accuracy: when the model calls it an upgrade, does it improve?
  cat("\n--- 5. Directional accuracy (net of RTM) ---\n")
  d2 <- d |> mutate(dperf_adj = residuals(lm(dperf ~ resid_out, data = d)))
  up <- d2 |> filter(dgrade > 0); dn <- d2 |> filter(dgrade < 0)
  cat(sprintf("  model-predicted UPGRADES  (dgrade>0, n=%d): improved (RTM-adj) %.1f%%, mean dperf_adj %+.3f\n",
              nrow(up), 100 * mean(up$dperf_adj > 0), mean(up$dperf_adj)))
  cat(sprintf("  model-predicted DOWNGRADES(dgrade<0, n=%d): improved (RTM-adj) %.1f%%, mean dperf_adj %+.3f\n",
              nrow(dn), 100 * mean(dn$dperf_adj > 0), mean(dn$dperf_adj)))
  gap_t <- t.test(up$dperf_adj, dn$dperf_adj)
  cat(sprintf("  upgrade vs downgrade gap in dperf_adj: %+.3f PPG (t %.2f, p %s)\n",
              gap_t$estimate[1] - gap_t$estimate[2], gap_t$statistic, es_p(gap_t$p.value)))

  invisible(list(
    events = d,
    # validated LEVEL spec (the headline hiring test)
    level_slope = s2b["blup_in", 1], level_p = s2b["blup_in", 4],
    level_slope_mixed = if (exists("smb")) smb["blup_in", 1] else NA_real_,
    level_p_mixed = if (exists("smb")) 2 * pnorm(-abs(smb["blup_in", "t value"])) else NA_real_,
    # naive difference spec (confounded, reported for contrast)
    diff_slope = s2["dgrade", 1], diff_p = s2["dgrade", 4], diff_p_mixed = mm_p,
    rtm_slope = s2["resid_out", 1]))
}

# Fan/team-facing leaderboards
es_leaderboards <- function(d, n = 12) {
  fmt <- function(x) x |>
    transmute(season, club = team_name, league,
              out = out_coach_name, `in` = in_coach_name,
              dgrade = round(dgrade, 3), dperf = round(dperf, 3),
              type = event_type)
  cat("\n=== Biggest model-predicted UPGRADES that paid off (dgrade>0, top dperf) ===\n")
  print(as.data.frame(fmt(d |> filter(dgrade > 0) |> arrange(desc(dperf)) |> head(n))), row.names = FALSE)
  cat("\n=== Model said UPGRADE but it BACKFIRED (dgrade>0, worst dperf) ===\n")
  print(as.data.frame(fmt(d |> filter(dgrade > 0) |> arrange(dperf) |> head(n))), row.names = FALSE)
  cat("\n=== Model said DOWNGRADE and it did get worse (dgrade<0, worst dperf) ===\n")
  print(as.data.frame(fmt(d |> filter(dgrade < 0) |> arrange(dperf) |> head(n))), row.names = FALSE)
}

# --- Sacking efficiency -------------------------------------------------------
# Clubs sack on RESULTS; the model splits results into a squad-value expectation
# plus a residual (coach + luck). A mid-season sacking is "harsh" when the outgoing
# coach was actually OVERperforming his squad (resid_out > 0) -- bad results, but a
# worse squad than the club thinks. Questions: how often does that happen, do big
# clubs do it more, and does firing an overperformer backfire (the replacement
# regresses toward expectation)?
es_sacking_efficiency <- function(ev) {
  prep <- readRDS(file.path(es_results_dir, "mb_prep.rds"))
  val <- prep$ds |>
    group_by(league, season) |>
    mutate(value_pct = 100 * rank(total_team_value) / n()) |>
    ungroup() |>
    select(team_season_id, total_team_value, value_pct)

  s <- ev |>
    filter(event_type == "midseason") |>
    left_join(val, by = "team_season_id") |>
    mutate(harsh = resid_out > 0,                       # overperforming when sacked
           backfired = resid_in < resid_out)            # replacement did worse

  n <- nrow(s)
  cat("\n\n=== Sacking Efficiency (mid-season replacements) ===\n")
  cat(sprintf("Mid-season sackings analysed: %d\n", n))
  cat(sprintf("Outgoing coach was OVERperforming his squad when sacked (harsh): %d (%.1f%%)\n",
              sum(s$harsh), 100 * mean(s$harsh)))
  cat(sprintf("Outgoing coach was UNDERperforming (defensible):                %d (%.1f%%)\n",
              sum(!s$harsh), 100 * mean(!s$harsh)))
  cat(sprintf("Mean outgoing residual at sacking: %+.3f PPG (clubs sack during a dip)\n",
              mean(s$resid_out)))

  # by club size tercile
  cat("\n--- Harsh-sacking rate by squad-value tercile ---\n")
  s <- s |> mutate(tier = cut(value_pct, c(0, 33.3, 66.7, 100),
                              labels = c("small", "mid", "big"), include.lowest = TRUE))
  bt <- s |> filter(!is.na(tier)) |> group_by(tier) |>
    summarize(n = n(), pct_harsh = round(100 * mean(harsh), 1),
              mean_resid_out = round(mean(resid_out), 3), .groups = "drop")
  print(as.data.frame(bt), row.names = FALSE)

  # backfire test: what follows harsh vs defensible sackings
  cat("\n--- Does the replacement do better? (change in residual, incoming - outgoing) ---\n")
  cat(sprintf("  after HARSH sacking (overperformer fired): mean dperf %+.3f  (replacement improved %.1f%%)\n",
              mean(s$dperf[s$harsh]), 100 * mean(s$dperf[s$harsh] > 0)))
  cat(sprintf("  after DEFENSIBLE sacking (underperformer): mean dperf %+.3f  (replacement improved %.1f%%)\n",
              mean(s$dperf[!s$harsh]), 100 * mean(s$dperf[!s$harsh] > 0)))
  cat("  (a lower/negative dperf after harsh sackings = firing the overperformer backfires via regression)\n")

  # were harshly-sacked coaches actually good? (career grade among those with a BLUP)
  hg <- s |> filter(harsh, !is.na(blup_out))
  dg <- s |> filter(!harsh, !is.na(blup_out))
  cat(sprintf("\n  mean career grade (as-of BLUP) of harshly-sacked coaches:   %+.4f (n=%d)\n",
              mean(hg$blup_out), nrow(hg)))
  cat(sprintf("  mean career grade of defensibly-sacked coaches:            %+.4f (n=%d)\n",
              mean(dg$blup_out), nrow(dg)))

  cat("\n=== Harshest sackings: overperforming coach fired, replacement then regressed ===\n")
  print(as.data.frame(s |> filter(harsh) |> arrange(dperf) |>
    transmute(season, club = team_name, league, sacked = out_coach_name,
              resid_out = round(resid_out, 3), replacement = in_coach_name,
              resid_in = round(resid_in, 3), swing = round(dperf, 3)) |> head(12)),
    row.names = FALSE)

  invisible(s)
}

run_event_study <- function(min_out_games = 5, min_in_games = 8, save = TRUE) {
  L  <- es_load()
  ev <- es_build_events(L$stints, L$asof, min_out_games, min_in_games)
  # PRIMARY: full sample -- an unproven incoming coach enters at the model's honest
  # prior (BLUP 0), the same convention the recommender and market benchmark use.
  res <- es_analyze(ev, require_both_blup = FALSE)
  cat("\n\n########## ROBUSTNESS: restrict to changes where BOTH coaches are already graded ##########\n")
  es_analyze(ev, require_both_blup = TRUE)
  es_leaderboards(res$events)
  sack <- es_sacking_efficiency(ev)
  if (save) {
    saveRDS(c(list(events = res$events, all_events = ev, sacking = sack),
              res[setdiff(names(res), "events")]),
            file.path(es_results_dir, "event_study.rds"))
    cat(sprintf("\nSaved data/results/event_study.rds (%d analysed events)\n", nrow(res$events)))
  }
  invisible(res)
}
