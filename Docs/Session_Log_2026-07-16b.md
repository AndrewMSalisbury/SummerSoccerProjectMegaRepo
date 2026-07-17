# Session Log — 2026-07-16b: Coach Descriptive Profile, Phase 6 (site + writeup)

## Trigger

Andrew: "Lets do phase 6 and investigate the open question later" — i.e. build the
site surface for the descriptive-profile package (phases 1–5 landed earlier the
same day, analysis only), and defer the `r(club_pct, blup) = +0.39` question that
the 07-16 log flagged as untested.

This closes `Docs/Coach_Descriptive_Profile_Design.md`. Nothing in the analysis was
re-run; this session is presentation, plus the writeup part that phase 5 left owed.

## Two decisions Andrew made up front

| Question | Choice | Consequence |
|---|---|---|
| Who gets the Layer A tilt? | **Graded coaches only**, on their headline cut | 545 of 958 — the design's "every coach gets a tilt" (§2.2) loses to consistency with the display certification bar |
| Ship the xG cut on coach pages? | **No — writeup only** | 3 seasons, no coach ≥5 stints, zero FDR-significant; a coach page flattens a recent-form lens into a career verdict |

Both are recorded in design §6 as as-built notes.

## What shipped

**`src/site_export.R`** — `se_coach_strengths()` and `se_coach_style()` onto the
coach JSON, plus `se_pct_rank()`. Strengths are read from the *same cut* as the
headline rating (`se_rating()$cut`) so the split and the grade describe one number.
Style percentiles are precomputed once in `se_load()` over the whole displayed
population.

**`site/js/charts.js`** — two new charts:

- `strengthBars()` — Layer A. Two rows on **one fixed domain** (`STRENGTH_DOMAIN`
  = ±0.26 goals/game) shared across both rows and every coach page.
- `styleBars()` — Layer B. Nine percentile rows on a 0–100 track with a
  50th-percentile midline, one hue, `coach_owned` dots on the two axes phase 4
  cleared.

**`site/js/coach.js`** — `renderStrengths` / `renderStyle` / `edgeNote` /
`tiltLabel`. **`site/css/site.css`** — `.strength-lede`, `.tilt-chip`, `.key-dot`.

**`Docs/Summary_of_Findings.md`** — Part 8 (~16k chars, 4 tables, 6 subsections),
covering all three layers, the xG cut, the coach-vs-squad result, and the Layer C
null; Limitations item 9; a new closing paragraph. Regenerated `writeup.html`
(14 TOC sections; Part 8's four tables verified converted, row and header counts
correct).

## Design decisions made during the build (and why)

- **The radar became horizontal percentile bars.** The design offered "a style
  radar (or small-multiple bars)". Nine axes of heavily-compressed SDs on a radar
  is the standard unreadable-fingerprint failure, the axis order would be
  arbitrary, and the enclosed area would encode nothing. The reader's actual job —
  "more or less than a typical coach" — is a baseline comparison, which is a bar
  around a midline. It also makes room to mark the coach-owned axes inline.
- **Style bars use one hue, not the site's `--pos`/`--neg` diverging pair.** These
  axes have no good/bad polarity — more possession is not better — and painting
  them with the above/below-expectation ramp would assert exactly the verdict
  phase 5 proved the data cannot support. The midline carries "more/less" alone.
- **Percentiles rank within the ≥38-game display set** (256 coaches), not all 337
  profiles: the reference class a reader is shown should be the one the number is
  computed against. This differs slightly from the percentiles quoted in the design
  doc and the 07-16 log, which used a ≥100-game reference (Simeone solidity 94th
  here vs 92nd there; possession 74th here vs 64th there). Not a discrepancy — a
  different, stated denominator.
- **The fixed shared x domain on Layer A is deliberate.** Defence bars are much
  shorter than attack bars for nearly every coach. That is phase 1's finding (coach
  variance is far larger on goals-for: LRT χ² = 160 vs 60), and giving the rows
  their own axes would erase it while looking tidier.

## The Simeone problem, found by rendering

The first render of a B-graded Simeone read:

> "Across 15 stints, Diego Simeone's teams **fell short of** their squad-value
> expectation by 0.03 goals of goal difference per game"

— directly beneath a grade card reading **B · rank 27 of 215 · BLUP +0.043**. Both
statements are true (this is the phase 1 finding that his points overperformance is
*not* a goals overperformance), but side by side and unexplained they read as a
bug in the site.

