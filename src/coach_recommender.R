# coach_recommender.R
#
# The coach recommender (Docs/Coach_Recommender_Design.md): given a team's
# squad, rank candidate coaches by predicted performance — coach quality (M5
# BLUPs) + shrunken archetype-fit slopes + a formation-based deployed-value
# forecast — with career-fact plausibility filters and a descriptive
# similarity layer.
#
# Functions use the cr_ prefix. Pure cache/results reader: no scraping, no
# chromote. Sources the coach_fit.R chain (which pulls in coach_attribution.R
# -> residual_analysis.R -> model_comparison.R -> tabler.R); source
# source_data.r first, as usual.
#
# Decisions fixed at Phase 0 (2026-07-13, from the sizing checks):
#   - 22 distinct formation strings cover all 36,022 team-matches; slots are
#     hand-mapped per string (no lossy family grouping for the best-XI step).
#   - Formation families (used for recency-decay selection and rigidity only)
#     are the 2x2 of back line (4 vs 3/5) x strikers (1 vs 2).
#   - Composite fit axes (revised once pre-fit, as the design allows: the
#     planned destroyer and build-up axes correlated at -0.868 — near mirror
#     images of the same spine choice — so they merged into one bipolar axis):
#     A1 creators (F3+M4), A2 spine (D2+M2 minus M1+D1), A3 wing-back (M3).
#     Max |r| between the revised axes: 0.47.

source("coach_fit.R")

# =============================================================================
# 1. Formation data
# =============================================================================

# slot counts per formation string, hand-mapped from the 22 strings observed
# across all 50 big-5 league-seasons (Phase 0). Slot types:
#   CB centre-back | FB fullback/wing-back | DM holding mid | CM central mid |
#   AM attacking mid | W winger/wide forward | ST striker
# Every vector sums to 10 (outfield); the GK slot is implicit.
cr_formation_slots <- list(
  "4-2-3-1" = c(CB = 2, FB = 2, DM = 2, CM = 0, AM = 1, W = 2, ST = 1),
  "4-3-3"   = c(CB = 2, FB = 2, DM = 0, CM = 3, AM = 0, W = 2, ST = 1),
  "4-4-2"   = c(CB = 2, FB = 2, DM = 0, CM = 2, AM = 0, W = 2, ST = 2),
  "3-4-2-1" = c(CB = 3, FB = 2, DM = 0, CM = 2, AM = 2, W = 0, ST = 1),
  "3-5-2"   = c(CB = 3, FB = 2, DM = 0, CM = 3, AM = 0, W = 0, ST = 2),
  "4-1-4-1" = c(CB = 2, FB = 2, DM = 1, CM = 2, AM = 0, W = 2, ST = 1),
  "4-3-1-2" = c(CB = 2, FB = 2, DM = 0, CM = 3, AM = 1, W = 0, ST = 2),
  "3-4-1-2" = c(CB = 3, FB = 2, DM = 0, CM = 2, AM = 1, W = 0, ST = 2),
  "3-4-3"   = c(CB = 3, FB = 2, DM = 0, CM = 2, AM = 0, W = 2, ST = 1),
  "4-4-1-1" = c(CB = 2, FB = 2, DM = 0, CM = 2, AM = 1, W = 2, ST = 1),
  "5-3-2"   = c(CB = 3, FB = 2, DM = 0, CM = 3, AM = 0, W = 0, ST = 2),
  "3-1-4-2" = c(CB = 3, FB = 2, DM = 1, CM = 2, AM = 0, W = 0, ST = 2),
  "5-4-1"   = c(CB = 3, FB = 2, DM = 0, CM = 2, AM = 0, W = 2, ST = 1),
  "4-2-2-2" = c(CB = 2, FB = 2, DM = 2, CM = 0, AM = 2, W = 0, ST = 2),
  "3-5-1-1" = c(CB = 3, FB = 2, DM = 0, CM = 3, AM = 1, W = 0, ST = 1),
  "4-5-1"   = c(CB = 2, FB = 2, DM = 0, CM = 3, AM = 0, W = 2, ST = 1),
  "4-3-2-1" = c(CB = 2, FB = 2, DM = 0, CM = 3, AM = 2, W = 0, ST = 1),
  "4-1-3-2" = c(CB = 2, FB = 2, DM = 1, CM = 3, AM = 0, W = 0, ST = 2),
  "3-2-4-1" = c(CB = 3, FB = 2, DM = 2, CM = 0, AM = 2, W = 0, ST = 1),
  "3-3-1-3" = c(CB = 3, FB = 0, DM = 0, CM = 3, AM = 1, W = 2, ST = 1),
  "3-3-3-1" = c(CB = 3, FB = 2, DM = 1, CM = 0, AM = 3, W = 0, ST = 1),
  "4-2-4"   = c(CB = 2, FB = 2, DM = 0, CM = 2, AM = 0, W = 2, ST = 2)
)

# family = back line x striker count, for recency-decay selection and rigidity
# (the best-XI step always uses exact strings)
cr_formation_family <- function(formation) {
  slots <- cr_formation_slots[formation]
  vapply(slots, function(s) {
    if (is.null(s)) return(NA_character_)
    paste0(if (s[["CB"]] >= 3) "back3" else "back4",
           "_", s[["ST"]], "st")
  }, character(1))
}

# (event, team, formation) rows for one league-season, playoff-filtered the
# same way as cf_season_match_minutes()
cr_season_formations <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  events <- pa_read("events", sid) |> filter(status_type == "finished")
  appearances <- table(c(events$home_team_ss_id, events$away_team_ss_id))
  league_team_ids <- as.numeric(names(appearances[appearances >= 10]))
  events <- events |>
    filter(home_team_ss_id %in% league_team_ids,
           away_team_ss_id %in% league_team_ids)
  pa_read("formations", sid) |>
    inner_join(events |> select(event_ss_id, home_team_ss_id, away_team_ss_id),
               by = "event_ss_id") |>
    mutate(team_ss_id = ifelse(is_home, home_team_ss_id, away_team_ss_id),
           league = league_key, season_start_year = year) |>
    select(event_ss_id, team_ss_id, formation, league, season_start_year)
}

