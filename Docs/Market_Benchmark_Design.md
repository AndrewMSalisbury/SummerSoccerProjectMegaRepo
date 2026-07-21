# Forecasting Against the Betting Market — Design

**Goal:** Assemble the project's validated components — minutes-weighted squad value and
the coach quality BLUP — into a leakage-free, walk-forward **match/season forecaster**,
and test it against the sharpest external benchmark that exists: the **bookmakers'
closing odds.** This is the most direct answer the project can give to the question it
has never truly answered — *"can this actually predict, versus a market that already
prices in both the squad and the manager?"*

Status: **design only — not built.** Requires one new data source
(football-data.co.uk, verified §2) and a team-name crosswalk.

---

## 0. Honest framing (binding, read first)

The closing line is a **near-efficient-market null**. After the bookmaker's margin,
sharp closing odds are extremely hard to beat for profit. **The primary verdict is
therefore a skill question, not a profit one: "do we carry information the market's
implied probabilities do not?"** — a crisp statistical test (§4) with two publishable
outcomes. Andrew has asked for a **proper P&L backtest** as well (§4.4), and it ships as
a genuine secondary result — but with its honesty rails bolted on: beating *closing*
odds is the hard bar, a real bettor rarely gets the closing price, and margin + variance
mean a positive return over any finite sample can be luck. The P&L illustrates and
stress-tests the skill finding; it does not replace it as the headline, and a positive
P&L is never reported as a profitability claim without its confidence interval and the
closing-line caveat. The two outcomes the skill test can yield:

- **We add orthogonal information** → the coach/value signal is *underpriced* by the
  market (most plausible for lower-profile managers the market misjudges). A real
  headline.
- **We add nothing beyond the line** → the market already knows what our model knows.
  This is not a failure; it is the fourth on-brand "the signal is real but not
  incrementally exploitable" result, and it is the correct, honest verdict if that is
  what the data says.

Label: **confirmatory** — a pre-registered out-of-sample test with a fixed metric
decided *before* the run. The effect may well be null; that is a legitimate result and
must be reported as readily as a positive one. **No metric, feature, or subset may be
chosen after seeing the evaluation.**

---

## 1. Motivation

Every validation so far has been *internal* (leave-one-season-out, held-out coach-club
pairings). A skeptic's fair reply is: "your baseline is your own squad-value model —
show me you beat, or add to, the market." The betting line is the aggregation of every
serious model plus money on the line; it is the toughest, most credible baseline
available, and testing against it converts the project's scattered validated pieces into
a single forward-looking product with a pass/fail verdict. It also isolates the one
question that most matters for the coach work specifically: **is coaching quality
underpriced relative to squad value?** — the market surely prices the squad; it may
misprice a new or low-profile manager.

---

## 2. Feasibility — verified coverage (2026-07-21, football-data.co.uk)

- **Source:** free static CSV downloads (one per league-season) — no scraping politeness
  problem, no TLS fingerprinting (unlike SofaScore). Results + closing odds from up to
  ~10 books.
- **League coverage vs the project's 14:** **13 of 14 covered** — Premier League,
  Championship, La Liga, La Liga 2, Serie A, Bundesliga, Ligue 1, Portugal (Liga I),
  Netherlands (Eredivisie), Belgium (Jupiler), Turkey, Denmark, Poland. **Croatia (HNL)
  is absent — excluded from the benchmark.**
