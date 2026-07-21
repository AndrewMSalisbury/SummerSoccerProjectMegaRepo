# Session Log — 2026-07-21: Testing the club-size confound in the coach BLUP

## Trigger

Andrew: "lets look into the confound." The 2026-07-16b log flagged
`r(club_pct, blup) = +0.39` — coaches at bigger clubs grade higher — as "the most
load-bearing untested claim in the project": benign if better coaches are hired by
bigger clubs, a mis-specification if the M3 value model under-predicts big clubs and
that leaks into the coach effect. The published ranking rests on which it is. This
session tests it. **Analysis only — Andrew chose "document only"; nothing in the
pipeline was changed.**

## Verdict (up front)

The confound is **overwhelmingly benign selection, not mis-specification.** The
published ranking is robust. There is one genuine but small, now-quantified,
out-of-sample-validated exception: a top-decile curvature in the linear-in-log value
term that modestly inflates the grades of coaches permanently at the very biggest
clubs — without reordering them.

## The identification problem

A residual tilt by club size is consistent with **both** hypotheses:

- **H_selection (benign):** good coaches → big clubs; the coach effect is genuinely
  theirs and the correlation is composition.
- **H_misspec (a bug):** the value model under-predicts big clubs, so their residual
  is positive regardless of coach, inflating big-club coaches' BLUPs.

The team-season residual tilt alone cannot separate them (good coaches clustering at
big clubs *produces* a value-correlated tilt). Two structural facts shaped the test:

1. The M3 residual is **OLS-orthogonal to `log(norm_weighted_value)`** by
   construction, so any tilt vs *weighted-value* percentile is mechanically ~0. But
   `club_pct` is built from **raw `total_team_value`** percentile — so the confound,
   if real, lives in the total-vs-weighted gap or the value curve's shape.
2. The M5 mixed model **already carries `(1|club_id)`**, which is meant to absorb
   club-level mis-specification. The +0.39 surviving that is the puzzle.

## What I ran (`scratchpad/confound_probe.R`, `robustness_refit.R`, `cv_form.R`)

Reads `residuals_14league.rds`, `coach_residuals_14league.rds`,
`coach_blups_{top5,14league}.rds` — no scrape, no model re-plumb.

### 0. Reproduced the confound

Games-weighted `r(club_pct, blup)`: **+0.30** (top-5, 334 coaches), **+0.21**
(14-league, 959). The doc's +0.39 was the 231-coach Layer-C style-overlap subset —
same phenomenon, narrower denominator. Bigger-club coaches do grade higher.

### 1. The symptom is nearly absent at team-season level

| axis | r(residual, ·) |
|---|---|
| log(norm_weighted_value) | −0.00 (mechanical sanity — passes) |
| weighted-value pct (within season) | +0.06 |
| **total-value pct (the confound axis)** | **+0.02 (ns, p = 0.13)** |

The club-size tilt is essentially flat across deciles 1–9. **Only the top decile**
(the single biggest club per league) shows a bump: **+0.081 PPG ≈ +2.75 pts/season.**
Slope `residual ~ tot_pct` predicts a top-vs-bottom gap of only +0.017 PPG (~0.6
pts/season).

### 2. The top-decile bump is a small linear-in-log curvature artifact

Refitting M3 with a flexible value term: curvature is significant (quad F = 250,
p < 2e-16; spline-4 adds more, p = 9e-8). A natural spline flattens the top decile
**+0.081 → +0.022** and lifts the bottom **+0.023 → −0.029**. So linear-in-log
genuinely under-predicts the very top — a real but small mis-specification.

### 3. Decisive test — within-coach club-size slope

Mundlak split of total-value pct into between-coach and within-coach parts,
`resid ~ club_between + club_within + (1|coach) + (1|club)`, games-weighted (6,409
stints, 959 coaches, 457 clubs; within-coach SD of club_pct = 22.8 pts, so the
variation exists):

| term | estimate | t | reading |
|---|---|---|---|
| **club_between** | +0.00087 | +4.2 | bigger-club coaches grade higher — *this is the confound* |
| **club_within** | **−0.00085** | **−5.0** | *same* coach at his bigger clubs overperforms **less**, not more |