# per-(event, team) coach attribution for one league-season — the events/
# coaches part of cf_season_match_minutes() without the (large) match_stats
# read, for callers that only need formations or match dates
cr_season_match_coaches <- function(league_key, year) {
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(year)]]
  league_season_id <- xx_league_season_id(cf_tm_league_ids()[[league_key]], year)

  events <- pa_read("events", sid) |>
    filter(status_type == "finished") |>
    mutate(match_date = as.Date(as.POSIXct(start_timestamp,
                                           origin = "1970-01-01",
                                           tz = "Europe/London")))
  appearances <- table(c(events$home_team_ss_id, events$away_team_ss_id))
  league_team_ids <- as.numeric(names(appearances[appearances >= 10]))
  events <- events |>
    filter(home_team_ss_id %in% league_team_ids,
           away_team_ss_id %in% league_team_ids)

  ss_team_names <- events |>
    transmute(team_ss_id = home_team_ss_id, team_name = home_team_name) |>
    bind_rows(events |>
                transmute(team_ss_id = away_team_ss_id,
                          team_name = away_team_name)) |>
    count(team_ss_id, team_name) |>
    group_by(team_ss_id) |>
    slice_max(n, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(team_ss_id, team_name)
  tm_teams <- xx_data_cache$teams |>
    filter(league_season_id == !!league_season_id)
  team_map <- ss_crosswalk_team_map(ss_team_names$team_name, tm_teams) |>
    bind_cols(ss_team_names |> select(team_ss_id))
  if (any(is.na(team_map$team_season_id))) {
    stop(league_key, " ", year, ": unmapped league team(s): ",
         paste(team_map$team_name_ss[is.na(team_map$team_season_id)],
               collapse = ", "))
  }

  team_matches <- events |>
    select(event_ss_id, match_date, home_team_ss_id, away_team_ss_id) |>
    pivot_longer(c(home_team_ss_id, away_team_ss_id), values_to = "team_ss_id") |>
    left_join(team_map |> select(team_ss_id, team_season_id), by = "team_ss_id") |>
    select(event_ss_id, match_date, team_ss_id, team_season_id)

  team_matches |>
    group_by(team_season_id) |>
    group_modify(function(g, key) {
      xx_assign_matches_to_coaches(
        g |> mutate(match_id = event_ss_id),
        xx_data_cache$coaches |> filter(team_season_id == key$team_season_id)
      ) |> select(event_ss_id, match_date, team_ss_id, coach_id)
    }) |>
    ungroup() |>
    mutate(league = league_key, season_start_year = year)
}

# every team-match with its formation and the coach in charge, all leagues and
# seasons. Slow (~2-3 min: coach attribution per league-season); cache the
# result when iterating.
cr_build_coach_formations <- function() {
  bind_rows(lapply(names(ss_big5_leagues), function(lg) {
    bind_rows(lapply(as.integer(names(ss_big5_leagues[[lg]]$seasons)),
                     function(yr) {
      cr_season_match_coaches(lg, yr) |>
        inner_join(cr_season_formations(lg, yr),
                   by = c("event_ss_id", "team_ss_id", "league",
                          "season_start_year"))
    }))
  })) |>
    filter(!is.na(coach_id)) |>
    mutate(family = cr_formation_family(formation))
}

# =============================================================================
# 2. Formation profiles: recency decay, rigidity
# =============================================================================

# recency-weighted formation distribution for one coach as of a given season:
# matches from season s get weight delta^(as_of - s); as_of-season matches are
# excluded (the profile must be knowable before the season starts).
# Returns a named share vector over `key` ("formation" or "family").
cr_formation_profile <- function(coach_matches, as_of_season, delta,
                                 key = "formation") {
  h <- coach_matches |> filter(season_start_year < as_of_season)
  if (nrow(h) == 0) return(NULL)
  w <- delta^(as_of_season - h$season_start_year)
  shares <- tapply(w, h[[key]], sum)
  shares / sum(shares)
}

# Selects the recency decay delta out-of-sample: for every coach move (first
# season at a new club with at least `min_games` matches there and any prior
# history), predict the family distribution he will play at the new club from
# his history, and score it against the realized distribution by total
# variation distance. Lower mean TV = better delta. delta = 1 is the uniform
# career-wide special case.
cr_select_delta <- function(coach_formations,
                            deltas = c(0.3, 0.5, 0.7, 0.85, 1.0),
                            min_games = 10) {
  cf <- coach_formations |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))

  # first season at each (coach, club): the arrival observations
  arrivals <- cf |>
    group_by(coach_id, club_id) |>
    summarize(arrival_season = min(season_start_year), .groups = "drop") |>
    inner_join(cf, by = c("coach_id", "club_id"),
               relationship = "one-to-many") |>
    filter(season_start_year == arrival_season) |>
    group_by(coach_id, club_id, arrival_season) |>
    summarize(n_matches = n(), .groups = "drop") |>
    filter(n_matches >= min_games)

  by_coach <- split(cf, cf$coach_id)

  scores <- sapply(deltas, function(delta) {
    tvs <- unlist(lapply(seq_len(nrow(arrivals)), function(i) {
      a <- arrivals[i, ]
      cm <- by_coach[[a$coach_id]]
      # history strictly before arrival AND not at the new club (predicting a
      # coach's shape at a club he already coached is not a move)
      hist_m <- cm |> filter(club_id != a$club_id)
      pred <- cr_formation_profile(hist_m, a$arrival_season, delta,
                                   key = "family")
      if (is.null(pred)) return(NULL)
      realized <- cm |>
        filter(club_id == a$club_id, season_start_year == a$arrival_season)
      real_shares <- table(realized$family) / nrow(realized)
      fams <- union(names(pred), names(real_shares))
      p <- setNames(rep(0, length(fams)), fams); p[names(pred)] <- pred
      q <- setNames(rep(0, length(fams)), fams); q[names(real_shares)] <- real_shares
      sum(abs(p - q)) / 2
    }))
    mean(tvs)
  })

  out <- data.frame(delta = deltas, mean_tv = scores)
  cat("=== recency delta selection (lower TV better) ===\n")
  print(out, row.names = FALSE)
  best <- out$delta[which.min(out$mean_tv)]
  cat("chosen delta:", best, "\n")
  invisible(list(table = out, delta = best))
}

# Rigidity in [0, 1] per coach: how much his formation choice is a fixed trait
# vs squad-adaptive.
#   - entropy component: 1 - H/Hmax of the delta-weighted family distribution
#     over his full history (Hmax = log of families he could have used, i.e.
#     the 4 families)
#   - persistence component (coaches with >= 2 clubs): 1 - mean pairwise total
#     variation distance between his per-club family distributions
# r = mean of the available components. One-club coaches get entropy only.
cr_rigidity <- function(coach_formations, delta) {
  cf <- coach_formations |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))
  n_fam <- length(unique(cf$family))

  cf |>
    group_by(coach_id) |>
    group_modify(function(g, key) {
      last_season <- max(g$season_start_year)
      w <- delta^(last_season - g$season_start_year)
      shares <- tapply(w, g$family, sum)
      shares <- shares / sum(shares)
      H <- -sum(shares * log(shares))
      entropy_rigidity <- 1 - H / log(n_fam)

      clubs <- split(g$family, g$club_id)
      clubs <- clubs[vapply(clubs, length, integer(1)) >= 10]
      persistence <- NA_real_
      if (length(clubs) >= 2) {
        dists <- lapply(clubs, function(f) table(factor(f, levels = sort(unique(cf$family)))) / length(f))
        pairs <- combn(length(dists), 2)
        tv <- apply(pairs, 2, function(p) sum(abs(dists[[p[1]]] - dists[[p[2]]])) / 2)
        persistence <- 1 - mean(tv)
      }

      data.frame(
        n_matches = nrow(g),
        entropy_rigidity = entropy_rigidity,
        persistence = persistence,
        rigidity = mean(c(entropy_rigidity, persistence), na.rm = TRUE)
      )
    }) |>
    ungroup()
}

# =============================================================================
# 3. Slot eligibility and the deployed-value forecast
# =============================================================================

# archetype -> slot eligibility factors (soft penalties, not binary):
# 1.0 = the archetype's home slot; fractions = playable at a value discount.
# Grounded in the archetype definitions (player_archetypes.R labels) and the
# mechanical validation (cr_mechanical_validation()); revise there, not here.
cr_slot_types <- c("CB", "FB", "DM", "CM", "AM", "W", "ST")

