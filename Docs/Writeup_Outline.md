# Writeup Outline — Football Coach Valuation Model

**Purpose of this document:** a section-by-section skeleton for a professional writeup you
will draft yourself. Every section carries its argument, its target length, the exact
numbers to use, the figures to draw, and the traps to avoid. Nothing here is prose to
copy — it is the scaffolding under the prose.

**Source material already in the repo:**
- `Docs/Summary_of_Findings.md` — the full technical record, organised chronologically by
  milestone (Parts 1–12). This is the *lab notebook*. Mine it for numbers, not structure.
- `Docs/How_It_Works.md` — the plain-language site guide. Mine it for *explanations* of
  mechanisms; the analogies there are already tested on a lay reader.
- `Docs/Session_Log_*.md` — the decision history. This is where the "why we did it that
  way" lives, and it is the richest and least-used material for a professional writeup.
- `Docs/*_Design.md` — pre-registrations. These prove the honesty claims: several
  designs declare in advance what a null would look like. Cite them.

---

## 0. Decisions to make before you write a word

### 0.1 Audience and venue

Pick one. The outline below is built for **(A)**; §14 tells you how to cut it to the others.

| | Audience | Length | Emphasis |
|---|---|---|---|
| **A (primary)** | Technical portfolio piece for sports-analytics / DS hiring | 6,000–9,000 words | Method rigour, validation design, the nulls, engineering |
| B | Public essay / Substack / club-facing | 1,500–2,500 words | The three validations, sacking efficiency, deserved table |
| C | Academic-style report | 8,000–12,000 + appendices | Identification strategy, formal specs, robustness tables |
| D | Executive one-pager for a club | 600–900 words | What it predicts, what it costs to be wrong, what it can't do |

Your project goal document (`Goals_V6.md`) names the audience explicitly: *"a project to
show as proof of this understanding"* to *"future employers"*, with sports analytics in
mind. That is **A**. Write A, then derive B and D from it.

### 0.2 The one-sentence thesis

Write it down before drafting and test every section against it. The defensible version,
almost verbatim from your own conclusion:

> Coaching quality is real, portable across clubs, worth roughly a point and a half per
> season per standard deviation of grade, and it predicts a season the model has never
> seen — but it is a **single number**: four independent attempts to decompose it or find a
> second coach effect all came back empty, and the betting market has already priced it.

Everything in the writeup either supports that sentence or explains why some plausible
alternative sentence is false.

### 0.3 Structural recommendation — reorganise by argument, not by chronology

This is the single most important editorial decision. `Summary_of_Findings.md` runs
Part 1 → Part 12 in the order the work happened. A reader does not care about the order
the work happened; they care whether the number is real. **Reorder to:**

1. Question → 2. Data → 3. Method → 4. **Does it work?** → 5. **What it's worth** →
6. **What it isn't (the nulls)** → 7. What can be described → 8. Products →
9. Engineering → 10. Limits.

Consequences of the reorder you must handle deliberately:
- Parts 1–5 (the model) collapse into §3–§5 below, with the *original 5-league* and
  *14-league refit* results merged into a single current-vintage statement plus a
  robustness note. Do not make the reader relive two dataset expansions.
- Parts 6, 8-Layer-C, 9, 10 (the nulls) **group into one section** (§7). They are
  individually unremarkable and collectively the strongest thing in the project. Scattered
  chronologically they read as a losing streak; grouped they read as a research program.
- Parts 7, 11a, 11b (payoff, event study, forward test) **group into one section** (§6).
  Three designs, one conclusion. This is your centrepiece.

### 0.4 Voice and tense conventions — decide once, apply everywhere

- First person singular ("I built") is correct for a solo portfolio piece. Avoid the
  royal "we" — it reads as padding when the repo is one author.
- Past tense for what you did, present tense for what the model does.
- **Never write "the coach caused"**. The vocabulary that survives scrutiny is
  *"performance above squad-value expectation"*, *"associated with"*, *"predicts"*,
  *"attributable to"* (attributable ≠ caused, and say so once explicitly).
- **Always name the cut.** Every grade, BLUP, or count is either top-5 or 14-league and
  means different things in each. A number without its cut is an error.
- **Always name the units.** PPG vs points-per-season is the most common self-inflicted
  confusion in this project's own docs. Pick points-per-38-game-season for reader-facing
  effect sizes, PPG for model internals, and convert explicitly the first time.

---

## 1. Front matter

**Length: ~250 words.** Title, one-line subtitle, abstract box, and a "what you're looking
at" line (solo project, R, ~20 months of football across 14 leagues, live site).

### Title options
- *What Is a Coach Worth? Measuring Manager Quality Against Squad Value in 14 Leagues*
- *The Residual: Isolating a Coaching Effect from 5,339 Team-Seasons*
- *Coaching Quality Is Real, Portable, and Exactly One Number*

Prefer the third if you are confident; it states the thesis and the limit in one breath,
which is the project's whole personality.

### Abstract beats (in order, one sentence each)
1. Squad market value predicts league points; the gap between the two is where coaching
   would live if it exists.
2. Weighting each player's value by his share of team minutes improves the prediction
   (out-of-sample, significantly).
3. The residual from that model is decomposed into coach and club random effects; the
   coach component is significant and, in the top-5 cut, larger than the club's.
4. The resulting per-coach grade is validated on three independent designs, including a
   true future season the model never saw.
5. Four attempts to find *more* than that number — style, player-type fit, player value
   growth, and an edge over the betting market — all failed, and those nulls are reported.
6. Everything ships as a public site; all of it is reproducible from cached scrapes.

---

## 2. The question, and why it is hard

**Length: 600–800 words.** This section earns the reader's attention; it is not throat-clearing.

### 2.1 The motivating asymmetry
Player analytics is a mature public field; coach analytics is not. Clubs make the single
most expensive personnel decision in football — a manager hire — with the least
quantitative support. Open with that gap, not with "football is a popular sport".

### 2.2 Why coaching is hard to measure (the identification problem)
State the problem crisply, because the rest of the writeup is your answer to it:
- A coach's output (points) is overwhelmingly determined by an input he did not choose
  (the squad).
- Coaches are **not randomly assigned** — good coaches are hired by good clubs, which is
  the confound that kills naive comparisons and that you test directly later (§7.5).
