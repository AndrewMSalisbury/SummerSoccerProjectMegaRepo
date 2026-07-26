# Session Log — 2026-07-26

## Ask

> Let's scrape sofascore for 25/26 as well. Additionally, lets update Everything
> except for what should be held out to test for the future, this means BLUPs,
> grades, rankings, and anything else that seems correct to update.

This reverses yesterday's arrangement. On 2026-07-25 the site displayed 2025/26 but
**froze every model at 2024** so the Part-11b forward test would stay honest. Today's
instruction is to fold 2025/26 into the fit — grades, BLUPs, rankings — while still
protecting whatever must not see it.

## The one thing that made this safe

The forward test's claim is *"these grades never saw 2025/26."* Its Q1 (M3 structure) was
always self-contained — it refits on `season < 2025` from `mb_prep`. But **Q2 read the
live `coach_blups_14league.rds`**, which was ≤2024 only because the whole pipeline stopped
there. Refitting would have turned that read circular: the test would score grades against
the very season they had been estimated on, and would still print a small p-value.

Fix: **freeze the vintage, not the pipeline.**

- `data/results/coach_blups_14league_asof2024.rds` — a byte copy of the BLUPs taken
  *before* the refit.
- `forward_test.R` gained `ft_holdout_season` and `ft_blup_vintage`, reads the snapshot,
  and **errors out rather than falling back** to the live file.
- `full <- bind_rows(prep$ds |> filter(season < ft_holdout_season), ...)` — a dedupe
  guard, because `mb_prep$ds` now itself spans the holdout year and would otherwise
  contribute a second, training-side copy of all 252 rows.
- `rp_check_vintage()` fails the refit if the snapshot is missing.

**Verified twice.** Before the refit (both files identical, so the plumbing had to be
transparent) and again after the full 2025/26 refit:

| | published | after refit |
|---|---|---|
| train team-seasons | 5,080 | 5,080 |
| Q1 enhanced R² | 0.721 | 0.721 |
| enhanced beats baseline | +0.0133 PPG | +0.0133 PPG |
| Q2 slope | +1.896 | +1.896 |
| Q2 p | 0.0024 | 0.0024 |
| graded-only p | 0.0036 | 0.0036 |

## One knob for the season span

`xx_last_data_season <- 2025` in `source_data.r`. Every analysis layer's season default now
derives from it (M3/M4/M5, strengths, CDE, style, fit, recommender, market benchmark,
event study, `augmented_model`, `midseason_analysis`, `tabler`). The SofaScore span is a
second, separate constant — `ss_seasons()`, derived from `ss_pl_season_ids` in both
`source_sofascore.r` and the chromote-free mirror in `player_archetypes.R`, so the two
copies of the id table cannot disagree about the span.

## refit_pipeline.R — the recipe is now code

