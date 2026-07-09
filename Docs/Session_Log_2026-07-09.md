# Session Log — 2026-07-09 (covers July 8–9)

## Purpose

Record of decisions made and work completed. This session was mostly unattended: the staged pilot scrape ran to completion, crosswalks were built for all seasons, and the project documentation was updated to reflect the finished M6 data foundation.

---

## Pilot Scrape Completed

The staged scrape launched on July 7 finished cleanly on July 9:

| Season | Players (stats/heatmaps) | Matches (lineups/shotmaps) |
|---|---|---|
| 2015/16 | 549 | 380 |
| 2016/17 | 524 | 380 |
| 2017/18 | 515 | 380 |
| 2018/19 | 505 | 380 |
| 2019/20 | 515 | 380 |
| 2020/21 | 524 | 380 |
| 2021/22 | 538 | 380 |
| 2022/23 | 554 | 380 |
| 2023/24 | 570 | 380 |
| 2024/25 | 562 | 380 |

- **Totals:** 5,356 player-seasons, 3,800 matches, ~4.5M heatmap points, ~96k shots with coordinates.
- **Cost:** 16,572 requests over 28.8 hours (stages 2–10) plus 1,890 requests / 3.3 hours (stage 1). **Zero failed requests** — the 4–7s jittered pacing with rest breaks was never rate-limited.
- **Data health:** only 20 player-seasons across the decade have no heatmap (confirmed absent, not fetch failures). **xG begins mid-2021/22** (164/380 matches) and is complete from 2022/23 onward; shot coordinates are complete for all ten seasons.

## Crosswalks Built for All Seasons

`ss_build_crosswalk()` run for every season: **99.2–100% matched** (16 unmatched of 5,356 total, all Transfermarkt-absent youth players). Cached as `crosswalk_<season_ss_id>.rds`.

## Documentation Updated

- **CLAUDE.md:** added the SofaScore data layer section (access method, politeness rules, coverage limits, resume command), the SofaScore cache schema table, and the `ss_` prefix convention.
- **Docs/Milestones.md:** M6 rewritten — direction chosen (coach/player-type fit), data foundation complete, Player Development Score dropped for scope.
- **Docs/Plan.md:** M6 stub replaced with the full working plan: design decisions, completed data steps, and the remaining steps (feature engineering → archetype clustering → lagged squad composition → coach-fit analysis → optional 2025/26 validation → write-up).

## Commits

- `757ddfb` — SofaScore data layer, TM crosswalk module, PL 2023/24 pilot data (stage 1), session docs (July 7)
- `be5cff3` — complete pilot dataset (all 10 seasons) and all crosswalks
- this session's docs commit — documentation updates + these session docs

---

## State at Session Close

The M6 data foundation is complete and committed. Next session starts the analytical core: archetype feature engineering and clustering design (Plan.md M6 steps 1–2).
