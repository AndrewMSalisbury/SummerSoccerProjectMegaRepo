# Session Log — 2026-07-16: Coach Descriptive Profile, Layer A (goals)

## Trigger

Andrew: "Let's begin on the coach descriptive profile as described by the design
doc." Per `Docs/Coach_Descriptive_Profile_Design.md` §7, phase 1 is Layer A
(strength decomposition) on goals — the cheapest and most defensible layer, and
the one the 2026-07-15 log already flagged as next.

## What shipped

`src/coach_strengths.R` (new, `cs_` prefix) — splits the M4/M5 overperformance
residual into an attacking and a defensive half. Analysis only; **nothing is on
the site yet** (design phase 6).

- `cs_compute_head_residuals()` — two head models on the *same* right-hand side
  as `compute_residuals()` (`log(norm_weighted_value)` + league + `is_b_team`),
  with goals-for-per-game and goals-against-per-game as responses. Yields
  `off_resid` (goals scored above value expectation) and `def_resid`
  (value-expected goals conceded − actual, so positive = better).
- `cs_validate_tieback()` — the design's built-in consistency check.
- `cs_build_coach_goal_residuals()` — mirrors `build_coach_residuals()` exactly
  (same coverage filter, same `xx_assign_matches_to_coaches()`, same
  re-appointment dedup, same difference-against-the-season-level-prediction
  logic), aggregating goals instead of points.
- `cs_fit_head_blups()` / `cs_head_stats()` — **reuse** `fit_mixed_model()`,
  `compute_coach_stats()`, and `add_significance()` verbatim by presenting the
  head residual under the column name they expect, so the games weighting, the
  BLUP shrinkage, the weighted mean/SE, and the ≥3-stint FDR rule are the M5
  ones by construction, not by re-implementation.
- `run_coach_strengths(cut)` + `cs_save_results()` — writes
  `coach_strengths_<cut>.rds` (per coach) and `coach_goal_residuals_<cut>.rds`
  (the stint table), for both published cuts.

Two small supporting changes in `coach_attribution.R`:

- `xx_filter_value_coverage()` extracted out of `build_coach_residuals()` (pure
  refactor) so the goal models filter on identical team-seasons.
- `compute_coach_stats()` gained a `label` argument (histogram axis only) so the
  reused printout doesn't claim PPG units for a goals-per-game response.

## Validation

- **Tie-back (design §2.1, expected ~0.8+):** goal-difference edge
  (`off_resid + def_resid`) vs the M4 points residual — **r = 0.862** (top-5),
  **r = 0.872** (14-league); ~0.59 points per goal of edge. Passes.
- **Attribution identity:** the goal stint tables are 2,895 (top-5) and 8,207
  (14-league) rows — *exactly* matching the saved `coach_residuals_*.rds`, which
  confirms the attribution path is the M5 one.
- **Coach-level tie-back:** the goal `edge` correlates **r = 0.823** with the
  published points BLUP across 334 top-5 coaches (`off` 0.646, `def` 0.468).
- **Coach effect is stronger on goals than on points.** 14-league LRT for coach
  variance: offence χ² = 160.2 (p ≈ 1e-36), defence χ² = 60.5 — against χ² =
  28.5 for the points model. Goals-for is a lower-noise coach signal than points.
  (top-5: offence coach var 6.0% of total, defence 4.8%.)
- **lme4 convergence warning is a false positive.** The 14-league offence fit
  warns `max|grad| = 0.0028 (tol = 0.002)`; refitting with bobyqa converges
  cleanly to the same optimum — logLik −1517.085 both ways, variance components
  equal to 5 dp, BLUP correlation 1.0, LRT χ² = 160.215 both ways. Documented in
  the source; **do not** switch optimizers to silence it.

## Face validity (top-5 cut, BLUPs in goals per game)