Fix: `edgeNote()` fires whenever the goal edge and the BLUP disagree in sign, and
names the gap in place — "his teams converted the goal difference they had into
more points than expected. This split describes that gap rather than explaining
it." Verified present on Simeone (2 `.strength-lede` nodes) and absent on Guardiola
(1). The generic footnote about r = 0.86 was not enough on its own: a reader who
sees a contradiction stops before reaching a footnote.

## Verification

**JSON audit** (`export_check.R`, all 2,341 coach files parsed):

- 545 with `strengths`, 256 with `style` — both match the expected populations.
- **0** coaches carry strengths without a rating (the certification-bar gate holds).
- `strengths$cut == rating$cut` for **all 545** — no coach shows a tilt from one cut
  under a grade from the other.
- All 256 style blocks carry exactly 9 axes; `seasons` survives `auto_unbox` as an
  array (the documented `I()` gotcha).

**Face validity** — Guardiola: possession 99th, shot volume 99th, solidity 99th,
directness 4th, width 5th, **pressing intensity 45th with height 98th** (the phase 3
finding that his press is height, not intensity, renders correctly and legibly).
Simeone: solidity 94th, width 13th, chance quality 84th — the refined caricature,
not the received one.

**Chromote QA** — Guardiola + Simeone, light + dark + 375px. All five cards render;
`scrollWidth == clientWidth` on every card; the new cards sit between the career
chart and the formations card as designed.

## Follow-up: pressing height promoted out of the footnote

Andrew: "Can we show in a more clear way where the ball is won back (pressing
height)". It was one line of footnote prose ending in a bare percentile — the
weakest thing on the card, and "pressing height" is jargon in a way "possession"
is not.

