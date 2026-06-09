# Session Log — 2026-06-09 (Session 2)

## Purpose
Record of decisions made, code changes, results produced, and their meaning. Continuation of the June 9 session; covers Milestone 5 implementation.

---

## Files Modified/Created

- `src/coach_attribution.R` — new file containing the full Milestone 5 attribution pipeline
- `Docs/Plan.md` — updated M5 Step 1 (coach scraping already done) and Step 3 (partial attribution rule)
- `Docs/Milestones.md` — updated M4 completion note
- `Docs/Summary_of_Findings.md` — primary project deliverable (new)

---

## Functions in `coach_attribution.R`

| Function | Purpose |
|---|---|
| `xx_match_points_for_team(matches, team_sid)` | Adds `team_points` column from the perspective of a given team |
| `xx_assign_matches_to_coaches(team_matches, team_coaches)` | Assigns each match to a coach via date-bracket matching; unattributed matches get NA |
| `validate_coach_coverage(coach_residuals_tbl, residuals_tbl)` | Reports team-season coverage, attribution rate, dropped matches, and short stints |
| `compute_coach_stats(coach_residuals_tbl, min_games, min_stints)` | Aggregates to one row per coach with mean residual, SD, SE, n_stints, total_games, n_clubs |
| `add_significance(coach_stats, alpha)` | Adds per-coach t-test results and BH FDR correction; coaches with n_stints < 2 get NA |
| `fit_mixed_model(coach_residuals_tbl, min_games, min_stints)` | Mixed-effects model with club and coach random effects; LRT, variance components, BLUPs |
| `test_tenure_effect(coach_residuals_tbl, min_days_into_season, max_days_into_season)` | Tests whether residuals trend by tenure year; filters on days_into_season using date_from |
| `build_coach_residuals(residuals_tbl)` | Main function; returns coach-stint table with partial_residual_ppg and date_from |

---

## Methodological Decisions

### Partial Attribution Rule
Rather than assigning the full season residual to the coach who managed >60% of games, each match is attributed to the coach in charge on that date. For each coach stint:
- `partial_residual_ppg = (actual_points_in_stint / games_in_stint) − predicted_ppg`
- `predicted_ppg` is the squad-value model's season-level prediction (constant within the season)
- Matches on a coach's exact `date_from` belong to the new coach
- Matches covered by no coach (caretaker gaps) are dropped from both actual and expected
- No minimum games threshold applied at the stint level

### Mid-Season Change Definition
Initially used `n_games` as a proxy for pre-season vs mid-season appointments. Revised to use `days_into_season = date_from − first_match_date` (from matches cache), which correctly separates pre-season appointments who were later sacked from genuine mid-season arrivals.

---

## Coverage Results

```
Team-seasons in residuals table:   976
Team-seasons with coach data:      975 (99.9%)
Team-seasons with >1 coach:        346 (35.5%)

Total match-slots:                 36,022
Attributed to a coach:             35,796 (99.4%)
Dropped (no coach coverage):       226 (0.6%)

Stints of <=5 games:               129
```

Short stints are all real caretaker/emergency appointments (Kevin MacDonald, Duncan Ferguson, Michael Carrick, Ruud van Nistelrooy, etc.) — confirmed correct, not scraping errors.

---

## Coach Statistics (min_games = 10, min_stints = 3)

```
Total coaches meeting threshold:  194
Coaches with 3+ stints:           194
Coaches with 5+ stints:           116
```

---

## Significance Testing

One-sample t-tests (H0: mean_residual = 0) computed analytically from summary stats. BH FDR correction applied across 194 coaches.

```
Coaches tested:         194
Significant after FDR:  1 (Pep Guardiola)
```

Only Guardiola clears the bar — a sample size constraint, not a model failure. Most coaches have 3–5 stints, giving df = 2–4, which requires very large effects for significance.

---

## Mixed-Effects Model Results

Model: `partial_residual_ppg ~ (1 | club_id) + (1 | coach_id)`

```
Variance Components:
  coach_id   var = 0.0113  sd = 0.1061  (8.5% of total)
  club_id    var = 0.0065  sd = 0.0806  (4.9% of total)
  Residual   var = 0.1147  sd = 0.3387  (86.6% of total)

LRT: Chi-sq = 10.640  df = 1  p = 0.0011
```

**Key finding:** Coach variance (8.5%) exceeds club variance (4.9%). The coaching effect is portable — it follows the manager more than it stays at the club. The LRT confirms the coach effect is significant after accounting for club-level variation.

**Top 5 BLUPs:** Guardiola (+0.180), Klopp (+0.140), Tudor (+0.139), Conte (+0.125), Allegri (+0.103)

---

## Tenure Effect Analysis

**Hypothesis tested:** Do residuals decline over successive seasons at the same club, consistent with market value inflation compressing the residual baseline?

Three cuts of the data were tested:

| Filter | Year 1 | Year 2 | Mixed model p |
|---|---|---|---|
| All stints | -0.087 | -0.131 | 0.075 (n.s.) |
| n_games >= 30 | +0.059 | +0.045 | 0.960 (n.s.) |
| n_games <= 29 | -0.189 | -0.346 | 0.0005 * |
| days_into_season <= 30 | -0.081 | -0.116 | 0.536 (n.s.) |
| days_into_season > 30 | -0.102 | -0.127 | 0.109 (n.s.) |

**Conclusions:**
- The year 2 dip is a consistent descriptive pattern across all cuts but is never significant after controlling for coach and club effects (except in the n_games <= 29 case, which is a crisis-club selection effect)
- The significant result in the mid-season-only analysis was reinterpreted: coaches with two short stints at the same club are repeat crisis situations, not a clean test of value inflation
- The n_games filter was later replaced with days_into_season (more principled: separates pre-season appointments sacked early from genuine mid-season arrivals)
- **The value inflation theory is not confirmed.** Rankings are not materially affected.

**Alternative explanation noted:** The year 2 dip is equally consistent with a new manager bounce (motivational novelty in year 1 that regresses in year 2). The two mechanisms cannot be distinguished with available data.

---

## Documented Limitations

1. **Sample size:** Most coaches have 3–5 stints — individual significance is hard to achieve. Rankings are directional for coaches with < 5 seasons.
2. **Serie A 2018 data quality:** Inflated residuals visible in top and bottom of rankings.
3. **League scope:** Top 5 European leagues only. Coaches with careers in other competitions are incompletely represented.
4. **Value endogeneity:** Transfermarkt values partly reflect past performance; may compress residuals for long-tenured coaches (unconfirmed).
5. **No season fixed effects:** 8 of 50 league-seasons show residual imbalance > 0.05 PPG (all in known anomalous seasons).
6. **Attribution gaps:** 226 unattributed matches, SC Freiburg 2018 missing coach data.

---

## Next Steps

- **Milestone 6 (stretch):** Player Development Score or Playing Style Analysis if time permits
- **Potential extension:** Add more seasons (pre-2015) to increase stints per coach and allow more individual significance tests
