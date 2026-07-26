# How It Works

*A plain-language explanation of what this project measures and what each page of the
site shows.*

---

## The short version

Football clubs do not compete on equal terms. A squad worth €900m is expected to
finish above a squad worth €90m, and usually does. So "who had the best season?" is
mostly a question about money, and it tells you almost nothing about the manager.

This project asks a different question: **given what a squad was worth, how did the
team actually do?**

1. Estimate what each team's points *should* have been, from the market value of the
   players who actually played.
2. Subtract. What is left over — the **residual** — is performance the squad's price
   tag does not explain.
3. Attribute that leftover to the coaches who were in charge, across their whole
   careers and every club they worked at.
4. The result is one number per coach, turned into a letter grade.

Everything on the site is either that number, something that number is built from, or
a test of whether that number is real.

---

## The model, step by step

### Step 1 — What is a squad worth?

Every player on Transfermarkt carries a market value in euros. Add them up and you
have a squad value. But a €70m striker who tore his ACL in August did not help anyone,
and the €4m academy graduate who played every minute did.

So the project uses **minutes-weighted squad value**: each player's value is multiplied
by the share of league minutes he actually played, then summed. It is a measure of the
value a team *put on the pitch*, not the value it owned.

This was the project's original hypothesis, and it holds: minutes-weighted value
predicts final points better than raw squad value, in 14 leagues over 21 seasons, and
the margin survives every cross-validation test thrown at it. It is a small margin
(about 0.016 points per game) but a consistent one.

### Step 2 — What should this team have scored?

A single model, fitted across all 14 leagues and 21 seasons, turns squad value into
expected points per game. Two details matter:

- **Values are compared within a league-season, not across them.** Being worth €200m
  means something different in the 2024 Premier League than in the 2008 Eredivisie. The
  model looks at how far above or below the league's average a squad sits that year.
- **Each league gets its own baseline.** Some leagues are more predictable than others.

Where you see **"expected points"** on the site, this is where it comes from.

### Step 3 — The residual

**Residual = actual points − expected points.** It is the single most important
quantity on this site, and everything downstream is a way of slicing it.

A residual of +0.20 PPG means a team beat its squad-value expectation by a fifth of a
point per game — roughly +7.6 points over a 38-game season. Across the dataset the
typical season lands within about ±0.24 PPG of expectation.

The residual is not "the coach." It contains luck, injuries, referees, a hot goalkeeper,
a favourable fixture list, and a hundred other things. The next step is what separates
the coach's part from the noise.

### Step 4 — From residuals to a coach number

A single good season proves nothing. The trick is that most coaches appear **many
times** — different seasons, different clubs, sometimes different leagues. If a coach's
teams keep beating expectation after he changes squads, that is harder to explain as
luck.

A mixed-effects model estimates, simultaneously, how much of the leftover belongs to
**the coach**, how much belongs to **the club** (some clubs consistently over-run their
valuations for reasons that outlive any manager), and how much is season-to-season
noise. Two features of that estimate are worth knowing:

- **Long stints count more than short ones.** A caretaker's six games carry far less
  weight than a full season, because a six-game residual is enormously noisy.
- **Thin records are pulled toward the middle.** A coach with two spectacular seasons
  gets a number closer to average than his raw record suggests — the model does not
  believe a small sample until it repeats. This shrunken estimate is what the site
  labels **BLUP**, in points per game.

The headline result of the project is that this coach term is real: performance above
squad-value expectation follows the manager more than it stays at the club.

### Step 5 — Grades

A BLUP of +0.043 PPG is not something anyone can read. So the graded coaches are placed
on a bell curve: the average graded coach scores **75**, and each standard deviation is
worth **10 points**, with ordinary letter cutoffs on top (A ≥ 93, B ≥ 83, C ≥ 73, and so
on down to F).

Two consequences to keep in mind:

- **Grades are relative to other coaches in the ranking**, not to some absolute
  standard. A C is an average professional manager, not a bad one.
- **A coach must earn a grade.** The bar is roughly **109 career games** in that ranking
  (or a result strong enough to be statistically significant on its own). Below it, a
  coach still appears on the site with his stints and residuals, but with no grade —
  the data cannot tell his record apart from luck. Of 2,445 coaches in the dataset,
  **566** clear the bar in the all-leagues ranking and **224** in the top-5 ranking.

