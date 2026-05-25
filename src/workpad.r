countries <- c("Italy", "England", "Germany", "Spain", "France")
league_seasons <- xx_league_seasons(countries)
italy_2024 <- league_seasons |> xx_league_season("Italy", "2024")
spain_2024 <- league_seasons |> xx_league_season("Spain", "2024")
italy_2024_teams <- xx_team_urls(italy_2024)
italy_team = italy_2024_teams[1]
italy_team2 = italy_2024_teams[2]
italy_team_player_urls = tm_team_player_urls(italy_team)
italy_player_url = italy_team_player_urls[1]
italy_player_bio = tm_player_bio(italy_player_url)
italy_player_info = xx_player_info(italy_player_url)
italy_players_info = xx_player_info(italy_team_player_urls)
italy_team_stats = tm_squad_stats(italy_team)
italy_team_full <- merge(italy_team_stats, italy_team_value, by = "player_url")
italy_team_player_info <- xx_team_player_info(italy_team)
spain_team <- xx_team_urls(spain_2024)[1]
spain_team_player_info <- xx_team_player_info(spain_team)

spain_2024_games <- xx_league_season_games(spain_2024)
spain_2024_team_points <- xx_team_points(spain_2024_games)

# For a whole league season:
# first, get all the team URLs for 
italy_team_urls <- tm_league_team_urls(country_name = "Italy", start_year = 2024)
england_team_urls <- tm_league_team_urls(country_name = "England", start_year = 2024)
germany_team_urls <- tm_league_team_urls(country_name = "Germany", start_year = 2024)
spain_team_urls <- tm_league_team_urls(country_name = "Spain", start_year = 2024)
france_team_urls <- tm_league_team_urls(country_name = "France", start_year = 2024)

mancity_matches <- fb_team_match_results("https://fbref.com/en/squads/b8fd03ef/Manchester-City-Stats")
big_5_2020_results <- fb_match_results(country = c("ENG", "ESP", "ITA", "GER", "FRA"),
                                       gender = "M", season_end_year = 2020, tier = "1st")
epl_2021_team_urls <- fb_teams_urls("https://fbref.com/en/comps/9/Premier-League-Stats")
epl_2021_team_results <- fb_team_match_results(team_url = epl_2021_team_urls) # too many requests from fbref
epl_2021_team_results <- fb_team_match_results(team_url = epl_2021_team_urls[1])
