# player_archetypes.R
#
# Milestone 6, step 1-2: per-player-season style features from the SofaScore
# caches, and k-means archetype clustering within broad position groups.
#
# Functions use the pa_ prefix. Pure cache-reader: no scraping, no chromote —
# everything runs off data/cache/sofascore/ (working directory src/).
#
# Feature design principles:
#   - style, not quality: volumes, locations, and mix shares; no goals/assists,
#     no ratings. Accuracy/win percentages are kept where they describe a risk
#     profile (long passers trade accuracy for range).
#   - no xG anywhere: xG only exists from mid-2021/22, so any xG feature would
#     make early and late seasons incomparable. Shot locations substitute.
#   - per-90 normalization from season minutesPlayed; shares where a volume
#     would double-count overall involvement.

library(dplyr)
library(tidyr)

# SofaScore season ids, keyed by season start year. Kept in sync with
# source_sofascore.r, which is not sourced here because it loads {chromote} —
# this file must run in analysis-only sessions.
if (!exists("ss_pl_season_ids")) {
  ss_pl_season_ids <- c(
    "2015" = 10356, "2016" = 11733, "2017" = 13380, "2018" = 17359,
    "2019" = 23776, "2020" = 29415, "2021" = 37036, "2022" = 41886,
    "2023" = 52186, "2024" = 61627
  )
}
if (!exists("ss_big5_leagues")) {
  ss_big5_leagues <- list(
    premier_league = list(ut = 17, seasons = ss_pl_season_ids),
    la_liga = list(ut = 8, seasons = c(
      "2015" = 10495, "2016" = 11906, "2017" = 13662, "2018" = 18020,
      "2019" = 24127, "2020" = 32501, "2021" = 37223, "2022" = 42409,
      "2023" = 52376, "2024" = 61643
    )),
    serie_a = list(ut = 23, seasons = c(
      "2015" = 10596, "2016" = 11966, "2017" = 13768, "2018" = 17932,
      "2019" = 24644, "2020" = 32523, "2021" = 37475, "2022" = 42415,
      "2023" = 52760, "2024" = 63515
    )),
    bundesliga = list(ut = 35, seasons = c(
      "2015" = 10419, "2016" = 11818, "2017" = 13477, "2018" = 17597,
      "2019" = 23538, "2020" = 28210, "2021" = 37166, "2022" = 42268,
      "2023" = 52608, "2024" = 63516
    )),
    ligue_1 = list(ut = 34, seasons = c(
      "2015" = 10373, "2016" = 11648, "2017" = 13384, "2018" = 17279,
      "2019" = 23872, "2020" = 28222, "2021" = 37167, "2022" = 42273,
      "2023" = 52571, "2024" = 61736
    ))
  )
}

pa_cache_dir <- "data/cache/sofascore"

pa_read <- function(kind, season_ss_id) {
  readRDS(file.path(pa_cache_dir, paste0(kind, "_", season_ss_id, ".rds")))
}

# --- position groups -----------------------------------------------------------

# Minutes-weighted modal position (G/D/M/F) per player from per-match lineups.
# A player listed as D in some matches and M in others gets whichever role
# they spent more minutes in.
pa_position_groups <- function(season_ss_id) {
  ms <- pa_read("match_stats", season_ss_id)

  mins <- ms |>
    filter(stat_name == "minutesPlayed") |>
    select(event_ss_id, player_ss_id, position, minutes = stat_value)

  mins |>
    group_by(player_ss_id, position) |>
    summarize(minutes = sum(minutes, na.rm = TRUE), .groups = "drop") |>
    group_by(player_ss_id) |>
    slice_max(minutes, n = 1, with_ties = FALSE) |>
    ungroup() |>
    select(player_ss_id, position_group = position)
}

# --- heatmap descriptors ---------------------------------------------------------

