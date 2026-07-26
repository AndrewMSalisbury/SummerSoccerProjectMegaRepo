# source_odds.R — Betting-market benchmark data layer (Milestone: Market Benchmark)
# Design: Docs/Market_Benchmark_Design.md
#
# Ingests football-data.co.uk results + closing odds for the 13 project leagues
# that the site covers (all 14 active leagues except Croatia/HNL, which
# football-data does not carry), builds a verified team-name -> Transfermarkt
# crosswalk, and emits a clean matches+odds table joined to TM team_season ids.
#
# Prefix: od_. Two tiers mirror source_data.r / source_sofascore.r:
#   od_raw_*  downloads a CSV from football-data (network).
#   od_data_* reads the local CSV cache first, downloads only if missing.
#
# football-data is free static CSV (no TLS fingerprinting, no politeness problem
# like SofaScore) so the only rate courtesy is a short sleep between downloads.
# Caches live in data/cache/odds/ (raw CSVs) and data/cache/odds/*.rds (parsed).
# All reads/writes stay under src/data/ per project convention.

suppressWarnings(suppressMessages({
  library(dplyr)
}))

od_cache_dir <- "data/cache/odds"

# --- League configuration -----------------------------------------------------
# div      : football-data division code (main-file leagues) or country code
#            (new-league combined files).
# format   : "main" = mmz4281/<SSSS>/<div>.csv (one file per season, wide odds).
#            "new"  = new/<CODE>.csv (one combined file, all seasons, thin odds).
# tm_league: the Transfermarkt league_id constant name in source_data.r.
# tm_code  : the TM wettbewerb code (last URL path token) — used only for docs.
od_leagues <- tibble::tribble(
  ~div,   ~format, ~tm_league_var,               ~tm_code, ~label,
  "E0",   "main",  "xx_league_id_PREMIER_LEAGUE", "GB1",    "Premier League",
  "E1",   "main",  "xx_league_id_CHAMPIONSHIP",   "GB2",    "Championship",
  "SP1",  "main",  "xx_league_id_LA_LIGA",        "ES1",    "La Liga",
  "SP2",  "main",  "xx_league_id_LALIGA_2",       "ES2",    "LaLiga 2",
  "I1",   "main",  "xx_league_id_SERIE_A",        "IT1",    "Serie A",
  "D1",   "main",  "xx_league_id_BUNDESLIGA",     "L1",     "Bundesliga",
  "F1",   "main",  "xx_league_id_LIGUE_1",        "FR1",    "Ligue 1",
  "P1",   "main",  "xx_league_id_LIGA_PORTUGAL",  "PO1",    "Liga Portugal",
  "N1",   "main",  "xx_league_id_EREDIVISIE",     "NL1",    "Eredivisie",
  "B1",   "main",  "xx_league_id_PRO_LEAGUE",     "BE1",    "Jupiler Pro League",
  "T1",   "main",  "xx_league_id_SUPER_LIG",      "TR1",    "Super Lig",
  "DNK",  "new",   "xx_league_id_SUPERLIGA",      "DK1",    "Danish Superliga",
  "POL",  "new",   "xx_league_id_EKSTRAKLASA",    "PL1",    "Ekstraklasa"
)

# football-data season code: TM season_start_year 2012 -> "1213".
od_season_code <- function(season_start_year) {
  a <- season_start_year %% 100
  b <- (season_start_year + 1) %% 100
  sprintf("%02d%02d", a, b)
}

# --- Raw download -------------------------------------------------------------
od_raw_url <- function(div, format, season_start_year = NULL) {
  if (format == "main") {
    sprintf("https://www.football-data.co.uk/mmz4281/%s/%s.csv",
            od_season_code(season_start_year), div)
  } else {
    sprintf("https://www.football-data.co.uk/new/%s.csv", div)
  }
}

# Downloads one CSV to the cache. main -> per season; new -> one combined file.
# Returns the cache path on success, NA on failure (e.g. season not published).
od_raw_download <- function(div, format, season_start_year = NULL, sleep = 1) {
  if (!dir.exists(od_cache_dir)) dir.create(od_cache_dir, recursive = TRUE)
  fname <- if (format == "main") sprintf("%s_%d.csv", div, season_start_year)
           else sprintf("%s_all.csv", div)
  dest <- file.path(od_cache_dir, fname)
  url  <- od_raw_url(div, format, season_start_year)
  ok <- tryCatch({
    download.file(url, dest, quiet = TRUE, mode = "wb")
    # football-data returns a small HTML error page for missing seasons; a valid
    # CSV is > 1 KB and parseable with a Date/HomeTeam or Home column.
    info <- file.info(dest)
    if (is.na(info$size) || info$size < 200) { unlink(dest); FALSE } else TRUE
  }, error = function(e) FALSE)
  Sys.sleep(sleep)
  if (ok) dest else NA_character_
}

