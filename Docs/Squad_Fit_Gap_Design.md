# Squad-Fit Gap Analysis — Design

**Goal:** For a given club squad and a candidate coach, show *where* that coach's
preferred shapes leave the squad short (positions/archetypes with no natural
option) and *which* of the squad's value the coach would strand (expensive
players his formations bench or play out of role). Turns the recommender's
deployment number — today a single opaque ΔPPG term — into a concrete,
recruitment-facing diagnostic.

Status: designed and **implemented 2026-07-15** (`src/coach_recommender.R`
`cr_best_xi_assign` / `cr_squad_fit`, `src/site_export.R` `se_squad_fit`,
`site/js/team.js`). A presentation/diagnostic layer on top of already-built,
already-validated machinery; introduces no new model and makes no new points
claim. Settled with Andrew before the build (2026-07-15):

- **Surface:** per-coach expandable panels on the team-page similarity grid
  (Direction 1, §4). The team-level aggregate needs card (Direction 2) is not in
  this cut.
- **"Stranded" definition:** *worth more than a starter* — a benched player is
  stranded when he is worth more than the cheapest player the coach's shape
  actually starts (§3.3), plus value played out of natural role. (Self-calibrating
  to the squad; a deep squad legitimately benches value, stated as a limitation.)
  **Amended 2026-07-16 (§3.3a): and startable by at least one of the 22 shapes.**
  The "deep squad legitimately benches value" limitation anticipated here turned
  out to dominate the panel rather than sit beside it — see §3.3a.
- **Team builder:** deferred to a follow-up (§4 note); this cut is team-pages only.

---

## 0. Honest framing (binding, read first)

The recommender's payoff validation (2026-07-13) was decisive on this point:
**the deployment/formation layer did *not* improve out-of-sample hiring
forecasts** (−0.0003 RMSE, 4 folds better / 5 worse) and ships as an
exploratory column, never in the headline score. This feature is downstream of
that layer, so it inherits the same label.

What that means precisely:

- This feature is a **what-if deployment diagnostic**, not a validated
  prediction. It *explains* the (exploratory) deployment term — it does not add
  a new one, and it must never be presented as "points this coach will win/lose."
- The underlying eligibility matrix *did* pass its mechanical gate (fit → minutes
  share, t = 26.9, 316/316 arrival stints positive), so the statement "player P
  is a poor positional fit for coach C's shapes" rests on validated machinery.
  The statement "and that will cost you N points" does not.
- Copy discipline: describe **gaps and stranded value in € and slots**, never in
  predicted points. Same footnote family as the team-page suggestions.

Everything below is engineered so the honest version is the only version the
math can express.

---

## 1. Motivation and the core idea

The M4/M5 residual is blind to value wastage *by construction* — it conditions
on the minutes-weighted value that actually played, so a coach who benches a
€100m winger is not punished; the model simply lowers its expectation to match
the weaker XI (`Docs/Coach_Recommender_Design.md` §1). The recommender's
deployment layer forecasts the *deployed value* a coach would field
(`cr_deployable()`), but it collapses that to one scalar. A sporting director's
actual question is structural:

> "If we hire this coach, which of our players stop mattering, and what do we
> then need to buy?"

Both halves already fall out of the best-XI assignment the recommender runs:

- **Stranded value** = high-value squad players the coach's shapes leave *out of
  the best XI*, or force to play a slot they fit poorly (eligibility < 1.0).
- **Slot/archetype gaps** = formation slots the coach's shapes *require* that the
  squad can only fill with a low-eligibility "stretch" player or a cheap body.

The recommender computes the best XI and throws away the assignment. This
feature keeps it.

---

## 2. What already exists (reuse inventory)

Everything structural is built in `src/coach_recommender.R`:

| Piece | Function | What it gives us |
|---|---|---|
| Squad + eligibility | `cr_team_squad(team_season_id, league_key, year)` | one row per player: market value, lagged archetype, and the 7 slot-eligibility factors (`cr_slot_types` = CB, FB, DM, CM, AM, W, ST; GK handled separately) |
| Best XI for a shape | `cr_best_xi_value(squad, formation)` | greedy + pairwise-swap max-value assignment of 10 outfield slots (currently returns only the summed value) |
| Every shape's value | `cr_team_formation_values(squad)` | named vector over all 22 formation strings |
| Coach shape prior | `cr_formation_profile(coach_matches, as_of, delta = 0.3)` | recency-weighted share vector over formation strings |
| Coach rigidity | `cr_rigidity(coach_formations, delta)` | entropy + cross-club persistence ∈ [0, 1] |
| Deployed value | `cr_deployable(fvals, profile, rigidity)` | `r·Σ p(f)·bestXI(f) + (1−r)·max_f bestXI(f)` |
| Archetype→slot matrix | `cr_archetype_slot_matrix` | soft eligibility per archetype; TM-position fallback `cr_tm_position_slot()` |

**The only genuinely new code is (a) making `cr_best_xi_value()` optionally
return the assignment, not just the total, and (b) differencing two assignments
into gaps and stranded value.** No new scrape, no new model, no chromote.

---

## 3. Computation

### 3.1 Reference shape(s) for the coach

A coach is not one formation. Use his recency-weighted profile
`p(f | C)` (δ = 0.3) and take a **weighted view over his supported shapes**,
mirroring `cr_deployable()` so the diagnostic and the scalar it explains stay
consistent. Concretely, restrict to formations with `p(f | C) ≥ 0.10` (his real
repertoire, typically 1–3 shapes), renormalise, and compute per-slot and
per-player quantities as the profile-weighted average across those shapes. A
highly rigid coach (Gasperini, 97% back-3) collapses to essentially one shape; a
flexible coach (Streich, rigidity 0.09) averages several — which is correct, an
adaptable coach strands less because he can reshape around the squad.

### 3.2 Return the assignment

Add `cr_best_xi_assign(squad, formation)` (refactor of `cr_best_xi_value` — the
value version calls it and sums). It returns, per formation:

- `xi`: the 11 chosen players (10 outfield + GK) with the slot each was assigned
  and that player's eligibility for the slot.
- `bench`: outfield players not selected, with their value and their *best*
  eligibility across this formation's slot types.

### 3.3 Stranded value (what the coach wastes)

For each shape in the coach's repertoire:

- **Benched value**: `Σ value` of bench players above a relevance floor (e.g. top
  ~18 by value, so we don't count the 4th-choice keeper). These are players good
  enough to expect minutes whom this shape has no room for.
- **Out-of-role value**: for selected players with eligibility `< 1.0`, the
  value-weighted eligibility deficit `value · (1 − elig)` — value that is playing
  but not in its natural slot.

Aggregate profile-weighted across shapes, then **roll up by archetype** (the
player's lagged M6 archetype, or TM-position bucket on fallback). Output: a
ranked list like *"wide-creator: €140m largely stranded — this coach's shapes
field 0.7 W slots on average."* This is the "Lookman/De Ketelaere in a 3-5-2"
story the recommender already noticed for S. Inzaghi at Atalanta, made explicit.

### 3.3a Startable filter — as-built amendment (2026-07-16, binding)

Andrew, from the shipped site: *"They are showing nearly identical positions and
value left out of the squad despite different formations."* He was right, and the
cause is structural, not a coding error.

Two facts, measured on the 2024 squads:

1. **The max-value XI is near formation-invariant.** On Man City, any two of the
   22 shapes share **8–10 of 10** outfield starters (median 9); **6** players
   start in all 22 shapes and **24 of 36 start in none**. The XI maximises value
   and the eligibility matrix is broad, so the shape moves a slot or two, never a
   team.
2. **`rep_w` sums to 1**, so a player benched in *every* shape contributes
   `Σ_f w_f · value = value` — his **full value, identically, to every coach**,
   whatever his repertoire.

Together those put a flat `destroyer €40m` (Nico González, started by 0 of 22
shapes) on **all 81** Man City coaches, with Bernardo Silva (€38m, also 0 of 22)
making up an invariant €78m floor — **40–50% of every coach's strand total**.
Site-wide, **88.9%** of a team's coaches shared the same *top* strand label
(Q1 74%). The panel was answering "how deep is this squad?" while its position in
a per-coach drawer promised "how does this coach differ?".

**Fix (option 1 of 3, chosen by Andrew):** `cr_startable_players(squad)` — the
players who make the max-value XI in **at least one of the 22 shapes** — and the
strand counts only bench players in that set. A player no shape in the data would
start is squad depth; no coach can be said to strand him.

**The quantifier is load-bearing and must not be narrowed to the coach's own
repertoire.** A player benched by Guardiola's shapes but started by Allegri's
*is* stranded by Guardiola — that contrast is the entire coach-specific signal
this diagnostic exists to show. Filtering per-coach would delete exactly what we
are trying to expose.

Measured effect on the shipped JSON:

| | before | after |
|---|---|---|
| same top strand label (median) | 88.9% | **77.8%** |
| same top strand label (Q1) | 74.1% | **64.2%** |
| distinct signatures per team (median, of 81) | 36.5 | 34.5 |
| strand € retained | — | ~74% |
| `gaps` list unaffected | 23.1% | 23.1% |

**This is a partial fix and should not be recorded as a solved problem.** Top-label
agreement is still ~78%, because the remaining sameness is *real*: the same one or
two expensive attackers genuinely sit outside most shapes. Face validity on Man
City — Guardiola `box striker €75m · advanced creator €31m`, Conte `box striker
€65m · advanced creator €52m`, Allegri `advanced creator €120m` alone (his 3-5-2
fields two strikers, so Marmoush stops being stranded at all). That contrast was
previously invisible under the flat €40m.

**Known consequence, accepted:** on squads whose whole value range sits near the
€5m `strand_floor` the strand can empty entirely (Venezia: max player value
€8.5m; 70 of 81 drawers now show nothing). This is a *correction* — every euro
Venezia's old panel displayed was a depth player no shape would start — and the
frontend already degrades to "Natural fits across the pitch…". Do not "restore"
those numbers by dropping the filter.

### 3.4 Slot/archetype gaps (what the coach then needs)

For each slot *instance* the coach's shapes require, record the eligibility of
the player assigned to it. Profile-weighted across shapes, a slot is a **gap**
when its best available fill is a stretch (assigned eligibility `< 0.5`) or when
the marginal player is cheap relative to the league-position norm. Roll up to a
**needs list** by slot type / archetype: *"no natural left wing-back (best fill
0.35); thin at destroyer DM."* This is the direct hand-off to the recruitment
target finder (the inverse-builder idea, a separate plan) — the gap list is
exactly a shopping list of archetypes.

### 3.5 The one scalar, kept honest — computed, but NOT displayed

The model also carries a deployment-cost scalar:

```
deployment_gap(C, T) = max_f bestXI(T, f)  −  cr_deployable(fvals, p(·|C), r_C)
```

i.e. best-XI value the coach's *shape preferences and rigidity* leave on the
table versus the squad's single best shape (a €/% number, **not** points).
`cr_squad_fit()` computes and ships it (`gap_pct`, `gap_eur`), but **QA
(2026-07-15) showed it should not headline the panel**, for two reasons found on
the City card:

1. **It mis-orders the flagship case.** The "best shape" is the *value-maximizing*
   XI, which for City is a two-striker shape cramming Haaland + Marmoush + the
   creators. A one-striker possession coach (Guardiola, 4.5%) therefore looks
   *more* wasteful than a two-striker back-3 coach (Conte 2.2%, Allegri 1.7%) —
   backwards as a fit read, because the anchor is a value artifact, not a
   tactically sensible XI.
2. **It doesn't reconcile with the strand list.** `gap_eur` (rigidity-blended
   deployment shortfall, €36m for Guardiola) and the strand total (raw benched
   value, €189m) are different quantities; showing both invites a "€36m vs
   €189m?" contradiction.

Resolution: the panel **leads with the strand (§3.3) and gap (§3.4) lists**,
which are internally coherent and genuinely coach-differentiating (Conte's 3-5-2
strands €100m of advanced-creator value because it has zero wide slots; Allegri's
back-3 €193m; Guardiola less). `gap_pct`/`gap_eur` stay in the JSON for a possible
future team-level card but render nowhere. This is the exploratory-labeling
discipline of §0 applied to presentation: keep the robust description, drop the
gameable scalar.

---

## 4. Two directions of use

1. **Coach → squad (diagnostic on a candidate).** On a team page's suggestion
   card, an expandable "Squad fit" panel per coach: the deployment-gap %, the
   top-3 stranded-value archetypes, the top-3 gaps. Answers "what happens to *our
   squad* if we hire *him*."
