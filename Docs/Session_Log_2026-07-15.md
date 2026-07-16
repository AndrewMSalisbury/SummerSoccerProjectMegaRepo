# Session Log — 2026-07-15: Squad-Fit Gap Diagnostic

## Purpose

Getting-up-to-speed pass on the whole project, then two design docs for future
work, then the first of them built end to end: the **squad-fit gap** — a
per-(coach, team) diagnostic on the team-page similarity grid that shows which
of a squad's value a candidate coach's usual shapes leave idle, and which
positions those shapes can only fill with a poor positional match. Design:
`Docs/Squad_Fit_Gap_Design.md`.

---

## Part 0 — feature brainstorm + two plan docs

At Andrew's request, sketched fan- and team-facing feature ideas, then wrote two
full design docs for the two he picked:

- `Docs/Squad_Fit_Gap_Design.md` — the diagnostic built this session.
- `Docs/Coach_Descriptive_Profile_Design.md` — a three-layer "what are coaches
  good at / what do they do / what makes them good" package (strength
  decomposition → style fingerprint → style↔quality association), best-first,
  each layer labeled on its own honesty gradient. **Not built yet** — next up.

## Part 1 — settled design decisions (Andrew, 2026-07-15)

| Decision | Choice |
|---|---|
| Surface | Per-coach expandable panels on the similarity grid (not a team-level card) |
| "Stranded" definition | *Worth more than a starter* — benched player worth > the cheapest player the coach's shape fields, + value played out of role |
| Team builder | Deferred to a follow-up; team pages only this cut |

## Part 2 — implementation

All on top of existing, validated machinery — no new model, no scrape, no points
claim (the deployment layer failed the 2026-07-13 payoff test and this inherits
that exploratory label).

- **`coach_recommender.R`**: refactored `cr_best_xi_value` → `cr_best_xi_assign`
  (returns the XI with per-slot eligibility + the bench with best-fit, not just
  the summed value; value fn now wraps it). New `cr_squad_fit(squad, fvals,
  profile, rigidity)`: profile-weighted over the coach's real repertoire (shapes
  with p(f|C) ≥ 0.10), rolls stranded value up by archetype and positional gaps
  (slots filled below eligibility 0.5) up by slot type. `cr_score_team()` now
  exposes the squad + formation values as attributes; `cr_save_results()`
  computes a `squad_fit` block for every similarity-grid coach on all 96
  latest-season big-5 teams.
- **`site_export.R`**: `se_squad_fit()` ships a compact per-coach block
  (stranded archetypes + €, thin slots) onto each similarity card.
- **`team.js` / `site.css`**: expandable "▸ Squad fit" panel per card; the
  toggle `preventDefault`+`stopPropagation`s so it doesn't navigate the card
  (the card is an `<a>`). Theme-aware styles in both blocks.

## Part 3 — verification

- **Unit test** (scratchpad `test_squad_fit.R`, Man City 2024): best-XI
  assignment reconciles exactly (`value == Σ elig·value + gk_value`) for 4-3-3
  and 3-5-2; a rigid 3-5-2 coach strands €193m of advanced-creator value (no W
  slots), the squad's own best shape strands nothing coach-attributable.
- **Regen** (`regen_recommender.R`): scorer rebuilt (warm, 0.7 min), all 96
  teams scored, **96/96 carry a squad_fit block**. Reused the saved payoff folds
  (validation carried forward, not re-run).
- **Export + JSON check** (`export_and_verify.R`): 96/96 team JSONs carry
  squad-fit cards; per-coach variation confirmed (Leicester: Ranieri vs Sergio
  González differ).
- **Chromote QA** (`qa_squad_fit.R` + shots): 9/9 City cards have a toggle;
  clicking three does **not** navigate (URL unchanged); panels render in light,
  dark, and 375 px.

## Part 4 — QA-driven design change (dropped the gap-% headline)

The first render exposed a real wart on the flagship card: Guardiola showed a
*higher* "% idle" (4.5%) than Conte (2.2%) / Allegri (1.7%) — backwards as a fit
read — and the headline € (€36m) didn't reconcile with the strand list (€189m).
Cause: the gap-% scalar anchors on the squad's *value-maximizing* XI (a two-
striker shape cramming Haaland + Marmoush + creators), so a one-striker
possession coach looks wasteful vs that artifact, and it's a different
(rigidity-blended) quantity than the raw strand total.