# Count-weighted shape descriptors of a player's season heatmap. Coordinates
# are on a 0-100 grid, attack normalized toward x = 100 (verified empirically:
# strikers' centroids sit ~15 units higher in x than centre-backs').
# Lateral features are folded around y = 50 so left- and right-sided players
# with mirror-image roles land in the same archetype.
pa_heatmap_features <- function(season_ss_id) {
  hm <- pa_read("heatmap", season_ss_id)

  hm |>
    group_by(player_ss_id) |>
    summarize(
      hm_depth        = sum(x * count) / sum(count),
      hm_spread_x     = sqrt(sum(count * (x - hm_depth)^2) / sum(count)),
      hm_wideness     = sum(abs(y - 50) * count) / sum(count),
      hm_spread_y     = sqrt(sum(count * (y - sum(y * count) / sum(count))^2) /
                               sum(count)),
      hm_att_third    = sum(count[x >= 200 / 3]) / sum(count),
      hm_def_third    = sum(count[x <= 100 / 3]) / sum(count),
      hm_wide_share   = sum(count[y <= 25 | y >= 75]) / sum(count),
      hm_opp_box      = sum(count[x >= 84 & y >= 19 & y <= 81]) / sum(count),
      .groups = "drop"
    )
}

# --- season statistics profile ---------------------------------------------------

# The season stat fields used for features. Everything else in the ~110-field
# table (ratings, goals, conversion rates, GK stats) is deliberately unused.
pa_stat_fields <- c(
  "minutesPlayed", "appearances",
  "totalPasses", "accuratePassesPercentage", "totalLongBalls",
  "accurateLongBallsPercentage", "totalCross", "accurateCrossesPercentage",
  "accurateFinalThirdPasses", "totalChippedPasses", "keyPasses",
  "bigChancesCreated", "totalOppositionHalfPasses", "totalOwnHalfPasses",
  "totalContest", "successfulDribblesPercentage", "dispossessed",
  "possessionLost", "touches", "wasFouled",
  # outfielderBlocks (2023/24 only) and ballRecovery (2023/24-2024/25 only)
  # are excluded: features must exist in every season to be comparable
  "tackles", "interceptions", "clearances",
  "possessionWonAttThird", "dribbledPast", "fouls",
  "aerialDuelsWon", "aerialLost", "aerialDuelsWonPercentage",
  "totalDuelsWon", "duelLost"
)

pa_stat_features <- function(season_ss_id) {
  st <- pa_read("stats", season_ss_id) |>
    filter(stat_name %in% pa_stat_fields) |>
    pivot_wider(id_cols = player_ss_id,
                names_from = stat_name, values_from = stat_value)

  # ensure every field exists even if absent from this season's cache
  for (f in setdiff(pa_stat_fields, names(st))) st[[f]] <- NA_real_

  p90 <- function(x) x / st$minutesPlayed * 90

  st |>
    transmute(
      player_ss_id,
      minutes             = minutesPlayed,
      pass_p90            = p90(totalPasses),
      pass_acc_pct        = accuratePassesPercentage,
      long_ball_p90       = p90(totalLongBalls),
      long_ball_acc_pct   = accurateLongBallsPercentage,
      cross_p90           = p90(totalCross),
      final_third_pass_p90 = p90(accurateFinalThirdPasses),
      chipped_pass_p90    = p90(totalChippedPasses),
      key_pass_p90        = p90(keyPasses),
      big_chance_created_p90 = p90(bigChancesCreated),
      opp_half_pass_share = totalOppositionHalfPasses /
        (totalOppositionHalfPasses + totalOwnHalfPasses),
      dribble_p90         = p90(totalContest),
      dribble_succ_pct    = successfulDribblesPercentage,
      dispossessed_p90    = p90(dispossessed),
      poss_lost_p90       = p90(possessionLost),
      touches_p90         = p90(touches),
      was_fouled_p90      = p90(wasFouled),
      tackle_p90          = p90(tackles),
      interception_p90    = p90(interceptions),
      clearance_p90       = p90(clearances),
      poss_won_att3_p90   = p90(possessionWonAttThird),
      dribbled_past_p90   = p90(dribbledPast),
      fouls_p90           = p90(fouls),
      # aerial attempts reconstruct cleanly; ground attempts fall out of
      # total duels minus aerial duels (no groundDuels-attempted field exists)
      aerial_duel_p90     = p90(aerialDuelsWon + aerialLost),
      aerial_won_pct      = aerialDuelsWonPercentage,
      ground_duel_p90     = p90((totalDuelsWon + duelLost) -
                                  (aerialDuelsWon + aerialLost))
    )
}

# --- shot profile ----------------------------------------------------------------

