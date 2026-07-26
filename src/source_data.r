# FBCoach Data Layer
#
# These methods provide access to the raw data provided by TransferMarkt.
# They also provide a caching layer so that we only scrape the TransferMarkt
# pages when we don't already have a local copy.

#library(worldfootballR)
library(dplyr)
library(httr)
library(purrr)
library(rvest)
library(stringr)
library(tidyr)
library(xml2)

# Browser session cookie for Transfermarkt. Expires after days/weeks.
# To refresh: in Chrome DevTools Network tab, right-click any TM request
# -> Copy -> Copy as cURL, then update the -b '...' value below.
.TM_COOKIE <- "_sp_su=false; AMCV_B21B678254F601E20A4C98A5%40AdobeOrg=MCMID|88287303479104173192568162169096146625; _sp_v1_ss=1:H4sIAAAAAAAAAItWqo5RKimOUbLKK83J0YlRSkVil4AlqmtrlXQGVlk0MiMPxDCojcWlD6eEUiwAP1Mivu4AAAA%3D; _sp_v1_p=826; _sp_v1_data=1208957; euconsent-v2=CQlVK8AQlVK8AAGABCENCfFsAP_gAEPgACiQLdtR_C7dCCFAADZzaLsgeIQQ1lADJsABAAQAACAFAAIQgIwCkUEAFAAAgAAAERAAIgAAAAAAAAAAAAAAAIAEKACEAAAUwAAAIAAAABAAQAAAAAAAAAAAAAAAAgABAAAAgAAEAAIAQAAAAQACAAAgAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAkAAAAAAAABAIAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAQiAABAAAAACC3cAUBKwEKwI3gStAt2AWEgNAAVAAuABwADwAIIAZABoAEwAKoAbwA_ACEgEMARIAjgBNADAAHsAPuAjQCOAEiAPaAvMBkgEBAIXAV8AsKEABgAOACKAQcdAdAAWABUADgAIIAZABoAEwAKoAXQAxABvAD9AIYAiQBHACaAFGAMAAewA-wCLAEcAJEAWIAvIB7QEyALzAZIBAQC3Y4AHAA4ADwALwEHAQghAJAAWAFUAMQAbwA_ADAAI4ASICAhAAEAA8AsRKAcAAsADgATAAqgBigEMARIAjgBRgDAAI4AvMBkgEBAJWkgAQAFwCDlIDAACwAKgAcABAADQAJgAVQAxAB-gEMARIAjgBRgDAAH2ARYAjgBIgC8gHtAXmAyQBsoEBALClAAoAFwAZAEHALEAdstAFAGAARwCAgFhQLdgA.ILdtR_C7dCCFAADZzaLsgeIQQ1lADJsABAAQAACAFAAIQgIwCkUEAFAAAgAAAERAAIgAAAAAAAAAAAAAAAIAEKACEAAAUwAAAIAAAABAAQAAAAAAAAAAAAAAAAgABAAAAgAAEAAIAQAAAAQACAAAgAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAkAAAAAAAABAIAAAAAAAAACAAAAAAAAAAAAAAAAAAAAAAACAAAAAAAAAAQiAABAAAAAC.YAAAAAAAAAAA; consentUUID=3127fd6a-cbf5-4efc-a00b-e7a84966fcf1_57; kndctr_B21B678254F601E20A4C98A5_AdobeOrg_identity=CiY4ODI4NzMwMzQ3OTEwNDE3MzE5MjU2ODE2MjE2OTA5NjE0NjYyNVISCNTX7dmIMxABGAEqA09SMjAA8AHb37fw6zM%3D; kndctr_B21B678254F601E20A4C98A5_AdobeOrg_cluster=or2; cuukie=VGZkZHJwRHZwTDZfXzZMUWlPbkQwdW5oMTc0ZjNZYX5AbrFeNJO01IsdyRSqUNj0RvIdoWW2hVGvx9MYZF-Taw%3D%3D"

xx_fetch_page <- function(url) {
  tryCatch({
    response <- httr::GET(
      url,
      httr::add_headers(
        `accept`                    = "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        `accept-language`           = "en-US,en;q=0.9",
        `cache-control`             = "max-age=0",
        `cookie`                    = .TM_COOKIE,
        `sec-ch-ua`                 = '"Google Chrome";v="149", "Chromium";v="149", "Not)A;Brand";v="24"',
        `sec-ch-ua-mobile`          = "?0",
        `sec-ch-ua-platform`        = '"Windows"',
        `sec-fetch-dest`            = "document",
        `sec-fetch-mode`            = "navigate",
        `sec-fetch-site`            = "none",
        `sec-fetch-user`            = "?1",
        `upgrade-insecure-requests` = "1",
        `user-agent`                = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
      )
    )
    if (httr::http_error(response)) {
      cat('  HTTP', httr::status_code(response), 'for', url, '\n')
      return(NULL)
    }
    xml2::read_html(httr::content(response, as = "text", encoding = "UTF-8"))
  }, error = function(e) {
    cat('  ERROR loading page:', conditionMessage(e), '\n')
    NULL
  })
}

# Individual leagues — top 5
xx_league_id_PREMIER_LEAGUE <- "https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1"
xx_league_id_LIGUE_1        <- "https://www.transfermarkt.com/ligue-1/startseite/wettbewerb/FR1"
xx_league_id_LA_LIGA        <- "https://www.transfermarkt.com/laliga/startseite/wettbewerb/ES1"
xx_league_id_SERIE_A        <- "https://www.transfermarkt.com/serie-a/startseite/wettbewerb/IT1"
xx_league_id_BUNDESLIGA     <- "https://www.transfermarkt.com/bundesliga/startseite/wettbewerb/L1"

