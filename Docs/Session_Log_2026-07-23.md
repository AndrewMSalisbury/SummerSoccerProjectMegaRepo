# Session Log — 2026-07-23: The forward-test charts, and swapping the published writeup

**Note on provenance:** this log was written after the fact (2026-07-24) from commits
`358ceb30` ("Grade graph", 17:16) and `60b67658` ("changed writeup", 22:54), which
shipped without one. The *decisions* below are all recoverable from the diffs and the
code comments they left behind; where a rationale is inferred rather than recorded, it
says so.

## What shipped

Two things, both on the presentation side — no model, no scrape, no `data/results/`
change:

1. **"Inside test 3" became two charts** on the validation page — the forward test's two
   questions, drawn instead of asserted.
2. **The published writeup is now a plain-language guide.** `Docs/How_It_Works.md` (new,
   355 lines / ~3.1k words) replaced `Docs/Summary_of_Findings.md` (~13.2k words) as the
   source of `site/writeup.html`.

## 1. The forward-test charts (`358ceb30`)

The validation page stated test 3's result in a card and then, underneath, listed the
2025/26 over- and under-performers. That is the wrong material for the page: the section's
job is to *show* the result the card above it states.

**Added** (`charts.js`, +292 lines; payloads from a rewritten `se_export_validation()`):

- **`expectedVsActual()` — Q1.** All 252 holdout clubs, expected vs actual, against a
  y = x reference. Both axes share one domain (a squashed axis would fake a tighter fit)
  and the unit is **PPG, not total points**, because the 14 leagues play 22–46 games.
  Dots use the site's `--pos`/`--neg` pair as a *polarity* encoding — which side of the
  line — not a ramp.
- **`gradeVsOutcome()` — Q2.** One dot per 2025/26 stint, prior grade against realized
  overperformance, carrying three things at once: the raw stints with **area = games
  played**, the games-weighted fit line, and the **tertile means**. Tertiles, not
  quartiles: at 219 stints the quartile Q3/Q4 gap (0.117 vs 0.060) sits inside its own
  SEs and would read as a real dip. Group SEs (~0.03 against a ±1.9 axis) render as 2px
  stubs, so they are stated in words rather than drawn.

**The chart is deliberately unflattering — r = 0.166.** That is the point of including
the group means: without them a validated result looks like a null, and without the
"the cloud is wide, single dots mean little" footnote the trend line oversells it. Only
the 219 graded stints are plotted (the 216 first-timers would pile into a stripe at
x = 0), so the chart quotes the **graded-only p = 0.0036** and names p = 0.0024 as the
all-stints headline — the two must stay apart.

**Cut in the same commit: the "who over/underperformed most in 2025/26" leaderboards**
(teams *and* coaches). They were descriptive colour on a page whose job is evidence, and
the same material already lives on the league pages (deserved table) and coach pages. The
export carries a comment saying so, to stop them being re-added.

Shared label idiom introduced here: a hairline leader from label to dot plus a
`paint-order: stroke` surface halo; label sets thin below 560px; `gradeVsOutcome` picks
its two labels by **separation** (best-graded + biggest overperformer), never the first
few in the array.

All of the above is recorded in CLAUDE.md (the "Inside test 3" bullets, added in this
commit).

## 2. The writeup swap (`60b67658`)

`se_export_writeup()` now reads `../Docs/How_It_Works.md`; the page title is "How it
works"; the header nav item reads **"How it works"** instead of "Writeup"; the home hero
says "read the guide". `writeup.html` went 1,095 → 367 lines. The TOC-from-headings
machinery is unchanged.

Every in-page reference was rewritten to match, and this is the substantive part:

- The footnotes that said **"See the writeup, Part 8"** (coach strengths, coach style),
  "Part 6" (player-type fit), "see the writeup's limitations" (league stats) and "See the
  writeup" (team suggestions) became **links to `writeup.html` reading "how it works"**.
- The validation page's **deep links were removed entirely** — the three `.val-card`
  "What this means" rows lost their `link` field and their `Part 7 →` / `Part 11a →` /
  `Part 11b →` anchors, and the "Why it takes three" card lost its Part 10 link.
- `players.js` dropped the parenthetical "(writeup Part 9)" from the
  player-descriptor-not-a-coach-one footnote.

**Consequence worth stating plainly, because nothing in the commit does:**
`Summary_of_Findings.md` is now an internal document with **no published surface**. The
project convention has been "a null lives in the writeup, not on the site" — the xG cut,
Layer C, the CDE (Part 9) and the market benchmark (Part 10) are all writeup-only. That
convention no longer means a reader can reach them; it now means they are documented for
whoever reads the repo. `How_It_Works.md` does carry the honesty gradient (its "How much
to trust each number" and "What the model does not do" sections name the four failed
explanations and the labelling rules), so the *stance* survived the swap even though the
statistics did not. Whether the technical writeup should be republished alongside the
guide is an open call, not a settled one.

*(Inferred, not recorded: the trigger appears to be that a 13k-word methods document was
the site's only explainer, and every page's footnotes pointed a general reader into it.
The guide is written for that reader — plain language, page-by-page, one table of terms.)*

## Files touched

| File | Change |
|---|---|
| `Docs/How_It_Works.md` | new — the published guide |
| `src/site_export.R` | `se_export_writeup()` source + title; `se_export_validation()` rewritten (scatter/bins/q2/q2_fit payloads; leaderboards dropped) |
| `site/js/charts.js` | `expectedVsActual()`, `gradeVsOutcome()` |
| `site/js/validation.js` | new "Inside test 3" section; deep links removed |
| `site/js/components.js`, `home.js`, `coach.js`, `league.js`, `team.js`, `players.js` | nav + footnote copy pointing at "how it works" |
| `site/writeup.html`, `site/data/validation.json` | regenerated |
| `CLAUDE.md` | "Inside test 3" bullets |

## Loose ends

- **CLAUDE.md and `Docs/Website_Design.md` still describe `writeup.html` as a rendering
  of `Summary_of_Findings.md`.** CLAUDE.md was corrected on 2026-07-24; Website_Design.md
  is a design record and still reads as-designed (§Writeup page scope, §6.3 file map).
- The technical writeup has no route from the site. If it should be published as a second
  page (`findings.html`), the export is a two-line change and the deep links that were
  removed here would come back.
- Otherwise unchanged from 07-22b: the three-validation block, the fan surfaces, and the
  forward test that is designed to re-run each new season.