# Location and body-part mix of a player's shots. Penalties are excluded —
# they say who takes penalties, not where a player shoots from in open play.
# Shot coordinates do NOT share the heatmap convention: the goal under attack
# sits at (0, 50) and x measures distance from the goal line (verified: median
# shot x = 12.8, the box edge lands near x = 16). Distances are in grid units,
# monotone in true distance — fine for a style feature.
pa_shot_features <- function(season_ss_id) {
  sh <- pa_read("shots", season_ss_id) |>
    filter(is.na(situation) | situation != "penalty")

  sh |>
    group_by(player_ss_id) |>
    summarize(
      shot_count        = n(),
      shot_dist_mean    = mean(sqrt(x^2 + (y - 50)^2)),
      shot_box_share    = mean(x <= 16),
      shot_central_share = mean(abs(y - 50) <= 15),
      shot_header_share = mean(body_part == "head", na.rm = TRUE),
      .groups = "drop"
    )
}

# --- assembly --------------------------------------------------------------------

# One row per qualifying player-season across all big-5 league-seasons.
#   min_minutes — a player-season needs at least this many league minutes to
#                 receive features (600 keeps ~2/3 of players and the vast
#                 majority of minutes; sub-threshold profiles are rate noise).
# Goalkeepers are excluded: their stat profile is a different universe and
# their share of the coach-fit composition is handled separately if needed.
pa_build_features <- function(leagues = ss_big5_leagues, min_minutes = 600) {
  rows <- list()
  for (league_key in names(leagues)) {
    for (yr in names(leagues[[league_key]]$seasons)) {
      sid <- leagues[[league_key]]$seasons[[yr]]
      players <- pa_read("players", sid)

      feats <- players |>
        select(season_ss_id, player_ss_id, player_name, team_ss_id, team_name) |>
        mutate(league = league_key, season_start_year = as.integer(yr)) |>
        inner_join(pa_position_groups(sid), by = "player_ss_id") |>
        left_join(pa_stat_features(sid),    by = "player_ss_id") |>
        left_join(pa_heatmap_features(sid), by = "player_ss_id") |>
        left_join(pa_shot_features(sid),    by = "player_ss_id")

      rows[[paste(league_key, yr)]] <- feats |>
        mutate(
          shot_count = coalesce(shot_count, 0L),
          shot_p90   = shot_count / minutes * 90
        ) |>
        filter(position_group != "G", !is.na(minutes), minutes >= min_minutes)
    }
  }
  bind_rows(rows)
}

pa_feature_cols <- function(features) {
  setdiff(
    names(features)[vapply(features, is.numeric, logical(1))],
    c("season_ss_id", "player_ss_id", "team_ss_id", "season_start_year",
      "minutes", "shot_count")
  )
}

# Imputes remaining NAs (e.g. cross accuracy for players who never crossed,
# shot location for players who never shot) with the league × season ×
# position-group median, then z-scores each feature within league × season ×
# position group. Z-scoring within league as well as season means a player is
# described relative to contemporaries in the same competition — otherwise
# systematic league differences in pace and volume (Serie A passes more,
# Bundesliga presses higher) would dominate the clusters and archetypes would
# degenerate into league labels.
pa_zscore_features <- function(features) {
  cols <- pa_feature_cols(features)

  features |>
    group_by(league, season_start_year, position_group) |>
    mutate(across(all_of(cols), function(x) {
      x <- ifelse(is.na(x) | is.nan(x), median(x, na.rm = TRUE), x)
      s <- sd(x)
      if (is.na(s) || s == 0) 0 else (x - mean(x)) / s
    })) |>
    ungroup()
}

# --- clustering ------------------------------------------------------------------

# k-means for one position group's z-matrix at one k, deterministic via seed.
pa_kmeans <- function(m, k, seed = 6) {
  set.seed(seed)
  kmeans(m, centers = k, nstart = 25, iter.max = 50)
}

