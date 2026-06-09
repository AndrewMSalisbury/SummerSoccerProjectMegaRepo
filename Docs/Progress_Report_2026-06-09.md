# Session Progress Report

**Date:** June 9, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

This session completed Milestone 4: Residual Analysis. The goal was to take the winning model from Milestone 3 (`enhanced_fixed` — minutes-weighted squad value with league fixed effects), compute validated residuals for every team-season in the dataset, and confirm that those residuals contain a real signal worth attributing to coaches. The full analysis pipeline was built in a new file `src/residual_analysis.R` and is reproducible via `run_milestone4()`.

---

## What Was Accomplished

### Data Verification

Before beginning analysis, the two outstanding cache gaps from prior sessions were confirmed resolved. All 18,011 match rows now have dates populated, and coach data covers 975 of 976 team-seasons — the one gap (SC Freiburg 2018) is negligible and won't affect M5 meaningfully.

### Milestone 4 Analysis Pipeline

The full pipeline was built and run across 7 steps.

**Residuals table:** The winning model from M3 was fitted on the full 2015–2024 dataset and used to generate a predicted points-per-game and residual for every team-season. 6 of 976 team-seasons received NA residuals due to an imputation edge case (the within-season regression predicting a negative weighted squad value for very low-value teams). These are treated as NA throughout and are not a concern at 0.6% of the dataset.

**Balance check:** 8 of 50 league-seasons showed a mean residual above the 0.05 PPG flag threshold. These are the same Serie A and early-season anomalies that appeared in M3 — expected behaviour of a model without year fixed effects, not a data error.

**Residual distribution:** With a mean of exactly zero and standard deviation of 0.238 PPG, the distribution is well-behaved. The Q-Q plot is approximately normal in the middle but shows heavier tails than a perfect normal at the extremes — both the best and worst seasons are more extreme than the model would predict. This is driven by a handful of genuinely remarkable seasons and the known 2018 data quality issue.

**Top performers:** The overperformers list is dominated by well-known coaching narratives: Liverpool under Klopp (three entries in the top 10 across 2018–2021, including +32 points in 2019), Leicester City's miracle 2015 title at +30 points, Manchester City under Guardiola, and Bayer Leverkusen's unbeaten 2023 season under Xabi Alonso. The model is identifying real sporting signals. The 2018 Serie A data quality issue is also visible — Juventus (+31.6 pts) and Napoli (+24.2 pts) appear as likely artefacts alongside the genuine results.

The underperformers include Southampton in two separate seasons (2022 and 2024), Chelsea in 2015 during Mourinho's sacking year, and several 2018 Serie A clubs whose inflated residuals are almost certainly data-driven rather than genuine coaching underperformance.

**Heteroskedasticity:** No significant relationship between squad value and residual magnitude (p = 0.26). The model is equally reliable across the full range from small promoted clubs to elite teams. Coach rankings in M5 will not be systematically less trustworthy for any particular tier.

**Temporal persistence:** The lag-1 correlation in residuals across consecutive seasons for the same team is 0.25 (p < 0.001, 95% CI [0.18, 0.32]). This is statistically significant but modest — year-to-year team performance above expectation is only weakly persistent. Roughly 6% of next-season residual variance is explained by this season's residual. This is the most important analytical finding of M4: the residual is not simply a stable club quality proxy. There is genuine year-to-year variation that the coach attribution model in M5 can meaningfully work with.

**Visualizations:** Two chart types were built. A horizontal bar chart shows all team residuals for any single league-season. A set of five heatmaps (one per league) shows how team residuals have evolved across all ten seasons, with teams sorted by their mean residual. These make the persistent over- and underperformers immediately visible.

---

## Documented Limitations

- **6 NA residuals** from the imputation edge case. Treated as NA; not a meaningful gap.
- **8 league-season balance flags** concentrated in the known anomalous seasons. Expected from the pooled model design.
- **Heavy tails in the residual distribution** driven by the 2018 data quality issue and a few genuinely extreme seasons. Mild concern for M5 significance tests; adequate sample size provides protection.
- **Modest club effect (lag-1 r = 0.25).** Real but limited. M5 must account for it — the mixed-effects model approach (team as random effect) is the right tool.

---

## What Comes Next

Milestone 4 is complete. The project moves to **Milestone 5: Coach Attribution & Rankings** (target: ~July 25, resuming after the June 23 – July 3 gap).

The residuals table is validated and ready. M5 will join it to the coach data already scraped in `coaches.rds`, apply the mid-season change rule to handle coaching changes within a season, and produce a final ranked table of coaches by mean residual above expectation. The central analytical question — whether the coach effect is portable across different clubs — will be tested using a mixed-effects model.

The groundwork is solid. Leicester 2015, Liverpool under Klopp, and Leverkusen 2023 are already visible as the kinds of signals M5 will be built on.
