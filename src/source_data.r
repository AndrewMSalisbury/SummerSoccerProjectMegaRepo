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

httr::set_config(httr::user_agent(
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"
))

# Individual leagues
xx_league_id_PREMIER_LEAGUE <- "https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1"
xx_league_id_LIGUE_1 <- "https://www.transfermarkt.com/ligue-1/startseite/wettbewerb/FR1"
xx_league_id_LA_LIGA <- "https://www.transfermarkt.com/laliga/startseite/wettbewerb/ES1"
xx_league_id_SERIE_A <- "https://www.transfermarkt.com/serie-a/startseite/wettbewerb/IT1"
xx_league_id_BUNDESLIGA <- "https://www.transfermarkt.com/bundesliga/startseite/wettbewerb/L1"

# list all available leagues
xx_all_leagues <- function() {
  c(
    xx_league_id_PREMIER_LEAGUE,
    xx_league_id_LIGUE_1,
    xx_league_id_LA_LIGA,
    xx_league_id_SERIE_A,
    xx_league_id_BUNDESLIGA
  )
}

# returns all league_season_ids for the given league
xx_league_seasons <- function(league_id) {
  xx_data_all_league_seasons() |> 
    dplyr::filter(.data$league_id == .env$league_id) |> 
    dplyr::select(league_name, league_season_id, season_start_year)
}

xx_league_season_id <- function(league_id, season_year) {
  xx_data_all_league_seasons() |> 
    dplyr::filter(.data$league_id == .env$league_id &
                  .data$season_start_year == season_year) |> 
    dplyr::pull(league_season_id)
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

xx_refresh_match_dates <- function(seasons = 2015:2024) {
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

# Compute team points given a set of matches.
xx_team_points <- function(matches) {
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
    purrr::pmap_dfr(function(match_id, home_team_id, away_team_id, home_team_goals, away_team_goals, home_team_points, away_team_points) {
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
  Sys.sleep(10)
  host_url <- "https://www.transfermarkt.com"
  season_page <- tryCatch(
    xml2::read_html(league_season_id),
    error = function(e) {
      cat('  ERROR loading league season page:', conditionMessage(e), '\n')
      NULL
    }
  )
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
  Sys.sleep(5)
  # Change url of form: https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024
  #     to url of form: https://www.transfermarkt.com/premier-league/gesamtspielplan/wettbewerb/GB1/?saison_id=2024
  league_season_results_url <- sub("startseite", "gesamtspielplan", sub("/plus/","/", league_season_id))
  host_url <- "https://www.transfermarkt.com"
  link_to_team_id <- function(link) {
    paste0(host_url, sub('/spielplan/', '/startseite/', link))
  }
  xml2::read_html(league_season_results_url) |>
    rvest::html_elements('div.large-6 table') |> # one table per season-week
    purrr::map_df(function(week_table) {
      week_table |>
        rvest::html_elements('tr:not(.bg_blau_20):not(:first-child)') |> # one tr per match
        purrr::map_df(function(match_tr) {
          field_tds <- match_tr |> rvest::html_elements('td')
          score_link <- field_tds[5] |> rvest::html_elements('a')
          score_parts <- strsplit(score_link |> rvest::html_text(), ':')[[1]]
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
  Sys.sleep(15)
  stats <- xx_raw_squad_stats(team_season_id)
  Sys.sleep(10)
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
  Sys.sleep(10)
  host_url <- "https://www.transfermarkt.com"

  empty_result <- data.frame(
    team_season_id = character(),
    coach_id       = character(),
    coach_name     = character(),
    date_from      = as.Date(character()),
    date_to        = as.Date(character())
  )

  page <- tryCatch(
    xml2::read_html(team_season_id),
    error = function(e) {
      cat('  ERROR loading page:', conditionMessage(e), '\n')
      NULL
    }
  )
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
  team_data_page <- tryCatch(xml2::read_html(team_data_url), error = function(e) {
    cat('  ERROR loading squad stats page:', conditionMessage(e), '\n')
    NULL
  })
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

  team_page <- tryCatch(
    xml2::read_html(team_players_url),
    error = function(e) {
      cat('  ERROR loading market value page:', conditionMessage(e), '\n')
      NULL
    }
  )
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