### What the model has seen

Everything on the site — league tables, team pages, coach grades — is fitted on the
full span, **2005/06 through 2025/26**. When a new season is scraped it is added to the
fit, and every grade is recomputed from scratch over the whole history.

That raises an obvious question, and it is worth answering plainly: if the model has
been fitted to every season it displays, how can any of it be a *test*? A model can
always explain a season it was fitted to.

The answer is that the tests on the "Does it work?" page were run **before** the fit
moved. Test 3 in particular took the grades as they stood at the end of 2024/25, froze
them, and used them to predict 2025/26 while that season was still unplayed from the
model's point of view. The result of that test is a fact about a specific run and does
not change when the model is later updated. Once the season had been scored, it was
folded into the fit like any other.

So the grade you see on a coach page today is **not the same number** test 3 validated
— it is a later version of it, one that has since absorbed 2025/26. The validation page
says so on the card. What carries over is the finding: grades built this way predicted a
season they had never seen, which is evidence about the method, not about any one
number.

Each new season repeats the cycle: scrape it, score it against the frozen grades, record
the result, then refit.

### The two cuts

Every grade on the site carries a label: **"Top-5 leagues"** or **"All leagues."**

- **Top-5 leagues** grades a coach only on his work in the Premier League, La Liga,
  Serie A, Bundesliga and Ligue 1.
- **All leagues** uses all 14, adding the Championship, Eredivisie, Liga Portugal,
  Jupiler Pro League, Süper Lig, Danish Superliga, Ekstraklasa, HNL and LaLiga 2.

They are **separate rankings with separate bell curves**, so the same coach can be a B+
in one and an A− in the other, and neither is wrong. That is why the site never shows a
grade without its cut label. A coach who dominated the Eredivisie has an all-leagues
grade and often no top-5 grade at all.

---

## The words the site uses

| Term | What it means |
|---|---|
| **Squad value** | Sum of Transfermarkt market values for a squad, in euros. |
| **Minutes-weighted value** | The same, but each player counted in proportion to the minutes he played. The project's core metric. |
| **Expected points** | What the model predicts from squad value alone. |
| **Residual** | Actual minus expected, in points per game. Positive = beat the squad. |
| **Stint** | One coach at one club in one season. A season with two managers is two stints. |
| **BLUP** | A coach's estimated effect in PPG, shrunk toward zero when his record is thin. |
| **Grade** | The BLUP placed on a bell curve, 0–100 plus a letter. |
| **Cut** | Which ranking a grade comes from — top-5 leagues or all 14. |
| **Significant** | The coach's record would be unlikely to arise by chance, after accounting for the fact that thousands of coaches are being tested at once. Very few clear this bar; most graded coaches do not, and that is expected. |
| **Archetype** | A playing-style category a player is sorted into from his on-ball and off-ball numbers — "wide creator," "destroyer," and nine others. |

---

## The site, page by page

### Home — the leaderboard

The front page is the ranking. Toggle between the two cuts; the table gives each coach's
grade, score, BLUP, career stints, clubs, games, and mean residual. "sig" marks the rare
coaches whose record is individually significant. The stat tiles above it are the size
of the dataset: 14 leagues, 21 seasons, 5,339 team-seasons, 2,445 coaches.

The league tiles at the bottom, the dropdown in the header, and the search box (coaches,
teams, leagues) are the ways into everything else.

### Coach page

The deepest page on the site. In order:

**Grade card.** Letter, score out of 100, rank, BLUP, and the same coach's standing in
the *other* cut underneath. Unranked coaches get an explicit "record too thin to grade."

**Career points per game.** One club crest per stint, actual PPG plotted against the
dashed expected-PPG line from the squad-value model. Click a crest for that stint's
detail — games managed, actual and expected points, and the residual in both PPG and
total points. Sort chronologically or best-to-worst.

**Where his edge comes from.** The same overperformance the grade is built on, split
into two halves: goals scored above what the squad's value predicted, and goals conceded
below it. It answers "good at what?" — attacking tilt, defensive tilt, or balanced. Only
graded coaches have it, because it is a re-slice of the grade rather than a new
measurement. Where a coach's goal edge disagrees with his points grade (it happens —
goal difference and points track each other closely but not perfectly), the page says so
in plain words rather than leaving a contradiction on the screen.

