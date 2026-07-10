# Website Design Document

**Project:** Football Coach Valuation Model — presentation website
**Author:** Andrew Salisbury
**Date:** July 10, 2026
**Status:** Implemented July 10, 2026 (`site/`; build record in `Docs/Website_Implementation_Plan.md` and `Docs/Session_Log_2026-07-10.md`)

---

## 1. Purpose

A website that presents every statistic and resource the project has produced: a page per coach, per team, and per league, plus the full project writeup. The site is the public face of the analysis — it should make the rankings browsable and the methodology credible.

## 2. Decisions Already Made

| Decision | Choice | Rationale |
|---|---|---|
| Tech stack | Static site + exported JSON | R script exports all tables to JSON once; plain HTML/CSS/JS reads them. No server, no build toolchain, lives in this repo. All interactivity (click, sort, season switch) is client-side. |
| Hosting | Local only for now | Open `site/index.html` in a browser. The site must therefore work from `file://` (or a trivial `python -m http.server`) — no hard-coded absolute URLs. Structure stays GitHub-Pages-ready for later. |
| Coach rating source | Top-5 headline, 14-league fallback | Coaches present in the top-5-leagues cut (668 ranked) get that grade/BLUP as their headline, labeled "Top-5 leagues". Coaches only in smaller leagues get the 14-league number, labeled "All leagues". Both cuts shown in a detail section when both exist. |
| Team logos | Scrape crests from Transfermarkt | New scraper modeled on the coach-image scraper (Section 6.1). Until the scrape completes, a generated fallback badge (club initials on a colored circle) renders in its place — the site never breaks on a missing crest. |
| League page default season | Latest available (2024/25) | Header labels it "latest available season" so the snapshot nature is explicit. |
| Grades for 14-league-only coaches | Letter grade shown | Every ranked coach gets a letter grade; the cut label ("Top-5 leagues" / "All leagues") disambiguates the two grading curves. |
| Writeup page scope | Single clean document | `Summary_of_Findings.md` only; session logs and progress reports are not linked as an appendix. |

## 3. What the Data Already Supports

All source tables exist today in `src/data/results/`, `src/data/cache/`, and `src/data/images/`:

- **`coach_residuals_14league.rds` / `_top5.rds`** — one row per coach stint: `coach_id`, `coach_name`, `team_season_id`, `team_name`, `league`, `season`, `date_from`, `n_games`, `actual_points`, `actual_ppg`, `predicted_ppg`, `partial_residual_ppg`. This is the backbone of the coach-page graph and the team-page coach history.
- **`residuals_14league.rds`** — one row per team-season: actual points, predicted PPG, residual (in PPG and points), squad values, games played. Backbone of team and league pages. 5,087 team-seasons, 14 leagues, 2005–2024.
- **`coach_blups_14league.rds` / `_top5.rds`** — per-coach BLUP, stint/game/club counts. Input to `grade_coaches()`.
- **`coach_ranked_14league.rds` / `_top5.rds`** — mean residual, SD, SE, 95% CI, p-value, FDR-adjusted p, significance flag.
- **Coach images** — 3,528 headshots in `src/data/images/coaches/<numeric_id>.<ext>` with lookup `src/data/cache/coach_images.rds` (includes confirmed no-image cases).
- **M6 archetype fit** — computed by `cf_run_analysis()` (PL 2015/16–2024/25, 26 coaches with ≥4 stints). Not yet saved to disk — Section 6.2 adds an export. All other coaches show **N/A** as agreed.
- **Writeup** — `Docs/Summary_of_Findings.md`, rendered as the writeup page.

**Gaps the pipeline must fill** (Section 6): team crests, a saved grades table, a saved archetype-fit table, and league/season metadata for navigation.

## 4. Site Structure

```
site/
├── index.html            # home: top-coach leaderboard + league directory + search
├── coach.html            # template page; ?id=<tm_numeric_id> selects the coach
├── team.html             # template page; ?id=<tm_numeric_id> selects the club
├── league.html           # template page; ?id=<league_code> selects the league
├── writeup.html          # full Summary_of_Findings rendering
├── css/site.css
├── js/                   # vanilla JS modules (no framework)
│   ├── data.js           # JSON loading + caching
│   ├── charts.js         # SVG chart rendering
│   ├── coach.js / team.js / league.js / home.js
├── data/                 # JSON exported by R (Section 6.3)
└── assets/
    ├── coaches/          # copied headshots
    └── crests/           # scraped club crests
```

**Routing:** four template pages driven by a query parameter, not one file per entity. With ~1,800 coaches and ~700 clubs, per-entity HTML generation is needless complexity; a template + JSON lookup gives identical UX. Entity keys are the numeric IDs already embedded in Transfermarkt URLs (`/trainer/5672`, `/verein/281`), extracted at export time — URLs stay short and filenames safe.

**Navigation:** persistent header with Home / Leagues (dropdown of 14) / Writeup and a client-side search box over coach and team names (loads a small `search_index.json`, filters as you type).