Fix: the panel now **leads with the strand + gap lists** (internally coherent
and genuinely coach-differentiating — Conte's 3-5-2 strands €100m of creators
for want of wide slots, Allegri's back-3 €193m, Guardiola less). `gap_pct` /
`gap_eur` are still computed and shipped in the JSON for a possible future
team-level card but render nowhere. Recorded in design §3.5, CLAUDE.md.

## Part 5 — UX revision: inline panel → right-side pop-up drawer (2026-07-15, later)

Andrew liked the feature but preferred the cards' original clean look, asking for
the detail to appear in a pop-up on the right when a card is clicked. Reworked the
frontend (no R/data change — the JSON already carries `squad_fit`):

- Cards restored to their clean form; the inline expandable panel removed.
- A single right-side **drawer** (built once, appended to `body`) slides in when a
  card is clicked, showing the coach header + grade, plausibility badges, the
  squad-fit detail, and a "View full coach profile →" link. Backdrop + Escape + ×
  close it.
- Click semantics: normal left-click opens the drawer (`preventDefault`);
  ctrl/⌘/shift/middle-click fall through to the card's `href` so power-users can
  still open the coach profile in a new tab.
- z-index fix found in QA: the drawer/backdrop (was 40/41) sat **below** the
  sticky header (50), hiding the coach name behind it — raised to 110/111 so the
  drawer is a true full-page overlay.
- Chromote QA (`qa_drawer.R`): click opens the drawer without navigating (URL
  unchanged); name/detail/profile-href correct (Conte → id 3517); Escape closes;
  ctrl-click does **not** open the drawer; light + dark element shots confirm
  styling. `team.js` CSS: `.sf-drawer` / `.sf-backdrop` / drawer head / section
  title / profile link (both themes); the old `.sf-toggle` / `.squad-fit` rules
  removed.

## Part 6 — richer coach dossier in the drawer (2026-07-16)

With the roomier right-side drawer, Andrew asked to make the content bigger and
more visually appealing and to add more about each coach (preferred formation,
teams coached, etc.). Added a descriptive **dossier** on top of the existing
squad-fit detail — still no new model, no scrape, no points claim:

- **`coach_recommender.R`**: new `cr_coach_dossier(scorer, coach_ids)` — per
  coach: top-3 preferred formations (recency-weighted shares from
  `scorer$profiles`), rigidity, career span (first/last season, total games,
  stints), leagues, and clubs coached (from `coach_residuals_14league.rds`,
  most recent first). Restricted to the 81-coach similarity pool
  (`thriving$coach_id`) so `recommender.rds` stays lean; stored as
  `out$dossier` (named list by coach_id).
- **`site_export.R`**: `se_coach_dossier()` formats it (formation %, club spans
  like `2016–24`, pretty league names via `se_league_names`) onto every
  similar-coach entry as `career`.
- **`team.js` / `site.css`**: `drawerContent` rebuilt — larger header, a 3-tile
  stat row (match % / career residual / span+clubs+games), **preferred-formation
  meter bars** with a rigidity descriptor line (`rigidityLabel`), **clubs-coached
  chips** with year spans + a leagues line, then the squad-fit box (now titled
  "Squad fit at <team>"), then the profile link. Drawer widened 370 → 440px.
- **Regen + export**: reran `cr_save_results` (warm scorer, reused payoff folds),
  `recommender.rds` now carries 81 dossiers; re-exported the site. Face-valid
  spot check — Guardiola: 4-2-3-1 48% / 4-1-4-1 26% / 3-2-4-1 12%, "sticks
  tightly to his usual shape", Man City 2016–24 / Bayern 2013–15 / Barcelona
  2008–11.
- **Chromote QA**: drawer opens without navigating (URL unchanged); all sections
  render (3 stat tiles, 3 formation rows, 3 club chips); geometry check confirms
  no horizontal overflow (`scrollW == clientW`, pct labels inside the padding);
  light + dark both clean.

Then, at Andrew's request, the squad-fit block itself was made graphical rather
than one line of text: the underused-value archetypes now render as a **mini
horizontal bar chart** (label · €m-scaled bar · value) under a "Squad value his
shapes underuse" subhead, and the thin positions render as **amber
stretch-position chips** under "Positions his shapes fill only with a stretch"
(new theme-aware `--warn` token). Verified on a coach with gaps (Igor Tudor at
Lyon: back-3 shapes underuse wide creator/pressing forward/deep playmaker, thin
at centre-back) in light + dark. Frontend-only (`team.js`, `site.css`); no
re-export.

## Files added/modified

- `Docs/Squad_Fit_Gap_Design.md`, `Docs/Coach_Descriptive_Profile_Design.md` — new
- `src/coach_recommender.R` — `cr_best_xi_assign`, `cr_squad_fit`,
  `cr_slot_labels`, `cr_arch_label`, score/save wiring
- `src/site_export.R` — `se_squad_fit`, similarity-card wiring
- `site/js/team.js`, `site/css/site.css` — squad-fit panel + styles
- `data/results/recommender.rds` — regenerated with `squad_fit`
- `site/data/`, `site/assets/` — re-exported
- `Docs/Milestones.md`, `CLAUDE.md`, this log

## Reproduction

```r
# working dir src/
source("source_data.r"); source("coach_recommender.R")
folds  <- readRDS("data/results/recommender.rds")$meta$payoff
scorer <- cr_build_scorer()
cr_save_results(scorer, folds)          # now includes $teams[[t]]$squad_fit
source("site_export.R"); export_site_data()
```

## Loose ends / next

- **Not committed** — working tree has the code + regenerated results/site
  (plus the still-uncommitted player-image scrape from 2026-07-14). Commit when
  Andrew asks.
- **Team-builder squad-fit panel** deferred (design §5) — reuses the identical
  differ client-side.
- **Next feature:** the descriptive-coach package
  (`Docs/Coach_Descriptive_Profile_Design.md`), Layer A (strength decomposition)
  first — the cheapest, most defensible piece.
