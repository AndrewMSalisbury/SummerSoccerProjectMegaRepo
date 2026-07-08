# Session Log — 2026-07-07 (session spans July 6–7)

## Purpose

Record of decisions made and work completed. This session opened a new research direction — coach/player-type fit using SofaScore data — and built the data infrastructure for its pilot: a SofaScore scraper module, a Transfermarkt↔SofaScore player crosswalk, and the start of the staged pilot scrape.

---

## New Research Direction: Coach/Player-Type Fit

### The idea

Use SofaScore's per-player charts and statistics to assign players characteristics (archetypes), then test whether coaches systematically over/underperform (per the M4/M5 residual metric) depending on the player types at their disposal. Fits the Milestone 6 "Playing Style Analysis" stretch goal.

### Design decisions from discussion

- **Endogeneity guard:** a player's observed behaviour in season X reflects the coach's system in season X. Player characteristics will be *lagged* — defined from prior seasons — when testing coach fit.
- **Low-dimensional archetypes:** the residual signal is small (coach explains ~2–9% of variance), so the design uses a handful of robust player archetypes (~6–10), not many fine-grained categories.
- **Scope:** pilot on Premier League 2015/16–2024/25 before considering more leagues.
- **Framing:** descriptive findings ("coach X overperforms with player type Y"), each backed by statistical evidence; not a full inferential expansion of the core model.
- **Formations:** coach formation tendencies will be measured empirically from per-match lineup data rather than a static "preferred formation" label.

---

## SofaScore Data Layer (`src/source_sofascore.r`)

New module, `ss_` prefix, mirroring the `xx_raw_*`/`xx_data_*` two-tier convention. Caches per league-season under `data/cache/sofascore/`.

### Access method

SofaScore 403-blocks all plain HTTP clients by TLS fingerprint (R httr, curl — headers irrelevant). All requests therefore go through **headless Chrome via {chromote}** (installed to the user library). This matches what the maintained ScraperFC library does (it switched to a real browser for the same reason).

### What is scraped

| Layer | Endpoint | Contents |
|---|---|---|
| Player-season | league statistics (paginated) | enumeration: every player with an appearance (~570/season) |
| Player-season | player season statistics | ~110 numeric fields: zone-split passing, dribbles, duels, crosses, xG/xA, touches, minutes |
| Player-season | player season heatmap | ~1,000–1,600 weighted (x, y, count) points on a 0–100 pitch grid |
| Match | season events (paginated) | all matches: teams, scores, dates, round, coverage flags |
| Match | lineups | per-team **formation** + per-player match statistics (~21–42 fields), one request covers all ~30 players |
| Match | shotmap | every shot: pitch coordinates, xG/xGOT (where available), body part, situation, outcome |
| Match (2025/26+ only) | rating-breakdown | see Pass Charts below |

### Historical coverage (verified by smoke tests)

- Per-player match stats, formations, shot **coordinates**: available back to **2015/16** (all 380 matches of 2015/16 have `hasEventPlayerStatistics`).
- **xG**: not present in 2015/16 (`has_xg = 0` season-wide); begins in a later season — the per-event flag records exactly where.
- Season heatmaps and season statistics: verified for 2015/16 and 2023/24.

### Politeness / resilience

- 4–7s jittered sleep per request; 90s rest every 250 requests; 10-minute backoff on 403/429.
- Only HTTP 404 is recorded as "missing" (never retried); rate-limit errors are retried on the next run.
- Populate loops abort cleanly after 3 consecutive failures with all progress saved; every cache is written every 25 items. Fully resumable.

---

## Rate-Limit Incident (July 6) and Response

A one-off endpoint-discovery step loaded a full SofaScore match page in the browser (~70 simultaneous requests), which triggered an **IP-level block of ~20–24 hours** on all API paths. Key lessons, now encoded in the module:

- The block trigger was **burst velocity**, not sustained scraping — steady 2–3.5s pacing was never punished across two days of testing.
- Community claims of "30s between requests" trace to continuous live-polling use cases (betting bots), not bulk historical scraping; nevertheless delays were raised to 4–7s for the pilot.
- The incident exposed that a 403 would previously have been mis-recorded as "data missing" and never retried — fixed before any large scrape ran.

---

## Pass Charts Found (`rating-breakdown`)

Andrew had seen true pass charts (every pass as a start→end line) on SofaScore; a dozen guessed endpoint names all 404'd. The endpoint was found by opening a debug Chrome window (`--remote-debugging-port`), letting Andrew browse to the chart, and logging the tab's API traffic via chromote.

- **Endpoint:** `/api/v1/event/{event_id}/player/{player_id}/rating-breakdown`
- **Contents:** complete per-match action chart — passes (start + end coordinates, outcome, key-pass flag), dribbles, defensive actions, ball-carries. Verified complete: pass count equals the player's `totalPass`.
- **Coverage limit:** exists **only from 2025/26 onward** (verified: present Aug 2025, 404 for May 2025 and earlier). It arrived with SofaScore's new tracking stats (top speed, distance covered, progressive carries).
- **Implication:** unusable for the historical window; candidate as a *validation layer* — check that archetypes from cheap historical features agree with archetypes from true pass coordinates on 2025/26. `ss_raw_player_event_breakdown()` is implemented and ready.

---

## Transfermarkt↔SofaScore Crosswalk (`src/sofascore_crosswalk.r`)

Links SofaScore numeric player ids to Transfermarkt player URLs so SofaScore features can join `players.rds` and the residual tables. Per league-season: teams are mapped by token overlap, then players matched within team by a rule ladder — exact normalized name → reordered tokens → token subset (TM "Gabriel" vs SS "Gabriel Magalhães") → token prefix (SS "Max Kilman" vs TM "Maximilian Kilman") → fuzzy with a clear-winner requirement (≤0.30 distance, runner-up far behind) — with a league-wide fallback (exact/tokens only) for mid-season movers. Rules fall through on multiple hits so stricter rules can disambiguate; a TM player claimed by two SS players demotes both.

**Result, PL 2023/24: 568/570 matched (99.6%).** All 22 non-exact matches manually verified correct. The 2 unmatched are Chelsea youth players absent from the TM squad cache (correct behaviour).

Two bugs caught during development, recorded here because they would have silently corrupted results:

1. **Team-name stopwords:** stripping "United"/"City" as filler mapped *both* Manchester clubs to Manchester City. Symptom: Man United players matching league-wide instead of in-squad. Only `fc`/`afc` are stripped now, and duplicate team mappings are a hard error.
2. **`substr()` vectorization:** R's `substr(a, 1, n)` ignores all but the first element of `n`, which silently disabled the prefix rule. `substring()` is the correctly vectorized form.

---

## Staged Pilot Scrape

Full pilot = ~19,000 requests across 10 seasons (~3h/season at current pacing). Run staged: one season first to validate the pacing survives, then the rest.

**Stage 1 (2023/24, season id 52186) was launched and running at session close** — 100/567 players done, zero failures. Remaining nine seasons ≈ 27 further hours, expected as overnight runs. Everything is resumable; a block would cost waiting time only.

---

## Files Modified

- `src/source_sofascore.r` — new: SofaScore data layer (player-season + match layers, politeness, resume)
- `src/sofascore_crosswalk.r` — new: TM↔SofaScore player crosswalk
- `src/data/cache/sofascore/` — new cache directory: players/stats/heatmap/status for 52186 (in progress), events/formations/match_stats/shots for 52186 + 10356 (smoke), `crosswalk_52186.rds`
- `Docs/Session_Log_2026-07-07.md` — this file
- `Docs/Progress_Report_2026-07-07.md` — session progress report

Not yet committed to git (scrape caches still filling; commit planned once stage 1 completes).