| Coach | off_blup | def_blup | tilt | edge |
|---|---|---|---|---|
| Pep Guardiola | +0.249 | +0.082 | +0.167 | +0.331 |
| Alex Ferguson | +0.187 | +0.063 | +0.123 | +0.250 |
| Luis Enrique | +0.240 | −0.027 | +0.267 | +0.213 |
| Jürgen Klopp | +0.119 | +0.052 | +0.067 | +0.171 |
| Tony Pulis | −0.058 | +0.093 | −0.151 | +0.035 |
| Diego Simeone | −0.111 | +0.086 | −0.197 | −0.025 |
| Marcelo Bielsa | +0.011 | −0.074 | +0.084 | −0.063 |

The tilt extremes at ≥200 games are De Zerbi / Luis Enrique / Genesio (attacking)
and Alguacil / Baup / Fernandez / Simeone (defensive); Pulis and Bordalás sit at
the top of the raw defence BLUP. Team-season heads are equally recognisable —
Verona 2013, Atalanta 2019, Real Madrid 2011, Liverpool 2013 lead the attacking
residual; Getafe, Reims, St. Pauli, Ingolstadt lead the defensive one.

Worth noting for the eventual write-up: **Simeone's points overperformance is not
a goals overperformance** (edge ≈ −0.02) — his edge is in converting goal
difference to points, which the tilt describes but does not explain.

## Part 2 — the xG cut (design phase 2)

Splits the goals cut again into **process** and **outcome**, four per-game
measures (positive = better): `creation` (xG-for above value expectation),
`prevention` (value-expected xG-against − actual), `finishing` (goals-for −
xG-for) and `shotstop` (xG-against − goals-against). Creation and prevention get
head models — they are measured against what the squad's value predicts;
finishing and shot-stopping do not, being within-team differences between what
happened and what the chances were worth.

`run_coach_xg_strengths()` writes `coach_xg_strengths.rds` (209 coaches) and
`coach_xg_residuals.rds` (452 stints). No cut suffix — the xG data is big-5 only,
so this layer has a single population.

### Coverage, verified rather than inherited

- The design says xG is "present but partial mid-2021/22". Measured: **2022–2024
  are 99–100% covered; 2021 is ~40%**; 0% before. **2021 is excluded** — partial
  coverage would understate team xG on a non-random subset of matches. So the
  window is 3 seasons, 15 league-seasons, 5,330 events.
- **A defect worth recording: 27 of those 5,330 events (0.5%, all in 2023, every
  league affected) carry a full ~21 shots but are missing their goal shots
  entirely.** In those matches xG loses exactly the chances that scored while the
  scoreline keeps the goals — understating creation and inflating finishing. The
  coverage rule is therefore stricter than "has xG": **an event counts only if its
  shotmap reconciles with the scoreline on both sides.** 5,303 events survive.
  Note a reconciliation check that conditions on events *having* goal shots
  reports a clean bill of health and misses this — the first version of my check
  did exactly that.
- **Own goals** (436, 2.9% of goals) are recorded in the shotmap credited to the
  *benefiting* side but named for the defender who scored, with no xG and
  coordinates on the goal line. Aggregating by `is_home` is therefore right at
  team level, and own goals land wholly in finishing — where they belong.

### Validation

- **Cross-source tie-back (new, and the strongest check here):** the xG cut is
  built from SofaScore, the goals cut from Transfermarkt. `creation + finishing`
  vs the goals cut's `off_resid` → **r = 0.949**; `prevention + shotstop` vs
  `def_resid` → **r = 0.981**, over all 452 stints. Two independently-sourced
  pipelines agree, which is what would collapse first if the SofaScore→TM team
  map or the coach attribution were wrong.
- **Repeatability — the design's process/outcome premise, tested not asserted.**
  Same club, consecutive seasons (165 pairs):

  | measure | lag-1 r | p |
  |---|---|---|
  | creation | **0.423** | 1.5e-08 |
  | prevention | 0.271 | 4.2e-04 |
  | finishing | 0.242 | 1.7e-03 |
  | shotstop | **−0.005** | 0.95 |

  Creation is the most repeatable and shot-stopping is pure noise, exactly as the
  design predicts. But **finishing persists more than the design assumes**
  (r = 0.24, not ~0). The likely reason is squad continuity rather than coach
  skill — clubs keep their finishers — which is a reason to keep labelling
  finishing as an unreliable *coach* signal, not a reason to promote it.
