# Session Progress Report

**Date:** July 8–9, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

Milestone 6 (coach/player-type fit) was designed and its infrastructure built on July 6–7. This session completed the data collection phase.

---

## What Was Accomplished

### Pilot dataset complete

The full Premier League 2015/16–2024/25 SofaScore scrape finished with **zero failed requests** (16,572 requests, ~29 hours, 4–7s pacing never rate-limited):

- **5,356 player-seasons** — ~110-field season statistics and positional heatmaps (~4.5M points)
- **3,800 matches** — team formations, per-player match statistics, and ~96,000 shots with pitch coordinates
- **Coverage boundaries confirmed:** shot coordinates complete for all ten seasons; xG from mid-2021/22 (complete 2022/23+); per-pass/dribble coordinates only exist from 2025/26 and remain an optional validation layer.

### Players linked to the existing dataset

Transfermarkt crosswalks built for all ten seasons at **99.2–100% match rates** (16 unmatched of 5,356, all youth players absent from TM squad pages). Every SofaScore feature can now join squad values, minutes, coach tenures, and the M4 residuals.

### Documentation brought current

CLAUDE.md (new data layer, schemas, conventions), Milestones.md (M6 active, direction fixed), and Plan.md (full M6 working plan with remaining steps) all updated.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 (core model, rankings) | Complete |
| M6: design + data foundation | Complete |
| M6: archetype clustering + fit analysis | **Next — the analytical core** |
| M6: 2025/26 pass-coordinate validation | Optional |
| Website | Queued |

---

## What's Next

Plan.md M6 steps 1–4: engineer per-player-season features (heatmap shape, per-90 profiles, shot profiles), cluster into ~6–10 archetypes with validity checks, build lagged minutes-weighted squad archetype shares per coach-season, and run the coach-fit analysis against the residuals. The clustering design (feature set, position grouping, method, k) is the next working conversation.
