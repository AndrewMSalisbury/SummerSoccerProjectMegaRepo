# source_sofascore.r
#
# SofaScore data layer for the coach/player-type fit pilot (Premier League,
# seasons 2015/16 through 2024/25).
#
# Functions use the ss_ prefix, with the same two tiers as source_data.r:
#   ss_raw_*  — fetches directly from SofaScore (always slow, sleeps 2s per request)
#   ss_data_* — checks the RDS cache first, scrapes only what is missing
#
# SofaScore rejects plain libcurl clients (TLS fingerprinting — httr/curl get
# HTTP 403 regardless of headers), so every request is made through a real
# headless Chrome session via {chromote}. Chrome must be installed.
#
# IDs: SofaScore uses opaque numeric ids, unlike the Transfermarkt-URL ids in
# source_data.r. Columns holding them are suffixed _ss_id. Linking SofaScore
# players to Transfermarkt players is done separately (name+team+season
# crosswalk), not here.
#
# Caches live in data/cache/sofascore/ (relative to the src/ working
# directory), one file per league-season:
#
# Player-season level (populated by ss_data_populate_player_season):
#   players_<season_ss_id>.rds — enumeration: player_ss_id, player_name, team
#   stats_<season_ss_id>.rds   — long table: player_ss_id, stat_name, stat_value
#   heatmap_<season_ss_id>.rds — points: player_ss_id, x, y, count
#   status_<season_ss_id>.rds  — per-player scrape status ("ok"/"missing");
#                                players absent from status are not yet scraped
#                                (network failures are not recorded, so they are
#                                retried on the next populate run)
#
# Match level (populated by ss_data_populate_match_season):
#   events_<season_ss_id>.rds       — all matches: event_ss_id, teams, score, date
#   formations_<season_ss_id>.rds   — per match per team: formation string
#   match_stats_<season_ss_id>.rds  — long per-player match statistics
#   shots_<season_ss_id>.rds        — every shot: coordinates, xg, body part, ...
#   match_status_<season_ss_id>.rds — per-event scrape status, same convention
#                                     as the player status table

library(chromote)
library(jsonlite)

# --- constants ---------------------------------------------------------------

ss_ut_PREMIER_LEAGUE <- 17
ss_ut_LA_LIGA        <- 8
ss_ut_SERIE_A        <- 23
ss_ut_BUNDESLIGA     <- 35
ss_ut_LIGUE_1        <- 34

# SofaScore season ids for the Premier League, keyed by season start year
# (same convention as season_start_year in leagues.rds).
ss_pl_season_ids <- c(
  "2015" = 10356,
  "2016" = 11733,
  "2017" = 13380,
  "2018" = 17359,
  "2019" = 23776,
  "2020" = 29415,
  "2021" = 37036,
  "2022" = 41886,
  "2023" = 52186,
  "2024" = 61627,
  "2025" = 76986
)

# Season ids for the other big-5 leagues, discovered from the
# /unique-tournament/{ut}/seasons endpoint on 2026-07-09 and smoke-tested
# (2015/16 season statistics confirmed present for all four).
# 2025/26 ids added 2026-07-25 from the same endpoint; the 2024/25 ids it
# returned matched these constants exactly, which is the check that the id
# convention still holds.
ss_big5_leagues <- list(
  premier_league = list(ut = ss_ut_PREMIER_LEAGUE, seasons = ss_pl_season_ids),
  la_liga = list(ut = ss_ut_LA_LIGA, seasons = c(
    "2015" = 10495, "2016" = 11906, "2017" = 13662, "2018" = 18020,
    "2019" = 24127, "2020" = 32501, "2021" = 37223, "2022" = 42409,
    "2023" = 52376, "2024" = 61643, "2025" = 77559
  )),
  serie_a = list(ut = ss_ut_SERIE_A, seasons = c(
    "2015" = 10596, "2016" = 11966, "2017" = 13768, "2018" = 17932,
    "2019" = 24644, "2020" = 32523, "2021" = 37475, "2022" = 42415,
    "2023" = 52760, "2024" = 63515, "2025" = 76457
  )),
  bundesliga = list(ut = ss_ut_BUNDESLIGA, seasons = c(
    "2015" = 10419, "2016" = 11818, "2017" = 13477, "2018" = 17597,
    "2019" = 23538, "2020" = 28210, "2021" = 37166, "2022" = 42268,
    "2023" = 52608, "2024" = 63516, "2025" = 77333
  )),
  ligue_1 = list(ut = ss_ut_LIGUE_1, seasons = c(
    "2015" = 10373, "2016" = 11648, "2017" = 13384, "2018" = 17279,
    "2019" = 23872, "2020" = 28222, "2021" = 37167, "2022" = 42273,
    "2023" = 52571, "2024" = 61736, "2025" = 77356
  ))
)

