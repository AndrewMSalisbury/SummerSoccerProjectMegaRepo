# sofascore_crosswalk.r
#
# Links SofaScore player ids to Transfermarkt player ids (URLs) so archetype
# features built from SofaScore data can join the existing players.rds /
# residual tables. Pure cache-reader: no scraping, no chromote.
#
# Matching runs per league-season, team by team:
#   1. exact    — normalized full name equal within the mapped team
#   2. tokens   — same name tokens in any order (handles "Heung-Min Son" vs
#                 "Son Heung-min")
#   3. fuzzy    — unique within-team Levenshtein match at <= 0.25 normalized
#                 distance
#   4. league   — steps 1-2 against the whole league (mid-season transfers,
#                 team mapping misses)
# Unmatched or ambiguous players are returned with method NA for review.
#
# Output cache: data/cache/sofascore/crosswalk_<season_ss_id>.rds

# --- name and team normalization ----------------------------------------------

ss_normalize_name <- function(x) {
  x <- tolower(x)
  x <- iconv(x, from = "UTF-8", to = "ASCII//TRANSLIT")
  x <- gsub("[^a-z ]", " ", x)
  x <- gsub("\\s+", " ", trimws(x))
  x
}

ss_name_tokens <- function(x) {
  sort(strsplit(ss_normalize_name(x), " ")[[1]])
}

