# install.packages("devtools")
# devtools::install_github("JaseZiv/worldfootballR")
library(worldfootballR)
library(dplyr)

# Top 5 leagues:
#   England's Premier League
#   Spain's La Liga
#   Germany's Bundesliga
#   Italy's Serie A
#   France's Ligue 1


# api docs: https://jaseziv.github.io/worldfootballR/articles/extract-transfermarkt-data.html
# functions:

# tm_league_team_urls()
#   country_name: the country of the league's players
#   start_year: the start year of the season (2020 for the 20/21 season)
#   league_url=NA: league url from transfermarkt.com. To be used when country_name not available in main function
#   returns a character vector of all transfermarkt team URLs for a selected league

# tm_team_staff_urls()
#   team_urls: the staff member's team URL (can be from tm_league_team_urls())
#   staff_role: role of the staff member URLs required for with options including: "Manager"
#   returns a character vector of all transfermarkt staff URLs for a selected team(s)

# tm_team_player_urls()
#   team_url: the staff member's team URL (can be from tm_league_team_urls())
#   returns a character vector of all transfermarkt player URLs for a selected team

# tm_player_bio()
#   player_urls: player url(s) from transfermarkt
#   returns a dataframe of player bios
#     player_name
#     player_id
#     name_in_home_country
#     place_of_birth
#     height
#     citizenship
#     position
#     foot
#     player_agent
#     current_club
#     joined
#     contract_expires
#     player_valuation (current)
#     URL
#     picture_url
#     date_of_birth

# tm_squad_stats()
#   team_url: team url for a season
#   returns a dataframe of all player stats for team
#     team_name
#     league
#     country
#     player_name
#     player_url
#     player_pos
#     player_age
#     nationality
#     in_squad
#     appearances
#     goals
#     minutes_played
#

# tm_each_team_player_market_val()
#   each_team_url: the url of the required team
#   time_pause: the wait time (in seconds) between page loads
#   returns a dataframe of player valuations for a team
#     comp_name (league name)
#     country
#     season_start_year
#     squad
#     player_num
#     player_name
#     player_position
#     player_dob
#     player_age
#     player_nationality
#     current_club
#     player_height_mtrs
#     player_foot
#     date_joined
#     joined_from
#     contract_expiry
#     player_market_value_euro
#     player_url


# tm_matchday_table()
#   country_name: the country of the league's players
#   start_year: the start year of the season (2020 for the 20/21 season)
#   matchday: the matchweek number. Can be a vector of matchdays
#   league_url: league url from transfermarkt.com. To be used when country_name not available in main function
#   returns a dataframe of the table for a selected league and matchday
#     country
#     league
#     matchday (week#)
#     rk (rank)
#     squad (name)
#     p/w/d/l/gf/ga/g_diff
#     pts

# player_dictionary_mapping()
#   returns a dataframe of FBref players and respective Transfermarkt URL