# All big-5 season ids as one named vector ("league.year" = season_ss_id),
# for the combined accessors below.
ss_big5_season_ids <- function(leagues = ss_big5_leagues) {
  unlist(lapply(leagues, function(l) l$seasons))
}

# Seasons covered by the SofaScore caches (also defined in player_archetypes.R,
# which mirrors the id table for chromote-free analysis sessions).
ss_seasons <- function() as.integer(names(ss_pl_season_ids))

ss_cache_dir <- "data/cache/sofascore"

# --- fetching ----------------------------------------------------------------

ss_env <- new.env()

ss_browser <- function() {
  s <- ss_env$session
  if (!is.null(s)) {
    alive <- tryCatch({ s$Runtime$evaluate("1"); TRUE }, error = function(e) FALSE)
    if (alive) return(s)
  }
  ss_env$session <- ChromoteSession$new()
  ss_env$session
}

# Fetches a SofaScore API URL through headless Chrome and parses the JSON.
# Returns a list with:
#   status — "ok" (parsed data), "missing" (HTTP 404: the resource genuinely
#            doesn't exist, e.g. no heatmap for a player — never retried), or
#            "failed" (network / browser / parse problem, or a 403/429 rate
#            limit — retried on the next populate run)
#   data   — the parsed JSON (lists, not simplified) when status == "ok"
#
# Politeness: sleeps 2-3s with jitter before every request and rests 90s
# after every 250 requests. On a 403/429 it backs off for 10 minutes —
# SofaScore rate-limits by IP and the block clears after a pause.
# (The PL pilot ran at 4-7s; lowered to 2-3s for the big-5 expansion on
# Andrew's decision 2026-07-09 — steady 2-3.5s was never punished in testing,
# the one IP block came from a 70-request burst. Never remove these delays;
# if a run starts hitting 403s, put the pacing back up before resuming.)
ss_fetch_json <- function(url) {
  n <- (if (is.null(ss_env$request_count)) 0 else ss_env$request_count) + 1
  ss_env$request_count <- n
  if (n %% 250 == 0) {
    message("  [", n, " requests this session — resting 90s]")
    Sys.sleep(90)
  }
  Sys.sleep(runif(1, 2, 3))
  txt <- tryCatch({
    b <- ss_browser()
    loaded <- b$Page$loadEventFired(wait_ = FALSE)
    b$Page$navigate(url, wait_ = FALSE)
    b$wait_for(loaded)
    b$Runtime$evaluate("document.body.innerText")$result$value
  }, error = function(e) {
    message("  fetch failed: ", conditionMessage(e))
    ss_env$session <- NULL   # force a fresh browser session next time
    NULL
  })
  if (is.null(txt)) return(list(status = "failed", data = NULL))
  parsed <- tryCatch(fromJSON(txt, simplifyVector = FALSE), error = function(e) NULL)
  if (is.null(parsed)) return(list(status = "failed", data = NULL))
  if (!is.null(parsed$error)) {
    code <- as.numeric(parsed$error$code)
    if (identical(code, 404)) return(list(status = "missing", data = NULL))
    message("  API error ", code, " on ", url, " — backing off 10 minutes")
    Sys.sleep(600)
    return(list(status = "failed", data = NULL))
  }
  list(status = "ok", data = parsed)
}

