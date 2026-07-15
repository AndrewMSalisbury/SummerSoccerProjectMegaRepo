# Session Log — 2026-07-14: Games-Weighted M5 BLUPs

## Trigger

Andrew asked whether the coach BLUP accounts for how many games a stint had —
e.g. would losing both games of a 2-game caretaker spell (≈ −1.5 PPG residual)
move the BLUP a little or a lot? Inspection showed a split: the M5 leaderboard
model (`fit_mixed_model()` in `coach_attribution.R`) treated every stint as one
unweighted observation, while the M6/recommender models already used
`weights = n_games`. Andrew then raised the follow-on concern that games
weighting could *over*-shrink bad short stints, since stint length is an outcome
of performance (sackings), inflating coaches whose disasters were truncated.

## Analysis (scratchpad: `weight_comparison.R`, `weight_k_estimate.R`, `weight_oos.R`)

1. **Selection premise confirmed.** Mean stint residual rises monotonically with
   stint length: −0.41 PPG (1–5 games) → +0.10 (46+). The gradient is mostly
   within-coach (0.0129 PPG/game, t = 32 vs 0.0093 between-coach, t = 12) —
   the signature of performance-driven sackings.
2. **Naive ML profiling of a saturating weight `n/(n+k)` is confounded**: the
   likelihood keeps rising as k → ∞ because down-weighting short stints also
   hides their unmodeled mean shift, not just their noise. Estimating the
   variance function *after removing the stint-length mean trend* gives
   Var(stint) = 0.0136 + 1.495/n → k ≈ 110. Match noise (sd ≈ 1.22 pts/game)
   dwarfs the stint-level shock (sd ≈ 0.12), so principled inverse-variance
   weights are nearly proportional to n_games (leaderboard rank r = 0.998 vs
   plain n_games; and the saturating fit went singular on one OOS split).
3. **Decisive OOS test** (train even seasons → predict odd-season stint
   residuals, and vice versa, games-weighted metrics): games-weighted BLUPs won
   on both splits — weighted correlation with held-out residuals 0.129 vs 0.090
   unweighted; MSE improvement over a zero prediction 0.97% vs 0.73%. The noise
   reduction outweighs the selection tilt. (All improvements are small in
   absolute terms because coach effects are modest — consistent with M5's
   variance decomposition.)
4. Bonus consistency: the recommender's pre-registered payoff validation
   (`cr_payoff_validation()`) already refit quality games-weighted per fold, so
   the games-weighted leaderboard is what was actually validated OOS on new
   coach-club pairings.

## Change

- `coach_attribution.R` `fit_mixed_model()`: `weights = n_games` on both the
  null and full models; variance-component printout now labels the residual as
  per-game and computes % shares on the stint scale at the mean stint length;
  header comment documents the rationale and the selection-tilt caveat.
- Regenerated `coach_blups_top5.rds`, `coach_blups_14league.rds`,
  `coach_grades_top5.rds`, `coach_grades_14league.rds`
  (scratchpad `refit_m5_weighted.R`).
- Follow-up (same day, after Andrew flagged the inconsistency): the per-coach
  descriptive stats and t-tests were weighted the same way.
  `compute_coach_stats()` now uses the games-weighted mean with
  SE = √(σ̂²_game / total_games) (σ̂²_game from games-weighted squared
  deviations on n_stints − 1 df), and `add_significance()` requires ≥ 3 stints
  to test — on df = 1 the SE can collapse to ~0 when a coach's two stints agree
  by luck (Mark Wotte, 2 stints, would have shipped as "significantly bad").
  `coach_ranked_*.rds` regenerated: significant-after-FDR is now Ferguson,
  Guardiola, Conte, Xavi (top-5) and Ferguson, Guardiola, Marek Papszun, Xavi
  (all leagues). The recommender similar-pool means (`mean_res_b5`) were
  already games-weighted from the start.