# Split-half stability: cluster 2015-2019 and 2020-2024 separately at the same
# k, assign each half's players to the *other* half's nearest centroid, and
# measure agreement with the half's own clustering (adjusted Rand index,
# averaged over both directions). High ARI means the same player types exist
# in both halves of the decade — the clusters are structure, not noise.
pa_split_stability <- function(m, seasons, k, seed = 6) {
  early <- seasons <= 2019
  km_e <- pa_kmeans(m[early, , drop = FALSE], k, seed)
  km_l <- pa_kmeans(m[!early, , drop = FALSE], k, seed)

  nearest <- function(m_part, centers) {
    apply(m_part, 1, function(r) {
      which.min(colSums((t(centers) - r)^2))
    })
  }
  ari <- function(a, b) {
    # adjusted Rand index from the contingency table
    tab <- table(a, b)
    n <- sum(tab)
    sum_comb <- function(x) sum(choose(x, 2))
    idx <- sum_comb(tab)
    row_c <- sum_comb(rowSums(tab)); col_c <- sum_comb(colSums(tab))
    expected <- row_c * col_c / choose(n, 2)
    (idx - expected) / ((row_c + col_c) / 2 - expected)
  }

  mean(c(
    ari(km_e$cluster, nearest(m[early, , drop = FALSE], km_l$centers)),
    ari(km_l$cluster, nearest(m[!early, , drop = FALSE], km_e$centers))
  ))
}

# Clusters each position group's player-seasons into archetypes.
# For every k in k_range, reports average silhouette width and split-half
# stability; picks the k with the best silhouette unless a fixed k is given
# via k_fixed (e.g. c(D = 3, M = 4, F = 3) after eyeballing diagnostics).
# Returns list(assignments = <features + archetype col>, diagnostics, centers).
pa_cluster_archetypes <- function(features, k_range = 2:5, k_fixed = NULL,
                                  seed = 6) {
  z <- pa_zscore_features(features)
  cols <- pa_feature_cols(features)

  diagnostics <- list(); assignments <- list(); centers <- list()

  for (grp in sort(unique(z$position_group))) {
    zg <- z |> filter(position_group == grp)
    m  <- as.matrix(zg[cols])

    diag_g <- data.frame(position_group = grp, k = k_range,
                         silhouette = NA_real_, stability = NA_real_)
    dm <- dist(m)
    for (i in seq_along(k_range)) {
      k  <- k_range[i]
      km <- pa_kmeans(m, k, seed)
      diag_g$silhouette[i] <- mean(cluster::silhouette(km$cluster, dm)[, 3])
      diag_g$stability[i]  <- pa_split_stability(m, zg$season_start_year, k, seed)
    }

    k_use <- if (!is.null(k_fixed) && grp %in% names(k_fixed)) {
      k_fixed[[grp]]
    } else {
      diag_g$k[which.max(diag_g$silhouette)]
    }
    km <- pa_kmeans(m, k_use, seed)

    # stable archetype ids: order clusters by mean heatmap depth so labels
    # don't reshuffle when k-means happens to permute cluster numbers
    depth_order <- order(tapply(zg$hm_depth, km$cluster, mean))
    relabel <- match(seq_len(k_use), depth_order)
    diag_g$k_chosen <- k_use

    assignments[[grp]] <- zg |>
      select(season_ss_id, player_ss_id, player_name, team_name,
             league, season_start_year, position_group, minutes) |>
      mutate(
        archetype = paste0(grp, relabel[km$cluster]),
        archetype_label = unname(pa_archetype_labels[archetype])
      )
    centers[[grp]] <- km$centers[depth_order, , drop = FALSE]
    rownames(centers[[grp]]) <- paste0(grp, seq_len(k_use))
    diagnostics[[grp]] <- diag_g
  }

  list(
    assignments = bind_rows(assignments),
    diagnostics = bind_rows(diagnostics),
    centers     = centers
  )
}

# --- interpretation --------------------------------------------------------------

# Prints, per archetype: the most distinguishing features (largest |z| centre
# coordinates) and the highest-minutes example players, so the archetypes can
# be named and face-checked by hand.
pa_label_archetypes <- function(clusters, n_features = 8, n_players = 10) {
  for (grp in names(clusters$centers)) {
    ctr <- clusters$centers[[grp]]
    for (a in rownames(ctr)) {
      cat("\n=== ", a, " ===\n", sep = "")
      z_sorted <- sort(ctr[a, ], decreasing = TRUE)
      top <- head(z_sorted, n_features); bot <- rev(tail(z_sorted, n_features))
      cat("  high:", paste0(names(top), " (", round(top, 2), ")",
                            collapse = ", "), "\n")
      cat("  low: ", paste0(names(bot), " (", round(bot, 2), ")",
                            collapse = ", "), "\n")
      ex <- clusters$assignments |>
        filter(archetype == a) |>
        group_by(player_name) |>
        summarize(minutes = sum(minutes), seasons = n(), .groups = "drop") |>
        slice_max(minutes, n = n_players)
      cat("  e.g.:", paste0(ex$player_name, " (", ex$seasons, ")",
                            collapse = ", "), "\n")
    }
  }
  invisible(clusters)
}