**Style of the teams he coached.** Nine axes — possession, pressing intensity,
directness, width, shot volume, chance quality, defensive solidity, set-piece reliance,
lineup stability — each as a percentile among the coaches with comparable data, plus an
inset block for where up the pitch his teams won the ball back.

The title of that card is doing real work. The project tested whether style belongs to
the coach or the club, and on **seven of these nine axes the club explains more than the
coach does** — the same club under two different managers looks more alike than the same
manager at two different clubs. Only **lineup stability** and **pressing intensity**
travel with the coach; those two are dotted on the chart. So the card describes the
style of the teams he ran, never "his style" in the abstract.

**Preferred formations.** How his matches split across shapes, weighted toward recent
seasons, plus a one-line read on how rigid or adaptable he is.

**Player-type fit.** Whether particular squad archetypes track his over- or
under-performance. Explicitly descriptive — with 4–10 stints per coach, no individual
coach × player-type pattern survives proper multiple-testing correction, so only
patterns that recur under two different specifications are shown at all.

### Team page

**Header.** Mean residual, best season, toughest season.

**Seasons: actual vs expected.** A dumbbell per season — gray dot expected, coloured dot
actual. Click a season to highlight its coaches in the table below.

**Coach history.** Every stint at the club: coach, his overall grade, games, PPG,
expected PPG, residual. Sortable chronologically or best-to-worst. This is the club's
own record of who over-delivered against the squad they were given.

**Suggested coaches** (big-5 clubs with a current squad). Coaches who thrived with
squads shaped like this one — matched on the player-type mix of their overperforming
spells, tilted slightly toward overall quality. Filter chips narrow by career
plausibility: has coached in this league, this country, big-5 proven, similar club
level, recently active, domestic.

Clicking a card opens a **drawer**: the coach's career dossier (span, clubs, formations,
rigidity) and a **squad fit** read — which of this squad's value his usual shapes tend
to leave on the bench, and which positions those shapes can only fill with a player out
of role. That is stated in euros and positions, never in points, because it is a
judgment aid rather than a validated forecast. The page says as much, including the part
where it will cheerfully suggest hiring Guardiola, since contracts and wages are not
modelled.

**Squad value over time.** Total value in euros, and minutes-weighted strength relative
to the league average that season.

### League page

Pick a season. The **standings** carry the usual columns plus three of the project's own:

- **Expected** — points the squad-value model predicted.
- **Deserved** — where the club *should* have finished on that expectation, with the
  swing against its actual position.
- **± vs expected** — the residual, in points.

This is the "deserved table," and it is where the model is most fun and most legible.
Leicester in 2015/16 finished first and deserved tenth. Sort by overperformance to see
the season's real story.

Below: a diverging bar chart of the same residuals, and league-wide statistics — how
well squad value explains points in this league, plus all-time over- and
under-performers and the most-used coaches.

One honest caveat is printed on the page: extreme entries from pre-2010 seasons in
smaller leagues can reflect patchy market-value coverage rather than genuine
overperformance.

### Player growth

A different question, and the only page not about coaches.

The model expects a player's market value to move along a trajectory set by his age,
his current price, his position and his recent momentum. The **chart at the top is that
expectation** — one curve per position group, running from roughly +65–81% a year at 16
down to about −36% at 34, crossing zero at 26 for outfielders. Goalkeepers are the
outlier the curve makes visible: only +11% at 16 and nearly flat until the mid-twenties,
crossing zero at 27.

The **leaderboard** ranks the players who beat their own curve by the widest margin —
genuine breakouts rather than expensive teenagers getting more expensive. Filter by
position, league or era.

The page states its own limit prominently: **this describes players, not coaches.** The
project tested whether a coach's share of value growth repeats across his career. It
does not, so no coaching credit is taken from this list.

### Team builder

Pick one of 22 real formations, click a slot, and choose from every big-5 player-season
since 2015/16 — cross-era XIs allowed. The readout gives the XI's value, its value
percentile, and its player-type mix. Fill all eleven and you get the same descriptive
coach-similarity grid the team pages show, computed live against your XI.

