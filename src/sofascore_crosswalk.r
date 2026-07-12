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

# Maps SofaScore team names to TM team_season_ids. Returns a data frame in
# input order; unmappable teams (e.g. lower-division relegation-playoff
# opponents that appear in SofaScore season data) get NA.
#
# Two mechanisms beyond plain token equality, both needed for the big-5
# leagues (plain Jaccard mapped "Borussia M'gladbach" onto Borussia Dortmund
# via the shared "borussia"):
#   - token equivalence: equal, one contains the other (>= 4 chars,
#     gladbach ~ monchengladbach, lyon ~ lyonnais), or edit distance <= 2 for
#     tokens of >= 7 chars (nurnberg ~ nuremberg)
#   - greedy one-to-one assignment: best-scoring pairs claim their teams
#     first, so an exact "Borussia Dortmund" consumes the Dortmund slot
#     before Gladbach's weak partial overlap can. Pairs below min_score are
#     never assigned.
ss_crosswalk_team_map <- function(ss_team_names, tm_teams, min_score = 0.2) {
  # only drop pure furniture — words like "United"/"City" distinguish clubs
  # (Manchester United vs Manchester City) and must stay
  stopwords <- c("fc", "afc")
  core_tokens <- function(nm) {
    toks <- ss_name_tokens(nm)
    core <- setdiff(toks, stopwords)
    if (length(core) == 0) toks else core
  }
  tok_eq <- function(a, b) {
    if (a == b) return(TRUE)
    if (nchar(a) >= 4 && nchar(b) >= 4 && (grepl(a, b, fixed = TRUE) ||
                                           grepl(b, a, fixed = TRUE))) return(TRUE)
    nchar(a) >= 7 && nchar(b) >= 7 && adist(a, b) <= 2
  }
  pair_score <- function(ss_toks, tm_toks) {
    used <- rep(FALSE, length(tm_toks))
    m <- 0
    for (a in ss_toks) {
      hit <- which(!used & vapply(tm_toks, tok_eq, logical(1), a = a))
      if (length(hit) > 0) { used[hit[1]] <- TRUE; m <- m + 1 }
    }
    m / (length(ss_toks) + length(tm_toks) - m)
  }

  ss_toks <- lapply(ss_team_names, core_tokens)
  tm_toks <- lapply(tm_teams$team_name, core_tokens)
  scores <- outer(seq_along(ss_toks), seq_along(tm_toks),
                  Vectorize(function(i, j) pair_score(ss_toks[[i]], tm_toks[[j]])))

  assignment <- rep(NA_integer_, length(ss_team_names))
  ord <- order(scores, decreasing = TRUE)
  tm_used <- rep(FALSE, nrow(tm_teams))
  for (k in ord) {
    if (scores[k] < min_score) break
    i <- (k - 1) %% length(ss_team_names) + 1
    j <- (k - 1) %/% length(ss_team_names) + 1
    if (is.na(assignment[i]) && !tm_used[j]) {
      assignment[i] <- j
      tm_used[j] <- TRUE
    }
  }

  data.frame(
    team_name_ss   = ss_team_names,
    team_season_id = ifelse(is.na(assignment), NA_character_,
                            tm_teams$team_season_id[assignment]),
    team_name_tm   = ifelse(is.na(assignment), NA_character_,
                            tm_teams$team_name[assignment]),
    overlap        = vapply(seq_along(assignment), function(i) {
      if (is.na(assignment[i])) NA_real_ else scores[i, assignment[i]]
    }, numeric(1)),
    stringsAsFactors = FALSE
  )
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
  tm_players <- players[players$team_season_id %in% tm_teams$team_season_id &
                          !is.na(players$player_name), ]

  team_map <- ss_crosswalk_team_map(unique(ss$team_name), tm_teams)
  unmapped <- team_map[is.na(team_map$team_season_id), ]
  if (nrow(unmapped) > 0) {
    # expected for lower-division relegation-playoff opponents that leak into
    # SofaScore season data; their players fall through to league-wide match
    warning("unmapped SofaScore teams (players matched league-wide only): ",
            paste(unmapped$team_name_ss, collapse = "; "))
  }
  low <- team_map[!is.na(team_map$overlap) & team_map$overlap < 0.34, ]
  if (nrow(low) > 0) {
    warning("weak team mappings: ",
            paste(low$team_name_ss, "->", low$team_name_tm, collapse = "; "))
  }

  rows <- lapply(seq_len(nrow(ss)), function(i) {
    p <- ss[i, ]
    tsid <- team_map$team_season_id[team_map$team_name_ss == p$team_name]
    in_team <- if (length(tsid) == 1 && !is.na(tsid)) {
      tm_players[tm_players$team_season_id == tsid, ]
    } else {
      tm_players[0, ]
    }

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
