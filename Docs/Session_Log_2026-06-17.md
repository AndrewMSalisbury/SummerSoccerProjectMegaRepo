# Session Log — 2026-06-17

## Purpose
Record of decisions made, results produced, and their meaning. Covers re-running M4 and M5 on the expanded 14-league dataset, a targeted top-5-leagues comparison, and new analysis utilities.

---

## Context

The previous session (2026-06-15) finalised the 14-league, 2005–2024 dataset and updated M3. M4 and M5 had not yet been re-run on the expanded data — coach attribution and rankings still reflected the original 5-league, 2015–2024 subset. This session re-ran the full pipeline.

---

## M4: Residual Analysis on Expanded Dataset (14 leagues, 2005–2024)

### Code changes

- `compute_residuals()`: added `is_b_team` to the model formula to match `enhanced_fixed`. This was a bug — residuals were being computed from a misspecified model.
- `run_milestone4()`: default seasons updated to `2005:2024`.
- `plot_team_heatmap()`: each league now opens its own plot device via `dev.new()`.
- `leagues` parameter added to `build_model_dataset()` and `run_milestone4()` to allow subset runs.

### Results

- 5,080 valid residuals (7 NA from non-positive norm_weighted_value)
- Distribution: mean = 0, SD = 0.242 PPG, approximately normal
- No heteroskedasticity detected (p = 0.392)
- Lag-1 temporal persistence: r = 0.203, p ≈ 0, CI [0.174, 0.232] — slightly lower than the original 5-league result (r = 0.25), consistent with more diverse leagues adding noise

### Balance check flags (87 league-seasons)

87 of ~280 league-seasons were flagged (|mean residual| > 0.05 PPG). This is expected and is not a data quality problem. The model uses league fixed effects — not league-season fixed effects — so individual seasons within a league can have non-zero mean residuals by design. The flag count reflects the more stringent threshold applied to a pooled model. Noted as a limitation (no season fixed effects).

### Minutes coverage diagnostic

`minutes_coverage()` added to `residual_analysis.R`. Reveals a clean split in the top 15 overperformers:

- **Artifacts (coverage < 50%):** 5 team-seasons, all 2005, all from LaLiga 2 or 1-HNL. Transfermarkt had almost no market values for these clubs in 2005, producing spuriously large positive residuals.
- **Genuine signals (coverage ≥ 97%):** 10 team-seasons including Liverpool 2019, Leicester 2015, Ipswich 2023, Millwall 2017. Hellas Verona 2013 has 100% coverage but is still an artifact — newly promoted club with Serie B valuations, not a data completeness issue.
- **Rule of thumb established:** coverage below ~80% is a red flag for artifact residuals.

---

## M5: Coach Attribution on Expanded Dataset (14 leagues, 2005–2024)

### Code changes

- `build_coach_residuals()`: added `min_coverage` parameter (default 80%). Drops team-seasons where fewer than 80% of minutes have valued players before the attribution loop. Reports count dropped/retained.
- `run_milestone5()`: new wrapper function following the M3/M4 pattern.
- `validate_coach_coverage()`: short-stints list now prints 15 rows with "N more not shown".
- `add_significance()`: guarded against `se_residual == 0` (degenerate case where 2 stints have identical residuals). Such coaches now receive `NA` rather than a spurious p = 0. Fixed `qt(0.975, df = pmax(df, 1))` to prevent NaN warnings from single-stint coaches.

### Results (14 leagues)

- Coverage filter: 88 team-seasons dropped, 4,999 retained
- 8,286 stints, 2,341 unique coaches
- Attribution coverage: 98.2% of team-seasons, 98.2% of match-slots

**Variance components:**

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0029 | 1.9% |
| Club | 0.0051 | 3.4% |
| Residual | 0.1434 | 94.7% |

LRT p = 0.0088 — coach effect is statistically significant.

**Key finding:** Club variance exceeds coach variance in the 14-league dataset. Interpretation: expanding to smaller leagues brings in many coaches who never move between leagues, making cross-club portability harder to detect. Dominant clubs in smaller leagues (Dinamo Zagreb, Legia Warsaw, Club Brugge) also add stable club-level overperformance that inflates the club component. The coach effect is real but diluted.