- The sample per coach is tiny: a career is often 3–10 stints of 10–40 games each.
- Results are noisy at the season level, and *very* noisy at the caretaker-stint level
  (the variance function you estimated: `Var(stint) ≈ 0.014 + 1.50/n`).

### 2.3 The hypothesis, stated so it could have failed
From `Docs/Hypothesis.md` and `Goals_V6.md`. Include the **pre-declared success
criterion** — you wrote one before starting, which is unusual and worth showing:

> success = a working coach ranking whose coach variable significantly reduces model error,
> *or* a sufficient disproof plus a replacement hypothesis.

Also list the three risks you named in advance (causation assumption, the ceiling effect,
coach-data availability) and forward-reference where each is addressed. Naming risks
before you hit them is the cheapest credibility in the document.

### 2.4 What this writeup claims and does not claim
A four-line box. Claims: measurement, portability, forecast utility. Does not claim:
causal mechanism, tactical explanation, transfer-market or in-play exploitability.

---

## 3. Data

**Length: 700–900 words + 1 table.** Resist the urge to make this a catalogue. The reader
needs scope, provenance, and the *judgement* you applied.

### 3.1 Sources
- **Transfermarkt** (custom R scraper): squad market values, per-player minutes, coach
  appointment dates, match results. IDs are URLs, not integers — mention once as an
  engineering choice with a cost (string joins) and a benefit (no id-mapping layer).
- **SofaScore** (headless-Chrome scraper): per-match player statistics, formations, shot
  coordinates, heatmaps — used for the style/archetype layers only.
- **football-data.co.uk**: closing odds, for the external benchmark.

### 3.2 Scope table (current vintage — use these numbers)

| | value |
|---|---|
| Leagues | 14 |
| Seasons | 2005/06 – 2025/26 (21) |
| Team-seasons | 5,339 |
| Coach stints | 8,642 |
| Distinct coaches | 2,445 (1,006 with a BLUP) |
| Clubs | 505 |
| Graded coaches | 566 (14-league) / 224 (top-5) |
| SofaScore span | 2015/16 – 2025/26, big-5 only |
| Odds benchmark | 51,977 matches, 2012/13–2025/26, 13 leagues |

### 3.3 The exclusions — write this as a *findings* subsection, not an appendix
Six leagues were dropped, and the reasons are individually interesting. Cover:
- **Argentina (AR1N)** — Transfermarkt silently ignores `saison_id`, returning current
  squads for every historical season. Confirmed data corruption. This is a good story: it
  is the kind of defect that produces a beautiful, meaningless result if unnoticed.
- **Brazil, MLS** — the minutes-weighted metric *actively hurts* prediction, because
  multi-competition rotation (Brazil) and salary-cap roster construction (MLS) break the
  assumption that league minutes reflect squad deployment. You dropped leagues for
  violating a modelling assumption, not for being inconvenient — say so.
- **Sweden, Japan, Mexico** — coverage sparsity and non-comparable season formats.

Frame the whole subsection with the principle: *the metric encodes an assumption, and a
league that violates the assumption is out of scope, not evidence against the metric.*

### 3.4 Scraping conduct
One short paragraph, and do include it: deliberate rate limiting (2–3s jittered, rest
periods, exponential backoff on 429/403, fully resumable, permanent-404 recording). It
demonstrates you have run a long-lived scrape responsibly, which hiring managers read as
operational maturity. Mention the one incident honestly (a ~70-request burst during
development earned a ~24-hour IP block; steady pacing never has).

---

## 4. Method

**Length: 1,200–1,600 words + 1 diagram.** The core of the technical case. Structure it as
a chain the reader can hold in their head: **value → expectation → residual → coach →
grade.** Draw that chain as a figure (Figure 1) and refer back to it.

### 4.1 Step 1 — Minutes-weighted squad value
- Definition: per player, `market_value × share_of_team_minutes`, summed.
- The intuition in one sentence: *a €60m striker who played 400 minutes is not a €60m
  contribution to this season.*
- Normalisation within league-season; log transform (and why: value's effect on points is
  multiplicative, not additive).
- The imputation edge case (teams with no minutes data get a within-season regression
  fill) — mention, it is a place a reader will look for a hole.

### 4.2 Step 2 — Expected points (the M3 model)
- Spec: `points_per_game ~ log(norm_weighted_value) + league + is_b_team`.
- Response is **points per game**, not points, because the 14 leagues play 22–46 games.
- League fixed effects; no season fixed effects (state this and flag as Limitation).
- Note the deliberate simplicity: the baseline exists to be *beaten cleanly*, and every
  added covariate is a place for leakage to hide. That choice pays off in §7.4.

### 4.3 Step 3 — The residual
- Definition, distribution (mean 0, SD ≈ 0.24 PPG, approximately normal, no
  heteroskedasticity across value tiers — that last point matters: the model is equally
  reliable for promoted clubs and elite clubs).
- Lag-1 persistence r ≈ 0.20 — a modest club effect exists, so the residual is *not*
  simply a stable club-quality proxy. This is the sentence that pre-empts the most obvious
  objection.

### 4.4 Step 4 — Attribution to coaches
- Match-level assignment using Transfermarkt appointment dates; ~99.4% of matches
  attributed; matches in coverage gaps dropped from *both* actual and expected (symmetry
  is the point).
- Stints, not seasons, are the unit — mid-season changes are 30% of some seasons.
- The `coach_id` vs `coach_name` invariant: **id is identity, name is a label**. Include
  the Ivan Juric / "Ivan Jurić" incident (§10.3) — it is a genuinely instructive bug.

### 4.5 Step 5 — The mixed model and BLUPs
- Spec: `partial_residual_ppg ~ (1|coach_id) + (1|club_id)`, stint-weighted by games.
- **Why games-weighted**, with the estimated variance function `0.014 + 1.50/n` and the
  out-of-sample justification (games-weighted BLUPs predicted held-out stints better,
  r 0.13 vs 0.09). Also state the honest cost: stint length is itself an outcome, so
  games weighting slightly downweights each coach's truncated disasters. You tested the
  trade and it came out in favour; report both sides.
- BLUP shrinkage explained in one plain sentence: *a coach with two good months is pulled
  toward the average; a coach with ten good seasons is not.*