# Where did well-known players land? Quick face-validity table.
pa_face_validity <- function(clusters,
                             players = c("Virgil van Dijk", "Harry Maguire",
                                         "Trent Alexander-Arnold",
                                         "Andrew Robertson", "Kyle Walker",
                                         "N'Golo Kanté", "Rodri", "Jordan Henderson",
                                         "Kevin De Bruyne", "Mesut Özil",
                                         "Jack Grealish", "Riyad Mahrez",
                                         "Mohamed Salah", "Sadio Mané",
                                         "Erling Haaland", "Harry Kane",
                                         "Jamie Vardy", "Olivier Giroud",
                                         # non-PL anchors for the big-5 run
                                         "Lionel Messi", "Sergio Ramos",
                                         "Sergio Busquets", "Toni Kroos",
                                         "Giorgio Chiellini", "Jorginho",
                                         "Robert Lewandowski", "Thomas Müller",
                                         "Kylian Mbappé", "Ángel Di María",
                                         "Ciro Immobile", "Manuel Lazzari",
                                         "Joshua Kimmich", "Filip Kostić")) {
  clusters$assignments |>
    filter(player_name %in% players) |>
    arrange(player_name, season_start_year) |>
    group_by(player_name, position_group, archetype) |>
    summarize(seasons = paste(sort(unique(season_start_year)), collapse = ","),
              .groups = "drop") |>
    arrange(position_group, archetype, player_name)
}

# Human-readable archetype names for the seeded (seed = 6) D=4/M=4/F=3 run on
# the full big-5 dataset (relabeled 2026-07-12; the PL-only pilot had
# different M-group semantics). Ids are ordered by mean heatmap depth, so they
# are stable across re-runs of the same data + seed; if either changes,
# re-verify with pa_label_archetypes() before trusting these names.
# M3 (wing-back) only emerged with the big-5 data — back-3 systems are too
# rare in the PL for the pilot to have found it.
pa_archetype_labels <- c(
  D1 = "no-nonsense CB",    D2 = "ball-playing CB",
  D3 = "defensive fullback", D4 = "attacking fullback",
  M1 = "destroyer",          M2 = "deep playmaker",
  M3 = "wing-back",          M4 = "advanced creator",
  F1 = "pressing forward",   F2 = "box striker",
  F3 = "wide creator"
)

# --- orchestrator ----------------------------------------------------------------

# Builds features, clusters, prints diagnostics and labels, and caches the
# per-player-season archetype assignments to data/cache/sofascore/archetypes.rds.
# Default k per group chosen 2026-07-09: the finer cut is less stable than
# k = 2 (split-half ARI 0.32-0.68 vs 0.76-0.97) but yields football-native
# styles within roles (e.g. ball-playing vs no-nonsense CB) — accepted as a
# documented limitation of the descriptive pilot.
run_archetypes <- function(min_minutes = 600, k_range = 2:5,
                           k_fixed = c(D = 4, M = 4, F = 3),
                           save = TRUE) {
  sep <- function(title) cat("\n", strrep("=", 60), "\n", title, "\n",
                             strrep("=", 60), "\n\n", sep = "")

  sep("STEP 1: FEATURES")
  features <- pa_build_features(min_minutes = min_minutes)
  cat("Qualifying player-seasons:", nrow(features),
      "| features:", length(pa_feature_cols(features)), "\n")
  print(table(features$position_group))

  sep("STEP 2: CLUSTERING")
  clusters <- pa_cluster_archetypes(features, k_range = k_range,
                                    k_fixed = k_fixed)
  print(clusters$diagnostics, row.names = FALSE)

  sep("STEP 3: ARCHETYPE PROFILES")
  pa_label_archetypes(clusters)

  sep("STEP 4: FACE VALIDITY")
  print(as.data.frame(pa_face_validity(clusters)), row.names = FALSE)

  if (save) {
    saveRDS(clusters$assignments, file.path(pa_cache_dir, "archetypes.rds"))
    cat("\nSaved", nrow(clusters$assignments), "assignments to",
        file.path(pa_cache_dir, "archetypes.rds"), "\n")
  }
  invisible(list(features = features, clusters = clusters))
}
