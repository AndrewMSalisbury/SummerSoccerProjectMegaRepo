# coach_grade_history.R — "grade over time" for each coach
# Design: Docs/Coach_Grade_History_Design.md
#
# For every past season, recompute the grade this site WOULD HAVE PUBLISHED at
# that point, using only completed seasons before it. A vintage is a full replay
# of the published pipeline — M3 lm -> stint partial residuals -> M5 mixed model
# -> the >=109-game/FDR certification bar -> grade_coaches() — so the last
# vintage IS the live fit and must reproduce coach_grades_<cut>.rds exactly
# (gh_verify_endpoint(), the acceptance test).
#
#   working dir src/
#   source("source_data.r"); source("coach_attribution.R"); source("coach_grade_history.R")
#   gh_run_all()
#
# Prefix: gh_. Pure results-reader — no scraping, no chromote.
#
# VINTAGE SEMANTICS. A vintage is indexed by an integer cutoff C meaning "fit on
# team-seasons with season < C". The last completed season in the fit is C - 1,
# and that is what the point is LABELLED with: cutoff 2025 renders as 2024/25.
# Never label a point with the raw cutoff — it is off by one against every other
# season label on the site. The `season` column below is already C - 1.

source("coach_attribution.R")   # chains residual_analysis -> model_comparison -> tabler
source("refit_pipeline.R")      # rp_cuts: the two published cuts, declared once

suppressWarnings(suppressMessages({ library(dplyr) }))

gh_results_dir <- "data/results"
gh_cache_dir   <- "data/results/grade_history"

# Earliest useful cutoff. 2008 fits on 2005-2007; a coach needs 3 stints, so
# nothing earlier can populate the mixed model at all.
gh_first_cutoff <- 2008

# Thin-vintage guards. Vintages failing these are still fit and cached; they are
# just not published.
#
# THE POOL-SIZE GUARD IS NOT THE LOAD-BEARING ONE. The real failure mode, found
# on the first run (2026-07-26), is a DEGENERATE VARIANCE COMPONENT: on a thin
# sample lme4 puts the coach random effect on the zero boundary, every BLUP comes
# back exactly 0, and grade_coaches()' z-score divides 0 by 0 — so every coach in
# that vintage gets NaN, which to_letter() silently renders as "F". top5 2008/09
# did this with 44 graded coaches, i.e. it sailed past a pool >= 40 test. Guard
# on the vintage's own evidence that a coach effect exists instead: the M5 LRT
# that run_milestone5() already reports. If the model cannot detect a coach
# effect in that year's data, it has no business printing coach grades for it.
gh_min_pool  <- 40      # secondary: the curve's SD is estimated on this many coaches
gh_max_lrt_p <- 0.05    # primary: the coach variance component must be identified

# Minimum published vintages before a coach's card renders. A two-point line is
# not a history.
gh_min_points <- 3

# "2024/25" for a season start year (matching se_season_label in site_export.R).
gh_season_label <- function(season) sprintf("%d/%02d", season, (season + 1) %% 100)

# --- one vintage --------------------------------------------------------------

# Refits M3 on team-seasons strictly before `cutoff`, recomputes stint partial
# residuals, fits the M5 mixed model, and runs the significance test that feeds
# the certification bar's FDR exemption. Returns the full BLUP table (not just
# coach_id/blup like mb_asof_blups(), which grading cannot use) plus the
# significant ids and the fit's size.
#
# mb_asof_blups() in market_benchmark.R is deliberately left alone: the market
# benchmark and the event study both depend on its current shape and on the
# mb_asof_blups.rds cache keyed to it. gh_verify_asof_cache() checks the two
# agree where they overlap.
gh_asof_vintage <- function(ds, stints, cutoff, min_games = 10, min_stints = 3) {
  dp <- ds |>
    dplyr::filter(season < cutoff, norm_weighted_value > 0, norm_total_value > 0)
  # identical spec to compute_residuals() (residual_analysis.R) — verified, not assumed
  m <- lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
          data = dp)
  pred <- data.frame(team_season_id = dp$team_season_id,
                     predicted_ppg  = as.numeric(predict(m, dp)),
                     stringsAsFactors = FALSE)

  st <- stints |> dplyr::filter(season < cutoff)
  st$predicted_ppg <- pred$predicted_ppg[match(st$team_season_id, pred$team_season_id)]
  st$partial_residual_ppg <- st$actual_ppg - st$predicted_ppg
  st <- st |> dplyr::filter(!is.na(partial_residual_ppg))

  suppressWarnings(suppressMessages(utils::capture.output(
    mm <- fit_mixed_model(st, min_games = min_games, min_stints = min_stints)
  )))
  suppressWarnings(suppressMessages(utils::capture.output(
    ranked <- add_significance(
      compute_coach_stats(st, min_games = min_games, min_stints = 1))
  )))

  vc <- mm$var_components
  list(
    blups          = mm$coach_blups,
    sig_ids        = ranked$coach_id[!is.na(ranked$significant) & ranked$significant],
    n_team_seasons = nrow(dp),
    n_stints       = nrow(st),
    # the vintage's own evidence that a coach effect exists at all — this is what
    # decides whether the vintage may be published (see gh_run_cut)
    lrt_p          = mm$lrt$p,
    var_coach      = vc$vcov[vc$grp == "coach_id"][1]
  )
}

