# Coach Descriptive Profile — Design

**Goal:** Move beyond *ranking* coaches to *characterizing* them — answer, for
each coach, "what are they good at?" (where their overperformance comes from),
"what do they do?" (their team's playing-style signature), and, in aggregate,
"what tends to make coaches good?" — all with the project's usual discipline
about the line between description and causation.

Status: **design only** (2026-07-15). Not yet implemented. Three layers of
increasing data lift and *decreasing* validation confidence; each ships
independently, best-first.

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

### 3.3 Presentation

A **style radar** (or small-multiple bars) per coach, face-validity-checkable:
Guardiola high on possession + pressing; Simeone low possession + high solidity +
low line; a Bielsa-lineage coach high on pressing + shot volume + rotation churn
low. Coverage is big-5, 2015/16–2024/25.

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

---

## 7. Implementation plan (best-first)

| Phase | Layer | Work | Lift |
|---|---|---|---|
| 1 | A (goals) | Two head models (`goals_for/against_pg`); coach-stint attribution reusing `build_coach_residuals`; offence/defence BLUPs + sanity tie-back to the points residual. | light |
| 2 | A (xG) | Team xG for/against per match (SofaScore shots + `ss_crosswalk_team_map`); creation vs finishing split on xG-era stints. | medium |
| 3 | B | `match_stats` → team-match → coach-stint aggregation; the ~8 style axes, z-scored within league-season; style radar export. | heavy |
| 4 | — | Coach-vs-squad checks (§5): cross-club style persistence; style residualized on archetype mix. | medium |
| 5 | C | BLUP ~ style + rigidity across coaches, penalized + FDR; writeup part. | analysis |
| 6 | site | `coach.js` Strengths block + radar; writeup; screenshot QA; session log. | site |

Phase 1 alone gives every coach a defensible "good at attack/defence" line and is
a ~day of work on data already in memory. Phases 3–5 are the research-grade
content and can follow once Layer A is shipped and reviewed.

---

## 8. Known limitations (per layer, state on the pages)

- **A:** goal difference → points is monotone but noisy, so the two head residuals
  won't perfectly reconstruct the points residual (report the correlation, don't
  hide the gap). Defence residual absorbs opponent-finishing luck; the xG cut
  addresses this but only for ~3 recent big-5 seasons.
- **B:** big-5 only, 2015/16–2024/25; team style, not coach style in the abstract
  (§5); kickoff formations + season-aggregate stats miss in-game changes.
- **C:** associational, confounded, exploratory — never stated as causal;
  multiplicity-controlled but still hypothesis-generating.
- **Throughout:** SofaScore layers exclude the non-big-5 leagues the site
  otherwise covers, so coaches seen only in (e.g.) the Championship get Layer A
  (goals) but not Layers B–C. Make the absence explicit, don't fabricate a radar.
