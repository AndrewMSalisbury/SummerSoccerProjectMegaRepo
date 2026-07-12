# Session Log — 2026-07-12

## Purpose

Record of decisions made, code changes, results produced, and their meaning. This session verified and committed the completed big-5 SofaScore scrape, then extended the entire M6 archetype/coach-fit analysis from the PL pilot to all five leagues.

---

## Part 1: Big-5 Scrape Verified and Committed

The scrape launched July 9 (run mostly by Andrew between sessions) was verified season by season: all 40 new league-seasons complete after a small finisher pass (6 players + 2 matches that had failed transiently and were queued for retry). Committed as `b65a2d5`.

**Coverage facts recorded in CLAUDE.md:**
- Events include relegation playoffs where the league has them (Bundesliga 308 = 306 + 2; Ligue 1 similar in barrage years, including the Ligue 2 playoff rounds that feed the barrage).
- Ligue 1 2019/20 has 279 matches (COVID abandonment).
- Shotmaps have a permanent 404 hole clustered in 2018/19 (~20–31 matches per league outside the PL).
- Final totals: ~22k new player-seasons, ~14k new matches; the 2–3s pacing was never rate-limited.

---

## Part 2: M6 Extended to All Big-5 Leagues

### Archetypes rebuilt on the full dataset

`pa_build_features()` is now league-aware: **17,219 qualifying player-seasons** (≥600 minutes, non-GK) across 50 league-seasons, same 38 style features. Z-scoring is now within **league × season × position group** — without the league term, systematic pace/volume differences between competitions would dominate the clusters and archetypes would degenerate into league labels.

Same clustering recipe (k-means, seed 6, D=4/M=4/F=3). The 5× data **improved split-half stability at the chosen k**: D 0.85 (PL pilot: 0.68), F 0.92 (was 0.32), M 0.62 (was 0.48). Silhouette still prefers k=2 everywhere; the fine cut remains a deliberate interpretability choice.

**The M-group archetypes reorganized, and one is genuinely new:**

| Id | Big-5 label | Examples | vs PL pilot |
|---|---|---|---|
| M1 | destroyer | Casemiro, Ndidi, Skhiri, Romeu | was "deep playmaker" |
| M2 | deep playmaker | Kroos, Modrić, Jorginho, Parejo, Koke | was "destroyer" |
| M3 | **wing-back** | Gosens, Hateboer, Kadeřábek, Trimmel | **new** — was "advanced creator" |
| M4 | advanced creator | De Bruyne, Müller, Fekir, Kostić | absorbed "wide midfielder" |

The wing-back archetype could not exist in the PL pilot — back-3 systems are too rare in England; Bundesliga and Serie A data surfaced it. D and F archetypes kept their meanings (D1 no-nonsense CB … F3 wide creator), with reassuring face validity: Messi and Mbappé in wide creator, Lewandowski/Kane/Immobile in box striker, Van Dijk/Rüdiger/Marquinhos in ball-playing CB, Kimmich straddling D2/D4/M2 across seasons as his role actually changed.

`pa_archetype_labels` updated; `archetypes.rds` re-cached (17,219 rows, archetype sizes 698–2,161).

### Team-mapping failures found and fixed

Extending attribution beyond the PL broke `ss_crosswalk_team_map()` in three distinct ways, all caught by hard-stop guards rather than silent corruption:

1. **Name drift within a season:** one SofaScore team id can carry several names across events ("Deportivo de A Coruña" vs "… La Coruña"). Fix: modal name per team id before mapping.
2. **Jaccard token overlap fails on German/French naming:** "Borussia M'gladbach" mapped onto Borussia Dortmund via the shared "borussia" (all 10 Bundesliga seasons); "Olympique Lyonnais" tied with Marseille; "1. FC Nürnberg" matched nothing (digits are stripped in normalization; nurnberg ≠ nuremberg).
3. **Playoff contamination:** SofaScore league seasons include relegation barrages, so lower-division clubs (Nürnberg 2015, Holstein Kiel 2020, Saint-Étienne/Rodez/Paris FC in Ligue 1) appear in team lists and stole league teams' mappings.

**The rewritten mapper** (shared by `ss_build_crosswalk()` and `cf_season_match_minutes()`):
- token equivalence = equal | containment ≥4 chars (gladbach ⊂ monchengladbach, lyon ⊂ lyonnais) | edit distance ≤2 for tokens ≥7 chars (nurnberg ≈ nuremberg);
- **greedy one-to-one assignment** — best-scoring pairs claim teams first, so exact "Borussia Dortmund" consumes the Dortmund slot before Gladbach's weak overlap can, and barrage teams are left unmapped (score < 0.2 or no slots remaining) instead of mis-mapped.

`cf_season_match_minutes()` additionally pre-filters events to teams with ≥10 appearances (drops barrage matches) and hard-stops on any unmapped or duplicated league team. `ss_build_crosswalk()` also gained an NA-player-name filter (two seasons crashed on NA names in the TM players cache).

### Crosswalks built for all 40 new league-seasons

