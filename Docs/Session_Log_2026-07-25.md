# Session Log — 2026-07-25

## Goal

Add the 2025/26 season to the website and the site data, without contaminating
anything that must not contain it — in particular the "Does it work?" page's
forward test, which exists precisely because 2025/26 was never in the fit.

## The decision

Two ways to "add a season":

1. **Refit** M3/M4/M5 with 2025/26 in the training data.
2. **Display-only**: score 2025/26 with the model already frozen at 2024, and
   show it as a holdout year.

Option 1 was rejected, and the rejection is now written into CLAUDE.md as a
binding rule. The forward test (writeup Part 11b, validation page test 3) claims
that the coach grades it validates were computed without ever seeing 2025/26. If
2025/26 enters the fit, `coach_blups_14league.rds` stops being a *prior* BLUP,
the saved `forward_test.rds` numbers become unreproducible from the results
files, and the page asserts something false. There is no 2026/27 to roll the
holdout forward to (the season has not been played), so the forward test cannot
be re-based — it can only be destroyed. It is one of three concordant
validations and the only true future holdout.

Option 2 also turns out to be the better *product*: the most recent season on the
site becomes a live scorecard — the model's predictions for a year it never saw —
rather than one more fitted row.

## What made it cheap

`forward_test.rds` already contained exactly the two tables needed:

- `$deserved_2025` — 252 team-seasons, carrying **exactly** the
  `residuals_14league.rds` schema (plus extras).
- `$stints` — 435 coach stints, carrying **exactly** the
  `coach_residuals_14league.rds` schema (plus `prior_blup`/`has_prior`).

And critically, the frozen M3 fit inside `forward_test.R` is *the same fit* as the
one behind `residuals_14league.rds`. Verified by refitting on `mb_prep$ds` +
`ds_2025.rds` restricted to `season <= 2024` and predicting every existing row:

```
max |delta| in predicted_ppg over all 5,080 fitted rows = 0
mean |delta| = 0
```

So the holdout rows land on the same scale as the fitted ones and can share a
table with them. `se_load()` appends them with a `holdout` flag; nothing needed
re-deriving.

Sanity check on the data itself: 2025/26 games-per-league match the 2024
reference in all 14 leagues, with one real league change (Süper Lig 19 → 18
teams, 36 → 34 games).

## Invariants enforced

| Quantity | Window |
|---|---|
| M3 coefficients, M5 BLUPs, grades, ranks, significance | ≤ 2024/25 |
| Per-league Model R² / RMSE | ≤ 2024/25 (`ok_fit`, new) |
| Standings, deserved table, residuals, team/coach stint lists | through 2025/26 |
| Career totals (stints, clubs, games) | through 2025/26 |
| Recommender, team builder, style/strengths layers, player growth | unchanged (SofaScore ends 2024/25) |

Career totals deliberately *include* the holdout — they are facts about a career,
and the coach page lists the 2025/26 stint, so a total that excluded it would
contradict the list directly above it. Every surface that puts a career total
next to a grade now names both windows (`career.graded_through`,
`career.n_holdout_stints`, `rating.through_season`,
`meta.dataset.fit_last_season`).

## Verification

`export_site_data()` re-run, diffed against a pre-change snapshot:

- `validation.json`, `players.json`, `builder/{players,coaches,meta}.json` —
  **byte-identical**. These are insulated by construction: they read their own
  rds/cache files, never `d$res`/`d$cr`.
- `leaderboard.json` — **0 of 545 coaches changed any grade field** (rank, letter,
  numeric, BLUP, mean residual, significance) in either cut. 148 coaches gained
  career games/stints, all from 2025/26 work (Guardiola 596 → 634 games, +1 stint).
- `meta.json` — `last_season` 2024 → 2025, `team_seasons` 5,087 → 5,339 (+252),
  `coaches` 2,341 → 2,445, `clubs` 496 → 505; `n_graded_*` unchanged.
- 104 new coach pages, 9 new club pages, 113 new search-index entries.

## Assets

The 9 clubs new to 2025/26 (Ceuta, Telstar, Wrexham, Fredericia, Paris FC, RAAL
La Louvière, Alverca, Vukovar, Pisa) had no crest and were absent from the crest
cache; ~97 coaches new to 2025/26 had no photo. Both fetched via the existing
resumable populates (`xx_data_populate_team_crests()`,
`xx_data_populate_coach_images()`).

Coach *nationalities* were deliberately not re-scraped: they feed only the
recommender's plausibility chips, whose pool is the frozen 81-coach similarity
set.

## Incidental fix

`compare.js` carried hand-typed counts — "545 of the 2,341 in the data",
"Search 545 graded coaches…" — which this change would have made wrong. Both are
now read from `leaderboard.json` (new top-level `n_coaches`).

## Rolling forward next year

`xx_data_populate_league_seasons(<yr>)` → rebuild `ds_<yr>.rds` → re-run M3→M5 on
≤`<yr>-1` → `run_forward_test()` → bump `se_fit_last_season` / `se_holdout_season`.
The holdout must always be the newest season, and there must always be exactly
one.