# Populate the CSV cache for all leagues across a season range.
# main leagues: one file per season. new leagues: one combined file (season
# range ignored, downloaded once). Idempotent — skips files already cached
# unless force = TRUE.
od_data_populate <- function(seasons = 2005:xx_last_data_season, force = FALSE) {
  if (!dir.exists(od_cache_dir)) dir.create(od_cache_dir, recursive = TRUE)
  log <- list()
  for (i in seq_len(nrow(od_leagues))) {
    lg <- od_leagues[i, ]
    if (lg$format == "main") {
      for (s in seasons) {
        fname <- sprintf("%s_%d.csv", lg$div, s)
        dest  <- file.path(od_cache_dir, fname)
        if (!force && file.exists(dest)) { log[[fname]] <- "cached"; next }
        res <- od_raw_download(lg$div, "main", s)
        log[[fname]] <- if (is.na(res)) "MISSING" else "downloaded"
        cat(sprintf("  %-12s %s\n", fname, log[[fname]]))
      }
    } else {
      fname <- sprintf("%s_all.csv", lg$div)
      dest  <- file.path(od_cache_dir, fname)
      if (!force && file.exists(dest)) { log[[fname]] <- "cached"; next }
      res <- od_raw_download(lg$div, "new")
      log[[fname]] <- if (is.na(res)) "MISSING" else "downloaded"
      cat(sprintf("  %-12s %s\n", fname, log[[fname]]))
    }
  }
  invisible(log)
}

# --- Name normalization + scorer ---------------------------------------------
# football-data uses stable abbreviations ("Man City", "Ath Madrid", "Sp Lisbon")
# that plain token equality misses. The scorer is prefix-aware: an fd token
# matches a TM token if either is a >=3-char prefix of the other. Matching is
# done as a within-season one-to-one assignment (the ~20 clubs are a bijection),
# so even an imperfect scorer resolves correctly under the bijection constraint.
od_norm_name <- function(x) {
  x <- tolower(x)
  x <- iconv(x, to = "ASCII//TRANSLIT")
  x <- gsub("[^a-z0-9 ]", " ", x)
  x <- paste0(" ", x, " ")
  for (w in c("fc","cf","sc","ac","as","ss","us","ud","cd","sd","rc","if",
              "afc","bk","fk","calcio","club","de","the","1","04","05","09")) {
    x <- gsub(paste0(" ", w, " "), " ", x, fixed = TRUE)
  }
  trimws(gsub("[[:space:]]+", " ", x))
}

od_name_tokens <- function(x) {
  t <- strsplit(od_norm_name(x), " ")[[1]]
  t[nchar(t) > 0]
}

od_tok_match <- function(a, b) {
  if (a == b) return(TRUE)
  n <- min(nchar(a), nchar(b))
  if (n < 3) return(FALSE)
  substr(a, 1, n) == substr(b, 1, n)
}

od_name_score <- function(a, b) {
  ta <- od_name_tokens(a); tb <- od_name_tokens(b)
  if (length(ta) == 0 || length(tb) == 0) return(0)
  m_ab <- mean(vapply(ta, function(x) any(vapply(tb, od_tok_match, logical(1), a = x)), logical(1)))
  m_ba <- mean(vapply(tb, function(x) any(vapply(ta, od_tok_match, logical(1), a = x)), logical(1)))
  tok <- (m_ab + m_ba) / 2
  na <- od_norm_name(a); nb <- od_norm_name(b)
  ed <- 1 - as.numeric(adist(na, nb)) / max(nchar(na), nchar(nb), 1)
  0.75 * tok + 0.25 * max(ed, 0)
}

# --- Main-file parser ---------------------------------------------------------
# Odds priority: Pinnacle closing (PSC) -> Pinnacle (PS) -> Bet365 closing
# (B365C) -> Bet365 (B365). Rows without any usable 1X2 triple keep odds = NA.
od_parse_date <- function(v) {
  d <- as.Date(v, format = "%d/%m/%Y")
  na <- is.na(d)
  if (any(na)) d[na] <- as.Date(v[na], format = "%d/%m/%y")
  d
}