Deliberately absent: any predicted points total for a fantasy XI. A 2016 Leicester
midfield behind a 2024 Bayern attack is outside anything the model has evidence about,
and inventing a number for it would be fiction.

### Does it work?

The page that justifies the rest. Any model can explain the past; the question is
whether the coach grade predicts things it was never shown. Three tests, on three
deliberately different designs, each vulnerable to something the other two are not:

| | Design | Question | Result |
|---|---|---|---|
| **Test 1** | Out-of-sample forecast | Does a coach's grade improve the forecast of a *new* appointment? | Forecast error falls; p = 0.0027 |
| **Test 2** | Natural experiment | When one club swaps managers, does the incoming grade predict what changes? | ≈ +0.7 pts/season per SD of grade; p = 0.0015 |
| **Test 3** | Future holdout | Do grades frozen before a season predict that season? | ≈ +1.4 pts/season per SD; p = 0.0024 |

Test 3's grades were frozen at the end of 2024/25, before 2025/26 was played. That
season is now part of the fit ([what the model has seen](#what-the-model-has-seen)), so
the grades on coach pages today are a later vintage than the ones the test scored.

Tests 1 and 2 are the pair readers conflate — both are about hiring. The difference:
test 1 pools appointments across hundreds of clubs, while test 2 holds a single club
fixed across a single swap.

The page then goes inside two of them. For test 3, two charts: every club in the tested
season plotted against what the frozen model expected (the cloud around the diagonal is
the residual, made visible), and each coach's prior grade against what his team actually
went on to do. That second chart is deliberately unflattering — the correlation is only
0.17, one part-season is a noisy measure of anyone, and the claim is the tilt of the
line and the rise across the three group averages, not any individual dot.

For test 2, **sacking efficiency**: because the model sees results *minus* what the
squad was worth, it can ask how often a sacked manager was actually doing well with a
weak squad. About one mid-season sacking in six fires an overperformer, and those are
the ones that backfire — the replacement gets worse on average, where a defensible
sacking is followed by improvement. The table of examples is the model's catalogue of
regret, surfaced from the residual alone.

---

## How much to trust each number

The site deliberately holds its own findings to different standards, and labels them
accordingly. From strongest to weakest:

**Validated — predicts things it was not shown.**
The minutes-weighted squad-value model, and the coach quality grade built on it. Three
independent tests, three different designs, all agreeing. This is the project's claim.

**Defensible — a re-slice of something already trusted.**
The attack/defence split on coach pages. It makes no new leap; it cuts the same
overperformance by goals instead of points.

**Descriptive — accurate about the past, not a forecast.**
The style fingerprint, preferred formations, player-type fit, the coach suggestions and
the squad-fit drawer. Each of these is a true statement about what happened. None of
them has been shown to predict anything, and each says so on the page.

**A player descriptor, not a coach one.**
The player-growth leaderboard.

The one rule that runs through all of it: a number's presence on the site is not an
endorsement of a causal story about it. Where the evidence stops, the copy stops.

---

## What the model does not do

- **It does not judge coaches against each other in the abstract** — only against what
  their squads were worth. A manager who wins the league with the most expensive squad
  in it has met expectation, not beaten it.
- **It does not know about anything outside the pitch and the price tag.** Injuries,
  boardroom chaos, wage bills, transfer strategy, contract lengths, European fixture
  congestion — none of it is in the model. All of it lands in the residual.
- **It does not model availability.** Suggested coaches are ranked without any knowledge
  of who is employed, wanted, or affordable.
- **It cannot say what makes a good coach good.** The project tested style, player-type
  fit, formation deployment and player value growth as explanations for the quality
  grade, and none of them survived. The grade is real and it is a single number; what it
  is made of is beyond what this data can show. Those null results were kept and reported
  rather than buried, which is why they are not dressed up as findings anywhere on the site.
- **It inherits its data's limits.** Market-value coverage before about 2010 in smaller
  leagues is patchy, and the style and player-type layers only exist for the big five
  leagues from 2015/16, because that is where the underlying data starts.

---

*Sources: Transfermarkt (squad values, minutes, results, coaches) and SofaScore
(per-player style data for the big-5 leagues, 2015/16 onward). Every figure on the site
is regenerated from the analysis pipeline; nothing is hand-entered.*
