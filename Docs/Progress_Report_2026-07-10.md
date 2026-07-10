# Session Progress Report

**Date:** July 10, 2026
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

With the analytical work complete (M1–M6), this session built the project's
public face: a website presenting every result — a page for each of the 2,341
coaches, 496 clubs, and 14 leagues, plus the full writeup. The design and
implementation plan were agreed in advance (`Docs/Website_Design.md`,
`Docs/Website_Implementation_Plan.md`) and the whole build ran as one session.

---

## What Was Accomplished

### The site

A fully static site in `site/` — no server, no framework; open it with a
one-line local web server.

- **Coach pages** are the centerpiece. Each shows a career points-per-game
  chart where every data point is the crest of the club managed that season;
  clicking a crest opens that stint's numbers (actual vs expected points,
  residual, tenure, share of the season). A dashed line shows what the
  squad-value model expected, so over/under-performance is visible as the gap.
  Stints can be ordered chronologically or best-to-worst. The header carries
  the coach's photo, letter grade and 0–100 score, BLUP, rank — always labeled
  with which ranking cut they come from — plus an auto-generated plain-language
  summary and the player-type fit findings (real data for the 26 Premier League
  coaches from Milestone 6; an explicit N/A for everyone else, as planned).
- **Team pages** show the full coach history with each coach's grade, sortable
  chronologically or by performance; a per-season actual-vs-expected chart
  (click a season to highlight its coaches); and squad-value trends. Edge cases
  are labeled rather than hidden — B teams, seasons without coach attribution,
  seasons with too little market-value data for a residual.
- **League pages** default to the latest available season with a season
  switcher back to 2005/06, standings sortable by points or by overperformance,
  a diverging bar chart of points above/below expectation, and all-time
  over/underperformer lists (Liverpool 2019/20 +32.2 and Leicester 2015/16
  +30.0 lead the Premier League list — the model's known narratives, now
  browsable).
- **Home** carries the leaderboard (Guardiola first, as published) and search
  over every coach, team, and league. The **writeup page** renders the full
  Summary of Findings with a table of contents.
- Light and dark mode both ship; charts follow a validated accessible palette.

### Club crests

Crests for all 496 clubs were downloaded after discovering they live at a
predictable Transfermarkt CDN address — no page scraping needed. Coverage is
100%, and the site generates initial-badges automatically wherever an image is
ever missing.

### Verification

Every page type was screenshot-tested headlessly (desktop, dark mode, and
375px mobile), interactions included: crest clicks, sort toggles, season
switching, search keyboard navigation, and bad-URL error states. An automated
sweep confirmed every cross-link in the ~2,850 generated data files resolves.
Two real bugs were caught by looking at rendered pages — duplicated stint rows
for sacked-and-reappointed coaches, and a JSON edge case that blanked pages for
single-league clubs — both fixed at the source and re-verified.

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M5 (core model, rankings) | Complete |
| M6 (coach/player-type fit) | Complete |
| Website | **Complete** |
| M6: 2025/26 pass-coordinate validation | Optional |
| Big-5 SofaScore expansion scrape | In progress (background) |

---

## What's Next

- **Hosting** when wanted: the site is GitHub-Pages-ready; publishing is a
  settings change, not a build task.
- **Refresh cycle:** after any model re-run, three R calls regenerate the site
  (`save_coach_grades()`, `cf_save_results()`, `export_site_data()`).
- The big-5 SofaScore scrape continues in the background; once complete, the
  archetype-fit analysis can extend beyond the Premier League and the coach
  pages' player-type sections will fill in for four more leagues.