od_coalesce_odds <- function(df, trip) {
  H <- rep(NA_real_, nrow(df)); D <- H; A <- H; src <- rep(NA_character_, nrow(df))
  for (s in names(trip)) {
    cols <- trip[[s]]
    if (!all(cols %in% names(df))) next
    h  <- suppressWarnings(as.numeric(df[[cols[1]]]))
    dd <- suppressWarnings(as.numeric(df[[cols[2]]]))
    a  <- suppressWarnings(as.numeric(df[[cols[3]]]))
    ok <- is.na(H) & !is.na(h) & !is.na(dd) & !is.na(a) & h > 1 & dd > 1 & a > 1
    H[ok] <- h[ok]; D[ok] <- dd[ok]; A[ok] <- a[ok]; src[ok] <- s
  }
  data.frame(odds_h = H, odds_d = D, odds_a = A, odds_src = src, stringsAsFactors = FALSE)
}

od_parse_main <- function(path) {
  d <- tryCatch(read.csv(path, stringsAsFactors = FALSE), error = function(e) NULL)
  if (is.null(d) || nrow(d) == 0) return(NULL)
  need <- c("Date","HomeTeam","AwayTeam","FTHG","FTAG")
  if (!all(need %in% names(d))) return(NULL)
  d <- d[!is.na(d$HomeTeam) & d$HomeTeam != "" & !is.na(d$FTHG) & d$FTHG != "", ]
  if (nrow(d) == 0) return(NULL)
  odds <- od_coalesce_odds(d, list(
    PSC   = c("PSCH","PSCD","PSCA"),
    PS    = c("PSH","PSD","PSA"),
    B365C = c("B365CH","B365CD","B365CA"),
    B365  = c("B365H","B365D","B365A")
  ))
  out <- data.frame(
    match_date = od_parse_date(d$Date),
    fd_home = trimws(d$HomeTeam),
    fd_away = trimws(d$AwayTeam),
    fthg = suppressWarnings(as.integer(d$FTHG)),
    ftag = suppressWarnings(as.integer(d$FTAG)),
    stringsAsFactors = FALSE
  )
  out <- cbind(out, odds)
  out[!is.na(out$match_date) & !is.na(out$fthg) & !is.na(out$ftag), ]
}

od_fd_team_names <- function(div) {
  files <- list.files(od_cache_dir, pattern = sprintf("^%s_[[:digit:]]+[.]csv$", div), full.names = TRUE)
  nm <- character(0)
  for (f in files) {
    p <- od_parse_main(f)
    if (!is.null(p)) nm <- c(nm, p$fd_home, p$fd_away)
  }
  sort(unique(nm))
}

# --- Transfermarkt side -------------------------------------------------------
# team_season_id embeds a stable club id: .../verein/<id>/saison_id/<year>.
# Extracted by string split to avoid regex backreference escaping.
od_verein_id <- function(team_season_id) {
  a <- strsplit(team_season_id, "/verein/", fixed = TRUE)
  vapply(a, function(p) {
    if (length(p) < 2) return(NA_character_)
    strsplit(p[[2]], "/", fixed = TRUE)[[1]][1]
  }, character(1))
}

od_saison_of <- function(league_season_id) {
  a <- strsplit(league_season_id, "saison_id=", fixed = TRUE)
  vapply(a, function(p) if (length(p) < 2) NA_character_ else p[[2]], character(1))
}

# TM clubs for one league-season, as (verein, team_name, team_season_id).
od_tm_teams_for <- function(tm_code, season, teams_tbl) {
  key <- sprintf("wettbewerb/%s/plus/?saison_id=%d", tm_code, season)
  sub <- teams_tbl[grepl(key, teams_tbl$league_season_id, fixed = TRUE), ]
  if (nrow(sub) == 0) return(NULL)
  data.frame(
    verein         = od_verein_id(sub$team_season_id),
    tm_name        = sub$team_name,
    team_season_id = sub$team_season_id,
    league_season_id = sub$league_season_id,
    stringsAsFactors = FALSE
  )
}

# --- Manual overrides ---------------------------------------------------------
# (div, fd_name) -> TM verein id, for clubs the greedy bijection mis-assigns or
# leaves unmatched. Filled from od_crosswalk_report() diagnostics. verein is the
# numeric TM club id (character).
od_name_overrides <- tibble::tribble(
  ~div, ~fd_name, ~verein
  # populated after first crosswalk diagnostic run
)