cr_archetype_slot_matrix <- local({
  m <- matrix(0, nrow = 11, ncol = 7,
              dimnames = list(
                c("D1", "D2", "D3", "D4", "M1", "M2", "M3", "M4",
                  "F1", "F2", "F3"),
                cr_slot_types))
  m["D1", ] <- c(CB = 1.0, FB = 0.35, DM = 0.30, CM = 0,    AM = 0,    W = 0,    ST = 0)
  m["D2", ] <- c(CB = 1.0, FB = 0.40, DM = 0.50, CM = 0.30, AM = 0,    W = 0,    ST = 0)
  m["D3", ] <- c(CB = 0.50, FB = 1.0, DM = 0.30, CM = 0.25, AM = 0,    W = 0.25, ST = 0)
  m["D4", ] <- c(CB = 0.25, FB = 1.0, DM = 0,    CM = 0.30, AM = 0.25, W = 0.60, ST = 0)
  m["M1", ] <- c(CB = 0.35, FB = 0.30, DM = 1.0, CM = 0.90, AM = 0.25, W = 0,    ST = 0)
  m["M2", ] <- c(CB = 0.25, FB = 0,    DM = 1.0, CM = 1.0,  AM = 0.50, W = 0.25, ST = 0)
  m["M3", ] <- c(CB = 0,    FB = 1.0,  DM = 0.25, CM = 0.40, AM = 0.30, W = 0.60, ST = 0)
  m["M4", ] <- c(CB = 0,    FB = 0.25, DM = 0.30, CM = 0.80, AM = 1.0,  W = 0.80, ST = 0.30)
  m["F1", ] <- c(CB = 0,    FB = 0,    DM = 0,    CM = 0.25, AM = 0.60, W = 0.80, ST = 1.0)
  m["F2", ] <- c(CB = 0,    FB = 0,    DM = 0,    CM = 0,    AM = 0.30, W = 0.35, ST = 1.0)
  m["F3", ] <- c(CB = 0,    FB = 0.25, DM = 0,    CM = 0.30, AM = 0.80, W = 1.0,  ST = 0.60)
  m
})

# TM position -> slot eligibility, used for players without an archetype
# (never met the 600-minute bar, new to the big 5, or pre-2015 squads). The
# 0.9 ceiling is the information discount vs a real archetype.
cr_tm_position_slot <- function(position) {
  base <- list(
    "Goalkeeper"          = c(0, 0, 0, 0, 0, 0, 0),
    "Centre-Back"         = c(CB = 1, FB = 0.35, DM = 0.3, CM = 0, AM = 0, W = 0, ST = 0),
    "Left-Back"           = c(CB = 0.35, FB = 1, DM = 0, CM = 0.25, AM = 0, W = 0.5, ST = 0),
    "Right-Back"          = c(CB = 0.35, FB = 1, DM = 0, CM = 0.25, AM = 0, W = 0.5, ST = 0),
    "Defensive Midfield"  = c(CB = 0.3, FB = 0.25, DM = 1, CM = 0.9, AM = 0.3, W = 0, ST = 0),
    "Central Midfield"    = c(CB = 0, FB = 0.25, DM = 0.8, CM = 1, AM = 0.7, W = 0.3, ST = 0),
    "Attacking Midfield"  = c(CB = 0, FB = 0, DM = 0.25, CM = 0.7, AM = 1, W = 0.7, ST = 0.3),
    "Left Midfield"       = c(CB = 0, FB = 0.5, DM = 0, CM = 0.6, AM = 0.6, W = 1, ST = 0.25),
    "Right Midfield"      = c(CB = 0, FB = 0.5, DM = 0, CM = 0.6, AM = 0.6, W = 1, ST = 0.25),
    "Left Winger"         = c(CB = 0, FB = 0.3, DM = 0, CM = 0.25, AM = 0.7, W = 1, ST = 0.5),
    "Right Winger"        = c(CB = 0, FB = 0.3, DM = 0, CM = 0.25, AM = 0.7, W = 1, ST = 0.5),
    "Second Striker"      = c(CB = 0, FB = 0, DM = 0, CM = 0.25, AM = 0.8, W = 0.6, ST = 1),
    "Centre-Forward"      = c(CB = 0, FB = 0, DM = 0, CM = 0, AM = 0.3, W = 0.4, ST = 1),
    # generic buckets TM sometimes uses
    "Defender"            = c(CB = 0.8, FB = 0.8, DM = 0.25, CM = 0, AM = 0, W = 0, ST = 0),
    "midfield"            = c(CB = 0, FB = 0.25, DM = 0.7, CM = 0.8, AM = 0.7, W = 0.4, ST = 0),
    "Midfielder"          = c(CB = 0, FB = 0.25, DM = 0.7, CM = 0.8, AM = 0.7, W = 0.4, ST = 0),
    "attack"              = c(CB = 0, FB = 0, DM = 0, CM = 0, AM = 0.5, W = 0.7, ST = 0.8),
    "Attacker"            = c(CB = 0, FB = 0, DM = 0, CM = 0, AM = 0.5, W = 0.7, ST = 0.8)
  )
  v <- base[[position]]
  if (is.null(v)) v <- rep(0.35, 7)   # unknown label: playable anywhere, weakly
  0.9 * setNames(as.numeric(v), cr_slot_types)
}

# Squad table for one team-season, ready for the best-XI assignment:
# one row per player with market value, archetype (lagged, via the SofaScore
# crosswalk) where available, and the 7 slot eligibility factors.
cr_team_squad <- function(team_season_id, league_key, season_start_year,
                          archetypes = NULL) {
  if (is.null(archetypes)) archetypes <- cf_player_archetypes()
  sid <- ss_big5_leagues[[league_key]]$seasons[[as.character(season_start_year)]]
  cw <- readRDS(file.path(pa_cache_dir, paste0("crosswalk_", sid, ".rds")))

  squad <- xx_data_cache$players |>
    filter(team_season_id == !!team_season_id,
           !is.na(player_market_value_euro),
           player_market_value_euro > 0) |>
    select(player_id, player_name, player_position,
           value = player_market_value_euro) |>
    left_join(cw |> select(player_id, player_ss_id) |> distinct(player_id, .keep_all = TRUE),
              by = "player_id") |>
    left_join(archetypes |>
                filter(season_start_year == !!season_start_year) |>
                select(player_ss_id, archetype),
              by = "player_ss_id")

  gk <- squad |> filter(player_position == "Goalkeeper")
  outfield <- squad |> filter(player_position != "Goalkeeper")

  elig <- t(vapply(seq_len(nrow(outfield)), function(i) {
    a <- outfield$archetype[i]
    if (!is.na(a) && a %in% rownames(cr_archetype_slot_matrix)) {
      cr_archetype_slot_matrix[a, ]
    } else {
      cr_tm_position_slot(outfield$player_position[i])
    }
  }, numeric(7)))
  colnames(elig) <- cr_slot_types

  list(
    outfield = bind_cols(outfield, as.data.frame(elig)),
    gk_value = if (nrow(gk)) max(gk$value) else 0
  )
}

