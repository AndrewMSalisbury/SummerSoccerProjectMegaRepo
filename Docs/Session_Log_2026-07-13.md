# Session Log — 2026-07-13

## Purpose

Record of decisions made, code changes, results produced, and their meaning. This
session designed and then one-shot implemented the **coach recommender**: given a
team's squad, rank candidate coaches by predicted performance, with plausibility
filters and a similarity layer, embedded on each big-5 team page.

---

## Part 1: Design (`Docs/Coach_Recommender_Design.md`)

Agreed interactively before implementation. The core decomposition:

```
predicted PPG(coach, team) = f(weighted value the coach would deploy)   ← formation layer
                           + coach quality BLUP (M5)
                           + Σ axes x(team) × (global β + coach's shrunken slope)
```

Key design principles, all downstream of one statistical fact — per-coach ×
archetype effects never cleared FDR in M6 — plus one modeling insight:

- **Nothing ranks coaches on raw per-coach correlations.** Every coach-specific fit
  quantity is a shrunken random effect; the system degrades to "hire the best coach"
  where it knows nothing.
- **The M4/M5 residual is blind to value wastage by construction** (it conditions on
  the minutes-weighted value that actually played). The formation/deployment layer
  forecasts the *deployed value* factor; the residual layers forecast the rest.
  Andrew's formation idea fills a genuine gap, not a bolt-on.
- **Plausibility (would he coach here?) is filters + badges, never score terms**:
  league/country coached, big-5 proven, club level, recency, nationality.
- **Pre-registered payoff validation** with a fixed acceptance rule: a layer ships
  in the headline score only if it does not hurt out-of-sample RMSE on new
  coach-club pairings. Decided before any result was seen.

Settled with Andrew: all 2,341 coaches scoreable (degrading tiers); recent-weighted
formation prior; theory-driven composite axes; full scope with the recommendations
embedded **on each team page** (no separate page).

## Part 2: Implementation (`src/coach_recommender.R`, `cr_` prefix)

Ten phases, each gated; all gates run and recorded. Heavy intermediates cached to
the session scratchpad; everything reproducible from the file.

### Phase 0 — sizing (decisions frozen before modeling)

- **22 distinct formation strings** cover all 36,022 team-matches (essentially 100%
  formation coverage). Slots hand-mapped per string — no lossy family grouping for
  the best-XI step. Families (back-line × striker count, 2×2) only for decay/rigidity.
- Base rates: back-3/5 = 28% overall, **rising 10.7% (2015/16) → 36.2% (2024/25)**;
  Serie A 43%, La Liga 16%. Genuine two-striker shapes ≈ 33% — the formation layer
  has real discriminating power.
- **Axis collinearity caught the planned axes**: destroyers (M1+D1) vs build-up
  (D2+M2) r = −0.868 (compositional mirror images). Merged once, pre-fit, into a
  bipolar **spine** axis. Final axes: A1 creators (F3+M4), A2 spine, A3 wing-back
  (M3); max |r| = 0.47.
- Composition rebuild verified exactly against the published cf run (1,485 stints,
  26.2% fallback, 2.9% unclassified).

### Phase 1 — formation profiles, δ, rigidity

- Coach formation attribution: 35,826 team-matches across 516 coaches (M5
  date-bracket rule reused verbatim).
- **δ = 0.3** chosen out-of-sample: predicting each coach's formation-family mix at
  his *next* club, total variation distance, interior minimum on the grid
  0.05–1.0 (uniform career weighting = δ 1.0 was worst). Differences small (~1% TV)
  but consistent: the last one-two seasons dominate.
- **Rigidity** (entropy of δ-weighted family mix + cross-club persistence): face
  validity excellent — Italiano 0.99, Iraola 0.92, Klopp 0.91, Sarri 0.85,
  Marcelino 0.86 rigid; Streich 0.09, Galtier 0.22, Simeone 0.23, Davide Nicola
  0.28 adaptive. Gasperini: 97% back-3.

### Phase 2 — eligibility, best XI, deployed value — GATE PASSED

- Archetype → slot matrix (soft penalties), TM-position fallback at a 0.9 discount;
  greedy + pairwise-swap max-value XI (no lpSolve dependency).
- Sanity: Man City 2023/24 4-3-3 picks Dias/Gvardiol/Rodri/Foden/Haaland correctly;
  the squad's value maximizes in two-striker shapes (4-4-2 €952M vs 4-3-3 €922M —
  Haaland + Álvarez).
