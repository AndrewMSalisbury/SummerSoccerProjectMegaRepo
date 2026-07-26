# refit_pipeline.R
#
# The M3 -> M4 -> M5 refit, as runnable code. Until now this recipe lived only as
# prose in Docs/Session_Log_2026-07-10b.md ("save coach_residuals/ranked/blups per
# cut, then save_coach_grades()"), which is the kind of instruction that quietly
# rots. Everything data/results/ needs for the coach ranking is written here.
#
#   working dir src/
#   source("source_data.r"); source("coach_attribution.R"); source("refit_pipeline.R")
#   run_refit()
#
# Season span comes from xx_last_data_season (source_data.r) — one knob.
#
# WHAT THIS MUST NOT TOUCH: the forward test's frozen BLUP vintage
# (coach_blups_14league_asof<year>.rds). run_forward_test() reads that snapshot,
# not the live coach_blups_14league.rds this script overwrites, so that the
# "grades never saw the holdout season" claim stays true after a refit. See the
# header of forward_test.R.

rp_results_dir <- "data/results"

# The two published cuts. "top5" is the big-5 European leagues refit on their own
# (its own M3 fit, not a filter of the 14-league residuals); "14league" is all
# active leagues.
rp_cuts <- list(
  top5 = c(xx_league_id_PREMIER_LEAGUE, xx_league_id_LA_LIGA,
           xx_league_id_SERIE_A, xx_league_id_BUNDESLIGA, xx_league_id_LIGUE_1),
  `14league` = NULL   # NULL -> xx_all_leagues()
)

# One cut: M4 (build dataset, fit M3, residuals) then M5 (stints, stats,
# significance, mixed model). Writes four rds files and returns the pieces.
rp_refit_cut <- function(cut, seasons = 2005:xx_last_data_season) {
  leagues <- rp_cuts[[cut]]
  if (is.null(leagues)) leagues <- xx_all_leagues()

  # run_milestone4()'s step 6 calls dev.new() once per league heatmap. In a
  # non-interactive session that drops a numbered Rplots*.pdf into src/ for
  # every one of them (57 after one run). Send them to the temp dir instead —
  # the refit is not the place to be looking at plots.
  old_dev <- getOption("device")
  options(device = function(...) grDevices::pdf(file = tempfile(fileext = ".pdf")))
  on.exit({
    options(device = old_dev)
    while (grDevices::dev.cur() > 1) grDevices::dev.off()
  }, add = TRUE)
  cat("\n", strrep("#", 70), "\n# CUT: ", cut, "  (", length(leagues), " leagues, seasons ",
      min(seasons), "-", max(seasons), ")\n", strrep("#", 70), "\n", sep = "")

  m4 <- run_milestone4(seasons = seasons, leagues = leagues)
  res <- m4$residuals_tbl
  saveRDS(res, file.path(rp_results_dir, paste0("residuals_", cut, ".rds")))

  m5 <- run_milestone5(res)
  saveRDS(m5$coach_residuals,
          file.path(rp_results_dir, paste0("coach_residuals_", cut, ".rds")))
  saveRDS(m5$coach_ranked,
          file.path(rp_results_dir, paste0("coach_ranked_", cut, ".rds")))
  saveRDS(m5$mixed$coach_blups,
          file.path(rp_results_dir, paste0("coach_blups_", cut, ".rds")))

  cat(sprintf("\n[%s] saved: %d team-seasons, %d stints, %d ranked, %d BLUPs\n",
              cut, nrow(res), nrow(m5$coach_residuals),
              nrow(m5$coach_ranked), nrow(m5$mixed$coach_blups)))
  invisible(list(m4 = m4, m5 = m5))
}

# Guard: the forward test's vintage snapshot must exist and must NOT be the file
# we are about to overwrite. Cheap to check, expensive to discover later.
rp_check_vintage <- function() {
  v <- file.path(rp_results_dir, "coach_blups_14league_asof2024.rds")
  if (!file.exists(v)) {
    stop("coach_blups_14league_asof2024.rds is missing. Take the snapshot BEFORE ",
         "refitting, or the forward test loses the pre-holdout grades it scores against.")
  }
  cat("Forward-test BLUP vintage present: ", v, " (",
      nrow(readRDS(v)), " coaches)\n", sep = "")
}

run_refit <- function(seasons = 2005:xx_last_data_season, cuts = names(rp_cuts)) {
  rp_check_vintage()
  out <- lapply(cuts, function(cut) rp_refit_cut(cut, seasons = seasons))
  names(out) <- cuts

  cat("\n", strrep("#", 70), "\n# GRADES\n", strrep("#", 70), "\n", sep = "")
  grades <- save_coach_grades(results_dir = rp_results_dir)

  cat("\n=== refit complete ===\n")
  for (cut in cuts) {
    g <- grades[[cut]]
    b <- out[[cut]]$m5$mixed$coach_blups
    cat(sprintf("  %-9s %4d graded of %4d BLUPs   top: %s (%+.3f PPG)\n",
                cut, nrow(g), nrow(b), g$coach_name[1], g$blup[1]))
  }
  invisible(list(cuts = out, grades = grades))
}