# Max-value XI for one formation: assign outfield players to the formation's
# 10 slots to maximize sum(value x eligibility). Greedy seeding + pairwise
# improvement (swap assigned<->assigned and assigned<->bench until no gain);
# exact enough at this scale and dependency-free (design sec. 4.3 note re
# lpSolve).
cr_best_xi_value <- function(squad, formation) {
  slots <- cr_formation_slots[[formation]]
  slot_list <- rep(names(slots), slots)          # length 10
  o <- squad$outfield
  if (nrow(o) < 10) return(NA_real_)
  W <- as.matrix(o[, cr_slot_types]) * o$value   # player x slot value matrix
  Wl <- W[, slot_list, drop = FALSE]             # player x slot-instance

  n <- nrow(Wl); k <- ncol(Wl)
  assigned <- rep(NA_integer_, k)                # slot-instance -> player row
  taken <- rep(FALSE, n)
  Wtmp <- Wl
  for (step in seq_len(k)) {                     # greedy: best cell first
    idx <- arrayInd(which.max(Wtmp), dim(Wtmp))
    p <- idx[1]; s <- idx[2]
    assigned[s] <- p; taken[p] <- TRUE
    Wtmp[p, ] <- -Inf; Wtmp[, s] <- -Inf
  }

  # local improvement
  repeat {
    improved <- FALSE
    # swap two assigned players' slots
    for (s1 in seq_len(k - 1)) for (s2 in seq(s1 + 1, k)) {
      p1 <- assigned[s1]; p2 <- assigned[s2]
      if (Wl[p1, s2] + Wl[p2, s1] > Wl[p1, s1] + Wl[p2, s2] + 1e-9) {
        assigned[s1] <- p2; assigned[s2] <- p1
        improved <- TRUE
      }
    }
    # replace an assigned player with a bench player
    bench <- which(!taken)
    for (s in seq_len(k)) for (b in bench) {
      if (Wl[b, s] > Wl[assigned[s], s] + 1e-9) {
        taken[assigned[s]] <- FALSE
        assigned[s] <- b; taken[b] <- TRUE
        bench <- which(!taken)
        improved <- TRUE
      }
    }
    if (!improved) break
  }

  sum(Wl[cbind(assigned, seq_len(k))]) + squad$gk_value
}

# Best-XI value for every formation string, one team. Returns a named vector.
cr_team_formation_values <- function(squad) {
  vapply(names(cr_formation_slots), function(f) cr_best_xi_value(squad, f),
         numeric(1))
}

# The deployed-value forecast (design sec. 4.2):
#   deployable(C, T) = r x sum_f p(f|C) bestXI(T, f) + (1 - r) x max_f bestXI(T, f)
# profile: named share vector over formation strings (cr_formation_profile);
# fvals: cr_team_formation_values(squad); rigidity in [0, 1].
cr_deployable <- function(fvals, profile, rigidity) {
  vmax <- max(fvals, na.rm = TRUE)
  if (is.null(profile)) return(vmax)   # no history: assume squad's best shape
  common <- intersect(names(profile), names(fvals))
  vprof <- sum(profile[common] * fvals[common]) / sum(profile[common])
  rigidity * vprof + (1 - rigidity) * vmax
}

# Mechanical validation of the eligibility matrix (design sec. 7.2): at every
# coach arrival (first stint at a club, with formation history from elsewhere),
# does a player's fit to the incoming coach's shapes predict his minutes under
# that coach, beyond his market value? For each arrival-stint player:
#   fit      = sum_f p(f | coach history before arrival) x best eligibility
#              across f's slots (competition-free player-level fit)
#   response = minutes under the coach / (games under the coach x 90)
# Gate: the fit coefficient in
#   minutes_share ~ log(value) + fit + (1 | stint)
# must be positive and significant, and the mean within-stint Spearman
# correlation positive. Only then is the formation layer used downstream.
cr_mechanical_validation <- function(minutes_all, coach_formations,
                                     delta = 0.3, min_stint_games = 10,
                                     archetypes = NULL) {
  if (is.null(archetypes)) archetypes <- cf_player_archetypes()

  cfm <- coach_formations |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))
  by_coach <- split(cfm, cfm$coach_id)

  # arrivals: first season of each (coach, club) with >= min_stint_games there
  arrivals <- cfm |>
    group_by(coach_id, club_id) |>
    summarize(arrival_season = min(season_start_year), .groups = "drop")

  stints <- minutes_all |>
    filter(!is.na(coach_id)) |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id)) |>
    inner_join(arrivals, by = c("coach_id", "club_id")) |>
    filter(season_start_year == arrival_season)

  stint_games <- stints |>
    group_by(coach_id, team_season_id, league, season_start_year) |>
    summarize(n_games = n_distinct(event_ss_id), .groups = "drop") |>
    filter(n_games >= min_stint_games)

  # per-formation best slot eligibility for each archetype (and TM fallback),
  # precomputed once
  best_elig_arch <- sapply(names(cr_formation_slots), function(f) {
    slots <- cr_formation_slots[[f]]
    present <- names(slots)[slots > 0]
    apply(cr_archetype_slot_matrix[, present, drop = FALSE], 1, max)
  })   # 11 x 22

  rows <- list()
  for (i in seq_len(nrow(stint_games))) {
    s <- stint_games[i, ]
    cm <- by_coach[[s$coach_id]]
    hist_m <- cm |> filter(club_id != gsub("/saison_id/\\d+$", "", s$team_season_id))
    profile <- cr_formation_profile(hist_m, s$season_start_year, delta,
                                    key = "formation")
    if (is.null(profile)) next
    profile <- profile[names(profile) %in% colnames(best_elig_arch)]
    if (length(profile) == 0) next
    profile <- profile / sum(profile)

    squad <- cr_team_squad(s$team_season_id, s$league, s$season_start_year,
                           archetypes = archetypes)$outfield
    if (nrow(squad) < 10) next

    stint_minutes <- minutes_all |>
      filter(team_season_id == s$team_season_id, coach_id == s$coach_id) |>
      group_by(player_ss_id) |>
      summarize(minutes = sum(minutes), .groups = "drop")

    fit <- vapply(seq_len(nrow(squad)), function(j) {
      a <- squad$archetype[j]
      if (!is.na(a) && a %in% rownames(best_elig_arch)) {
        sum(profile * best_elig_arch[a, names(profile)])
      } else {
        e <- cr_tm_position_slot(squad$player_position[j])
        sum(profile * vapply(names(profile), function(f) {
          slots <- cr_formation_slots[[f]]
          max(e[names(slots)[slots > 0]])
        }, numeric(1)))
      }
    }, numeric(1))

    rows[[i]] <- squad |>
      select(player_ss_id, value, archetype) |>
      mutate(
        fit = fit,
        stint = paste(s$team_season_id, s$coach_id),
        n_games = s$n_games
      ) |>
      left_join(stint_minutes, by = "player_ss_id") |>
      mutate(minutes_share = coalesce(minutes, 0) / (s$n_games * 90))
  }
  d <- bind_rows(rows)

  cat("arrival stints scored:", n_distinct(d$stint),
      "| player rows:", nrow(d), "\n")

  # within-stint Spearman between fit and minutes share
  sp <- d |>
    group_by(stint) |>
    filter(sd(fit) > 0, sd(minutes_share) > 0) |>
    summarize(rho = cor(fit, minutes_share, method = "spearman"),
              .groups = "drop")
  cat(sprintf("mean within-stint Spearman(fit, minutes share): %.3f (%d stints, %.0f%% positive)\n",
              mean(sp$rho), nrow(sp), 100 * mean(sp$rho > 0)))

  m <- lmer(minutes_share ~ log(value) + fit + (1 | stint), data = d,
            control = lmerControl(optimizer = "bobyqa"))
  co <- summary(m)$coefficients
  cat("mixed model minutes_share ~ log(value) + fit + (1|stint):\n")
  print(round(co, 4))
  t_fit <- co["fit", "t value"]
  cat(sprintf("GATE %s: fit t = %.2f (needs > 2 with positive sign)\n",
              if (t_fit > 2) "PASSED" else "FAILED", t_fit))

  invisible(list(data = d, spearman = sp, model = m, t_fit = t_fit))
}