- **Mechanical validation: at 316 historical coach arrivals, player fit to the
  incoming coach's shapes predicts minutes share beyond market value — t = 26.9;
  mean within-stint Spearman 0.52, positive in 100% of stints.**

### Phase 3 — random-slope fit model

`partial_residual ~ 11 shares + fallback + (1 + A1 + A2 + A3 || coach) + (1 | club)`,
games-weighted, bobyqa. **Coach-specific slopes NOT significant: LRT χ² = 2.65,
df = 3, p = 0.449.** Wing-back slope variance shrank to exactly zero. Slope BLUPs
have amusing face validity (Guardiola/Klopp/Arteta top creators & spine) but the
model says mostly noise; kept under shrinkage, fate decided by Phase 5.

### Phase 4 — scorer

`cr_score_team()`: quality (BLUP, cut-labeled) + fit (slope BLUPs × centered axes)
+ deployment (β_wv × log deployable ratio vs a league-average coach), approximate
95% intervals from posterior variances, full vs quality-only tiers. Face validity:
Guardiola #1 for City (+0.27 PPG ≈ +10 pts vs average coach); at Atalanta the
deployment term correctly punishes S. Inzaghi's 3-5-2 (−0.048 — it strands
Lookman/De Ketelaere wide-creator value). Component spreads sane (quality sd 0.021
dominates; fit 0.006–0.014; deployment 0.004–0.009). lme4 gotcha fixed: with `||`
syntax, `ranef(condVar = TRUE)` returns postVar as a *list* of per-term arrays.

### Phase 5 — payoff validation (pre-registered) — THE VERDICT