**21,690 / 21,849 matched (99.27%).** Weakest: La Liga 2023/24 (94.6%) and Serie A 2021/22 (95.6%) — the two seasons whose TM caches contain NA player names; their unmatched rows are flagged for later review. The other 38 seasons sit at 98–100%.

### Coach-fit analysis (all five leagues, 2015/16–2024/25)

Composition now lags archetypes **across leagues** — a Serie A → PL transfer arrives with his Serie A archetype instead of falling back. Mean fallback share dropped from 30.4% (PL-only) to **26.2%**; unclassified 2.9%.

Join validation: **1,475 of 1,475 stints matched, game-count agreement r = 1.000** (composition builds 1,485; the extra 10 belong to team-seasons the M5 coverage filter drops).

**Global model — the headline replicates at 5× the data:**

| Specification | LRT | p |
|---|---|---|
| Current-season fallback | χ² = 21.34, df = 11 | **0.030** |
| Strict lagged (sensitivity) | χ² = 30.02, df = 11 | **0.0016** |

Wide-creator share (F3) is again the dominant coefficient in both runs — now **t = 3.19 / 3.30** (up from 2.63/2.45 in the pilot), coefficient +0.75/+0.78 PPG per unit share. The effect size halved vs the PL-only estimate (+10pp of outfield minutes ≈ +2.8 points/season, was ≈ +5), which reads as the pilot overestimating on a small sample — but the direction, ranking, and significance strengthen. Every archetype's coefficient is ≥ 0 relative to the destroyer reference (M1): destroyer-heavy squads underperform their squad value most.

**Per-coach tests:** 149 coaches with ≥4 stints (was 26), 1,605 tests — **still 0 survive BH FDR** (best q = 0.52; more coaches also means a stricter correction, and 4–10 observation correlations stay underpowered). Per-coach findings remain descriptive. Pairs recurring in *both* specifications, with face validity:

- **Gian Piero Gasperini + no-nonsense CBs** (strict r = 0.89, 10 stints) — the aggressive man-marking back-3 profile is exactly his system
- **Patrick Vieira + destroyers** (r = 0.92/0.93)
- **Mauricio Pochettino − pressing forwards** (r = −0.89 both runs)
- **Sergio González + wide creators**, **Rubi − wide creators/− ball-playing CBs**, **Ivan Jurić − advanced creators**, **Oliver Glasner − wide creators**

### Results exported

`cf_save_results()` regenerates `data/results/archetype_fit.rds` (per-coach pairs with recurs-in-strict flags + global summary) for the website pipeline.

---

## Documented Limitations (M6 big-5)

1. **Per-coach tests remain exploratory** even at 149 coaches — within-coach correlations on 4–10 stints cannot clear FDR at 1,605 tests.
2. **Cluster granularity is still an interpretability choice** over silhouette; stability now 0.62–0.92 at the chosen k (much improved from 0.32–0.68).
3. **Fallback endogeneity** now covers 26.2% of classified minutes (2015 remains all-fallback by construction); the strict sensitivity again *strengthens* the global result.
4. **Archetype labels changed meaning from the pilot** (M-group). Anything citing pilot archetype ids must use the new labels; the website needs regeneration.
5. Shotmap 404 hole in 2018/19 (~5–8% of matches outside the PL) slightly undersamples that season's shot-profile features.

---

## Files Modified

- `src/player_archetypes.R` — league-aware features, league×season×group z-scoring, big-5 season table, relabeled archetypes, non-PL face-validity anchors
- `src/coach_fit.R` — league map, cross-league lagged archetypes, playoff filtering, name-drift handling, unmapped/duplicate hard stops, big-5 residual filter
- `src/sofascore_crosswalk.r` — rewritten `ss_crosswalk_team_map()` (token equivalence + greedy one-to-one), NA-name filter, unmapped-team handling
- `src/data/cache/sofascore/archetypes.rds` — 17,219 big-5 assignments
- `src/data/cache/sofascore/crosswalk_*.rds` — 40 new league-seasons
- `data/results/archetype_fit.rds` — big-5 coach-fit results for the site
- `Docs/Summary_of_Findings.md` — Part 6 updated to big-5 results
- `Docs/Plan.md`, `Docs/Milestones.md`, `CLAUDE.md` — M6 status and labels
- `Docs/Session_Log_2026-07-12.md`, `Docs/Progress_Report_2026-07-12.md` — this session

---

## Reproduction

```r
source("source_data.r")
source("coach_fit.R")
run_archetypes()          # rebuilds archetypes.rds on all 5 leagues (~10 min)
res <- cf_run_analysis()  # composition, join, global model, per-coach, sensitivity (~20 min)
cf_save_results(res)      # regenerates data/results/archetype_fit.rds
```

---

## Next Steps

- Regenerate the website (`export_site_data()`) so coach pages show big-5 archetype-fit results and the new labels.
- Optional: 2025/26 pass-coordinate validation (~11k requests/league; scope decision pending).
- Review the flagged unmatched crosswalk rows in La Liga 2023/24 and Serie A 2021/22 (NA player names in the TM cache).
