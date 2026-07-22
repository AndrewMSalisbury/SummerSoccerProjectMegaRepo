# market_benchmark.R — Forecasting against the betting market (Market Benchmark)
# Design: Docs/Market_Benchmark_Design.md
#
# Assembles the project's validated pieces — a pre-season squad-value strength and
# the as-of coach quality BLUP — into a leakage-free, walk-forward match
# forecaster, and tests it against bookmaker closing odds (Pinnacle, de-margined).
#
# Prefix: mb_. Pure cache/results reader over source_odds.R + the M5 chain; no
# scraping. Leakage is the whole game (design §3.2, §5.1): every feature for a
# match in season S is computed from data strictly before S —
#   - squad strength = a PRE-SEASON value snapshot (raw total squad value; never
#     the minutes-weighted value, which embeds realized in-season minutes), and
#   - coach BLUP = the M5 mixed model refit on completed seasons < S only.
# The goal-model coefficients are likewise fit on fd matches from seasons < S
# (expanding window). A coach with no prior history enters at the shrinkage
# prior (BLUP = 0), which is itself the honest forecast.

source("source_data.r")        # cache + xx_ helpers (auto-inits data cache)
source("coach_attribution.R")  # chains residual_analysis -> model_comparison -> tabler; M5 fns
source("source_odds.R")        # od_ ingest + crosswalk

suppressWarnings(suppressMessages({ library(dplyr) }))

mb_results_dir <- "data/results"

# --- Leakage-free feature preparation -----------------------------------------
# Builds, once, the two cutoff-independent inputs the walk-forward needs:
#   $ds     : team-season value + points (the M3 dataset over all 14 leagues).
#   $stints : model-independent coach-stint actuals (games, points, date_from)
#             per (coach, team-season) — the attribution is model-independent, so
#             it is computed once and each window only swaps in its own
#             predicted_ppg to form the partial residual.
# Cached to data/results/mb_prep.rds so the slow player-join build runs once.
mb_prepare <- function(seasons = 2005:2024, refresh = FALSE) {
  cache <- file.path(mb_results_dir, "mb_prep.rds")
  if (!refresh && file.exists(cache)) return(readRDS(cache))

  full_ds  <- build_model_dataset(seasons, leagues = xx_all_leagues())
  full_res <- compute_residuals(full_ds)          # full-data model; used only for stint structure
  full_st  <- build_coach_residuals(full_res)     # per-stint actuals + date_from

  prep <- list(ds = full_ds, stints = full_st)
  saveRDS(prep, cache)
  prep
}

# As-of coach BLUPs for forecasting season `cutoff`: refit M3 on team-seasons
# strictly before cutoff, recompute stint partial residuals, fit the M5 mixed
# model, return coach_id -> blup. Coaches below the mixed-model thresholds (or
# unseen) are simply absent and treated as BLUP 0 by the caller.
mb_asof_blups <- function(prep, cutoff, min_games = 10, min_stints = 3) {
  dp <- prep$ds |>
    dplyr::filter(season < cutoff, norm_weighted_value > 0, norm_total_value > 0)
  m <- lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team, data = dp)
  pred <- data.frame(team_season_id = dp$team_season_id,
                     predicted_ppg = as.numeric(predict(m, dp)),
                     stringsAsFactors = FALSE)
  st <- prep$stints |> dplyr::filter(season < cutoff)
  st$predicted_ppg <- pred$predicted_ppg[match(st$team_season_id, pred$team_season_id)]
  st$partial_residual_ppg <- st$actual_ppg - st$predicted_ppg
  st <- st |> dplyr::filter(!is.na(partial_residual_ppg))
  mm <- suppressWarnings(suppressMessages(
    utils::capture.output(res <- fit_mixed_model(st, min_games = min_games, min_stints = min_stints))
  ))
  data.frame(coach_id = res$coach_blups$coach_id,
             blup = res$coach_blups$blup, stringsAsFactors = FALSE)
}