# =============================================================================
# 4. Composite axes and the random-slope fit model
# =============================================================================

# Fixed at Phase 0 (design sec. 3.1). Input: a stint composition table with
# share_* columns; adds A1..A4.
cr_add_axes <- function(tbl) {
  tbl |>
    mutate(
      A1_creators = share_F3 + share_M4,
      A2_spine    = (share_D2 + share_M2) - (share_M1 + share_D1),
      A3_wingback = share_M3
    )
}

cr_axis_cols <- c("A1_creators", "A2_spine", "A3_wingback")

# Random-slope model (design sec. 3.2): the M6 global model plus uncorrelated
# coach slopes on the three axes. Centering the axes keeps the coach intercept
# interpretable as quality-at-average-composition. Reports the LRT of the
# slopes against the intercept-only model. If it fails to converge, drop axes
# from the random part in reverse order of global signal (A3 first).
cr_fit_model <- function(tbl, reference = "share_M1") {
  tbl <- cr_add_axes(tbl) |>
    mutate(across(all_of(cr_axis_cols), \(x) x - mean(x), .names = "{.col}_c"))
  cols <- setdiff(cf_share_cols(tbl), reference)
  fixed <- paste(c(cols, "fallback_share"), collapse = " + ")
  ctrl <- lmerControl(optimizer = "bobyqa")

  fit_with_axes <- function(axes) {
    slope_part <- if (length(axes) == 0) "(1 | coach_id)" else
      sprintf("(1 + %s || coach_id)", paste(paste0(axes, "_c"), collapse = " + "))
    formula_str <- paste("partial_residual_ppg ~", fixed, "+", slope_part,
                         "+ (1 | club_id)")
    suppressWarnings(
      lmer(as.formula(formula_str), data = tbl, weights = n_games,
           REML = FALSE, control = ctrl)
    )
  }

  axes_use <- cr_axis_cols
  full <- NULL
  while (length(axes_use) >= 0) {
    m <- fit_with_axes(axes_use)
    conv <- m@optinfo$conv$lme4
    singular_ok <- TRUE  # singular fits are expected (some slope SDs -> 0)
    if (is.null(conv$messages) ||
        !any(grepl("failed to converge", conv$messages))) {
      full <- m
      break
    }
    if (length(axes_use) == 0) { full <- m; break }
    cat("convergence failure with axes:", paste(axes_use, collapse = ", "),
        "- dropping", tail(axes_use, 1), "\n")
    axes_use <- head(axes_use, -1)
  }

  null <- fit_with_axes(character(0))
  lrt <- anova(null, full)

  cat("=== Random-slope fit model ===\n")
  cat("random-slope axes:", if (length(axes_use)) paste(axes_use, collapse = ", ") else "none", "\n")
  cat(sprintf("LRT (slopes vs intercept-only): Chi-sq = %.3f  df = %d  p = %.4f\n",
              lrt$Chisq[2], lrt$Df[2], lrt$`Pr(>Chisq)`[2]))
  print(VarCorr(full))

  invisible(list(full = full, null = null, lrt = lrt, axes = axes_use,
                 axis_means = colMeans(cr_add_axes(tbl)[cr_axis_cols])))
}

# =============================================================================
# 5. The scorer
# =============================================================================

# Recovers the published enhanced_fixed coefficients exactly from the saved
# residuals table (predicted_ppg is a deterministic function of the model
# inputs, so the regression reproduces the coefficients to machine precision;
# R^2 = 1 is asserted).
cr_value_model_coefs <- function() {
  res <- readRDS("data/results/residuals_14league.rds") |>
    filter(!is.na(predicted_ppg), norm_weighted_value > 0) |>
    mutate(is_b_team = grepl(" B$|Castilla|Bilbao Athletic|Mestalla|Fabril|Sevilla Atlético",
                             team_name))
  m <- lm(predicted_ppg ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
          data = res)
  stopifnot(summary(m)$r.squared > 0.999999)
  coef(m)
}

# Assembles every input the recommender needs to score teams, as of the
# season after `as_of` (default: profiles/rigidity use history through 2024
# to advise a 2025/26 appointment — which makes 2024/25 archetypes
# legitimately lagged for the target squad).
#
# Heavy inputs (composition table, coach_formations, fit model) can be passed
# in when iterating; anything omitted is rebuilt.
cr_build_scorer <- function(composition = NULL, coach_formations = NULL,
                            fit = NULL, tbl = NULL, delta = 0.3,
                            as_of = 2025) {
  if (is.null(coach_formations)) coach_formations <- cr_build_coach_formations()
  if (is.null(composition)) composition <- cf_stint_composition()
  if (is.null(tbl)) {
    tbl <- cf_build_analysis_table(
      composition,
      coach_residuals = readRDS("data/results/coach_residuals_14league.rds"))
  }
  if (is.null(fit)) fit <- cr_fit_model(tbl)

  rigidity <- cr_rigidity(coach_formations, delta)
  by_coach <- split(coach_formations, coach_formations$coach_id)
  profiles <- lapply(by_coach, cr_formation_profile, as_of_season = as_of,
                     delta = delta, key = "formation")

  # league-average reference profile per league (same recency machinery)
  league_profiles <- lapply(split(coach_formations, coach_formations$league),
                            cr_formation_profile, as_of_season = as_of,
                            delta = delta, key = "formation")
  mean_rigidity <- mean(rigidity$rigidity)

  # slope BLUPs with conditional SDs. With the `||` syntax lme4 fits the same
  # grouping factor in several terms; ranef() merges the columns but returns
  # postVar as a list of per-term arrays (in column order).
  re <- lme4::ranef(fit$full, condVar = TRUE)$coach_id
  pv <- attr(re, "postVar")
  block_vars <- function(a) {          # k x k x n array -> n x k variances
    vapply(seq_len(dim(a)[1]), function(r) a[r, r, ], numeric(dim(a)[3]))
  }
  slope_vars <- if (is.list(pv)) {
    do.call(cbind, lapply(pv, block_vars))
  } else {
    block_vars(pv)
  }
  stopifnot(ncol(slope_vars) == ncol(re))
  colnames(slope_vars) <- paste0("var_", colnames(re))
  slopes <- bind_cols(data.frame(coach_id = rownames(re), re,
                                 check.names = FALSE),
                      as.data.frame(slope_vars))

  # quality BLUPs, both cuts, with the published variance components for the
  # approximate posterior SD: var_post = (1/var_coach + n/var_resid)^-1
  q <- lapply(c(top5 = "top5", `14league` = "14league"), function(cut) {
    blups <- readRDS(sprintf("data/results/coach_blups_%s.rds", cut))
    grades <- readRDS(sprintf("data/results/coach_grades_%s.rds", cut))
    blups |> left_join(grades |> select(coach_id, letter_grade, rank),
                       by = "coach_id")
  })
  vc5  <- list(coach = 0.0044, resid = 0.1150)   # Part 5 published components
  vc14 <- list(coach = 0.0027, resid = 0.1439)

  coefs <- cr_value_model_coefs()
  beta_wv <- coefs[["log(norm_weighted_value)"]]

  list(
    delta = delta, as_of = as_of,
    coach_formations = coach_formations, profiles = profiles,
    league_profiles = league_profiles,
    rigidity = rigidity |> select(coach_id, rigidity),
    mean_rigidity = mean_rigidity,
    fit = fit, slopes = slopes,
    slope_cols = paste0(fit$axes, "_c"),
    composition = composition, tbl = tbl,
    quality = q, vc = list(top5 = vc5, `14league` = vc14),
    beta_wv = beta_wv,
    archetypes = cf_player_archetypes(),
    coach_names = xx_data_cache$coaches |> distinct(coach_id, coach_name)
  )
}