Framing fixed before results: primary = pre-hire information set (raw squad value;
realized weighted value doesn't exist before you hire); the design's realized-value
framing ran as sensitivity. LOSO 2016–2024, **785 new coach-club pairings** (no
stint at that club the season before), games-weighted RMSE:

| Tier | Pre-hire | p | Realized | p |
|---|---|---|---|---|
| value only | 0.3124 | — | 0.3016 | — |
| + quality BLUP | 0.3103 | 0.052 | 0.2992 | **0.016** |
| + global archetype effects | 0.3099 | 0.33 | 0.3000 | n.s. |
| + fit slopes + deployment | 0.3101 | n.s. | 0.3003 | n.s. |

Acceptance rule applied: **quality ships; fit + deployment are exploratory-only**
(−0.0003, 4 folds better / 5 worse — a wash). Notable positive: the quality result
is a harder, better-targeted version of Part 4 (new pairings, expanded-era data) and
it *passes* — the M5 BLUPs generalize to the hiring decision. Survivorship note:
clubs already hire for fit, so realized appointments understate the fit signal.

### Phases 6–7 — career facts, similarity

- Career facts (2,341 coaches): leagues/countries, big-5 games, **club level**
  (games- and δ-weighted percentile of clubs coached by squad value across the 14
  leagues — Guardiola 100.0, Ancelotti 99.4, Ferguson 98.9 last seen 2012, Danny
  Röhl 32), last season, nationality. Spot checks all pass.
- Similarity profiles (residual-softmax-tilted stint compositions, τ = 0.2):
  self-similarity gate passed (held-out stint ranks at the 82nd percentile against
  the coach's own profile, median over 149 coaches). Site strip restricted to
  coaches with ≥4 big-5 stints and positive career residual. City 2024/25 →
  Setién, Guardiola, Pochettino, Rose, Arteta.

### Phase 8 — site

- `cr_save_results()` → `data/results/recommender.rds` (96 latest-season big-5
  teams scored, zero skips; facts; payoff meta).
- `site_export.R`: `se_suggestions()` embeds the block in team JSON — ranking by
  the validated quality score, fit ("Fit") and deployment ("Shape") as exploratory
  columns, badges precomputed against the team (this-league / this-country / big-5 /
  club level / last-seen / domestic), level-band and active-since thresholds shipped
  in the JSON so the frontend stays dumb.
- `team.js`: filter chips (AND-combining, default off, badges always visible),
  validated/exploratory sort toggle, similarity strip, honest footnote (including
  the Guardiola-to-Getafe wink); non-big-5 clubs get a note + leaderboard link.
  CSS: chips/badges/strip, both themes.
- QA: chromote screenshots — City light/dark/filtered/exploratory-sort/375px, Leeds
  note card. Filters verified live (Ferguson drops on "recently active"; Howe shows
  the domestic badge). Link sweep: 96 suggestion blocks, every coach id/img
  resolves, 0 problems. (Missing avatars in one screenshot were `loading="lazy"`
  below-fold images, not data gaps — JSON verified.)

### Post-review restructure (same day, Andrew's direction — two revisions)

**Revision 1:** Andrew judged the similarity layer the most useful, team-specific
content, so it became the card's dominant graphic — a grid of large cards (photo,
name, grade chip with cut label, rank-scaled similarity meter, % match + career
residual + stints) — with the validated-quality candidate table demoted below it.

**Revision 2:** Andrew wasn't convinced the quality table adds much on a team page
(its order is team-independent), so the card is now **similarity-only**: the
plausibility chips moved onto the similarity grid, which shows the 9 closest
matches *of the filtered pool* — a filter backfills with coaches who weren't in
the unfiltered nine (City + "This country" surfaces Ancelotti/Pellegrini/Conte/
Koeman; + "Domestic" honestly leaves only Howe and Dyche). To support this the
export ships the **full qualifying pool** (~81 coaches per team: ≥4 big-5 stints,
positive career residual, ranked by similarity) with per-team badge fields
(`se_coach_badges()` helper). The validated-quality table is hidden but its data
still ships in the JSON (`suggestions.coaches`) and the code documents why —
restoring it is frontend-only. The footnote now points to the leaderboard as the
home of the validated ranking. Verified by live chromote click-tests and
screenshots; each card carries its badges so filter pass/fail reasons are visible.

## Part 3: Nationality scrape (`source_data.r`)

- `xx_raw_coach_nationality()` (header `span[itemprop='nationality']`, flag titles,
  info-table fallback; NULL = fetch failure for retry vs NA = confirmed missing) and
  `xx_data_populate_coach_nationalities()` (image-scraper pattern: resumable lookup
  `data/cache/coach_nationalities.rds`, per-coach saves).
- The WAF cookie still works, but **TM intermittently 502/504s trainer profile
  pages**: two runs aborted on consecutive-failure streaks. Hardened with
  backoff-before-abort (120s, 5 strikes) and **priority ordering** (ranked coaches
  by career games first) so partial coverage covers the pool the site actually
  shows. Scrape running at session close; export picks up whatever coverage exists
  (domestic badge simply absent for unscraped coaches).

## Documented limitations

Summary_of_Findings limitation #9: big-5-only team specificity; exploratory fit/
deployment labeling is mandatory; survivorship-conservative validation; kickoff
formations only; filters are history proxies, not availability; nationality
coverage partial until the resumable scrape completes.

## Files added/modified

- `Docs/Coach_Recommender_Design.md` — new (design; status updated with gate outcomes)
- `src/coach_recommender.R` — new (~1,100 lines: formations, δ/rigidity, eligibility
  + best XI + deployable, random-slope model, scorer, payoff validation, career
  facts, similarity, results export)
- `src/source_data.r` — nationality scraper (+ backoff/priority hardening)
- `src/site_export.R` — recommender load, `se_suggestions()`, team JSON block
- `site/js/team.js` — suggestions section (chips, table, strip, note card)
- `site/css/site.css` — chips/badges/similarity-strip styles (both themes)
- `data/results/recommender.rds` — new results file
- `data/cache/coach_nationalities.rds` — new (partial, resumable)
- `site/data/`, `site/assets/`, `site/writeup.html` — regenerated
- `Docs/Summary_of_Findings.md` — Part 7, limitation #9, conclusion, Part 4 note
- `Docs/Plan.md`, `Docs/Milestones.md`, `CLAUDE.md` — recommender sections
- `Docs/Session_Log_2026-07-13.md`, `Docs/Progress_Report_2026-07-13.md` — this session

## Reproduction

```r
# working dir src/
source("source_data.r")
source("coach_recommender.R")
scorer <- cr_build_scorer()               # ~15 min cold (composition + attribution)
folds  <- cr_payoff_validation(scorer)    # ~20 min (per-fold refits + deployables)
cr_save_results(scorer, folds)            # scores 96 teams -> recommender.rds
source("site_export.R"); export_site_data()
# nationality (resumable, safe to re-run until complete):
xx_data_populate_coach_nationalities(priority_ids = <ranked coach ids>)
```

## Next steps

- Let the nationality scrape finish (resumable; re-run `cr_save_results()` +
  `export_site_data()` afterward so all domestic badges appear).
- Optional: 2025/26 pass-coordinate validation of archetypes (unchanged from M6).
- Optional: public hosting (unchanged).