# Additional leagues (6–20 by global rating)
xx_league_id_PRO_LEAGUE       <- "https://www.transfermarkt.com/jupiler-pro-league/startseite/wettbewerb/BE1"
xx_league_id_CHAMPIONSHIP     <- "https://www.transfermarkt.com/championship/startseite/wettbewerb/GB2"
xx_league_id_LIGA_PORTUGAL    <- "https://www.transfermarkt.com/liga-portugal/startseite/wettbewerb/PO1"
xx_league_id_SERIE_A_BRAZIL   <- "https://www.transfermarkt.com/campeonato-brasileiro-serie-a/startseite/wettbewerb/BRA1"
xx_league_id_MLS              <- "https://www.transfermarkt.com/major-league-soccer/startseite/wettbewerb/MLS1"
xx_league_id_EREDIVISIE       <- "https://www.transfermarkt.com/eredivisie/startseite/wettbewerb/NL1"
xx_league_id_SUPERLIGA        <- "https://www.transfermarkt.com/superliga/startseite/wettbewerb/DK1"
xx_league_id_EKSTRAKLASA      <- "https://www.transfermarkt.com/ekstraklasa/startseite/wettbewerb/PL1"
xx_league_id_LIGA_PROFESIONAL <- "https://www.transfermarkt.com/liga-profesional-de-futbol/startseite/wettbewerb/AR1N"
xx_league_id_J_LEAGUE         <- "https://www.transfermarkt.com/j1-league/startseite/wettbewerb/JAP1"
xx_league_id_SUPER_LIG        <- "https://www.transfermarkt.com/super-lig/startseite/wettbewerb/TR1"
xx_league_id_ALLSVENSKAN      <- "https://www.transfermarkt.com/allsvenskan/startseite/wettbewerb/SE1"
xx_league_id_HNL              <- "https://www.transfermarkt.com/1-hnl/startseite/wettbewerb/KR1"
xx_league_id_LIGA_MX          <- "https://www.transfermarkt.com/liga-mx/startseite/wettbewerb/MEX1"
xx_league_id_LALIGA_2         <- "https://www.transfermarkt.com/laliga2/startseite/wettbewerb/ES2"

# The newest completed season in the cache, and the season every model fits
# through. One knob: the analysis layers take their season ranges from it, so
# rolling the project forward a year is
#   xx_data_populate_league_seasons(<yr>) ; bump this ; re-run the chain.
#
# NOT the same thing as the forward test's holdout year. forward_test.R scores a
# season against grades frozen BEFORE it, and carries its own ft_holdout_season
# plus a frozen BLUP snapshot precisely so that it does not move when this does.
xx_last_data_season <- 2025

# Returns all 20 supported leagues.
xx_all_leagues <- function() {
  c(
    xx_league_id_PREMIER_LEAGUE,
    xx_league_id_LIGUE_1,
    xx_league_id_LA_LIGA,
    xx_league_id_SERIE_A,
    xx_league_id_BUNDESLIGA,
    xx_league_id_PRO_LEAGUE,
    xx_league_id_CHAMPIONSHIP,
    xx_league_id_LIGA_PORTUGAL,
    xx_league_id_EREDIVISIE,
    xx_league_id_SUPERLIGA,
    xx_league_id_EKSTRAKLASA,
    xx_league_id_SUPER_LIG,
    xx_league_id_HNL,
    xx_league_id_LALIGA_2
  )
}

# Returns all league-season entries for a given league (from cache/CSV).
xx_league_seasons <- function(league_id) {
  xx_data_all_league_seasons() |>
    dplyr::filter(.data$league_id == .env$league_id) |>
    dplyr::select(league_name, league_season_id, season_start_year)
}

# Constructs the league-season URL directly from the base league URL and year.
# URL pattern: {league_id}/plus/?saison_id={season_year}
xx_league_season_id <- function(league_id, season_year) {
  paste0(league_id, "/plus/?saison_id=", season_year)
}

# returns all teams for given league_season_id
xx_teams_for_league_season <- function(league_season_id) {
}
  
#######################
# Cached access to tm data
xx_data_read_cache <- function(filename, defaultFrame) {
  tryCatch({
    readRDS(filename)
  }, error = function(e) {
    return(defaultFrame)
  })
}
xx_data_write_cache <- function(db, filename) {
  saveRDS(db, filename) 
}

xx_init_data_cache <- function() {
  dir.create("data/cache", recursive = TRUE, showWarnings = FALSE)
  xx_data_cache <<- list(
    'leagues' = 
      # league_id
      # league_name
      # league_season_id
      # season_start_year
      xx_data_read_cache('data/cache/leagues.rds',
                         data.frame(
                           league_id = character(), 
                           league_name = character(), 
                           league_season_id = character(), 
                           season_start_year = integer()
                         )),
    'teams' = 
      # league_season_id
      # team_season_id
      # team_name
      xx_data_read_cache('data/cache/teams.rds',
                         data.frame(
                           league_season_id = character(),
                           team_season_id = character(),
                           team_name = character()
                         )),
    'players' = 
      # team_season_id
      # player_id
      # player_name
      # player_age
      # player_position
      # minutes_played
      # percent_minutes_played
      # player_market_value_euro
      xx_data_read_cache('data/cache/players.rds',
                         data.frame(
                           team_season_id = character()
                         )),
    'matches' =
      # league_season_id
      # match_id
      # match_date
      # home_team_id
      # away_team_id
      # home_team_goals
      # away_team_goals
      xx_data_read_cache('data/cache/matches.rds',
                         data.frame(
                           league_season_id = character(),
                           match_id         = character(),
                           match_date       = as.Date(character()),
                           home_team_id     = character(),
                           away_team_id     = character(),
                           home_team_goals  = integer(),
                           away_team_goals  = integer()
                         )),
    'coaches' =
      # team_season_id
      # coach_id
      # coach_name
      # date_from
      # date_to
      xx_data_read_cache('data/cache/coaches.rds',
                         data.frame(
                           team_season_id = character(),
                           coach_id       = character(),
                           coach_name     = character(),
                           date_from      = as.Date(character()),
                           date_to        = as.Date(character())
                         ))
  )
}
# Init cache when sourcing this file.
xx_init_data_cache()