# --- Dixon-Coles bivariate goal model -----------------------------------------
# One strength scalar per team enters as a linear differential of two leakage-free
# features. For a match:
#   s_diff = a*(logv_home - logv_away) + b*(blup_home - blup_away)
#   log(lambda_home) = c_league + home + s_diff
#   log(lambda_away) = c_league        - s_diff
# with the Dixon-Coles low-score dependence tau(rho) on the (0,0),(0,1),(1,0),(1,1)
# cells (draw calibration, design §5.6). Params: per-league baseline c_league, a
# global home effect, value slope a, blup slope b, and rho. Fit by MLE.
mb_dc_tau <- function(i, j, lh, la, rho) {
  ifelse(i == 0 & j == 0, 1 - lh*la*rho,
  ifelse(i == 0 & j == 1, 1 + lh*rho,
  ifelse(i == 1 & j == 0, 1 + la*rho,
  ifelse(i == 1 & j == 1, 1 - rho, 1))))
}

# Negative log-likelihood over a training frame with columns:
# fthg, ftag, dv (logv_home-logv_away), db (blup_home-blup_away), lg (league idx 1..L)
mb_dc_nll <- function(par, tr, L) {
  c_lg  <- par[1:L]
  home  <- par[L + 1]
  a     <- par[L + 2]
  b     <- par[L + 3]
  rho   <- par[L + 4]
  sdiff <- a * tr$dv + b * tr$db
  lh <- exp(c_lg[tr$lg] + home + sdiff)
  la <- exp(c_lg[tr$lg]        - sdiff)
  tau <- mb_dc_tau(tr$fthg, tr$ftag, lh, la, rho)
  tau[tau <= 0] <- 1e-10
  ll <- dpois(tr$fthg, lh, log = TRUE) + dpois(tr$ftag, la, log = TRUE) + log(tau)
  -sum(ll)
}

# Fit the DC model. leagues: character vector giving the league factor levels.
# Full joint MLE (slow on large folds); kept for reference and as the primary run.
mb_fit_dc <- function(tr) {
  leagues <- sort(unique(tr$league))
  L <- length(leagues)
  tr$lg <- match(tr$league, leagues)
  base_c <- log(mean(c(tr$fthg, tr$ftag)))
  # inits: home 0.25, value slope 0.4, coach slope 0 (neutral — if the coach term
  # is unidentified in a fold it stays at no-effect, not an arbitrary value), rho -0.05
  par0 <- c(rep(base_c, L), 0.25, 0.4, 0.0, -0.05)
  fit <- optim(par0, mb_dc_nll, tr = tr, L = L, method = "BFGS",
               control = list(maxit = 500, reltol = 1e-9))
  list(par = fit$par, leagues = leagues, L = L, convergence = fit$convergence,
       home = fit$par[L + 1], a = fit$par[L + 2], b = fit$par[L + 3], rho = fit$par[L + 4])
}

# Fast fit: the DC mean structure is two Poisson regressions, so fit c_league,
# home, and the value slope a by a single stacked Poisson GLM (home + away goal
# rows), then fit rho by a 1-D search holding the means. Value-only (b = 0). Gives
# effectively identical H/D/A to the joint MLE at a fraction of the cost — used
# for the robustness variants (prior-season value). Verified to reproduce the
# optim run's a and skill numbers.
mb_fit_dc_glm <- function(tr, with_rho = TRUE) {
  leagues <- sort(unique(tr$league)); L <- length(leagues)
  n <- nrow(tr)
  stacked <- data.frame(
    goals   = c(tr$fthg, tr$ftag),
    league  = factor(c(tr$league, tr$league), levels = leagues),
    is_home = c(rep(1, n), rep(0, n)),
    sdiff   = c(tr$dv, -tr$dv)
  )
  m  <- glm(goals ~ 0 + league + is_home + sdiff, family = poisson, data = stacked)
  co <- coef(m)
  c_lg <- as.numeric(co[paste0("league", leagues)])
  home <- as.numeric(co["is_home"]); a <- as.numeric(co["sdiff"])
  rho <- 0
  if (with_rho) {
    lh <- exp(c_lg[match(tr$league, leagues)] + home + a * tr$dv)
    la <- exp(c_lg[match(tr$league, leagues)]        - a * tr$dv)
    nll_rho <- function(r) {
      tau <- mb_dc_tau(tr$fthg, tr$ftag, lh, la, r); tau[tau <= 0] <- 1e-10
      -sum(dpois(tr$fthg, lh, log = TRUE) + dpois(tr$ftag, la, log = TRUE) + log(tau))
    }
    rho <- optimize(nll_rho, c(-0.2, 0.2))$minimum
  }
  list(par = c(c_lg, home, a, 0, rho), leagues = leagues, L = L,
       convergence = 0L, home = home, a = a, b = 0, rho = rho)
}