# --- enumeration -------------------------------------------------------------

# All players with season statistics in a league-season, from the paginated
# league statistics endpoint. One row per player.
ss_raw_league_season_players <- function(ut_id, season_ss_id) {
  rows <- list()
  page <- 1
  total_pages <- 1
  while (page <= total_pages) {
    url <- paste0(
      "https://www.sofascore.com/api/v1/unique-tournament/", ut_id,
      "/season/", season_ss_id,
      "/statistics?limit=100&offset=", (page - 1) * 100,
      "&order=-rating&accumulation=total&group=summary"
    )
    res <- ss_fetch_json(url)
    if (res$status != "ok") {
      stop("player enumeration failed for season ", season_ss_id, " page ", page)
    }
    total_pages <- res$data$pages
    page_rows <- lapply(res$data$results, function(r) {
      data.frame(
        season_ss_id = season_ss_id,
        player_ss_id = r$player$id,
        player_name  = r$player$name,
        team_ss_id   = r$team$id,
        team_name    = r$team$name,
        stringsAsFactors = FALSE
      )
    })
    rows <- c(rows, page_rows)
    message("  season ", season_ss_id, ": enumeration page ", page, "/", total_pages)
    page <- page + 1
  }
  do.call(rbind, rows)
}

ss_data_league_season_players <- function(ut_id, season_ss_id) {
  path <- file.path(ss_cache_dir, paste0("players_", season_ss_id, ".rds"))
  if (file.exists(path)) return(readRDS(path))
  players <- ss_raw_league_season_players(ut_id, season_ss_id)
  dir.create(ss_cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(players, path)
  players
}

# --- per-player scrapers -----------------------------------------------------

# Season statistics for one player: long data frame (stat_name, stat_value).
# ~110 numeric fields: zone-split passing, dribbles, duels, shooting, xG/xA,
# touches, minutes, etc.
ss_raw_player_season_stats <- function(player_ss_id, ut_id, season_ss_id) {
  url <- paste0(
    "https://www.sofascore.com/api/v1/player/", player_ss_id,
    "/unique-tournament/", ut_id, "/season/", season_ss_id,
    "/statistics/overall"
  )
  res <- ss_fetch_json(url)
  if (res$status != "ok") return(res)
  stats <- res$data$statistics
  stats <- stats[vapply(stats, is.numeric, logical(1))]
  list(status = "ok", data = data.frame(
    season_ss_id = season_ss_id,
    player_ss_id = player_ss_id,
    stat_name    = names(stats),
    stat_value   = as.numeric(unlist(stats)),
    stringsAsFactors = FALSE
  ))
}

# Season heatmap for one player: data frame of (x, y, count) on a 0-100 pitch
# grid, aggregated over all league matches in the season.
ss_raw_player_season_heatmap <- function(player_ss_id, ut_id, season_ss_id) {
  url <- paste0(
    "https://www.sofascore.com/api/v1/player/", player_ss_id,
    "/unique-tournament/", ut_id, "/season/", season_ss_id,
    "/heatmap/overall"
  )
  res <- ss_fetch_json(url)
  if (res$status != "ok") return(res)
  pts <- res$data$points
  list(status = "ok", data = data.frame(
    season_ss_id = season_ss_id,
    player_ss_id = player_ss_id,
    x     = vapply(pts, function(p) as.numeric(p$x), numeric(1)),
    y     = vapply(pts, function(p) as.numeric(p$y), numeric(1)),
    count = vapply(pts, function(p) as.numeric(p$count), numeric(1)),
    stringsAsFactors = FALSE
  ))
}

# --- match-level scrapers ------------------------------------------------------

ss_null_na <- function(x, as = as.numeric) {
  if (is.null(x)) as(NA) else as(x)
}

# All matches of a league-season from the paginated events endpoint.
ss_raw_league_season_events <- function(ut_id, season_ss_id) {
  rows <- list()
  page <- 0
  repeat {
    url <- paste0(
      "https://www.sofascore.com/api/v1/unique-tournament/", ut_id,
      "/season/", season_ss_id, "/events/last/", page
    )
    res <- ss_fetch_json(url)
    if (res$status != "ok") {
      stop("event enumeration failed for season ", season_ss_id, " page ", page)
    }
    page_rows <- lapply(res$data$events, function(e) {
      data.frame(
        season_ss_id     = season_ss_id,
        event_ss_id      = e$id,
        slug             = e$slug,
        round            = ss_null_na(e$roundInfo$round),
        start_timestamp  = ss_null_na(e$startTimestamp),
        status_type      = e$status$type,
        home_team_ss_id  = e$homeTeam$id,
        home_team_name   = e$homeTeam$name,
        away_team_ss_id  = e$awayTeam$id,
        away_team_name   = e$awayTeam$name,
        home_goals       = ss_null_na(e$homeScore$current),
        away_goals       = ss_null_na(e$awayScore$current),
        has_xg           = isTRUE(e$hasXg),
        has_player_stats = isTRUE(e$hasEventPlayerStatistics),
        stringsAsFactors = FALSE
      )
    })
    rows <- c(rows, page_rows)
    message("  season ", season_ss_id, ": events page ", page + 1,
            " (", length(page_rows), " events)")
    if (!isTRUE(res$data$hasNextPage)) break
    page <- page + 1
  }
  do.call(rbind, rows)
}

ss_data_league_season_events <- function(ut_id, season_ss_id) {
  path <- file.path(ss_cache_dir, paste0("events_", season_ss_id, ".rds"))
  if (file.exists(path)) return(readRDS(path))
  events <- ss_raw_league_season_events(ut_id, season_ss_id)
  dir.create(ss_cache_dir, recursive = TRUE, showWarnings = FALSE)
  saveRDS(events, path)
  events
}

# Lineups for one match: each team's formation plus every player's match
# statistics (passes by half, long balls, crosses, dribbles, duels, touches,
# minutes, rating, ...) in long format. One request covers all ~30 players.
ss_raw_event_lineups <- function(event_ss_id) {
  url <- paste0("https://www.sofascore.com/api/v1/event/", event_ss_id, "/lineups")
  res <- ss_fetch_json(url)
  if (res$status != "ok") return(res)

  formations <- list()
  stat_rows <- list()
  for (side in c("home", "away")) {
    team <- res$data[[side]]
    if (is.null(team)) next
    formations[[side]] <- data.frame(
      event_ss_id = event_ss_id,
      is_home     = side == "home",
      formation   = ss_null_na(team$formation, as.character),
      stringsAsFactors = FALSE
    )
    for (p in team$players) {
      stats <- p$statistics
      if (is.null(stats)) next
      stats <- stats[vapply(stats, is.numeric, logical(1))]
      if (length(stats) == 0) next
      stat_rows[[length(stat_rows) + 1]] <- data.frame(
        event_ss_id  = event_ss_id,
        player_ss_id = p$player$id,
        team_ss_id   = ss_null_na(p$teamId),
        is_home      = side == "home",
        position     = ss_null_na(p$position, as.character),
        substitute   = isTRUE(p$substitute),
        stat_name    = names(stats),
        stat_value   = as.numeric(unlist(stats)),
        stringsAsFactors = FALSE
      )
    }
  }
  list(
    status     = "ok",
    formations = do.call(rbind, unname(formations)),
    data       = if (length(stat_rows) > 0) do.call(rbind, stat_rows) else NULL
  )
}

# Shotmap for one match: every shot by every player, with pitch coordinates,
# xG/xGOT, body part, situation and outcome. One request per match.
ss_raw_event_shotmap <- function(event_ss_id) {
  url <- paste0("https://www.sofascore.com/api/v1/event/", event_ss_id, "/shotmap")
  res <- ss_fetch_json(url)
  if (res$status != "ok") return(res)
  rows <- lapply(res$data$shotmap, function(s) {
    data.frame(
      event_ss_id  = event_ss_id,
      shot_ss_id   = s$id,
      player_ss_id = s$player$id,
      player_name  = s$player$name,
      is_home      = isTRUE(s$isHome),
      shot_type    = ss_null_na(s$shotType, as.character),
      situation    = ss_null_na(s$situation, as.character),
      body_part    = ss_null_na(s$bodyPart, as.character),
      x            = ss_null_na(s$playerCoordinates$x),
      y            = ss_null_na(s$playerCoordinates$y),
      goal_mouth_location = ss_null_na(s$goalMouthLocation, as.character),
      xg           = ss_null_na(s$xg),
      xgot         = ss_null_na(s$xgot),
      time         = ss_null_na(s$time),
      time_seconds = ss_null_na(s$timeSeconds),
      stringsAsFactors = FALSE
    )
  })
  list(status = "ok", data = do.call(rbind, rows))
}

# Per-player per-match action chart from the (misleadingly named)
# rating-breakdown endpoint: every pass (start AND end coordinates, outcome,
# keypass flag), dribble, defensive action, and ball-carry.
# ONLY AVAILABLE FROM THE 2025/26 SEASON ONWARD — 404 for all earlier matches
# (verified: exists 2025-08, missing 2025-05 and earlier).
ss_raw_player_event_breakdown <- function(event_ss_id, player_ss_id) {
  url <- paste0(
    "https://www.sofascore.com/api/v1/event/", event_ss_id,
    "/player/", player_ss_id, "/rating-breakdown"
  )
  res <- ss_fetch_json(url)
  if (res$status != "ok") return(res)
  rows <- list()
  for (group in names(res$data)) {
    for (a in res$data[[group]]) {
      rows[[length(rows) + 1]] <- data.frame(
        event_ss_id  = event_ss_id,
        player_ss_id = player_ss_id,
        action_group = group,
        action_type  = ss_null_na(a$eventActionType, as.character),
        x            = ss_null_na(a$playerCoordinates$x),
        y            = ss_null_na(a$playerCoordinates$y),
        end_x        = ss_null_na(a$passEndCoordinates$x),
        end_y        = ss_null_na(a$passEndCoordinates$y),
        outcome      = if (is.null(a$outcome)) NA else isTRUE(a$outcome),
        keypass      = if (is.null(a$keypass)) NA else isTRUE(a$keypass),
        stringsAsFactors = FALSE
      )
    }
  }
  list(status = "ok",
       data = if (length(rows) > 0) do.call(rbind, rows) else NULL)
}

# --- bulk population ---------------------------------------------------------

ss_read_or <- function(path, empty) {
  if (file.exists(path)) readRDS(path) else empty
}

# Scrapes stats + heatmap for every enumerated player in one league-season.
# Resumable: players already in the status table are skipped; network failures
# are not recorded and so are retried on the next run. Caches are written every
# save_every players and at the end, so an interrupted run loses little.
# max_players limits the number of *new* players processed (for testing).
ss_data_populate_player_season <- function(ut_id, season_ss_id,
                                           save_every = 25, max_players = Inf) {
  players <- ss_data_league_season_players(ut_id, season_ss_id)

  stats_path   <- file.path(ss_cache_dir, paste0("stats_", season_ss_id, ".rds"))
  heatmap_path <- file.path(ss_cache_dir, paste0("heatmap_", season_ss_id, ".rds"))
  status_path  <- file.path(ss_cache_dir, paste0("status_", season_ss_id, ".rds"))

  empty_status <- data.frame(
    player_ss_id = numeric(0), stats = character(0), heatmap = character(0),
    stringsAsFactors = FALSE
  )
  stats_all   <- ss_read_or(stats_path, NULL)
  heatmap_all <- ss_read_or(heatmap_path, NULL)
  status      <- ss_read_or(status_path, empty_status)

  todo <- players[!(players$player_ss_id %in% status$player_ss_id), ]
  if (nrow(todo) > max_players) todo <- todo[seq_len(max_players), ]
  message("season ", season_ss_id, ": ", nrow(todo), " players to scrape (",
          nrow(status), " already done)")

  save_caches <- function() {
    dir.create(ss_cache_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(stats_all, stats_path)
    saveRDS(heatmap_all, heatmap_path)
    saveRDS(status, status_path)
  }

  done_this_run <- 0
  consecutive_failures <- 0
  for (i in seq_len(nrow(todo))) {
    p <- todo[i, ]
    stats_res   <- ss_raw_player_season_stats(p$player_ss_id, ut_id, season_ss_id)
    heatmap_res <- ss_raw_player_season_heatmap(p$player_ss_id, ut_id, season_ss_id)

    # A failed request means we don't record the player at all, so both
    # endpoints are retried next run (stats and heatmap are cheap to re-fetch).
    if (stats_res$status == "failed" || heatmap_res$status == "failed") {
      message("  ", p$player_name, ": fetch failed, will retry on next run")
      consecutive_failures <- consecutive_failures + 1
      if (consecutive_failures >= 3) {
        save_caches()
        stop("3 players failed in a row — probably rate-limited. ",
             "Progress is saved; re-run later to resume.")
      }
      next
    }
    consecutive_failures <- 0

    if (stats_res$status == "ok")   stats_all   <- rbind(stats_all, stats_res$data)
    if (heatmap_res$status == "ok") heatmap_all <- rbind(heatmap_all, heatmap_res$data)
    status <- rbind(status, data.frame(
      player_ss_id = p$player_ss_id,
      stats        = stats_res$status,
      heatmap      = heatmap_res$status,
      stringsAsFactors = FALSE
    ))

    done_this_run <- done_this_run + 1
    if (done_this_run %% save_every == 0) {
      save_caches()
      message("  season ", season_ss_id, ": ", done_this_run, "/", nrow(todo),
              " scraped this run")
    }
  }
  save_caches()
  invisible(status)
}

# Scrapes lineups (formations + per-player match stats) and shotmap for every
# finished match of a league-season. Same resume conventions as the player
# populate: recorded events are skipped, failures are retried next run.
ss_data_populate_match_season <- function(ut_id, season_ss_id,
                                          save_every = 25, max_events = Inf) {
  events <- ss_data_league_season_events(ut_id, season_ss_id)
  events <- events[events$status_type == "finished", ]

  formations_path  <- file.path(ss_cache_dir, paste0("formations_", season_ss_id, ".rds"))
  match_stats_path <- file.path(ss_cache_dir, paste0("match_stats_", season_ss_id, ".rds"))
  shots_path       <- file.path(ss_cache_dir, paste0("shots_", season_ss_id, ".rds"))
  status_path      <- file.path(ss_cache_dir, paste0("match_status_", season_ss_id, ".rds"))

  empty_status <- data.frame(
    event_ss_id = numeric(0), lineups = character(0), shotmap = character(0),
    stringsAsFactors = FALSE
  )
  formations_all  <- ss_read_or(formations_path, NULL)
  match_stats_all <- ss_read_or(match_stats_path, NULL)
  shots_all       <- ss_read_or(shots_path, NULL)
  status          <- ss_read_or(status_path, empty_status)

  todo <- events[!(events$event_ss_id %in% status$event_ss_id), ]
  if (nrow(todo) > max_events) todo <- todo[seq_len(max_events), ]
  message("season ", season_ss_id, ": ", nrow(todo), " matches to scrape (",
          nrow(status), " already done)")

  save_caches <- function() {
    dir.create(ss_cache_dir, recursive = TRUE, showWarnings = FALSE)
    saveRDS(formations_all, formations_path)
    saveRDS(match_stats_all, match_stats_path)
    saveRDS(shots_all, shots_path)
    saveRDS(status, status_path)
  }

  done_this_run <- 0
  consecutive_failures <- 0
  for (i in seq_len(nrow(todo))) {
    e <- todo[i, ]
    lineups_res <- ss_raw_event_lineups(e$event_ss_id)
    shotmap_res <- ss_raw_event_shotmap(e$event_ss_id)

    if (lineups_res$status == "failed" || shotmap_res$status == "failed") {
      message("  ", e$slug, ": fetch failed, will retry on next run")
      consecutive_failures <- consecutive_failures + 1
      if (consecutive_failures >= 3) {
        save_caches()
        stop("3 matches failed in a row — probably rate-limited. ",
             "Progress is saved; re-run later to resume.")
      }
      next
    }
    consecutive_failures <- 0

    if (lineups_res$status == "ok") {
      formations_all  <- rbind(formations_all, lineups_res$formations)
      match_stats_all <- rbind(match_stats_all, lineups_res$data)
    }
    if (shotmap_res$status == "ok") shots_all <- rbind(shots_all, shotmap_res$data)
    status <- rbind(status, data.frame(
      event_ss_id = e$event_ss_id,
      lineups     = lineups_res$status,
      shotmap     = shotmap_res$status,
      stringsAsFactors = FALSE
    ))

    done_this_run <- done_this_run + 1
    if (done_this_run %% save_every == 0) {
      save_caches()
      message("  season ", season_ss_id, ": ", done_this_run, "/", nrow(todo),
              " matches scraped this run")
    }
  }
  save_caches()
  invisible(status)
}

# Full pilot: all Premier League seasons 2015-2024, player-season data
# (season stats + heatmap per player) and match data (formations + per-player
# match stats + shotmap per match). Roughly 1,900 requests per season at 2s
# each — about an hour per season, 10-11 hours for all ten. Safe to interrupt
# and re-run at any point.
ss_data_populate_pl_pilot <- function(start_years = names(ss_pl_season_ids)) {
  for (yr in start_years) {
    ss_data_populate_player_season(ss_ut_PREMIER_LEAGUE, ss_pl_season_ids[[yr]])
    ss_data_populate_match_season(ss_ut_PREMIER_LEAGUE, ss_pl_season_ids[[yr]])
  }
}

# Big-5 expansion: every league-season in ss_big5_leagues, same two layers as
# the pilot. Seasons already fully scraped (the PL) are skipped by the resume
# logic at negligible cost. ~70k new requests at 2-3s pacing — roughly 55
# hours end to end; run overnight in stages, interrupt and re-run freely.
ss_data_populate_big5 <- function(leagues = ss_big5_leagues,
                                  start_years = names(ss_pl_season_ids)) {
  for (league_name in names(leagues)) {
    league <- leagues[[league_name]]
    for (yr in start_years) {
      message("=== ", league_name, " ", yr, " ===")
      ss_data_populate_player_season(league$ut, league$seasons[[yr]])
      ss_data_populate_match_season(league$ut, league$seasons[[yr]])
    }
  }
}

# --- combined accessors ------------------------------------------------------

ss_read_seasons <- function(prefix, season_ss_ids) {
  paths <- file.path(ss_cache_dir, paste0(prefix, "_", season_ss_ids, ".rds"))
  found <- paths[file.exists(paths)]
  if (length(found) == 0) return(NULL)
  do.call(rbind, lapply(found, readRDS))
}

# Long stats table across seasons: season_ss_id, player_ss_id, stat_name, stat_value
ss_data_player_stats <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("stats", season_ss_ids)
}

# Heatmap points across seasons: season_ss_id, player_ss_id, x, y, count
ss_data_player_heatmaps <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("heatmap", season_ss_ids)
}

# Player enumeration across seasons: season_ss_id, player_ss_id, player_name, team
ss_data_players <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("players", season_ss_ids)
}

# Matches across seasons: teams, scores, dates, round
ss_data_events <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("events", season_ss_ids)
}

# Per-match team formations: event_ss_id, is_home, formation
ss_data_formations <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("formations", season_ss_ids)
}

# Long per-player match statistics: event_ss_id, player_ss_id, stat_name, stat_value
ss_data_match_stats <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("match_stats", season_ss_ids)
}

# All shots with coordinates and xG: event_ss_id, player_ss_id, x, y, xg, ...
ss_data_shots <- function(season_ss_ids = ss_pl_season_ids) {
  ss_read_seasons("shots", season_ss_ids)
}