Now its own inset block (`renderPressingHeight` + `charts.js spectrumBar`): a
heading, a plain-English verdict ("His teams won possession in the attacking third
more often than 74% of coaches — a fairly high line"), and a **named-pole scale**
(Deep block ↔ High press) with the marker at the percentile. Inset and visually
separated from the nine axes because it is a different measurement — per season,
not per match — so it must not read as a tenth axis.

**The rejected design is the instructive part.** The obvious "clearer" answer is a
marker on a drawn pitch. It would be a fabrication: the stat is the *share of
possession won in the attacking third, ranked against other coaches*, so the 98th
percentile does not mean "wins it 98% of the way upfield" — a pitch would claim a
physical location the data does not contain. Poles carry the meaning as labels;
the scale stays a rank. Recorded in design §6 and CLAUDE.md so it is not
"improved" into a pitch later.

Two wording bugs the render caught, both at the tails (a midpoint rank over 256
really does round to 0 and 100):

- Flick read "more often than **100% of coaches**" — he cannot beat himself.
- Bruce read "more often than **0% of coaches**" — which reads as *never won it
  there at all*, not *ranked lowest*.

`heightSentence()` gives the tails their own phrasing ("more/less often than almost
every coach in the data"); the marker label likewise becomes "highest/lowest of
256" rather than "100th/0th percentile". A bare `${pct}th` also produced "1th" and
"22th", so `ordinal()` was added.

Verified on the full spread — Flick (100, high press), Bruce (0, deep block),
Míchel (99 + blended caveat), Simeone (56, mid-block), Guardiola (98) — light,
dark, and 375px, no overflow anywhere. Face validity is strong in passing: Bruce
sits at possession 4th / pressing 1st / directness 94th, Flick at possession 99th /
shot volume 100th / directness 8th.

## Follow-up: the squad-fit strand was mostly a squad constant

Andrew, reading the shipped site: *"when I click on suggested coaches on a team's
tab they are showing nearly identical positions and value left out of the squad
despite different formations. Can you verify if this is correct?"*

It was correct arithmetic and a misleading panel. Two structural facts:

1. **The max-value XI is near formation-invariant.** On Man City any two of the 22
   shapes share **8–10 of 10** outfield starters (median 9); 6 players start in all
   22, **24 of 36 start in none**. The XI maximises value and eligibility is broad,
   so a shape change moves a slot, not a team.
2. **`rep_w` sums to 1**, so a player benched in every shape contributes his **full
   value identically to every coach**.

Result: a flat `destroyer €40m` — Nico González, started by 0 of 22 shapes — on
**all 81** Man City coaches, with Bernardo Silva (€38m, also 0 of 22) completing an
invariant €78m floor worth **40–50% of every coach's strand total**. Site-wide,
**88.9%** of a team's coaches shared the same *top* strand label. The panel was
answering "how deep is this squad?" from inside a per-coach drawer.

Fix (Andrew chose option 1 of 3): `cr_startable_players(squad)` — players making
the best XI in **≥1 of the 22 shapes** — computed once per team and passed into
`cr_squad_fit`, which now strands only players in that set. The quantifier is
load-bearing: narrowing it to the coach's *own* repertoire would delete exactly
the coach-specific signal (a player Guardiola benches but Allegri starts *is*
stranded by Guardiola). Comments in both functions say so.

| | before | after |
|---|---|---|
| same top strand label (median) | 88.9% | **77.8%** |
| same top strand label (Q1) | 74.1% | **64.2%** |
| strand € retained | — | ~74% |
| `gaps` list (untouched by design) | 23.1% | 23.1% |

Face validity, Man City: Guardiola `box striker €75m · advanced creator €31m`,
Conte `box striker €65m · advanced creator €52m`, Allegri `advanced creator €120m`
alone — his 3-5-2 fields two strikers so Marmoush stops being stranded at all.
That contrast was previously buried under the identical €40m.

**Recorded as a partial fix, not a solved problem.** Residual ~78% top-label
agreement is real: the same one or two expensive attackers genuinely sit outside
most shapes. Accepted consequence: squads near the €5m `strand_floor` can empty
out (Venezia, max player value €8.5m: 70 of 81 drawers now show nothing) — a
correction, since every euro its old panel showed was a depth player no shape
would start, and `team.js` already degrades to "Natural fits across the pitch…".

Regenerated `recommender.rds` (96 teams) reusing the existing `meta$payoff` — the
LOSO validation is unaffected by a display-side filter — then re-exported the site.
QA'd the drawer in chromote on Man City (discriminating) and Venezia (the empty
case); no overflow.

## A pre-existing bug the QA caught

Mobile QA reported `bodyOverflow: 22` on Guardiola — but **0** on every card. The
culprit was `.grade-card` in the page header, not the new work: `flex: 0 0 auto`
made it unshrinkable, and its widest line ("All leagues: A+ · rank 1 of 545 · BLUP
+0.137") exceeds a 375px viewport. Confirmed pre-existing by testing an *unranked*
coach (id 1007), who has no grade card and overflowed by 0.

This has been sideways-scrolling **every one of the 545 graded coach pages** on
mobile since the site shipped on 2026-07-10. Fixed with `flex: 0 1 auto;
min-width: 0`; re-verified at 0 overflow on graded, unranked, home and team pages.
Unrelated to phase 6 — recorded here because this QA is what found it.

## Reproducing

```r
# working dir src/
source("site_export.R"); export_site_data()   # ~4 min incl. builder + assets
```

No analysis re-run is needed — phase 6 reads `coach_strengths_{top5,14league}.rds`
and `coach_style.rds` as they were written earlier on 2026-07-16. Re-run
`run_coach_strengths()` / `run_coach_style()` before exporting only after an M4/M5
refit.

The squad-fit follow-up *does* need `recommender.rds` rebuilt (the strand is
computed R-side), but not the LOSO payoff run — reuse the stored folds:

```r
source("coach_recommender.R")
scorer <- cr_build_scorer()
old <- readRDS("data/results/recommender.rds")
cr_save_results(scorer, old$meta$payoff)   # payoff is unaffected by a display filter
source("site_export.R"); export_site_data()
```

## Loose ends / next

- **Still not committed.** The working tree now carries phases 1–6 plus the
  uncommitted 2026-07-14/15 work (player images, squad-fit drawer, coach
  formations). Everything in the descriptive-profile package is now complete and
  verified, so this is a natural commit point.
- **The open question, explicitly deferred by Andrew:** `r(club_pct, blup) = +0.39`
  — coaches at bigger clubs grade higher. Benign if better coaches are hired by
  better clubs; a mis-specification if the value model under-predicts big clubs. The
  published ranking rests on which it is and nothing has tested it. This is now the
  most load-bearing untested claim in the project.
- **Not done, and probably not worth doing:** the team-builder squad-fit panel
  (deferred 2026-07-15) and the 2025/26 `rating-breakdown` archetype validation.
