# Coach Grade History — Design

A "grade over time" line on each coach page: the grade this site **would have
published** at the end of each past season, recomputed from scratch on data
available only up to that point.

Status: **built 2026-07-26** (`src/coach_grade_history.R`, session log
`Docs/Session_Log_2026-07-26b.md`). Sections marked **[as built]** record where
the design was corrected by what the data actually did.

---

## 0. What this is, and its honesty label

**Descriptive-clean, with one caveat that must be in the copy.** Every point is a
faithful replay of the site's own published pipeline (M3 → M4 → M5 → certification
bar → grade curve) restricted to completed seasons before a cutoff. Nothing new is
estimated and no new attribution leap is made, so the line can be stated plainly.

The caveat: because the grading curve is **re-fit at every vintage** (decision §1.3),
a point is a coach's standing *against the cohort of that era*, not a fixed physical
quantity. A coach can move a little without playing a game, because the pool around
him changed. That is the correct reading of "what the grade would have been," and it
is what the footnote must say.

**This is not a form chart.** It is a cumulative career-to-date verdict, and it will
look heavily smoothed — early stints never leave the sample. The per-season
performance chart already on the coach page ("Career points per game") is the form
view; this card sits below it and answers a different question. Do not let the two
drift into looking like the same chart with different axes.

## 1. The quantity

### 1.1 Vintage semantics

A vintage is indexed by an integer **cutoff `C`**, meaning *fit on team-seasons with
`season < C`*. The last completed season in the fit is therefore `C - 1`, and the
point is **labelled by that season** — cutoff 2025 renders as `2024/25`. Never label
a point with the raw cutoff; it is off by one against everything else on the site.

The final point is `C = xx_last_data_season + 1` (2026 → `2025/26`), which is the full
dataset — i.e. the live fit behind the coach's grade card.

### 1.2 One vintage = a full replay of `save_coach_grades()`

Per cutoff `C` and per cut (`top5`, `14league`):

1. `lm(points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team)`
   on the cut's team-seasons with `season < C` and both normalized values `> 0`.
   This is byte-for-byte the `compute_residuals()` spec (`residual_analysis.R:9-17`) —
   verified, not assumed.
2. Attach `predicted_ppg` to the model-independent stint table, form
   `partial_residual_ppg = actual_ppg - predicted_ppg`, drop NAs.
3. `fit_mixed_model(st, min_games = 10, min_stints = 3)` → that vintage's BLUPs.
4. `add_significance(compute_coach_stats(st, min_games = 10, min_stints = 1))` →
   that vintage's FDR-significant ids.
5. Certification bar and curve: `total_games >= 109 | significant`, then
   `grade_coaches()` on the survivors, then `rank = row_number()`.

Step 5 is exactly what `save_coach_grades()` does today. **It must not be
reimplemented.** Factor the per-cut body of `save_coach_grades()` into

```r
gh_grade_from_blups <- function(blups, sig_ids, min_games_graded = 109)
```

and have `save_coach_grades()` call it. This is the same discipline
`coach_strengths.R` follows in reusing `fit_mixed_model()` / `compute_coach_stats()`
verbatim: if the bar or the curve ever changes, the history must move with it, and a
fork would silently not.

### 1.3 Decisions taken (2026-07-26)

| Decision | Choice | Consequence |
|---|---|---|
| Cut | Both; the chart shows the **same cut as the headline grade** | Needs a top-5 as-of series, which does not exist yet (§2.2) |
| Y quantity | Numeric grade 0–100 | Same unit as the grade card |
| Curve | **Re-fit per vintage** | Each point = what would have been published that year; cohort drift is real and must be footnoted |
| Sub-bar vintages | **Not shown** | Line starts the season he first clears 109 games (or goes FDR-significant); consistent with the site's rule that sub-bar coaches get no grade anywhere |
| Form | Line | It is a carry-over cumulative quantity, not a per-period one |

The combination of "re-fit curve" + "certified only" buys a hard consistency
property: **the last point equals the grade card by construction**, because vintage
`xx_last_data_season + 1` *is* the live fit. That is the acceptance test (§3.1).

**[as built]** All three verifications pass exactly: endpoint max |Δgrade| =
`0.00e+00` for both cuts with identical coach sets (224 / 566), ranks and letters;
and 18/18 vintages reproduce `mb_asof_blups.rds` to `0.00e+00`. Note the consequence
of the cut decision plus §3.3: a top-5-headline coach gets a **9-season** line while
a 14-league-only coach gets up to **16**, because the two cuts have different
publishable windows. That is the honest reading of "the same cut as the grade above
it", but it is the one thing a reader might find odd, and it is the lever to pull if
a longer line is ever wanted (show the 14-league history to everyone, and label it).