The M3→M4→M5 driver existed only as prose in `Session_Log_2026-07-10b.md` ("save
coach_residuals/ranked/blups per cut, then `save_coach_grades()`"). It is now
`src/refit_pipeline.R`: `run_refit()` writes all four rds files per cut and grades both.

**Validated against the hand-run before use.** Pinned to ≤2024 and diffed against the
committed results: 14-league **max |numeric delta| = 0** across residuals, coach residuals,
ranked, BLUPs and grades; top-5 ≤1e-11 (lme4 optimizer noise). So everything that moved
after the real refit is attributable to the new season alone.

## What the refit changed

| | before (≤2024) | after (≤2025) |
|---|---|---|
| team-seasons (14lg) | 5,087 | 5,339 |
| coach stints | 8,207 | 8,642 |
| coaches with a BLUP | 959 | 1,006 |
| graded, 14-league | 545 | **566** |
| graded, top-5 | 215 | **224** |

Rank correlation on the 545 common coaches: **0.990**. Mean |ΔBLUP| 0.0030 PPG. No coach
lost his grade; 21 crossed the 109-game bar on 2025/26 games. Biggest movers are exactly
who you would expect from one strong season: Kompany +142 ranks (D+ → C), Eustace +115
(C → B), Nathan Jones +103; Scott Parker −91. Guardiola stays #1 in both cuts.

## The honesty cost, and where it is paid

The grades on coach pages are **no longer the grades test 3 validated** — they are a later
vintage that has since absorbed the tested season. Two surfaces carry this:

- **Validation page, test-3 card** — a `vintage` line: *"Grades shown elsewhere on this
  site now run through 2025/26, so they include it. This test used the earlier 2024/25
  vintage, which had never seen it."* Driven by `fwd$graded_through` /
  `site_graded_through` / `vintage_differs`. `se_export_validation()` takes the tested
  season from `ft$holdout$season`, never a site constant, so the page keeps describing what
  that run did as the fit window moves past it.
- **`How_It_Works.md` §"What the model has seen"** — replaces §"The holdout season" and
  explains the scrape → score → fold-in cycle, including the obvious objection (*if it was
  fitted to every season it shows, how is any of it a test?*).

Everything else from yesterday's holdout labelling was **removed, not kept** — leaving
"held out" chips on a season that is now fitted would be actively false. Gone from
`site_export.R` (the `holdout` column and all its JSON fields), `league.js` (banner),
`team.js` (footnote + tag), `coach.js` (tag), `home.js`, `compare.js`, and `site.css`.

## A real bug the new season exposed: one coach, two spellings

The export crashed in `se_rating_cut()` on `'length = 2' in coercion to 'logical(1)'`.
Root cause was not the export. **Transfermarkt re-spelled Ivan Juric as "Ivan Jurić" on
his 2025/26 page** while all nine earlier stints still read "Ivan Juric". `coach_id` (a TM
profile URL) was identical throughout — only the label changed.

`compute_coach_stats()` grouped by `(coach_id, coach_name)`, so this split one career into
a 9-stint row and a 1-stint row and produced **two entries in `coach_ranked_*`**.
`fit_mixed_model()` groups by `coach_id` alone, so `coach_blups_*` had **one** row and the
two tables silently disagreed about who existed. The crash was the lucky part: the quiet
failure mode is a coach appearing twice in the rankings with half a career each.

Fixed at the root, in three places:

- **`xx_canonical_coach_names()`** (new, `coach_attribution.R`) — one name per `coach_id`,
  taken from the **most recent** stint so a TM re-spelling propagates rather than being
  pinned to the oldest record. Applied inside `build_coach_residuals()`, so every
  downstream layer inherits it.
- **`compute_coach_stats()`** now groups by `coach_id` only, carrying the name along as a
  label. This is the invariant that was violated: id is identity, name is presentation.
- **`cs_build_team_xg()`** (`coach_strengths.R`) joined
  `coaches |> distinct(coach_id, coach_name)`, which for a two-spelling id is a
  one-to-many join that would have **duplicated his stint rows** rather than crashing.

Worth remembering because it is a data-source behaviour, not a one-off: any future season
can re-spell any name, and the failure is silent everywhere except the one place it
happened to hit a length-1 assumption.

## The archetype-relabelling hazard (checked, and it held)

`pa_archetype_labels` maps a **cluster index** (`D1`…`F3`) to a semantic name
("no-nonsense CB", "deep playmaker", …). K-means cluster indices are arbitrary, so
re-running `run_archetypes()` on an extra season could have permuted them and silently
mislabelled coach fit, style, the recommender, the builder and the site copy — with
nothing failing.

Checked properly rather than assumed: recovered the pre-run `archetypes.rds` from git,
joined on (`player_ss_id`, `season_start_year`) and cross-tabulated old vs new within each
position group.

| group | diagonal agreement | permuted? |
|---|---|---|
| D (4 clusters) | 98–100% | no |
| M (4 clusters) | 97–99% | no |
| F (3 clusters) | 98–100% | no |

Identity mapping on all 11, so the labels stand. `seed = 6` in `pa_kmeans()` is what makes
this reproducible. Independently corroborated by the printed profiles — D1 is still
clearances/aerials/defensive-third, D2 still passing volume and accuracy, D4 still key
passes and crosses. Added to CLAUDE.md as a required check after any re-clustering.

The `Quick-TRANSfer stage steps exceeded maximum` warnings are a Hartigan–Wong inner-loop
budget notice, not non-convergence; `nstart = 25` still returns the best of 25 starts.

## Incidental fixes

- **Four hand-typed "2015/16–2024/25" spans** in `coach.js`, `compare.js`, `builder.js`
  would have gone stale the moment the scrape lands. Now data-driven:
  `meta.dataset.sofascore_span` (computed from the archetype cache) via a new memoized
  `siteMeta()` in `components.js`; the builder derives its own span from its player pool.
- `charts.js expectedVsActual()` had "model frozen at 2024" baked into the axis label —
  now `opts.frozenAt` from the data.
- `se_export_builder()` filtered TM seasons to a literal `2015:2024`; now takes the span
  from `archetypes.rds`, so a TM season scraped ahead of its SofaScore counterpart cannot
  leak in player-less rows.
- `site_export.R` now fails loudly if `source_data.r` was not sourced first, instead of
  erroring obscurely on `xx_last_data_season`.

## SofaScore 2025/26

Season ids discovered from `/unique-tournament/{ut}/seasons`; the 2024/25 ids the endpoint
returned matched the existing constants exactly, which is the check that the convention
still holds.

| league | ut | 2025/26 season id |
|---|---|---|
| Premier League | 17 | 76986 |
| LaLiga | 8 | 77559 |
| Serie A | 23 | 76457 |
| Bundesliga | 35 | 77333 |
| Ligue 1 | 34 | 77356 |

Added to `ss_big5_leagues` **and** the `player_archetypes.R` mirror. Scrape running at the
documented 2–3s pacing (~12s per player once Chrome navigation is counted, ~15h for all
five leagues); fully resumable, no 403s. Layers waiting on it: archetypes, `coach_fit`,
`coach_style`, xG strengths, recommender, builder.

## What the extra season did to each layer

Adding a season is a free out-of-sample test of every claim in the repo, because none of
these numbers were fitted with it. They did not all move the same way, which is the useful
part:

| layer | before (through 2024/25) | after (through 2025/26) | direction |
|---|---|---|---|
| **M6 archetype fit** | χ² 21.3, p = 0.03; strict p = 0.0016 | χ² 26.1, **p = 0.0062**; strict **p = 0.00025** | stronger |
| **Event study** | +1.10, p = 0.004 | +1.167, **p = 0.0015** | stronger |
| **Market benchmark** (coach term) | p = 0.51 | **p = 0.96** | weaker (null) |
| **xG cut** FDR-significant | 0 of 57 (≥3 stints) | **0 of 89** | unchanged (null) |
| **CDE** repeatability | does not repeat | does not repeat | unchanged (null) |
| **Forward test** | p = 0.0024 | p = 0.0024 (frozen by design) | held |

The three positive results strengthened and the three nulls stayed null. Nothing crossed
in either direction, which is the best available evidence that the pipeline is not
overfitting to whatever era it was tuned on.

Detail worth keeping:

- **M6**: 1,628 big-5 stints (1,475 + **153 new**), wide-creator coefficient essentially
  unchanged (0.75 → 0.761) with a better t (3.19 → 3.48). Per-coach tests still 0
  significant of 1,704 after FDR — a global effect that still cannot name an individual.
- **xG cut**: 605 stints / 310 coaches / 89 with ≥3 stints / **7 now with ≥5** (previously
  none) — and still zero significant on all four measures. Creation's lag-1 repeatability
  fell 0.42 → 0.353, so its margin over finishing (0.246) is narrower than the 3-season
  sample implied; the docs were corrected rather than left standing. Cross-source tie-back
  to the goals cut *strengthened*, r = 0.960 / 0.981 over 605 stints.
- **Style**: 39,520 team-matches, 1,638 stints, 556 coaches; feature completeness ≥97% on
  all fourteen inputs.
- **CDE**: still "does not repeat — treat as noise"; orthogonal-variance share 92.8% /
  96.4%, inside the documented 93–96%.

## Market benchmark, refreshed through 2025/26

`od_data_populate(2025)` — all 11 football-data leagues have 2025/26 files. `mb_run()`
season arguments now derive from `xx_last_data_season`. Re-ran the leakage-free
walk-forward on **51,977 matches** (was 51,807).

**The null held and got stronger** — every p moved *further* from significance:

| | 2012–2024 | 2012–2025 |
|---|---|---|
| log-loss, model vs market | 1.014 vs 0.978 | 1.015 vs 0.979 |
| value, incremental to market | p = 0.31 | **p = 0.29** |
| coach BLUP, incremental | p = 0.51 | **p = 0.96** |
| low-profile-manager subgroup | p = 0.32 | **p = 0.68** |
| P&L, closing prices | −6.4% ROI | −6.6% (CI −8.2% to −5.1%) |
| P&L, 2% haircut | −9.9% | −7.8% |

The market still prices both squad value and coaching quality. Worth noting the direction:
a *weakening* result on an added year is what a real null looks like — if the coach term
had drifted toward significance as data accumulated, that would have been the signal to
re-examine it.

Odds reconciliation still passes: fd-derived season points match `matches.rds` on the
2,981 checked team-seasons outside the known Belgian-playoff and Portuguese
fixture-count differences.
