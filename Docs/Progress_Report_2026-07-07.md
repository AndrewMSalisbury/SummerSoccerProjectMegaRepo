# Session Progress Report

**Date:** July 6–7, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

The analytical core (M1–M5) is complete. This session opened the Milestone 6 direction: testing whether coaches perform best with particular *types* of players. SofaScore was identified as a new data source offering per-player heatmaps, rich season statistics, per-match statistics, shot coordinates, and (recently) full pass/dribble coordinate charts.

---

## What Was Accomplished

### Research design for coach/player-type fit

The idea was refined into a testable pilot: derive a small set of player archetypes (~6–10) from SofaScore data, lag each player's archetype to prior seasons (so the measure is not contaminated by the current coach's system), summarize each coach-season squad as archetype shares, and test these against the existing performance-above-expectation residuals. Pilot scope: Premier League 2015/16–2024/25. Deliverable framing: descriptive findings with statistical backing.

### SofaScore data infrastructure

- **`src/source_sofascore.r`** — full scraper module in the project's two-tier convention. SofaScore blocks ordinary HTTP clients by TLS fingerprint, so all requests run through headless Chrome ({chromote}). Resumable per-season caching, jittered 4–7s pacing, rate-limit backoff, clean abort with progress saved.
- **Coverage verified:** per-match player statistics, team formations, and shot coordinates reach back to 2015/16; xG begins later; SofaScore's new per-pass/dribble coordinate charts (`rating-breakdown`, found via live browser traffic capture) exist only from 2025/26 — usable as a validation layer, not for the historical window.
- **One incident:** a 70-request burst during endpoint discovery earned a ~24-hour IP block from SofaScore. The block exposed a retry-semantics bug (rate-limit responses would have been recorded as permanently missing data) which was fixed before any large scrape ran. Steady-paced scraping has never been blocked.

### Transfermarkt↔SofaScore player crosswalk

**`src/sofascore_crosswalk.r`** matches SofaScore player ids to Transfermarkt player URLs via team mapping plus a five-rule name-matching ladder. On PL 2023/24: **99.6% matched (568/570)**, every non-exact match manually verified, the two misses being youth players absent from Transfermarkt squad data.

### Pilot scrape started

Stage 1 (full 2023/24 season: ~570 players × stats + heatmap, ~380 matches × lineups + shotmap) was running cleanly at session close. Remaining nine seasons ≈ 27 hours of scraping, planned as overnight runs.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 (core model, rankings) | Complete |
| Coach images | Complete |
| M6: Coach/player-type fit — design | Complete (pilot scoped) |
| M6: SofaScore scraper + crosswalk | Complete |
| M6: Pilot data scrape | In progress (stage 1 of 10 running) |
| M6: Archetype clustering + fit analysis | Next |
| Website | Queued (pivot decision pending pilot viability) |

---

## What's Next

1. Complete the staged scrape (stages 2–10, overnight runs) and build crosswalks for the remaining seasons.
2. Design and prototype the archetype clustering on 2023/24 data (heatmap shape + season statistics).
3. Join archetypes to coach residuals and run the first fit analysis.
4. Decide continue-vs-pivot (website) based on whether the archetypes show signal.
5. Optional: scrape 2025/26 `rating-breakdown` (~11k requests) to validate archetypes against true pass coordinates.