# P(H/D/A) for a vector of matches from fitted params + features. Returns an
# [n x 3] matrix. Fully vectorized: the independent-Poisson H/D/A are summed over
# away goals analytically (P(home>j) via the upper Poisson tail), then the
# Dixon-Coles low-score correction is applied to the four (0,0),(0,1),(1,0),(1,1)
# cells and the triple renormalized.
mb_dc_probs <- function(fit, league, dv, db, max_goals = 10) {
  n <- length(dv)
  li <- match(league, fit$leagues); li[is.na(li)] <- 1L
  c_lg  <- fit$par[li]
  sdiff <- fit$a * dv + fit$b * db
  lh <- exp(c_lg + fit$home + sdiff)
  la <- exp(c_lg            - sdiff)
  ph_win <- numeric(n); pdraw <- numeric(n)
  for (j in 0:max_goals) {
    paj    <- dpois(j, la)
    ph_win <- ph_win + paj * ppois(j, lh, lower.tail = FALSE)  # home goals > j
    pdraw  <- pdraw  + paj * dpois(j, lh)
  }
  pa_win <- 1 - ph_win - pdraw
  p0h <- dpois(0, lh); p1h <- dpois(1, lh); p0a <- dpois(0, la); p1a <- dpois(1, la)
  d00 <- p0h * p0a * (-lh * la * fit$rho)   # (0,0) draw
  d01 <- p0h * p1a * ( lh * fit$rho)        # (0,1) away win
  d10 <- p1h * p0a * ( la * fit$rho)        # (1,0) home win
  d11 <- p1h * p1a * (-fit$rho)             # (1,1) draw
  ph_win <- ph_win + d10
  pa_win <- pa_win + d01
  pdraw  <- pdraw  + d00 + d11
  tot <- ph_win + pdraw + pa_win
  cbind(p_h = ph_win / tot, p_d = pdraw / tot, p_a = pa_win / tot)
}

# --- As-of BLUP tables (cached) -----------------------------------------------
# One BLUP table per cutoff season, each fit only on completed prior seasons.
# Expensive (a mixed-model refit per season), so cached to disk.
mb_asof_blup_tables <- function(prep, seasons, refresh = FALSE) {
  cache <- file.path(mb_results_dir, "mb_asof_blups.rds")
  if (!refresh && file.exists(cache)) {
    B <- readRDS(cache)
    if (all(as.character(seasons) %in% names(B))) return(B[as.character(seasons)])
  }
  B <- list()
  for (s in seasons) {
    cat(sprintf("  as-of BLUPs, cutoff %d ...\n", s))
    B[[as.character(s)]] <- mb_asof_blups(prep, cutoff = s)
  }
  saveRDS(B, cache)
  B
}