# One (cut, cutoff): fit, apply the shared certification bar + grade curve, cache.
# Cached per vintage so gh_run_all() is resumable and a roll-forward year only
# costs the new vintage.
gh_vintage <- function(ds, stints, cut, cutoff, refresh = FALSE) {
  if (!dir.exists(gh_cache_dir)) dir.create(gh_cache_dir, recursive = TRUE)
  f <- file.path(gh_cache_dir, sprintf("%s_%d.rds", cut, cutoff))
  if (!refresh && file.exists(f)) return(readRDS(f))

  v <- gh_asof_vintage(ds, stints, cutoff)
  # the SAME bar and curve as save_coach_grades() — grade_blup_table() is shared,
  # not reimplemented, so the history moves if either ever changes
  graded <- grade_blup_table(v$blups, v$sig_ids, quiet = TRUE)
  # the curve needs an SD: a pool of 0 or 1 yields NA grades that would render as
  # "F". The gh_min_pool guard drops such vintages anyway, but do not let NA
  # grades sit in the cache waiting for someone to lower the threshold.
  if (nrow(graded) < 2) graded <- graded[0, , drop = FALSE]

  out <- list(
    graded  = graded,
    vintage = data.frame(
      cutoff         = cutoff,
      season         = cutoff - 1L,
      n_team_seasons = v$n_team_seasons,
      n_stints       = v$n_stints,
      n_blups        = nrow(v$blups),
      n_graded       = nrow(graded),
      n_significant  = length(v$sig_ids),
      blup_mean      = mean(v$blups$blup),
      blup_sd        = sd(v$blups$blup),
      lrt_p          = v$lrt_p,
      var_coach      = v$var_coach,
      stringsAsFactors = FALSE
    )
  )
  saveRDS(out, f)
  out
}

# --- the two cuts -------------------------------------------------------------

# mb_prepare()'s cache holds both cutoff-independent inputs: $ds (team-season
# value + points, all 14 leagues) and $stints (model-independent coach-stint
# actuals, already coverage-filtered at min_coverage = 80). Nothing needs
# rebuilding here.
gh_load_prep <- function() {
  f <- file.path(gh_results_dir, "mb_prep.rds")
  if (!file.exists(f)) {
    source("market_benchmark.R")   # brings mb_prepare() (and source_odds.R)
    return(mb_prepare())
  }
  readRDS(f)
}

# The cut's league slugs as they appear in ds$league / stints$league. rp_cuts
# holds Transfermarkt URLs; the dataset carries the 4th path segment as `league`
# (see build_model_dataset() in model_comparison.R).
gh_cut_leagues <- function(cut) {
  ids <- rp_cuts[[cut]]
  if (is.null(ids)) return(NULL)          # NULL -> all leagues, no filter
  vapply(strsplit(ids, "/"), `[`, character(1), 4)
}

# Subsetting the 14-league frame to a cut is exact, not an approximation:
# norm_total_value / norm_weighted_value are normalized WITHIN each league-season
# (model_comparison.R:340-341), so they do not depend on which leagues are in the
# frame. Filtering therefore yields exactly the rows a
# build_model_dataset(leagues = rp_cuts$top5) call would produce, which is why
# the top-5 series needs no dataset rebuild and no scraping.
gh_cut_inputs <- function(prep, cut) {
  lg <- gh_cut_leagues(cut)
  if (is.null(lg)) return(list(ds = prep$ds, stints = prep$stints))
  list(ds     = prep$ds     |> dplyr::filter(league %in% lg),
       stints = prep$stints |> dplyr::filter(league %in% lg))
}