xx_data_populate_league_seasons <- function(seasons) {
  leagues <- xx_all_leagues()
  n_leagues <- length(leagues)
  n_seasons <- length(seasons)
  league_num <- 0
  for (league_id in leagues) {
    league_num <- league_num + 1
    season_num <- 0
    for (season_year in seasons) {
      season_num <- season_num + 1
      league_season_id <- xx_league_season_id(league_id, season_year)
      cat(sprintf('[%d/%d leagues | %d/%d seasons] %s\n',
                  league_num, n_leagues, season_num, n_seasons, league_season_id))
      team_season_ids <- xx_data_team_seasons(league_season_id) |>
        dplyr::pull(team_season_id)
      n_teams <- length(team_season_ids)
      team_num <- 0
      for (team_season_id in team_season_ids) {
        team_num <- team_num + 1
        cat(sprintf('  [%d/%d] %s\n', team_num, n_teams, team_season_id))
        xx_data_player_info(team_season_id)
        xx_data_coach(team_season_id)
      }
      xx_matches_for_league_season(league_season_id)
    }
  }
}

xx_refresh_match_dates <- function(seasons = 2015:xx_last_data_season) {
  leagues <- xx_all_leagues()
  n_total <- length(leagues) * length(seasons)
  n <- 0
  for (league_id in leagues) {
    for (season_year in seasons) {
      n <- n + 1
      league_season_id <- xx_league_season_id(league_id, season_year)
      cat(sprintf('[%d/%d] re-scraping match dates for %s\n', n, n_total, league_season_id))
      xx_matches_for_league_season(league_season_id, force_recrawl = TRUE)
    }
  }
  cat('Done. All match dates refreshed.\n')
}

xx_data_populate_team_seasons <- function(league_season_ids) { 
  for (league_season_id in league_season_ids) {
    xx_data_team_seasons(league_season_id)
  }
}
xx_data_populate_team_season_players <- function(team_season_ids) { 
  for (team_season_id in team_season_ids) {
    xx_data_player_info(team_season_id)
  }
}

# All league seasons:
# - league_id
# - league_name
# - season_id
# - season_start_year
xx_data_all_league_seasons <- function() {
  if (nrow(xx_data_cache$leagues) == 0) {
    league_seasons <- xx_raw_all_league_seasons() |> 
      dplyr::select(comp_url, comp_name, season_urls, season_start_year) |>
      dplyr::rename(league_id = comp_url,
                    league_name = comp_name,
                    league_season_id = season_urls)
    xx_data_write_cache(league_seasons, 'data/cache/leagues.rds')
    xx_data_cache$leagues <<- league_seasons
  }
  xx_data_cache$leagues  
}

xx_data_team_seasons <- function(league_season_id, force_recrawl = FALSE) {
  filter_by_league <- function(df) {
    df |> dplyr::filter(.data$league_season_id == .env$league_season_id)
  }
  if (force_recrawl | nrow(xx_data_cache$teams |> filter_by_league()) == 0) {
    team_seasons <- xx_raw_team_seasons(league_season_id) |> 
      mutate(league_season_id = league_season_id)
    cache <- rbind(xx_data_cache$teams, team_seasons)
    xx_data_write_cache(cache, 'data/cache/teams.rds')
    xx_data_cache$teams <<- cache
  }
  xx_data_cache$teams |> 
    filter_by_league() |> 
    dplyr::select(-league_season_id)
}
  
xx_data_player_info <- function(team_season_id, force_recrawl = FALSE) {
  filter_by_team <- function(df) {
    df |> dplyr::filter(.data$team_season_id == .env$team_season_id)
  }
  if (force_recrawl | nrow(xx_data_cache$players |> filter_by_team()) == 0) {
    players <- xx_raw_team_player_info(team_season_id)
    if (nrow(players) == 0) {
      cat('  WARNING: no player data returned for', team_season_id, '-- will retry on next run\n')
    } else {
      players$team_season_id <- team_season_id
      cache <- rbind(xx_data_cache$players, players)
      xx_data_write_cache(cache, 'data/cache/players.rds')
      xx_data_cache$players <<- cache
    }
  }
  xx_data_cache$players |>
    filter_by_team()
}

# returns all matches for given league_season_id
xx_matches_for_league_season <- function(league_season_id, force_recrawl = FALSE) {
  filter_by_league <- function(df) {
    df |> dplyr::filter(.data$league_season_id == .env$league_season_id)
  }
  if (force_recrawl | nrow(xx_data_cache$matches |> filter_by_league()) == 0) {
    cache <- xx_data_cache$matches |> dplyr::filter(.data$league_season_id != .env$league_season_id)
    matches <- xx_raw_league_season_matches(league_season_id)
    cache <- dplyr::bind_rows(cache, matches)
    xx_data_write_cache(cache, 'data/cache/matches.rds')
    xx_data_cache$matches <<- cache
  }
  xx_data_cache$matches |> 
    filter_by_league() |> 
    dplyr::select(-league_season_id)
}

xx_matches_for_team_season <- function(team_season_id, force_recrawl = FALSE) {
  filter_by_team <- function(df) {
    df |> dplyr::filter(home_team_id == team_season_id | away_team_id == team_season_id)
  }
  if (force_recrawl | nrow(xx_data_cache$matches |> filter_by_team()) == 0) {
    cat(team_season_id, 'not in matches cache\n')
    # Cache all league teams for this season.
    # Extract season from end of team_season_id: https://www.transfermarkt.com/real-madrid/startseite/verein/418/saison_id/2024
    season <- as.integer(stringr::str_sub(team_season_id, start = -4, end = -1))
    for (league_id in xx_all_leagues()) {
      league_season_id <- xx_league_season_id(league_id, season)
      xx_data_team_seasons(league_season_id)
    }
    # Find league for this team.
    league_season_id <-  xx_data_cache$teams |>  
      dplyr::filter(.data$team_season_id == .env$team_season_id) |> 
      dplyr::pull(league_season_id)
    print(league_season_id)
    # Cache matches for full league for this team_season
    xx_matches_for_league_season(league_season_id)
  }
  xx_data_cache$matches |> 
    filter_by_team() |> 
    dplyr::select(-league_season_id)
}

