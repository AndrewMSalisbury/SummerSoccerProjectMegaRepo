# Session Log — 2026-07-09 (Session 2)

## Purpose

Record of decisions made, code changes, results produced, and their meaning. This session built the analytical core of Milestone 6: player archetype features and clustering (`src/player_archetypes.R`), and the coach/player-type fit analysis (`src/coach_fit.R`).

---

## Design Decisions (agreed at session start)

Four forks were settled before implementation:

1. **Clustering unit:** within broad position groups — goalkeepers excluded; D, M, F clustered separately using each player-season's minutes-weighted modal per-match SofaScore position.
2. **New-to-PL players:** current-season fallback — players with no prior PL season get their current-season archetype (strict lagging alone covers only ~68–80% of minutes per season, measured before deciding). Fallback rows are flagged and a strict-lagged sensitivity run quantifies what the fallback changes.
3. **Outcome level:** M5 coach-stint partial residuals; composition computed from per-match minutes under that specific coach.
4. **Test framing:** layered — global mixed model first, then per-coach tests with FDR control, reported descriptively.

Defaults set during implementation: 600-minute threshold for a player-season to receive features; k-means on within-season × position-group z-scores; **no xG features** (xG only exists from mid-2021/22); residuals from the published pooled 14-league M4 model.

---

## Data Conventions Discovered (verified empirically, encoded in comments)

1. **Heatmaps:** 0–100 grid, attack normalized toward x = 100 (Haaland centroid x ≈ 69 vs Van Dijk ≈ 37; fullback wideness ≈ 30+ vs Rodri ≈ 17).
2. **Shot coordinates use the opposite convention:** the goal under attack is at (0, 50) and x measures distance from the goal line (median shot x = 12.8; box edge ≈ 16). The first-draft distance formula assumed the heatmap convention and was sign-flipped — caught by verification before any clustering ran.
3. **`match_stats$team_ss_id` is the player's club at scrape time**, not the match team — SofaScore embeds the player's current club in lineup responses. Only 2.3% of 2015 (event, team) pairs matched the event's home/away ids (13.5% in 2023 — players still at the same club). Match sides are instead derived from `is_home` + the event's home/away ids; `is_home` verified at 99.97% agreement against season-level club (the disagreements are mid-season transfers, which is the point of deriving per match).
4. **Season stat fields are not stable across seasons:** `outfielderBlocks` exists only in 2023/24, `ballRecovery` only from 2023/24. Both excluded from features. All 33 remaining source fields verified present in all ten seasons.
5. **`build_coach_residuals()` duplicates a stint row** when a coach had two tenure brackets in the same team-season (sacked and re-appointed): its `date_from` join multiplies rows. `cf_build_analysis_table()` dedupes, keeping the earliest bracket (4 affected rows).

---

## Archetype Features (`src/player_archetypes.R`, `pa_` prefix)

One row per qualifying player-season (≥600 league minutes, non-GK): **3,476 player-seasons, 38 features.**

- **Heatmap descriptors** (count-weighted): depth centroid, x/y spread, wideness (|y−50|, folded so mirror-image left/right players cluster together), attacking/defensive-third shares, wide-channel share, opposition-box share.
- **Per-90 profiles** from season stats: passing (volume, accuracy, long balls, crosses, final-third, chipped, key passes, big chances created, opposition-half share), carrying (dribbles, dispossessed, possession lost, touches, fouls drawn), defending (tackles, interceptions, clearances, possession won in attacking third, dribbled past, fouls), duels (aerial volume + win %, ground-duel volume reconstructed as total duels − aerial duels).
- **Shot profile** from shot coordinates (penalties excluded): shots/90, mean distance, box share, central share, header share.
- Style, not quality: no goals, assists, ratings, or conversion rates — clusters should be types, not good-vs-bad players.
- NAs (never crossed, never shot) imputed with the season × position-group median; all features z-scored within season × position group, so archetypes are era-comparable across the decade.