# Scores every candidate coach for one target team.
#   team_season_id / league_key / season: the squad to advise on (default
#   season = as_of - 1, the latest observed squad).
# Returns one row per coach: total predicted uplift vs a league-average coach
# (PPG), its quality / fit / deployment components, an approximate 95%
# interval, and the tier label.
cr_score_team <- function(scorer, team_season_id, league_key,
                          season = scorer$as_of - 1) {
  squad <- cr_team_squad(team_season_id, league_key, season,
                         archetypes = scorer$archetypes)
  fvals <- cr_team_formation_values(squad)

  # target composition: squad archetype shares weighted by last-season minutes
  comp <- xx_data_cache$players |>
    filter(team_season_id == !!team_season_id, player_position != "Goalkeeper",
           !is.na(minutes_played), minutes_played > 0) |>
    inner_join(squad$outfield |> select(player_id, archetype), by = "player_id") |>
    filter(!is.na(archetype)) |>
    group_by(archetype) |>
    summarize(m = sum(minutes_played), .groups = "drop") |>
    mutate(share = m / sum(m))
  shares <- setNames(rep(0, 11), rownames(cr_archetype_slot_matrix))
  shares[comp$archetype] <- comp$share
  x <- c(
    A1_creators = unname(shares["F3"] + shares["M4"]),
    A2_spine    = unname((shares["D2"] + shares["M2"]) - (shares["M1"] + shares["D1"])),
    A3_wingback = unname(shares["M3"])
  )
  x_c <- x - scorer$fit$axis_means[names(x)]

  # deployment reference: a league-average coach at this squad
  ref_deploy <- cr_deployable(fvals, scorer$league_profiles[[league_key]],
                              scorer$mean_rigidity)

  # candidate pool: every coach with a quality BLUP in either cut
  pool <- scorer$quality$top5 |>
    select(coach_id, coach_name, blup, n_stints, letter_grade, rank) |>
    mutate(cut = "top5") |>
    bind_rows(
      scorer$quality$`14league` |>
        filter(!(coach_id %in% scorer$quality$top5$coach_id)) |>
        select(coach_id, coach_name, blup, n_stints, letter_grade, rank) |>
        mutate(cut = "14league")
    )

  rows <- lapply(seq_len(nrow(pool)), function(i) {
    p <- pool[i, ]
    vc <- scorer$vc[[p$cut]]
    var_quality <- 1 / (1 / vc$coach + p$n_stints / vc$resid)

    # fit component: shrunken slope deviations x centered axes
    s <- scorer$slopes[scorer$slopes$coach_id == p$coach_id, ]
    has_fit <- nrow(s) == 1
    fit_uplift <- 0; var_fit <- 0
    if (has_fit) {
      for (ax in scorer$slope_cols) {
        xa <- x_c[[sub("_c$", "", ax)]]
        fit_uplift <- fit_uplift + s[[ax]] * xa
        var_fit <- var_fit + s[[paste0("var_", ax)]] * xa^2
      }
    }

    # deployment component: value the coach's shapes can field vs the
    # league-average coach, through the published value coefficient
    prof <- scorer$profiles[[p$coach_id]]
    has_deploy <- !is.null(prof)
    deploy_uplift <- 0
    if (has_deploy) {
      r <- scorer$rigidity$rigidity[scorer$rigidity$coach_id == p$coach_id]
      if (length(r) == 0) r <- scorer$mean_rigidity
      deploy <- cr_deployable(fvals, prof, r)
      deploy_uplift <- scorer$beta_wv * log(deploy / ref_deploy)
    }

    total <- p$blup + fit_uplift + deploy_uplift
    se <- sqrt(var_quality + var_fit)
    data.frame(
      coach_id = p$coach_id, coach_name = p$coach_name,
      cut = p$cut, letter_grade = p$letter_grade, rank_in_cut = p$rank,
      tier = if (has_fit || has_deploy) "full" else "quality_only",
      quality = p$blup, fit = fit_uplift, deployment = deploy_uplift,
      uplift_ppg = total, lo = total - 1.96 * se, hi = total + 1.96 * se
    )
  })

  out <- bind_rows(rows) |>
    arrange(desc(uplift_ppg)) |>
    mutate(uplift_rank = row_number())
  attr(out, "shares") <- shares   # 11 archetype shares (similarity layer)
  attr(out, "axes") <- x
  out
}

# =============================================================================
# 6. Payoff validation (pre-registered; design sec. 7.3)
# =============================================================================

