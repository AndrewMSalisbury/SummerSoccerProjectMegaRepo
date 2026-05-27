# Project Milestones

**Timeline:** May 27 – August 16 (gap: June 23 – July 3)

---

## Milestone 1: Data Foundation ✓
**Completed**

Player squad data and match results are confirmed clean and queryable across cached seasons. The pipeline can be re-run without manual intervention. A source for coach-team-season assignments is identified and integrated into the data layer.

---

## Milestone 2: Core Metric ✓
**Completed**

Minutes-weighted squad value is calculated for every team-season in the dataset. A sanity check confirms the metric behaves as expected (e.g., elite clubs score higher, clubs with injured starters score lower than their raw value suggests). The data pipeline runs end-to-end: scrape → clean → metric.

---

## Milestone 3: Model Comparison
**Target: ~June 6**

The model is rebuilt on a points basis rather than league rank, addressing the ceiling problem where top coaches have no room to outperform a rank of first. Both the baseline model (raw squad value → points) and the enhanced model (minutes-weighted squad value → points) are evaluated and compared. The core hypothesis has a direct answer: does weighting by minutes improve predictive accuracy?

---

## Milestone 4: Residual Analysis
**Target: ~June 20**

Residuals from the best-performing model are computed for every team-season. The distribution and structure of those residuals is analyzed — do certain teams consistently over- or underperform their expected points? This milestone stands on its own: even without coach attribution, a reliable residual is a defensible analytical result.

---

*[ Gap: June 23 – July 3 ]*

---

## Milestone 5: Coach Attribution & Rankings
**Target: ~July 25**

Residuals are linked to the coaches responsible for each team-season. Coaches with multiple teams are analyzed for consistency of residuals across different environments. A defensible ranking of coaches by performance above expectation is produced, and findings clearly support, refute, or refine the original hypothesis.

---

## Milestone 6: Extensions (Stretch)
**Target: ~August 10**

Further development pursued if time and results from earlier milestones support it. Possible directions:
- **Player Development Score** — measuring coach impact on player transfer value growth
- **Playing Style Analysis** — categorizing coaches by tactical fingerprint
