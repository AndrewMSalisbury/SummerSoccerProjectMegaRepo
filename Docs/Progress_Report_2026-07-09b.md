# Session Progress Report

**Date:** July 9, 2026 (Session 2)
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

The M6 data foundation (SofaScore pilot scrape + crosswalks) was completed earlier this week. This session built and ran the analytical core: player archetypes and the coach/player-type fit analysis.

---

## What Was Accomplished

### Player archetypes derived and validated

3,476 Premier League player-seasons (≥600 minutes, 2015/16–2024/25) were described by 38 style features — heatmap shape, per-90 passing/carrying/defending profiles, shot locations — and clustered within position groups into **11 archetypes** with strong face validity:

no-nonsense CB, ball-playing CB, defensive fullback, attacking fullback, deep playmaker, destroyer, advanced creator, wide midfielder, pressing forward, box striker, wide creator.

(Van Dijk and Stones land in ball-playing CB, Tarkowski and Mee in no-nonsense CB; De Bruyne in advanced creator; Kane and Vardy in box striker.)

### Coach-fit analysis run

Each coach stint's squad composition (minutes-weighted archetype shares, lagged one season as an endogeneity guard) was joined to the M5 partial residuals — 301 of 301 stints matched, with SofaScore and Transfermarkt game counts agreeing perfectly.

**Headline finding: squad archetype mix predicts performance above squad-value expectation** (mixed model LRT p = 0.013; p = 0.0017 under the strict-lagged sensitivity). The signal is concentrated in attacking archetypes — most strongly **wide creators** (Salah/Sterling/Firmino types): +10pp of outfield minutes ≈ +5 points/season above expectation.

**Per-coach fits are suggestive but not individually significant** (26 coaches, 280 tests, none survive FDR — a sample-size constraint, as with M5's individual rankings). Recurring descriptive pairs have good face validity: Klopp with pressing forwards, Guardiola and Arteta with ball-playing centre-backs.

### Along the way

Three SofaScore data conventions were discovered and verified empirically (shot coordinates use a goal-at-origin convention; lineup team ids are scrape-time clubs, not match teams; two stat fields exist only in recent seasons) — each would have silently corrupted results.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 (core model, rankings) | Complete |
| M6: archetype clustering + fit analysis | **Complete** |
| M6: 2025/26 pass-coordinate validation | Optional |
| Website | Queued |

---

## What's Next

M6 is analytically complete and written up in Summary_of_Findings Part 6. Remaining options: the 2025/26 pass-coordinate validation scrape (~11k requests, optional), and the coach-rankings website (images already downloaded July 5; archetype-fit findings are candidate content).