- **Odds depth (verified from the site's own notes):** match odds back to **2000/01**;
  closing odds + Asian-handicap/totals since **2005/06**; **Pinnacle** (the sharpest
  book) closing odds only from **2012/13**; opening *and* closing since **2019/20**.
- **Caveat to verify in Phase 1:** the smaller leagues (Denmark, Poland, and possibly
  Turkey/Portugal in early seasons) have **thinner bookmaker coverage** than the big-5.
  The benchmark's strong core is big-5 + Championship + La Liga 2 + Portugal + Nether-
  lands + Belgium + Turkey; Denmark/Poland ride along only where odds exist.

**Net:** a clean overlap with the project's active leagues — everything except Croatia —
with match odds available across essentially the whole 2005–2024 span, and a
best-quality subset (Pinnacle closing, 2012/13+) for the sharpest comparison.

---

## 3. Method

### 3.1 The forecaster (leakage-free by construction)
Team strength is a function of **only pre-match-known** inputs:

```
strength(team, matchdate) = f( minutes-weighted squad value  [prior season / as-of],
                               coach quality BLUP             [as-of matchdate],
                               home advantage,
                               promoted / newly-observed fallback )
```

- **Match model:** a Poisson / Dixon–Coles goals model (home & away expected goals from
  the strength differential + home effect), yielding P(H/D/A) and correct-score → the
  natural grain for odds comparison. A simpler ordered-logit on the strength gap is the
  fallback/robustness spec.
- **Season model:** aggregate the match model to a predicted table (interpretable
  output; also lets us compare to the existing M3 season-points framing).

### 3.2 Leakage is the whole game — walk-forward, as-of everything
The published coach BLUP is fit on *all* seasons; using it to "forecast" the past is
leakage. The benchmark **must** use an **expanding-window, as-of protocol**:

- For a match in season S, squad value = the squad as known before S (prior-season
  weighting, or the pre-season snapshot), never the realized in-season minutes.
- Coach BLUP = **refit on data strictly before the match** (expanding window; refit
  per season is sufficient and cheap). A coach with no prior history enters at the
  shrinkage prior (BLUP ≈ 0), which is itself the honest forecast and a natural test of
  whether the *first-season* coach signal has any value.
- Newly-promoted / first-observed teams get a documented value fallback (they have no
  big-5 prior); the recommender's squad handling is the reference.

### 3.3 Odds handling
- Use **closing** odds (sharpest); prefer **Pinnacle** where available (2012/13+), else
  Bet365 / the market average, recorded per match.
- **De-margin** (remove the overround) to implied probabilities before any comparison;
  note and, in a robustness pass, correct for the **favourite–longshot bias**.
- Keep opening odds (2019/20+) only as a secondary line-movement diagnostic.

---

## 4. Evaluation — pre-registered (fix before running)

Primary metrics, decided now:

1. **Calibration/skill vs market** — mean **log-loss** and **Brier** of our P(H/D/A) vs
   the de-margined closing implied probabilities, over the walk-forward test set. Report
   the gap. Expectation: the market is at least as good; the question is *how close*, and
   whether the coach term closes any of it.
2. **The incremental-information test (the real headline).** Logistic / multinomial
   regression of the actual result on **{market implied prob, our model's signal}**. A
   **significant coefficient on our signal after conditioning on the market prob** means
   we carry information the closing line underweights. This does *not* require beating
   the book — it is the honest, high-power test and the primary result.
3. **The coach-specific slice.** Re-run test 2 with the signal split into
   squad-value and coach-BLUP components. The squad value is near-certainly already in
   the line; the **coach BLUP's incremental coefficient** is the question that most
   matters — *is managerial quality underpriced?* Pre-register a focus on **newly-hired /
   low-profile managers**, where mispricing is most plausible (but as a pre-declared
   subgroup, not a fishing expedition).

4. **P&L backtest (secondary, pre-registered — Andrew, 2026-07-21).** A proper
   walk-forward paper-trading backtest, not an afterthought, with the staking rule and
   edge threshold **fixed before the run**: flat unit stake on every match where the
   model's edge over the de-margined market prob exceeds a pre-declared threshold, plus a
   **fractional-Kelly** variant as a robustness spec. Report cumulative return, ROI per
   bet, and a **bootstrapped confidence interval** on ROI (returns are heavy-tailed —
   a point estimate alone is meaningless). Mandatory honesty rails baked into the design:
   - **Closing-line realism:** we backtest at *closing* odds but a real bettor usually
     cannot get them; report a parallel run at the market average / opening line as the
     achievable-price floor.
   - **Margin & favourite–longshot bias** interact with any staking rule — report bets
     bucketed by favourite/longshot so a "profit" that is really longshot variance is
     visible.
   - A positive ROI whose bootstrap CI includes zero is reported as **not distinguishable
     from luck**, full stop.
   The P&L corroborates or stress-tests §4.2's incremental-information finding; the skill
   test remains the headline verdict.

**Anti-p-hacking discipline:** the primary/secondary metrics, the league/season test
window, the odds source priority, the newly-hired-manager subgroup, **and the P&L staking
rule + edge threshold** are all fixed in this document before the run. Anything discovered
post-hoc is labelled exploratory.

---

## 5. Confounds and traps (do not re-walk)

1. **Leakage** — the dominant risk. Any in-season information (realized minutes, the
   all-data BLUP, end-of-season value) invalidates the whole test. Walk-forward, as-of,
   audited (§3.2).
2. **Market margin & favourite-longshot bias** — de-margin; robustness-correct the bias
   (§3.3).
3. **Coverage gaps** — Croatia out; Denmark/Poland/early-Turkey odds thin (§2). Report
   results per-league and lead with the well-covered core; do not average a sparse-odds
   league into the headline.
4. **Team-name crosswalk** — football-data uses its own names ("Man City", "Ath Madrid")
   and league codes (E0, SP1, D1…). Mapping to TM ids is the real engineering cost and a
   known error source; build it like `ss_crosswalk_team_map()` (explicit, one-to-one,
   verified), not fuzzy best-guess. Promotion/relegation churn means the club set changes
   yearly.
5. **Closing-line timing** — "closing" quality varies by book and era; Pinnacle-only
   (2012/13+) is the cleanest subset and should be reported alongside the full span.
6. **Draw modelling** — three-outcome skill is dominated by draw calibration; the
   Dixon–Coles low-score correction exists precisely for this and must be included.
7. **Multiple leagues × eras = many comparisons** — the pre-registered primary metric
   (§4.2) is one test on the pooled walk-forward set; per-league is descriptive.

---

## 6. Phases

1. **Ingest + crosswalk.** New `src/source_odds.R` (`od_` prefix, cache under
   `data/cache/odds/`): download football-data CSVs for the 13 covered leagues, parse
   results + closing odds, build and **verify** the team-name → TM-id crosswalk. Confirm
   the odds-depth caveat per league/season. *Deliverable: a clean matches+odds table
   joined to TM team ids.*
2. **Walk-forward strength forecaster (value-only baseline).** The as-of Poisson model,
   no coach term, leakage-audited. Establish the value-only skill vs market.
3. **Add the coach BLUP (as-of).** Incremental info vs value-only and vs market (§4.2–4.3).
4. **Pre-registered evaluation** (§4): log-loss/Brier, incremental logistic, coach slice,
   calibration plots, the newly-hired subgroup; Pinnacle subset + full span.
5. **Site + writeup.** A "how the model would have forecast" surface + the verdict
   (positive or null), with the §0 framing intact. Optionally a live current-season
   forecast card, clearly marked as unvalidated going forward.

Recommended to build **after** the value-growth metric (that one needs no new data);
this one's Phase 1 crosswalk is the project's next real integration cost.

---

## 7. Resolved decisions (Andrew, 2026-07-21)

1. **Grain — both match and season.** Match-level for the odds benchmark, season-level
   for interpretability and M3 continuity.
2. **Odds source — Pinnacle where available → Bet365 fallback**, market average as a
   robustness spec (and as the "achievable price" floor in the P&L, §4.4).
3. **Test window — 2012/13+ primary** (Pinnacle-clean closing odds), full 2005/06+
   reported as secondary.
4. **P&L — yes, a proper pre-registered backtest** (§4.4), shipped as a genuine secondary
   result with fixed staking/threshold, bootstrap CIs, and the closing-line/margin rails.
   Skill metrics (§4.1–4.3) remain the headline verdict.

No open questions remain; ready to build Phase 1 (ingest + crosswalk) once the
value-growth metric is under way.

## 8. As-built notes
*(filled in as phases land — crosswalk coverage, leakage audit, the market verdict.)*