- `coach_recommender.R` `cr_build_scorer()` / `cr_score_team()`: published
  variance components updated (top5 coach 0.0038 / residual 1.7683 per game;
  14-league 0.0030 / 1.8143) and the quality posterior SD now uses
  `total_games` against the per-game residual variance instead of `n_stints`
  against a stint-scale one. `recommender.rds` regenerated (phase8a).
- `Docs/Summary_of_Findings.md` Part 5: dated revision note; new variance
  tables (top5: coach 5.3% > club 4.5%, χ² = 17.89; 14-league: 3.7% vs 3.8%
  tied, χ² = 28.47 — both p < 0.0001, much stronger than unweighted); new
  top-15 table; updated notable-findings BLUPs. Parts 2–4 remain as-run.
- `CLAUDE.md`: M5 weighting noted, plus the rule that the recommender's
  posterior-SD constants must be refreshed whenever M5 is refit.
- Site re-exported (`export_site_data()`).

## Leaderboard effect

Material: rank correlation 0.79 with the unweighted leaderboard. Full-season
track records rise (Ferguson 7th → 2nd in the top-5 cut, Allegri 17th → 4th),
short-burst profiles fall (Igor Tudor out of the top 15; Quique Sánchez Flores
425th → 880th in the all-leagues cut). Chris Hughton is the biggest riser
(832nd → ~134th) — a couple of brief disasters no longer count like full
seasons. LRT evidence for a coach effect strengthens in both cuts. The grade
curve re-centres automatically (mean 75 / sd 10 on the new BLUP distribution).

## Follow-up: certification bar (same day, later session)

Andrew flagged Andrea Mandorlini (108 games, 7th in the top-5 cut) as exactly
the selection-flattered thin record he'd predicted: three short stints
averaging −0.42 PPG are (correctly) down-weighted, leaving a career mean of
+0.45 weighted vs +0.07 unweighted. Score-side fixes were tested and all
degraded out-of-sample prediction of held-out stints (scratchpad `floor_oos.R`,
`trunc_test.R`, `gap_penalty_test.R`, `gap_quarter.R`):

- weight floors (`pmax(n, season/2)` etc.): worse on both games-weighted and
  unweighted evaluation, and singular on one even/odd split;
- a truncation-share penalty (replaced mid-season): the OOS coefficient is
  *positive* (+0.06, p = 0.018 unweighted eval) — the model already prices
  truncation in (cor(BLUP, trunc share) = −0.33) and sacked coaches mean-revert;
- a gap penalty (weighted − unweighted career mean, incl. one-sided λ·max(gap,0)):
  gap coefficient positive (p ≈ 0.02–0.03); λ = 0.25 halves the held-out
  ordering correlation (0.105 → 0.048); the symmetric version puts 21–54-game
  caretakers with negative BLUPs above Guardiola.

Resolution: a **display certification bar** in `save_coach_grades()` —
≥ 109 career games in the cut (Andrew's number, chosen to exclude Mandorlini's
108), with an FDR-significance exemption (added because Xavi, 103 games,
significant in both cuts, would otherwise be uncertified; the exemption
currently re-admits only him). Ungraded coaches keep their BLUP but get no
grade, no leaderboard slot, and no recommender-pool entry
(`cr_score_team()` pool now filters to graded coaches, preferring the top-5
row only when graded there). Grade curve re-fit on certified coaches
(215 top-5, 545 all-leagues; leaderboard n matches). Coach-page copy updated
(`site_export.R` summary, `coach.js` grade card). Docs: display note +
top-15 table (Sarri in at 15) in `Summary_of_Findings.md`, CLAUDE.md note.
Verified on the exported site: Mandorlini ungraded, off the leaderboard, in
zero of 496 teams' suggestion cards; all four significant chips present.

## Loose ends

- Coach nationality scrape **completed** during the session: 3,533 coaches in
  `data/cache/coach_nationalities.rds`, 0 NA. `recommender.rds` and the site
  were regenerated afterward, so all domestic/country badges are final.
- Documented limitation kept: no reweighting fully removes informative
  censoring (sacked-early stints); the complete fix would be a match-level
  model with coach × stint random effects.