# --- Crosswalk ----------------------------------------------------------------
# Greedy one-to-one assignment of fd names to TM clubs within each league-season
# (the ~20 clubs are a bijection). Aggregates to a stable (div, fd_name)->verein
# map by majority vote across seasons; applies od_name_overrides last.
od_greedy_assign <- function(fd_names, tm) {
  # score matrix fd x tm
  S <- matrix(0, nrow = length(fd_names), ncol = nrow(tm),
              dimnames = list(fd_names, tm$verein))
  for (i in seq_along(fd_names))
    for (j in seq_len(nrow(tm)))
      S[i, j] <- od_name_score(fd_names[i], tm$tm_name[j])
  assign <- data.frame(fd_name = character(0), verein = character(0),
                        tm_name = character(0), score = numeric(0),
                        stringsAsFactors = FALSE)
  Sc <- S
  repeat {
    if (all(is.na(Sc))) break
    idx <- which(Sc == max(Sc, na.rm = TRUE), arr.ind = TRUE)[1, ]
    best <- Sc[idx[1], idx[2]]
    if (is.na(best) || best <= 0) break
    fn <- rownames(Sc)[idx[1]]; vr <- colnames(Sc)[idx[2]]
    assign <- rbind(assign, data.frame(
      fd_name = fn, verein = vr,
      tm_name = tm$tm_name[tm$verein == vr][1], score = best,
      stringsAsFactors = FALSE))
    Sc[idx[1], ] <- NA
    Sc[, idx[2]] <- NA
  }
  assign
}

od_build_crosswalk <- function(divs = od_leagues$div[od_leagues$format == "main"],
                               seasons = 2012:2024, verbose = FALSE) {
  teams_tbl <- readRDS("data/cache/teams.rds")
  per_season <- list()
  for (div in divs) {
    tm_code <- od_leagues$tm_code[od_leagues$div == div]
    for (s in seasons) {
      f <- file.path(od_cache_dir, sprintf("%s_%d.csv", div, s))
      if (!file.exists(f)) next
      p <- od_parse_main(f)
      if (is.null(p) || nrow(p) == 0) next
      fd_names <- sort(unique(c(p$fd_home, p$fd_away)))
      tm <- od_tm_teams_for(tm_code, s, teams_tbl)
      if (is.null(tm)) next
      a <- od_greedy_assign(fd_names, tm)
      a$div <- div; a$season <- s
      per_season[[paste(div, s)]] <- a
    }
  }
  allpairs <- do.call(rbind, per_season)
  # majority vote per (div, fd_name)
  stable <- allpairs |>
    group_by(div, fd_name) |>
    summarize(
      verein   = names(sort(table(verein), decreasing = TRUE))[1],
      tm_name  = tm_name[which.max(score)][1],
      n_seasons = n(),
      min_score = min(score),
      mean_score = mean(score),
      n_verein = n_distinct(verein),
      .groups = "drop"
    )
  # apply overrides
  if (nrow(od_name_overrides) > 0) {
    stable <- stable |>
      left_join(od_name_overrides, by = c("div", "fd_name"), suffix = c("", "_ovr")) |>
      mutate(verein = ifelse(!is.na(verein_ovr), verein_ovr, verein),
             overridden = !is.na(verein_ovr)) |>
      select(-verein_ovr)
  } else {
    stable$overridden <- FALSE
  }
  list(map = stable, per_season = allpairs)
}

# --- Odds de-margining ---------------------------------------------------------
# Proportional (normalized) de-margin: p_i = (1/odds_i) / overround. Basic and
# standard; the design's favourite-longshot correction is a later robustness pass.
od_demargin <- function(oh, od, oa) {
  ih <- 1/oh; id <- 1/od; ia <- 1/oa
  s <- ih + id + ia
  list(p_h = ih/s, p_d = id/s, p_a = ia/s, overround = s)
}

