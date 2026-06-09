# Session Progress Report

**Date:** June 9, 2026 (Session 2)
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

This session completed Milestone 5: Coach Attribution & Rankings. Building on the validated residuals table from M4, the session implemented the full coach attribution pipeline, produced a ranked list of coaches, and wrote the project's primary deliverable — the summary of findings.

---

## What Was Accomplished

### Methodology: Partial Attribution Rule

The mid-season change rule was redesigned from scratch. Rather than assigning the full season residual to whichever coach managed more than 60% of games, each match is now attributed to the coach in charge on that date using Transfermarkt appointment date brackets. Each coach receives:

`partial_residual_ppg = (actual_points_in_stint / games_in_stint) − predicted_ppg`

where `predicted_ppg` is the squad-value model's season-level prediction (constant within the season). Matches in coverage gaps are dropped from both actual and expected. This approach attributes every game cleanly without excluding any team-seasons due to coaching changes.

### Attribution Pipeline (`src/coach_attribution.R`)

The full pipeline was built across a series of steps. Key results from running it:

- **99.9% team-season coverage** (975/976 — SC Freiburg 2018 is the one gap)
- **99.4% match attribution rate** — only 226 of 36,022 matches dropped due to caretaker gaps
- **35.5% of team-seasons had a mid-season change** (346/976)
- **129 stints of ≤5 games** — all confirmed as genuine caretaker appointments, not scraping errors

### Coach-Level Statistics

With minimum thresholds of 10 games and 3 stints, 194 coaches were included in the ranking. The per-coach t-test with BH FDR correction found only one statistically significant coach: **Pep Guardiola** (10 stints, 376 games, +0.39 PPG, 95% CI [0.26, 0.52]). This is a sample size constraint — most coaches have 3–5 stints, giving too few degrees of freedom for individual significance.

### Mixed-Effects Model: The Central Finding

A mixed-effects model decomposing partial residual PPG into coach and club variance components produced the project's headline result:

- **Coach variance: 8.5%** of total variance
- **Club variance: 4.9%** of total variance
- **LRT: χ² = 10.64, p = 0.0011**

Coach identity explains significant variance in performance above expectation after accounting for club-level effects, and coach variance exceeds club variance. The coaching effect is portable — it follows the manager more than it stays at the club. This directly supports the project hypothesis.

The BLUP rankings place Guardiola, Klopp, Tudor, Conte, and Spalletti at the top — names broadly consistent with external assessments of coaching quality. The most notable portability finding is **Davide Nicola** (9 stints, 7 clubs, consistently positive) and **Eusebio Di Francesco** (9 stints, 7 clubs, consistently negative), both providing strong evidence that the effect travels with the coach.

### Tenure Effect Analysis

A theory was proposed and tested: that a coach's first season at a club should show the highest residual because strong year 1 performance raises player market values, compressing the apparent residual in subsequent years even if coaching quality is unchanged.

The year 2 dip is a genuine descriptive finding — residuals in a coach's second season at a club are consistently lower than year 1 across every cut of the data. However:

- The effect is never statistically significant in the mixed model after controlling for coach and club effects
- Years 3–5 recover strongly, ruling out a general declining trend
- The initial significant result in the mid-season-only analysis was a crisis-club selection effect, not a clean test of the theory
- An equally valid alternative explanation is the well-documented new manager bounce (motivational novelty in year 1 followed by regression)

**Conclusion:** The year 2 dip is real but cannot be attributed to value inflation specifically. The rankings are not materially affected.

### Summary of Findings

The project's primary deliverable was written and saved to `Docs/Summary_of_Findings.md`. It states that both parts of the hypothesis are supported: minutes-weighted squad value is a better predictor of points than raw squad value, and the residual contains a real, portable coaching signal.

---

## Documented Limitations

- **Sample size** is the binding constraint on individual significance — more seasons would allow more coaches to reach significance
- **Serie A 2018** data quality issues visible in rankings
- **Top 5 leagues only** — coaches with careers elsewhere are incompletely represented
- **Value endogeneity** — Transfermarkt values partly reflect past performance (unconfirmed impact)

---

## Project Status

Milestones 1–5 are complete. The project is presentable. Milestone 6 (stretch extensions) remains optional pending available time.
