# Coach → Player Value Growth — Design

**Goal:** Build a new, €-denominated coaching metric that the project does not yet
have — **do players appreciate in market value faster than expected under a given
coach, and how much of that excess is attributable to the coach?** This turns the
project's Limitation #5 (value endogeneity) from a caveat into the object of study,
and adds a second outcome axis alongside the points BLUP: not *did the team win more
than its value predicted*, but *did the players become more valuable than their
trajectory predicted*.

Status: **design only — not built.** All core data is already in the cache (no new
scrape). Feasibility verified 2026-07-21 (see §2).

**Working name for the metric:** the **Coach Development Effect (CDE)** — a coach-level
value-growth-over-expectation BLUP, built on the exact M3→M4→M5 skeleton (baseline
expectation model → residual → games/minutes-weighted mixed-model attribution with
shrinkage) so it inherits the machinery and the discipline. Final name is Andrew's
call (§8).

---

## 0. Honest framing (binding, read first)

The points BLUP earned its **validated** label the hard way — out-of-sample payoff on
new coach-club pairings (p = 0.016). **CDE has earned nothing yet, and its outcome is
structurally harder to trust than points:**

- **Points are zero-sum within a league-season** (they sum to a fixed total; the M3
  residual is mean-zero by construction). **Value growth is not** — a whole league can
  appreciate in a boom market, players develop on their own age curve, and there is no
  adding-up constraint. Every confound that zero-summing quietly cancelled for points
  is live here.
- **Market value is partly a function of the very performance the coach produced.** If
  a team overperforms, the market marks its players up — so CDE and the points BLUP are
  *mechanically entangled*, not independent. A CDE that is just the points BLUP
  re-expressed in euros is not a new metric (§5, the reflection trap).
- **Value growth is overwhelmingly an age story** (verified §2): teens gain ~+0.22 log
  value/year, prime-age players ~0, over-30s lose ~0.29/year. A coach of a young squad
  tops any naïve list trivially.

**Therefore the honesty label is `exploratory` until it passes a pre-registered
validation (§6)** — and even then it is an *association*, stated as "players tended to
appreciate more under this coach," never "this coach adds €X to a player." The design's
whole job is to strip the age/mean-reversion/market confounds down to something that
*might* be coaching, then test honestly whether anything survives and whether it carries
information beyond the points BLUP. If it doesn't, that is a publishable, on-brand null
(the fourth such result — see the descriptive-profile Layer C precedent).

---

## 1. Motivation

The site answers "how good is this coach?" (points BLUP) and "what is he good at?"
(descriptive profile). It says nothing about the outcome a sporting director cares
about almost as much as points: **do players get better — and more sellable — under
him?** A coach who takes a €5m academy graduate to a €40m sale has produced value the
points table never shows, and the transfer surplus can dwarf a season's prize money.
This is the "moneyball" dimension the project has the raw material for but has never
touched. It is also the most fan- and scout-shareable single number after the grade.

Crucially it is a *different outcome*, not a re-slice of the residual (unlike Layer A).
That makes it the first genuinely new signal the project has attempted since M6 — and
the first chance to either corroborate the points BLUP from an independent direction or
expose that the two measure the same thing.

---

## 2. Feasibility — verified facts (2026-07-21)

Probed on `xx_data_cache$players` (274,910 player-team-season rows, 67,221 players):

- **Market values are genuine historical snapshots, not a current scrape.** Of 26,772
  players with ≥3 valued seasons, **96.7% show >1 distinct value** (mean 4.87 distinct
  values). TM's per-season squad pages serve the valuation *as it was that season*.
  **This is the make-or-break fact and it passes** — trajectories are real.