xx_data_coach <- function(team_season_id, force_recrawl = FALSE) {
  filter_by_team <- function(df) {
    df |> dplyr::filter(.data$team_season_id == .env$team_season_id)
  }
  if (force_recrawl | nrow(xx_data_cache$coaches |> filter_by_team()) == 0) {
    coach <- xx_raw_team_season_coach(team_season_id)
    cache <- rbind(xx_data_cache$coaches, coach)
    xx_data_write_cache(cache, 'data/cache/coaches.rds')
    xx_data_cache$coaches <<- cache
  }
  xx_data_cache$coaches |> filter_by_team()
}

# Returns the URL of the coach's profile image scraped from their Transfermarkt
# page. Returns NA_character_ if the page cannot be fetched or no image is found.
xx_raw_coach_image_url <- function(coach_id) {
  cat('## fetching coach image URL for', coach_id, '\n')
  Sys.sleep(2)
  page <- xx_fetch_page(coach_id)
  if (is.null(page)) return(NA_character_)
  img <- rvest::html_element(page, "img.data-header__profile-image")
  if (inherits(img, "xml_missing")) {
    cat('  WARNING: no profile image element found\n')
    return(NA_character_)
  }
  src <- rvest::html_attr(img, "src")
  if (is.na(src) || nchar(trimws(src)) == 0) return(NA_character_)
  src
}