# Maps each SofaScore team name to a TM team_season_id by token overlap,
# ignoring generic suffixes (FC, AFC, ...). Returns a data frame.
ss_crosswalk_team_map <- function(ss_team_names, tm_teams) {
  # only drop pure furniture — words like "United"/"City" distinguish clubs
  # (Manchester United vs Manchester City) and must stay
  stopwords <- c("fc", "afc")
  core_tokens <- function(nm) {
    toks <- ss_name_tokens(nm)
    core <- setdiff(toks, stopwords)
    if (length(core) == 0) toks else core
  }
  rows <- lapply(ss_team_names, function(ss_nm) {
    ss_toks <- core_tokens(ss_nm)
    overlap <- vapply(tm_teams$team_name, function(tm_nm) {
      tm_toks <- core_tokens(tm_nm)
      length(intersect(ss_toks, tm_toks)) /
        length(union(ss_toks, tm_toks))
    }, numeric(1))
    best <- which.max(overlap)
    data.frame(
      team_name_ss   = ss_nm,
      team_season_id = tm_teams$team_season_id[best],
      team_name_tm   = tm_teams$team_name[best],
      overlap        = overlap[best],
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

# --- player matching -----------------------------------------------------------

# Finds the TM row matching one SofaScore name within candidates.
# Rules run loosest-tolerance-last; a rule with several hits does not decide —
# it falls through so a stricter later rule can disambiguate. Only if no rule
# produces a unique hit does a multi-hit earlier rule mark the case ambiguous.
# Returns list(row = index or NA, method = character).
ss_match_player <- function(ss_name, tm_names) {
  norm_ss <- ss_normalize_name(ss_name)
  norm_tm <- ss_normalize_name(tm_names)
  tok_ss  <- ss_name_tokens(ss_name)
  tok_tm  <- lapply(tm_names, ss_name_tokens)

  # a is scalar, b may be a vector — substring() (unlike substr) vectorizes
  # over its stop argument
  prefix_pair <- function(a, b) {
    n <- pmin(nchar(a), nchar(b))
    n >= 3 & substring(a, 1, n) == substring(b, 1, n)
  }
  d <- as.vector(adist(norm_ss, norm_tm)) / pmax(nchar(norm_ss), nchar(norm_tm))

  rules <- list(
    exact  = function() which(norm_tm == norm_ss),
    tokens = function() {
      flat <- vapply(tok_tm, paste, character(1), collapse = " ")
      which(flat == paste(tok_ss, collapse = " "))
    },
    # one name's tokens contained in the other's: TM "Gabriel" vs
    # SS "Gabriel Magalhaes"
    subset = function() which(vapply(tok_tm, function(t) {
      all(t %in% tok_ss) || all(tok_ss %in% t)
    }, logical(1))),
    # multi-token names whose tokens all pair as >= 3-char prefixes:
    # SS "Max Kilman" vs TM "Maximilian Kilman"
    prefix = function() which(vapply(tok_tm, function(t) {
      short <- if (length(t) <= length(tok_ss)) t else tok_ss
      long  <- if (length(t) <= length(tok_ss)) tok_ss else t
      length(short) >= 2 &&
        all(vapply(short, function(s) any(prefix_pair(s, long)), logical(1)))
    }, logical(1))),
    fuzzy = function() {
      # accept up to 0.30 but only a clear winner: runner-up must be far away
      ord <- order(d)
      if (length(d) >= 1 && d[ord[1]] <= 0.30 &&
          (length(d) == 1 || d[ord[2]] >= pmax(0.45, d[ord[1]] + 0.15))) {
        return(ord[1])
      }
      integer(0)
    }
  )

  saw_multi <- FALSE
  for (nm in names(rules)) {
    hit <- rules[[nm]]()
    if (length(hit) == 1) return(list(row = hit, method = nm))
    if (length(hit) > 1) saw_multi <- TRUE
  }
  list(row = NA, method = if (saw_multi) "ambiguous" else NA_character_)
}

# --- crosswalk builder ----------------------------------------------------------

# Builds the SofaScore->TM crosswalk for one league-season.
#   season_ss_id     — SofaScore season id (players_<id>.rds must be cached)
#   league_season_id — TM league-season URL (as in leagues.rds)
ss_build_crosswalk <- function(season_ss_id, league_season_id) {
  teams   <- readRDS("data/cache/teams.rds")
  players <- readRDS("data/cache/players.rds")
  ss      <- readRDS(file.path("data/cache/sofascore",
                               paste0("players_", season_ss_id, ".rds")))

  tm_teams   <- teams[teams$league_season_id == league_season_id, ]
  tm_players <- players[players$team_season_id %in% tm_teams$team_season_id, ]

  team_map <- ss_crosswalk_team_map(unique(ss$team_name), tm_teams)
  low <- team_map[team_map$overlap < 0.34, ]
  if (nrow(low) > 0) {
    warning("weak team mappings: ",
            paste(low$team_name_ss, "->", low$team_name_tm, collapse = "; "))
  }
  if (anyDuplicated(team_map$team_season_id)) {
    dup <- team_map[team_map$team_season_id %in%
                    team_map$team_season_id[duplicated(team_map$team_season_id)], ]
    stop("two SofaScore teams mapped to the same TM team: ",
         paste(dup$team_name_ss, "->", dup$team_name_tm, collapse = "; "))
  }

  rows <- lapply(seq_len(nrow(ss)), function(i) {
    p <- ss[i, ]
    tsid <- team_map$team_season_id[team_map$team_name_ss == p$team_name]
    in_team <- tm_players[tm_players$team_season_id == tsid, ]

    m <- ss_match_player(p$player_name, in_team$player_name)
    scope <- "team"
    if (is.na(m$row) && !identical(m$method, "ambiguous")) {
      m <- ss_match_player(p$player_name, tm_players$player_name)
      scope <- "league"
      # at league scope only exact/tokens are trustworthy
      if (!identical(m$method, "exact") && !identical(m$method, "tokens")) {
        m <- list(row = NA, method = m$method)
      }
    }
    matched_from <- if (scope == "team") in_team else tm_players
    data.frame(
      season_ss_id  = p$season_ss_id,
      player_ss_id  = p$player_ss_id,
      player_name_ss = p$player_name,
      team_name_ss  = p$team_name,
      player_id     = if (is.na(m$row)) NA_character_ else matched_from$player_id[m$row],
      player_name_tm = if (is.na(m$row)) NA_character_ else matched_from$player_name[m$row],
      method        = if (is.na(m$row)) m$method else paste(scope, m$method, sep = "_"),
      stringsAsFactors = FALSE
    )
  })
  xw <- do.call(rbind, rows)

  # a TM player matched by two different SS players is a red flag — demote both
  dup <- xw$player_id[!is.na(xw$player_id)]
  dup <- unique(dup[duplicated(dup)])
  if (length(dup) > 0) {
    xw$method[xw$player_id %in% dup] <- "duplicate_target"
    xw$player_id[xw$player_id %in% dup] <- NA_character_
  }

  saveRDS(xw, file.path("data/cache/sofascore",
                        paste0("crosswalk_", season_ss_id, ".rds")))
  xw
}

# Prints a match-rate summary and returns unmatched rows invisibly.
ss_crosswalk_report <- function(xw) {
  cat("players:", nrow(xw), "\n")
  cat("matched:", sum(!is.na(xw$player_id)),
      sprintf("(%.1f%%)", 100 * mean(!is.na(xw$player_id))), "\n")
  print(table(xw$method, useNA = "ifany"))
  un <- xw[is.na(xw$player_id), ]
  if (nrow(un) > 0) {
    cat("\nunmatched/ambiguous:\n")
    print(un[, c("player_name_ss", "team_name_ss", "method")], row.names = FALSE)
  }
  invisible(un)
}