- Squad value predicts chance creation better than it predicts goals (xG-for
  R² = 0.719 vs goals-for R² = 0.641; against: 0.579 vs 0.505) — consistent with
  goals being chances plus noise.
- `creation` vs `finishing` correlate −0.017 across coaches: the two axes carry
  independent information, which is the point of the split.

### Sample-size honesty

Three seasons is a hard ceiling: 264 coaches, 209 with ≥10 games, 117 with ≥38,
**57 with ≥3 stints and none with ≥5**. **Zero coaches are FDR-significant on any
of the four measures.** Console previews apply a ≥38-game display bar, or the
"top 10" would be a list of caretakers. This layer is a recent-form lens and must
never be shown as a career verdict.

### Face validity

Top creation (≥38 games): Klopp (+0.46), Arne Slot, Hansi Flick, Giráldez,
Tuchel, Eddie Howe, De Zerbi. Bottom: Imanol Alguacil (−0.39), Rubén Baraja,
Vieira, Potter. It coheres with phase 1 independently — Alguacil had the most
negative offence BLUP in the goals cut and is bottom on creation here; De Zerbi
and Klopp are attacking in both. Klopp's edge is creation with finishing ≈ 0
(process, not luck); Flick's Barcelona pairs high creation with high finishing.

## Part 3 — the style fingerprint (design phase 3, Layer B)

`src/coach_style.R` (new, `sy_` prefix): the M6 archetype recipe pointed at *team
style*. per-player-per-match → team-match → z-score within league × season →
coach-stint mean → games-weighted coach profile. Writes `coach_style.rds`
(`$profiles` 337 coaches, `$stints` 1,485, `$axes`, `$meta`) from **36,018
team-matches** across all 50 big-5 league-seasons, 2015/16–2024/25. Honesty label:
**descriptive-clean** — literally what the team did, no causal content — but it is
the *team's* style, co-produced with the squad (§5).

**Nine axes**, each an equal-weight mean of its members' z-scores (not a PCA, not
a fitted weighting — nothing is trained against an outcome, so there is nothing
to overfit and the axes stay readable): possession, pressing intensity,
directness, width, shot volume, chance quality, defensive solidity, set-piece
reliance, lineup stability. No axis pair exceeds |r| = 0.8 (highest: possession ↔
shot volume 0.77, directness ↔ width 0.70), so they carry distinct information.
Feature completeness ≥ 99% except XI stability (97.3%: first match of each
season has no predecessor) and the shot-derived axes (99.1%: the known 2018/19
shotmap hole).

### Field availability — the docs are easy to misread, both ways

- **CLAUDE.md's "`outfielderBlocks`/`ballRecovery` only from 2023/24" is true of
  the SEASON cache only.** In `match_stats`, `ballRecovery` is populated in all 50
  league-seasons (PL 2015 mean 5.0 per player-match), so the design's inherited
  "do not use" does not bind this layer, which reads `match_stats`. It's used.
- **The trap runs the other way:** `possessionWonAttThird` — the design's
  pressing-*height* input — is **absent from `match_stats` entirely**. Height is
  season-level, so it cannot be split between two coaches of one team-season.
- `match_stats$team_ss_id` matches the real match side only **41.5%** of the time
  (the caveat is real and severe); `substitute == FALSE` gives the XI exactly.
- Counting conventions drift over the decade (ballRecovery 5.0 → 3.8,
  interceptions 2.2 → 1.5). Z-scoring within league × season absorbs it — which is
  precisely why the design insists on it.

### Pressing is two traits, not one (the main finding)

Andrew chose to ship both: per-match **intensity** (a PPDA proxy, stint-safe) and
season-level **height** (`possessionWonAttThird`, flagged `height_blended`). The
data says that was the right call — they correlate only **r = 0.38** and are
genuinely different traits:

- **Intensity** (how hard you contest per opponent pass): Gasperini +0.59, Hütter,
  Tudor, Bosz, Iraola, Mendilibar, Klopp. A good pressing list.
- **Height** (where you win it): Mendilibar +1.7, Guardiola +1.5, Berizzo, Xavi,
  Klopp, Tuchel. Bottom: Aguirre, Nuno Espírito Santo, Nicola — textbook deep
  blocks.