### 1.4 Series continuity

`total_games` and `n_stints` are cumulative, so once a coach clears the 109-game bar
he never falls below it — the series is contiguous for the overwhelming majority.
The one way to drop out is a coach admitted *only* by the FDR exemption (as of
2026-07-14, exactly one: Xavi at 103 games) who later loses significance while still
under 109 games. Handle it by **breaking the path into segments at gaps** rather than
interpolating across them; do not forward-fill a grade the model did not produce.

## 2. Data layer — `src/coach_grade_history.R` (`gh_` prefix)

Pure results-reader. No scraping, no chromote. Sources `coach_attribution.R` (which
chains `residual_analysis.R` → `model_comparison.R` → `tabler.R`) for the M3/M5
functions, and reads `data/results/mb_prep.rds`.

### 2.1 Inputs

`mb_prepare()`'s cache (`mb_prep.rds`) already holds both cutoff-independent inputs:

- `$ds` — 5,339 team-seasons, 2005–2025, all 14 leagues, with `norm_weighted_value`.
- `$stints` — 8,642 model-independent coach-stint actuals (`n_games`, `actual_ppg`,
  `date_from`), built through `build_coach_residuals()` at the standard
  `min_coverage = 80`.

Nothing needs rebuilding. If `mb_prep.rds` is absent, call `mb_prepare()`.

### 2.2 The two cuts

**`norm_total_value` / `norm_weighted_value` are normalized within each
league-season** (`model_comparison.R:340-341`), so they do not depend on which
leagues are in the frame. Therefore filtering `$ds` and `$stints` to the big-5
league slugs yields exactly the rows `build_model_dataset(leagues = rp_cuts$top5)`
would produce, and the top-5 as-of series needs no new dataset build. Take the
league vectors from `rp_cuts` in `refit_pipeline.R` — do not re-declare them.

### 2.3 Extending the as-of BLUP function

`mb_asof_blups()` returns only `(coach_id, blup)`; grading needs `coach_name`,
`n_stints`, `total_games`, `n_clubs` as well, plus the significance table. Add

```r
gh_asof_vintage(ds, stints, cutoff)   # -> list(blups = <full coach_blups>, sig_ids = <chr>)
```

carrying the same `min_games = 10, min_stints = 3`. Leave `mb_asof_blups()` alone —
`market_benchmark.R` and `event_study.R` both depend on its current shape and on the
`mb_asof_blups.rds` cache, and the event study's leakage rule is keyed to it.

### 2.4 Output

```r
gh_run_all(cuts = c("top5", "14league"), cutoffs = 2008:(xx_last_data_season + 1))
```

writes `data/results/coach_grade_history_<cut>.rds`: one row per
(coach, vintage) for **certified** coaches only —

`coach_id, cutoff, season (= cutoff - 1), blup, numeric_grade, letter_grade, rank,
n_graded, total_games, n_stints`

plus an attribute or sibling meta table recording, per vintage: `n_blups`,
`n_graded`, `blup_mean`, `blup_sd` (the curve constants), and `n_team_seasons`.
That meta is what makes an odd-looking line diagnosable later.

Cache per vintage on disk and skip completed ones, so the run is resumable and a
roll-forward year only costs the new vintage.

### 2.5 Cost — **[as built: ~30 seconds, not 10–25 minutes]**

One `lm` plus `fit_mixed_model()` (which fits **two** `lmer` models, null and full)
per vintage per cut: 19 vintages × 2 cuts ≈ 76 `lmer` fits on up to 8.6k rows. The
estimate of 10–25 minutes was an order of magnitude too pessimistic — the whole run
is **~30 seconds** (≤1s per vintage). The per-vintage disk cache is therefore
convenience rather than necessity, and `refresh = TRUE` is cheap enough to be the
default habit after any refit. The 14-league BLUPs for cutoffs 2008–2025 already
exist in `mb_asof_blups.rds` but carry only two columns, so they are a cross-check
(§3.2), not a shortcut.

## 3. Verification — required before export

### 3.1 Endpoint identity (acceptance test)

