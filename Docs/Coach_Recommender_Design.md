# Coach Recommender — Design

**Goal:** Given a team and its current squad, rank candidate coaches by how well they
would be expected to perform *at that club* — combining coach quality (M5), coach ×
squad-composition fit (M6), and a new formation-based deployed-value forecast.

Status: design agreed 2026-07-13; **implemented same day** (`src/coach_recommender.R`,
session log `Docs/Session_Log_2026-07-13.md`). Deviations and gate outcomes, recorded
per the pre-registration discipline:

- **Fit axes revised once pre-fit (§3.1's allowance):** the planned destroyer and
  build-up axes correlated at −0.868 and merged into one bipolar "spine" axis.
  Final axes: A1 creators, A2 spine, A3 wing-back (max |r| = 0.47).
- **Payoff framing fixed before results:** primary framing uses the pre-hire
  information set (raw squad value + deployable forecast); the §7.3 realized-value
  framing ran as the sensitivity. Decided and logged before any fold was scored.
- **Gate outcomes:** mechanical validation PASSED (fit → minutes t = 26.9, 316/316
  arrival stints positive); random-slope LRT NOT significant (χ² = 2.65, p = 0.449 —
  the failure §3.2 allowed); payoff verdict per §7.3's acceptance rule: **quality
  ships (p = 0.052 pre-hire / 0.016 realized), fit + deployment exploratory-only**
  (−0.0003, a wash). The site implements the §7.3 fallback presentation.
- δ = 0.3 (interior minimum); formation families as planned (2×2); nationality
  scrape implemented and running (resumable; priority-ordered to ranked coaches).

---

## 1. Motivation and the core decomposition

The M5 rankings answer "who is the best coach?" — one answer for every club. A hiring
club's real question is conditional: "who is the best coach *for us*?" Two coaches with
the same BLUP can differ for a specific squad in two distinct ways:

1. **Fit (residual factor):** the M6 result shows performance above squad-value
   expectation depends on the archetype mix a coach has available. Some coaches extract
   more from particular player types.
2. **Deployment (value factor):** the M4/M5 residual conditions on *minutes-weighted*
   value — the value that actually played. A coach who benches an expensive player is
   not punished by the residual (the model just lowers its expectation to match the
   weaker XI). Value wastage is invisible to the residual **by construction**, but it
   directly costs the hiring team points.

The recommender therefore predicts *points*, not residual, decomposed as:

```
predicted PPG(coach C, team T)
  = f( weighted value C would deploy at T )     ← formation/deployment factor  (§4)
  + quality BLUP of C                            ← M5                            (§2)
  + Σ_axes  axis_share(T) × (global β + C's shrunken slope)   ← archetype fit   (§3)
```

where `f` is the published M3 `enhanced_fixed` model. Recommendations are shown as
**uplift vs. a league-average coach** (ΔPPG and Δpoints/season), with intervals.

### Settled design decisions (2026-07-13)

| Decision | Choice |
|---|---|
| Candidate pool | **All 2,341 coaches, degrading gracefully** — coaches without SofaScore-era big-5 stints get quality-only scores, clearly labeled (like the site's two grading curves) |
| Formation prior | **Recent-weighted** (exponential decay; decay rate chosen empirically, §4.1) |
| Fit-interaction axes | **Theory-driven composites** fixed before fitting (§3.1) |
| Scope | **Full:** model-based ranker + similarity layer + website integration **on each team page** (no separate page) |
| Plausibility | **Career-history filters + badges** (league / country / big-5 / club level / recency) — a lens on the ranking, never mixed into the score (§6) |

### The statistical trap this design is built around

Per-coach × archetype effects are exactly the part of M6 that never cleared FDR
(0/1,605 tests; 4–10 stints per coach). Nothing in this system may rank coaches on raw
per-coach correlations. Every coach-specific fit quantity is a **shrunken random
effect**: coaches with little or inconsistent data revert to the global effect, and the
system degrades to "hire the best coach by BLUP" when it knows nothing about fit. The
formation layer partially escapes this trap because a formation distribution is
estimated from hundreds of matches per coach, not from stint counts.

---

## 2. Component: coach quality (exists)

The M5 BLUPs, both cuts (top-5 / 14-league), from `coach_attribution.R`. Used as-is.
The recommender uses the same cut precedence as the site: top-5 BLUP where available,
14-league otherwise, always labeled.

---

## 3. Component: archetype fit with shrinkage

### 3.1 Composite axes

The full `(1 + 11 shares | coach)` random-slope model cannot be estimated from 1,475
stints / 149 coaches. Shares are collapsed to **four theory-driven axes**, each a stated
hypothesis (big-5 archetype labels):

| Axis | Definition | Hypothesis it encodes |
|---|---|---|
| A1 creator share | F3 wide creator + M4 advanced creator | the globally strongest coefficients; do some coaches amplify/waste creators? |
| A2 destroyer share | M1 destroyer + D1 no-nonsense CB | globally the worst value-for-money mix; some systems (man-marking, low block) monetize it |
| A3 build-up share | D2 ball-playing CB + M2 deep playmaker | possession systems need ball-players (Guardiola/Arteta pilot pairs) |
| A4 back-3 share | M3 wing-back | proxy for back-3 suitability; pairs with the formation layer |

Before fitting: check the axes' correlation structure (shares are compositional — they
sum to 1 with the remaining archetypes, so collinearity must be measured, not assumed
away). Axes may be revised **once** at this stage, before any model sees residuals;
revisions are documented.

### 3.2 Model

Extend `cf_global_model()`:

```
partial_residual_ppg ~ archetype shares (11, fixed, as in M6)
                     + (1 | club)
                     + (1 + A1 + A2 + A3 + A4 || coach)     # uncorrelated slopes
```

weighted by stint games, ML fit, bobyqa. The `||` (diagonal covariance) keeps the
parameter count feasible; if convergence still fails, drop axes in reverse order of
global signal (A4 first). A coach's fit contribution for team T is
`Σ_a axis_share_a(T) × slope_BLUP_a(C)` — zero by construction for coaches with no
SofaScore-era stints.

An LRT of the random slopes against the intercept-only model is reported: it is the
confirmatory test of "does coach-specific fit exist at all?" and is allowed to fail
(§7.3).

### 3.3 Target-team composition

A team's shares use **lagged archetypes** (most recent prior qualifying season, cross-
league), exactly as in M6 — the squad's types as they arrive, before the new coach's
system can contaminate them. For the site (§9), composition comes from the latest
available season's squad; minutes weights are that season's realized league minutes.