# list all teams in these leagues from 2010-2024
xx_league_seasons <- function(country_names) {
  all_team_seasons <- read.csv(url("https://raw.githubusercontent.com/JaseZiv/worldfootballR_data/master/raw-data/transfermarkt_leagues/main_comp_seasons.csv"),
                      stringsAsFactors = F)
  tryCatch(
    {
      found_team_seasons <- all_team_seasons |> 
        dplyr::filter(.data[["country"]] %in% country_names) 
    }, 
    error = function(e) {found_team_seasons <- data.frame()}
  )
  
  if(nrow(found_team_seasons) == 0) {
    stop(glue::glue("Country {country_names} not found. Check that the country exists at https://github.com/JaseZiv/worldfootballR_data/blob/master/raw-data/transfermarkt_leagues/main_comp_seasons.csv"))
  }
  
  found_team_seasons |> 
    dplyr::select(comp_name, country, season_start_year, season_urls) |>
    dplyr::rename(url = season_urls,
                  league_name = comp_name)
}
xx_team_urls <- function(league_season_url) {
  main_url <- "https://www.transfermarkt.com"
  season_page <- xml2::read_html(league_season_url)
  
  team_urls <- season_page %>%
    rvest::html_nodes("#yw1 .hauptlink a") %>% rvest::html_attr("href") %>%
    # rvest::html_elements("tm-tooltip a") %>% rvest::html_attr("href") %>%
    unique() %>% paste0(main_url, .)
  # there now appears to be an errorneous URL so will remove that manually:
  if(any(grepl("com#", team_urls))) {
    team_urls <- team_urls[-grep(".com#", team_urls)]
  }
  team_urls
}
xx_league_season <- function(league_seasons, country, season) {
  league_seasons |> 
    dplyr::filter(country == .env$country,
                  season_start_year == season) |> 
    dplyr::pull("url")
}
xx_player_info <- function(player_url) {
  tm_player_bio(player_url) |> 
    dplyr::select(player_name, position, player_valuation, date_of_birth) |> 
    dplyr::rename(name = player_name,
                  valuation = player_valuation)
}
xx_team_player_info <- function(team_url) {
  stats <- tm_squad_stats(team_url)
  values <- tm_each_team_player_market_val(team_url)
  merged <- full_join(stats, values, by = "player_url") |> 
    dplyr::select(player_url, player_name.x, player_age.x, player_position, minutes_played, player_market_value_euro) |> 
    dplyr::rename(url = player_url, 
                  name = player_name.x, 
                  age = player_age.x, 
                  position = player_position, 
                  market_value_euro = player_market_value_euro)
  total_minutes_played = sum(merged$minutes_played)
  merged$percent_minutes_played = merged$minutes_played / total_minutes_played
  merged
}

#install.packages("XML")

xx_league_season_games_html <- function(league_season_url) {
  # Change url of form: https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024
  #     to url of form: https://www.transfermarkt.com/premier-league/gesamtspielplan/wettbewerb/GB1/?saison_id=2024
  league_season_results_url <- sub("startseite", "gesamtspielplan", sub("/plus/","/", league_season_url))
  xml2::read_html(league_season_results_url)
}

library(purrr)
xx_league_season_games_from_html <- function(league_season_results_html) {
  weeks <- league_season_results_html |> html_elements('div.large-6 table') # one table per week
  weeks |> purrr::map_df(function(week_table) {
    matches <- week_table |> html_elements('tr:not(.bg_blau_20):not(:first-child)') # one tr per match
    matches |> purrr::map_df(function(match_tr) {
      field_tds <- match_tr |> html_elements('td')
      score_parts <- strsplit(field_tds[5] |> html_elements('a') |> html_text(), ':')[[1]]
      data.frame(
        HomeTeamUrl = field_tds[4] |> html_elements('a') |> html_attr('href'),
        AwayTeamUrl = field_tds[6] |> html_elements('a') |> html_attr('href'),
        HomeTeamScore = as.integer(score_parts[1]),
        AwayTeamScore = as.integer(score_parts[2])
      )
    })
  })
}
xx_league_season_games <- function(league_season_url) {
  xx_league_season_games_html(league_season_url) |> 
    xx_league_season_games_from_html()
}
xx_team_points <- function(games) {
  points_from_goal_diff <- function(diff) {
    case_when(
      diff > 0 ~ 3,
      diff == 0 ~ 1,
      TRUE ~ 0
    )
  }
  games |> 
    transform(HomeTeamPoints = points_from_goal_diff(HomeTeamScore - AwayTeamScore),
              AwayTeamPoints = points_from_goal_diff(AwayTeamScore - HomeTeamScore)) |> 
    purrr::pmap_dfr(function(HomeTeamUrl, AwayTeamUrl, HomeTeamScore, AwayTeamScore, HomeTeamPoints, AwayTeamPoints) {
      data.frame(
        TeamUrl = c(HomeTeamUrl, AwayTeamUrl),
        TeamPoints = c(HomeTeamPoints, AwayTeamPoints)
      ) 
    }) |> 
    group_by(TeamUrl) |> 
    summarise(TotalPoints = sum(TeamPoints)) |> 
    arrange(desc(TotalPoints))
}
