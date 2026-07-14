# site_export.R
#
# Exports the published results to site/ as JSON + assets for the static
# website (Docs/Website_Design.md sec. 6.3, Website_Implementation_Plan.md
# Phase 1). Reads only from data/ and ../Docs/Summary_of_Findings.md; writes
# only to ../site/data, ../site/assets, and ../site/writeup.html. Writing
# outside data/ is the documented exception to the data-layer rule: site/ is
# a publishing target, not analysis data. Hand-written site files (html, css,
# js) are never touched.
#
# Usage (working dir src/, like the rest of the project):
#   source("site_export.R")
#   export_site_data()
#
# Functions use the se_ prefix. Pure cache/results reader — no scraping.

library(dplyr)
library(tidyr)
library(stringr)

se_site_dir <- "../site"

# league slug (the `league` column in results tables) -> display name
se_league_names <- c(
  "premier-league"     = "Premier League",
  "laliga"             = "La Liga",
  "laliga2"            = "LaLiga 2",
  "serie-a"            = "Serie A",
  "bundesliga"         = "Bundesliga",
  "ligue-1"            = "Ligue 1",
  "championship"       = "Championship",
  "liga-portugal"      = "Liga Portugal",
  "jupiler-pro-league" = "Jupiler Pro League",
  "eredivisie"         = "Eredivisie",
  "superliga"          = "Danish Superliga",
  "ekstraklasa"        = "Ekstraklasa",
  "1-hnl"              = "1. HNL",
  "super-lig"          = "Süper Lig"
)

# same rule model_comparison.R uses to flag B teams
se_is_b_team <- function(team_name) {
  grepl(" B$|Castilla|Bilbao Athletic|Mestalla|Fabril|Sevilla Atlético", team_name)
}

se_coach_num <- function(coach_id) {
  out <- str_extract(coach_id, "(?<=/trainer/)\\d+")
  stopifnot(!anyNA(out[!is.na(coach_id)]))
  out
}

se_club_num <- function(id) {
  out <- str_extract(id, "(?<=/verein/)\\d+")
  stopifnot(!anyNA(out[!is.na(id)]))
  out
}

se_write_json <- function(x, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  jsonlite::write_json(x, path, auto_unbox = TRUE, digits = 4, null = "null",
                       na = "null")
}

se_num <- function(x, digits = 3) ifelse(is.na(x), NA, round(x, digits))

# --- load + precompute -------------------------------------------------------------