gh_run_cut <- function(prep, cut, cutoffs, refresh = FALSE) {
  inp <- gh_cut_inputs(prep, cut)
  cat(sprintf("\n=== grade history: %s (%d team-seasons, %d stints) ===\n",
              cut, nrow(inp$ds), nrow(inp$stints)))

  vs <- lapply(cutoffs, function(C) {
    t0 <- Sys.time()
    v <- gh_vintage(inp$ds, inp$stints, cut, C, refresh = refresh)
    cat(sprintf("  %s  %4d BLUPs, %4d graded  (pool sd %.4f)  [%.0fs]\n",
                gh_season_label(C - 1L), v$vintage$n_blups, v$vintage$n_graded,
                v$vintage$blup_sd, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
    v
  })

  vintages <- dplyr::bind_rows(lapply(vs, `[[`, "vintage"))
  points <- dplyr::bind_rows(lapply(vs, function(v) {
    v$graded |>
      dplyr::mutate(cutoff = v$vintage$cutoff, season = v$vintage$season) |>
      dplyr::select(coach_id, coach_name, cutoff, season, blup, numeric_grade,
                    letter_grade, rank, n_stints, total_games) |>
      dplyr::mutate(n_graded = nrow(v$graded))
  }))

  # thin-vintage guards, applied at assembly so thresholds can move without refitting
  vintages <- vintages[order(vintages$cutoff), ]
  ok <- vintages$n_graded >= gh_min_pool &
        is.finite(vintages$blup_sd) & vintages$blup_sd > 0 &
        is.finite(vintages$lrt_p)   & vintages$lrt_p < gh_max_lrt_p
  for (i in which(!ok)) {
    why <- c(if (vintages$n_graded[i] < gh_min_pool) sprintf("pool %d", vintages$n_graded[i]),
             if (!isTRUE(vintages$blup_sd[i] > 0)) "degenerate BLUP sd",
             if (!isTRUE(vintages$lrt_p[i] < gh_max_lrt_p))
               sprintf("coach effect undetected (LRT p = %.3f)", vintages$lrt_p[i]))
    cat(sprintf("  fails guard %s: %s\n",
                gh_season_label(vintages$season[i]), paste(why, collapse = "; ")))
  }

  # Publish the CONTIGUOUS run ending at the endpoint, not every passing vintage.
  # The top-5 cut's LRT wobbles across the 0.05 line in the mid-2010s (2015/16
  # passes, 2016/17 p = 0.064, 2017/18 passes), so cherry-picking passers would
  # punch a hole in the middle of every top-5 coach's line — and a series that
  # flickers in and out at a threshold communicates worse than a shorter one.
  # This also gives the line's start a meaning a reader can be told: the earliest
  # season from which the coach effect is detectable continuously to the present.
  n <- nrow(vintages)
  start <- n + 1L
  for (i in n:1) if (ok[i]) start <- i else break
  if (start > n) stop("No publishable vintage for cut '", cut,
                      "': the endpoint itself fails the guard.")
  keep <- vintages$cutoff[start:n]
  if (start > 1L) {
    cat(sprintf("  published window: %s onward (%d of %d vintages; %s dropped)\n",
                gh_season_label(vintages$season[start]), length(keep), n,
                gh_season_label(vintages$season[start - 1L])))
  }
  vintages$published <- vintages$cutoff %in% keep
  points <- points |> dplyr::filter(cutoff %in% keep)
  # backstop for the NaN-becomes-"F" failure above: nothing unrenderable ships
  stopifnot(!any(is.na(points$numeric_grade)), !any(is.na(points$letter_grade)))

  out <- list(
    points   = points,
    vintages = vintages,
    meta     = list(cut = cut, cutoffs = cutoffs, min_pool = gh_min_pool,
                    min_points = gh_min_points, generated = Sys.time())
  )
  saveRDS(out, file.path(gh_results_dir, paste0("coach_grade_history_", cut, ".rds")))
  cat(sprintf("  saved: %d points, %d coaches, %d published vintages\n",
              nrow(points), dplyr::n_distinct(points$coach_id), length(keep)))
  out
}

# --- verification -------------------------------------------------------------

# ACCEPTANCE TEST. The last vintage (cutoff = xx_last_data_season + 1) fits on
# every completed season, so it IS the live fit: it must reproduce
# coach_grades_<cut>.rds — same coach set, same ranks, same grades. A mismatch
# means the replay has drifted from the published pipeline and the chart must
# not ship. Tolerance 1e-9 on the numeric grade is lme4 optimizer noise, the
# tolerance refit_pipeline.R was validated at.
gh_verify_endpoint <- function(cuts = names(rp_cuts), tol = 1e-9) {
  ok_all <- TRUE
  for (cut in cuts) {
    live <- readRDS(file.path(gh_results_dir, paste0("coach_grades_", cut, ".rds")))
    h    <- readRDS(file.path(gh_results_dir, paste0("coach_grade_history_", cut, ".rds")))
    last <- h$points |> dplyr::filter(cutoff == max(cutoff))

    j <- merge(live[, c("coach_id", "numeric_grade", "letter_grade", "rank")],
               last[, c("coach_id", "numeric_grade", "letter_grade", "rank")],
               by = "coach_id", suffixes = c("_live", "_hist"))
    same_set   <- setequal(live$coach_id, last$coach_id)
    max_dgrade <- if (nrow(j)) max(abs(j$numeric_grade_live - j$numeric_grade_hist)) else NA
    same_rank  <- all(j$rank_live == j$rank_hist)
    same_letter<- all(j$letter_grade_live == j$letter_grade_hist)
    ok <- same_set && same_rank && same_letter && !is.na(max_dgrade) && max_dgrade <= tol
    ok_all <- ok_all && ok
    cat(sprintf("[%s] endpoint %s: coach set %s (%d live / %d hist), ranks %s, letters %s, max |dgrade| %.2e\n",
                cut, if (ok) "PASS" else "FAIL", same_set, nrow(live), nrow(last),
                same_rank, same_letter, max_dgrade))
  }
  invisible(ok_all)
}

# Free cross-check: for cutoffs the market benchmark already computed (14-league),
# our BLUPs must match mb_asof_blups.rds. Catches a wrong filter in the cut plumbing.
gh_verify_asof_cache <- function(tol = 1e-8) {
  f <- file.path(gh_results_dir, "mb_asof_blups.rds")
  if (!file.exists(f)) { cat("mb_asof_blups.rds absent — cross-check skipped\n"); return(invisible(NA)) }
  B <- readRDS(f)
  worst <- 0; n_ok <- 0; n_bad <- 0
  for (nm in names(B)) {
    g <- file.path(gh_cache_dir, sprintf("14league_%s.rds", nm))
    if (!file.exists(g)) next
    ours <- readRDS(g)
    # our cached table is post-bar; compare on the shared ids
    j <- merge(B[[nm]], ours$graded[, c("coach_id", "blup")], by = "coach_id",
               suffixes = c("_mb", "_gh"))
    if (!nrow(j)) next
    d <- max(abs(j$blup_mb - j$blup_gh))
    worst <- max(worst, d)
    if (d <= tol) n_ok <- n_ok + 1 else { n_bad <- n_bad + 1; cat(sprintf("  MISMATCH %s: %.2e\n", nm, d)) }
  }
  cat(sprintf("as-of cross-check: %d vintage(s) match, %d differ, worst |dblup| %.2e\n",
              n_ok, n_bad, worst))
  invisible(n_bad == 0)
}

# --- driver -------------------------------------------------------------------

gh_run_all <- function(cuts    = names(rp_cuts),
                       cutoffs = gh_first_cutoff:(xx_last_data_season + 1L),
                       refresh = FALSE) {
  prep <- gh_load_prep()
  out <- lapply(cuts, function(cut) gh_run_cut(prep, cut, cutoffs, refresh = refresh))
  names(out) <- cuts

  cat("\n", strrep("=", 60), "\nVERIFICATION\n", strrep("=", 60), "\n", sep = "")
  ok_end  <- gh_verify_endpoint(cuts)
  ok_asof <- gh_verify_asof_cache()
  if (!isTRUE(ok_end)) {
    warning("Grade-history endpoint does NOT reproduce the published grades. ",
            "Do not export the chart until this passes.")
  }

  cat("\n=== grade history complete ===\n")
  for (cut in cuts) {
    p <- out[[cut]]$points
    n_eligible <- sum(table(p$coach_id) >= gh_min_points)
    cat(sprintf("  %-9s %d points, %d coaches, %d with >= %d vintages\n",
                cut, nrow(p), dplyr::n_distinct(p$coach_id), n_eligible, gh_min_points))
  }
  invisible(out)
}
