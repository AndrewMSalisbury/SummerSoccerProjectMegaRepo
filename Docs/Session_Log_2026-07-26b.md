# Session Log — 2026-07-26b

Built the **coach grade history** ("grade over time") card end to end: design →
data layer → verification → export → chart → render check. Design doc:
`Docs/Coach_Grade_History_Design.md` (updated in place with the **[as built]**
corrections below).

## What shipped

- `grade_blup_table()` factored out of `save_coach_grades()` (`coach_attribution.R`)
  — the certification bar + grade curve as one shared function, so the history
  replays the published pipeline instead of forking it. Verified a no-op: both
  `coach_grades_*.rds` byte-identical after the refactor (224 / 566 rows).
- `src/coach_grade_history.R` (`gh_` prefix), a pure results-reader over
  `mb_prep.rds`. Per vintage: M3 lm on `season < cutoff` → stint partial residuals
  → `fit_mixed_model()` → `add_significance()` → `grade_blup_table()`. Writes
  `coach_grade_history_{top5,14league}.rds` plus a per-vintage cache in
  `data/results/grade_history/`.
- `se_grade_history()` + `history` in the coach JSON; `gradeTimeline()` in
  `charts.js`; `renderGradeHistory()` in `coach.js`, placed between the career-PPG
  chart and the strengths card. Coach-page `min_cards` raised 5 → 6 and 3 → 4.

## Three decisions the user made up front

Cut = match the headline grade (both cuts built); y = numeric grade with the curve
**re-fit per vintage**; **certified vintages only**; line not bars. The last two
combine into the acceptance test: re-fitting the curve each year means the final
vintage *is* the live fit, so it must reproduce the grade card exactly.

## Verification — all exact

| Check | Result |
|---|---|
| Endpoint vs `coach_grades_top5.rds` | PASS, max \|Δgrade\| **0.00e+00**, 224/224 coaches, ranks + letters identical |
| Endpoint vs `coach_grades_14league.rds` | PASS, max \|Δgrade\| **0.00e+00**, 566/566 |
| BLUPs vs `mb_asof_blups.rds` (2008–2025) | 18/18 vintages match, worst \|Δblup\| **0.00e+00** |

## Two things the data corrected

**1. The proposed thin-vintage guard was the wrong instrument.** The design guarded
on graded-pool size (`gh_min_pool = 40`). The actual failure mode is a **degenerate
variance component**: lme4 puts the coach random effect on the zero boundary, every
BLUP comes back exactly 0, `grade_coaches()` divides 0 by 0, and every coach in the
vintage gets `NaN` — which `to_letter()` silently renders as **"F"**. Top-5 2008/09
did this **with 44 graded coaches**, sailing past a pool ≥ 40 test. Replaced with the
M5 **LRT** the pipeline already computes (`gh_max_lrt_p = 0.05`) plus `blup_sd > 0`,
pool size kept as secondary, and a `stopifnot` backstop.

Then the LRT guard produced a *hole* rather than a prefix: top-5 2016/17 fails at
p = 0.064 while 2015/16 and 2017/18 pass. A line that flickers in and out at a
threshold is worse than a shorter one, so only the **contiguous run ending at the
endpoint** is published.

Per-vintage LRT p (top5 / 14league), cutoff labelled by last completed season:

| Season | top5 | 14league |
|---|---|---|
| 2007/08 | 1.000 (all-NaN) | 0.121 |
| 2008/09 | 1.000 (all-NaN) | 0.106 |
| 2009/10 | 0.832 | 0.057 |
| 2010/11 | 0.473 | pass |
| 2011/12 | 0.233 | pass |
| 2012/13 | 0.378 | pass |
| 2013/14–2015/16 | pass | pass |
| **2016/17** | **0.064** | pass |
| 2017/18–2025/26 | pass | pass |

Published windows: **top5 2017/18→2025/26 (9)**, **14league 2010/11→2025/26 (16)**.
So the coach effect is only *continuously* detectable in the big-5-only cut from
2017/18 — a real fact about that cut's power, worth remembering before anyone treats
a top-5 p-value from a thin era as meaningful.

**2. The grade scale clamps, and the site's #1 coach is pinned to it.**
`grade_coaches()` applies `pmin(100, …)`, so **Guardiola's line is 100.0 at all nine
vintages** — perfectly flat. Extent: 2.5% of top-5 points and 1.2% of 14-league
points at the ceiling; 3 top-5 and 2 14-league coaches wholly flat. Not an error —
his published grade genuinely has been A+ 100 each year and the card above agrees —
so it is explained rather than rescaled: `renderGradeHistory()` emits a note when any
point is clamped, with distinct wording for a wholly-flat line, and the tooltip's
points-above-expectation keeps moving underneath. Un-clamping would invent grades
above 100 and break the endpoint identity.

## Cost

The design estimated 10–25 minutes for ~76 `lmer` fits. Actual: **~30 seconds**,
≤1s per vintage. The per-vintage cache is convenience, not necessity.

## Consequence worth knowing

Because the chart reads the **same cut as the headline grade**, a top-5-headline
coach gets a 9-point line and a 14-league-only coach up to 16. That is the honest
reading of the user's choice, but it is the lever to pull if a longer line is ever
wanted (show the 14-league history to everyone, explicitly labelled).

## Roll-forward

`gh_run_all()` is now a step in the roll-forward recipe, after `run_refit()` and
before `export_site_data()`. It must be re-run after **any** M4/M5 refit — the
endpoint check fails loudly if it is skipped, which is the intended behaviour.

## Render check

`src_render_check()`: 0 failures of 9 pages. Coach pages 6 cards (was 5), no console
errors, no unhandled rejections. Screenshots of Conte (rising then pinned) and
Guardiola (wholly flat, with the note) confirmed the card renders as intended.
