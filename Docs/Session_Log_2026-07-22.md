# Session Log — 2026-07-22: Market Benchmark (built in one session)

## Trigger

Andrew: "Let's attempt to oneshot the market benchmark." Build the whole thing from
`Docs/Market_Benchmark_Design.md` — ingest football-data.co.uk odds, crosswalk to TM,
a leakage-free walk-forward forecaster, and the pre-registered evaluation against
bookmaker closing odds — in a single pass.

## Verdict (up front)

**A clean null — the honest §0 outcome #2.** The leakage-free forecaster (pre-season
squad value + home + as-of coach BLUP) neither beats nor adds to Pinnacle closing odds.
The market already prices both squad value and coaching quality. The one apparent win
(+0.224, p = 10⁻²¹) was within-season valuation leakage, dissolved to p = 0.31 by the
pre-registered prior-season-value check. First *external* validation the project has run;
fourth on-brand "real but not incrementally exploitable" result, now against the sharpest
baseline that exists.

## What shipped

Two new files, both pure cache/results readers (no scraping):

- **`src/source_odds.R`** (`od_`) — download football-data CSVs (`data/cache/odds/`), parse
  results + closing odds, within-season greedy one-to-one team crosswalk to TM, de-margined
  matches table. 13 leagues covered (11 main-file; Denmark/Poland new-file deferred; Croatia
  absent). 51,807 matches 2012–2024, 99.9% Pinnacle-closing.
- **`src/market_benchmark.R`** (`mb_`) — `mb_prepare` (cached M3 dataset + model-independent
  coach-stint actuals), `mb_asof_blups` (M5 mixed model refit per cutoff, cached), Dixon–Coles
  goal model (`mb_fit_dc` MLE + fast `mb_fit_dc_glm` stacked Poisson, validated identical),
  `mb_walkforward`, `mb_evaluate` (McFadden conditional logit + log-loss/Brier), `mb_pnl`
  (§4.4 pre-registered backtest). `mb_run()` → `data/results/market_benchmark.rds`.

Docs: `Summary_of_Findings.md` Part 10 + Limitations 12 + Conclusion; design §8 as-built;
CLAUDE.md architecture section; this log.

## The build, in order (and what each step taught)

1. **Feasibility gate first.** Confirmed R can reach football-data (one E0 download): 380
   rows, Pinnacle closing (PSCH/D/A) + Bet365 present. Only then built anything.
2. **Ingest.** 13-league config; `od_data_populate` cached 143 main-file CSVs (idempotent
   resume). Odds audit: **PSCH/D/A present in every 2012–2024 season file** — Pinnacle
   closing is the primary, PS/B365 fallbacks.
3. **Crosswalk — the real work.** football-data's abbreviations beat name matching, so the
   scorer leans on the **within-season bijection**: greedy one-to-one assignment per
   league-season. First cut used a cross-season *stable* map and collided RAEC Mons 2012
   (two fd names → one verein, 60 games); fixed by building matches from the **per-season**
   assignment. **Verification is points reconciliation vs TM's own match records** (not name
   scores): 99.7% exact outside Belgium, 100% for seven leagues; every miss a fixture-count
   difference (Belgian playoffs, fd's ~2 missing Portugal fixtures), no misidentification.
   `od_name_overrides` never needed an entry.
4. **As-of BLUP.** Refit the full M5 mixed model on completed seasons < cutoff. Validated by
   face check: cutoff-2024 (fit on 2005–2023) → Guardiola #1 +0.138, then Ferguson/Allegri/
   Conte/Tuchel/Klopp, matching the published leaderboard. Also confirmed `coaches.rds`
   covers all 14 leagues 2005–2024 (~600–775 stints/yr) — CLAUDE.md's "5-league" note is stale.
5. **Forecaster.** Dixon–Coles bivariate Poisson; strength = a·Δlog-value + b·Δblup.
   **The coach term b would not stably fit inside the goal model** (collinear with value,
   sign-flipping across folds, b ∈ ~[0, 1.2]) — so the deployed forecaster is value+home and
   the coach is tested as a separate incremental signal. This also let the fit drop to a
   stacked Poisson GLM (`mb_fit_dc_glm`), ~50× faster and numerically identical to the MLE.
6. **Walk-forward + evaluation.** 12 folds, 2013–2024, 47,982 test matches. Conditional-logit
   incremental tests + P&L.

## Results

**Naive current-season value (the trap):** incremental beyond market **+0.224, z = 9.6,
p = 1.08×10⁻²¹**. Looked like the headline.

**Leakage-free prior-season value (primary):**

| test | result | verdict |
|---|---|---|
| skill (log-loss) | market 0.978 vs model 1.014; market better in all 11 leagues | market sharper |
| §4.2 value beyond market | +0.023, z = 1.0, p = 0.31 | null |
| §4.3 coach beyond market | −0.17, p = 0.51 | null |
| §4.3 coach beyond market+value | −0.17, p = 0.51 | null |
| §4.3 coach, low-profile subgroup | −0.41, p = 0.32 (n = 36,425) | null |
| §4.4 P&L, 5% edge, Pinnacle close | ROI −6.4%, CI [−8.1, −4.8] | loses money |
| §4.4 P&L, 5% haircut (achievable) | ROI −9.9% | loses more |

The single input change (current → prior value) collapsed +0.224/10⁻²¹ to +0.023/0.31.
Calibration of both market and model is good across deciles; the model is simply
strictly dominated by the line. Every P&L odds bucket loses.

## Decisions

- **Primary = prior-season value.** Current-season value kept only as the leakage demo.
- **No site surface.** A null lives in the writeup (project convention: CDE Part 9, Layer C).
  Part 10 + `writeup.html` regeneration is the deliverable.
- **Denmark/Poland + pre-2012 deferred** — secondary per design §2; the strong core (11
  main-file leagues, 2012/13+ Pinnacle-clean) carries the verdict.

## Environment traps (recorded for next time)

- Rscript at `C:/Program Files/R/R-4.6.0/bin/Rscript.exe`; working dir is `src/`.
- **Rscript `-e` inline segfaults intermittently** on this box — always use script files.
- **The editor's linter strips `\\` in regex string literals** (`\\d`→`\d`, breaks R
  parsing) — use POSIX classes `[[:digit:]]`/`[[:space:]]` and `[.]`, never backslash escapes.
- The full joint-MLE DC fit is slow on 40k-row folds (~3 min each); the GLM fit is the one
  to use. Prep + 13 as-of-BLUP refits are cached (`mb_prep.rds`, `mb_asof_blups.rds`).

## Reproducing

```r
# working dir src/ — pure cache/results reader after the one-time CSV download
source("source_odds.R"); od_data_populate(2012:2024)          # ~2 min, idempotent
source("market_benchmark.R")
ev <- mb_run(value_mode = "prior")                            # leakage-free primary
ev_leak <- mb_run(value_mode = "current")                     # the leakage demo
```

## Loose ends / next

- Denmark/Poland (new-file format) and pre-2012 seasons remain un-ingested — low value
  given the null, but the cleanest way to widen the benchmark if ever revisited.
- The favourite-side edge visible in the *current-value* P&L is a leakage artefact and
  must not be re-read as a real strategy.