## 5. Page Specifications

### 5.1 Coach page (`coach.html?id=…`)

**Header block**
- Headshot (fallback: neutral silhouette), name, career span in dataset, leagues coached in.
- **Grade card:** letter grade + 0–100 numeric grade (the "all-encompassing number" from `grade_coaches()`), BLUP with cut label ("Top-5 leagues" or "All leagues"), rank within that cut.
- Descriptive stats row: stints, total games, distinct clubs, mean residual ±95% CI, significance flag (with a plain-language note that only a handful of coaches individually clear FDR).

**Career PPG graph** — the centerpiece.
- X axis: season (2005–2024). Y axis: actual PPG for each stint.
- Each point is the **crest of the club** managed that season (fallback badge if crest missing). A coach with two stints in one season (sacked mid-season, or two clubs in one year) gets two crests side by side at that season.
- A subtle line connects points chronologically; a dashed reference series shows **expected PPG** (`predicted_ppg`) so over/underperformance is visible as the gap between crest and dashed line.
- **Click a crest** → detail panel below the chart with that stint's season statistics: club + league, tenure dates, games managed, actual points vs expected points (`predicted_ppg × n_games`), actual PPG vs predicted PPG, residual in PPG and in points-per-season terms, and share of the club's season managed.
- **Sort toggle:** chronological ⇄ best-to-worst stint (by `partial_residual_ppg`). In sorted mode the connecting line is dropped and the x axis becomes stint rank.

**Player-type fit section**
- For the 26 PL coaches with archetype data: the coach's strongest positive and negative archetype correlations (e.g. "Klopp overperforms with more pressing forwards, r = 0.67"), each with archetype label and correlation, plus a fixed caveat line that these are descriptive findings that do not survive multiple-testing correction.
- All other coaches: **"N/A — player-type data currently covers Premier League 2015/16–2024/25 only."**

**Auto-generated summary paragraph** — assembled from the data at export time (not hand-written per coach): grade, rank, portability (clubs count), best and worst season, significance status. Keeps 1,800 pages honest with zero manual curation.

### 5.2 Team page (`team.html?id=…`)

**Header block** — crest, club name, league(s), seasons in dataset, aggregate record: mean residual across seasons, best/worst season.

**Coach history table** — the primary content. One row per stint (from `coach_residuals_14league`): coach (photo thumbnail + link), season, tenure dates, games, actual PPG, expected PPG, residual, and the coach's overall grade/rank. **Sort toggle: chronological ⇄ best-to-worst** (by residual), as specified.

**Season history chart** — actual points vs expected points per season (paired bars or dot-plot with connecting line per season), colored by over/underperformance. Clicking a season highlights the coach rows for that season in the table.

**Relevant statistics** — squad value trend (raw and minutes-weighted, from `residuals_14league`), count of mid-season coaching changes, longest-tenured coach.

### 5.3 League page (`league.html?id=…`)

**Season selector** — dropdown/stepper over all seasons the league has data for (2005–2024 for most). Defaults to the latest season in the data, labeled "latest available season" in the page header.

**Standings table** for the selected season — one row per team: crest + name (links to team page), actual points, expected points, residual points, coach(es) that season (with mid-season changes shown), final PPG. **Sort toggle: most points ⇄ most overperforming** (residual), as specified.

**Overperformance chart** — horizontal diverging bar chart of residual points for the selected season (the M4 visualization, rebuilt in SVG), team crests on the axis.

**League statistics block** — teams/seasons covered, model fit for this league (R² / RMSE from the league diagnostic), all-time top over- and underperforming team-seasons, most-seen coaches in the league.

### 5.4 Writeup page (`writeup.html`)

`Summary_of_Findings.md` converted to HTML at export time (single pandoc/commonmark step in the export script — no client-side markdown parsing). Styled with the site CSS, with a table of contents sidebar. Existing figures in `Docs/` can be embedded where referenced.

### 5.5 Home page (`index.html`)

- Hero: project one-liner + link to writeup.
- **Top-coaches leaderboard** (top-5-leagues cut, min 3 stints/10 games — the table from Summary_of_Findings Part 5): rank, photo, name, grade, BLUP, stints, clubs. Links to coach pages.
- League directory (14 crest-style tiles → league pages).
- Search box (also in the global header).

## 6. Data Pipeline (R side)

### 6.1 New scraper: team crests (`source_data.r`)

- `xx_raw_team_crest_url(team_season_id)` — extract the club crest image URL from a team page (mirrors `xx_raw_coach_image_url()`).
- `xx_data_populate_team_crests()` — deduplicate clubs by numeric TM id across all team-seasons (~600–800 unique clubs), download to `src/data/images/crests/<numeric_id>.<ext>`, maintain `src/data/cache/team_crests.rds`. Standard politeness pacing, resumable, no-image cases recorded. Roughly an hour of scraping, one-time.

### 6.2 New result exports

