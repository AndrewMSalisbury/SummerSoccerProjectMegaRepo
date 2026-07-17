# Coach Descriptive Profile — Design

**Goal:** Move beyond *ranking* coaches to *characterizing* them — answer, for
each coach, "what are they good at?" (where their overperformance comes from),
"what do they do?" (their team's playing-style signature), and, in aggregate,
"what tends to make coaches good?" — all with the project's usual discipline
about the line between description and causation.

Status: **complete — all six phases implemented** (2026-07-16). Layer A goals + xG
in `src/coach_strengths.R`, Layer B style + the coach-vs-squad checks + Layer C in
`src/coach_style.R`, and the site + writeup in phase 6 (`site_export.R`,
`coach.js`, `charts.js`, `Summary_of_Findings.md` Part 8). Three layers of
increasing data lift and *decreasing* validation confidence; each ships
independently, best-first. See `Docs/Session_Log_2026-07-16.md` for the analysis
results and validation, and `Docs/Session_Log_2026-07-16b.md` for the site build.

**What actually shipped to the site (phase 6): the goals cut and the style
fingerprint, nothing else.** The xG cut and Layer C are writeup-only, by the
design's own honesty rules — see §6.

**Phase 4 changed what Layer B is allowed to claim — read §5 before building the
radar.** Team style is mostly the *club's*: club variance beats coach variance on
7 of 9 axes, and squad archetype mix alone explains 69% of possession. Only
**lineup stability** and **pressing intensity** survive as the coach's own.

**Phase 5 came back null — read §4 before writing a word about style and
quality.** Every style→quality association is large, significant, and dies under
one of four checks: the strong axes are inseparable from club size (possession
r = 0.86 with club value percentile) or restate the outcome the BLUP measures,
and lineup stability *reverses sign* within-coach. **There is no Layer C block to
ship** — only the null and the reason for it.

---

## 0. Honest framing (binding, read first)

The project has one causally-validated claim — the M5 quality BLUP generalizes to
the hiring decision (payoff p = 0.016). Everything in this document is
**descriptive**, and the three layers sit at different points on the honesty
gradient. State the label *per layer*, not once at the bottom:

- **Layer A — Strength decomposition (defensible).** Partitions a residual we
  already trust (the M4/M5 overperformance) into offensive vs defensive and
  process vs outcome. It re-slices a validated quantity; it makes no new
  attribution leap. Safe to state plainly ("this coach's edge is defensive").
- **Layer B — Style fingerprint (descriptive-clean).** It is literally *what the
  team did* on the pitch (possession, pressing height, rotation), z-scored within
  league-season. No causal content at all — a description, not a claim. Safe, but
  it is the *team's* style, jointly produced by coach and squad (see §5).
- **Layer C — Style → quality association (exploratory).** Correlating style/
  rigidity with the BLUP across coaches is vulnerable to reverse causality and
  confounding (better coaches get better, differently-built clubs; the BLUP
  conditions on squad *value* but not on squad *style*). Same bucket as the fit
  layer — must always be labeled exploratory, never "what makes a coach good"
  stated as fact. Phrase as "coaches who do X *tend to* rank higher, descriptively."

---

## 1. Motivation

The site ranks 2,341 coaches and grades the certified ones, but every coach page
answers the same question — *how good* — with a single number. It never says
*good at what*. Two coaches with identical B+ grades can be opposite animals:
one overperforms by conceding less than his squad value predicts, the other by
scoring more; one imposes 60% possession and a high line, the other sits deep
and counters. That texture is the most fan-shareable and the most
scouting-relevant content the data can yield, and almost none of it is surfaced.

Crucially, this is *M6 turned around.* M6 measured the player types a coach was
**given** and asked whether that mix predicted overperformance. This measures the
style a coach **imposes** and where his edge **lands** — the other half of the
same picture.

---

## 2. Layer A — Strength decomposition ("what are they good at?")

The most defensible layer, and the one to build first. Data lift is **light**:
goals-based version uses only `matches.rds`, full 2005–2024 span, TM-only.

### 2.1 Split the residual into offence and defence

The M3/M4 model (`compute_residuals()` in `residual_analysis.R`) fits

```
points_per_game ~ log(norm_weighted_value) + as.factor(league) + is_b_team
```

and calls the residual "overperformance." Fit **two parallel head models** on the
same right-hand side, with the same log-value + league + b-team predictors:

```
goals_for_per_game     ~ log(norm_weighted_value) + league + is_b_team
goals_against_per_game ~ log(norm_weighted_value) + league + is_b_team   (defence: sign-flip)
```

Goals for/against per team-season come straight from `matches.rds` via the
existing `xx_match_points_for_team()` pattern (sum home/away goals for and
against). The two residuals are:

- `off_resid` = actual goals scored − value-expected goals scored (attacking
  overperformance).
- `def_resid` = value-expected goals conceded − actual goals conceded (defensive
  overperformance; sign chosen so positive = better).

**Sanity tie-back:** more goal difference than expected should track more points
than expected — `off_resid + def_resid` (in goal terms) must correlate strongly
with the existing points `residual` per team-season. Report the correlation as a
built-in consistency check (expect ~0.8+; the map from goal difference to points
is monotone but noisy).

### 2.2 Attribute to coach stints

Reuse the M5 attribution verbatim: `xx_assign_matches_to_coaches()` +
`build_coach_residuals()`, but aggregate **goals for/against** within the stint
instead of points, and difference against the season-level head-model
predictions (constant within season, exactly as `partial_residual_ppg` already
does). Games-weight per stint, consistent with the 2026-07-14 M5 change. Output:
per coach, an `off_blup` and `def_blup` (mixed model, same `fit_mixed_model()`
scaffold with the goal-based response), or at minimum games-weighted career means
with the same ≥3-stint significance rule.

Deliverable: every coach gets an **offence/defence tilt** — e.g. Simeone
strongly defensive, an attacking-minded coach the reverse — plus the magnitude.
This is a one-line characterization on every coach page.

### 2.3 Process vs outcome (xG) — the second cut

Data lift **medium**: SofaScore `shots_<sid>.rds` carry per-shot `xg`, complete
from 2022/23 (present but partial mid-2021/22). Aggregate to **team xG for/against
per match** — deriving the match side from `is_home` + the event's home/away ids
(the `match_stats$team_ss_id` caveat in CLAUDE.md applies), and mapping SofaScore
teams to TM team-seasons via `ss_crosswalk_team_map()` (greedy one-to-one, never
plain overlap). Then, within the coach stints that fall in the xG era:

- **Creation edge** = team xG-for above value expectation (fit an xG-for head
  model like §2.1). Repeatable — it's process.
- **Finishing edge** = actual goals − xG (for), and for defence xG-against −
  goals-against (shot-stopping / luck). Less repeatable — flag it as such.

This distinguishes a coach whose overperformance is *chance quality he
manufactures* from one riding *finishing that may regress*. That distinction is
exactly the honest-signal discipline the rest of the project already applies to
short-stint BLUPs. **Coverage caveat: xG-era stints only (~2022/23–2024/25,
big-5), so this is a recent-form lens layered on the full-span goals cut, not a
career verdict.**

> **As-built correction (2026-07-16).** Measured coverage: 2022–2024 are 99–100%
> complete, **2021/22 is only ~40%** and is excluded (partial coverage would
> understate team xG on a non-random subset of matches) — so the window is three
> seasons, not four. Two data facts the implementation had to handle, both
> documented in `cs_season_team_xg()`: 27 of 5,330 xG-era events (0.5%, all in
> 2023) carry a full complement of shots but are **missing their goal shots**,
> which would understate creation and inflate finishing — so an event counts only
> if its shotmap reconciles with the scoreline; and own goals are credited in the
> shotmap to the *benefiting* side with no xG, so they land wholly in finishing.
> Also note the `match_stats$team_ss_id` caveat does not bite here: `shots`
> carries its own `is_home`, so the shooting team comes from the event directly.

---

## 3. Layer B — Style fingerprint ("what do they do?")

Data lift **heavy** (new SofaScore aggregation), payoff high and very shareable.
This is the M6 recipe pointed at team style instead of player archetype.

### 3.1 Build team-match style, then coach-stint style

`match_stats_<sid>.rds` is per-player-per-match. Aggregate to **team-per-match**
(sum/appropriate combine over the match side), then to **coach-stint** (mean over
the stint's matches). Complement with `formations_<sid>.rds` (already used),
`shots_<sid>.rds` (shot volume/quality, xG for/against), and team-level combines
of the same per-90 stat families `player_archetypes.R` already parses
(`pa_stat_features`: passes, long balls, crosses, final-third passes, tackles,
interceptions, duels, etc.). **Do not use** `outfielderBlocks` / `ballRecovery`
(exist only from 2023/24, per CLAUDE.md).

> **As-built correction (2026-07-16).** The `outfielderBlocks`/`ballRecovery`
> prohibition is a fact about the **season** stats cache and does **not** apply
> to this layer: in `match_stats`, `ballRecovery` is populated in all 50
> league-seasons (PL 2015 mean 5.0 per player-match), so it is used here. The
> trap runs the other way — **`possessionWonAttThird` is absent from
> `match_stats` entirely** (it exists only in the season cache), so the
> pressing-*height* input below cannot be attributed to a coach stint. See §3.2.
> Also: `match_stats$team_ss_id` matches the actual match side only **41.5%** of
> the time, and `substitute == FALSE` identifies the starting XI exactly (11 per
> side in all 760 of PL 2023's team-matches).

### 3.2 Style axes (z-scored within league × season, like archetypes)

Target ~6–8 interpretable axes:

| Axis | Built from |
|---|---|
| Possession / control | team pass volume, pass accuracy, share of opposition-half passes |
| Pressing height | possession-won-in-attacking-third, opponent passes allowed, defensive-action location (heatmap-derived) |
| Directness / tempo | long-ball share, chipped/through-ball rate, passes per shot |
| Width | cross volume, wide-channel touch share |
| Shot volume vs quality | shots per game vs xG per shot |
| Defensive solidity | xG-against, shots conceded |
| Set-piece reliance | share of shots/xG from set-piece situations (`shots$situation`) |
| **Squad rotation / lineup stability** | churn in the starting XI across consecutive matches (from `match_stats` lineups) — a real coach signature nobody visualizes |

Z-score within league × season × (nothing else) so a coach is measured against
his contemporaries, exactly as `pa_zscore_features()` does for players.

> **As-built (2026-07-16, `src/coach_style.R`, `sy_` prefix).** Nine axes, all
> full-span (2015/16–2024/25, big-5), each an **equal-weight mean of its members'
> z-scores** — deliberately not a PCA or a fitted weighting, since nothing here
> is trained against an outcome, so there is nothing to overfit and the axes stay
> interpretable. Every axis is signed so positive = more of the named trait.
>
> | Axis | Built from (per team-match) |
> |---|---|
> | Possession / control | pass share of the match, pass accuracy, opposition-half pass share |
> | **Pressing intensity** | PPDA proxy (defensive actions ÷ opponent passes), ball recoveries |
> | Directness / tempo | long-ball share, −passes per shot |
> | Width | cross share of passes |
> | Shot volume | shots |
> | Chance quality | −mean shot distance from goal (metres) |
> | Defensive solidity | −shots conceded, +opponent mean shot distance |
> | Set-piece reliance | set-piece share of shots (`shots$situation`) |
> | Lineup stability | share of the starting XI retained from the previous match |
>
> Deviations from the table above, and why:
> - **"Pressing height" → "pressing intensity".** The height input
>   (`possessionWonAttThird`) does not exist per-match (§3.1), so the axis
>   measures *how much* a team presses, not *how high*. True height ships as a
>   **secondary season-level descriptor** (`pressing_height`), flagged
>   `height_blended` wherever the team-season had more than one coach — there the
>   value is the club's, not the coach's.
> - **"Shot volume vs quality" split into two axes.** Volume and quality are a
>   trade-off, so collapsing them into one axis would cancel the very thing worth
>   seeing. Quality uses mean shot distance (available from 2015/16) rather than
>   xG per shot (2022+ only), keeping the axis full-span; the xG view is phase 2's
>   job.
> - **Defensive solidity uses shots conceded, not xG-against**, for the same
>   full-span reason.
> - **Width has no "wide-channel touch share"** — that needs heatmaps, which are
>   season-level only, so cross share carries the axis alone.

### 3.3 Presentation

A **style radar** (or small-multiple bars) per coach, face-validity-checkable:
Guardiola high on possession + pressing; Simeone low possession + high solidity +
low line; a Bielsa-lineage coach high on pressing + shot volume + rotation churn
low. Coverage is big-5, 2015/16–2024/25.

> **As-run face validity (2026-07-16, ≥100-game coaches).** Strong on every axis:
> possession — Luis Enrique, Guardiola, Xavi, Tuchel top; Allardyce, Nicola
> bottom. Directness — Bordalás, Dyche, Mendilibar, Allardyce top; Favre, Setién,
> Sarri bottom. Defensive solidity — Allegri, Guardiola, Tuchel, Arteta.
> Set-piece reliance — **Thomas Frank** (Brentford's known specialism), Dyche,
> Machín. Lineup stability — Dyche and Coudet top; Tuchel, Italiano, Allegri,
> Luis Enrique are the rotators. Shot volume — Zidane, Luis Enrique, Guardiola,
> Klopp.
>
> Two corrections to the expectations stated above:
> - **"Guardiola high on pressing" resolves to *height*, not intensity** — he is
>   ~0 on the per-match intensity axis and +1.5 on height, and that is right:
>   City make few defensive actions because opponents rarely hold the ball, yet
>   win it high. The two measures correlate only r = 0.38 and are different
>   traits; don't collapse them.
> - **"Simeone low possession … low line" is not supported.** He is +0.13 SD on
>   possession (64th pct) and dead average on pressing height (53rd pct). What
>   *is* supported is solidity — 92nd pct — alongside narrowness (16th pct on
>   width) and good shot selection (83rd pct on chance quality). The data refines
>   the caricature: his signature is solidity + narrow + good chances, not a
>   low-possession low block.
>
> **Display note for phase 6:** axis units are SDs of *team-matches*, so coach
> means are heavily compressed toward 0 (Simeone's 92nd-pct solidity is only
> +0.28 SD). A radar should map to percentile among coaches, not raw SD, or every
> fingerprint will look flat.

---

## 4. Layer C — Style → quality ("what tends to make coaches good?")

The literal answer to the question — and the one that must ship **exploratory**.
With Layer B's axes + rigidity (`cr_rigidity`, already built) + the M5 BLUP,
across the ~200–500 graded coaches:

- Correlate / regress BLUP on the style axes and rigidity (penalized / with FDR,
  mirroring M6's multiplicity discipline). Report standardized associations, not
  a causal model.
- Candidate findings worth their caveats: does **adaptability** (low rigidity)
  associate with quality? Is the edge concentrated in **chance prevention** vs
  creation (link to Layer A)? Do high-press coaches over- or under-rank?
- **Confounding is unavoidable** and must be stated: the BLUP conditions on squad
  *value* but not squad *style*, better coaches sort into differently-built clubs,
  and style is co-produced with the squad. Frame every result as "coaches who do
  X *tend to* grade higher (descriptive, not causal)."

This is a natural centerpiece for the writeup precisely because it is honest
about its own limits — the same posture as the M6 fit result.

> **As-run (2026-07-16, `run_style_quality()` in `src/coach_style.R` →
> `coach_style_quality_top5.rds`). The result is NULL, and the null is the
> centerpiece.** 231 coaches with both a top-5 BLUP and a fingerprint (173
> graded), weighted by career games.
>
> Every raw association is large and FDR-significant — defensive solidity
> β = +0.64, shot volume +0.53, possession +0.52, lineup stability −0.37. **Not
> one survives scrutiny.** Four checks, each of which kills a different group:
>
> | check | what it asks | casualties |
> |---|---|---|
> | consistency across 4 specs | raw / squad-residualized / club-controlled / graded-only, same sign | pressing, directness, width, set-piece reliance |
> | separable from club level | is the axis distinguishable from club size at all? | possession (r = 0.86 with club value pct), shot volume (0.81), defensive solidity (0.74) |
> | restates the outcome | is the axis built from the thing the BLUP measures? | chance quality (and solidity/shot volume again) |
> | within- vs between-coach | does the same coach do better when he does more of it? | **lineup stability (sign reverses)** |
>
> **Nothing is left.** Rigidity alone is unkilled (+0.155 club-controlled,
> q = 0.043) — but it is a career constant with no within-coach variation, so
> the decisive check *cannot be run on it*. That is an untested predictor, not a
> validated one, and the summary labels it "between-coach only; untestable"
> rather than letting it pass by default.
>
> Three findings worth carrying into the writeup:
>
> - **The style axes are proxies for club size.** possession r = +0.86 with the
>   coach's mean club value percentile. "Possession coaches grade higher" and
>   "big-club coaches grade higher" are not distinguishable in this data.
> - **The all-axes multivariable is a suppression trap.** `club_pct` flips from
>   r = **+0.39** bivariate to β = **−0.60** partial, which would read as "big
>   clubs underperform" and is an artifact of collinearity. Tell for the same
>   disease: possession's coefficient *rises* under a club control (0.517 →
>   0.568), which no genuine confound removal does. One axis + one control is
>   the only interpretable spec.
> - **Lineup stability is a Simpson's paradox.** Between coaches, rotators grade
>   higher (−0.373); within a coach, *stability* associates with better seasons
>   (+0.131, p < 0.0001), and within a club likewise (+0.110). The between-coach
>   version is club sorting — the heaviest rotators are Heynckes, Tuchel,
>   Allegri, Luis Enrique, all at top clubs with European fixture loads — and it
>   drops to p = 0.25 once club level is controlled at stint level. The phase 4
>   "coach-owned axis" therefore does **not** convert into a quality finding.
>
> `r(club_pct, blup) = +0.39` is itself worth stating: coaches at bigger clubs
> grade higher. Whether that is better coaches being hired by bigger clubs or the
> value model under-predicting them, the BLUP cannot say — it is the confound the
> whole layer runs aground on.
>
> **Consequence for §6: there is no Layer C block to ship.** The writeup gets the
> null and the reason for it. This is the same outcome as the M6 fit result and
> the payoff validation — the third independent attempt to find something beyond
> the quality BLUP, and the third to come back empty. That consistency is itself
> the most defensible thing the project can say.

---

## 5. Cross-cutting caveat: coach vs squad

Team style and even the strength split are **jointly produced** by the coach and
the players available. A possession fingerprint at a technical squad is not proof
the coach *is* a possession coach in the abstract. Two partial mitigations, worth
building but not over-claiming:

- **Within-coach across clubs:** for coaches with ≥2 clubs, how much of the style
  fingerprint travels? A high cross-club persistence (like the formation-profile
  δ analysis) is evidence the signature is the coach's, not the squad's.
- **Style residualized on squad archetype mix:** regress each style axis on the
  M6 archetype shares the coach was given and keep the residual — "more possession
  than this squad's personnel would predict." Optional, and itself imperfect.

Neither fully separates coach from squad; say so.

> **As-run (2026-07-16, `run_coach_vs_squad()` in `src/coach_style.R` →
> `coach_style_vs_squad.rds`). This section turned out to be the main result of
> Layer B, not a footnote.**
>
> **Team style is mostly the club's, not the coach's.** Club variance exceeds
> coach variance on **7 of 9 axes**, and the squad's archetype mix *alone*
> explains much of the fingerprint:
>
> | axis | coach var % | club var % | r coach travels | r club persists | R² from archetype mix |
> |---|---|---|---|---|---|
> | possession | 11.6 | **69.2** | 0.55 | 0.82 | **0.69** |
> | pressing | **30.9** | 23.6 | 0.34 | 0.47 | 0.12 |
> | directness | 24.8 | **52.1** | 0.52 | 0.71 | 0.51 |
> | width | 29.8 | 34.6 | 0.44 | 0.50 | 0.39 |
> | shot volume | 11.3 | **54.4** | 0.43 | 0.67 | 0.54 |
> | chance quality | 13.8 | 27.6 | 0.29 | 0.36 | 0.11 |
> | defensive solidity | 11.0 | **45.0** | 0.29 | 0.58 | 0.31 |
> | set-piece reliance | 12.9 | 24.7 | 0.25 | 0.29 | 0.22 |
> | lineup stability | **19.2** | 14.6 | **0.33** | 0.17 | 0.10 |
>
> A club under two *different* coaches (possession r = 0.82) looks far more alike
> than a coach at two *different* clubs (r = 0.55). **Consequence for §6: a radar
> must be labelled as the style of the teams this coach ran — never "his style"
> in the abstract.**
>
> **Two axes survive as genuinely the coach's:**
> - **Lineup stability** — the only axis where coach variance beats club (19.2 vs
>   14.6), the only one that travels better than it persists (0.33 vs 0.17), just
>   10% personnel-explained, and it still travels after residualizing on the
>   squad (0.25 vs 0.11). Rotation is a decision, not a squad property. The
>   design's hunch that this is "a real coach signature nobody visualizes" is
>   **confirmed**.
> - **Pressing intensity** — the best tactical axis: highest coach share (30.9%,
>   above club's 23.6%), only 12% personnel-explained, and the only tactical axis
>   still standing after residualization (0.34 vs 0.33).
>
> After residualizing on the archetype mix, everything else collapses (possession
> travel 0.55 → 0.17; shot volume 0.43 → 0.09).
>
> **Method caveat, stated because it cuts against the headline:** the two
> correlations are not a like-for-like contest. Consecutive coaches at one club
> inherit nearly the same squad, whereas a coach's two clubs have different
> squads — so `r_club > r_coach` is expected under *any* model where the squad
> matters and does not alone prove the coach is irrelevant. The variance
> decomposition, which estimates both effects at once, is the better instrument;
> it agrees on 7 of 9 axes, which is why the conclusion stands. And neither check
> is causal: coaches are hired by clubs that already suit them (inflating travel),
> and the archetype mix is partly one the coach shaped (so the residual strips out
> some of his own signature).

---

## 6. Where it lives

- **Coach pages** (`site/data/coaches/*.json`, `site/js/coach.js`): a "Strengths"
  block — the offence/defence tilt and process/outcome split (Layer A) as diverging
  bars, and the style radar (Layer B). Both carry their per-layer labels.
- **Writeup** (`Docs/Summary_of_Findings.md` → `writeup.html`): a new part for
  Layer C (aggregate style↔quality), explicitly exploratory, and the coach-vs-squad
  caveat (§5).
- **Data pipeline:** new savers analogous to the existing ones —
  `coach_strengths_*.rds` (Layer A) and `coach_style.rds` (Layer B) under
  `data/results/`, consumed by `site_export.R` and re-run after M5/M6 refits.

> **As-built (phase 6, 2026-07-16).** Two cards on coach pages, plus Part 8 of the
> writeup. The plan above assumed all of Layer A would ship and that Layer C would
> ship as "exploratory"; the phase 2 and phase 5 results changed both.
>
> | piece | ships where | why |
> |---|---|---|
> | Layer A, goals cut | **coach page** card "Where his edge comes from" | defensible; full 2005–2024 span |
> | Layer A, xG cut | **writeup only** | 3 big-5 seasons, no coach ≥5 stints, **zero FDR-significant** — a coach page would read it as a career verdict |
> | Layer B, style | **coach page** card "Style of the teams he coached" | descriptive-clean, but see the labeling rules below |
> | Layer B, pressing height | coach-page **inset block** with a named-pole scale, `blended` flag | season-level; substantially the club's where the season had >1 coach |
> | Layer C | **writeup only, as the null** | §4 — the raw correlations must never render as findings |
>
> Decisions worth not relitigating:
>
> - **Layer A is gated on being graded** (545 of 958 coaches), read from the *same
>   cut* as the headline grade. It re-slices the BLUP, so it inherits the display
>   certification bar rather than inventing a second one. The design's "every coach
>   gets a tilt" (§2.2) was overruled by that consistency.
> - **The two rows share one fixed x domain (±0.26 goals/game) across all coaches.**
>   Defence bars are much shorter than attack bars for nearly everyone — that is the
>   phase 1 finding (coach variance is far larger on goals-for), not a scaling bug.
> - **The radar became horizontal percentile bars.** Nine axes of compressed SDs on a
>   radar is the classic unreadable-fingerprint failure; the reader's actual job here
>   is "more or less than a typical coach", which is a baseline comparison. Bars
>   around a 50th-percentile midline do that and let the two coach-owned axes be
>   marked inline. Percentiles rank within the **≥38-game display set** (256 coaches)
>   so the reference class equals the displayed class — hence small differences from
>   the ≥100-game percentiles quoted in §3.3 and §5 (Simeone solidity 94th here vs
>   92nd there).
> - **The style bars use one hue, not the site's pos/neg diverging pair.** These axes
>   have no good/bad polarity; the green/red-style ramp would assert a verdict the
>   layer explicitly does not make (and §4 proves it cannot).
> - **Pressing height got its own block, and must not be drawn on a pitch.**
>   Andrew asked for it to be shown more clearly than a footnote percentile — it is
>   the axis a reader most wants a plain answer on, and "98th percentile on pressing
>   height" is not one. It now has a named-pole spectrum (Deep block ↔ High press)
>   and a plain verdict. **The obvious idea — a marker on a drawn pitch — is
>   false:** the stat is the share of possession won in the attacking third *ranked
>   against other coaches*, so 98th percentile does not mean "wins it 98% of the way
>   upfield". Poles as labels, scale as rank. Also note the tails need their own
>   phrasing: with a midpoint rank over 256 the extremes round to 0 and 100, and both
>   "more often than 100% of coaches" and "more often than 0% of coaches" are false
>   as English (`heightSentence()`).
> - **`edgeNote()` handles the sign-mismatch case.** A coach can grade well on points
>   with a negative goal edge (Simeone: B, −0.03). Unsaid, the Layer A lede reads as a
>   flat contradiction of the grade card directly above it, so the card names the gap
>   where it occurs rather than leaving it to a footnote.

---

## 7. Implementation plan (best-first)

| Phase | Layer | Work | Lift |
|---|---|---|---|
| 1 ✅ | A (goals) | Two head models (`goals_for/against_pg`); coach-stint attribution reusing `build_coach_residuals`; offence/defence BLUPs + sanity tie-back to the points residual. | light |
| 2 ✅ | A (xG) | Team xG for/against per match (SofaScore shots + `ss_crosswalk_team_map`); creation vs finishing split on xG-era stints. | medium |
| 3 ✅ | B | `match_stats` → team-match → coach-stint aggregation; the ~8 style axes, z-scored within league-season; style radar export. | heavy |
| 4 ✅ | — | Coach-vs-squad checks (§5): cross-club style persistence; style residualized on archetype mix. | medium |
| 5 ✅ | C | BLUP ~ style + rigidity across coaches, penalized + FDR; writeup part. | analysis |
| 6 ✅ | site | `coach.js` Strengths block + style bars; `Summary_of_Findings.md` Part 8; screenshot QA; session log. | site |

Phase 1 alone gives every coach a defensible "good at attack/defence" line and is
a ~day of work on data already in memory. Phases 3–5 are the research-grade
content and can follow once Layer A is shipped and reviewed.

**Phase 1 as-run (2026-07-16, `src/coach_strengths.R`).** Built as designed; the
head models, the coach-stint attribution, and the BLUP/significance machinery all
reuse the M3/M5 functions rather than re-implementing them. Results:

- Tie-back passes: goal-difference edge vs the points residual r = 0.862 (top-5)
  and 0.872 (14-league), ~0.59 points per goal of edge. At coach level the goal
  `edge` correlates r = 0.823 with the published points BLUP.
- **The coach effect is stronger on goals than on points** — 14-league LRT for
  coach variance χ² = 160.2 (offence) and 60.5 (defence) vs 28.5 for points.
  Goals-for is a lower-noise coach signal; worth carrying into the write-up.
- Face-valid: Simeone and Pulis anchor the defensive tilt, De Zerbi and Luis
  Enrique the attacking, Guardiola is high on both. Note Simeone's *goal* edge is
  ≈ 0 — his points overperformance is in converting goal difference to points,
  which the tilt describes but does not explain.
- Outputs: `data/results/coach_strengths_{top5,14league}.rds` (per coach:
  `off_blup`, `def_blup`, `tilt`, `edge`, plus games-weighted means and FDR
  significance) and `coach_goal_residuals_*.rds` (the stint table).

**Phase 2 as-run (2026-07-16, same file).** Four measures per coach — `creation`
and `prevention` (process, head-modelled against value expectation) and
`finishing` and `shotstop` (outcome, within-team). Outputs
`data/results/coach_xg_strengths.rds` + `coach_xg_residuals.rds`. Results:

- **Cross-source tie-back passes:** `creation + finishing` vs the goals cut's
  `off_resid` r = 0.949; `prevention + shotstop` vs `def_resid` r = 0.981, over
  all 452 stints. The xG cut is SofaScore-sourced and the goals cut is
  TM-sourced, so this is a real independent check on the team map and attribution.
- **The process/outcome premise is now tested, not assumed** (§2.3 asserted it).
  Lag-1 persistence for the same club in consecutive seasons (165 pairs):
  creation **0.423**, prevention 0.271, finishing 0.242, shot-stopping
  **−0.005**. Creation is the most repeatable and shot-stopping is pure noise, as
  designed — but **finishing persists more than assumed** (0.24, not ~0), most
  plausibly because clubs keep their finishers. That is a reason to keep
  finishing labelled an unreliable *coach* signal, not a reason to promote it.
- Squad value predicts chance creation better than goals (xG-for R² 0.719 vs
  goals-for 0.641), consistent with goals = chances + noise.
- **Sample-size ceiling is the binding constraint:** 3 seasons ⇒ 452 stints, 264
  coaches, 57 with ≥3 stints, none with ≥5, and **zero FDR-significant on any
  measure**. Anything shown from this layer needs the lens framing and a games
  bar (the console previews use ≥38 games).

---

## 8. Known limitations (per layer, state on the pages)

- **A:** goal difference → points is monotone but noisy, so the two head residuals
  won't perfectly reconstruct the points residual (report the correlation, don't
  hide the gap). Defence residual absorbs opponent-finishing luck; the xG cut
  addresses this but only for ~3 recent big-5 seasons.
- **B:** big-5 only, 2015/16–2024/25; team style, not coach style in the abstract
  (§5); kickoff formations + season-aggregate stats miss in-game changes.
- **C:** associational, confounded, exploratory — never stated as causal;
  multiplicity-controlled but still hypothesis-generating. **As-run this was not
  a limitation but the whole finding (§4): the layer is a null.** The axes cannot
  be separated from club size, several restate the outcome, and the one
  coach-owned axis reverses sign between the between-coach and within-coach
  contrasts. Report the null, not the raw correlations.
- **Throughout:** SofaScore layers exclude the non-big-5 leagues the site
  otherwise covers, so coaches seen only in (e.g.) the Championship get Layer A
  (goals) but not Layers B–C. Make the absence explicit, don't fabricate a radar.
