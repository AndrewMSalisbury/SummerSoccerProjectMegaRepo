# Session Progress Report

**Date:** July 13, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

With the model, rankings, archetype analysis, and website all complete, this session built the project's capstone: a **coach recommender** — given any team's squad, who is the best coach to hire? Designed in the morning (`Docs/Coach_Recommender_Design.md`), implemented end-to-end the same day.

---

## What Was Accomplished

### A complete recommender, built on an honest decomposition

The system predicts a coach's uplift at a specific club as three parts: **quality** (the M5 shrinkage rankings), **fit** (shrunken coach × player-type slopes on the M6 archetype axes), and **deployment** (a new formation layer: can this coach's shapes actually field this squad's market value?). The deployment idea fixes a genuine blind spot — the residual metric conditions on the value that played, so a coach who benches an €80M striker was never punished for it.

### The formation layer works mechanically — emphatically

All 36,022 big-5 team-matches carry kickoff formations (22 distinct shapes; back-3 football tripled over the decade, 11% → 36%). Each coach gets a recency-weighted formation profile (decay chosen out-of-sample) and a **rigidity** score with striking face validity: Italiano 0.99 and Klopp 0.91 shape-rigid, Streich and Galtier shape-shifters, Gasperini 97% back-3. The squad→formation value machinery passed its validation gate decisively: at 316 historical coach arrivals, a player's fit to the incoming coach's shapes predicts his minutes far beyond his market value (t = 26.9, positive in 100% of stints).

### The pre-registered verdict: quality is a validated hiring signal; fit is not (yet)

The whole build was gated by a validation designed before any results were seen: forecast the outcomes of **785 brand-new coach-club pairings**, 2016–2024, leave-one-season-out, adding one layer at a time, with a fixed rule — a layer ships in the headline score only if it doesn't hurt.

- **Coach quality shipped** (p = 0.016 in the realized-value framing) — knowing a coach's track record genuinely improves forecasts of his *next* appointment. This also closes the long-standing limitation that the Part 4 augmented-model test had never been re-run beyond the original dataset.
- **Fit and deployment did not** — statistically a wash on hiring forecasts, so they appear on the site as clearly-labeled exploratory columns, never in the ranking. Part of the story is survivorship: clubs already hire for fit, so the disastrous mismatches that would prove the fit signal are never observed.

### On the website, on every team page

All 96 latest-season big-5 team pages now carry a "Suggested coaches" section: the validated ranking with exploratory fit/shape columns, **plausibility filter chips** (has coached in this league / country, big-5 proven, similar club level, recently active, domestic coach — filters narrow, badges always show), and a descriptive strip of "coaches who thrived with squads like this" (for Man City: Setién, Guardiola, Pochettino, Rose, Arteta). Non-big-5 clubs get an honest note instead of a fake list. Screenshot-QA'd in both themes and at phone width; link sweep clean. Coach nationality (for the domestic-coach badge) comes from a new resumable Transfermarkt profile scrape, still filling in at session close.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M6 + website | Complete |
| Coach recommender (design + build + validation + site) | **Complete** |
| Nationality scrape (domestic-coach badge coverage) | Running, resumable |
| 2025/26 pass-coordinate validation | Optional |
| Public hosting | Optional |

---

## What's Next

Let the nationality scrape finish and refresh the export so every domestic badge appears; the optional items (pass-coordinate validation, public hosting) remain open by choice.
