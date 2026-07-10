# Website Implementation Plan

**Project:** Football Coach Valuation Model — presentation website
**Author:** Andrew Salisbury
**Date:** July 10, 2026
**Design reference:** `Docs/Website_Design.md` (approved)
**Status:** Not started

Phases are ordered so every phase ends in something verifiable. Phases 3–6 each deliver a working page; nothing in a later phase is needed to check an earlier one. The crest scrape (Phase 8) can run in the background any time after Phase 1.

---

## Phase 0: Result Exports (R)

New saved artifacts that the export script will need. All code goes in existing analysis files; all writes go to `src/data/results/`.

**0.1 Grades export** — in `coach_attribution.R`:
- Refactor `grade_coaches()` so it *returns* the graded tibble (it already builds one; today it only prints). Keep the printed output for interactive use.
- New `save_coach_grades()`: runs `grade_coaches()` on both BLUP tables (`coach_blups_top5.rds`, `coach_blups_14league.rds`) and writes `coach_grades_top5.rds` / `coach_grades_14league.rds` with columns: `coach_id`, `coach_name`, `blup`, `numeric_grade`, `letter_grade`, `rank`, `n_stints`, `total_games`, `n_clubs`.

**0.2 Archetype-fit export** — in `coach_fit.R`:
- New `cf_save_results()`: runs (or takes the result of) `cf_run_analysis()` and writes `src/data/results/archetype_fit.rds` containing:
  - `per_coach`: `coach_id`, `coach_name`, `archetype`, `archetype_label`, `correlation`, `n_stints`, `recurs_in_strict` (TRUE only when the pair recurs in both the fallback and strict-lagged runs — the "findings" per the design doc).
  - `global`: LRT statistic, df, p-values (both specifications), wide-creator headline coefficient — for a small credibility note on coach pages.
- Note: `cf_run_analysis()` takes minutes to run (model fits, no scraping). Run once, save, done.

**0.3 Verify assumptions the export script will rely on:**
- Confirm the `league` column format in `residuals_14league.rds` and `coach_residuals_14league.rds` (name vs code) and build the league code ⇄ display-name mapping for the 14 leagues.
- Confirm every `coach_id` / team URL yields a numeric TM id via regex (`/trainer/(\d+)`, `/verein/(\d+)`), with zero collisions and zero non-matches. Fix at the source if any URL deviates.
- Confirm `coach_images.rds` `local_path` entries resolve to files on disk.

**Done when:** three new RDS files exist in `src/data/results/`; id extraction asserts pass on all 1,774 coaches and all team-seasons.

---

## Phase 1: Export Script (`src/site_export.R`)

One idempotent entry point `export_site_data()` (working dir `src/`, like all project code). Wipes and rebuilds `site/data/` and `site/assets/` on every run; never touches hand-written files in `site/`.

**1.1 Shared helpers**
- `se_coach_num_id(url)` / `se_team_num_id(url)` — regex extractors with stop-on-failure.
- `se_write_json(x, path)` — `jsonlite::write_json(auto_unbox = TRUE, digits = 4)`, creating directories as needed.

**1.2 `site/data/coaches/<id>.json`** — per coach (~1,800 files), schema:
```json
{
  "id": 5672, "name": "Pep Guardiola",
  "img": "assets/coaches/5672.jpg",            // null if no image
  "career": {"first_season": 2008, "last_season": 2024,
             "leagues": ["Premier League", "Bundesliga", "La Liga"],
             "n_stints": 16, "total_games": 596, "n_clubs": 3},
  "rating": {                                   // headline cut per design §2
    "cut": "top5", "blup": 0.118, "numeric_grade": 92.1,
    "letter_grade": "A-", "rank": 1, "n_ranked": 668,
    "mean_residual": 0.31, "ci": [0.22, 0.40], "significant": true,
    "other_cut": { ... same fields for 14league, or null }
  },                                            // whole object null → "Unranked"
  "stints": [ {"season": 2016, "team_id": 281, "team": "Manchester City",
               "league": "Premier League", "date_from": "2016-07-01",
               "n_games": 38, "actual_points": 78, "expected_points": 74.6,
               "actual_ppg": 2.05, "predicted_ppg": 1.96,
               "residual_ppg": 0.09, "season_share": 1.0}, ... ],
  "archetype_fit": {                            // null → N/A rendering
    "findings": [{"label": "ball-playing CB", "r": 0.68, "direction": "+"}],
    "n_stints_pl": 8
  },
  "summary": "Pep Guardiola ranks 1st of 668 ..."   // generated, §5.1 of design
}
```
- Stint rows come from `coach_residuals_14league.rds` (superset of top5); `expected_points = predicted_ppg × n_games`; `season_share = n_games / games_played` for that team-season.
- Summary paragraph generated from a fixed template with data slots (grade, rank, clubs, best/worst stint, significance).