---

## Archetype Clustering

k-means (nstart 25, seeded) per position group; k chosen against average silhouette and split-half stability (cluster 2015–19 and 2020–24 separately, cross-assign to the other half's centroids, adjusted Rand index averaged over both directions).

**Diagnostics favored k = 2 everywhere** (silhouette 0.20–0.32; stability 0.76–0.97), but k = 2 clusters are just sub-positions (CB vs fullback, defensive vs attacking midfielder) — Van Dijk and Tarkowski in the same cluster. The finer cut was reviewed with Andrew and **chosen deliberately: D = 4, M = 4, F = 3 (11 archetypes)**, accepting lower stability (D 0.68, M 0.48, F 0.32) as a documented limitation in exchange for football-native styles within roles.

| Id | Label | Example players (by minutes) |
|---|---|---|
| D1 | no-nonsense CB | Tarkowski, Mee, Keane, Dunk |
| D2 | ball-playing CB | Van Dijk, Stones, Alderweireld, Gabriel |
| D3 | defensive fullback | Wan-Bissaka, Ward, Coleman, Lowton |
| D4 | attacking fullback | Alexander-Arnold, Robertson, Trippier, Digne |
| M1 | deep playmaker | Rodri, Xhaka, Højbjerg, Kanté, Neves |
| M2 | destroyer | Ndidi, Souček, Kouyaté, Doucouré |
| M3 | advanced creator | De Bruyne, Eriksen, Maddison, Bruno Fernandes |
| M4 | wide midfielder | Bowen, McNeil, Son, Albrighton |
| F1 | pressing forward | Richarlison, Jota, J. Ayew, Hwang |
| F2 | box striker | Kane, Vardy, Watkins, Calvert-Lewin |
| F3 | wide creator | Salah, Sterling, Firmino, Mané, Zaha |

Assignments cached to `data/cache/sofascore/archetypes.rds` (3,476 rows; archetype counts 162–454, well balanced). Multi-role players move archetypes across seasons as their role changes (e.g. Salah F3 in wide-forward seasons, M2/M4 when listed as midfield) — this is per-season role classification working as intended.

---

## Stint Composition and Join (`src/coach_fit.R`, `cf_` prefix)

- `cf_player_archetypes()`: lagged archetype (most recent prior qualifying PL season), current-season fallback flagged. Sub-600-minute player-seasons inherit a lagged archetype where one exists; otherwise "unclassified".
- `cf_stint_composition()`: SofaScore events → match dates; teams mapped to TM `team_season_id` via `ss_crosswalk_team_map()`; coach per match via the M5 date-bracket rule (`xx_assign_matches_to_coaches()` reused verbatim); minutes-weighted archetype shares per (team_season_id, coach_id) over outfield minutes.
- **301 stints**, shares sum to exactly 1, mean unclassified share 2.6%, mean fallback share 30.4% (2015 is ~100% fallback by construction — it has no prior season).
- Join to M5 partial residuals: **301 of 301 stints matched; SofaScore vs Transfermarkt per-stint game counts agree at r = 1.000.** Spot check: Chelsea 2022/23 attributes Tuchel 6, Potter 22, Saltor 1, Lampard 9 (38 total).

---

## Results

### Global model

`partial_residual_ppg ~ 10 archetype shares (reference: M1 deep playmaker) + fallback_share + (1|coach) + (1|club)`, weighted by stint games, ML fit, LRT against the no-shares null.

**Squad archetype mix predicts stint residuals: χ² = 23.96, df = 11, p = 0.013.** Under the strict-lagged sensitivity (fallback minutes → unclassified) the result *strengthens*: χ² = 29.77, **p = 0.0017** — the finding is not an artifact of the fallback choice.

The signal is concentrated in attacking archetypes. Largest coefficient in both runs: **wide-creator share (F3)** — +1.30 PPG per unit share (t = 2.63; strict run +1.21, t = 2.45). Moving 10 percentage points of outfield minutes from deep playmakers to wide creators associates with ≈ +0.13 PPG ≈ +5 points/season above squad-value expectation. Advanced creators (M3) carry the next-largest coefficient (t = 1.86; strict t = 2.19). Defensive archetype shares are all ≈ 0.

Interpretation (descriptive, two readings consistent with the data): teams built around wide creators genuinely outperform, and/or Transfermarkt market values systematically underprice what wide creators contribute relative to their cost. Either way the residual is not archetype-neutral.

### Per-coach tests

26 coaches with ≥4 PL stints; 280 (coach × archetype) within-coach correlations; **none survive BH FDR** (best q = 0.19) — expected with 4–9 stints per coach. Descriptive findings that recur in both the fallback and strict runs, with face validity:

- **Klopp + pressing forwards** (r = 0.67 / 0.75) — his best residual seasons had more F1 minutes available
- **Guardiola + ball-playing CBs** (strict r = 0.68); **Arteta + ball-playing CBs** (strict r = 0.86)
- **Marco Silva − wide midfielders** (r = −0.92 / −0.87), **Mark Hughes − box strikers** (r = −0.95 / −0.90)
- Benítez appears with extreme correlations in several pairs but at n = 4 stints these are the exploratory tail, not findings

### Convergence note

The default lme4 optimizer emitted a marginal convergence warning (max gradient 0.0046 vs 0.002 tolerance) on the strict variant; switched `cf_global_model()` to bobyqa, which fits cleanly with identical results to reported precision.

---

## Documented Limitations (M6)

1. **Single-league pilot:** PL 2015/16–2024/25 only; 26 coaches reach the ≥4-stint bar. No cross-league portability claim for archetype-fit effects.
2. **Fallback endogeneity:** 30% of classified minutes use current-season archetypes (100% in 2015). The strict sensitivity confirms the global result; per-coach descriptive pairs were only highlighted when they recur in both runs.
3. **Cluster stability:** the chosen fine granularity (11 archetypes) has split-half ARI 0.32–0.68 — boundaries shift somewhat between decade halves. The coarse k = 2 clustering (ARI 0.76–0.97) was rejected as analytically empty.
4. **Per-coach tests are exploratory:** 4–9 stints per coach cannot clear FDR; all per-coach findings are descriptive.
5. **Lagged-archetype survivorship:** archetypes require ≥600 minutes in a prior season, so late-career role changes register with a one-season delay.
6. **No pass-coordinate validation yet:** the 2025/26 `rating-breakdown` check (Plan.md M6 step 5) remains optional/not run.

---

## Files Modified

- `src/player_archetypes.R` — new: feature engineering, clustering, diagnostics, labels, `run_archetypes()`
- `src/coach_fit.R` — new: lagged assignment, stint composition, analysis table, global + per-coach models, `cf_run_analysis()`
- `src/data/cache/sofascore/archetypes.rds` — new cache: 3,476 player-season archetype assignments
- `Docs/Summary_of_Findings.md` — added Part 6, updated limitations and conclusion
- `Docs/Plan.md`, `Docs/Milestones.md` — M6 status updated
- `Docs/Session_Log_2026-07-09b.md`, `Docs/Progress_Report_2026-07-09b.md` — this session

---

## Reproduction

```r
source("source_data.r")
source("coach_fit.R")     # chains through coach_attribution.R -> ... -> tabler.R
run_archetypes()          # rebuilds archetypes.rds (features + clustering)
res <- cf_run_analysis()  # composition, join, global model, per-coach, sensitivity
```

---

## Next Steps

- **Optional:** 2025/26 `rating-breakdown` validation scrape (~11k requests) to check archetypes from cheap features against true pass coordinates.
- **Website** (queued from July 5): coach rankings + images; M6 archetype-fit findings are candidate content.