2. **Team → recruitment (aggregate need).** On the team page itself, independent
   of any one coach: run §3.4 across the *recommended* coaches (or the squad's
   own best shapes) and surface persistent gaps — positions the squad is thin at
   under *most* plausible setups. Feeds the future recruitment finder.

Direction 1 is the smaller, self-contained build and should ship first.

---

## 5. Where it lives

- **Team pages** (`site/data/teams/*.json`, `site/js/team.js`): clicking a
  similarity card opens a **right-side pop-up drawer** with that coach's header,
  plausibility badges, and the squad-fit detail (revised 2026-07-15 from an
  inline expandable panel — Andrew preferred keeping the cards clean). The drawer
  is a full-height overlay above the sticky header (z-index 110/111) with a
  backdrop; Escape / backdrop-click / × close it. Normal click opens the drawer;
  ctrl/⌘/middle-click still follows the card's `href` to the coach profile (also
  linked inside the drawer). The heavy lifting is precomputed in R and shipped in
  the JSON (frontend stays dumb, per house style) — per shown coach: `strand`
  (archetype label + €m) and `gaps` (slot label + best-fill); `gap_pct`/`gap_eur`
  ship but are not displayed (§3.5). Small payload (~a dozen rows per coach).
- **Team builder** (later, optional): the same panel against the *built* XI +
  chosen formation — "your 3-4-3 strands your two natural fullbacks." Reuses the
  identical assignment differ, client-side, against the builder's exported
  eligibility matrix.

---

## 6. Validation / sanity (no new statistical gate needed)

Because this adds no model, "validation" is consistency + face validity:

1. **Conservation unit test:** for every (coach, team), assigned-XI value +
   benched value + out-of-role deficit reconciles against total squad value
   considered; profile-weighted `cr_deployable` recomputed from the assignment
   equals the recommender's stored value (bit-for-bit).
2. **Face validity spot checks:** Gasperini (97% back-3) strands orthodox
   fullbacks and needs wing-backs; a two-striker coach at a one-elite-striker
   club strands the backup ST as low value, not high; a possession coach's shapes
   strand nobody at a deep, balanced squad (gap ≈ 0). Guardiola at City → near-zero
   deployment gap (the squad is built for his shapes).
3. **Cross-check vs recommender:** the coaches with the largest deployment gaps
   should be exactly those whose exploratory "Shape" column is most negative for
   that team. If not, a bug.

No chromote round is needed for the R computation; one screenshot pass for the
site panel (light/dark/mobile), consistent with prior UI additions.

---

## 7. Implementation plan

| Phase | Work | Output |
|---|---|---|
| 0 | Refactor `cr_best_xi_value` → `cr_best_xi_assign` returning the assignment; value fn wraps it. Conservation unit test. | assignment API |
| 1 | `cr_squad_fit(coach_id, team_season_id, ...)`: profile-weighted stranded value (§3.3), gaps (§3.4), deployment gap (§3.5). Face-validity script. | per-pair diagnostic |
| 2 | Persist into `recommender.rds` for the ~96 latest-season big-5 teams × their shown coaches (`cr_save_results()` gains a `squad_fit` block). | results file |
| 3 | `se_suggestions()` embeds the compact per-coach fit block into team JSON; `team.js` collapsible panel + CSS (both themes). | site |
| 4 | Screenshot QA (Atalanta/City/a thin squad), link sweep, doc + session log. | shipped |

Phases 0–1 are the substance (~a day); 2–4 mirror prior site additions.

---

## 8. Known limitations (state on the panel / in the writeup)

- **Exploratory, by inheritance.** The deployment layer is not a validated
  hiring signal; this diagnostic explains it, it does not upgrade it. No points
  claim anywhere.
- **Kickoff formations only** (same as the recommender) — in-game shape shifts
  are invisible.
- **Archetype is lagged and big-5 only**; players new to the big-5 use the
  TM-position fallback (flagged), and the whole feature is big-5-team only.
- **Value ≠ availability.** Stranded "value" is market value, not a claim the
  player is unhappy or should be sold; a squad legitimately carries depth. The
  panel describes shape mismatch, not roster advice.
- **Static squad.** Uses the club's current-season squad; it does not model the
  transfer window the club would actually run around a hire.