# --- Feature assembly ---------------------------------------------------------
# Attaches leakage-free features to the fd match table: pre-season log squad value
# per side (raw total_team_value snapshot) and the as-of coach BLUP per side
# (0 = no prior history), plus new_home/new_away flags for coaches absent from the
# as-of BLUP pool (the design's low-profile/first-season subgroup).
mb_build_features <- function(prep, mo, B, value_mode = c("current", "prior")) {
  value_mode <- match.arg(value_mode)
  # market de-margined probs are named p_* by od_build_matches; rename to m_* so
  # the model can own p_* downstream.
  mo$m_h <- mo$p_h; mo$m_d <- mo$p_d; mo$m_a <- mo$p_a
  mo$p_h <- NULL; mo$p_d <- NULL; mo$p_a <- NULL

  # squad-value snapshot. "current" = the team-season's own total value (a season
  # valuation, the leakage caveat). "prior" = the club's PRIOR-season total value
  # (strictly pre-season, zero look-ahead), with current-season fallback for
  # promoted / first-observed clubs — the leakage robustness variant (design §3.2).
  if (value_mode == "current") {
    val <- prep$ds |> dplyr::transmute(team_season_id, logv = log(total_team_value))
  } else {
    dd <- prep$ds |>
      dplyr::mutate(verein = od_verein_id(team_season_id),
                    yr = suppressWarnings(as.integer(sub(".*saison_id/", "", team_season_id))))
    prior <- dd |> dplyr::transmute(verein, yr_next = yr + 1L, prior_val = total_team_value)
    cur   <- dd |> dplyr::select(team_season_id, verein, yr, total_team_value)
    j <- cur |>
      dplyr::left_join(prior, by = c("verein" = "verein", "yr" = "yr_next")) |>
      dplyr::mutate(val_used = dplyr::coalesce(prior_val, total_team_value),
                    logv = log(val_used))
    val <- j |> dplyr::transmute(team_season_id, logv)
  }
  vmap <- setNames(val$logv, val$team_season_id)
  mo$home_logv <- vmap[mo$home_team_season_id]
  mo$away_logv <- vmap[mo$away_team_season_id]

  # coach at match date, per side, from coaches.rds via the M5 attribution rule.
  # Pre-index coaches by team-season so each lookup filters only that team's few
  # tenure brackets (not the whole 13k-row table) — the match table is large.
  coaches <- xx_data_cache$coaches
  coach_by_ts <- split(coaches[, c("coach_id","date_from","date_to")],
                       coaches$team_season_id)
  coach_at <- function(team_sid, dt) {
    cand <- coach_by_ts[[team_sid]]
    if (is.null(cand)) return(NA_character_)
    ok <- !is.na(cand$date_from) & cand$date_from <= dt &
          (is.na(cand$date_to) | cand$date_to >= dt)
    if (!any(ok)) return(NA_character_)
    cand$coach_id[ok][which.max(cand$date_from[ok])]
  }
  mo$home_coach <- mapply(coach_at, mo$home_team_season_id, mo$match_date)
  mo$away_coach <- mapply(coach_at, mo$away_team_season_id, mo$match_date)

  blup_lookup <- function(season, coach) {
    tb <- B[[as.character(season)]]
    if (is.null(tb) || is.na(coach)) return(0)
    v <- tb$blup[match(coach, tb$coach_id)]
    if (is.na(v)) 0 else v
  }
  in_pool <- function(season, coach) {
    tb <- B[[as.character(season)]]
    !is.null(tb) && !is.na(coach) && coach %in% tb$coach_id
  }
  mo$home_blup <- mapply(blup_lookup, mo$season, mo$home_coach)
  mo$away_blup <- mapply(blup_lookup, mo$season, mo$away_coach)
  mo$new_home  <- !mapply(in_pool, mo$season, mo$home_coach)
  mo$new_away  <- !mapply(in_pool, mo$season, mo$away_coach)

  mo$dv <- mo$home_logv - mo$away_logv
  mo$db <- mo$home_blup - mo$away_blup
  mo
}