### 4.6 Step 6 — Grades and the certification bar
- The curve, and the **display certification bar** (≥109 career games in the cut, or
  FDR-significant). Critically: the bar is **presentational**, not a model change —
  sub-bar coaches keep their BLUP and stay in the model but are not certified.
- Why every score-side "fix" was rejected: weight floors, truncation-share penalties and
  weighted-vs-unweighted gap penalties **all degraded out-of-sample prediction**, and the
  gap penalty even carried the opposite sign. This is a strong methodological beat — you
  chose not to correct a model that the data said was already right, and handled the
  presentation problem in presentation.
- The motivating case (Andrea Mandorlini, 108 games, briefly 7th on three discounted short
  stints) makes it concrete.

### 4.7 The two cuts
Top-5 vs 14-league, why both exist, why grades are never shown without their cut label.

---

## 5. Result 1 — The metric works

**Length: 400–600 words + 1 table + Figure 2.**

### Numbers (refreshed on the current 2005–2025 dataset, 5,332 rows — see §13)

| Metric | Baseline (raw value) | Enhanced (minutes-weighted) |
|---|---|---|
| In-sample R² | 0.629 | **0.674** |
| In-sample RMSE (PPG) | 0.258 | **0.241** |
| Leave-one-season-out RMSE | 0.258 | **0.241** |

- LOSO improvement **0.0164 PPG**, paired t over 21 folds, **p = 7.6 × 10⁻⁷**, 95% CI
  lower bound 0.0116.
- Leave-one-**league**-out is the second, harder test — re-run it (the published figure is
  p = 0.0001 on the ≤2024 vintage; see §13 for the caveat about the held-out league's
  fixed effect).
- Convert for the reader: 0.016 PPG ≈ **0.6 points per 38-game season** of error reduction
  — small, and that is the honest framing. The point is not the size; it is that the
  effect is consistent, directional, and survives two orthogonal CV schemes.

### Beats
- A combined model (raw + weighted) adds nothing over weighted alone — the weighting is
  not extra information bolted on, it is a better version of the same information.
- The Serie A exception (enhanced underperforms baseline in-sample there) — report it in
  the text, not just the limitations list. It supports the Brazil/MLS exclusion logic:
  rotation-heavy contexts weaken the minutes signal, and Serie A is the mildest case of the
  same disease.

**Figure 2:** predicted vs actual PPG scatter, both models, shared axes, y = x reference.
`charts.js expectedVsActual()` already does exactly this — reuse the design (shared domain,
PPG not total points).

---

## 6. Result 2 — The residual contains a coach, not just a club

**Length: 600–800 words + 1 table.** This is the hypothesis's load-bearing claim.

### The decomposition (current vintage — refreshed 2026-07-28)

| Cut | Stints | Coaches | Coach var % | Club var % | LRT |
|---|---|---|---|---|---|
| 14-league, 2005–2025 | 8,642 | 2,445 | **4.1%** | 3.8% | χ² = 35.8, df = 1, **p = 2.2 × 10⁻⁹** |
| Top-5, 2005–2025 | 3,048 | 890 | **5.4%** | 4.8% | χ² = 19.8, df = 1, **p = 8.7 × 10⁻⁶** |

### Beats, in this order
1. **The coach term is significant** — the null "coach identity explains nothing beyond
   club and squad value" is rejected decisively in both cuts.
2. **Coach variance exceeds club variance in both cuts** (it was tied in the 14-league cut
   before the 2025/26 refit — say so; a result that moved is more credible than one that
   never does). The interpretation is the portability claim: the effect follows the
   manager more than it stays at the club.
3. **Residual variance is ~90–92%** and you should say so loudly. Coaching is a small
   share of football outcomes. A writeup that oversells this number is not credible; one
   that states it plainly and then shows the small share *predicts the future* is.
4. Why the top-5 cut shows a bigger coach share: elite coaches move between clubs and
   leagues, so portability is observable. In broader datasets, locally-anchored coaches at
   dominant clubs (Dinamo Zagreb, Legia, Brugge) push signal into the club term.
5. **Individual significance is rare** — after FDR correction only a handful of coaches
   clear it individually. Frame this correctly: it is a **sample-size limit, not a model
   failure**, and it is why the project ships shrunken grades with a certification bar
   rather than a confident 1-to-2,445 ranking.