**Guardiola is ~0 on intensity and +1.5 on height, and that is correct** — City
make few defensive actions because opponents seldom hold the ball, yet win it
high. The design's "Guardiola high on pressing" (§3.3) resolves to *height*.
Caveat to carry: **58% of stints sit in a multi-coach team-season**, and 128 of
337 profiles are >half blended — for those, height is substantially the club's
number, not the coach's.

### Face validity — and a caricature corrected

Strong everywhere: possession (Luis Enrique, Guardiola, Xavi, Tuchel top;
Allardyce bottom), directness (Bordalás, Dyche, Mendilibar top; Favre, Setién,
Sarri bottom), solidity (Allegri, Guardiola, Tuchel, Arteta), **set-piece reliance
(Thomas Frank — Brentford's known specialism — then Dyche)**, lineup stability
(Dyche stable; Tuchel, Italiano, Allegri, Luis Enrique rotate).

**The design's Simeone prediction ("low possession + high solidity + low line")
holds on one of three.** He is +0.13 SD on possession (64th pct) and *average* on
pressing height (53rd pct). What is supported is solidity — **92nd pct** — plus
narrowness (16th pct width) and shot selection (83rd pct chance quality). His
signature in the data is solidity + narrow + good chances, not a low-possession
low block.

### Display note for phase 6

Axis units are SDs of *team-matches*, so coach means compress hard toward zero
(Simeone's 92nd-pct solidity is only +0.28 SD). A radar must map to **percentile
among coaches**, not raw SD, or every fingerprint will look flat.

## Part 4 — coach vs squad (design phase 4, §5)

`run_coach_vs_squad()` in `coach_style.R` → `coach_style_vs_squad.rds`. The design
treats §5 as a caveat to bolt on. **It turned out to be the main result of Layer
B**, and it changes what the site is allowed to say.

Four checks: (1) does the fingerprint **travel** — same coach, 1st vs 2nd club
(144 coaches); (2) its complement, does the club **keep** it — same club, 1st vs
2nd coach (129 clubs); (3) a **variance decomposition** per axis, `axis ~
(1|coach) + (1|club)`, games-weighted like M5; (4) style **residualized on the
squad's M6 archetype mix**, then 1–2 re-run on the residuals.

### Team style is mostly the club's, not the coach's

| axis | coach var % | club var % | r travels | r persists | R² from archetype mix |
|---|---|---|---|---|---|
| possession | 11.6 | **69.2** | 0.55 | 0.82 | **0.69** |
| pressing | **30.9** | 23.6 | 0.34 | 0.47 | 0.12 |
| directness | 24.8 | **52.1** | 0.52 | 0.71 | 0.51 |
| width | 29.8 | 34.6 | 0.44 | 0.50 | 0.39 |
| shot volume | 11.3 | **54.4** | 0.43 | 0.67 | 0.54 |
| chance quality | 13.8 | 27.6 | 0.29 | 0.36 | 0.11 |
| defensive solidity | 11.0 | **45.0** | 0.29 | 0.58 | 0.31 |
| set-piece reliance | 12.9 | 24.7 | 0.25 | 0.29 | 0.22 |
| lineup stability | **19.2** | 14.6 | **0.33** | 0.17 | 0.10 |

Club variance beats coach variance on **7 of 9 axes**. The squad's archetype mix
*alone* explains 69% of possession, 54% of shot volume, 51% of directness. A club
under two *different* coaches (possession r = 0.82) looks far more alike than a
coach at two *different* clubs (r = 0.55). After residualizing on the mix, the
travel correlations collapse — possession 0.55 → 0.17, shot volume 0.43 → 0.09.

**Consequence for phase 6: a radar must be labelled as the style of the teams this
coach ran, never "his style".**

### Two axes survive as genuinely the coach's

- **Lineup stability.** The only axis where coach variance beats club (19.2 vs
  14.6), the only one that travels better than it persists (0.33 vs 0.17), only
  10% personnel-explained, and it still travels after residualizing (0.25 vs
  0.11). Rotation is a decision, not a squad property. **The design's hunch that
  this is "a real coach signature nobody visualizes" is confirmed** — and it is
  now the best-evidenced thing in Layer B.
- **Pressing intensity.** Best tactical axis: highest coach share (30.9%, above
  club's 23.6%), 12% personnel-explained, and the only tactical axis still
  standing after residualization (0.34 vs 0.33). Note this is the axis Part 3
  nearly discarded for "failing" the Guardiola check.

### Method caveat (stated because it cuts against the headline)

The travel/persist pair is **not** a like-for-like ownership contest: consecutive
coaches at one club inherit nearly the same squad, whereas a coach's two clubs
have entirely different squads. So `r_club > r_coach` is expected under *any*
model where the squad matters, and does not by itself prove the coach is
irrelevant. The variance decomposition — which estimates both effects at once — is
the better instrument, and it agrees on 7 of 9 axes, which is why the conclusion
stands. Neither check is causal: coaches are hired by clubs that already suit them
(inflating travel), and the archetype mix is partly one the coach shaped (so the
residual strips out some of his own signature). Both are bounds, not an identified
split — as §5 says.

## Part 5 — style → quality (design phase 5, Layer C)

`src/coach_style.R`, `run_style_quality("top5")` → `coach_style_quality_top5.rds`.
The M5 quality BLUP regressed on the nine Layer B axes + `cr_rigidity`, across the
**231 coaches** with both a top-5 BLUP and a fingerprint (173 of them graded),
games-weighted. Families were pre-specified from phase 4 rather than chosen from
the data: *primary* = lineup stability, pressing, rigidity (the coach-owned ones);
*secondary* = the other seven (mostly club property). BH FDR within each family.

### The result is a null — and it took four checks to earn it

Every raw association is large and significant: defensive solidity **+0.64**,
shot volume +0.53, possession +0.52, chance quality +0.46, lineup stability
−0.37, rigidity +0.25 (standardized, games-weighted). Taken at face value this
is a rich "what makes coaches good" story. **All of it is artifact.**

| check | question | casualties |
|---|---|---|
| consistency across 4 specs | same sign + significant in raw / squad-residualized / club-controlled / graded-only? | pressing, directness, width, set-piece reliance |
| separable from club level | can the axis be told apart from club size at all? | possession (**r = 0.86** with club value pct), shot volume (0.81), defensive solidity (0.74) |
| restates the outcome | is the axis built from what the BLUP measures? | chance quality (+ solidity, shot volume again) |
| within vs between coach | does the *same* coach do better when he does more of it? | **lineup stability — sign reverses** |

**Nothing survives.** Rigidity alone is unkilled (+0.155 club-controlled,
q = 0.043), and only because it is a career constant with no within-coach
variation — the decisive check cannot run on it. The summary records that as
`"between-coach only; untestable"`; absence of a failed check is not a passed
check, and the code was changed so `robust` requires the check to have *run*.

### Three traps worth not re-walking

- **The all-axes multivariable is a suppression trap.** It reports `club_pct`
  β = **−0.60** (p = 0.0001), which reads as "big clubs underperform their value".
  The bivariate is r = **+0.39** — the opposite. With possession at r = 0.86 with
  club size and 0.89 with shot volume, the partials are collinearity artifacts.
  The tell that generalizes: possession's coefficient *rises* under a club control
  (0.517 → 0.568), which no genuine confound removal does. One axis + one control
  is the only interpretable spec; the multivariable is kept in the object marked
  "RECORD ONLY, NOT INTERPRETABLE".
- **Lineup stability is a Simpson's paradox**, and it is the phase 4 "coach-owned"
  axis, so it was the one most likely to be believed. Between coaches, rotators
  grade higher (−0.373, q < 0.0001, holds in all four specs). Within a coach,
  *stability* associates with better seasons (**+0.131, p < 0.0001**); within a
  club, +0.110. The between-coach version is club sorting — the heaviest rotators
  are Heynckes, Tuchel, Allegri, Luis Enrique, all at top clubs with European
  fixture loads — and it falls to p = 0.25 once club level is controlled at stint
  level with matched levelling. (Controlling a between-coach term with a per-stint
  covariate mixes levels and mis-estimates it; both the axis and the control are
  split into coach mean + deviation.)
- **Several "style" axes are performance restated.** Defensive solidity is built
  from shots conceded, which is a step on the path to conceding goals and dropping
  points; it correlates 0.30 with the stint's own points residual. "Solid teams
  overperform" is a restatement, not a discovery.

### The confound the layer runs aground on

`r(club_pct, blup) = **+0.39**`: coaches at bigger clubs grade higher. Whether
that is better coaches being hired by bigger clubs, or the value model
under-predicting big clubs, **the BLUP cannot say** — and since the style axes are
near-proxies for club size, every style association inherits that ambiguity.

This is the **third independent attempt to find something beyond the quality
BLUP** — after the M6 archetype-fit result (LRT p = 0.449) and the recommender's
payoff validation (only quality validated) — and the third to come back empty.
That consistency is worth more in the writeup than any of the correlations would
have been.

## Refactor

`cr_season_match_coaches()` moved from `coach_recommender.R` to `coach_fit.R` as
`cf_season_match_coaches()` — it is the SofaScore↔TM↔coach join spine, its
sibling `cf_season_match_minutes()` already lives there, and this lets
`coach_strengths.R` and `coach_style.R` (both *lower* layers) share it instead of
depending upward on the recommender. One call site updated. Verified: the
recommender's formation join returns the identical 760 rows / 18 formations for
PL 2023.

## Reproducing

```r
# working dir src/
source("source_data.r"); source("coach_strengths.R")
run_coach_strengths("top5")      # ~2 min; writes coach_strengths_top5.rds
run_coach_strengths("14league")  # ~5 min
run_coach_xg_strengths()         # ~4 min; phase 2 (needs the top5 goals cut
                                 #   saved first, for the cross-source tie-back)

source("coach_style.R"); run_coach_style()   # ~12 min; phase 3 (Layer B).
# Pass team_matches = <cached> to skip the slow rebuild when iterating on axes.

run_coach_vs_squad()             # phase 4; reads coach_style.rds. Slow only
                                 #   because cf_stint_composition() rebuilds
                                 #   per-match minutes — pass composition = <cached>.

run_style_quality("top5")        # phase 5 (Layer C). Rebuilds coach formations
                                 #   for rigidity (~5 min) + cf_stint_composition();
                                 #   pass d = sy_style_quality_data(...) to iterate.
```

Re-run after any M4/M5 refit — the head models depend on the same dataset build.

## Loose ends / next

- **Not committed** — working tree carries this plus the still-uncommitted
  2026-07-14/15 work (player images, squad-fit drawer, coach formations).
- **Phase 6 (site):** nothing from any phase is on coach pages yet. Constraints
  now known: label the radar as *the teams' style under this coach*, not his;
  map axes to percentile among coaches, not raw SD, or every fingerprint looks
  flat; **no Layer C block at all** (phase 5 is a null — the writeup gets the
  null and the reason, and the raw correlations must not be shown as findings);
  and note that phase 5 removed the last reason to *lead* with lineup stability
  — it is the coach's own trait (phase 4) but says nothing about quality, so
  present it as description only. Layer A's offence/defence tilt remains the most
  defensible single line.
- **The writeup part of phase 5 is still unwritten.** The design's phase table
  scopes "writeup part" into phase 5; only the design doc + this log carry the
  result so far. `Docs/Summary_of_Findings.md` needs the null, framed as the
  third strike alongside the M6 fit LRT (p = 0.449) and the payoff validation.
- **Worth a look someday:** `r(club_pct, blup) = +0.39` is a fact about the M5
  BLUP itself, not about style — big-club coaches grade higher. Benign if better
  coaches are hired by better clubs; a mis-specification if the value model
  under-predicts big clubs. The published ranking rests on which it is, and
  nothing in this session tested it.
- **Design doc §0 label:** the goals cut is *defensible*; the xG cut inherits
  that but adds a hard coverage caveat (3 recent big-5 seasons, nobody
  significant), so it is a lens, not a verdict. The coach-vs-squad caveat (§5)
  still applies to any style claim built on top.
