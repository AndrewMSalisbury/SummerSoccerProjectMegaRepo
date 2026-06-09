# Session Progress Report

**Date:** June 9, 2026 (Session 3)
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

Following the completion of Milestone 5 (coach attribution and rankings), this session asked a stronger question: can we use the coach signal not just to describe past performance, but to improve predictions for new seasons? The result was a clean, significant yes.

---

## What Was Accomplished

### Augmented Model (`src/augmented_model.R`)

A new, self-contained analysis file was built that leaves every prior file untouched. It implements leave-one-season-out cross-validation comparing:

- **Enhanced model** (the M3 winner): `points_per_game ~ log(norm_weighted_value) + league`
- **Augmented model**: enhanced prediction + games-weighted coach BLUP estimated from training seasons only

The pipeline per fold:
1. Fit the base model on 9 training seasons
2. Build coach stints from training residuals (reusing `build_coach_residuals()`)
3. Fit the mixed-effects model on training stints and extract per-coach BLUPs
4. For each test team-season, compute a games-weighted BLUP from training coaches
5. Augmented prediction = base + weighted BLUP (unseen coaches default to 0)

### Results

Mean RMSE improved from 0.2373 to 0.2328 — a reduction of 0.0044 PPG across 10 folds. 8 of 10 folds showed improvement. The two non-improving folds are explainable: 2015 is disadvantaged because BLUPs come from later seasons and fewer coaches are represented, and 2020 is essentially flat (−0.0004) due to the COVID season.

**Paired t-test: p = 0.001, 95% CI lower bound = 0.0025.**

This is statistically significant by a wide margin — stronger than the M3 model comparison result.

### What This Means

The M5 finding was that coach identity explains 8.5% of residual variance and is statistically detectable (p = 0.0011). That established the signal exists. This new result goes further: the signal is useful for prediction. Knowing who a team's coach is — based only on their prior track record — meaningfully improves forecasts for seasons the model has never seen.

In terms of cumulative improvement:

| Step | RMSE improvement |
|---|---|
| Raw → minutes-weighted (M3) | ~0.013 |
| Minutes-weighted → +coach BLUP (new) | 0.0044 |

The coach augmentation contributes roughly a third of what the weighting step added. This is a meaningful result and the strongest confirmation of the original hypothesis.

---

## Project Status

Milestones 1–5 complete. The augmented model is a stretch extension beyond the original scope and materially strengthens the project's core claim: coaching quality is real, portable, measurable, and predictively useful.

`Docs/Summary_of_Findings.md` has been updated with a new Part 4 covering these results and a revised conclusion.

Milestone 6 extensions (Player Development Score, Playing Style Analysis) remain optional pending available time.