### Face validity, kept short and used as illustration only
Top of the ranking (Guardiola #1 in both cuts, Ferguson, Conte, Allegri, Klopp); the
notable negatives (Bielsa, Di Francesco, Lampard); the most-portable case (Claudio
Ranieri, 17 stints across 11 clubs). One paragraph. **Explicitly label this as face
validity, not evidence** — the evidence is §7.

---

## 7. Result 3 — Three independent validations (the centrepiece)

**Length: 1,200–1,500 words + 1 summary table + Figures 3–4.** Give this the most space
in the document. It is the section that separates this project from a correlation study.

### 7.1 Open with why three
Each design is vulnerable to something the other two are not. Say this before the results,
so the reader reads the three as a triangulation rather than as repetition.

### 7.2 Validation 1 — Out-of-sample forecast of new coach–club pairings
- Design: leave-one-season-out over 10 folds; forecast stint PPG for **877 brand-new
  coach–club pairings** (no stint at that club the previous season); layers added one at
  a time; **pre-registered acceptance rule** (a layer ships only if it does not hurt
  out-of-sample RMSE).
- Result: quality BLUP layer improves RMSE 0.3026 → 0.2993, **p = 0.0027** (realized
  framing), **p = 0.017** (pre-hire framing, which uses only information available before
  the hire), 7 of 10 folds improved.
- **Publish the one-sided p and say it is one-sided**, because the pre-registration
  declared a directional acceptance rule. Two-sided would be 0.0054 — the wrong test, not
  a stricter one. This is a small point that a careful reader will respect enormously.
- Vulnerability: coach and club are still compared across different squads.

### 7.3 Validation 2 — The manager-change event study (within-club natural experiment)
- Design: **3,043 manager changes, 436 clubs, 2005–2025**. First-difference within club,
  so the club's squad-value level is swept out entirely. Leakage rule: each coach's grade
  is taken **as-of the outgoing coach's season**, which excludes both the before- and
  after-period results from both grades — an expanding-window refit of the whole mixed
  model, once per cutoff.
- Result (**level spec**, `resid_in ~ blup_in + resid_out`): **+1.17, p = 0.0015**;
  **+0.91–1.0, p = 0.002** in a club-random-effect games-weighted mixed model; strongest
  for **mid-season crisis hires (p = 0.0023)**, weak for considered summer moves.
- **Report the difference spec as a confounded null and explain why**: clubs fire a
  well-graded coach precisely during an unlucky dip, which reverts regardless of who
  arrives (outgoing performance carries a coefficient of −0.95 — regression to the mean is
  the dominant force in any manager change). This is the most sophisticated single
  paragraph available to you; do not cut it. The practical lesson is sharp and quotable:
  **hiring is about the absolute quality of who you bring in, not how he compares to the
  man you are replacing.**
- Vulnerability: hires are not random; clubs choose whom to hire.

### 7.4 Validation 3 — The 2025/26 forward test (true future holdout)
- Design: model **frozen at 2024** (M3 coefficients and M5 BLUPs both), then used to
  predict a freshly-scraped season it had never seen (252 team-seasons, 14 leagues).
- Q1 (does the structure generalise out-of-time?): **R² = 0.721, r = 0.852, mean error 6.3
  points per team-season**, and it still beats raw squad value by **0.0133 PPG** — the same
  margin the original cross-validation found, on a genuinely future year.
- Q2 (do the grades predict the future?): prior grade predicts new-season overperformance,
  slope **+1.90, p = 0.0024** (all 435 stints), **p = 0.0036** on the 219 graded-only
  stints. Adding the grade lowers holdout RMSE 0.223 → 0.220.
- **Be scrupulous about the vintage problem.** The grades currently published on the site
  are a *later* vintage that has since absorbed 2025/26; the tested grades were the
  2024/25 vintage. Your engineering fix (a byte-snapshot BLUP vintage file the test reads,
  which errors rather than falling back to the live file) is exactly the sort of detail
  that proves rigour. Include it.
- Vulnerability: n of 1 season.

### 7.5 The confound you tested directly rather than waving away
The obvious objection to all three: *good coaches are hired by big clubs, so you're
measuring club size.* You tested it. Split club size into between- and within-coach parts:
- between-coach slope **+0.00087 (t = 4.2)** — the confound, as expected;
- within-coach slope **−0.00085 (t = −5.0)**; coach fixed-effects cross-check p = 1e-7.

Mis-specification would require a **positive** within-coach slope (the same coach
overperforming more once he moves to a bigger club). The sign is wrong for
mis-specification, so the correlation is composition — good coaches at big clubs, effect
genuinely theirs. Also report the robustness: refitting with a spline value term leaves
the ranking essentially unchanged (rank r = 0.98, Guardiola still #1) and shrinks the
confound only 0.21 → 0.16, and the one real residual (linear-in-log slightly
under-predicts the single biggest club per league, worth ~0.02–0.04 PPG to permanently-elite
coaches, no reordering).

**Give this its own subsection with a heading.** It is the objection a reviewer will raise
first, and answering it before it is asked is worth more than any additional result.

### 7.6 Summary table (build it; it is the figure people will screenshot)

| Test | Design type | n | Result | p |
|---|---|---|---|---|
| Recommender payoff | Out-of-sample forecast, new pairings | 877 pairings / 10 folds | RMSE 0.3026 → 0.2993 | **0.0027** |
| Manager-change event study | Within-club natural experiment | 3,043 changes / 436 clubs | slope +1.17 | **0.0015** |
| 2025/26 forward test | True future holdout | 435 stints (219 graded) | slope +1.90 | **0.0024** |

### 7.7 What the number is worth, in football units
Convert once and use consistently: **≈1.4 points per 38-game season per SD of grade** on
the forward test, **≈0.7** on the event study (the event-study estimate is lower because a
single partial-season outcome is very noisy). Give the reader the range honestly rather
than the flattering endpoint.

**Figure 3:** grade vs realized 2025/26 overperformance, dot area = games played, with the
games-weighted fit line and **tertile means**. Note the design lesson explicitly: the raw
correlation is r = 0.166 and the chart looks unflattering — without the group means a
validated result reads as a null; without a "single dots mean little" caption the trend
line oversells it. Also: never draw the group error bars (they render as 2px stubs at
this scale) — state them in words.

---

## 8. What the model is *not* — five nulls

**Length: 1,200–1,600 words.** Argue, in the opening line of the section, that this is the
most valuable part of the project. Then earn that claim.

### 8.1 The framing paragraph
Five separate attempts, on four different data slices, to find either a **decomposition**
of the coach number or a **second, independent** coach effect. All five failed. That
consistency is the finding: the coach signal this data can measure is one number, and the
project's refusal to ship the others is why the one it does ship can be trusted.

### 8.2 Null 1 — Coach × player-type fit (M6)
- The *global* effect is real and got stronger with more data: squad archetype composition
  predicts overperformance, **χ² = 26.1, df = 11, p = 0.0062** (strict-lagged sensitivity
  **p = 0.0003**), with the **wide-creator** share dominant (coef 0.76, t = 3.48) — roughly
  +2.8 points/season per 10pp of minutes shifted from destroyers to wide creators.
- The *individual* effect is not: 0 of 1,704 within-coach correlations survive FDR;
  per-coach random slopes give **LRT p = 0.449**.
- The right reading, stated plainly: **squad composition matters; we cannot show that
  *this coach* is the one who benefits from it.** Descriptive pairs (Gasperini with
  man-marking centre-backs, r = 0.89; Vieira with destroyers; Pochettino negative with
  pressing forwards) recur across specifications and have face validity — present them as
  colour, explicitly labelled exploratory.
- Include the 11 archetypes and their exemplars as a table; it is the most immediately
  legible artefact in the project.

### 8.3 Null 2 — Style → quality (Layer C). *The best-written null available to you.*
This deserves the most space of the five, because it is a complete cautionary tale.
- Every raw association is large and FDR-significant: defensive solidity **+0.64**, shot
  volume +0.53, possession +0.52, lineup stability −0.37. Say explicitly: *this would have
  been the most shareable content the project ever produced.*
- Four checks, each killing a different group:

  | check | casualties |
  |---|---|
  | consistency across four specs | pressing, directness, width, set-piece reliance |
  | separable from club size? | possession (**r = 0.86** with mean club-value percentile), shot volume, solidity |
  | does the axis restate the outcome? | chance quality, solidity, shot volume |
  | within- vs between-coach | **lineup stability — sign reverses** |

- The three traps, each worth a paragraph:
  - **The suppression trap.** The all-axes multivariable reports club level at β = −0.60
    ("big clubs underperform"), while the bivariate is +0.39. The generalisable tell:
    possession's coefficient *rises* under a club control (0.517 → 0.568), which no genuine
    confound removal does.
  - **A Simpson's paradox in the axis most likely to be believed.** Between coaches,
    rotators grade higher (−0.373, q < 0.0001, in all four specs). Within a coach,
    *stability* associates with better seasons (+0.131, p < 0.0001). The between-coach
    version is club sorting — the heaviest rotators are Heynckes, Tuchel, Allegri, Luis
    Enrique, all at clubs with European fixture loads.
  - **Outcome restatement.** Defensive solidity is built from shots conceded. "Solid teams
    overperform" is a restatement, not a discovery.
- Only rigidity survives, and only because it is a career constant with no within-coach
  variation — so the decisive check **cannot run on it**. Record it as "between-coach only;
  untestable", not as a pass. That distinction is the section's moral.

### 8.4 Null 3 — The Coach Development Effect (does value growth repeat?)
- The one genuinely *new outcome* the project tried: log market-value growth against a
  player's own age/price/position/momentum baseline, attributed through the same spine,
  with **player, club and coach** random effects.
- It passes the orthogonality gate (93–96% of variance orthogonal to the points BLUP — so
  it is not points re-expressed) and **fails repeatability**: even/odd split-half
  **r = −0.07 / +0.05**, indistinguishable from zero in both cuts.
- The trap worth naming: the in-sample coach variance component looks impressive (18–22%,
  LRT p < 1e-60) and is meaningless, because it does not repeat within a coach's own
  career. It measures *which players happened to blow up on his watch*. The player random
  effect dominates (44–62%).
- Two by-products worth keeping: the clean **player**-development residual (which ships as
  a scouting leaderboard), and a corroboration of §8.2 from an independent direction —
  attacking/creative archetypes over-appreciate relative to baseline (wide creator +0.07),
  defensive fullbacks least (−0.02).
- The one real signal is a **club** property, not a coach one, and only in selling leagues
  (consecutive-regime r ≈ +0.10, p = 2e-4, entirely outside the big five). Include the
  **method trap**: the naive club test gives a spurious +0.40 because a mid-season-change
  player-season is shared between two managers; collapsing to the primary coach removes it.

### 8.5 Null 4 — The betting market (the external test)
- Framing: every prior validation is internal, against your own baseline. The fair
  sceptical reply is *"show me you beat, or add to, the market."* The closing line already
  prices both the squad and the manager, making it the hardest and most credible baseline.
- Pre-registered as confirmatory, with the null declared in advance as a legitimate result.
- Result: the leakage-free walk-forward forecaster is **worse than the closing line**
  (log-loss 1.015 vs 0.979, market better in all 11 leagues) and adds nothing beyond it —
  value **p = 0.29**, **coach BLUP p = 0.96**, **p = 0.68** even in the pre-declared
  low-profile-manager subgroup. P&L −6.6% ROI at closing prices (CI [−8.2%, −5.1%]),
  −7.8% at achievable prices.
- **Note the direction of travel**: adding 2025/26 moved every p *further* from
  significance. A weakening result on added data is what a real null looks like; a
  strengthening one would have been the signal to re-examine.
- The honest reading: a near-efficient market pricing your signal is **external
  corroboration that the signal is real**, and simultaneously the ceiling on exploiting it.

### 8.6 The leakage story — give it its own heading and treat it as a set piece
The naive forecaster used each season's *own* Transfermarkt squad value instead of the
prior season's. It showed an incremental coefficient beyond the market of
**+0.224, p = 1 × 10⁻²¹**. It would have been the project's headline. Swapping in
strictly pre-season value — a one-line change — collapsed it to **+0.023, p = 0.31**.
Transfermarkt's in-season valuation had already absorbed that season's results.

Draw the general lesson: **against a near-efficient benchmark, a few percent of leaked
variance is the difference between a spurious 10⁻²¹ and the truth.** This is the single
most persuasive paragraph in the whole project for a technical reader, because it is you
catching your own hand in the till and reporting it.

### 8.7 Null 5 — The recommender's fit and deployment layers
Brief. The layers pass their *mechanical* gates emphatically (fit to an incoming coach's
shapes predicts a player's minutes share beyond market value, t = 26.9; positive in 100%
of stints) but add nothing to hiring forecasts, and ship as clearly-labelled exploratory
columns. One informative interpretation to offer: **clubs already hire for fit**, so
survivorship pushes the measurable fit signal toward zero — the disastrous mismatches were
never hired, so they are not in the data.

---

## 9. What *can* be described honestly

**Length: 700–900 words + Figure 5.** The point of this section is the *gradient*: three
layers at deliberately different trust levels, each labelled with its own.

### 9.1 Layer A — where the edge comes from (defensible; ships)
- Method: refit M3 with goals-for-per-game and goals-against-per-game on the **same
  right-hand side**, attribute through the identical M5 path (same coverage filter, same
  weighting, same shrinkage, same FDR rule — reused verbatim, not re-implemented).
- Why it is defensible: it re-slices a residual the project already trusts and makes no new
  attribution leap.
- Tie-back: goal-difference edge vs the points residual **r = 0.86–0.87**; at coach level
  **r = 0.82** against the published BLUP.
- The finding worth stating on its own: **the coach effect is stronger on goals than on
  points** — 14-league LRT χ² = 160 (offence) and 60 (defence) vs 28 for points. Goals-for
  is a lower-noise coach signal, which is a genuinely useful pointer for future work.
- The instructive exception: **Simeone**, whose goal edge is ≈ 0 (−0.03) despite a B grade —
  his overperformance is in converting goal difference into points, which the split
  describes but does not explain.

### 9.2 Layer B — the style fingerprint (descriptive-clean; ships, carefully labelled)
- Nine axes, each an equal-weight mean of member z-scores, z-scored within league × season.
  Deliberately **not** a PCA and not a fitted weighting: nothing is trained against an
  outcome, so there is nothing to overfit.
- Two caricatures the data corrected — use both, they are the best colour in the project:
  - **"Guardiola presses high" resolves to *height*, not intensity.** He is ≈0 on per-match
    pressing intensity and +1.5 SD on pressing height: City make few defensive actions
    because opponents rarely have the ball, yet win it high. The two measures correlate
    only r = 0.38 and are different traits.
  - **"Simeone: low possession, low block" is not supported.** 74th percentile possession,
    dead average pressing height. What *is* supported: solidity (94th), narrowness (13th on
    width), shot selection (84th).
- **The main result, and it is a caveat that became a finding:** team style is mostly the
  **club's**, not the coach's. Club variance beats coach variance on **7 of 9 axes**
  (possession 69% club vs 12% coach); the squad's archetype mix alone explains 69% of
  possession, 54% of shot volume, 51% of directness; a club under two different coaches
  (r = 0.82) looks more alike than a coach at two different clubs (r = 0.55), and after
  residualising on archetype mix the travel correlations collapse (0.55 → 0.17).
- **Only two axes survive as genuinely the coach's**: lineup stability (rotation is a
  decision, not a squad property) and pressing intensity.
- Include the method caveat that cuts against your own headline (travel-vs-persist is not
  like-for-like, because consecutive coaches at a club inherit the same squad; the variance
  decomposition is the better instrument and it agrees on 7 of 9). Publishing the weakness
  of your own supporting check is exactly the habit this writeup should display.

### 9.3 The xG cut — measured, and deliberately not shipped
Four measures split process from outcome: creation and prevention (process) vs finishing
and shot-stopping (outcome). Report:
- The **cross-source tie-back** — SofaScore-built xG cut vs Transfermarkt-built goals cut,
  **r = 0.960 / 0.981 over 605 stints**. Two independently-sourced pipelines agreeing is the
  strongest single integrity check in the project, and it is the thing that would break
  first if the team mapping or attribution regressed.
- Repeatability (lag-1, same club, 247 pairs): creation 0.353, prevention 0.275, finishing
  0.246, shot-stopping **0.033 (p = 0.61 — pure noise, exactly as predicted)**.
- Finishing persisting more than assumed is most plausibly squad continuity, not coach
  skill — a reason to keep labelling it unreliable, not to promote it.
- **Why it is not on the site**: 605 stints, 310 coaches, 89 with ≥3 stints, and **zero
  FDR-significant on all four measures**. It is a recent-form lens; a coach page would
  flatten it into a career verdict.
- Two data defects worth recording (they show the checking habit): 28 of 7,082 xG-era
  events carry a full complement of shots but are missing their goal shots (0.4%, almost
  all 2023) — so an event counts only if its shotmap reconciles with the scoreline on both
  sides; and own goals sit in the shotmap credited to the benefiting side with no xG,
  landing wholly in finishing, which is where they belong.

---

## 10. What was built (products)

**Length: 600–800 words + screenshots.** Keep it brisk; this is a tour, not a manual. For
a portfolio piece, screenshots do more work than prose.

- **The site** — per-coach, per-team, per-league pages; grades never rendered without their
  cut label; the honesty gradient enforced in what each page is *allowed* to show.
- **The coach recommender** — "who is the best coach for this squad?", decomposed into
  quality (validated) / fit (exploratory) / deployment (exploratory), with career-history
  plausibility filters that are never mixed into the score.
- **The squad-fit gap drawer** — which of a squad's value a coach's usual shapes leave
  idle, expressed **in euros and slots, never in points**. Include the design lesson: the
  computed gap scalar is deliberately *not displayed* because QA showed it mis-orders the
  value-max anchor and doesn't reconcile with the strand list.
- **The team builder** — build any XI on a drawn pitch, get similarity-based coach
  suggestions computed client-side, numerically identical to the R implementation (verified
  against a fixture). Never shows predicted points for a fantasy XI — outside the model's
  support.
- **The deserved table** — the residual restated as league standings. The most visceral
  version of the whole project: **Leicester 2015/16 finished 1st and deserved 10th;
  Chelsea that year deserved 1st and finished 10th.**
- **The player-development leaderboard** — the one durable by-product of the Part-9 null.
  Describes *players*, never coaches, and is labelled as such.
- **Sacking efficiency** — the most quotable application, and it belongs either here or at
  the end of §7. Of 1,748 mid-season sackings, **16.5% fired a coach who was actually
  overperforming his squad**; firing that overperformer **backfires** (replacement's
  performance-vs-expectation −0.16 PPG, improves on the sacked man only 35% of the time),
  whereas replacing a genuine underperformer is followed by the expected bounce (+0.35,
  79%). The model surfaces the game's own catalogue of regret from the residual alone —
  Birmingham firing an overperforming John Eustace (+0.47) for Wayne Rooney (−0.50) en
  route to relegation; Birmingham firing Gary Rowett for Gianfranco Zola.

---

## 11. Engineering and reproducibility

**Length: 700–1,000 words.** For audience A this section is not optional — for many
readers it is the *most* informative section, because it shows how you work. Nothing like
it exists in `Summary_of_Findings.md`; you will be writing it fresh.

### 11.1 Architecture
Two-tier data layer (`xx_raw_*` scrapes, `xx_data_*` reads cache first) across two
independent sources; a pure analysis layer that never scrapes; a publishing layer that
writes only to `site/`. Draw it (Figure 6). The invariant worth stating: **analysis code
cannot make a network call**, so any analysis is reproducible offline from the caches.

### 11.2 The pipeline as code, not prose
`refit_pipeline.R` replaced a written recipe in a session log. Note the validation that
made the replacement safe: **pinned to ≤2024 it reproduced the hand-run results
bit-identically** (14-league max |numeric delta| = 0; top-5 ≤ 1e-11, lme4 optimizer noise).
That is how you retire a manual process responsibly.

### 11.3 The vintage discipline
The forward test reads a **byte snapshot** of the BLUPs as of the 2024 fit and errors out
rather than falling back to the live file; the refit driver refuses to run if the snapshot
is missing. Explain the failure it prevents: refitting would have made the test circular —
scoring grades against the very season they were estimated on — **and it would still have
printed a small p-value.** A silent-success failure mode is the kind worth engineering
against.

### 11.4 A catalogue of bugs that would have been invisible
Pick three or four; each is a short paragraph and each teaches something different.
- **One coach, two spellings.** Transfermarkt re-spelled Ivan Juric as "Ivan Jurić" on his
  2025/26 page; the profile URL was unchanged. Grouping by `(id, name)` split one career
  into two ranked rows while the mixed model kept one — two tables silently disagreeing
  about who existed. The crash was the lucky part; the quiet failure mode is a coach
  appearing twice with half a career each. Fix: canonical names resolved per id from the
  most recent stint, applied at the root so every downstream layer inherits it.
- **The archetype relabelling hazard.** K-means cluster indices are arbitrary, so
  re-clustering on a new season could permute them and silently mislabel every downstream
  layer with nothing failing. Checked properly rather than assumed: recovered the previous
  cluster assignment from git, cross-tabulated old vs new within each position group,
  confirmed 97–100% diagonal agreement and an identity mapping on all 11.
- **The half-rendered page.** A deleted-but-still-referenced variable threw a
  ReferenceError inside an unhandled async render, so a page drew its header and then
  silently appended nothing. Nothing caught it: no console error surfaced, `node --check`
  passed, and the smoke test only asserted a character count that 777 characters of
  half-rendered page cleared. Fix: a render checker that installs `error` **and**
  `unhandledrejection` handlers before page scripts evaluate and asserts a per-page
  minimum card count — a contract, not a guess.
- **The `team_ss_id` trap.** SofaScore's per-match player rows carry the player's club *at
  scrape time*, which matches the actual match side only **41.5%** of the time. Every
  team-side derivation goes through the event's home/away ids instead.

### 11.5 Working with an AI agent
Worth one honest paragraph, given it was an explicit project goal. The mechanism that
actually worked: a large, continuously-maintained `CLAUDE.md` that records **binding
verdicts and traps**, not code structure — so that a null stays a null, a rejected
approach stays rejected, and a data quirk does not have to be rediscovered. Frame the
lesson as *what an agent's context should contain*: decisions and their reasons, because
the code is already readable and the reasons are not.

### 11.6 Reproducibility summary
One short block: cached scrapes, a single season knob (`xx_last_data_season`) that every
layer derives from, one driver script per stage, endpoint acceptance tests that fail loudly
if a downstream layer was not re-run (the grade-history endpoint check reproduces the live
grades at max |Δ| = 0.00e+00), and a documented roll-forward procedure for next season.

---

## 12. Limitations

**Length: 500–700 words.** Do not dump all 15 from `Summary_of_Findings.md`. Select the
**six or seven that a sceptic would actually raise**, write each as 2–4 sentences, and
state for each whether it is bounded, tested, or open.

Recommended set:
1. **Coaching is ~5% of the variance.** The effect is real and small. Everything downstream
   inherits that ceiling.
2. **Individual coaches mostly aren't individually significant.** The ranking is a set of
   shrunken estimates with a certification bar, not a confident ordering of 2,445 people.
3. **Value endogeneity.** Transfermarkt values partly reflect past performance, so strong
   year-1 coaching may raise the year-2 baseline and compress residuals for long-tenured
   coaches. Related: the **Year 2 dip**, a consistent but statistically inconclusive
   pattern with two indistinguishable explanations (new-manager bounce vs value inflation).
4. **Early-season sparsity in smaller leagues.** Give the most extreme case concretely
   (Kalmar FF 2005: 26 of 27 players with no recorded value, producing an artefactual
   +2.02 PPG residual). State the ≥80% minutes-coverage filter as the mitigation.
5. **Selection into hiring.** All three validations observe real appointments; none
   randomises. The within-coach club-size test (§7.5) bounds the worst version of this, but
   does not eliminate it.
6. **Scope.** 14 European leagues; the excluded leagues are excluded for principled reasons
   that also limit generalisability. SofaScore-dependent layers are big-5 and 2015/16+ only.
7. **Single-source dependence.** Squad values are one vendor's estimates. The xG
   cross-source tie-back (r = 0.96/0.98) is the only genuine second-source check in the
   project.

---

## 13. Conclusion and next steps

**Length: 400–600 words.**

### 13.1 Restate the thesis with the evidence attached
Not a summary of sections — a single paragraph in which every clause carries its number.
Your existing final sentence is close to right and worth rewriting rather than replacing:

> Coaching quality is real, portable, measurable, useful for forecasting a hire against a
> squad-value baseline, validated on a within-club natural experiment and a true future
> season, and already priced by the market; it is a single number; and this data cannot yet
> say what it is made of.

### 13.2 Return to the pre-declared success criterion
You wrote the criterion before you started (§2.3). State whether it was met, in its own
terms. It was: the coach variable significantly reduces out-of-sample error. Note that the
hoped-for 25% variance reduction was **not** achieved and say so — the honest number is a
few percent, and reporting the miss against your own target is worth more than quietly
dropping the target.

### 13.3 What you would do next, ranked by expected value
- **Goals, not points, as the response.** Layer A found the coach effect is far stronger on
  goals (χ² = 160 vs 28). That is the highest-value known lead in the project.
- **A matchday-frozen value snapshot**, which would let the market benchmark be re-run
  without the season-level valuation compromise.
- **Contract length and transfer fees**, the two named open gaps in the value-growth work.
- **More seasons for the xG cut** — the only null that failed on power rather than on
  substance.
- **A hiring-decision dataset** (shortlists, not just outcomes), which is the only way to
  break the survivorship problem that flattens the fit signal.

---

## 14. Cut-downs and variants

- **Public essay (B, ~2,000 words):** §2.1 hook → §4 method in 300 words with the Figure-1
  chain → §7 the three validations → §10 sacking efficiency + deserved table → §8.6 the
  leakage story as the closer. Drop §9, §11, most of §12.
- **Club-facing one-pager (D):** what it predicts (§7.7 effect size), what it costs to get
  a hire wrong (§10 sacking efficiency), what it cannot tell you (§8 in three lines), one
  worked example on a real squad.
- **Academic (C):** promote §7.5 (identification) to its own section directly after
  method; move all robustness tables to appendices; add formal specifications for M3, M5,
  and the event-study first-difference design; expand the pre-registration story.

---

## 15. Figure inventory

Build these six; the site's `charts.js` already implements four of them and the design
decisions embedded there are worth preserving.

| # | Figure | Notes |
|---|---|---|
| 1 | The chain: value → expectation → residual → coach → grade | Hand-drawn diagram; anchors §4 and gets referenced throughout |
| 2 | Predicted vs actual PPG, both models | Shared axes, y = x reference, PPG not total points |
| 3 | Prior grade vs realized 2025/26 overperformance | Dot area = games; games-weighted fit line; **tertile** means (not quartiles); error bars in words, not drawn |
| 4 | Coach vs club variance shares, both cuts | Simple paired bars; carries the portability claim |
| 5 | A style radar with its honesty label | Percentile, never raw SD; one hue, not a diverging good/bad ramp; the label must say "the teams he coached" |
| 6 | Architecture diagram | Two sources → two-tier cache → analysis layers → publishing layer |

Optional seventh: the deserved-table extract (Leicester/Chelsea 2015/16) as a small table.
It is the fastest way to make a lay reader understand the residual.

---

## 16. Numbers to verify before you publish

`Summary_of_Findings.md` was last updated **2026-07-22**; the full 2025/26 refit landed
**2026-07-25/26**. Several headline numbers in it are the pre-refit vintage. The table
below is what I refreshed or confirmed on **2026-07-28** — use these, and re-derive the two
marked *open* before publishing.

| Quantity | Current value | Source |
|---|---|---|
| Team-seasons / stints / coaches | 5,339 / 8,642 / 2,445 | `site/data/meta.json` |
| Coaches with a BLUP | 1,006 | refit log |
| Graded (14-league / top-5) | 566 / 224 | `meta.json` |
| M3 in-sample R² (base → enhanced) | 0.629 → 0.674 | recomputed on `mb_prep$ds` |
| M3 LOSO RMSE (base → enhanced) | 0.2576 → 0.2412 | recomputed, 21 folds |
| M3 LOSO improvement | +0.0164 PPG, p = 7.6e-7, CI_lo 0.0116 | recomputed |
| M5 14-league variance | coach 4.1% / club 3.8% / resid 92.1% | refit, 2026-07-28 |
| M5 14-league LRT | χ² = 35.78, df = 1, p = 2.2e-9 | refit |
| M5 top-5 variance | coach 5.4% / club 4.8% / resid 89.8% | refit |
| M5 top-5 LRT | χ² = 19.79, df = 1, p = 8.7e-6 | refit |
| Event study | 3,043 changes, 436 clubs, +1.17, p = 0.0015; mixed p = 0.002; mid-season p = 0.0023 | `validation.json` |
| Sackings | 1,748 mid-season, 16.5% harsh, backfire −0.16 vs +0.35, 35% vs 79% improve | `validation.json` |
| Payoff | 877 pairings, 10 folds, 0.3026 → 0.2993, p = 0.0027, pre-hire p = 0.017 | `validation.json` |
| Forward test | R² 0.721, r 0.852, RMSE edge 0.0133, slope +1.90, p = 0.0024, graded-only 0.0036 | `validation.json` |
| M6 archetype global | χ² 26.13, df 11, p = 0.0062, strict p = 0.0003, wide-creator 0.76 (t = 3.48) | `meta.json` |
| Market benchmark | 51,977 matches; log-loss 1.015 vs 0.979; value p = 0.29; coach p = 0.96; subgroup p = 0.68; ROI −6.6% | Session log 2026-07-26 |
| xG cut | 605 stints, 310 coaches, 89 with ≥3, 0 significant; tie-back r = 0.960 / 0.981 | Session log 2026-07-26 |

**Open — re-derive before publishing:**
1. **Leave-one-league-out CV** for §5. My re-run failed on the held-out league's fixed
   effect (a new factor level at predict time); `run_milestone3()` handles this properly.
   The published value (p = 0.0001, improvement 0.009–0.014) is the ≤2024 vintage.
2. **Event-study slope**: `validation.json` publishes +1.17 / p = 0.0015 (post-refit) while
   `CLAUDE.md` and `Summary_of_Findings.md` still carry +1.10 / p = 0.004 (pre-refit). The
   published site value is correct; fix the two docs so the writeup does not inherit a
   stale figure.
3. Anything you quote from Parts 1–4 of `Summary_of_Findings.md` labelled "original
   5-league analysis" — those are 2015–2024, five leagues, **unweighted** stints. Either
   re-derive on the current vintage or label the vintage explicitly. Do not mix them into
   a current-vintage table.

---

## 17. Writing traps specific to this project

1. **Do not let the nulls read as a losing streak.** Group them (§8), open with the claim
   that they are the most valuable part, and make each one teach a distinct methodological
   lesson.
2. **Never quote a grade or count without its cut.** Top-5 and 14-league use separate
   grading curves and different coach populations.
3. **PPG vs points-per-season.** Convert once, early, and stay consistent. Every league in
   the dataset plays a different number of games (22–46), which is why the model is in PPG
   at all.
4. **Never write "his style"** about Layer B. Club variance beats coach variance on 7 of 9
   axes. The only permissible phrasing is "the style of the teams he coached", with lineup
   stability and pressing intensity as the two marked exceptions.
5. **Do not present the xG cut or Layer C correlations as findings.** They are in the
   writeup precisely because they are not shippable; re-framing them as results in a more
   polished document would undo the project's central discipline.
6. **Do not present the current-season-value market result** (the +0.224 / 10⁻²¹) as
   anything but the leakage demonstration, including its favourite-side P&L edge.
7. **Attribution ≠ causation.** Say it once, explicitly, early, and then let the careful
   verb choices carry it.
8. **Face validity is illustration, not evidence.** Guardiola ranking first is reassuring
   and proves nothing; label it as such wherever it appears.
9. **The certification bar is presentational.** If you describe it as a model correction,
   you contradict §4.6 — every score-side correction was tested and rejected.
10. **Don't hide the effect size.** ~1.4 points per season per SD, ~5% of variance. The
    writeup is more persuasive, not less, for leading with the modesty of the number and
    then showing it survives three independent tests.