**1.3 `site/data/teams/<id>.json`** — per club (~700 files): club name, leagues, per-season rows from `residuals_14league.rds` (points, expected, residual, squad values, games, `is_b_team`, residual `null` for the coverage-filtered/NA cases with a `residual_note`), and the coach-history array (stint rows joined with each coach's headline grade/rank; SC Freiburg 2018 gets an explicit `coach: null` row).

**1.4 `site/data/leagues/<code>.json`** — per league (14 files): display name, seasons list, and per-season standings blocks (team rows with points/expected/residual/coaches in tenure order), plus the league stats block (per-league R²/RMSE — reuse `league_value_fit_diagnostic()` output, all-time top/bottom residual team-seasons, most-seen coaches).

**1.5 Small files:** `leaderboard.json` (top-5 cut, min 3 stints/10 games, top ~25 + full ranked list for a "show all" toggle), `search_index.json` (`[{t:"c"|"t"|"l", id, n}]`, ~2,500 entries, loads once), `meta.json` (export timestamp, dataset span, counts).

**1.6 Assets:** copy coach images and crests (when present) into `site/assets/`, skipping confirmed no-image entries; emit a count summary.

**1.7 Writeup:** convert `Docs/Summary_of_Findings.md` → HTML fragment via the `{commonmark}` package (no pandoc dependency), inject into a template with TOC generated from headings, write `site/writeup.html`.

**Done when:** `export_site_data()` runs clean end-to-end; spot-open Guardiola, Ranieri, Man City, Premier League JSONs and hand-check numbers against `Summary_of_Findings.md` tables; file counts match entity counts; re-running produces identical output (idempotence).

---

## Phase 2: Site Scaffold (static shell)

- Directory layout per design §4; `css/site.css` (layout, header, cards, tables, responsive rules); system font stack.
- `js/data.js`: `loadJSON(path)` with in-memory cache; query-param helper; error panel for bad/missing ids ("No coach with this id") instead of a blank page.
- Shared header partial (Home / Leagues dropdown / Writeup / search box) — injected by a small JS include since there's no build step.
- `js/components.js`: fallback badge generator (deterministic color from club name hash + 2–3 letter abbreviation, as inline SVG `<g>`), coach-photo-with-silhouette-fallback, sortable-table helper (used by team, league, and home pages), stat-card renderer.
- `README` note in `site/`: how to run locally (`python -m http.server` one-liner if the browser blocks `file://` fetch).

**Done when:** empty template pages load with header, search box does live filtering over `search_index.json`, and navigating to a bogus id shows the friendly error.

---

## Phase 3: Coach Page (richest page first — validates the whole schema)

> Load the `dataviz` skill before writing any chart code in this phase.

**3.1 Header block:** photo, name, career line, grade card (letter + numeric + cut label + rank), descriptive stats row, "Unranked — insufficient data" state.

**3.2 Career PPG chart** (`js/charts.js`, hand-rolled SVG):
- X = season, Y = actual PPG; crest image (or fallback badge) as each point; chronological connecting line; dashed expected-PPG series.
- Two stints in one season: x-jitter, both independently clickable.
- Click → detail panel below chart (club, league, tenure dates, games, actual vs expected points, PPG pair, residual in PPG and points, season share). Clicking another crest swaps the panel; Esc/close clears it.
- Sort toggle chronological ⇄ best-to-worst: sorted mode drops the connecting line, x becomes stint rank. Y-axis domain fixed across modes so bars of the same stint don't jump vertically.

**3.3 Player-type fit section:** findings list with correlation + fixed caveat line when `archetype_fit` present; the exact N/A sentence from design §5.1 otherwise.

**3.4 Summary paragraph** from JSON.

**Done when:** Guardiola, Ranieri (11 clubs — crest density stress test), a 1-stint unranked caretaker, and a 14-league-only coach all render correctly; click/sort/keyboard interactions work; page is readable at 375 px width.

---

## Phase 4: Team Page

- Header block (crest, name, leagues, aggregate record).
- Coach history table via the shared sortable-table component (chronological ⇄ best-to-worst by residual); coach thumbnails link to coach pages; grade column uses each coach's headline grade.
- Season history chart: actual vs expected points per season (paired dots + connecting rule, diverging color by residual sign); clicking a season highlights that season's rows in the table.
- Squad value trend chart (raw + minutes-weighted lines).
- Edge states: B-team label + footnote, residual "—" rows with note, Freiburg-2018-style "coach data unavailable" rows.

**Done when:** Man City (stable, long tenure), Watford (many mid-season changes), a LaLiga 2 B-team, and SC Freiburg render correctly and all cross-links resolve.

---

## Phase 5: League Page

- Season selector (dropdown, default latest, "latest available season" label in header).
- Standings table (shared component): crest + team link, points, expected, residual, coaches in tenure order, PPG; sort toggle points ⇄ overperformance.
- Diverging horizontal bar chart of residual points, crests on axis, synced to the selector.
- League statistics block (fit metrics, all-time over/underperformers, most-seen coaches).

**Done when:** Premier League and Ekstraklasa (small-league data quality edge) render for earliest and latest seasons; Ligue 1 2023 (18 teams) and Bundesliga (34 games) show correct game counts; sort + season switching don't refetch.

---

## Phase 6: Home Page + Search polish

- Hero + one-liner + writeup link; leaderboard table (photos, grade, BLUP, stints, clubs → coach pages) with "show all ranked" toggle; 14 league tiles.
- Search UX: keyboard navigation (↑/↓/Enter), type-grouped results (coaches/teams/leagues), highlight matched substring.

**Done when:** home renders from `leaderboard.json` alone; every leaderboard/tile/search result navigates to a working page.

---

## Phase 7: Writeup Page

- Verify the Phase 1 conversion renders all tables/headings correctly in site CSS; TOC sidebar with scroll-spy; embed existing `Docs/` figures where referenced.
- Single document only (no session-log appendix, per design decision).

**Done when:** side-by-side read of `writeup.html` against `Summary_of_Findings.md` shows no lost content; all internal anchors work.

---

## Phase 8: Crest Scrape (parallel track — any time after Phase 1)

- `xx_raw_team_crest_url(team_season_id)` + `xx_data_populate_team_crests()` in `source_data.r`, mirroring the coach-image pair: dedupe clubs by numeric id (~600–800), standard politeness pacing (respect all existing sleep rules), resumable, no-image cases recorded in `src/data/cache/team_crests.rds`, files to `src/data/images/crests/<id>.<ext>`.
- Smoke-test on 3 known clubs before the full run; run the full populate (~1 hour); re-run `export_site_data()` — pages upgrade from badges to crests with zero frontend changes.

**Done when:** ≥95% of clubs have a crest file, remainder confirmed no-image; coach chart and league pages show real crests after re-export.

---

## Phase 9: QA Pass + Wrap-up

- Walk the full edge-case list (design §8) item by item; record each check.
- Narrative spot-checks: Leicester 2015 and Leverkusen 2023 prominent on their pages; Klopp's pressing-forwards finding on his page; Bielsa's negative BLUP consistent with Summary Part 5.
- Broken-link sweep: script over all JSON files asserting every referenced `team_id`/`coach_id`/asset path exists.
- Cross-browser sanity (Chrome + one other), 375 px mobile pass on all five page types.
- Update `CLAUDE.md` (site layer, export command, the `site/` write-target exception), `Milestones.md`/`Plan.md` (website status), session log + progress report.

**Done when:** every §8 edge case verified, link sweep clean, docs updated.

---

## Order and Dependencies

```
Phase 0 → Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 → Phase 9
                         └───────────── Phase 8 (crest scrape, parallel) ──────────┘
```

Suggested session grouping: (0+1) exports · (2+3) scaffold + coach page · (4+5) team + league pages · (6+7+9) home, writeup, QA · 8 runs in the background of any of these after Phase 1.

## Risks / Watch Items

1. **`file://` fetch restrictions** — mitigated by documenting the one-line local server; test both modes in Phase 2, not Phase 9.
2. **Crest hotlink/format surprises** (TM may serve small or webp crests) — the Phase 8 smoke test checks dimensions/format before the full run; badges remain the safety net.
3. **League column format mismatch** between results tables — resolved explicitly in Phase 0.3 before anything depends on it.
4. **1,800 + 700 JSON files in git** — small text files, acceptable; if repo bloat becomes a concern, `site/data/` can be gitignored and regenerated (decide at Phase 9 wrap-up).
5. **Two grading curves confusion** — every grade rendering must carry its cut label; enforced as a component-level rule (grade never renders without the label), checked in QA.