# Leave-one-season-out over 2016-2024 (2015 has no lag year), scoring only
# NEW coach-club pairings in the held-out season (no stint at that club the
# season before). Weighted RMSE (stint games) per fold, paired t-tests
# between adjacent tiers.
#
# Primary framing P uses the pre-hire information set:
#   P0 = baseline_fixed on raw squad value (trained without the fold season)
#   P1 = P0 + coach quality BLUP        (mixed model on training stints)
#   P2 = P1 + global archetype effects  (train-centered adjustment)
#   P3 = P2 + coach fit slopes + deployment term
# Sensitivity framing R conditions on the realized weighted value:
#   R0 = enhanced_fixed (trained without the fold), R1-R3 as above minus the
#   deployment term (deployment is already inside realized weighted value).
cr_payoff_validation <- function(scorer, dataset = NULL,
                                 seasons = 2016:2024) {
  if (is.null(dataset)) dataset <- build_model_dataset(2005:2024)
  tbl <- cr_add_axes(scorer$tbl)
  cfm <- scorer$coach_formations |>
    mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))
  by_coach_form <- split(cfm, cfm$coach_id)
  d_log <- dataset |> filter(norm_total_value > 0, norm_weighted_value > 0)

  share_cols <- cf_share_cols(tbl)
  fixed_terms <- paste(c(setdiff(share_cols, "share_M1"), "fallback_share"),
                       collapse = " + ")
  ctrl <- lmerControl(optimizer = "bobyqa")

  # new pairings: no stint by this coach at this club the season before
  tbl <- tbl |> mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id))
  prev <- tbl |> transmute(coach_id, club_id, season = season + 1, had_prev = TRUE)
  new_pairs <- tbl |>
    left_join(prev, by = c("coach_id", "club_id", "season")) |>
    filter(is.na(had_prev), season %in% seasons)

  wrmse <- function(a, p, w) sqrt(sum(w * (a - p)^2) / sum(w))

  fold_rows <- list()
  for (s in seasons) {
    train <- tbl |> filter(season != s)
    test  <- new_pairs |> filter(season == s)
    if (nrow(test) == 0) next

    # --- value predictions
    train_d <- d_log |> filter(season != s)
    m_raw <- lm(points_per_game ~ log(norm_total_value) + as.factor(league) + is_b_team,
                data = train_d)
    m_wv  <- lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team,
                data = train_d)
    test_ds <- dataset |>
      filter(team_season_id %in% test$team_season_id) |>
      select(team_season_id, norm_total_value, norm_weighted_value, is_b_team,
             league_ds = league)
    test <- test |> left_join(test_ds, by = "team_season_id") |>
      filter(norm_total_value > 0, norm_weighted_value > 0)
    newd <- test |> transmute(norm_total_value, norm_weighted_value,
                              league = league_ds, is_b_team)
    p0 <- predict(m_raw, newdata = newd)
    r0 <- predict(m_wv,  newdata = newd)

    # --- quality BLUP (training stints only)
    m_q <- lmer(partial_residual_ppg ~ (1 | coach_id) + (1 | club_id),
                data = train, weights = n_games, REML = FALSE, control = ctrl)
    re_q <- lme4::ranef(m_q)$coach_id
    blup_q <- setNames(re_q[, 1], rownames(re_q))
    q_adj <- unname(blup_q[test$coach_id])
    q_adj[is.na(q_adj)] <- 0

    # --- global archetype adjustment (train-centered)
    m_g <- lmer(as.formula(paste("partial_residual_ppg ~", fixed_terms,
                                 "+ (1 | coach_id) + (1 | club_id)")),
                data = train, weights = n_games, REML = FALSE, control = ctrl)
    fe <- lme4::fixef(m_g)
    terms_used <- intersect(names(fe), c(share_cols, "fallback_share"))
    g_part <- function(df) {
      out <- rep(0, nrow(df))
      for (tm in terms_used) out <- out + fe[[tm]] * df[[tm]]
      out
    }
    train_mean_g <- weighted.mean(g_part(train), train$n_games)
    g_adj <- g_part(test) - train_mean_g

    # --- fit slopes + deployment (trained without the fold)
    fit_s <- cr_fit_model_quiet(train, ctrl)
    re_s <- lme4::ranef(fit_s$model)$coach_id
    s_adj <- rep(0, nrow(test))
    if (length(fit_s$axes)) {
      for (ax in fit_s$axes) {
        xa <- test[[ax]] - fit_s$axis_means[[ax]]
        sl <- re_s[test$coach_id, paste0(ax, "_c")]
        sl[is.na(sl)] <- 0
        s_adj <- s_adj + sl * xa
      }
    }

    dep_adj <- vapply(seq_len(nrow(test)), function(i) {
      tt <- test[i, ]
      lg <- names(cf_tm_league_names())[cf_tm_league_names() == tt$league]
      squad <- cr_team_squad(tt$team_season_id, lg, tt$season,
                             archetypes = scorer$archetypes)
      if (nrow(squad$outfield) < 10) return(0)
      fvals <- cr_team_formation_values(squad)
      hist_m <- by_coach_form[[tt$coach_id]]
      if (!is.null(hist_m)) {
        hist_m <- hist_m |> filter(season_start_year < tt$season,
                                   club_id != tt$club_id)
      }
      prof <- if (is.null(hist_m) || nrow(hist_m) == 0) NULL else
        cr_formation_profile(hist_m, tt$season, scorer$delta, key = "formation")
      lg_prof <- cr_formation_profile(
        cfm |> filter(league == lg, season_start_year < tt$season),
        tt$season, scorer$delta, key = "formation")
      ref <- cr_deployable(fvals, lg_prof, scorer$mean_rigidity)
      if (is.null(prof)) return(0)
      r <- scorer$rigidity$rigidity[scorer$rigidity$coach_id == tt$coach_id]
      if (length(r) == 0) r <- scorer$mean_rigidity
      scorer$beta_wv * log(cr_deployable(fvals, prof, r) / ref)
    }, numeric(1))
    dep_adj <- dep_adj - weighted.mean(dep_adj, test$n_games)

    w <- test$n_games; a <- test$actual_ppg
    fold_rows[[as.character(s)]] <- data.frame(
      fold = s, n_test = nrow(test),
      P0 = wrmse(a, p0, w),
      P1 = wrmse(a, p0 + q_adj, w),
      P2 = wrmse(a, p0 + q_adj + g_adj, w),
      P3 = wrmse(a, p0 + q_adj + g_adj + s_adj + dep_adj, w),
      R0 = wrmse(a, r0, w),
      R1 = wrmse(a, r0 + q_adj, w),
      R2 = wrmse(a, r0 + q_adj + g_adj, w),
      R3 = wrmse(a, r0 + q_adj + g_adj + s_adj, w)
    )
    cat(sprintf("fold %d: n = %d done\n", s, nrow(test)))
  }

  folds <- bind_rows(fold_rows)
  print(folds |> mutate(across(-c(fold, n_test), \(x) round(x, 4))),
        row.names = FALSE)
  cat("\nmeans:\n")
  print(round(colMeans(folds[, -(1:2)]), 4))

  cat("\npaired t-tests (adjacent tiers, one-sided improvement):\n")
  for (pair in list(c("P0", "P1"), c("P1", "P2"), c("P2", "P3"),
                    c("R0", "R1"), c("R1", "R2"), c("R2", "R3"),
                    c("P0", "P3"))) {
    tt <- t.test(folds[[pair[1]]], folds[[pair[2]]], paired = TRUE,
                 alternative = "greater")
    cat(sprintf("  %s -> %s: mean improvement %+.4f  p = %.4f\n",
                pair[1], pair[2], mean(folds[[pair[1]]] - folds[[pair[2]]]),
                tt$p.value))
  }
  invisible(folds)
}

# quiet per-fold random-slope fit for the payoff loop; drops axes on
# convergence failure like cr_fit_model()
cr_fit_model_quiet <- function(train, ctrl, reference = "share_M1") {
  train <- train |>
    mutate(across(all_of(cr_axis_cols), \(x) x - mean(x), .names = "{.col}_c"))
  fixed <- paste(c(setdiff(cf_share_cols(train), reference), "fallback_share"),
                 collapse = " + ")
  axes_use <- cr_axis_cols
  repeat {
    slope_part <- if (length(axes_use) == 0) "(1 | coach_id)" else
      sprintf("(1 + %s || coach_id)", paste(paste0(axes_use, "_c"), collapse = " + "))
    m <- suppressWarnings(suppressMessages(
      lmer(as.formula(paste("partial_residual_ppg ~", fixed, "+", slope_part,
                            "+ (1 | club_id)")),
           data = train, weights = n_games, REML = FALSE, control = ctrl)))
    conv <- m@optinfo$conv$lme4
    if (is.null(conv$messages) ||
        !any(grepl("failed to converge", conv$messages)) ||
        length(axes_use) == 0) break
    axes_use <- head(axes_use, -1)
  }
  list(model = m, axes = axes_use,
       axis_means = colMeans(train[cr_axis_cols]))
}

# =============================================================================
# 7. Career facts (plausibility filters; design sec. 6)
# =============================================================================

cr_league_countries <- c(
  "premier-league" = "England",     "championship" = "England",
  "laliga" = "Spain",               "laliga2" = "Spain",
  "serie-a" = "Italy",              "bundesliga" = "Germany",
  "ligue-1" = "France",             "liga-portugal" = "Portugal",
  "jupiler-pro-league" = "Belgium", "eredivisie" = "Netherlands",
  "superliga" = "Denmark",          "ekstraklasa" = "Poland",
  "1-hnl" = "Croatia",              "super-lig" = "Turkey"
)