- **Sample is large.** 137,631 consecutive (t, t+1) valued player pairs;
  **94,397 (68.6%) are same-club** (player stayed → growth window cleanly under one
  club's coach(es)). 82.4% of player-rows carry a value.
- **Coach coverage is essentially complete** over the value era: 7,190 of 7,214 player
  team-seasons have coach data in `coaches.rds`. The M5 attribution spine already
  covers this.
- **The age curve is the dominant signal and must be modelled** (same-club pairs,
  median log-growth by age): (15,19] +0.223 · (19,21] +0.095 · (21,25] ~0 ·
  (27,29] −0.134 · (29,31] −0.236 · (31,40] −0.288. Any baseline that omits age is
  measuring squad age profile, not coaching.

**Open empirical question to pin in Phase 1:** *when* in the season is the snapshot
taken (start / mid / end)? It determines which coach a growth window belongs to. The
design is robust to the answer as long as we are consistent (§3, attribution), but it
should be checked against a couple of known mid-season transfers before locking the
attribution rule.

---

## 3. Method — the CDE pipeline (mirrors M3 → M4 → M5)

### 3.1 Unit of analysis
The **player-season** (player × club × season) with a valued snapshot at both the
season-t and season-(t+1) boundary. Response = **log value growth**,
`g = log(value_{t+1} / value_t)`. Log because growth is multiplicative and the age
curve is roughly linear in log (§2); it also tames the €180m-vs-€1m scale.

### 3.2 Baseline expectation model (the "M3" analog)

**Governing principle (binding): control every confounder the coach does *not*
influence; never control a mediator the coach *does* influence.** "Control for everything
possible" is the wrong objective — the largest threat to CDE is *over-control*, where
conditioning on something the coach causes (minutes, results, player output) silently
deletes the effect we are measuring. Selective control, not maximal control (§5.3).

Predict `g` from confounders only, fit pooled across all player-seasons:

```
g ~ ns(age, k) * position_group      # age curve, allowed to differ by position
    + log(value_t)                   # mean reversion / ceiling
    + prior_growth                   # lagged momentum: already on a breakout arc?
    + factor(league) + factor(season)
```

- `ns(age) * position_group` — the dominant term (§2), splined for the teen surge and
  the over-30 cliff, **interacted with position** because the curves differ in shape
  (keepers peak late; forwards' value is front-loaded). A single shared age curve
  under-fits the tails.
- `log(value_t)` — **mean reversion / ceiling**: expensive players grow slower in %
  terms; cheap ones have room. Without it, low-value squads look developmental.
- `prior_growth` — the player's **own value momentum** into season t (lagged log-growth).
  Controls for players already on a breakout arc who would rise under any coach, so their
  pre-existing trend is not credited to the current one.
- `factor(season)` — absorbs market-wide value **inflation** (2005–2024 is a rising
  market); the non-zero-sum analog of a within-season balance constraint.
- `factor(league)` — different market sizes value the same performance differently.

**The residual `dev_resid = g − ĝ` is the player-development residual** — value growth
beyond what age, position, price, pre-existing momentum, league and market conditions
predict.

#### 3.2a Controls classification — the load-bearing table

Every candidate factor is either a confounder (control it) or a mediator (leave it in the
residual, or it strips the effect). Getting a single row wrong invalidates the metric.

| Factor | Type | Decision |
|---|---|---|
| Age (spline × position) | confounder | **control** — dominant driver (§2) |
| Position group | confounder | **control** |
| Starting value `log(value_t)` | confounder (mean reversion) | **control** |
| League, season | confounder (market size, inflation) | **control** |
| Prior-season value momentum | confounder (pre-existing trend) | **control** — new |
| Contract length remaining | confounder | **omitted, known gap** — drives TM value, not the coach's doing, not in cache; needs a scrape to close (§5.8) |
| **Minutes / starts played** | **mediator** (his deployment) | **do not control** in CDE-total; enters *only* the labelled CDE-development fork (§3.3) |
| **Team results / goals / European qualification** | **mediator** (he causes them; they raise value via exposure) | **never control** — this is the reflection channel; instead test CDE's orthogonality to the points BLUP separately (§5.4) |
| **Player's own output** (goals, assists, rating) | **mediator** (his system produces it) | **never control** — "he made him a 20-goal striker" *is* the effect being measured |

The three mediator rows are exactly the ones it is most tempting to "control for, to be
rigorous." Conditioning on any of them answers a degenerate question (e.g. controlling
for goals asks "does he grow value *beyond* making players productive" — almost nothing).
They are excluded by design, not by omission.

### 3.3 The minutes question — a deliberate fork, run both ways
Minutes played in season t is **the coach's decision** and a **mediator**, not a clean
covariate. Two baselines, reported as a decomposition, not an either/or:

- **CDE-total** (baseline *excludes* minutes): the residual credits the coach for
  *both* trusting the player with minutes *and* improving him per minute. This is the
  "did players grow under him, full stop" number.
- **CDE-development** (baseline *includes* `f(minutes, starts)`): credits only growth
  *beyond* what the playing time alone would explain — "did he make them better, given
  how much he played them."

The gap between the two **is** the opportunity channel (a coach who develops value
mainly by giving minutes vs mainly by coaching). That decomposition is itself a finding
and arguably the most interesting output. Note: minutes is the coach's within-window
deployment, so it aligns cleanly with the growth window.

### 3.4 Attribution to coach (the "M4→M5" analog)
Reuse the M5 spine verbatim where possible:

- A player-season's `dev_resid` is attributed to the coach(es) who ran that club in
  season t. Where a season had multiple coaches, split by the player's **minutes under
  each coach** (finer than the games-weighting M5 uses for team points, because we have
  per-player minutes; falls back to games-share if minute splits are unavailable).
- Aggregate to coach as a **weighted mean**, weight = the player's minutes (or value
  exposure) in the stint — the CDE analog of games-weighting.