---

## Top-5-Leagues Comparison (2005–2024)

To isolate the elite-coaching signal, M4 and M5 were re-run on the 5 major European leagues only (Premier League, La Liga, Ligue 1, Serie A, Bundesliga) for all 20 seasons.

### Results

**Variance components:**

| Component | Variance | % of total |
|---|---|---|
| Coach | 0.0045 | 3.6% |
| Club | 0.0044 | 3.6% |
| Residual | 0.1156 | 92.8% |

LRT p = 0.0072. Coach and club variance are essentially tied — the effect is symmetric.

This sits between the original 5-league result (coach 8.5% > club 4.9%, 2015–2024 only) and the 14-league result. Extending to 20 years gives elite clubs (Bayern, Real Madrid, Juventus) more time to accumulate a stable club signal, narrowing the gap.

**Top BLUP rankings (top-5 leagues, 2005–2024):**

| Rank | Coach | Stints | Games | Clubs | BLUP |
|---|---|---|---|---|---|
| 1 | Pep Guardiola | 16 | 596 | 3 | +0.118 |
| 2 | Alex Ferguson | 8 | 304 | 1 | +0.085 |
| 3 | Thomas Tuchel | 15 | 426 | 5 | +0.081 |
| 4 | Antonio Conte | 11 | 357 | 6 | +0.080 |
| 5 | Jürgen Klopp | 18 | 640 | 3 | +0.075 |
| 6 | Igor Tudor | 7 | 116 | 5 | +0.074 |
| 7 | Massimiliano Allegri | 13 | 468 | 3 | +0.067 |
| 8 | Claudio Ranieri | 17 | 490 | 11 | +0.062 |
| 9 | Unai Emery | 19 | 638 | 7 | +0.060 |
| 10 | Simone Inzaghi | 10 | 349 | 2 | +0.057 |

Notable findings:
- **Claudio Ranieri** (17 stints, 11 clubs): most portable coach in the top-5 dataset. Consistent overperformance across an extraordinary range of clubs and contexts.
- **Marcelo Bielsa** (7 stints, 4 clubs, BLUP −0.070): consistently underperforms squad value despite strong tactical reputation. Squads are expensive relative to points achieved.
- **Eusebio Di Francesco** (12 stints, 8 clubs, BLUP −0.060): strong negative portability — underperformance follows him across environments.
- **Frank Lampard** (5 stints, 2 clubs, BLUP −0.062): fits the pattern of a coach who has not converted playing quality into management results.

**Significance (3 coaches after FDR):** Alex Ferguson, Pep Guardiola, Xavi. Xavi's very narrow CI reflects 3 highly consistent seasons at Barcelona.

---

## Coach Grade Function

`grade_coaches()` added to `coach_attribution.R`. Maps BLUP rankings to a 0–100 numeric grade and letter grade (F through A+) via z-score rescaling. The mean BLUP maps to 75 (C+) by default; each SD maps to 10 points. The resulting distribution is bell-shaped. Includes a grade distribution summary table. Call: `grade_coaches(m5$mixed$coach_blups)`.

---

## Files Modified

- `src/residual_analysis.R` — `is_b_team` in `compute_residuals()`; default seasons 2005:2024; `dev.new()` per league in heatmap; `leagues` param in `run_milestone4()`; added `minutes_coverage()`
- `src/model_comparison.R` — `leagues` param in `build_model_dataset()`
- `src/coach_attribution.R` — `min_coverage` filter in `build_coach_residuals()`; `run_milestone5()`; short-stints truncation; `add_significance()` degenerate-case fix; `grade_coaches()`
- `src/data/cache/coaches.rds`, `matches.rds`, `players.rds`, `teams.rds` — expanded to 14 leagues, 2005–2024
- `Docs/Session_Log_2026-06-17.md` — this file
- `Docs/Progress_Report_2026-06-17.md` — session progress report
