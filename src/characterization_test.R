# Characterization (golden-master) tests for tabler.R
#
# Captures the current model's exact outputs as a frozen reference before M3
# changes the model from rank-based to points-based. After any code change,
# re-run run_characterization_tests() to see exactly what shifted. When a
# change is intentional, re-run generate_baseline() and commit the new
# baseline files alongside the code change — the commit message is the record
# of why the outputs changed.
#
# Usage (in RStudio, after sourcing source_data.r and tabler.R):
#   source("characterization_test.R")  # or source("src/characterization_test.R")
#   generate_baseline()           # run ONCE before touching M3; commit the result
#   run_characterization_tests()  # run after any code change

BASELINE_DIR <- "data/baselines"

# 3 seasons per league spanning the full 2015-2024 range (early / mid / late)
.baseline_league_seasons <- function() {
  years <- c(2015, 2019, 2024)
  unlist(lapply(xx_all_leagues(), function(league_id) {
    sapply(years, function(y) xx_league_season_id(league_id, y))
  }))
}

# Short key from a league_season_id, e.g. "GB1_2024"
.lsid_key <- function(lsid) {
  league_code <- sub(".*wettbewerb/([^/]+).*", "\\1", lsid)
  season_year <- sub(".*saison_id=", "", lsid)
  paste0(league_code, "_", season_year)
}

# ---------------------------------------------------------------------------
# generate_baseline()
#
# Writes current model outputs to data/baselines/. Run once before M3. Commit
# the generated files to git so they serve as the frozen reference going
# forward.
# ---------------------------------------------------------------------------
generate_baseline <- function() {
  chart_dir <- file.path(BASELINE_DIR, "team_charts")
  dir.create(chart_dir, recursive = TRUE, showWarnings = FALSE)

  corr_rows <- list()

  for (lsid in .baseline_league_seasons()) {
    key <- .lsid_key(lsid)
    cat("Generating baseline:", key, "\n")

    chart <- league_season_team_chart(lsid)
    write.csv(chart, file.path(chart_dir, paste0(key, ".csv")), row.names = FALSE)

    corr <- league_season_correlations(lsid)
    corr$key <- key
    corr_rows[[length(corr_rows) + 1]] <- corr
  }

  all_corr <- do.call(rbind, corr_rows)
  write.csv(all_corr, file.path(BASELINE_DIR, "correlations.csv"), row.names = FALSE)

  cat("\nDone. Commit data/baselines/ to lock in this snapshot.\n")
}

# ---------------------------------------------------------------------------
# run_characterization_tests()
#
# Re-runs the model for each baseline league-season and compares against the
# frozen reference. Any diff is printed with before/after values. When all
# outputs match, prints ALL PASS.
# ---------------------------------------------------------------------------
run_characterization_tests <- function() {
  frozen_corr <- read.csv(
    file.path(BASELINE_DIR, "correlations.csv"),
    stringsAsFactors = FALSE
  )

  all_passed <- TRUE
  results <- list()

  for (lsid in .baseline_league_seasons()) {
    key <- .lsid_key(lsid)
    cat(sprintf("%-12s ... ", key))

    current_chart <- league_season_team_chart(lsid)
    frozen_chart <- read.csv(
      file.path(BASELINE_DIR, "team_charts", paste0(key, ".csv")),
      stringsAsFactors = FALSE
    )

    current_corr <- league_season_correlations(lsid)
    frozen_row <- frozen_corr[frozen_corr$key == key, ]

    diffs <- c(
      .diff_team_chart(frozen_chart, current_chart),
      .diff_correlations(frozen_row, current_corr)
    )

    passed <- length(diffs) == 0
    if (!passed) all_passed <- FALSE
    cat(if (passed) "PASS\n" else "FAIL\n")
    if (!passed) for (d in diffs) cat("    ", d, "\n")

    results[[key]] <- list(passed = passed, diffs = diffs)
  }

  cat("\n---\n", if (all_passed) "ALL PASS\n" else "FAILURES ABOVE\n")
  invisible(results)
}

# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

.diff_team_chart <- function(frozen, current) {
  diffs <- character(0)

  f_teams <- sort(frozen$team_name)
  c_teams <- sort(current$team_name)
  if (!identical(f_teams, c_teams)) {
    added   <- setdiff(c_teams, f_teams)
    removed <- setdiff(f_teams, c_teams)
    if (length(added)   > 0) diffs <- c(diffs, paste("teams added:",   paste(added,   collapse = ", ")))
    if (length(removed) > 0) diffs <- c(diffs, paste("teams removed:", paste(removed, collapse = ", ")))
    return(diffs)
  }

  f <- frozen[order(frozen$team_name), ]
  c <- current[order(current$team_name), ]

  # Integer columns — exact match; any change is meaningful
  for (col in c("total_value_rank", "weighted_value_rank", "points_rank", "total_points")) {
    if (!(col %in% names(f)) || !(col %in% names(c))) next
    changed <- which(as.integer(c[[col]]) != as.integer(f[[col]]))
    for (i in changed) {
      diffs <- c(diffs, sprintf(
        "%s[%s]: %s -> %s",
        col, c$team_name[i], f[[col]][i], c[[col]][i]
      ))
    }
  }

  # Euro value columns — relative tolerance to absorb floating-point noise
  for (col in c("total_team_value", "weighted_team_value")) {
    if (!(col %in% names(f)) || !(col %in% names(c))) next
    fv <- as.numeric(f[[col]])
    cv <- as.numeric(c[[col]])
    rel_err <- abs(cv - fv) / pmax(abs(fv), 1)
    changed <- which(rel_err > 1e-6)
    for (i in changed) {
      diffs <- c(diffs, sprintf(
        "%s[%s]: %.2f -> %.2f",
        col, c$team_name[i], fv[i], cv[i]
      ))
    }
  }

  diffs
}

.diff_correlations <- function(frozen_row, current) {
  diffs <- character(0)
  for (col in c("unweighted_correlation", "weighted_correlation")) {
    delta <- abs(current[[col]] - frozen_row[[col]])
    if (delta > 1e-6) {
      diffs <- c(diffs, sprintf(
        "%s: %.6f -> %.6f (delta %.2e)",
        col, frozen_row[[col]], current[[col]], delta
      ))
    }
  }
  diffs
}