### 3.5 Mixed model + shrinkage BLUP (the headline)
```
dev_resid ~ (1 | player_id) + (1 | club_id) + (1 | coach_id)   [weighted]
```

**The `(1 | player_id)` random effect is not optional — it is the metric's integrity.**
The same player recurs many times and carries persistent, unmodelled appreciation (a
generational talent appreciates under whoever coaches him). Without a player RE, a coach
handed naturally-rising talents is credited for their trajectory. With it, the coach
BLUP is identified from **players who deviate from their own trend under this coach vs
others** — the honest question. Player and coach are partially confounded (a player sees
few coaches), so identification leans on player movement; report the effective
identifying overlap, and treat coaches whose entire signal comes from one or two players
as uncertain (the §6 games/minutes bar).

Extract coach BLUPs = **CDE**. Apply the same display-certification discipline as the
grades (a minutes/games floor; §6).

---

## 4. What the metric is allowed to say

- **CDE-total ≈ "players appreciated more than their trajectory predicted under him."**
  Descriptive, exploratory-labelled.
- The **decomposition** (opportunity vs per-minute) is descriptive color, not causal.
- **Never** "he adds €X to a player" or "he caused the growth" as fact — the reflection
  problem (§5) forbids it. The site language, if it ships, is a *tag* ("develops
  value") on validated coaches, gated exactly like Layer A/B were.

---

## 5. Confounds and traps (pre-register; do not re-walk)

1. **Age curve** — handled by `ns(age) * position_group`. Sanity check: CDE must be
   ~uncorrelated with the coach's mean squad age after the baseline; if not, the spline
   (or its position interaction) is under-fit.
2. **Mean reversion / ceiling** — handled by `log(value_t)`; verify CDE isn't just
   "coaches of cheap squads."
3. **Over-control / bad controls (the mediator trap — the one that would quietly kill
   the metric).** The instinct to "control for everything possible" is *wrong* here:
   conditioning on any factor the coach influences — minutes, team results, player
   output (§3.2a) — is a bad control that subtracts the very effect CDE measures. A CDE
   that controls for goals scored answers "does he grow value beyond making players
   productive," which is almost nothing. The baseline holds **confounders only**; every
   mediator stays in the residual by design. Any proposal to add a control must first
   pass the test "is this something the coach does *not* influence?" — if no, it is
   forbidden, not optional.
4. **The reflection trap (the other big one).** Market value is marked up *because* the
   team overperformed under the coach → CDE and the points BLUP are entangled. This is
   the reason team results are a mediator, not a control. **Mandatory test: partial CDE
   on the points BLUP.** If nothing survives, CDE is points re-expressed and must be
   reported as such (not a new signal). If a residual survives, *that* is the genuinely
   new information (development independent of results).
5. **Selection / survivorship in transfers.** A player sold mid-window leaves the
   same-club sample; declining players get dropped from squads (no t+1 valuation) →
   the same-club set is tilted toward stayers/succeeders. Start same-club, then add a
   cross-club variant (attribute the season-t window to the selling club's coach) and
   check the CDE is stable across the two.
6. **TM bulk revaluation lag.** Values update in batches and can be sticky; growth may
   register a season late. Season fixed effects + not over-interpreting single pairs.
7. **Not zero-sum → no free balance check.** Unlike points, we cannot lean on
   within-season residuals summing to zero. Season FE handles inflation, but there is
   no adding-up identity to validate against — a reason the validation (§6) matters
   more here than it did for M5.
8. **Contract length — the known omitted confounder.** A player in his final contract
   year is marked down regardless of coaching; contract remaining is a genuine value
   driver, is *not* the coach's doing (so it belongs in the baseline), and is **not in
   the cache**. Closing it needs a TM scrape (contract-expiry is on the same profile
   pages as the transfer-fee data, so the §7 parallel scrape can pick it up cheaply).
   Until then it is an honest gap: name it, and check whether CDE correlates with squad
   mean contract-age as a proxy for how much it bites.
9. **Small-sample coaches.** A coach seen with two youngsters who blew up will top a raw
   list. The minutes/games bar + player RE shrinkage + the ≥3-stint significance rule
   (inherited from M5) are the guardrails.

---

## 6. Validation (pre-registered, before any ranking is read)

CDE ships **only if** it clears tests analogous to the ones the points BLUP passed:

- **Repeatability (OOS).** Split each coach's career (even/odd seasons, as M5's
  weighting test did). Does early-career CDE predict held-out late-career CDE? A metric
  that doesn't repeat is noise.
- **Adds information beyond points (§5.4).** Partial correlation of CDE with the points
  BLUP; report the residual-signal magnitude. Pre-register that "CDE is interesting"
  requires a non-trivial component orthogonal to points.
- **Face validity.** Known developers should surface high (academy-to-sale pipelines:
  think Dortmund/Ajax/Southampton/Salzburg-type tenures, Klopp/Ten Hag/Tuchel/De Zerbi
  era clubs) and "buy-it-ready" galactico managers lower. Bottom of the list should be
  plausible (value-destroying spells, aging expensive squads).
- **External tie-back — scoped in parallel (Andrew, 2026-07-21).** Correlate CDE with
  **realized transfer surplus** — sale fee minus prior value — which TM records on player
  transfer-history pages. This is the closest thing to ground truth for "did the value
  become *real money*" rather than a TM paper valuation, and a positive tie is the
  strongest possible evidence CDE is not an artifact of TM's own valuation model. It is
  a genuine new scrape (`xx_raw_player_transfers()` / `xx_data_populate_player_transfers()`,
  `xx_` prefix, resumable + priority-ordered like the nationality/image scrapers, with
  TM's mandatory politeness delays — see the scrape track in §7). Built **alongside**
  Phases 1–2, not after, so the external check is ready the moment the internal
  validation lands. The fee data is validation-only; it does **not** enter the CDE
  construction (that would circularly bake sales into the metric it is meant to test).
- **Certification bar.** A minutes/games floor for display (the CDE analog of the ≥109
  games grade bar), re-derived on this metric's own reliability, not copied blindly.

---

## 7. Phases

1. **Baseline model + development residual.** Build the player-season table (same-club),
   fit §3.2 baselines (both minutes variants), verify the age/price/season controls,
   face-check top/bottom `dev_resid` player-seasons. Pin the snapshot-timing question
   (§2). *Deliverable: `player_dev_residuals.rds`, a validated residual.*
2. **Coach attribution + CDE BLUP.** §3.4–3.5, player RE included. Face validity,
   partial-out-points test, repeatability OOS. *Deliverable: `coach_value_growth.rds`
   (per-coach CDE-total, CDE-development, significance), the honesty verdict.*
3. **The opportunity/development decomposition** as a reported result (§3.3 gap).
4. **Cross-club robustness** + selection/survivorship checks (§5.5).
5. **Site + writeup**, *gated by the §0 label*: almost certainly a clearly-labelled
   "develops value" descriptor on validated coaches + a writeup part, **not** a hard €
   claim. If CDE fails validation, writeup-only null.

**Parallel scrape track (runs alongside Phases 1–2, decided 2026-07-21):** the
transfer-fee scrape for the §6 external tie-back. Independent of the main pipeline (it
touches no CDE construction), so it can populate in the background while Phases 1–2 are
built and be ready for validation when Phase 2 lands. Resumable and priority-ordered
(highest-minutes / highest-value players first) so a partial scrape still validates the
coaches that matter most. **The same TM profile pages carry contract-expiry dates**, so
this scrape should capture them too and close the §5.8 contract-length omitted-variable
gap in one pass — but note the distinction: **fees are validation-only** (never fed into
CDE), whereas **contract length is a legitimate baseline confounder** and, once scraped,
*does* enter the §3.2 model.

Both cuts follow the same order: **top-5 first, then 14-league** (Andrew, 2026-07-21) —
clean values give a trustworthy first read; the 14-league extension is a second pass.

Recommended to build **before** the market benchmark: the core needs no new data source
or crosswalk, so it is lower-risk and self-contained.

---

## 8. Resolved decisions (Andrew, 2026-07-21)

1. **Metric name — "Coach Development Effect (CDE)."** Modest by design; pairs with
   "grade" for quality. Used throughout this doc.
2. **Sample — same-club first, movers as a §5.5 robustness pass.** Cleanest attribution
   first; cross-club stability check second.
3. **Cut scope — top-5 first, then 14-league.** Clean values for a trustworthy read,
   then extend.
4. **Transfer-fee scrape — scoped now, in parallel** (not deferred to post-Phase-2). See
   the parallel scrape track in §7 and the §6 external tie-back. Ready for validation the
   moment Phase 2 lands; validation-only, never fed into CDE construction.

No open questions remain; ready to build Phase 1 on the top-5 cut.

## 9. As-built notes
*(filled in as phases land — validation results, the honesty verdict, what shipped.)*