cr_big5_slugs <- c("premier-league", "laliga", "serie-a", "bundesliga", "ligue-1")

# One row per coach: leagues/countries coached, big-5 games, club level
# (games- and recency-weighted percentile of the clubs coached, where a
# club-season's level is its squad-value percentile among all 14-league clubs
# that season), last season seen, nationality (if the profile scrape ran).
cr_career_facts <- function(delta = 0.3, as_of = 2025) {
  cr14 <- readRDS("data/results/coach_residuals_14league.rds")
  res  <- readRDS("data/results/residuals_14league.rds")

  lvl <- res |>
    group_by(season) |>
    mutate(value_pctile = 100 * (rank(total_team_value) - 1) / (n() - 1)) |>
    ungroup() |>
    select(team_season_id, value_pctile)

  stints <- cr14 |>
    left_join(lvl, by = "team_season_id") |>
    mutate(w = n_games * delta^pmax(as_of - 1 - season, 0))

  facts <- stints |>
    group_by(coach_id, coach_name) |>
    summarize(
      leagues     = list(sort(unique(league))),
      countries   = list(sort(unique(unname(cr_league_countries[league])))),
      big5_games  = sum(n_games[league %in% cr_big5_slugs]),
      total_games = sum(n_games),
      n_stints    = n(),
      club_level  = weighted.mean(value_pctile, w, na.rm = TRUE),
      last_season = max(season),
      .groups = "drop"
    )

  nat_path <- "data/cache/coach_nationalities.rds"
  if (file.exists(nat_path)) {
    facts <- facts |>
      left_join(readRDS(nat_path), by = "coach_id")
  } else {
    facts$nationality <- NA_character_
  }
  facts
}

# =============================================================================
# 8. Similarity layer (descriptive; design sec. 5)
# =============================================================================

# Coach composition profiles: weighted mean of stint archetype shares, tilted
# toward overperforming stints (softmax over stint residuals, temperature tau
# = 0.2 PPG ~ mild tilt: a stint 0.35 PPG — one stint SD — above another gets
# ~5.8x its weight before the games weighting).
cr_coach_profiles <- function(tbl, tau = 0.2) {
  share_cols <- cf_share_cols(tbl)
  tbl |>
    group_by(coach_id, coach_name) |>
    group_modify(function(g, key) {
      w <- g$n_games * exp((g$partial_residual_ppg -
                              max(g$partial_residual_ppg)) / tau)
      out <- as.data.frame(t(vapply(share_cols,
                                    function(cn) weighted.mean(g[[cn]], w),
                                    numeric(1))))
      out$n_stints <- nrow(g)
      out
    }) |>
    ungroup()
}

# Cosine similarity between a target team's archetype share vector and every
# coach profile. `shares` is a named vector over the 11 archetype ids.
cr_similar_coaches <- function(profiles, shares, min_stints = 3) {
  share_cols <- grep("^share_", names(profiles), value = TRUE)
  v <- setNames(rep(0, length(share_cols)), share_cols)
  common <- intersect(paste0("share_", names(shares)), share_cols)
  v[common] <- shares[sub("^share_", "", common)]

  m <- as.matrix(profiles[, share_cols])
  sim <- as.numeric(m %*% v) / (sqrt(rowSums(m^2)) * sqrt(sum(v^2)))
  profiles |>
    mutate(similarity = sim) |>
    filter(n_stints >= min_stints) |>
    arrange(desc(similarity)) |>
    select(coach_id, coach_name, n_stints, similarity)
}

# =============================================================================
# 9. Results export for the website
# =============================================================================

# Persists everything the site exporter needs to data/results/recommender.rds:
#   teams   — per latest-season big-5 team: the suggestion table (top n_top by
#             the VALIDATED quality score, per the payoff acceptance rule; fit
#             and deployment are carried as exploratory columns), the
#             similarity strip, and the team's value-percentile level
#   facts   — per-coach career facts for the plausibility filter chips
#   meta    — payoff validation summary + fit-model LRT for honest labeling
# The payoff verdict (2026-07-13): quality ships (P0->P1 +0.0021, p = 0.052;
# realized framing p = 0.016); global archetype effects neutral (+0.0005);
# fit slopes + deployment a wash (-0.0003, p = 0.67) -> exploratory only.
cr_save_results <- function(scorer, payoff_folds, n_top = 60,
                            results_dir = "data/results") {
  facts <- cr_career_facts(delta = scorer$delta, as_of = scorer$as_of)
  profiles <- cr_coach_profiles(scorer$tbl)

  # "thrived with squads like yours": similarity strip restricted to coaches
  # with >= 4 big-5 stints and a positive games-weighted mean stint residual
  perf <- scorer$tbl |>
    group_by(coach_id) |>
    summarize(mean_res_b5 = weighted.mean(partial_residual_ppg, n_games),
              n_stints_b5 = n(), .groups = "drop")
  thriving <- profiles |>
    inner_join(perf, by = "coach_id") |>
    filter(n_stints_b5 >= 4, mean_res_b5 > 0)

  # team level: value percentile in the latest season, across the 14 leagues
  res <- readRDS("data/results/residuals_14league.rds")
  season <- scorer$as_of - 1
  lvl <- res |>
    filter(season == !!season) |>
    mutate(team_level = 100 * (rank(total_team_value) - 1) / (n() - 1)) |>
    select(team_season_id, team_level)

  team_rows <- list()
  for (lg in names(cf_tm_league_ids())) {
    lsid <- xx_league_season_id(cf_tm_league_ids()[[lg]], season)
    teams <- xx_data_cache$teams |> filter(league_season_id == lsid)
    for (i in seq_len(nrow(teams))) {
      ts <- teams$team_season_id[i]
      sc <- tryCatch(cr_score_team(scorer, ts, lg, season),
                     error = function(e) {
                       cat("  skip", ts, ":", conditionMessage(e), "\n")
                       NULL
                     })
      if (is.null(sc)) next
      top <- sc |> arrange(desc(quality)) |> head(n_top) |>
        mutate(headline_rank = row_number())
      sim <- cr_similar_coaches(thriving, attr(sc, "shares"), min_stints = 4) |>
        head(8) |>
        left_join(perf, by = "coach_id")
      team_rows[[ts]] <- list(
        team_season_id = ts, league_key = lg, season = season,
        team_level = lvl$team_level[match(ts, lvl$team_season_id)],
        suggestions = top, similar = sim
      )
      cat(sprintf("  %s scored (%d/%d in %s)\n",
                  teams$team_name[i], i, nrow(teams), lg))
    }
  }

  out <- list(
    teams = team_rows,
    facts = facts,
    meta = list(
      as_of = scorer$as_of, season = season, delta = scorer$delta,
      beta_wv = scorer$beta_wv,
      slope_lrt = list(chisq = scorer$fit$lrt$Chisq[2],
                       df = scorer$fit$lrt$Df[2],
                       p = scorer$fit$lrt$`Pr(>Chisq)`[2]),
      payoff = payoff_folds,
      headline = "quality",   # payoff acceptance rule outcome
      generated = format(Sys.time(), "%Y-%m-%d")
    )
  )
  saveRDS(out, file.path(results_dir, "recommender.rds"))
  cat("recommender.rds:", length(team_rows), "teams,",
      nrow(facts), "coach fact rows\n")
  invisible(out)
}