# --- Walk-forward forecaster --------------------------------------------------
# For each test season S, fit the DC goal model on fd matches strictly before S
# (expanding window) and predict season S. The deployed forecaster is VALUE +
# HOME only (coach slope forced to 0): adding the coach BLUP to the goal model
# gives a collinear, sign-flipping, fold-unstable b (verified: b ranged ~0 to
# +1.2 across folds), so the coach signal is not put into the forecaster — it is
# tested directly against the market in mb_evaluate via the as-of BLUP
# differential. Returns test-set predictions (p_* = model) with market probs (m_*).
mb_walkforward <- function(prep, mo, test_seasons = 2013:2024, fitter = mb_fit_dc) {
  feat <- mo |>
    dplyr::filter(is.finite(dv), is.finite(db), !is.na(m_h), !is.na(fthg), !is.na(ftag),
                  is.finite(home_logv), is.finite(away_logv))
  out <- list()
  for (S in test_seasons) {
    tr <- feat |> dplyr::filter(season >= 2012, season < S)
    te <- feat |> dplyr::filter(season == S)
    if (nrow(tr) < 200 || nrow(te) == 0) next
    tr$db <- 0                       # value + home forecaster (stable)
    fit <- fitter(tr)
    pr  <- mb_dc_probs(fit, te$league, te$dv, 0)
    te$p_h <- pr[,1]; te$p_d <- pr[,2]; te$p_a <- pr[,3]
    out[[as.character(S)]] <- te
    cat(sprintf("  season %d: train %d, test %d, home=%.3f a=%.3f rho=%+.3f conv=%d\n",
                S, nrow(tr), nrow(te), fit$home, fit$a, fit$rho, fit$convergence))
  }
  dplyr::bind_rows(out)
}

# --- Evaluation ---------------------------------------------------------------
# Multiclass log-loss and Brier score of a probability triple against realized
# results (y in {"H","D","A"}). Lower is better.
mb_logloss <- function(ph, pd, pa, y) {
  p <- ifelse(y == "H", ph, ifelse(y == "D", pd, pa))
  -mean(log(pmax(p, 1e-12)))
}
mb_brier <- function(ph, pd, pa, y) {
  yh <- as.integer(y == "H"); yd <- as.integer(y == "D"); ya <- as.integer(y == "A")
  mean((ph - yh)^2 + (pd - yd)^2 + (pa - ya)^2)
}

# Conditional (McFadden) logit over 3 alternatives per match. cov_list: named
# list of [n x 3] covariate matrices (columns = H,D,A). y3: integer 1/2/3 for the
# realized outcome. Returns coef/se/z/p per covariate. Fit by optim; SEs from the
# numerical Hessian.
mb_condlogit <- function(cov_list, y3) {
  n <- length(y3); K <- 3
  P <- length(cov_list)
  X <- array(0, dim = c(n, K, P))
  for (p in seq_len(P)) X[, , p] <- cov_list[[p]]
  nll <- function(beta) {
    eta <- matrix(0, n, K)
    for (p in seq_len(P)) eta <- eta + X[, , p] * beta[p]
    m <- apply(eta, 1, max)
    denom <- log(rowSums(exp(eta - m))) + m
    chosen <- eta[cbind(seq_len(n), y3)]
    -sum(chosen - denom)
  }
  fit <- optim(rep(0, P), nll, method = "BFGS", hessian = TRUE,
               control = list(maxit = 500, reltol = 1e-10))
  se <- sqrt(diag(solve(fit$hessian)))
  z <- fit$par / se
  data.frame(term = names(cov_list), coef = fit$par, se = se, z = z,
             p = 2 * pnorm(-abs(z)), stringsAsFactors = FALSE)
}

