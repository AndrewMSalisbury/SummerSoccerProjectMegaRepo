# Session Progress Report

**Date:** July 10–11, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

A follow-up session on the website launched July 10: visual polish based on a
design review, plus two bugs — one cosmetic-looking display inconsistency that
turned out to have a real analytical bug underneath it.

---

## What Was Accomplished

### Website polish

- The home page now opens with a clean **"Coach Rankings"** header instead of
  the explanatory paragraph, with the writeup one small link away.
- A **light/dark toggle** in the header on every page. The choice is
  remembered, beats the operating-system preference, and applies before the
  page paints so there is no flash. Charts recolor instantly.
- A tighter **color system** after a first draft was rejected for being too
  rainbow: blue/aqua as the site's accent pair; grades on a green–gray–red
  scale that matches how the charts already speak (green-ish good, red-ish
  bad); and each of the 14 leagues assigned its own unique color — the one
  place with a wide palette, by design.

### Bug 1: leaderboard didn't match coach pages

José Ramón Sandoval showed 4 stints / 77 games on the leaderboard but
13 / 278 on his own page. The leaderboard was quietly counting only top-5
league stints (the scope of its ranking) while pages count full careers.
Careers with stints in both cuts diverged. The leaderboard now shows the same
full-career totals as the pages, with the ranking columns still clearly
labeled as the top-5 cut.

### Bug 2: duplicated stints inside the rankings themselves

Verifying bug 1 exposed a coach whose numbers moved the wrong way. Root cause:
when a coach had two spells at the same club in one season (caretaker then
permanent, or sacked and re-hired), the attribution pipeline counted that
stint **twice** — 79 stints across the dataset. This double-weighted those
stints in the coach statistics and the ranking model.

The pipeline was fixed and Milestone 5 re-run for both ranking cuts:

- **The findings all hold.** Same three statistically significant coaches
  (Ferguson, Guardiola, Xavi); the top-10 order is unchanged; the coach effect
  remains significant in both cuts; rankings correlate 0.999 with the old run.
- The honest casualties: a few coaches (most visibly Marcel Rapp, formerly
  rank 7 with an A+ built on a double-counted 4-game hot streak) fell below
  the minimum-data bar and are now correctly unranked. 334 coaches are graded
  in the top-5 cut (was 338), 959 in the all-league cut (was 975).
- The write-up (`Summary_of_Findings.md`) carries a dated correction note and
  updated figures; the website was regenerated and re-verified end to end.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 (core model, rankings) | Complete — **corrected & re-run July 10–11** |
| M6 (coach/player-type fit) | Complete (unaffected — it already filtered the duplicates) |
| Website | Complete, restyled |
| Big-5 SofaScore expansion scrape | In progress (La Liga done; Serie A nearly done) |

---

## What's Next

- Big-5 scrape completion → crosswalks → extend the archetype-fit analysis
  beyond the Premier League.
- Optional: 2025/26 pass-coordinate validation of the archetypes.
- Hosting (GitHub-Pages-ready) whenever wanted.