# Downloads profile images for all unique coaches in the coaches cache that
# have not yet been downloaded. Images are saved to data/images/coaches/ named
# by the coach's Transfermarkt numeric ID (e.g. 5672.jpg).
#
# A lookup table is maintained at data/cache/coach_images.rds with columns:
#   coach_id   — Transfermarkt profile URL
#   local_path — relative path to the saved image, or NA if no image was found
#
# Coaches already in the lookup (success or confirmed no-image) are skipped.
# Coaches where the download failed due to a network/HTTP error are not recorded
# and will be retried on the next call.
xx_data_populate_coach_images <- function() {
  images_dir  <- "data/images/coaches"
  lookup_path <- "data/cache/coach_images.rds"
  dir.create(images_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(lookup_path)) {
    lookup <- readRDS(lookup_path)
  } else {
    lookup <- data.frame(
      coach_id   = character(),
      local_path = character(),
      stringsAsFactors = FALSE
    )
  }

  todo <- xx_data_cache$coaches |>
    dplyr::distinct(coach_id, coach_name) |>
    dplyr::filter(!is.na(coach_id), nchar(coach_id) > 0) |>
    dplyr::filter(!(coach_id %in% lookup$coach_id))

  cat('## downloading images for', nrow(todo), 'coaches\n')

  for (i in seq_len(nrow(todo))) {
    cid  <- todo$coach_id[i]
    name <- todo$coach_name[i]

    img_url <- xx_raw_coach_image_url(cid)

    if (is.na(img_url)) {
      lookup <- rbind(lookup, data.frame(coach_id = cid, local_path = NA_character_, stringsAsFactors = FALSE))
      saveRDS(lookup, lookup_path)
      next
    }

    numeric_id <- stringr::str_extract(cid, "\\d+$")
    ext        <- tools::file_ext(httr::parse_url(img_url)$path)
    if (nchar(ext) == 0) ext <- "jpg"
    local_path <- file.path(images_dir, paste0(numeric_id, ".", ext))

    tryCatch({
      resp <- httr::GET(
        img_url,
        httr::add_headers(
          `referer`    = "https://www.transfermarkt.com/",
          `user-agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
          `cookie`     = .TM_COOKIE
        ),
        httr::write_disk(local_path, overwrite = TRUE)
      )
      if (!httr::http_error(resp)) {
        cat('  saved:', local_path, '\n')
        lookup <- rbind(lookup, data.frame(coach_id = cid, local_path = local_path, stringsAsFactors = FALSE))
        saveRDS(lookup, lookup_path)
      } else {
        cat('  HTTP', httr::status_code(resp), 'downloading image for', name, '— will retry next run\n')
      }
    }, error = function(e) {
      cat('  ERROR downloading image for', name, ':', conditionMessage(e), '— will retry next run\n')
    })
  }

  invisible(lookup)
}

# Returns a coach's citizenship(s) scraped from their Transfermarkt profile
# page header ("Citizenship:" row). Multiple citizenships are comma-joined,
# first listed = primary. Returns NULL if the page cannot be fetched (caller
# should retry later), NA_character_ if the page loaded but has no citizenship
# row (permanently missing). Added for the coach recommender's plausibility
# filters (Docs/Coach_Recommender_Design.md sec. 6).
xx_raw_coach_nationality <- function(coach_id) {
  cat('## fetching nationality for', coach_id, '\n')
  Sys.sleep(2)
  page <- xx_fetch_page(coach_id)
  if (is.null(page)) return(NULL)
  # header row: <li class="data-header__label">Citizenship:
  #   <span itemprop="nationality"><img class="flaggenrahmen" title="Spain">…
  nat <- rvest::html_element(page, "span[itemprop='nationality']")
  if (!inherits(nat, "xml_missing")) {
    flags <- rvest::html_elements(nat, "img.flaggenrahmen")
    titles <- rvest::html_attr(flags, "title")
    titles <- titles[!is.na(titles) & nchar(trimws(titles)) > 0]
    if (length(titles) > 0) return(paste(unique(trimws(titles)), collapse = ", "))
    txt <- trimws(rvest::html_text(nat))
    if (nchar(txt) > 0) return(txt)
  }
  # fallback: the profile info table has a "Citizenship:" <th> with flag <td>
  ths <- rvest::html_elements(page, xpath = "//th[contains(text(), 'Citizenship')]")
  if (length(ths) > 0) {
    td <- xml2::xml_find_first(ths[[1]], "following-sibling::td")
    if (!inherits(td, "xml_missing")) {
      flags <- rvest::html_elements(td, "img.flaggenrahmen")
      titles <- rvest::html_attr(flags, "title")
      titles <- titles[!is.na(titles) & nchar(trimws(titles)) > 0]
      if (length(titles) > 0) return(paste(unique(trimws(titles)), collapse = ", "))
      txt <- trimws(rvest::html_text(td))
      if (nchar(txt) > 0) return(txt)
    }
  }
  cat('  WARNING: no citizenship row found\n')
  NA_character_
}

# Scrapes citizenship for all unique coaches in the coaches cache that have
# not yet been looked up. Mirrors xx_data_populate_coach_images(): a lookup
# table at data/cache/coach_nationalities.rds with columns:
#   coach_id    — Transfermarkt profile URL
#   nationality — comma-joined citizenship(s), or NA if none found on the page
#
# Coaches already in the lookup (success or confirmed missing) are skipped;
# page-fetch failures are not recorded and retry on the next call. Safe to
# interrupt and re-run.
#   priority_ids — optional coach_id vector scraped first (e.g. the ranked
#     coaches the website shows), so partial runs cover the useful pool.
#   max_failures / backoff_secs — TM intermittently 502s this page type;
#     each failure backs off before retrying the run, and only a long streak
#     aborts (progress is saved either way).
xx_data_populate_coach_nationalities <- function(priority_ids = NULL,
                                                 max_failures = 5,
                                                 backoff_secs = 120) {
  lookup_path <- "data/cache/coach_nationalities.rds"

  if (file.exists(lookup_path)) {
    lookup <- readRDS(lookup_path)
  } else {
    lookup <- data.frame(
      coach_id    = character(),
      nationality = character(),
      stringsAsFactors = FALSE
    )
  }

  todo <- xx_data_cache$coaches |>
    dplyr::distinct(coach_id) |>
    dplyr::filter(!is.na(coach_id), nchar(coach_id) > 0) |>
    dplyr::filter(!(coach_id %in% lookup$coach_id)) |>
    dplyr::arrange(!(coach_id %in% priority_ids))

  cat('## fetching nationality for', nrow(todo), 'coaches\n')

  consecutive_failures <- 0
  for (i in seq_len(nrow(todo))) {
    cid <- todo$coach_id[i]
    cat('[', i, '/', nrow(todo), '] ')
    nat <- xx_raw_coach_nationality(cid)
    # NULL = fetch failure (retry next run); NA = page loaded, no row (record)
    if (is.null(nat)) {
      consecutive_failures <- consecutive_failures + 1
      if (consecutive_failures >= max_failures) {
        cat('## aborting after', max_failures,
            'consecutive failures; progress saved\n')
        break
      }
      cat('  backing off', backoff_secs, 's after failure',
          consecutive_failures, 'of', max_failures, '\n')
      Sys.sleep(backoff_secs)
      next
    }
    consecutive_failures <- 0
    lookup <- rbind(lookup, data.frame(coach_id = cid, nationality = nat,
                                       stringsAsFactors = FALSE))
    saveRDS(lookup, lookup_path)
  }

  invisible(lookup)
}

# Downloads one club's crest to dest_path. Club crests live at a predictable
# Transfermarkt CDN URL keyed by numeric club id (wappen/head/<id>.png,
# verified 2026-07-10 — no page scrape needed; the club page header image is
# a lazy-load placeholder). Added for the website (Docs/Website_Design.md
# sec. 6.1). Returns:
#   "ok"      — crest saved
#   "missing" — 404 on both URL variants (permanently no crest)
#   "retry"   — transient network/HTTP failure; caller should not record it
xx_raw_team_crest <- function(numeric_id, dest_path) {
  cat('## fetching crest for club', numeric_id, '\n')
  Sys.sleep(2)
  for (variant in c("head", "normal")) {
    url <- sprintf("https://tmssl.akamaized.net/images/wappen/%s/%s.png",
                   variant, numeric_id)
    resp <- tryCatch(
      httr::GET(
        url,
        httr::add_headers(
          `referer`    = "https://www.transfermarkt.com/",
          `user-agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"
        ),
        httr::write_disk(dest_path, overwrite = TRUE)
      ),
      error = function(e) NULL
    )
    if (is.null(resp)) { unlink(dest_path); return("retry") }
    code <- httr::status_code(resp)
    # unknown ids return 200 with an empty body, not 404 — treat tiny files
    # as missing and try the next variant
    if (code == 200 && isTRUE(file.size(dest_path) >= 100)) return("ok")
    unlink(dest_path)
    if (code != 404) {
      cat('  HTTP', code, '— will retry next run\n')
      return("retry")
    }
  }
  cat('  404 on both variants — recording as missing\n')
  "missing"
}

# Downloads crest images for all unique clubs in the teams cache (active
# leagues only) that have not yet been downloaded. Crests are saved to
# data/images/crests/ named by the club's Transfermarkt numeric ID (e.g.
# 281.png). Mirrors xx_data_populate_coach_images(): a lookup table at
# data/cache/team_crests.rds records successes and confirmed no-crest clubs
# (both skipped on re-run); transient failures are not recorded and retry on
# the next call. Pass club_ids to scrape a specific set of club page URLs.
xx_data_populate_team_crests <- function(club_ids = NULL) {
  images_dir  <- "data/images/crests"
  lookup_path <- "data/cache/team_crests.rds"
  dir.create(images_dir, recursive = TRUE, showWarnings = FALSE)

  if (is.null(club_ids)) {
    active <- unlist(xx_all_leagues(), use.names = FALSE)
    club_ids <- xx_data_cache$teams |>
      dplyr::filter(purrr::map_lgl(league_season_id,
                                   \(ls) any(startsWith(ls, active)))) |>
      dplyr::mutate(club_id = gsub("/saison_id/\\d+$", "", team_season_id)) |>
      # a club renamed across seasons yields several slug variants of the same
      # numeric id — download each crest once
      dplyr::mutate(numeric_id = stringr::str_extract(club_id, "(?<=/verein/)\\d+")) |>
      dplyr::distinct(numeric_id, .keep_all = TRUE) |>
      dplyr::pull(club_id)
  }

  if (file.exists(lookup_path)) {
    lookup <- readRDS(lookup_path)
  } else {
    lookup <- data.frame(
      club_id    = character(),
      local_path = character(),
      stringsAsFactors = FALSE
    )
  }

  todo <- setdiff(unique(club_ids), lookup$club_id)
  cat('## downloading crests for', length(todo), 'clubs\n')

  for (cid in todo) {
    numeric_id <- stringr::str_extract(cid, "(?<=/verein/)\\d+")
    if (is.na(numeric_id)) {
      cat('  WARNING: no numeric id in', cid, '— skipping\n')
      next
    }
    local_path <- file.path(images_dir, paste0(numeric_id, ".png"))

    status <- xx_raw_team_crest(numeric_id, local_path)
    if (status == "retry") next
    lookup <- rbind(lookup, data.frame(
      club_id    = cid,
      local_path = if (status == "ok") local_path else NA_character_,
      stringsAsFactors = FALSE
    ))
    saveRDS(lookup, lookup_path)
    if (status == "ok") cat('  saved:', local_path, '\n')
  }

  invisible(lookup)
}

# Returns the URL of a player's profile headshot scraped from their
# Transfermarkt page (same data-header element as coach profiles). Added for
# the website team builder (Docs/Team_Builder_Design.md sec. 2.3). Returns
# NULL if the page cannot be fetched (caller should retry later),
# NA_character_ if the page loaded but shows no real photo (missing element
# or the site-wide default-portrait placeholder — permanently missing).
xx_raw_player_image_url <- function(player_id, sleep_secs = 2) {
  cat('## fetching player image URL for', player_id, '\n')
  Sys.sleep(sleep_secs)
  page <- xx_fetch_page(player_id)
  if (is.null(page)) return(NULL)
  img <- rvest::html_element(page, "img.data-header__profile-image")
  if (inherits(img, "xml_missing")) {
    cat('  WARNING: no profile image element found\n')
    return(NA_character_)
  }
  src <- rvest::html_attr(img, "src")
  if (is.na(src) || nchar(trimws(src)) == 0) return(NA_character_)
  # players without a licensed photo get a shared placeholder portrait —
  # record those as missing rather than downloading the same file thousands
  # of times (the frontend has its own initials fallback)
  if (grepl("default", src, ignore.case = TRUE)) {
    cat('  placeholder portrait — recording as missing\n')
    return(NA_character_)
  }
  src
}

# Downloads profile photos for the given players (Transfermarkt profile URLs),
# in the order given — pass a priority-sorted vector so an interrupted run
# covers the most-searched players first. Images are saved to
# data/images/players/ named by the player's Transfermarkt numeric ID.
#
# Mirrors xx_data_populate_coach_nationalities()'s resume semantics (the
# NULL/NA split the coach-image scraper predates): a lookup table at
# data/cache/player_images.rds with columns:
#   player_id  — Transfermarkt profile URL
#   local_path — relative path to the saved image, or NA if confirmed no photo
#
# Players already in the lookup are skipped; page-fetch and download failures
# are not recorded and retry on the next call. TM intermittently 502s profile
# pages: each fetch failure backs off before continuing, and only a streak of
# max_failures aborts (progress saved either way). Safe to interrupt & re-run.
xx_data_populate_player_images <- function(player_ids,
                                           sleep_secs = 2,
                                           max_failures = 5,
                                           backoff_secs = 120) {
  images_dir  <- "data/images/players"
  lookup_path <- "data/cache/player_images.rds"
  dir.create(images_dir, recursive = TRUE, showWarnings = FALSE)

  if (file.exists(lookup_path)) {
    lookup <- readRDS(lookup_path)
  } else {
    lookup <- data.frame(
      player_id  = character(),
      local_path = character(),
      stringsAsFactors = FALSE
    )
  }

  todo <- player_ids[!is.na(player_ids) & nchar(player_ids) > 0]
  todo <- unique(todo)
  todo <- todo[!(todo %in% lookup$player_id)]

  cat('## downloading photos for', length(todo), 'players\n')

  consecutive_failures <- 0
  for (i in seq_along(todo)) {
    pid <- todo[i]
    cat('[', i, '/', length(todo), '] ')

    img_url <- xx_raw_player_image_url(pid, sleep_secs = sleep_secs)

    # NULL = fetch failure (retry next run, with backoff); NA = confirmed none
    if (is.null(img_url)) {
      consecutive_failures <- consecutive_failures + 1
      if (consecutive_failures >= max_failures) {
        cat('## aborting after', max_failures,
            'consecutive failures; progress saved\n')
        break
      }
      cat('  backing off', backoff_secs, 's after failure',
          consecutive_failures, 'of', max_failures, '\n')
      Sys.sleep(backoff_secs)
      next
    }
    consecutive_failures <- 0

    if (is.na(img_url)) {
      lookup <- rbind(lookup, data.frame(player_id = pid,
                                         local_path = NA_character_,
                                         stringsAsFactors = FALSE))
      saveRDS(lookup, lookup_path)
      next
    }

    numeric_id <- stringr::str_extract(pid, "(?<=/spieler/)\\d+")
    if (is.na(numeric_id)) {
      cat('  WARNING: no numeric id in', pid, '— skipping\n')
      next
    }
    ext <- tools::file_ext(httr::parse_url(img_url)$path)
    if (nchar(ext) == 0) ext <- "jpg"
    local_path <- file.path(images_dir, paste0(numeric_id, ".", ext))

    tryCatch({
      resp <- httr::GET(
        img_url,
        httr::add_headers(
          `referer`    = "https://www.transfermarkt.com/",
          `user-agent` = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36",
          `cookie`     = .TM_COOKIE
        ),
        httr::write_disk(local_path, overwrite = TRUE)
      )
      if (!httr::http_error(resp) && isTRUE(file.size(local_path) >= 100)) {
        cat('  saved:', local_path, '\n')
        lookup <- rbind(lookup, data.frame(player_id = pid,
                                           local_path = local_path,
                                           stringsAsFactors = FALSE))
        saveRDS(lookup, lookup_path)
      } else {
        unlink(local_path)
        cat('  HTTP', httr::status_code(resp),
            'or empty body downloading photo — will retry next run\n')
      }
    }, error = function(e) {
      unlink(local_path)
      cat('  ERROR downloading photo:', conditionMessage(e),
          '— will retry next run\n')
    })
  }

  invisible(lookup)
}

# Compute team points given a set of matches.
xx_team_points <- function(matches) {
  if (nrow(matches) == 0) {
    return(data.frame(team_season_id = character(), total_points = integer()))
  }
  points_from_goal_diff <- function(diff) {
    case_when(
      diff > 0 ~ 3,
      diff == 0 ~ 1,
      TRUE ~ 0
    )
  }
  matches |>
    transform(home_team_points = points_from_goal_diff(home_team_goals - away_team_goals),
              away_team_points = points_from_goal_diff(away_team_goals - home_team_goals)) |> 
    purrr::pmap_dfr(function(match_id, home_team_id, away_team_id, home_team_goals, away_team_goals, home_team_points, away_team_points, ...) {
      data.frame(
        team_season_id = c(home_team_id, away_team_id),
        team_points = c(home_team_points, away_team_points)
      ) 
    }) |> 
    group_by(team_season_id) |> 
    summarise(total_points = sum(team_points)) |> 
    arrange(desc(total_points))
}

#######################
# Raw access to tm data
xx_raw_all_league_seasons <- function() {
  cat('## crawling raw_all_league_seasons\n')
  read.csv(url("https://raw.githubusercontent.com/JaseZiv/worldfootballR_data/master/raw-data/transfermarkt_leagues/main_comp_seasons.csv"),
               stringsAsFactors = F)
}

xx_raw_team_seasons <- function(league_season_id) {
  cat('## crawling raw_team_seasons for', league_season_id, '\n')
  Sys.sleep(2)
  host_url <- "https://www.transfermarkt.com"
  season_page <- xx_fetch_page(league_season_id)
  if (is.null(season_page)) return(data.frame(team_season_id = character(), team_name = character()))
  
  season_page |>
    rvest::html_elements("#yw1 .hauptlink a") |> 
    purrr::map_df(function(team_link) {
      data.frame(
        team_season_id = 
          team_link |> 
          rvest::html_attr('href') %>% 
          paste0(host_url, .),
        team_name = 
          team_link |> 
          rvest::html_attr('title')
      )
    }) |> 
    filter(!is.na(team_name))
}

xx_raw_league_season_matches <- function(league_season_id) {
  cat('## crawling raw_league_season_matches for', league_season_id, '\n')
  Sys.sleep(2)
  # Change url of form: https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024
  #     to url of form: https://www.transfermarkt.com/premier-league/gesamtspielplan/wettbewerb/GB1/?saison_id=2024
  league_season_results_url <- sub("startseite", "gesamtspielplan", sub("/plus/","/", league_season_id))
  host_url <- "https://www.transfermarkt.com"
  link_to_team_id <- function(link) {
    paste0(host_url, sub('/spielplan/', '/startseite/', link))
  }
  page <- xx_fetch_page(league_season_results_url)
  if (is.null(page)) return(data.frame(
    match_id = character(), league_season_id = character(),
    match_date = as.Date(character()), home_team_id = character(),
    away_team_id = character(), home_team_goals = integer(), away_team_goals = integer()
  ))
  page |>
    rvest::html_elements('div.large-6 table') |> # one table per season-week
    purrr::map_df(function(week_table) {
      week_table |>
        rvest::html_elements('tr:not(.bg_blau_20):not(:first-child)') |> # one tr per match
        purrr::map_df(function(match_tr) {
          field_tds <- match_tr |> rvest::html_elements('td')
          score_link <- field_tds[5] |> rvest::html_elements('a')
          if (length(score_link) == 0) return(NULL)
          score_parts <- strsplit(rvest::html_text(score_link), ':')[[1]]
          if (length(score_parts) < 2) return(NULL)
          data.frame(
            match_id =
              score_link |>
              rvest::html_attr('href') %>%
              paste0(host_url, .),
            league_season_id = league_season_id,
            match_date =
              field_tds[1] |>
              rvest::html_text(trim = TRUE) |>
              stringr::str_extract("\\d{2}/\\d{2}/\\d{2}") |>
              as.Date(format = "%d/%m/%y"),
            home_team_id =
              field_tds[4] |>
              rvest::html_elements('a') |>
              rvest::html_attr('href') |>
              link_to_team_id(),
            away_team_id =
              field_tds[6] |>
              rvest::html_elements('a') |>
              rvest::html_attr('href') |>
              link_to_team_id(),
            home_team_goals = as.integer(score_parts[1]),
            away_team_goals = as.integer(score_parts[2])
          )
        }) |>
        tidyr::fill(match_date)  # forward-fill date within each week-table
    })
}

xx_raw_team_player_info <- function(team_season_id) {
  cat('## crawling raw_team_player_info for', team_season_id, '\n')
  Sys.sleep(3)
  stats <- xx_raw_squad_stats(team_season_id)
  Sys.sleep(2)
  values <- xx_raw_player_market_value(team_season_id)
  merged <- full_join(stats, values, by = "player_url") |> 
    dplyr::select(player_url, player_name, player_age, player_position, minutes_played, player_market_value_euro) |> 
    dplyr::rename(player_id = player_url)
  
  total_minutes_played = sum(merged$minutes_played)
  merged$percent_minutes_played = merged$minutes_played / total_minutes_played
  merged
}

xx_raw_team_season_coach <- function(team_season_id) {
  cat('## crawling team_season_coach for', team_season_id, '\n')
  Sys.sleep(2)
  host_url <- "https://www.transfermarkt.com"

  empty_result <- data.frame(
    team_season_id = character(),
    coach_id       = character(),
    coach_name     = character(),
    date_from      = as.Date(character()),
    date_to        = as.Date(character())
  )

  page <- xx_fetch_page(team_season_id)
  if (is.null(page)) return(empty_result)

  coach_links <- rvest::html_elements(page, "a[href*='/profil/trainer/']")
  if (length(coach_links) == 0) {
    cat('  WARNING: no coach links found on page\n')
    return(empty_result)
  }

  purrr::map_df(coach_links, function(coach_link) {
    container <- tryCatch(
      rvest::html_element(coach_link, xpath = "ancestor::div[@class='container-content']"),
      error = function(e) NULL
    )
    if (is.null(container) || inherits(container, "xml_missing")) {
      return(NULL)
    }
    tenure_text <- container |>
      rvest::html_element(".container-tenure") |>
      rvest::html_text(trim = TRUE)
    tenure_parts <- stringr::str_split(tenure_text, "–")[[1]] |> stringr::str_trim()
    data.frame(
      team_season_id = team_season_id,
      coach_id       = paste0(host_url, rvest::html_attr(coach_link, "href")),
      coach_name     = rvest::html_text(coach_link, trim = TRUE),
      date_from      = as.Date(tenure_parts[1], format = "%d/%m/%Y"),
      date_to        = suppressWarnings(as.Date(tenure_parts[2], format = "%d/%m/%Y"))
    )
  })
}

xx_raw_squad_stats <- function(team_season_id) {
  # copied from worldfootballR::tm_squad_stats
  host_url <- "https://www.transfermarkt.com"
  team_data_url <- gsub("startseite", "leistungsdaten", team_season_id)
  team_data_page <- xx_fetch_page(team_data_url)
  if (is.null(team_data_page)) {
    return(data.frame(
      player_name     = character(),
      player_url      = character(),
      player_position = character(),
      player_age      = numeric(),
      minutes_played  = numeric(),
      team_name       = character()
    ))
  }
  team_name <-
    team_data_page %>%
    rvest::html_nodes(".data-header__headline-wrapper--oswald") %>% 
    rvest::html_text() %>% 
    stringr::str_squish()
  team_data_table <- 
    team_data_page %>% 
    rvest::html_nodes("#yw1") %>% 
    rvest::html_node("table") %>% 
    rvest::html_nodes("tbody") %>% 
    rvest::html_children()
  
  player_name <- 
    team_data_table %>% 
    rvest::html_nodes(".hauptlink") %>% 
    rvest::html_nodes(".hide-for-small") %>% 
    rvest::html_text()
  player_url <- 
    team_data_table %>% 
    rvest::html_nodes(".hauptlink") %>% 
    rvest::html_nodes(".hide-for-small a") %>% 
    rvest::html_attr("href") %>% 
    paste0(host_url, .)
  player_position <- 
    team_data_table %>% 
    rvest::html_nodes(".inline-table tr+ tr td") %>% 
    rvest::html_text()
  player_age <- 
    team_data_table %>% 
    rvest::html_nodes(".posrela+ .zentriert") %>% 
    rvest::html_text()
  minutes_played <- 
    team_data_table %>% 
    rvest::html_nodes(".rechts") %>% 
    rvest::html_text() %>%
    gsub("\\.", "", .) %>% 
    gsub("'", "", .) %>% 
    gsub("-", "0", .) %>% 
    as.numeric()
  
  team_data_df <- data.frame(player_name = as.character(player_name), 
                             player_url = as.character(player_url), 
                             player_position = as.character(player_position),
                             player_age = as.numeric(player_age), 
                             minutes_played = as.numeric(minutes_played),
                             team_name = as.character(team_name))
  return(team_data_df)
}

xx_raw_player_market_value <- function(team_season_id) {
  # Copied from worldfootballR::tm_each_team_player_market_val
  team_players_url <- gsub("startseite", "kader", team_season_id) %>%
    paste0(., "/plus/1")

  team_page <- xx_fetch_page(team_players_url)
  if (is.null(team_page)) {
    return(data.frame(player_url = character(), player_market_value_euro = numeric()))
  }
  
  team_data <- 
    team_page %>% 
    rvest::html_nodes("#yw1") %>% 
    rvest::html_nodes(".items") %>% 
    rvest::html_node("tbody")
  tab_head_names <- 
    team_page %>% 
    rvest::html_nodes("#yw1") %>% 
    rvest::html_nodes(".items") %>% 
    rvest::html_nodes("th") %>% 
    rvest::html_text()
  
  # player_url
  host_url <- "https://www.transfermarkt.com"
  player_url <- 
    team_data %>% 
    rvest::html_nodes(".inline-table a") %>% 
    rvest::html_attr("href") %>%
    paste0(host_url, .)
  if(length(player_url) == 0) {
    player_url <- NA_character_
  }
  # value
  player_market_value <- 
    team_data %>% 
    rvest::html_nodes(".rechts.hauptlink") %>% 
    rvest::html_text()
  if(length(player_market_value) == 0) {
    player_market_value <- NA_character_
  }
  
  suppressWarnings(team_df <- cbind(player_url, player_market_value) %>% data.frame())
  
  team_df <- team_df |> 
    dplyr::mutate(player_market_value_euro = mapply(.convert_value_to_numeric, player_market_value)) %>%
    dplyr::select(player_url, player_market_value_euro)
  
  return(team_df)
}

# Convert formatted valuations to numeric
# Returns a numeric data type for player valuations
# @param euro_value raw valuation from transfermarkt.com
# @return a cleaned numeric data value for market and/or transfer valuation
# @importFrom magrittr %>%
# @noRd
.convert_value_to_numeric <- function(euro_value) {
  # Copied from worldfootballR/R/internals.R
  clean_val <- gsub("[^\x20-\x7E]", "", euro_value) %>% tolower()
  if(grepl("free", clean_val)) {
    clean_val <- 0
  } else if(grepl("loan fee", clean_val)) {
    clean_val <- suppressWarnings(gsub("loan fee:", "", clean_val)) %>% .convert_value_to_numeric
  } else if(grepl("m", clean_val)) {
    clean_val <- suppressWarnings(gsub("m", "", clean_val) %>% as.numeric() * 1000000)
  } else if(grepl("th.", clean_val)) {
    clean_val <- suppressWarnings(gsub("th.", "", clean_val) %>% as.numeric() * 1000)
  } else if(grepl("k", clean_val)) {
    clean_val <- suppressWarnings(gsub("k", "", clean_val) %>% as.numeric() * 1000)
  } else {
    clean_val <- suppressWarnings(as.numeric(clean_val) * 1)
  }
  return(clean_val)
}