For both cuts, vintage `xx_last_data_season + 1` must reproduce
`coach_grades_<cut>.rds` — same coach set, same `numeric_grade`, `letter_grade`,
`rank`. Tolerance: exact on the coach set and ranks; `1e-9` on the numeric grade
(lme4 optimizer noise, the same tolerance `refit_pipeline.R` was validated at). A
mismatch means the replay has drifted from the published pipeline and the chart must
not ship.

### 3.2 Cross-check against the existing cache

For cutoffs 2008–2025, 14-league: `gh_` BLUPs must match `mb_asof_blups.rds` on
`coach_id` and `blup`. This is free and catches a wrong filter in the cut plumbing.

### 3.3 Thin-vintage guard — **[as built: the proposed guard was wrong]**

The design proposed guarding on **graded-pool size** (`gh_min_pool = 40`). Measuring
first, as instructed, showed that guard does not catch the actual failure mode.

**The real failure is a degenerate variance component.** On a thin sample lme4 puts
the coach random effect on the zero boundary; every BLUP returns exactly 0;
`grade_coaches()`' z-score divides 0 by 0; every coach in the vintage gets `NaN`,
which `to_letter()` silently renders as **"F"**. Top-5 2008/09 did exactly this
**with 44 graded coaches** — i.e. it sailed past a pool ≥ 40 test.

The guard is therefore the vintage's own evidence that a coach effect exists at all:
the **M5 LRT** that `run_milestone5()` already reports (`gh_max_lrt_p = 0.05`), plus
`blup_sd > 0` and the pool-size test kept as a secondary. If the model cannot detect
a coach effect in that year's data, it has no business printing coach grades for it.
A `stopifnot` on `is.na(numeric_grade)` backstops the whole path.

**Publish the contiguous run ending at the endpoint, not every passing vintage.**
The top-5 LRT wobbles across 0.05 in the mid-2010s (2015/16 passes, 2016/17
p = 0.064, 2017/18 passes), so cherry-picking passers punches a hole in the middle of
every top-5 coach's line, and a series that flickers in and out at a threshold
communicates worse than a shorter one. This also gives the line's start a meaning a
reader can be told.

Measured LRT p by vintage (see session log for the full table):

| Cut | Vintages fit | Published | Window | Dropped because |
|---|---|---|---|---|
| `top5` | 19 (2007/08–2025/26) | **9** | 2017/18 → 2025/26 | 2007/08–2008/09 degenerate (all-NaN); 2009/10–2012/13 LRT p 0.23–0.83; **2016/17 p = 0.064** truncates the window |
| `14league` | 19 | **16** | 2010/11 → 2025/26 | 2007/08 p = 0.121, 2008/09 p = 0.106, 2009/10 p = 0.057 |

So the coach effect is only continuously detectable in the big-5-only cut from
2017/18 — a real finding about the top-5 cut's power, not a display choice.

Also require **≥ 3 published vintages** for a coach before the card renders; a
two-point line is not a history. Result: 208 of 224 top-5 and 520 of 566 14-league
coaches get a card.

### 3.4 Grade clamping — **[as built: found at render, not modelled for]**

`grade_coaches()` clamps to `pmin(100, pmax(0, …))`, so a coach more than ~2.5 SD
above the mean saturates. **Guardiola's line is 100.0 at all nine vintages — a
perfectly flat line.** Extent: 2.5% of top-5 points and 1.2% of 14-league points sit
at the ceiling; **3 top-5 and 2 14-league coaches have a fully flat line**.

This is not an error — his published grade really has been A+ 100 every one of those
years, and the card above the chart says the same. Un-clamping the chart would
manufacture grades above 100 that disagree with the grade card and break the §3.1
identity, so **the fix is to explain it, not to rescale it**: `renderGradeHistory()`
emits a note whenever any point is clamped, worded differently for a wholly-flat line
("the scale stops at 100, not his record"), and the tooltip's
points-above-expectation keeps moving underneath. Do not "fix" this by giving the
history its own uncapped curve.

## 4. Export — `site_export.R`

- Load both history files in `se_load()` alongside the existing grade tables.
- `se_grade_history(d, coach_id, rating)` — returns `NULL` when `rating` is `NULL`
  (ungraded coaches get no card, same gate as `se_coach_strengths()`), otherwise
  reads the **same cut as `rating$cut`** and emits:

```
{ cut, cut_label, min_season, max_season,
  points: [ { season, grade, letter, rank, n_graded, blup, games } ] }
```

  `season` is `cutoff - 1` so the frontend never sees a cutoff integer.