# --- Build the joined matches+odds table --------------------------------------
# For the given seasons and main-file leagues, maps each fd match to home/away
# TM team_season_ids via the crosswalk and attaches de-margined closing probs.
# Returns one row per match with TM ids, goals, result, market probs, odds src.
od_build_matches <- function(seasons = 2012:2024, cw = NULL) {
  if (is.null(cw)) cw <- od_build_crosswalk(seasons = seasons)
  map <- as.data.frame(cw$map)
  teams_tbl   <- readRDS("data/cache/teams.rds")
  divs <- od_leagues$div[od_leagues$format == "main"]
  out <- list()
  # per-season assignment is one-to-one by construction (bijection guard), so it
  # cannot collide two fd names onto one verein the way the cross-season stable
  # map can (e.g. RAEC Mons 2012). Overrides from od_name_overrides layer on top.
  ps <- as.data.frame(cw$per_season)
  ovr <- as.data.frame(od_name_overrides)
  for (div in divs) {
    tm_code <- od_leagues$tm_code[od_leagues$div == div]
    for (s in seasons) {
      f <- file.path(od_cache_dir, sprintf("%s_%d.csv", div, s))
      if (!file.exists(f)) next
      p <- od_parse_main(f)
      if (is.null(p) || nrow(p) == 0) next
      tm <- od_tm_teams_for(tm_code, s, teams_tbl)
      if (is.null(tm)) next
      dmap <- ps[ps$div == div & ps$season == s, c("fd_name","verein")]
      if (nrow(ovr) > 0) {
        o <- ovr[ovr$div == div, c("fd_name","verein")]
        if (nrow(o) > 0) {
          dmap <- dmap[!(dmap$fd_name %in% o$fd_name), ]
          dmap <- rbind(dmap, o)
        }
      }
      vh <- dmap$verein[match(p$fd_home, dmap$fd_name)]
      va <- dmap$verein[match(p$fd_away, dmap$fd_name)]
      hts <- tm$team_season_id[match(vh, tm$verein)]
      ats <- tm$team_season_id[match(va, tm$verein)]
      lsid <- tm$league_season_id[1]
      dm <- od_demargin(p$odds_h, p$odds_d, p$odds_a)
      out[[paste(div, s)]] <- data.frame(
        div = div, season = s, league_season_id = lsid,
        match_date = p$match_date,
        fd_home = p$fd_home, fd_away = p$fd_away,
        home_verein = vh, away_verein = va,
        home_team_season_id = hts, away_team_season_id = ats,
        fthg = p$fthg, ftag = p$ftag,
        ftr = ifelse(p$fthg > p$ftag, "H", ifelse(p$fthg < p$ftag, "A", "D")),
        odds_h = p$odds_h, odds_d = p$odds_d, odds_a = p$odds_a, odds_src = p$odds_src,
        p_h = dm$p_h, p_d = dm$p_d, p_a = dm$p_a, overround = dm$overround,
        stringsAsFactors = FALSE
      )
    }
  }
  do.call(rbind, out)
}

# --- Reconciliation: fd-derived season points vs TM's own match records -------
# The definitive crosswalk check: independent of team names. For every mapped
# (league_season, TM club) it compares total points computed from fd matches to
# total points computed from matches.rds. A correct crosswalk agrees exactly
# (both sources record the same league fixtures); disagreement flags a bad map
# or a fixture-coverage gap.
od_reconcile <- function(matches_odds = NULL, seasons = 2012:2024) {
  if (is.null(matches_odds)) matches_odds <- od_build_matches(seasons = seasons)
  mo <- matches_odds[!is.na(matches_odds$home_team_season_id) &
                     !is.na(matches_odds$away_team_season_id), ]
  # fd points per team_season_id
  fd_pts <- function(mo) {
    hp <- ifelse(mo$fthg > mo$ftag, 3L, ifelse(mo$fthg == mo$ftag, 1L, 0L))
    ap <- ifelse(mo$ftag > mo$fthg, 3L, ifelse(mo$fthg == mo$ftag, 1L, 0L))
    rbind(
      data.frame(team_season_id = mo$home_team_season_id, pts = hp),
      data.frame(team_season_id = mo$away_team_season_id, pts = ap)
    ) |> group_by(team_season_id) |>
      summarize(fd_points = sum(pts), fd_games = n(), .groups = "drop")
  }
  fdp <- fd_pts(mo)

  # matches.rds columns are home_team_id / away_team_id (both are team_season_id URLs)
  tmm <- readRDS("data/cache/matches.rds")
  tm_pts <- rbind(
    data.frame(team_season_id = tmm$home_team_id,
               pts = ifelse(tmm$home_team_goals > tmm$away_team_goals, 3L,
                     ifelse(tmm$home_team_goals == tmm$away_team_goals, 1L, 0L))),
    data.frame(team_season_id = tmm$away_team_id,
               pts = ifelse(tmm$away_team_goals > tmm$home_team_goals, 3L,
                     ifelse(tmm$away_team_goals == tmm$home_team_goals, 1L, 0L)))
  ) |> group_by(team_season_id) |>
    summarize(tm_points = sum(pts), tm_games = n(), .groups = "drop")

  rec <- fdp |> left_join(tm_pts, by = "team_season_id") |>
    mutate(pts_diff = fd_points - tm_points, games_diff = fd_games - tm_games)
  rec
}
