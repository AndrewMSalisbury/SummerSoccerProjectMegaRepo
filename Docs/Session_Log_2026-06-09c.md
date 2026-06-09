# Session Log — 2026-06-09 (Session 3)

## Purpose
Record of decisions made, code changes, results produced, and their meaning. Continuation of the June 9 sessions; covers the augmented model (coach BLUP as a predictive feature).

---

## Files Modified/Created

- `src/augmented_model.R` — new file containing the augmented model CV pipeline
- `Docs/Summary_of_Findings.md` — added Part 4 (augmented model results) and updated conclusion
- `Docs/Session_Log_2026-06-09c.md` — this file
- `Docs/Progress_Report_2026-06-09c.md` — session progress report

---

## Functions in `augmented_model.R`

| Function | Purpose |
|---|---|
| `fit_enhanced_fixed(data)` | Fits the M3 winning model spec on arbitrary training data |
| `build_residuals_tbl_from(data, lm_model)` | Adds predicted_ppg/residual columns; compatible with `build_coach_residuals()` |
| `extract_coach_blups(coach_residuals_tbl, min_games, min_stints)` | Fits mixed model quietly, returns coach BLUP data frame |
| `get_coach_game_counts(team_season_ids)` | Games-per-coach for a set of team-seasons (attribution only, no residuals) |
| `weighted_blup_per_team(game_counts, blup_df)` | Games-weighted BLUP per team-season; unseen coaches contribute 0 |
| `cv_augmented_by_season(dataset, min_games, min_stints)` | Full leave-one-season-out CV; returns fold-by-fold RMSE table |
| `run_augmented_model(seasons, min_games, min_stints)` | Entry point: builds dataset, runs CV, prints t-test |

No existing files were modified.

---

## Design Decisions

### No-leakage constraint
BLUPs are estimated exclusively from the 9 training seasons in each fold. The mixed model in `extract_coach_blups()` is re-fitted from scratch per fold. Coaches appearing for the first time in the held-out season receive BLUP = 0.

### Games-weighted team BLUP
For teams with mid-season coaching changes, the adjustment is a games-weighted average of each coach's training BLUP. This is consistent with the partial attribution rule from M5 and avoids assigning the full season adjustment to a coach who managed only part of it.

### Conservative default (BLUP = 0)
Assigning 0 to unseen coaches is conservative — it means the model makes no coaching adjustment for new or data-scarce coaches rather than guessing. This biases the improvement estimate downward (the true effect is likely larger with more seasons of data).

### Quiet mixed model
`extract_coach_blups()` suppresses all console output from `lme4`. The full M5 `fit_mixed_model()` is not reused because its printing overhead would clutter the CV loop output. The M5 function is unchanged.

---

## Results

```
   fold n_test n_adjusted enhanced augmented improvement
1  2015     95         64   0.2444    0.2458     -0.0014
2  2016     98         81   0.2170    0.2103      0.0067
3  2017     98         84   0.2187    0.2148      0.0038
4  2018     97         87   0.3002    0.2949      0.0053
5  2019     98         86   0.2706    0.2637      0.0069
6  2020     98         86   0.2192    0.2196     -0.0004
7  2021     96         87   0.2091    0.2016      0.0075
8  2022     98         77   0.2386    0.2309      0.0078
9  2023     96         69   0.2190    0.2136      0.0054
10 2024     96         59   0.2357    0.2333      0.0025
11 MEAN     NA         NA   0.2373    0.2328      0.0044

Paired t-test: p = 0.001  |  95% CI lower = 0.0025
```

8 of 10 folds improved. Mean RMSE improvement 0.0044 PPG.

---

## Interpretation of Non-Improving Folds

**2015 (−0.0014):** First fold, so BLUPs are estimated from 2016–2024 data only. Coaches who were only active in 2015 get BLUP = 0 (64/95 teams adjusted vs 81–87 in later folds). Additionally, BLUPs estimated from a coach's peak later years may overstate their 2015 ability. This is a systematic disadvantage for the earliest fold and would resolve with more historical data.

**2020 (−0.0004):** Essentially flat. The COVID season introduced scheduling compression, bio-bubble conditions, and empty stadiums — a highly unusual environment that disrupts normal coach-quality signals. No adjustment warranted.

---

## Cumulative Improvement Chain

| Step | RMSE improvement |
|---|---|
| Raw squad value → minutes-weighted (M3) | ~0.013 |
| Minutes-weighted → +coach BLUP (new) | 0.0044 |

The coach augmentation adds approximately one-third of what the weighting step contributed — a meaningful additional layer on top of an already strong model.

---

## Next Steps

- **Milestone 6 (stretch):** Player Development Score or Playing Style Analysis if time permits
- **Potential extension:** More seasons (pre-2015) would increase stints per coach, improve BLUP precision, and likely strengthen the out-of-sample improvement (especially for the 2015 fold)