- Add `history` to the coach JSON in `se_export_coaches()`. Payload is ~19 small
  objects per coach — negligible.
- `I()` is not needed here (`points` is a list of lists, never length-collapsed), but
  any scalar vector added later must follow the `auto_unbox` rule.

## 5. Frontend

### 5.1 `charts.js` — `gradeTimeline(host, points, opts)`

A new export rather than a reuse of `lineChart()`: that helper hard-codes a
zero-based y domain and a single end label, and this chart needs a grade-scaled axis
and letter context. Follow its idioms (`measuredWidth` / `onResize` / `tooltip` /
`chartSvg` / `yAxis`).

- **Y domain**: pad the coach's own range, but clamp to a minimum span of ~10 grade
  points, so a coach who sat between 84.1 and 85.3 does not render as a mountain
  range. Never a zero-based axis — a 0–100 axis flattens every real career.
- **Reference line at 75** (the cohort mean by construction, at every vintage),
  hairline, labelled "average". This is the single most important piece of context on
  the chart: without it, "78" means nothing.
- **X axis**: season labels via `fmtSeason`, thinned by the existing `every`-nth
  pattern in `lineChart()` for narrow viewports.
- **Marks**: 2px path in `--series-1`, small dots at each vintage, filled end dot with
  a direct label carrying the letter grade (the site's selective direct-label idiom).
  Segments broken at gaps (§1.4).
- **Tooltip** per point: season, letter + numeric grade, `rank of n_graded`, BLUP in
  PPG, cumulative games. Rank is free from the export and is the most intuitive read.
- One hue. No diverging ramp — there is no good/bad polarity to encode beyond the
  75 line.

### 5.2 `coach.js` — `renderGradeHistory(c)`

Card placed **directly after** `renderChartCard(c)` (career PPG) and before
`renderStrengths(c)`, so the page reads: what he did → how the verdict on him
firmed up → where the edge came from → style. Gated on `c.history && c.history.points.length >= 3`.

Copy:

- Title: **"How his grade developed"**
- Sub: "The grade this model would have given at the end of each season, using only
  the data available at the time. Line starts when his record first cleared the
  grading bar (3 stints and 109 league games)."
- Footnote: "Each season's grade is set against the coaches known at that point, so
  the line can shift slightly as the pool of graded coaches grows. Grades are
  cumulative — a strong season moves a long career less than a short one."
- Cut label ("Top-5 leagues" / "All leagues") is **mandatory**, as everywhere grades
  render.

### 5.3 `site_render_check.R`

Raise the coach page's `min_cards` by one. The numbers there are a contract — the
2026-07-26 silent-ReferenceError incident is exactly what this catches.

## 6. Copy traps to avoid

- Never write "his grade in 2015". It is "his grade **as of** 2015" — a career-to-date
  verdict, not a season rating.
- Never present a rise as improvement in the coach. A rise means the accumulated
  evidence moved, which is usually *more* evidence rather than *better* results.
- The early part of any long career is fit on a thin dataset (133 coaches at cutoff
  2008 vs 959 at 2025), so the shrinkage toward the prior is heavier and early points
  sit closer to 75 than late ones. This is a property of the method, not of the coach.
  If it turns out to visibly dominate the shape of most lines, say so in the footnote.

## 7. Roll-forward integration

Add to the roll-forward recipe in `CLAUDE.md`, after `run_refit()`:

```r
source("coach_grade_history.R"); gh_run_all()   # adds one vintage, ~1-2 min
```

Because the per-vintage cache is keyed by cutoff, this only fits the new year. The
history files must be regenerated after **any** M4/M5 refit — a refit changes the
endpoint, and §3.1 will fail loudly if it was skipped, which is the intended
behaviour.

## 8. Build order

1. Factor `gh_grade_from_blups()` out of `save_coach_grades()`; confirm
   `save_coach_grades()` still reproduces `coach_grades_*.rds` exactly.
2. `coach_grade_history.R`: `gh_asof_vintage()`, the two-cut driver, per-vintage
   caching, `gh_run_all()`.
3. Run it. Record per-vintage pool sizes; set `gh_min_pool`.
4. Verification §3.1–§3.3. Do not proceed on a failure.
5. `se_grade_history()` + coach JSON.
6. `gradeTimeline()` + `renderGradeHistory()`.
7. `export_site_data()`, then `src_render_check()` with the bumped `min_cards`.
8. Session log entry; update `CLAUDE.md` (new layer section + roll-forward step).