# Full pre-registered evaluation (design §4). pred is the walk-forward test set.
mb_evaluate <- function(pred) {
  d <- pred |>
    dplyr::filter(!is.na(m_h), !is.na(p_h), !is.na(ftr))
  y  <- d$ftr
  y3 <- match(y, c("H","D","A"))

  # 4.1 skill vs market (the model is the value+home forecaster)
  skill <- data.frame(
    source  = c("market","value model"),
    logloss = c(mb_logloss(d$m_h,d$m_d,d$m_a,y),
                mb_logloss(d$p_h,d$p_d,d$p_a,y)),
    brier   = c(mb_brier(d$m_h,d$m_d,d$m_a,y),
                mb_brier(d$p_h,d$p_d,d$p_a,y)),
    stringsAsFactors = FALSE
  )

  lg <- function(a,b,c) log(pmax(cbind(a,b,c), 1e-12))
  # per-alternative covariate builders. intercepts for D and A (H is reference);
  # a scalar strength differential s (home minus away) maps to outcome directions
  # (+1, 0, -1) for (H,D,A): a bigger home edge favours H, disfavours A. This
  # avoids the value/full-model collinearity that a second log-prob column causes.
  mk_int <- function(n, k) matrix(rep(replace(numeric(3), k, 1), each = n), ncol = 3)
  dir3   <- function(s) cbind(s, 0, -s)
  n <- nrow(d)
  Lm   <- lg(d$m_h, d$m_d, d$m_a)
  Lp   <- lg(d$p_h, d$p_d, d$p_a)
  intD <- mk_int(n, 2); intA <- mk_int(n, 3)
  Dv   <- dir3(d$dv)      # squad-value differential (log-euro)
  Db   <- dir3(d$db)      # coach-quality (as-of BLUP) differential

  # 4.2 incremental info (the real headline): does the full model add beyond the
  # de-margined market probability?
  t_full <- mb_condlogit(list(intD=intD, intA=intA, market=Lm, model=Lp), y3)
  # does squad value add beyond the market? (near-certainly already priced)
  t_val  <- mb_condlogit(list(intD=intD, intA=intA, market=Lm, value=Dv), y3)
  # 4.3 the coach question: does managerial quality add beyond the market alone,
  # and beyond market + squad value? Positive coach coef = quality underpriced.
  t_coach      <- mb_condlogit(list(intD=intD, intA=intA, market=Lm, coach=Db), y3)
  t_coach_ctrl <- mb_condlogit(list(intD=intD, intA=intA, market=Lm, value=Dv, coach=Db), y3)

  # 4.3 subgroup: matches with a low-profile / first-season coach on either side
  sub <- d$new_home | d$new_away
  t_coach_new <- NULL
  if (sum(sub) > 300) {
    ds <- d[sub, ]; ns <- nrow(ds); y3s <- match(ds$ftr, c("H","D","A"))
    t_coach_new <- mb_condlogit(list(
      intD = mk_int(ns,2), intA = mk_int(ns,3),
      market = lg(ds$m_h,ds$m_d,ds$m_a), coach = dir3(ds$db)), y3s)
  }

  list(n = nrow(d), skill = skill,
       incremental_full = t_full, value_vs_market = t_val,
       coach_vs_market = t_coach, coach_vs_market_value = t_coach_ctrl,
       coach_subgroup_newcoach = t_coach_new, n_subgroup = sum(sub))
}

# --- Top-level runner ---------------------------------------------------------
# value_mode = "prior" is the leakage-free primary (design §3.2); "current" is the
# leakage-demonstration variant. fitter = mb_fit_dc_glm is the fast, validated fit.
mb_run <- function(seasons_test = 2013:2024, value_mode = "prior",
                   fitter = mb_fit_dc_glm, refresh_prep = FALSE, refresh_blups = FALSE) {
  prep <- mb_prepare(refresh = refresh_prep)
  cw   <- od_build_crosswalk(seasons = 2012:2024)
  mo   <- od_build_matches(seasons = 2012:2024, cw = cw)
  B    <- mb_asof_blup_tables(prep, seasons = 2012:2024, refresh = refresh_blups)
  feat <- mb_build_features(prep, mo, B, value_mode = value_mode)
  pred <- mb_walkforward(prep, feat, test_seasons = seasons_test, fitter = fitter)
  ev   <- mb_evaluate(pred)
  ev$value_mode <- value_mode
  saveRDS(list(pred = pred, eval = ev, value_mode = value_mode),
          file.path(mb_results_dir, "market_benchmark.rds"))
  ev
}

