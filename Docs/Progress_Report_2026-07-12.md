# Session Progress Report

**Date:** July 12, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

The big-5 SofaScore scrape (launched July 9) finished between sessions. This session verified and committed it, then extended the entire Milestone 6 archetype/coach-fit analysis from the Premier League pilot to all five leagues.

---

## What Was Accomplished

### Big-5 scrape verified and committed

All 40 new league-seasons checked season by season and completed (~22k player-seasons, ~14k matches; never rate-limited at 2–3s pacing). Coverage quirks documented: relegation playoffs included in events, COVID-shortened Ligue 1 2019/20, and a permanent SofaScore shotmap hole clustered in 2018/19.

### Archetypes rebuilt on 17,219 player-seasons

Same 11-archetype recipe, now with 5× the data — and stability at the fine granularity improved substantially (split-half agreement 0.62–0.92, up from 0.32–0.68). One archetype is **new: the wing-back** (Gosens, Hateboer, Trimmel) — back-3 systems are too rare in the PL for the pilot to have found it. Face validity across leagues is strong (Messi/Mbappé → wide creator; Lewandowski/Kane/Immobile → box striker; Kroos/Modrić/Jorginho → deep playmaker).

### Coach-fit re-run on 1,475 stints across five leagues

**The headline finding replicates and strengthens:** squad archetype mix predicts performance above squad-value expectation (p = 0.030; p = 0.0016 under the strict-lagged sensitivity), with wide-creator share again the dominant coefficient (t ≈ 3.2–3.3, up from ≈ 2.5 in the pilot). The effect size is more modest than the pilot suggested (+10pp of minutes ≈ +2.8 points/season, was ≈ +5) — a classic small-sample correction — but the direction and significance are more solid than ever.

**Per-coach fits remain descriptive** (149 coaches with ≥4 stints, 0 of 1,605 tests survive FDR), but the recurring pairs are football-sensible: Gasperini with no-nonsense man-marking CBs, Vieira with destroyers, Pochettino negatively with pressing forwards.

### Infrastructure hardened along the way

The team-name mapper was rewritten (greedy one-to-one assignment + smarter token matching) after the big-5 exposed three failure modes the PL never triggered — Gladbach mapping onto Dortmund, SofaScore renaming clubs mid-season, and relegation-playoff teams contaminating league team lists. All 40 Transfermarkt crosswalks then built at 99.27% match rate.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 + website | Complete |
| M6 pilot (PL) | Complete |
| M6 big-5 extension | **Complete** |
| Website refresh with big-5 archetype results | Next |
| 2025/26 pass-coordinate validation | Optional |

---

## What's Next

Regenerate the website data so coach pages reflect the big-5 fit results and the relabeled archetypes; optionally revisit the pass-coordinate validation scrape and the two crosswalk seasons flagged for NA-name review.