- **Grades:** run `grade_coaches()` on both BLUP cuts and save `coach_grades_top5.rds` / `coach_grades_14league.rds` to `src/data/results/` (function currently only prints).
- **Archetype fit:** persist the per-coach correlation table and the global-model summary from `cf_run_analysis()` to `src/data/results/archetype_fit.rds` (only pairs that recur in both the fallback and strict-lagged runs are exported as "findings"; the rest ship as the full table with an exploratory flag).

### 6.3 Export script: `src/site_export.R`

One idempotent function `export_site_data()` that reads only from `src/data/` and writes only to `site/` (a deliberate, documented exception to the src/data-only rule — `site/` is a publishing target, not analysis data):

| Output | Content | Source |
|---|---|---|
| `data/coaches/<id>.json` | header stats, both-cut grades/BLUPs/ranks, per-stint series for the graph, archetype fit or `null`, generated summary | blups, ranked, grades, residuals, archetype_fit |
| `data/teams/<id>.json` | header stats, coach history rows, season series, squad value series | coach_residuals, residuals |
| `data/leagues/<code>.json` | per-season standings blocks, league stats | residuals, coach_residuals |
| `data/leaderboard.json` | home-page top table | grades + ranked (top-5 cut) |
| `data/search_index.json` | `{type, id, name}` for every coach/team/league | all |
| `assets/coaches/`, `assets/crests/` | images copied, renamed to numeric ids | images dirs |
| `writeup.html` | converted markdown | Docs/Summary_of_Findings.md |

Per-entity JSON files (rather than one giant JSON) keep first paint fast and work fine from `file://`.

**ID mapping:** the export script derives numeric ids from the TM URL ids everywhere (`sub(".*/(trainer|verein)/(\\d+).*", ...)`) and asserts uniqueness; the mapping table ships in the JSON so pages can link between each other.

## 7. Frontend Implementation Notes

- **No framework, no build step.** Vanilla ES modules; one shared CSS file; system font stack. Total JS should stay small (~1,000 lines across modules).
- **Charts are hand-rolled SVG** (in `charts.js`), not a chart library: the crest-as-data-point interaction, click handlers, and dashed expected-PPG overlay are simpler to control directly in SVG than to fight through a library's plugin API, and it keeps the site dependency-free. Load the `dataviz` skill before writing any chart code (color, axes, interaction standards).
- **Crest fallback** is a `<g>` with a colored circle + 2–3 letter abbreviation, generated deterministically from the club name — used whenever the crest file is absent, so the site works before/without the crest scrape.
- **Sorting and season switching** re-render from already-loaded JSON; no refetch.
- Works offline from `file://`: relative paths only; `fetch()` of local JSON works under `python -m http.server` and most browsers' file access — the doc for running locally will say to use the one-line server if the browser blocks `file://` fetches.

## 8. Edge Cases and Rules

1. **Two stints, one season** (coach sacked and later re-hired, or moved clubs mid-season): render both crests at that season, x-jittered; both clickable independently.
2. **Mid-season changes on team/league pages:** show all coaches for the season with games managed; the league standings row lists them in tenure order.
3. **Coaches below the ranking threshold** (<3 stints or <10 games): page still exists with stats and graph, but grade shows "Unranked — insufficient data" rather than a misleading letter.
4. **Missing images:** neutral silhouette (coaches) / generated badge (crests); no broken-image icons.
5. **Coverage-filtered team-seasons** (the 88 dropped for <80% valued minutes) and the 7 NA residuals: shown in tables with points but with residual marked "—" and a footnote, never silently omitted.
6. **B-teams in LaLiga 2:** labeled "(B team)" and footnoted that the model includes a B-team adjustment.
7. **SC Freiburg 2018** (no coach data): team page shows the season with "coach data unavailable".
8. **Grades exist for both cuts:** headline follows the decision in Section 2; the detail section shows both numbers side by side to avoid any impression of cherry-picking.

## 9. Out of Scope (this phase)

- Public hosting/deployment (structure is GitHub-Pages-ready when wanted).
- Player pages and archetype-explorer pages (natural follow-up once the big-5 SofaScore expansion lands).
- Re-running the augmented model or refreshing rankings — the site renders the published results as they are.
- Any live/scheduled data updates; the site is a snapshot regenerated by re-running `export_site_data()`.

## 10. Build Order

1. **Exports first:** grades + archetype-fit RDS exports; `site_export.R` skeleton producing coach/team/league JSON with fallback badges (no crests yet). Verifiable in isolation.
2. **Coach page** end-to-end (the richest page: graph, click-detail, sort, grade card, N/A fit section) — validates the JSON schema design.
3. **Team page**, **league page**, **home + search** (reuse chart/table components).
4. **Writeup page** conversion.
5. **Crest scrape** run (parallel to 2–4; site upgrades automatically from badges to crests on next export).
6. Cross-page QA pass over edge cases in Section 8, spot-checking known narratives (Guardiola, Ranieri, Leicester 2015, Leverkusen 2023).

## 11. Open Questions

None — all design questions resolved (see Section 2). Status: approved for implementation; work not yet started.
