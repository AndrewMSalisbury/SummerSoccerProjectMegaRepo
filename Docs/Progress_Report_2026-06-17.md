# Session Progress Report

**Date:** June 17, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

M3 was re-run on the expanded 14-league, 2005–2024 dataset in the previous session. M4 and M5 had not yet been updated. This session re-ran the full downstream pipeline and conducted a targeted top-5-leagues comparison to isolate the elite-coaching signal.

---

## What Was Accomplished

### M4 Re-run (14 leagues, 2005–2024)

The residual analysis was updated and re-run on the full expanded dataset. A bug was fixed: `compute_residuals()` was missing `is_b_team` from its model formula, meaning residuals were being computed from a different specification than `enhanced_fixed`. With the fix, 5,080 valid residuals were produced (7 NA).

Key results match the original analysis in character:
- Distribution approximately normal, SD = 0.242 PPG
- No heteroskedasticity — rankings equally reliable across all squad value tiers
- Lag-1 persistence r = 0.203 (slightly lower than the original 0.25, consistent with more diverse leagues adding noise)

A `minutes_coverage()` diagnostic function was added. It revealed that 5 of the top 15 overperformers are data artifacts — LaLiga 2 and HNL clubs from 2005 with fewer than 30% of minutes having valued players. A coverage threshold of 80% was established as the filter for M5.

### M5 Re-run (14 leagues, 2005–2024)

Coach attribution was re-run on the expanded dataset with the 80% coverage filter applied. 88 team-seasons were dropped; 4,999 retained. Attribution coverage was 98.2%.

The mixed-effects model found a significant coach random effect (LRT p = 0.0088), but the variance breakdown shifted compared to the original:

- **Original (5 leagues, 2015–2024):** Coach 8.5% > Club 4.9%
- **Expanded (14 leagues, 2005–2024):** Club 3.4% > Coach 1.9%

The reversal reflects the composition of the expanded dataset: most coaches in smaller leagues never move between leagues, making cross-club portability hard to detect. Dominant clubs in smaller leagues also create strong persistent club signals. The coach effect is real but diluted.

### Top-5-Leagues Comparison (2005–2024)

To recover the sharper elite-coaching signal, M4 and M5 were re-run on the 5 major leagues only across all 20 seasons. This required adding a `leagues` parameter to `build_model_dataset()` and `run_milestone4()`.

Result: coach variance (3.6%) and club variance (3.6%) are now tied — a meaningful middle ground between the two prior runs. With 20 years of data, elite clubs accumulate a stronger persistent identity signal, but elite coaches (who move frequently between these leagues) also have more stints to establish their portable effect.

The BLUP rankings for this subset are the most credible output of the analysis:
- Guardiola clearly #1 at +0.118 PPG across 16 stints and 3 clubs
- Ranieri stands out at #8 (17 stints, 11 clubs) as the most portable coach in the dataset
- Three coaches achieve individual significance after FDR: Ferguson, Guardiola, Xavi

### Analysis Utilities

- `run_milestone5()` wrapper added (M5 now has a single callable entry point like M3/M4)
- `grade_coaches()` added: maps BLUP rankings to 0–100 numeric grades and letter grades (F–A+) via z-score rescaling, with a bell-curve distribution centred at 75 (C+)
- Fixed degenerate p = 0 entries in `add_significance()` for coaches with zero SD across stints

---

## Project Status

| Milestone | Status |
|---|---|
| M1 Data Foundation | Complete |
| M2 Core Metric | Complete |
| M3 Model Comparison | Complete (14 leagues, 2005–2024) |
| M4 Residual Analysis | Complete (14 leagues, 2005–2024) |
| M5 Coach Attribution | Complete (14 leagues + top-5 comparison, 2005–2024) |
| M6 Extensions | Optional |

The core hypothesis is fully tested across the expanded dataset. The most defensible coach rankings come from the top-5-leagues, 2005–2024 run. Remaining optional work: re-running the augmented model (Part 4 of Summary of Findings) on the expanded dataset, and updating `Summary_of_Findings.md` to reflect the new results.
