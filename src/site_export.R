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

# recommender league_key -> the dataset's league slug (the URL-derived slugs
# don't follow one rule: "la_liga" -> "laliga", not "la-liga")
se_key_to_slug <- c(premier_league = "premier-league", la_liga = "laliga",
                    serie_a = "serie-a", bundesliga = "bundesliga",
                    ligue_1 = "ligue-1")

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

  # player photos for the team builder (scrape may still be running; players
  # not in the lookup yet simply get the initials fallback)
  d$player_imgs <- if (file.exists("data/cache/player_images.rds")) {
    readRDS("data/cache/player_images.rds")
  } else {
    data.frame(player_id = character(), local_path = character())
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
    " Too thin a record for a grade (grading requires at least 3 stints and 109 league games in the dataset)."
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

# plausibility badges for one coach, precomputed against a target team
# Compact squad-fit block for one coach on one team (Docs/Squad_Fit_Gap_Design.md).
# NULL when recommender.rds predates the feature or the coach has no diagnostic.
# euros are rounded to whole millions for display.
se_squad_fit <- function(entry, coach_id) {
  sf <- entry$squad_fit[[coach_id]]
  if (is.null(sf)) return(NULL)
  strand <- if (!is.null(sf$strand) && nrow(sf$strand))
    lapply(seq_len(nrow(sf$strand)), function(j)
      list(label = sf$strand$label[j], eur_m = round(sf$strand$eur[j] / 1e6)))
    else list()
  gaps <- if (!is.null(sf$gaps) && nrow(sf$gaps))
    lapply(seq_len(nrow(sf$gaps)), function(j)
      list(label = sf$gaps$label[j], best_fill = se_num(sf$gaps$best_fill[j], 2)))
    else list()
  list(gap_pct = se_num(sf$gap_pct, 1),
       gap_eur_m = round(sf$gap_eur / 1e6),
       strand = strand, gaps = gaps)
}

# Descriptive career dossier for the suggestion drawer (preferred formations,
# rigidity, career span, clubs coached). NULL when the coach isn't in the pool.
se_coach_dossier <- function(d, coach_id) {
  x <- d$rec$dossier[[coach_id]]
  if (is.null(x)) return(NULL)
  forms <- if (length(x$formations))
    lapply(x$formations, function(f)
      list(formation = f$formation, pct = round(100 * f$share)))
    else list()
  teams <- if (length(x$teams))
    lapply(x$teams, function(t)
      list(name = t$name, games = t$games,
           span = if (t$first == t$last) as.character(t$first)
                  else paste0(t$first, "–", substr(t$last, 3, 4))))
    else list()
  list(
    formations   = forms,
    rigidity     = se_num(x$rigidity, 2),
    first_season = x$first_season,
    last_season  = x$last_season,
    total_games  = x$total_games,
    n_stints     = x$n_stints,
    n_teams      = x$n_teams,
    leagues      = I(unname(se_league_names[x$leagues])),
    teams        = teams
  )
}

se_coach_badges <- function(d, coach_id, team_slug, team_country) {
  f <- d$rec$facts_by_coach[[coach_id]]
  nat <- if (!is.null(f) && !is.na(f$nationality)) {
    strsplit(f$nationality, ", ")[[1]][1]
  } else NULL
  list(
    this_league  = !is.null(f) && team_slug %in% f$leagues[[1]],
    this_country = !is.null(f) && !is.null(team_country) &&
                     team_country %in% f$countries[[1]],
    big5         = !is.null(f) && f$big5_games >= 30,
    club_level   = if (!is.null(f)) se_num(f$club_level, 1) else NULL,
    last_season  = if (!is.null(f)) f$last_season else NULL,
    domestic     = !is.null(nat) && !is.null(team_country) &&
                     nat == team_country
  )
}

# Builds the team page's suggested-coaches block from recommender.rds, or NULL
# when the club has no scored latest-season big-5 squad. The site leads with
# the similarity list (Andrew's direction 2026-07-13, second revision) and
# currently hides the validated-quality table; the `coaches` array is still
# exported so restoring that view is frontend-only.
se_suggestions <- function(d, team_season_ids) {
  if (is.null(d$rec)) return(NULL)
  ts <- intersect(team_season_ids, names(d$rec$teams))
  if (length(ts) == 0) return(NULL)
  entry <- d$rec$teams[[ts[1]]]
  team_slug <- unname(se_key_to_slug[entry$league_key])
  stopifnot(!is.na(team_slug))
  team_country <- unname(se_league_countries[team_slug])

  s <- entry$suggestions
  coaches <- lapply(seq_len(nrow(s)), function(i) {
    r <- s[i, ]
    c(list(
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
      hi            = se_num(r$hi, 3)
    ), se_coach_badges(d, r$coach_id, team_slug, team_country))
  })

  # order the similarity pool by a quality-tilted blend (Andrew's direction;
  # weight softened 0.7/0.3 -> 0.85/0.15 on review): z-score similarity and
  # the quality BLUP within the pool, rank by 0.85 x similarity + 0.15 x
  # quality. The rank is assigned here, once, so cards keep their number when
  # the frontend filters the pool.
  sim <- entry$similar
  ratings <- lapply(sim$coach_id, function(cid) se_rating(d, cid))
  blup <- vapply(ratings, function(r) {
    if (is.null(r) || is.null(r$blup)) NA_real_ else as.numeric(r$blup)
  }, numeric(1))
  zscore <- function(x) {
    s <- sd(x, na.rm = TRUE)
    if (is.na(s) || s == 0) return(rep(0, length(x)))
    (x - mean(x, na.rm = TRUE)) / s
  }
  z_q <- zscore(blup); z_q[is.na(z_q)] <- 0
  ord <- order(-(0.85 * zscore(sim$similarity) + 0.15 * z_q))
  sim <- sim[ord, ]; ratings <- ratings[ord]

  similar <- lapply(seq_len(nrow(sim)), function(i) {
    rating <- ratings[[i]]
    c(list(
      id         = as.integer(se_coach_num(sim$coach_id[i])),
      name       = sim$coach_name[i],
      img        = unname(d$img_map[sim$coach_id[i]]),
      rank       = i,
      similarity = se_num(sim$similarity[i], 3),
      n_stints   = sim$n_stints_b5[i],
      mean_residual = se_num(sim$mean_res_b5[i], 3),
      grade = if (is.null(rating)) NULL else list(
        letter = rating$letter_grade, cut_label = rating$cut_label),
      squad_fit = se_squad_fit(entry, sim$coach_id[i]),
      career    = se_coach_dossier(d, sim$coach_id[i])
    ), se_coach_badges(d, sim$coach_id[i], team_slug, team_country))
  })

  list(
    season       = entry$season,
    team_level   = se_num(entry$team_level, 1),
    level_band   = 10,   # default +/- percentile band for the level filter
    active_since = entry$season - 1,   # "recently active" threshold season
    coaches      = coaches,
    similar      = similar
  )
}

# --- team builder (Docs/Team_Builder_Design.md) --------------------------------------

# Pitch coordinates for every formation string in cr_formation_slots
# (persisted to recommender.rds$builder$formation_slots). x = 0..100 left to
# right, y = 0..100 own goal line to opponent goal line; the GK slot is
# explicit here (type "GK") though implicit in the slot-count vectors.
# se_export_builder() hard-stops if a layout's type counts disagree with the
# model's slot counts — the two must never drift apart.
se_formation_layouts <- local({
  sl <- function(type, side, x, y) data.frame(type = type, side = side,
                                              x = x, y = y)
  gk <- sl("GK", NA, 50, 2)
  back4 <- rbind(sl("FB", "L", 15, 24), sl("CB", "L", 38, 18),
                 sl("CB", "R", 62, 18), sl("FB", "R", 85, 24))
  # flat back three at y = 18 (level with the back-4 CBs): a deeper middle CB
  # (the old 13) sat right on top of the GK circle once players were placed.
  # The GK at y = 2 keeps both the circles and the below-circle name chips
  # clear in the CB-over-GK stack.
  back3 <- rbind(sl("CB", "L", 25, 18), sl("CB", NA, 50, 18),
                 sl("CB", "R", 75, 18))
  list(
    "4-2-3-1" = rbind(gk, back4,
      sl("DM", "L", 38, 38), sl("DM", "R", 62, 38),
      sl("W", "L", 15, 62), sl("AM", NA, 50, 58), sl("W", "R", 85, 62),
      sl("ST", NA, 50, 80)),
    "4-3-3" = rbind(gk, back4,
      sl("CM", "L", 30, 44), sl("CM", NA, 50, 38), sl("CM", "R", 70, 44),
      sl("W", "L", 18, 66), sl("W", "R", 82, 66), sl("ST", NA, 50, 80)),
    "4-4-2" = rbind(gk, back4,
      sl("W", "L", 12, 50), sl("CM", "L", 38, 46), sl("CM", "R", 62, 46),
      sl("W", "R", 88, 50), sl("ST", "L", 38, 78), sl("ST", "R", 62, 78)),
    "3-4-2-1" = rbind(gk, back3,
      sl("FB", "L", 10, 42), sl("CM", "L", 38, 40), sl("CM", "R", 62, 40),
      sl("FB", "R", 90, 42), sl("AM", "L", 35, 62), sl("AM", "R", 65, 62),
      sl("ST", NA, 50, 80)),
    "3-5-2" = rbind(gk, back3,
      sl("FB", "L", 8, 45), sl("CM", "L", 30, 44), sl("CM", NA, 50, 38),
      sl("CM", "R", 70, 44), sl("FB", "R", 92, 45),
      sl("ST", "L", 38, 78), sl("ST", "R", 62, 78)),
    "4-1-4-1" = rbind(gk, back4,
      sl("DM", NA, 50, 34),
      sl("W", "L", 12, 52), sl("CM", "L", 38, 48), sl("CM", "R", 62, 48),
      sl("W", "R", 88, 52), sl("ST", NA, 50, 80)),
    "4-3-1-2" = rbind(gk, back4,
      sl("CM", "L", 30, 42), sl("CM", NA, 50, 38), sl("CM", "R", 70, 42),
      sl("AM", NA, 50, 58), sl("ST", "L", 38, 76), sl("ST", "R", 62, 76)),
    "3-4-1-2" = rbind(gk, back3,
      sl("FB", "L", 10, 42), sl("CM", "L", 38, 40), sl("CM", "R", 62, 40),
      sl("FB", "R", 90, 42), sl("AM", NA, 50, 58),
      sl("ST", "L", 38, 76), sl("ST", "R", 62, 76)),
    "3-4-3" = rbind(gk, back3,
      sl("FB", "L", 10, 42), sl("CM", "L", 38, 40), sl("CM", "R", 62, 40),
      sl("FB", "R", 90, 42), sl("W", "L", 22, 66), sl("W", "R", 78, 66),
      sl("ST", NA, 50, 80)),
    "4-4-1-1" = rbind(gk, back4,
      sl("W", "L", 12, 50), sl("CM", "L", 38, 46), sl("CM", "R", 62, 46),
      sl("W", "R", 88, 50), sl("AM", NA, 50, 62), sl("ST", NA, 50, 80)),
    "5-3-2" = rbind(gk,
      sl("FB", "L", 10, 30), sl("CB", "L", 30, 18), sl("CB", NA, 50, 18),
      sl("CB", "R", 70, 18), sl("FB", "R", 90, 30),
      sl("CM", "L", 30, 44), sl("CM", NA, 50, 40), sl("CM", "R", 70, 44),
      sl("ST", "L", 38, 76), sl("ST", "R", 62, 76)),
    "3-1-4-2" = rbind(gk, back3,
      sl("DM", NA, 50, 34),
      sl("FB", "L", 10, 46), sl("CM", "L", 30, 44), sl("CM", "R", 70, 44),
      sl("FB", "R", 90, 46), sl("ST", "L", 38, 76), sl("ST", "R", 62, 76)),
    "5-4-1" = rbind(gk,
      sl("FB", "L", 10, 28), sl("CB", "L", 30, 18), sl("CB", NA, 50, 18),
      sl("CB", "R", 70, 18), sl("FB", "R", 90, 28),
      sl("W", "L", 15, 50), sl("CM", "L", 38, 46), sl("CM", "R", 62, 46),
      sl("W", "R", 85, 50), sl("ST", NA, 50, 78)),
    "4-2-2-2" = rbind(gk, back4,
      sl("DM", "L", 38, 36), sl("DM", "R", 62, 36),
      sl("AM", "L", 30, 58), sl("AM", "R", 70, 58),
      sl("ST", "L", 38, 78), sl("ST", "R", 62, 78)),
    "3-5-1-1" = rbind(gk, back3,
      sl("FB", "L", 8, 45), sl("CM", "L", 30, 42), sl("CM", NA, 50, 38),
      sl("CM", "R", 70, 42), sl("FB", "R", 92, 45),
      sl("AM", NA, 50, 60), sl("ST", NA, 50, 80)),
    "4-5-1" = rbind(gk, back4,
      sl("W", "L", 10, 50), sl("CM", "L", 30, 46), sl("CM", NA, 50, 42),
      sl("CM", "R", 70, 46), sl("W", "R", 90, 50), sl("ST", NA, 50, 80)),
    "4-3-2-1" = rbind(gk, back4,
      sl("CM", "L", 30, 42), sl("CM", NA, 50, 38), sl("CM", "R", 70, 42),
      sl("AM", "L", 35, 60), sl("AM", "R", 65, 60), sl("ST", NA, 50, 80)),
    "4-1-3-2" = rbind(gk, back4,
      sl("DM", NA, 50, 32),
      sl("CM", "L", 28, 50), sl("CM", NA, 50, 52), sl("CM", "R", 72, 50),
      sl("ST", "L", 38, 76), sl("ST", "R", 62, 76)),
    "3-2-4-1" = rbind(gk, back3,
      sl("DM", "L", 38, 32), sl("DM", "R", 62, 32),
      sl("FB", "L", 10, 55), sl("AM", "L", 35, 58), sl("AM", "R", 65, 58),
      sl("FB", "R", 90, 55), sl("ST", NA, 50, 80)),
    "3-3-1-3" = rbind(gk, back3,
      sl("CM", "L", 25, 38), sl("CM", NA, 50, 35), sl("CM", "R", 75, 38),
      sl("AM", NA, 50, 54), sl("W", "L", 18, 68), sl("W", "R", 82, 68),
      sl("ST", NA, 50, 82)),
    "3-3-3-1" = rbind(gk, back3,
      sl("FB", "L", 12, 36), sl("DM", NA, 50, 35), sl("FB", "R", 88, 36),
      sl("AM", "L", 30, 58), sl("AM", NA, 50, 60), sl("AM", "R", 70, 58),
      sl("ST", NA, 50, 80)),
    "4-2-4" = rbind(gk, back4,
      sl("CM", "L", 38, 42), sl("CM", "R", 62, 42),
      sl("W", "L", 12, 64), sl("W", "R", 88, 64),
      sl("ST", "L", 38, 78), sl("ST", "R", 62, 78))
  )
})

# Exports the team-builder data: the selectable player pool, the coach
# similarity pool (raw profile vectors — the frontend computes cosine
# similarity against user-built XIs), and the shared metadata (formations
# with pitch coordinates, eligibility matrices, thresholds). Skipped with a
# message when recommender.rds predates the builder component.
se_export_builder <- function(d) {
  b <- d$rec$builder
  if (is.null(b)) {
    cat("builder: recommender.rds has no builder component — skipped\n")
    return(invisible())
  }
  season <- d$rec$meta$season

  # gate: every layout must exist and agree with the model's slot counts
  stopifnot(setequal(names(se_formation_layouts), names(b$formation_slots)))
  for (f in names(b$formation_slots)) {
    lay <- se_formation_layouts[[f]]
    stopifnot(sum(lay$type == "GK") == 1, nrow(lay) == 11)
    counts <- table(factor(lay$type[lay$type != "GK"],
                           levels = colnames(b$archetype_slot_matrix)))
    stopifnot(all(counts[names(b$formation_slots[[f]])] ==
                    b$formation_slots[[f]]))
  }

  # --- player pool -------------------------------------------------------------
  arch <- readRDS("data/cache/sofascore/archetypes.rds")
  cw <- bind_rows(lapply(
    list.files("data/cache/sofascore", pattern = "^crosswalk_\\d+\\.rds$",
               full.names = TRUE), readRDS)) |>
    filter(!is.na(player_id)) |>
    select(season_ss_id, player_ss_id, player_id)

  leagues <- readRDS("data/cache/leagues.rds")
  teams   <- readRDS("data/cache/teams.rds")
  players <- readRDS("data/cache/players.rds")
  big5_ls <- leagues |>
    filter(grepl("wettbewerb/(GB1|ES1|IT1|L1|FR1)/", league_season_id),
           season_start_year %in% 2015:2024) |>
    mutate(slug = case_when(
      grepl("GB1", league_season_id) ~ "premier-league",
      grepl("ES1", league_season_id) ~ "laliga",
      grepl("IT1", league_season_id) ~ "serie-a",
      grepl("L1",  league_season_id) ~ "bundesliga",
      TRUE                           ~ "ligue-1"
    ))
  big5_players <- players |>
    inner_join(teams |>
                 inner_join(big5_ls |> select(league_season_id,
                                              season_start_year, slug),
                            by = "league_season_id") |>
                 select(team_season_id, team_name, season_start_year, slug),
               by = "team_season_id") |>
    mutate(club_num = se_club_num(gsub("/saison_id/\\d+$", "", team_season_id)))

  outfield <- arch |>
    select(season_ss_id, player_ss_id, season_start_year, archetype) |>
    inner_join(cw, by = c("season_ss_id", "player_ss_id")) |>
    inner_join(big5_players |>
                 select(player_id, season_start_year, player_name, slug,
                        team_name, club_num, player_position, minutes_played,
                        player_market_value_euro),
               by = c("player_id", "season_start_year"),
               relationship = "many-to-many") |>
    group_by(season_ss_id, player_ss_id) |>
    slice_max(minutes_played, n = 1, with_ties = FALSE) |>
    ungroup()

  gks <- big5_players |>
    filter(player_position == "Goalkeeper", minutes_played >= 600) |>
    mutate(archetype = NA_character_)

  pool <- bind_rows(
    outfield |> select(player_id, player_name, season_start_year, slug,
                       team_name, club_num, player_position,
                       player_market_value_euro, archetype),
    gks |> select(player_id, player_name, season_start_year, slug,
                  team_name, club_num, player_position,
                  player_market_value_euro, archetype)
  ) |>
    arrange(player_id, desc(season_start_year))

  img_ok <- d$player_imgs |> filter(!is.na(local_path))
  photo_map <- setNames(paste0("assets/players/", basename(img_ok$local_path)),
                        img_ok$player_id)

  by_player <- split(pool, pool$player_id)
  players_out <- lapply(by_player, function(g) {
    list(
      id     = as.integer(str_extract(g$player_id[1], "(?<=/spieler/)\\d+")),
      name   = g$player_name[1],
      photo  = if (g$player_id[1] %in% names(photo_map))
                 unname(photo_map[g$player_id[1]]) else NULL,
      seasons = lapply(seq_len(nrow(g)), function(i) list(
        y    = g$season_start_year[i],
        lg   = g$slug[i],
        club = g$team_name[i],
        club_id = as.integer(g$club_num[i]),
        v    = if (is.na(g$player_market_value_euro[i])) NULL
               else g$player_market_value_euro[i],
        pos  = g$player_position[i],
        arch = if (is.na(g$archetype[i])) NULL else g$archetype[i]
      ))
    )
  })
  se_write_json(unname(players_out),
                file.path(se_site_dir, "data/builder/players.json"))
  cat("builder players:", length(players_out), "(",
      nrow(pool), "season rows )\n")

  # --- coach pool --------------------------------------------------------------
  share_cols <- grep("^share_", names(b$pool), value = TRUE)
  coaches_out <- lapply(seq_len(nrow(b$pool)), function(i) {
    p <- b$pool[i, ]
    f <- d$rec$facts_by_coach[[p$coach_id]]
    rating <- se_rating(d, p$coach_id)
    nat <- if (!is.null(f) && !is.na(f$nationality)) {
      strsplit(f$nationality, ", ")[[1]][1]
    } else NULL
    profile <- as.list(setNames(se_num(as.numeric(p[share_cols]), 4),
                                sub("^share_", "", share_cols)))
    list(
      id            = as.integer(se_coach_num(p$coach_id)),
      name          = p$coach_name,
      img           = unname(d$img_map[p$coach_id]),
      profile       = profile,
      blup          = if (is.null(rating)) NULL else rating$blup,
      grade         = if (is.null(rating)) NULL else list(
                        letter = rating$letter_grade,
                        cut_label = rating$cut_label),
      n_stints      = p$n_stints_b5,
      mean_residual = se_num(p$mean_res_b5, 3),
      leagues       = I(if (is.null(f)) character(0) else f$leagues[[1]]),
      countries     = I(if (is.null(f)) character(0) else f$countries[[1]]),
      big5          = !is.null(f) && f$big5_games >= 30,
      club_level    = if (is.null(f)) NULL else se_num(f$club_level, 1),
      last_season   = if (is.null(f)) NULL else f$last_season,
      nationality   = nat
    )
  })
  se_write_json(coaches_out,
                file.path(se_site_dir, "data/builder/coaches.json"))
  cat("builder coaches:", length(coaches_out), "\n")

  # --- meta ----------------------------------------------------------------------
  # XI-value distributions (sum of each club's 11 highest player values,
  # latest season): the frontend ranks the built XI against these for the
  # similar-level chip
  xi_vals <- big5_players |>
    filter(season_start_year == season, !is.na(player_market_value_euro)) |>
    group_by(slug, team_season_id) |>
    slice_max(player_market_value_euro, n = 11, with_ties = FALSE) |>
    summarize(xi_value = sum(player_market_value_euro), .groups = "drop")
  xi_dist <- c(
    lapply(split(xi_vals$xi_value, xi_vals$slug), function(v) sort(v)),
    list(big5 = sort(xi_vals$xi_value))
  )

  formations_out <- lapply(names(b$formation_slots), function(f) {
    lay <- se_formation_layouts[[f]]
    list(
      name   = f,
      family = paste0(if (sum(lay$type == "CB") >= 3) "back3" else "back4",
                      "_", sum(lay$type == "ST"), "st"),
      slots  = lapply(seq_len(nrow(lay)), function(i) list(
        type = lay$type[i],
        side = if (is.na(lay$side[i])) NULL else lay$side[i],
        x    = lay$x[i],
        y    = lay$y[i]
      ))
    )
  })

  elig <- apply(b$archetype_slot_matrix, 1, as.list, simplify = FALSE)
  tm_slots <- lapply(b$tm_position_slots, function(v) as.list(se_num(v, 3)))

  meta <- list(
    season          = season,
    season_label    = se_season_label(season),
    formations      = formations_out,
    slot_types      = I(colnames(b$archetype_slot_matrix)),
    eligibility     = elig,
    tm_position_eligibility = tm_slots,
    archetype_labels = as.list(b$archetype_labels),
    eligibility_floor = 0.25,   # picker cutoff (Natural 1.0 / Capable .5 / Stretch .25)
    sim_quality_blend = c(0.85, 0.15),   # same tilt as team pages
    level_band      = 10,
    active_since    = season - 1,
    xi_values       = lapply(xi_dist, function(v) I(round(v / 1e6, 1)))
  )
  se_write_json(meta, file.path(se_site_dir, "data/builder/meta.json"))

  # --- photos ----------------------------------------------------------------------
  player_dir <- file.path(se_site_dir, "assets/players")
  dir.create(player_dir, recursive = TRUE, showWarnings = FALSE)
  used <- img_ok |> filter(player_id %in% pool$player_id)
  n <- if (nrow(used)) sum(file.copy(used$local_path, player_dir,
                                     overwrite = TRUE)) else 0
  cat("builder assets:", n, "player photos copied\n")
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
  # stint/game/club counts in a cut's grades cover only that cut's stints; the
  # leaderboard shows full-career totals (same definition as the coach pages'
  # career header) so the two never disagree for coaches with stints in both
  # cuts (e.g. a La Liga + LaLiga 2 career)
  career <- d$cr |>
    group_by(coach_id) |>
    summarise(career_stints = n(),
              career_games  = sum(n_games),
              career_clubs  = n_distinct(club_num),
              .groups = "drop")
  se_lb_cut <- function(grades, ranked, cut_label) {
    lb <- grades |>
      left_join(ranked |> select(coach_id, mean_residual, ci_lower, ci_upper,
                                 significant),
                by = "coach_id") |>
      left_join(career, by = "coach_id") |>
      mutate(coach_num = se_coach_num(coach_id))
    stopifnot(!anyNA(lb$career_stints))
    coaches <- lapply(seq_len(nrow(lb)), function(i) {
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
    list(cut_label = cut_label, coaches = coaches)
  }
  # both grading cuts ship; the home page toggles between them (grades from the
  # two cuts sit on separate curves, so each block carries its own cut_label)
  se_write_json(list(top5  = se_lb_cut(d$grades5,  d$ranked5,  "Top-5 leagues"),
                     all14 = se_lb_cut(d$grades14, d$ranked14, "All leagues")),
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
  se_export_builder(d)
  se_copy_assets(d)
  se_export_writeup()
  cat("\nSITE EXPORT COMPLETE ->", normalizePath(se_site_dir, mustWork = FALSE), "\n")
  invisible(d)
}