---

## 4. Component: formation deployed-value forecast

### 4.1 Coach formation profiles

From the `formations_<sid>.rds` caches (per team-match formation strings, big-5
2015/16–2024/25), matched to coaches via the M5 date-bracket attribution:

- Formation strings are grouped into **families** (exact grouping fixed in Phase 0
  after seeing base rates; expected families: back-4 one-striker, back-4 two-striker,
  back-3/five, and splits within those if volumes support it).
- Each coach gets a family distribution with **exponential recency weighting**
  `w = δ^(years ago)`. δ is chosen out-of-sample: the δ that best predicts each coach's
  observed formation mix at his *next* club, evaluated across all historical coach
  moves in the dataset. (Uniform career-wide weighting is the δ = 1 special case, so
  the data can tell us Andrew's chosen option was wrong only by selecting δ ≈ 1.)

### 4.2 Rigidity

Some coaches impose their shape anywhere; others adapt to the squad. Treating an
adaptive coach's history as a constraint would wrongly penalize him. Per coach:

- **Entropy** of the recency-weighted family distribution.
- **Cross-club persistence:** similarity of family distributions across his clubs.

These combine into a rigidity weight `r ∈ [0, 1]` (exact functional form fixed in
Phase 1). The deployed-value forecast interpolates:

```
deployable(C, T) = r × Σ_f p(f | C) × bestXI_value(T, f)
                 + (1 − r) × max_f bestXI_value(T, f)
```

A rigid coach is scored against *his* shapes; a flexible coach is assumed to find the
squad's best shape. Rigidity is also a publishable coach statistic in its own right.

### 4.3 Slot eligibility matrix

`bestXI_value(T, f)` requires knowing which players can fill which formation slots.
Neither TM positions (one primary position) nor SofaScore match positions (coarse
letters) are granular enough alone; **archetypes are the bridge**:

- Slot taxonomy per family, e.g.: GK, CB, FB/WB, central-mid, attacking-mid/wide-mid,
  wide-fwd, striker (exact slots per family fixed with the family definitions).
- Archetype → slot map with **soft penalties**, not binary eligibility (elite players
  convert roles: a box striker can usually play the lone 9; a wide creator can play
  attacking-mid at a discount). Penalized value = value × eligibility factor.
- Players without an archetype (new to big-5, youth, sub-600-minute) fall back to a TM
  position → slot map at a small additional discount. GKs (excluded from archetypes)
  transfer their value identically across all families.
- `bestXI_value(T, f)` is a max-value assignment of squad players to the 11 slots
  (small assignment problem; greedy with swaps or `lpSolve`).

The matrix must pass the **mechanical validation** (§7.2) before the layer is used.

### 4.4 Into the points prediction

`deployable(C, T)` is converted to the same scale the M3 model expects (normalized by
league-season mean squad value, logged) and run through `enhanced_fixed` to produce
the value factor of predicted PPG. Values are taken at start of tenure (lagged, the
same endogeneity guard as everywhere else — current market values already encode the
current coach's deployment choices).

---

## 5. Component: similarity recommender (descriptive layer)

Model-free complement, immune to the overfitting trap and useful for the ~2,200
coaches whose fit slopes shrink to zero or don't exist:

- Each coach is described by the minutes-weighted archetype compositions of his
  historical stints, **weighted toward overperforming stints** (softmax over stint
  residuals; weighting choice documented).
- For a target team: cosine similarity between the team's current composition and each
  coach's profile → "coaches who have thrived with squads like this one."
- Explicitly labeled descriptive; makes no causal claim; shown alongside, never mixed
  into, the model score.

---

## 6. Component: plausibility profile and filters

Whether a coach *would plausibly take* (or be offered) the job is a separate dimension
from how he would perform. This layer computes descriptive **career facts** per coach
from existing caches (`coaches.rds`, teams, leagues, squad values — no new scraping)
and exposes them as **filters and badges on the ranking, never as terms in the score**.
The performance prediction stays pure; plausibility is a lens on which rows you look at.
This deliberately narrows the earlier "availability is out of scope" stance: career-
history plausibility is in scope; wages, contracts, and personal willingness stay out.

### 6.1 Career facts per coach

| Fact | Definition |
|---|---|
| Leagues coached | distinct leagues across stints, with games and last-seen season per league |
| Countries coached | via a league → country map (England counts PL *and* Championship; Spain La Liga *and* LaLiga 2) |
| Big-5 proven | any stint in the 5 major leagues, with games count |
| Club level | games-weighted percentile of the clubs he has coached, where a club-season's level is its squad-value percentile among all clubs across the 14 leagues that season; recent-weighted with the same δ machinery as §4.1 |
| Recency | last season observed in the dataset; "active" = coached within the last k seasons (default 2) |

"Club level" makes both directions of the level filter natural: a top-decile club
(Real Madrid) can restrict to coaches who have operated at top-decile clubs, and a
promoted club can hide coaches far above its realistic reach.

### 6.2 Filters (team page, §9)

Toggleable chips, combinable, applied client-side to the precomputed ranking:

- **Has coached in this league**
- **Has coached in this country**
- **Big-5 proven**
- **Similar level** — coach club-level within a band of the target club's level
  (default ±20 percentile points; threshold exposed in the export so it can be tuned
  without refitting anything)
- **Recently active**

Default view: **unfiltered, with badges visible on every row** — filters narrow, they
never silently hide information.

### 6.3 Notes and gaps

- These measure *career history*, not actual availability — a coach under contract
  elsewhere still appears (the site keeps its wink about Guardiola to Getafe).
- **Coach nationality is a real plausibility factor we do not currently have** —
  domestic coaches are likelier hires, especially outside the big 5. TM profile pages
  carry it and the scrape is small (~3,500 unique coach pages ≈ 2h at the standard
  2s pacing, same pages the image scraper already visited). Optional extension;
  go/no-go decided at Phase 0.

---

## 7. Validation plan (pre-registered)

Decided **before** any payoff results are seen. The order matters: each stage gates
the next.

### 7.1 Phase 0 sizing checks (cheap, first)

- **Formation base rates:** % of big-5 matches by formation family per league-season.
  If (say) two-striker shapes are <10% of matches, the formation layer mostly flags
  awkward squads rather than discriminating between candidates — it stays in the
  design but expectations (and write-up framing) are set accordingly.
- **Axis collinearity:** correlation matrix of the four composite axes across stints.

### 7.2 Mechanical validation (formation layer)

At historical coach changes: does the eligibility matrix + assignment predict what
actually happened — did inherited high-value players who fit the incoming coach's
shapes keep their minutes, and poor fits lose them? Test: predicted minutes-retention
rank vs. realized within squad. This should be *strongly* true; if it isn't, the
eligibility matrix is broken at the root and the formation layer is not used until it
passes.

### 7.3 Payoff validation (the make-or-break)

Held-out historical appointments — the dataset's real coach-team pairings are the test
set. Leave-one-season-out over 2016/17–2024/25 (2015/16 has no lag year): for every
*new* coach-team pairing in the held-out season, predict stint PPG, scoring four
nested models:

| Model | Contents |
|---|---|
| B0 | squad value only (`enhanced_fixed`) |
| B1 | + coach quality BLUP (the Part-4 augmented model, now on the expanded data) |
| B2 | + global archetype effects (no coach slopes) |
| B3 | + coach fit slopes + formation deployed-value factor (the full recommender) |

Paired RMSE tests between adjacent tiers, as in Part 4. **Acceptance rule, fixed now:**
a layer ships in the headline score only if it does not hurt out-of-sample RMSE. If
B3 ≤ B2 improvement fails, the site ships B2-based rankings and the fit/formation
layers are shown as clearly-labeled exploratory panels — that outcome is a legitimate
published finding, not a failure of the project.

*Side benefit:* B1 vs B0 on the expanded 14-league data closes the standing limitation
that Part 4's augmented model was only ever run on the original 5-league dataset.

### 7.4 Face validity

Spot-check recommendations for well-understood squads (e.g., does a wing-back-heavy
Atalanta-like squad surface back-3 coaches; does a creator-rich squad prefer coaches
with positive creator slopes). Surprises are investigated, not deleted.

---

## 8. Scoring output and uncertainty

Per (coach, team): predicted ΔPPG vs. a league-average coach, decomposed into the
three visible parts (quality / fit / deployment) so the site can explain *why* a coach
ranks where he does. Intervals from the mixed model's conditional variances (BLUP and
slope posteriors) plus the M3 model's prediction variance; the honest version of this
product shows how little separates ranks 3–20.

**Tier labels** (mirroring the site's cut labels):

- **Full model** — coach has SofaScore-era big-5 stints: quality + fit + formation.
- **Quality only** — everyone else: BLUP (cut-labeled) + global archetype effects.
  Note that quality-only ranking is *the same for every team*; the site presents these
  as "strongest available coaches" rather than pretending they are team-specific.

Career-history plausibility (has he coached at this league / country / level) is
handled by the filter layer (§6), which constrains *which rows are shown*, never the
score itself. Still out of scope, stated on the site with a wink: wages, contract
status, willingness of Guardiola to move to Getafe.

---

## 9. Website integration — on each team page

No separate recommender page. Each **team page** gains a "Suggested coaches" section:

- **Top-N table (model-based):** coach, predicted uplift (Δpoints/season) with
  interval, tier label, and the quality/fit/deployment decomposition as a small
  stacked/dot element. Current coach shown in context ("your current coach ranks #k
  for this squad").
- **Plausibility filter chips + badges (§6):** this-league / this-country / big-5
  proven / similar level / recently active. Badges always visible; chips narrow the
  list client-side against per-coach career facts shipped in the export. Default:
  unfiltered.
- **Similarity strip:** "coaches who've thrived with squads like this" (§5), visually
  separated from the model table.
- **Coverage rule:** team-specific scores need the team's archetype composition, which
  exists only for **big-5 clubs with a 2024/25 (latest) season**. Non-big-5 team pages
  get a short note and the quality-only leaderboard link instead of a fake
  team-specific list.
- Export via `site_export.R` (`se_` conventions, `I()` for length-1 arrays); scores
  precomputed in R — the frontend stays a dumb JSON renderer. Precompute scope: all
  scoreable coaches × ~96–100 latest-season big-5 teams.

---

## 10. Implementation plan

New file `src/coach_recommender.R`, prefix `cr_`, sourcing the `coach_fit.R` chain.
Pure cache-reader (no scraping). Phases, each ending with a recorded verification:

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Formation base rates, family taxonomy, axis collinearity check, nationality-scrape go/no-go | sizes the prize; axes frozen |
| 1 | Coach formation profiles + recency δ selection + rigidity measure | δ chosen out-of-sample |
| 2 | Eligibility matrix + best-XI assignment + deployed value | mechanical validation (§7.2) passes |
| 3 | Random-slope fit model (§3.2) | converges; LRT reported |
| 4 | Combined scorer + uncertainty + tier labels | face-validity spot checks (§7.4) |
| 5 | Payoff validation (§7.3) | acceptance rule applied; headline score frozen |
| 6 | Career facts + plausibility filters (§6) | spot-check against known careers (Ranieri's 11 clubs; Ferguson one-club) |
| 7 | Similarity layer | sanity: self-similarity of a coach's own stints ranks high |
| 8 | Site export + team-page section (incl. filter chips) | screenshot QA, link sweep, both themes |
| 9 | Write-up: `Summary_of_Findings.md` Part 7 + session log | — |

---

## 11. Known limitations (stated up front)

1. **Fit and formation layers cover big-5 / 2015/16+ only** (SofaScore coverage);
   most of the coach pool is quality-only, and team-specific suggestions exist only
   for big-5 clubs.
2. **Per-coach fit is shrunken, not significant.** No individual coach × archetype
   claim survives FDR; the system relies on partial pooling and is validated only in
   aggregate (§7.3). The site copy must not present fit components as per-coach proof.
3. **Squad values and archetypes are lagged but not exogenous** — market values and
   observed styles still embed history under previous coaches.
4. **Formation strings are kickoff shapes**; in-match changes and hybrid systems
   (nominal 4-3-3 defending as 4-4-2) are invisible. Family-level grouping limits but
   does not remove this.
5. **The counterfactual is never observed.** Validation uses realized appointments,
   which are themselves selected (clubs hire coaches they think fit) — survivorship
   pushes the measurable fit signal toward zero, so estimates are conservative.
6. **Small effective n for the payoff test:** new appointments per held-out season are
   limited; the B3-vs-B2 comparison may be underpowered, which is why the acceptance
   rule is "doesn't hurt" rather than "must significantly improve."
7. **Plausibility filters are career-history proxies**, not availability: they cannot
   see contracts, wages, or intent, and a coach's willingness to move is unmodeled.
   Coach nationality — a genuine plausibility factor — is not in the dataset unless
   the optional profile scrape (§6.3) is run. The "club level" percentile inherits
   the early-season sparsity of Transfermarkt values in smaller leagues (writeup
   limitation #3).
