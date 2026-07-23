# Session Log — 2026-07-22b: Four new directions (validation + fan surfaces)

## Trigger

Andrew: "Let's think of some new directions ... new things to add to be useful to
teams or fans, or even ways to validate that our model is useful." Picked all four
proposed directions and greenlit whatever scraping they needed:

1. **Manager-change event study** (validation, within-club natural experiment)
2. **2025/26 forward test** (validation, true future holdout — needed a scrape)
3. **Deserved table** (fan surface)
4. **Player-development leaderboard** (fan/scout surface)

Then, after seeing results: **docs + full site integration + a validation "report
card" surface**, and **deepen the event study with sacking efficiency**.

## Verdict (up front)

**Four for four, all positive** — a rare non-null session. Two independent new
validations of the coaching signal (event study p=0.004, forward test p=0.0024) that
agree with the recommender payoff (p=0.016), plus two face-valid fan surfaces. The
project now has three concordant internal validations of the coach BLUP and a market
benchmark saying the market has priced it.

## What shipped (analysis)

Three new pure-cache/results files, one scrape:

- **`src/event_study.R`** (`es_`) — manager-change event study + sacking efficiency.
- **`src/forward_test.R`** (`ft_`) — the frozen-at-2024 → 2025/26 holdout test.
- **`src/fan_surfaces.R`** (`fs_`) — deserved table + player-dev leaderboard.
- **2025/26 scrape**: `xx_data_populate_league_seasons(2025)`, 14 leagues, 252 teams,
  ~55 min, no 403/429. Game counts match the 2023 reference exactly per league
  (Danish Superliga's 22 is its regular-season-before-split convention).

Saved: `event_study.rds`, `forward_test.rds`, `fan_surfaces.rds`, `ds_2025.rds`.

## 1. Manager-change event study

Within-club first-difference design over **2,899 manager changes, 2005–2024, 14
leagues** (mid-season + between adjacent seasons). Leakage-clean via the as-of BLUP at
**cutoff = the outgoing coach's season**, which uniformly excludes both the before-
(`resid_out`) and after- (`resid_in`) residuals from both grades.

- **The naive difference spec is a null and confounded.** `dperf ~ dgrade + resid_out`:
  dgrade slope −0.24 (p=0.36), mixed −0.46 (p=0.04, wrong sign). Reason: selection ×
  RTM — clubs fire a well-graded coach during an unlucky dip (high `blup_out`, low
  `resid_out`) that then reverts, forcing a spurious negative dgrade↔dperf. RTM
  dominates everything (`resid_out` coef −0.95, p≈0).
- **The level spec is the validated headline.** `resid_in ~ blup_in + resid_out`:
  **blup_in +1.10, t=2.90, p=0.004**; club-clustered games-weighted mixed model
  **+0.91, p=0.006**. The grade of *who you hire* predicts how he does, controlling for
  the club's form. Strongest for **mid-season crisis hires** (+1.70, p=0.003), weak for
  summer moves (p=0.25) — the grade matters most exactly where clubs choose under
  pressure. Effect ≈ +0.7 pts/38-game season per +1 SD of blup_in.
- Full sample (unproven coach → prior BLUP 0, the honest forecast) is primary; the
  established-vs-established subset (n=610) is an underpowered robustness check
  (restricted range: blup_in SD only 0.025) and is directionally consistent.
- **Practical lesson: hiring is about the absolute quality of who you bring in, not
  how he compares to who you're firing.**

## 1b. Sacking efficiency (the deepening)

Mid-season sackings only (1,667). A sacking is "harsh" when the outgoing coach was
OVERperforming his squad (`resid_out > 0`).

- **16.4% of mid-season sackings were harsh** (overperformer fired); 83.6% defensible.
  Mean outgoing residual −0.30 (clubs sack during a dip).
- **Firing the overperformer backfires:** replacement mean dperf **−0.16** (improved
  only 36%) after harsh sackings vs **+0.35** (79%) after defensible ones — the RTM
  structure made actionable.
- Big and small clubs sack harshly more (18.5%) than mid clubs (12.7%).
- **Face validity is the headline:** the harshest-sackings leaderboard surfaces the
  canonical disasters — Birmingham firing **John Eustace (+0.47) for Wayne Rooney
  (−0.50)** → relegation; Birmingham firing **Gary Rowett for Zola**. The model finds
  the sackings fans already know were mistakes.

## 2. 2025/26 forward test

Model **frozen at 2024** (M3 coefficients + M5 BLUPs on ≤2024) → predict the completed
2025/26 season it never saw (252 team-seasons, 14 leagues). A genuine forward hold-out
in time, unlike LOSO-CV.

- **Q1 — the model generalizes out-of-time.** Enhanced (minutes-weighted) on the
  holdout: **R² 0.72, cor 0.85, mean error 6.3 pts/team-season**, and it **still beats
  raw squad value by 0.013 PPG** — the same margin as the original CV. No degradation
  (holdout RMSE 0.223, slightly better than the 20-year pooled in-sample 0.255 because
  2025 avoids the sparse early-2000s seasons). Uses the project's realized-minutes
  model, so it is an out-of-time test of the model *structure*; the pre-season-forecast
  question is the separate (already-answered) market benchmark.
- **Q2 — the coach grades are prospectively valid.** Coaches rated on ≤2024 data
  overperformed in 2025 as predicted: stint-level `partial_residual ~ prior_blup`
  **slope +1.90, t=3.05, p=0.0024** (graded-only p=0.0036); adding the BLUP improves the
  2025 forecast (RMSE 0.223→0.220). **A true future holdout with zero leakage** — the
  cleanest single validation of the coaching signal in the project, coherent with the
  event-study estimate.
- Bonus 2025/26 surfaces: over-achievers Bayern/Kompany (+18), Arsenal, Lens/Sage;
  under-achievers Wolves (−22, relegated), Leicester, Spurs, Chelsea.

## 3. Deserved table (fan)

`fs_deserved_table()` — expected standings from the enhanced model vs actual, per
league-season; over/under = the M4/M5 residual as a league table. Leicester 2015/16:
finished 1st, deserved 10th (+30 pts). Chelsea: deserved 1st, finished 10th. All-time
extremes match the known narratives (Liverpool 2019 +32, Leicester 2015 +30). The
documented early-small-league artifacts (Gimnàstic 2005 etc.) still show and must be
labelled per Limitation 3.

## 4. Player-development leaderboard (fan/scout)

`fs_dev_leaderboard()` — ranks the clean CDE by-product `dev_resid` (appreciation above
the age/price/position/momentum baseline; the one keepable output of the Part-9 null).
Minutes ≥ 1500, value_t ≥ €1m. Top: Ederson (€1.2m→€22m), Frenkie de Jong (€7m→€85m),
Vardy, E. Martínez, Reijnders, Matheus Nunes — canonical breakouts. A 2020+ cut surfaces
recent development-league gems (Las Palmas, Sheffield Utd, Legia). By position, forwards
& keepers over-appreciate most (corroborates the CDE archetype follow-up). **Note:
`pct_minutes` in this cache is share-of-team-minutes, maxing ~0.092 — use raw
`minutes_played` for thresholds, not a 0–1 season share.**

## Cross-result coherence

Three independent validations of the coach BLUP now agree, each on a different design:
recommender payoff (new coach-club pairings, p=0.016), event study (within-club natural
experiment, p=0.004), forward test (true future season, p=0.0024). The market benchmark
says the market has already priced it. This is the project's most robust position on the
coaching signal to date.

## Environment notes (unchanged from 07-22a)

- Rscript `-e` inline segfaults on this box — always script files.
- Working dir `src/`; source chain needs `source_data.r` before `coach_attribution.R`.
- The 2025/26 scrape is idempotent/resumable; re-run `xx_data_populate_league_seasons(2025)`.

## Reproducing

```r
# working dir src/ — pure cache/results readers after the one-time 2025 scrape
source("source_data.r"); xx_data_populate_league_seasons(2025)   # ~55 min, idempotent
source("event_study.R");  run_event_study()
source("forward_test.R"); run_forward_test()
source("fan_surfaces.R"); run_fan_surfaces()
```

## Follow-up: the player-growth page leads with the baseline, not sparklines

Andrew, reading the shipped page: *"Instead of player value histories on the player
growth page, I want one large graph showing the predicted player growth by position.
Also make the option to show all players look like the option to show all coaches on
the main page."*

Both done. The per-row market-value sparkline column is gone (and with it the
`players.rds` read, the `traj` payload — `players.json` 77 KB → 47 KB — and the
one-off `.more-btn` / `svg.spark` CSS). In its place the page opens with **the
expectation curve itself**: `charts.js growthCurves()`, one line per position group
over age, fed by a new `se_growth_curves()` in `site_export.R`. That is a better
answer to the same question the sparkline was gesturing at — the leaderboard ranks
residuals *against this curve*, and until now the curve was invisible.

Decisions worth keeping:

- **The curve is standardized (g-computation), not a group mean of fitted values.**
  Each grid point re-predicts over a fixed 4,000-row sample of real player-seasons
  with age and position overwritten, so starting value, league and season are held
  constant across the whole chart and a position gap is an age × role effect rather
  than a price-mix artifact — which is what "by position" has to mean. The cost is
  that the curve sits *below* what real teenagers average (+62% predicted vs +102%
  observed at 16, because actual 16-year-olds are far cheaper than the standardization
  population); that gap is stated in the footnote and the per-age observed mean rides
  along in the JSON.
- **The baseline is refit from `player_dev_residuals_14league.rds`, not re-derived.**
  Every right-hand-side column is in that file, so the CDE-total formula reproduces
  the stored `pred_total` to 1e-11 — and the export now *asserts* that, which is the
  tripwire if `cvg_fit_baselines()`'s spec ever moves.
- **Four series meant new colour, and the slot order is the safety mechanism.** The
  site had two categorical hues; `--series-3` (orange) and `--series-4` (yellow) were
  added from the dataviz reference palette and the set was run through the validator
  in both modes: blue → orange → aqua → yellow passes the adjacent-pair gate (worst
  CVD ΔE 9.1 light / 8.4 dark) but **fails all-pairs** — as the palette doc says no
  four-hue set can — so `CAT4` must never be re-ordered, cycled, or reused for a
  scatter. Aqua and yellow are sub-3:1 on the light surface, so every curve also
  carries a direct end label (in the right gutter, with a hairline leader, since the
  four curves converge hard after age 30 and end at different ages).
- The position filter now drives the chart too: selecting a position dims the other
  three curves rather than recomputing anything.
- The table's "show all" is now the home page's `.show-more` button verbatim —
  same class, same in-card placement, same `Show all N players` / `Show top 25`
  toggle.

Face validity of the curve is strong and is the reason it earns the top slot:
expected growth runs from ~+60–79% at 16 to −35% at 34, crossing zero at 26–27 for
outfielders — while **goalkeepers are flat at ~+10% from 17 to 25 and cross zero at
27**, the late-peaking keeper curve the CDE code comments assert, rendered.

QA: chromote, light + dark + 375px, plus the GK-filtered and fully-expanded states.
No card overflow anywhere; the 6px body overflow at 375px is pre-existing and
site-wide (wide tables inside `.table-wrap`) — `index.html` shows the same 6px.

## Follow-up: the three validations, spelled out

Andrew: *"for the Does it Work page lets make it clearer what the three concordant
validations mean, right now it is not clear what each one is, and they are the most
important thing on the page."*

Correct — they were three stat tiles carrying a bare p-value and a five-word label,
which is the least informative possible rendering of the page's whole point. Replaced
with three `.val-card`s.

**It took three passes to land, and the path is the useful record.** Draft 1 was five
labelled rows of prose per card — too dense (*"a bit too dense … just concisely describe
each test"*). Draft 2 cut each design to a single line — and lost the plot in the other
direction (*"now too short and does not clearly state what each test is … be sure to
differentiate test 1 and 2"*). The shipped version sits between them:

| slot | content |
|---|---|
| eyebrow | `Test N` + a **design-type chip**: Out-of-sample forecast / Natural experiment / Future holdout |
| title + question | one line each, in plain language |
| **What the test does** | a short paragraph — the data, the mechanic, and what is held out |
| Result | the effect **in points**, p-value as a chip, one-clause caveat under it |
| What this means | the takeaway + a deep link to the writeup part |

**Tests 1 and 2 are the pair a reader conflates** — both are "does the grade predict
hires?" — so the fix is structural, not cosmetic: the design-type chips separate them at
a glance, and test 2's description *opens* by naming the difference ("Where test 1 pools
appointments across hundreds of different clubs, this one holds a single club fixed").
The section subtitle does the same job for all three before the cards are read.

The lesson worth keeping: **"concise" is not the goal — legible is.** One line per design
was shorter and worse, because a reader who cannot tell two tests apart learns nothing
from either. The right cut is the *mechanic* of the test (what is compared with what, and
what is withheld); what belongs in the writeup is the statistics (slopes, fold counts,
model specs), one click away.

Decisions:

- **Effect sizes are now stated in points, not slopes.** "+1.10 PPG per unit of BLUP"
  is meaningless to a reader; the export computes `pts_per_sd` (slope × SD of the grade
  × 38) so tests 2 and 3 read as **+0.7** and **+1.4 points a season for a coach one SD
  above average** — comparable to each other and honest about the size of the effect.
  Test 1 keeps its own unit (forecast error 0.3016 → 0.2992 PPG) because it is an
  accuracy test, not a slope; inventing a points figure for it would be fabrication.
- **The Part-7 payoff numbers are now derived, not hardcoded.** `se_export_validation()`
  reads `recommender.rds$meta$payoff` and recomputes p from the LOSO folds. The
  published **p = 0.016 is the one-sided paired test** — the pre-registered acceptance
  rule is directional (a layer ships only if it does not hurt RMSE), so the two-sided
  0.031 would be the wrong test rather than a stricter one. Recorded in the code
  comment so nobody "fixes" it later.
- **The caveats ride on the cards, not in a footnote** — and survived both density
  edits for that reason. Test 1 says out loud that the 0.016 is the realized-value framing and
  the stricter pre-hire framing is only p = 0.052; test 2 says the incoming-vs-outgoing
  grade *gap* predicts nothing (the confounded null); test 3 says one season is one
  season. A reader who only reads the cards still gets the honest version.
- **"What this means" replaced "what this rules out".** The rules-out framing was
  written for a methodologist ("that good coaches simply inherit good squads"); the
  reader wants the conclusion ("the effect follows the coach, not the squad — and
  matters most when a club hires in a panic"). The objection each design kills now lives
  in the one "Why it takes three" card, said once instead of three times.
- A p-value explainer sits under the block, and the two detail sections were retitled
  "Inside test 3 / Inside test 2" and rewritten so they extend the cards (the 2025/26
  season's own story; sacking efficiency) instead of restating them.

QA: chromote light/dark/375px — 3 cards, p chips 0.016 / 0.0038 / 0.0024, writeup deep
links resolve to the Part 7 and Part 11 anchors, no card overflow.

## Next

- Docs: Summary_of_Findings Part 11 (+ fan surfaces), CLAUDE.md, Milestones — done.
- Site: deserved table (league standings column), player-growth page, validation
  report card — done.
- **Still not committed.** The tree now carries the 2025/26 scrape, the three new
  analysis files, both new pages and all of the above.
