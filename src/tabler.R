# install.packages("DescTools")
library(DescTools)

league_player_info <- function(league_season_url) {
  xx_data_team_seasons(league_season_url) |> 
    purrr::pmap_dfr(function(team_season_id, team_name) {
      xx_data_player_info(team_season_id) |> 
        mutate(team_name = team_name)
    })
}
italy_2024 <- xx_league_season_id(xx_league_id_SERIE_A, 2024)
italy_2024_players <- league_player_info(italy_2024)
italy_2024_matches <- xx_matches_for_league_season(italy_2024)
italy_2024_team_points <- xx_team_points(italy_2024_matches)

italy_2024_team_chart <- italy_2024_players |>
  transform(minute_value = player_market_value_euro * percent_minutes_played) |>
  group_by(team_name) |>
  summarize(total_team_value = sum(player_market_value_euro, na.rm = TRUE), 
            weighted_team_value = sum(minute_value, na.rm = TRUE),
            team_season_id = first(team_season_id))
italy_2024_model <- lm(weighted_team_value ~ total_team_value, italy_2024_team_chart)
italy_2024_team_chart <- italy_2024_team_chart |>
  mutate(predicted = predict(italy_2024_model, newdata = select(italy_2024_team_chart, total_team_value)),
         weighted_team_value = ifelse(weighted_team_value == 0, 
                                                      predicted, 
                                                      weighted_team_value))|>
  mutate(total_value_rank = rank(desc(total_team_value)),
         weighted_value_rank = rank(desc(weighted_team_value))) |> 
  full_join(italy_2024_team_points, by = "team_season_id") |> 
  mutate(points_rank = rank(desc(total_points), ties.method = "min")) |>
  select(-predicted)


league_season_team_chart <- function(league_season_id, min_minutes_pct = 0) {
  players <- league_player_info(league_season_id)
  matches <- xx_matches_for_league_season(league_season_id)
  team_points <- xx_team_points(matches)

  games_played <- rbind(
    matches |> select(team_season_id = home_team_id),
    matches |> select(team_season_id = away_team_id)
  ) |>
    group_by(team_season_id) |>
    summarize(games_played = n())

  # min_minutes_pct filters to players who played >= that fraction of their
  # team's available playing time (games_played * 90 minutes), not squad share.
  if (min_minutes_pct > 0) {
    players <- players |>
      left_join(games_played, by = "team_season_id") |>
      filter(minutes_played >= games_played * 90 * min_minutes_pct) |>
      select(-games_played)
  }

  team_chart <- players |>
    transform(minute_value = player_market_value_euro * percent_minutes_played) |>
    group_by(team_name) |>
    summarize(total_team_value = sum(player_market_value_euro, na.rm = TRUE),
              weighted_team_value = sum(minute_value, na.rm = TRUE),
              team_season_id = first(team_season_id))
  model <- lm(weighted_team_value ~ total_team_value, team_chart)
  team_chart |>
    mutate(predicted = predict(model, newdata = select(team_chart, total_team_value)),
           weighted_team_value = ifelse(weighted_team_value == 0,
                                        predicted,
                                        weighted_team_value)) |>
    mutate(total_value_rank = rank(desc(total_team_value)),
           weighted_value_rank = rank(desc(weighted_team_value))) |>
    full_join(team_points, by = "team_season_id") |>
    full_join(games_played, by = "team_season_id") |>
    mutate(points_rank = rank(desc(total_points), ties.method = "min")) |>
    select(-predicted)
}

league_season_correlations <- function(league_season_id) {
  team_chart <- league_season_team_chart(league_season_id)
  unweighted_correlation <- cor.test(x = team_chart$total_value_rank, y = team_chart$points_rank, method=c("pearson"), conf.level = 0.95)[["estimate"]]
  weighted_correlation <- cor.test(x = team_chart$weighted_value_rank, y = team_chart$points_rank, method=c("pearson"), conf.level = 0.95)[["estimate"]]
  correlations <- data.frame(unweighted_correlation = unweighted_correlation, weighted_correlation = weighted_correlation)
  rownames(correlations) <- NULL
  correlations
}

# Example of walking through the league-seasons.
all_correlations <- function(){  
  correlation_sheet <- data.frame()
  for(league_id in xx_all_leagues()) {
    for(season in 2015:xx_last_data_season) {
      league_season_id <- xx_league_season_id(league_id, season)
      lsc <- league_season_correlations(league_season_id)
      lsc$league <- strsplit(league_season_id, split = "/")[[1]][4]
      lsc$season <-season
      correlation_sheet <- rbind(correlation_sheet, lsc)
    }
  }
  correlation_sheet |>
    select(league,season,everything())
}

average_correlation <- function(correlations) {
  FisherZInv(mean(sapply(correlations, FisherZ)))
}