# --- P&L backtest (design §4.4, pre-registered) -------------------------------
# Walk-forward paper trading with the staking rule fixed BEFORE the run:
#   * bet 1 flat unit on every (match, outcome) whose model edge p*o - 1 exceeds
#     `threshold` (default 5%), at the Pinnacle closing decimal odds;
#   * fractional-Kelly variant (f * max(kelly,0)) as a robustness spec;
#   * ROI with a bootstrap CI (returns are heavy-tailed — a point estimate alone
#     is meaningless); a positive ROI whose CI includes 0 is "not distinguishable
#     from luck", full stop.
# Honesty rails: `haircut` re-prices every bet to a worse achievable line (design
# §4.4 closing-line realism — a real bettor rarely gets the closing price), and
# results are bucketed favourite/longshot so a longshot-variance "profit" shows.
mb_pnl <- function(pred, threshold = 0.05, kelly_frac = 0.25,
                   haircut = 0.0, boot = 2000, seed = 1) {
  d <- pred |>
    dplyr::filter(!is.na(odds_h), !is.na(p_h), !is.na(ftr))
  o <- cbind(d$odds_h, d$odds_d, d$odds_a)
  o <- 1 + (o - 1) * (1 - haircut)                  # achievable-price haircut
  p <- cbind(d$p_h, d$p_d, d$p_a)
  win <- cbind(d$ftr == "H", d$ftr == "D", d$ftr == "A")
  edge <- p * o - 1
  bet <- edge > threshold
  idx <- which(bet, arr.ind = TRUE)
  if (nrow(idx) == 0) return(list(n_bets = 0))
  bo <- o[idx]; bw <- win[idx]; bp <- p[idx]
  prof_flat  <- ifelse(bw, bo - 1, -1)
  kelly      <- pmax((bp * bo - 1) / (bo - 1), 0)
  stake_k    <- kelly_frac * kelly
  prof_kelly <- stake_k * ifelse(bw, bo - 1, -1)

  roi_flat  <- sum(prof_flat) / length(prof_flat)
  roi_kelly <- sum(prof_kelly) / sum(stake_k)

  set.seed(seed)
  bf <- replicate(boot, { s <- sample(length(prof_flat), replace = TRUE)
                          sum(prof_flat[s]) / length(s) })
  ci_flat <- quantile(bf, c(0.025, 0.975))
  bk <- replicate(boot, { s <- sample(length(prof_kelly), replace = TRUE)
                          sum(prof_kelly[s]) / sum(stake_k[s]) })
  ci_kelly <- quantile(bk, c(0.025, 0.975))

  bucket <- cut(bo, c(1, 2, 4, Inf), labels = c("fav(<2.0)","mid(2-4)","long(>4)"))
  by_bucket <- data.frame(
    bucket = levels(bucket),
    n = as.integer(table(bucket)),
    roi_flat = tapply(prof_flat, bucket, mean)[levels(bucket)],
    stringsAsFactors = FALSE
  )

  list(threshold = threshold, haircut = haircut,
       n_bets = length(prof_flat), n_matches = nrow(d),
       roi_flat = roi_flat, ci_flat = ci_flat, total_profit_flat = sum(prof_flat),
       roi_kelly = roi_kelly, ci_kelly = ci_kelly,
       hit_rate = mean(bw), by_bucket = by_bucket)
}

mb_report_pnl <- function(pnl) {
  if (is.null(pnl$n_bets) || pnl$n_bets == 0) { cat("No bets cleared the threshold.\n"); return(invisible()) }
  cat(sprintf("P&L (threshold %.0f%%, haircut %.0f%%): %d bets over %d matches, hit %.1f%%\n",
              100*pnl$threshold, 100*pnl$haircut, pnl$n_bets, pnl$n_matches, 100*pnl$hit_rate))
  cat(sprintf("  ROI flat : %+.2f%%  95%% CI [%+.2f%%, %+.2f%%]  (profit %+.1f u)\n",
              100*pnl$roi_flat, 100*pnl$ci_flat[1], 100*pnl$ci_flat[2], pnl$total_profit_flat))
  cat(sprintf("  ROI Kelly: %+.2f%%  95%% CI [%+.2f%%, %+.2f%%]\n",
              100*pnl$roi_kelly, 100*pnl$ci_kelly[1], 100*pnl$ci_kelly[2]))
  cat("  by odds bucket (mean flat return/bet):\n")
  print(pnl$by_bucket, row.names = FALSE)
}
