# Session Progress Report

**Date:** July 14, 2026 (Session 2)
**Project:** Football Coach Valuation Model
**Author:** Andrew Salisbury

---

## Context

With the recommender complete, this session added the site's most interactive
feature: a **team builder** — pick any formation, place any big-5 player from
the last decade onto a drawn pitch, and see which coaches thrived with squads
shaped like yours. Designed in the morning (`Docs/Team_Builder_Design.md`,
four decisions settled up front), implemented and QA'd the same day.

---

## What Was Accomplished

### A fantasy-XI front end on top of validated machinery

Almost every hard piece already existed and was reused rather than rebuilt:
the 22 hand-mapped formation slot sets, the archetype→slot eligibility matrix
(the one that passed the recommender's mechanical validation at t = 26.9), the
coach similarity profiles, and the team pages' 85/15 similarity/quality blend.
The genuinely new work: a player-level data export (5,570 players, 18,638
season rows, 2.4 MB), pitch coordinates for all 22 formations (validated
against the model's slot counts at export time), a resumable Transfermarkt
player-headshot scraper, and the page itself.

### The suggestion engine moved into the browser — and matches R exactly

Team pages precompute similarity in R; a user-built XI can't be precomputed.
The export now ships each qualifying coach's raw archetype-share profile (81
coaches) and the frontend computes cosine similarity + the quality blend
itself. The gate: a Manchester City 2024/25 replica XI produces **the exact
same coach ordering** from the R reference implementation and the rendered
page — Guardiola first, then Conte, Setién, Arteta, De Zerbi. Cross-era teams
(2023/24 Rodri next to 2024/25 teammates) work by construction.

### Honest by design

Two guardrails carried over deliberately: the page never predicts points for
a fantasy XI (a cross-era all-star squad is far outside the squad-value
model's support — any number would be theater), and the coach grid keeps the
descriptive-similarity labeling word for word, with the validated quality
ranking linked on the leaderboard. Plausibility chips need to know what
"this league" means for a team that has no league, so a league-context
selector gates the league/country/domestic filters.

### QA

Three chromote rounds: eligibility spot checks (no Van Dijk at striker, GK
slots list only goalkeepers), formation round-trips that preserve picks
(4-3-3 → 3-5-2 correctly benches a winger; switching back restores all 11),
search-and-pick flows, filter chips with stable card numbering, URL-hash
round-trip on a fresh load, dark mode, and 375 px. Link sweep over the new
JSON: zero dangling references. Two real bugs found and fixed (a picker tier
could be starved by a big Natural group; "Kevin De Bruyne" shortened to
"Bruyne").

---

## Project Status

| Milestone | Status |
|---|---|
| M1–M6 + website + recommender | Complete |
| Team builder (design + build + QA) | **Complete** |
| Player photo scrape (5,570 headshots) | Running, resumable (~500 done) |
| Nationality scrape | ~320 coaches remaining, resumable |
| 2025/26 pass-coordinate validation | Optional |
| Public hosting | Optional |

---

## What's Next

Let the two resumable scrapes finish, then refresh the export so every player
photo and domestic badge appears. The optional items are unchanged.