Cross-checked with coach fixed-effects OLS: within slope −0.00086, t = −5.3,
p = 1e-7. **Mis-specification requires a positive within-coach slope** (if the model
under-credited big clubs, a coach moving up would overperform more). It is robustly
**negative** — the opposite. The between-coach correlation is therefore selection
(which coaches are at big clubs), not the value model under-crediting them. Same
Simpson's-paradox instrument phase 5 used to kill lineup stability, same reversal.

(A residual *fixed* `club_pct` slope on top of the coach+club random effects is
−0.0002, t = −1.4, ns — no value structure survives the REs.)

### 4. Robustness — refit BLUPs with the corrected (spline) value term

Only `predicted_ppg` per team-season changes (attribution untouched), so stint
residuals recompute directly. Refit the M5 mixed model:

- ranking essentially unchanged: **Pearson r = 0.978, Spearman rank r = 0.976**,
  mean |ΔBLUP| = 0.005 (BLUP SD 0.023);
- confound shrinks **+0.213 → +0.164** — about a quarter of it was the curvature
  artifact;
- the coaches pulled down are exactly the permanent-elite names: **Guardiola
  0.137→0.093, Ferguson 0.107→0.076, Conte 0.090→0.064, Ancelotti 0.015→−0.010,
  Mourinho 0.029→0.007** — but **Guardiola still ranks #1.**

### 5. The curvature is real signal, not overfitting

Leave-one-season-out CV (the project's own instrument): spline value term beats
linear by **0.006 PPG (2.55%), paired p = 0.0017, winning 17 of 20 season folds.**
So the under-prediction of the top is a genuine, OOS-validated functional-form fact —
just small.

## What this means for the project

- **The loose-end fear is dispelled.** The ranking does *not* "rest on" whether the
  value model under-predicts big clubs. The within-coach slope is the wrong sign for
  that story, and the order survives the correction nearly intact (rank r = 0.98).
- **The confound is ~75% selection + ~25% a small top-club curvature.** The residual
  +0.16 is benign composition (good coaches at big clubs, effect genuinely theirs).
- **A small, honest caveat now exists and is documented:** linear-in-log inflates the
  grades of coaches permanently at the very biggest clubs by ~0.02–0.04 PPG. It is
  OOS-real but does not reorder the leaderboard.
- **This does not rescue Layer C.** The style→quality null stands for its own
  reason — style axes are near-proxies for club size and their causal content is not
  identifiable from between-coach correlations. Resolving the BLUP confound is a
  separate question from whether *style* explains quality.

## Decision (Andrew): document only

The spline value term is genuinely OOS-better and shrinks the confound, but adopting
it ripples through the entire chain (M4 → M5 → strengths → style residualization →
recommender → grades → site) for a ~0.005 PPG average BLUP move and no reordering.
Not worth re-plumbing. Recorded instead:

- `Docs/Summary_of_Findings.md` — Part 8 Layer C confound paragraph updated from
  "the BLUP cannot say … untested" to the tested resolution; Limitations item 9
  gains the within-coach result and the elite-club curvature caveat.
- `CLAUDE.md` — the `coach_style.R` confound note updated to point at this resolution
  so it is not re-flagged as open.
- Regenerated `site/writeup.html` from the edited markdown via `se_export_writeup()`
  (writeup only — no full site re-export, no data change).

## Reproducing

```r
# working dir src/ — pure cache/results reader, no scrape
Rscript scratchpad/confound_probe.R      # tests 0–4 (reproduce, tilt, form, within-coach)
Rscript scratchpad/robustness_refit.R    # BLUP stability under a spline value term
Rscript scratchpad/cv_form.R             # LOSO-season CV: linear vs quad vs spline
```

(Scripts live in the session scratchpad; they read only from `data/results/`.)

## Loose ends / next

- **If the confound is ever to be driven lower**, the spline value term is the lever
  (0.21 → 0.16, OOS-validated) — but it is a full-pipeline refit. Parked as
  not-worth-it unless the ranking's top-club precision becomes load-bearing.
- The other standing open item is unchanged: the team-builder squad-fit panel and
  2025/26 `rating-breakdown` archetype validation, both previously judged low-value.