se_load <- function() {
  d <- list(
    res      = readRDS("data/results/residuals_14league.rds"),
    cr       = readRDS("data/results/coach_residuals_14league.rds"),
    ranked5  = readRDS("data/results/coach_ranked_top5.rds"),
    ranked14 = readRDS("data/results/coach_ranked_14league.rds"),
    grades5  = readRDS("data/results/coach_grades_top5.rds"),
    grades14 = readRDS("data/results/coach_grades_14league.rds"),
    fit      = readRDS("data/results/archetype_fit.rds"),
    imgs     = readRDS("data/cache/coach_images.rds")
  )
  d$crests <- if (file.exists("data/cache/team_crests.rds")) {
    readRDS("data/cache/team_crests.rds")
  } else {
    data.frame(club_id = character(), local_path = character())
  }

  # coach recommender results (Docs/Coach_Recommender_Design.md sec. 9);
  # absent file -> team pages simply omit the suggestions section
  d$rec <- if (file.exists("data/results/recommender.rds")) {
    readRDS("data/results/recommender.rds")
  } else NULL
  if (!is.null(d$rec)) {
    d$rec$facts_by_coach <- split(d$rec$facts, d$rec$facts$coach_id)
  }

  d$res <- d$res |>
    mutate(
      club_id         = gsub("/saison_id/\\d+$", "", team_season_id),
      club_num        = se_club_num(club_id),
      expected_points = predicted_ppg * games_played,
      is_b_team       = se_is_b_team(team_name)
    )

  d$cr <- d$cr |>
    # guard: build_coach_residuals() dedupes tenure brackets since 2026-07-10;
    # kept as a no-op safety net against stale results files (rule: earliest
    # date_from per team-season × coach, same as cf_build_analysis_table())
    group_by(team_season_id, coach_id) |>
    slice_min(date_from, n = 1, with_ties = FALSE) |>
    ungroup() |>
    mutate(
      coach_num = se_coach_num(coach_id),
      club_id   = gsub("/saison_id/\\d+$", "", team_season_id),
      club_num  = se_club_num(club_id),
      expected_points = predicted_ppg * n_games
    ) |>
    left_join(d$res |> select(team_season_id, games_played),
              by = "team_season_id")

  # coach_id -> site-relative image path (files copied by se_copy_assets)
  img_ok <- d$imgs |> filter(!is.na(local_path))
  d$img_map <- setNames(paste0("assets/coaches/", basename(img_ok$local_path)),
                        img_ok$coach_id)

  # club_num -> site-relative crest path
  crest_ok <- d$crests |> filter(!is.na(local_path))
  d$crest_map <- setNames(paste0("assets/crests/", basename(crest_ok$local_path)),
                          se_club_num(crest_ok$club_id))

  # latest display name per club (names drift across seasons)
  d$club_names <- d$res |>
    group_by(club_num) |>
    slice_max(season, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(club_num, club_name = team_name)

  d
}

se_crest_path <- function(d, club_num) {
  p <- d$crest_map[club_num]
  ifelse(is.na(p), NA_character_, p)
}

# --- ratings -----------------------------------------------------------------------

# One cut's rating block for a coach, or NULL if not graded in that cut.
se_rating_cut <- function(d, coach_id, cut) {
  grades <- if (cut == "top5") d$grades5 else d$grades14
  ranked <- if (cut == "top5") d$ranked5 else d$ranked14
  g <- grades[grades$coach_id == coach_id, ]
  if (nrow(g) == 0) return(NULL)
  r <- ranked[ranked$coach_id == coach_id, ]
  list(
    cut           = cut,
    cut_label     = if (cut == "top5") "Top-5 leagues" else "All leagues",
    blup          = se_num(g$blup, 4),
    numeric_grade = g$numeric_grade,
    letter_grade  = g$letter_grade,
    rank          = g$rank,
    n_ranked      = nrow(grades),
    mean_residual = if (nrow(r)) se_num(r$mean_residual) else NULL,
    ci            = if (nrow(r) && !is.na(r$ci_lower)) {
                      c(se_num(r$ci_lower), se_num(r$ci_upper))
                    } else NULL,
    significant   = if (nrow(r)) isTRUE(r$significant) else FALSE
  )
}

# Headline rating (top-5 preferred, per Docs/Website_Design.md sec. 2) plus
# the other cut where it exists.
se_rating <- function(d, coach_id) {
  top5 <- se_rating_cut(d, coach_id, "top5")
  all14 <- se_rating_cut(d, coach_id, "14league")
  if (is.null(top5) && is.null(all14)) return(NULL)
  headline <- if (!is.null(top5)) top5 else all14
  other <- if (!is.null(top5)) all14 else NULL
  headline$other_cut <- other
  headline
}

# --- coach summary paragraph -------------------------------------------------------

se_season_label <- function(season) sprintf("%d/%02d", season, (season + 1) %% 100)

se_coach_summary <- function(name, rating, stints) {
  n_stints <- nrow(stints)
  n_clubs  <- n_distinct(stints$club_num)
  n_games  <- sum(stints$n_games)
  span <- paste0(se_season_label(min(stints$season)), " to ",
                 se_season_label(max(stints$season)))

  base <- sprintf(
    "%s has %d coaching stint%s at %d club%s (%d league games) in the dataset, from %s.",
    name, n_stints, if (n_stints == 1) "" else "s",
    n_clubs, if (n_clubs == 1) "" else "s", n_games, span)

  ok <- stints |> filter(!is.na(partial_residual_ppg), n_games >= 5)
  perf <- ""
  if (nrow(ok) > 0) {
    best  <- ok |> slice_max(partial_residual_ppg, n = 1, with_ties = FALSE)
    worst <- ok |> slice_min(partial_residual_ppg, n = 1, with_ties = FALSE)
    perf <- sprintf(
      " The best stint above squad-value expectation was %s %s (%+.2f PPG); the toughest was %s %s (%+.2f PPG).",
      best$team_name, se_season_label(best$season), best$partial_residual_ppg,
      worst$team_name, se_season_label(worst$season), worst$partial_residual_ppg)
  }

  rate <- if (is.null(rating)) {
    " Too few games for a grade (the ranking requires at least 3 stints and 10 games)."
  } else {
    sig <- if (isTRUE(rating$significant))
      " — one of the few coaches statistically significant after FDR correction" else ""
    sprintf(
      " Overall grade: %s (%.1f/100), ranked %d of %d in the %s cut%s.",
      rating$letter_grade, rating$numeric_grade, rating$rank, rating$n_ranked,
      rating$cut_label, sig)
  }
  paste0(base, rate, perf)
}

# --- coach pages -------------------------------------------------------------------

se_export_coaches <- function(d) {
  fit_by_coach <- split(d$fit$per_coach, d$fit$per_coach$coach_id)

  coaches <- d$cr |> group_by(coach_id, coach_num, coach_name) |> group_split()
  for (g in coaches) {
    coach_id <- g$coach_id[1]
    stints <- g |> arrange(season, date_from)
    rating <- se_rating(d, coach_id)

    fit <- NULL
    pc <- fit_by_coach[[coach_id]]
    if (!is.null(pc)) {
      findings <- pc |>
        filter(recurs_in_strict) |>
        arrange(desc(abs(r_fallback)))
      fit <- list(
        n_stints = max(pc$n_stints, na.rm = TRUE),
        findings = lapply(seq_len(nrow(findings)), function(i) list(
          label     = findings$archetype_label[i],
          r         = se_num(findings$r_fallback[i], 2),
          r_strict  = se_num(findings$r_strict[i], 2),
          direction = if (findings$r_fallback[i] > 0) "+" else "-"
        ))
      )
    }

    out <- list(
      id   = as.integer(g$coach_num[1]),
      name = g$coach_name[1],
      img  = unname(d$img_map[coach_id]),
      career = list(
        first_season = min(stints$season),
        last_season  = max(stints$season),
        # I() keeps length-1 vectors as JSON arrays under auto_unbox
        leagues      = I(unname(se_league_names[unique(stints$league)])),
        n_stints     = nrow(stints),
        total_games  = sum(stints$n_games),
        n_clubs      = n_distinct(stints$club_num)
      ),
      rating = rating,
      stints = lapply(seq_len(nrow(stints)), function(i) {
        s <- stints[i, ]
        list(
          season          = s$season,
          team_id         = as.integer(s$club_num),
          team            = s$team_name,
          crest           = unname(se_crest_path(d, s$club_num)),
          league          = s$league,
          league_name     = unname(se_league_names[s$league]),
          date_from       = if (is.na(s$date_from)) NULL else format(s$date_from, "%Y-%m-%d"),
          n_games         = s$n_games,
          actual_points   = s$actual_points,
          expected_points = se_num(s$expected_points, 1),
          actual_ppg      = se_num(s$actual_ppg),
          predicted_ppg   = se_num(s$predicted_ppg),
          residual_ppg    = se_num(s$partial_residual_ppg),
          season_share    = se_num(s$n_games / s$games_played, 2)
        )
      }),
      archetype_fit = fit,
      summary = se_coach_summary(g$coach_name[1], rating, stints)
    )
    se_write_json(out, file.path(se_site_dir, "data/coaches",
                                 paste0(g$coach_num[1], ".json")))
  }
  cat("coaches exported:", length(coaches), "\n")
}

# --- suggested coaches (recommender) -------------------------------------------------

# same map as cr_league_countries (coach_recommender.R); duplicated so the
# exporter stays a standalone results-reader
se_league_countries <- c(
  "premier-league" = "England",     "championship" = "England",
  "laliga" = "Spain",               "laliga2" = "Spain",
  "serie-a" = "Italy",              "bundesliga" = "Germany",
  "ligue-1" = "France",             "liga-portugal" = "Portugal",
  "jupiler-pro-league" = "Belgium", "eredivisie" = "Netherlands",
  "superliga" = "Denmark",          "ekstraklasa" = "Poland",
  "1-hnl" = "Croatia",              "super-lig" = "Turkey"
)

# Builds the team page's suggested-coaches block from recommender.rds, or NULL
# when the club has no scored latest-season big-5 squad. Ranking is by the
# validated quality score (payoff rule 2026-07-13); fit/deployment ship as
# exploratory columns.
se_suggestions <- function(d, team_season_ids) {
  if (is.null(d$rec)) return(NULL)
  ts <- intersect(team_season_ids, names(d$rec$teams))
  if (length(ts) == 0) return(NULL)
  entry <- d$rec$teams[[ts[1]]]
  team_league <- entry$league_key   # e.g. premier_league
  # league_key -> slug ("premier_league" -> "premier-league")
  team_slug <- gsub("_", "-", team_league)
  team_country <- unname(se_league_countries[team_slug])

  s <- entry$suggestions
  coaches <- lapply(seq_len(nrow(s)), function(i) {
    r <- s[i, ]
    f <- d$rec$facts_by_coach[[r$coach_id]]
    nat <- if (!is.null(f) && !is.na(f$nationality)) {
      strsplit(f$nationality, ", ")[[1]][1]
    } else NULL
    list(
      id            = as.integer(se_coach_num(r$coach_id)),
      name          = r$coach_name,
      img           = unname(d$img_map[r$coach_id]),
      rank          = r$headline_rank,
      tier          = r$tier,
      grade = list(letter = r$letter_grade,
                   cut_label = if (r$cut == "top5") "Top-5 leagues" else "All leagues",
                   rank = r$rank_in_cut),
      quality       = se_num(r$quality, 4),
      fit           = se_num(r$fit, 4),
      deployment    = se_num(r$deployment, 4),
      exploratory_total = se_num(r$uplift_ppg, 4),
      lo            = se_num(r$lo, 3),
      hi            = se_num(r$hi, 3),
      # plausibility badges, precomputed against this team
      this_league   = !is.null(f) && team_slug %in% f$leagues[[1]],
      this_country  = !is.null(f) && !is.null(team_country) &&
                        team_country %in% f$countries[[1]],
      big5          = !is.null(f) && f$big5_games >= 30,
      club_level    = if (!is.null(f)) se_num(f$club_level, 1) else NULL,
      last_season   = if (!is.null(f)) f$last_season else NULL,
      domestic      = !is.null(nat) && !is.null(team_country) &&
                        nat == team_country
    )
  })

  sim <- entry$similar
  similar <- lapply(seq_len(nrow(sim)), function(i) {
    rating <- se_rating(d, sim$coach_id[i])
    list(
      id         = as.integer(se_coach_num(sim$coach_id[i])),
      name       = sim$coach_name[i],
      img        = unname(d$img_map[sim$coach_id[i]]),
      similarity = se_num(sim$similarity[i], 3),
      n_stints   = sim$n_stints_b5[i],
      mean_residual = se_num(sim$mean_res_b5[i], 3),
      grade = if (is.null(rating)) NULL else list(
        letter = rating$letter_grade, cut_label = rating$cut_label)
    )
  })

  list(
    season       = entry$season,
    team_level   = se_num(entry$team_level, 1),
    level_band   = 20,   # default +/- percentile band for the level filter
    active_since = entry$season - 1,   # "recently active" threshold season
    coaches      = coaches,
    similar      = similar
  )
}

# --- team pages --------------------------------------------------------------------

se_export_teams <- function(d) {
  grade_map <- lapply(split(d$cr$coach_id, d$cr$coach_num), `[`, 1)

  clubs <- d$res |> group_by(club_num) |> group_split()
  for (g in clubs) {
    club_num <- g$club_num[1]
    name <- d$club_names$club_name[d$club_names$club_num == club_num]
    seasons <- g |> arrange(season)

    hist <- d$cr |>
      filter(club_num == !!club_num) |>
      arrange(season, date_from)

    # seasons with a residual row but no attributed stint (coach scrape gap or
    # the M5 minutes-coverage filter) get an explicit placeholder row
    missing <- setdiff(seasons$season, unique(hist$season))

    coach_rows <- c(
      lapply(seq_len(nrow(hist)), function(i) {
        s <- hist[i, ]
        rating <- se_rating(d, s$coach_id)
        list(
          season        = s$season,
          league        = s$league,
          league_name   = unname(se_league_names[s$league]),
          coach_id      = as.integer(s$coach_num),
          coach         = s$coach_name,
          img           = unname(d$img_map[s$coach_id]),
          date_from     = if (is.na(s$date_from)) NULL else format(s$date_from, "%Y-%m-%d"),
          n_games       = s$n_games,
          actual_ppg    = se_num(s$actual_ppg),
          predicted_ppg = se_num(s$predicted_ppg),
          residual_ppg  = se_num(s$partial_residual_ppg),
          grade = if (is.null(rating)) NULL else list(
            letter = rating$letter_grade, rank = rating$rank,
            n_ranked = rating$n_ranked, cut_label = rating$cut_label)
        )
      }),
      lapply(missing, function(yr) {
        s <- seasons[seasons$season == yr, ][1, ]
        list(season = yr, league = s$league,
             league_name = unname(se_league_names[s$league]),
             coach_id = NULL, coach = NULL,
             note = "coach attribution unavailable for this season")
      })
    )
    ord <- order(vapply(coach_rows, function(r) r$season, numeric(1)))

    ok <- seasons |> filter(!is.na(residual))
    out <- list(
      id      = as.integer(club_num),
      name    = name,
      crest   = unname(se_crest_path(d, club_num)),
      leagues = I(unname(se_league_names[unique(seasons$league)])),
      is_b_team = any(seasons$is_b_team),
      aggregate = list(
        n_seasons     = nrow(seasons),
        first_season  = min(seasons$season),
        last_season   = max(seasons$season),
        mean_residual = if (nrow(ok)) se_num(mean(ok$residual)) else NULL,
        best  = if (nrow(ok)) list(season = ok$season[which.max(ok$residual)],
                                   residual_points = se_num(max(ok$residual_points), 1)) else NULL,
        worst = if (nrow(ok)) list(season = ok$season[which.min(ok$residual)],
                                   residual_points = se_num(min(ok$residual_points), 1)) else NULL
      ),
      seasons = lapply(seq_len(nrow(seasons)), function(i) {
        s <- seasons[i, ]
        list(
          season          = s$season,
          league          = s$league,
          league_name     = unname(se_league_names[s$league]),
          games           = s$games_played,
          points          = s$total_points,
          ppg             = se_num(s$points_per_game),
          expected_points = se_num(s$expected_points, 1),
          predicted_ppg   = se_num(s$predicted_ppg),
          residual_ppg    = se_num(s$residual),
          residual_points = se_num(s$residual_points, 1),
          squad_value     = s$total_team_value,
          norm_weighted   = se_num(s$norm_weighted_value),
          is_b_team       = s$is_b_team,
          residual_note   = if (is.na(s$residual))
            "no residual — insufficient market value data" else NULL
        )
      }),
      coach_history = coach_rows[ord],
      suggestions = se_suggestions(d, g$team_season_id)
    )
    se_write_json(out, file.path(se_site_dir, "data/teams",
                                 paste0(club_num, ".json")))
  }
  cat("teams exported:", length(clubs), "\n")
}

# --- league pages ------------------------------------------------------------------

se_export_leagues <- function(d) {
  for (slug in unique(d$res$league)) {
    lr <- d$res |> filter(league == slug)
    lcr <- d$cr |> filter(league == slug)

    coaches_by_ts <- lcr |>
      arrange(date_from) |>
      group_by(team_season_id) |>
      group_split()
    coaches_map <- setNames(
      lapply(coaches_by_ts, function(g) {
        lapply(seq_len(nrow(g)), function(i) list(
          id = as.integer(g$coach_num[i]), name = g$coach_name[i],
          games = g$n_games[i]))
      }),
      vapply(coaches_by_ts, function(g) g$team_season_id[1], character(1))
    )

    standings <- lapply(sort(unique(lr$season)), function(yr) {
      rows <- lr |> filter(season == yr) |> arrange(desc(total_points))
      lapply(seq_len(nrow(rows)), function(i) {
        s <- rows[i, ]
        cs <- coaches_map[[s$team_season_id]]
        list(
          team_id         = as.integer(s$club_num),
          team            = s$team_name,
          crest           = unname(se_crest_path(d, s$club_num)),
          games           = s$games_played,
          points          = s$total_points,
          ppg             = se_num(s$points_per_game),
          expected_points = se_num(s$expected_points, 1),
          residual_points = se_num(s$residual_points, 1),
          residual_ppg    = se_num(s$residual),
          is_b_team       = s$is_b_team,
          residual_note   = if (is.na(s$residual))
            "no residual — insufficient market value data" else NULL,
          coaches         = if (is.null(cs)) list() else cs
        )
      })
    })
    names(standings) <- sort(unique(lr$season))

    ok <- lr |> filter(!is.na(residual))
    top_over <- ok |> slice_max(residual_points, n = 5)
    top_under <- ok |> slice_min(residual_points, n = 5)
    season_block <- function(s) lapply(seq_len(nrow(s)), function(i) list(
      team_id = as.integer(s$club_num[i]), team = s$team_name[i],
      season = s$season[i], residual_points = se_num(s$residual_points[i], 1)))

    top_coaches <- lcr |>
      group_by(coach_num, coach_name) |>
      summarize(games = sum(n_games), stints = n(), .groups = "drop") |>
      slice_max(games, n = 5)

    out <- list(
      id      = slug,
      name    = unname(se_league_names[slug]),
      seasons = I(sort(unique(lr$season))),
      stats = list(
        n_team_seasons = nrow(lr),
        r2   = se_num(cor(ok$predicted_ppg, ok$points_per_game)^2),
        rmse = se_num(sqrt(mean(ok$residual^2))),
        top_overperformers  = season_block(top_over),
        top_underperformers = season_block(top_under),
        top_coaches = lapply(seq_len(nrow(top_coaches)), function(i) list(
          id = as.integer(top_coaches$coach_num[i]),
          name = top_coaches$coach_name[i],
          games = top_coaches$games[i], stints = top_coaches$stints[i]))
      ),
      standings = standings
    )
    se_write_json(out, file.path(se_site_dir, "data/leagues",
                                 paste0(slug, ".json")))
  }
  cat("leagues exported:", n_distinct(d$res$league), "\n")
}

# --- home page + search + meta ----------------------------------------------------

se_export_small <- function(d) {
  # stint/game/club counts in grades5 cover top-5-league stints only; the
  # leaderboard shows full-career totals (same definition as the coach pages'
  # career header) so the two never disagree for coaches with stints in both
  # cuts (e.g. a La Liga + LaLiga 2 career)
  career <- d$cr |>
    group_by(coach_id) |>
    summarise(career_stints = n(),
              career_games  = sum(n_games),
              career_clubs  = n_distinct(club_num),
              .groups = "drop")
  lb <- d$grades5 |>
    left_join(d$ranked5 |> select(coach_id, mean_residual, ci_lower, ci_upper,
                                  significant),
              by = "coach_id") |>
    left_join(career, by = "coach_id") |>
    mutate(coach_num = se_coach_num(coach_id))
  stopifnot(!anyNA(lb$career_stints))
  leaderboard <- lapply(seq_len(nrow(lb)), function(i) {
    s <- lb[i, ]
    list(
      id = as.integer(s$coach_num), name = s$coach_name,
      img = unname(d$img_map[s$coach_id]),
      rank = s$rank, letter_grade = s$letter_grade,
      numeric_grade = s$numeric_grade, blup = se_num(s$blup, 4),
      n_stints = s$career_stints, total_games = s$career_games,
      n_clubs = s$career_clubs,
      mean_residual = se_num(s$mean_residual),
      significant = isTRUE(s$significant)
    )
  })
  se_write_json(list(cut_label = "Top-5 leagues", coaches = leaderboard),
                file.path(se_site_dir, "data/leaderboard.json"))

  search <- c(
    lapply(seq_along(se_league_names), function(i) list(
      t = "l", id = names(se_league_names)[i],
      n = unname(se_league_names[i]))),
    {
      cs <- d$cr |> distinct(coach_num, coach_name)
      lapply(seq_len(nrow(cs)), function(i) list(
        t = "c", id = as.integer(cs$coach_num[i]), n = cs$coach_name[i]))
    },
    lapply(seq_len(nrow(d$club_names)), function(i) list(
      t = "t", id = as.integer(d$club_names$club_num[i]),
      n = d$club_names$club_name[i]))
  )
  se_write_json(search, file.path(se_site_dir, "data/search_index.json"))

  g <- d$fit$global
  se_write_json(list(
    generated = format(Sys.time(), "%Y-%m-%d %H:%M"),
    dataset = list(
      leagues = n_distinct(d$res$league), first_season = min(d$res$season),
      last_season = max(d$res$season), team_seasons = nrow(d$res),
      coaches = n_distinct(d$cr$coach_id), clubs = n_distinct(d$res$club_num),
      n_graded_top5 = nrow(d$grades5), n_graded_14league = nrow(d$grades14)
    ),
    league_names = as.list(se_league_names),
    archetype_global = list(
      p = se_num(g$p, 4), p_strict = se_num(g$p_strict, 4),
      chisq = se_num(g$chisq, 2), df = g$df,
      f3_coef = se_num(g$f3_coef, 2), f3_t = se_num(g$f3_t, 2)
    )
  ), file.path(se_site_dir, "data/meta.json"))
  cat("leaderboard, search index, meta exported\n")
}

# --- assets ------------------------------------------------------------------------

se_copy_assets <- function(d) {
  coach_dir <- file.path(se_site_dir, "assets/coaches")
  crest_dir <- file.path(se_site_dir, "assets/crests")
  dir.create(coach_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(crest_dir, recursive = TRUE, showWarnings = FALSE)

  # only coaches that actually have a page
  used <- d$imgs |>
    filter(coach_id %in% unique(d$cr$coach_id), !is.na(local_path))
  n1 <- sum(file.copy(used$local_path, coach_dir, overwrite = TRUE))

  crests <- d$crests |> filter(!is.na(local_path))
  n2 <- if (nrow(crests)) sum(file.copy(crests$local_path, crest_dir,
                                        overwrite = TRUE)) else 0
  cat("assets copied:", n1, "coach images,", n2, "crests\n")
}

# --- writeup -----------------------------------------------------------------------

se_slugify <- function(x) {
  x <- tolower(gsub("[^A-Za-z0-9 ]", "", x))
  gsub(" +", "-", trimws(x))
}

se_export_writeup <- function() {
  md <- readLines("../Docs/Summary_of_Findings.md", encoding = "UTF-8")
  html <- commonmark::markdown_html(paste(md, collapse = "\n"),
                                    extensions = TRUE)

  # add ids to h2 headings and build the TOC from them
  heads <- regmatches(html, gregexpr("<h2>[^<]+</h2>", html))[[1]]
  toc_items <- character(0)
  for (h in heads) {
    text <- gsub("</?h2>", "", h)
    id <- se_slugify(text)
    html <- sub(h, sprintf('<h2 id="%s">%s</h2>', id, text), html, fixed = TRUE)
    toc_items <- c(toc_items,
                   sprintf('<li><a href="#%s">%s</a></li>', id, text))
  }

  page <- paste0(
    '<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n',
    '<meta name="viewport" content="width=device-width, initial-scale=1">\n',
    '<title>Summary of Findings — Football Coach Valuation</title>\n',
    '<link rel="stylesheet" href="css/site.css">\n',
    '<script src="js/theme.js"></script>\n</head>\n<body>\n',
    '<div id="site-header"></div>\n',
    '<div class="writeup-layout container">\n',
    '<nav class="toc" aria-label="Table of contents"><h3>Contents</h3><ul>',
    paste(toc_items, collapse = "\n"), '</ul></nav>\n',
    '<article class="writeup">\n', html, '\n</article>\n</div>\n',
    '<script type="module">import { initHeader } from "./js/components.js"; initHeader();</script>\n',
    '</body>\n</html>\n'
  )
  writeLines(page, file.path(se_site_dir, "writeup.html"), useBytes = TRUE)
  cat("writeup.html generated (", length(heads), "TOC sections )\n")
}

# --- entry point -------------------------------------------------------------------

export_site_data <- function() {
  d <- se_load()

  # wipe generated outputs so removals don't linger; hand-written files stay
  for (p in c("data", "assets")) {
    unlink(file.path(se_site_dir, p), recursive = TRUE)
  }

  se_export_coaches(d)
  se_export_teams(d)
  se_export_leagues(d)
  se_export_small(d)
  se_copy_assets(d)
  se_export_writeup()
  cat("\nSITE EXPORT COMPLETE ->", normalizePath(se_site_dir, mustWork = FALSE), "\n")
  invisible(d)
}
