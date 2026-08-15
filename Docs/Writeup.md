# Coaching Quality Is Real, It Travels, and It Is One Number

**Measuring manager performance against squad value across 14 leagues and 21 seasons**

Andrew Salisbury · R · [live site] · [repository]

---

> **Abstract.** Squad market value predicts league points well enough that the gap between
> the two is the only place a coaching effect could live. Weighting each player's value by
> his share of team minutes improves that prediction significantly and out-of-sample. I
> decompose the residual from the improved model into coach and club random effects; the
> coach component is significant in both dataset cuts and larger than the club's in each.
> The resulting per-coach grade survives three independent validations, including a true
> future season the model had never seen. Four separate attempts to find *more* than that
> single number (tactical style, coach × player-type fit, player market-value growth, and
> an edge over bookmakers' closing odds) all returned nulls, and all of them are reported
> here. Everything ships as a public site and is reproducible offline from cached scrapes.

**What you are looking at:** a solo project, written in R, covering 5,339 team-seasons and
8,642 coaching stints across 14 European leagues from 2005/06 to 2025/26, with a live
public site and a fully cached, offline-reproducible analysis pipeline.

---

## 1. The question, and why it is hard

### 1.1 The asymmetry worth attacking

Player analytics is a mature public field. Expected goals, progressive carries, possession
value models and their descendants get argued about on television. Coach analytics is
almost entirely absent from that conversation, and yet a manager hire is the single most
consequential personnel decision most clubs make in a given year. Clubs spend eight figures
on a centre-back after a scouting process backed by a data department, and then hire the
man who picks him on the strength of reputation, a shortlist, and vibes.

That gap is the target. The specific question is narrow and answerable: **given what a
squad was worth, how did the team actually do, and does the answer follow the manager when
he moves?**

### 1.2 Why coaching resists measurement

Four properties of the problem make the naive approach useless, and every design decision
downstream is a response to one of them.

**The dominant input is not the coach's choice.** A manager's visible output is points, and
points are overwhelmingly determined by the squad he was handed. Ranking coaches by points
per game ranks clubs by wage bill with extra steps.

**Coaches are not randomly assigned.** Good coaches get hired by good clubs. Any positive
association between a coach's reputation and his results is therefore contaminated by
selection at the source. This is the objection a reviewer raises first, so I test it
directly in §6.5 rather than gesturing at it.

**The per-coach sample is tiny.** A career in this dataset is typically 3 to 10 stints of
10 to 40 games. Most managers never accumulate enough evidence to be told apart from an
average manager, no matter how good the model is.

**Short spells are enormously noisy.** I estimated the sampling variance of a stint's
per-game residual directly, and it comes out at roughly `Var(stint) ≈ 0.014 + 1.50/n` in
games. A 2-game caretaker residual carries about 19 times the sampling variance of a
38-game one. Treating those two observations as equally informative, which is what an
unweighted model does, hands the ranking to the noisiest data in it.

### 1.3 The hypothesis, stated so it could have failed

The project began with a written hypothesis and a written success criterion, both fixed
before any data was scraped:

> A team's minutes-weighted squad value predicts final points more accurately than raw
> squad value. The residual, meaning performance above or below expectation, is partly
> attributable to coaching quality. Coaches who consistently produce positive residuals
> across multiple teams should be identifiably better.

And the criterion:

> Success is a working coach ranking whose additional coaching variable significantly
> reduces the variation between the model and actual results (rough hope: a 25% reduction),
> **or** a sufficient disproof of the hypothesis plus work toward a replacement hypothesis
> that serves the same goal.

Three risks were named in advance, and each maps to a section below: the assumption that
coaches cause the variation (addressed in §6, where the proposed remedy, studying coaches
when they change clubs, became the event-study design); a ceiling effect from ranking on
league position (addressed by modelling points per game instead of rank); and coach-data
availability (addressed by building a coach-appointment scrape into the data layer, §3.1).

Declaring a numeric target in advance turned out to matter, because the target was missed.
The honest reduction in variance is a few percent, not 25%. §11 returns to that.

### 1.4 What this document claims, and what it does not

**Claims.** That minutes-weighted squad value is a measurably better predictor of points
than raw squad value; that the residual from that model contains a coach component that is
statistically significant and larger than the club component; and that the resulting grade
predicts outcomes it was not fitted on, including a genuinely future season.

**Does not claim.** That the effect is causal in any identified sense; that the model can
say *what* good coaches do differently; that any of it is exploitable in the transfer or
betting markets.

One vocabulary note, stated once and then carried by verb choice throughout: I use
*attributable to* in its statistical sense. Attribution assigns the variance in a residual
to a labelled grouping factor. **Attribution is not causation.** Where the text says a
coach's grade "predicts" an outcome, that is a claim about forecast accuracy under a
specific holdout design, and nothing more.

---

## 2. Data

### 2.1 Sources

**Transfermarkt**, via a custom R scraper, supplies everything the core model runs on:
per-player market values, per-player league minutes, coach appointment and departure dates,
and match results. This is the project's spine.

One consequence of scraping Transfermarkt is an engineering choice with a visible cost.
**Every identifier in the project is a URL.** A `league_season_id` is
`https://www.transfermarkt.com/premier-league/startseite/wettbewerb/GB1/plus/?saison_id=2024`;
a `player_id` is a profile URL. The cost is that every join in the analysis layer is a
string match on long, punctuation-heavy keys. The benefit is that there is no id-mapping
layer to maintain, no synthetic-key drift between scrape runs, and any row in any cache can
be pasted into a browser and checked against the source in two seconds. On a project where
the most dangerous failure mode is a silent mis-join, that last property earned its keep
repeatedly.

**SofaScore**, via a headless-Chrome scraper, supplies per-match player statistics, kickoff
formations, shot coordinates and positional heatmaps. Everything built on it (player
archetypes, the style fingerprint, formation profiles) is therefore restricted to the big
five leagues from 2015/16 onward, because that is where the coverage starts. SofaScore
rejects ordinary HTTP clients by TLS fingerprint (R's `httr` gets HTTP 403 regardless of
headers), which is why the scraper drives a real browser.

**football-data.co.uk** supplies match results with bookmakers' closing odds, used only for
the external market benchmark in §7.4.

### 2.2 Scope

| | Value |
|---|---|
| Leagues | 14 |
| Seasons | 2005/06 – 2025/26 (21) |
| Team-seasons | 5,339 |
| Coach stints | 8,642 |
| Distinct coaches | 2,445 (1,006 with an estimated effect) |
| Clubs | 505 |
| Graded coaches | 566 (all-leagues cut) / 224 (top-5 cut) |
| SofaScore span | 2015/16 – 2025/26, big-5 only |
| Odds benchmark | 51,977 matches, 2012/13 – 2025/26, 13 leagues |

The 14 leagues are the big five (Premier League, La Liga, Serie A, Bundesliga, Ligue 1)
plus the Championship, LaLiga 2, Eredivisie, Liga Portugal, Jupiler Pro League, Süper Lig,
Danish Superliga, Ekstraklasa and the Croatian HNL.

### 2.3 The exclusions, which are findings in their own right

Six leagues were scraped, examined and dropped. Each was dropped for a specific, diagnosed
reason, and three of those reasons are more interesting than the leagues themselves.

**Argentina (Liga Profesional).** Transfermarkt silently ignores the `saison_id` parameter
for this competition and returns the *current* squad for every historical season. Every
Argentine team-season in the cache carried 2024 personnel. Nothing about the returned pages
looks broken; there is no error, no missing field, no obviously wrong number. Had it gone
unnoticed it would have produced a clean, plausible, entirely meaningless set of results
for two decades of Argentine football. It was caught by a routine check that squad
composition changes between consecutive seasons, which is now a check I run on every new
league.

**Brazil (Série A) and MLS.** In both, the minutes-weighted metric *actively hurts*
prediction relative to raw squad value. The diagnosis is the same in each case, arrived at
from opposite directions: Brazilian clubs rotate heavily across multiple simultaneous
competitions, so league minutes are a poor proxy for how a squad is actually deployed, and
MLS roster construction under a salary cap decouples market value from playing role in a
way the metric assumes away.

The framing here is the important part. The minutes-weighted metric encodes an assumption,
namely that league minutes reflect squad deployment. A competition that violates the
assumption is **out of scope**, and the correct response is to say so and exclude it.
Keeping those leagues in would have dragged down a metric with data it was never defined
over; dropping them silently would have quietly deleted evidence. Both leagues are named
here with the diagnosis attached.

**Sweden (Allsvenskan), Japan (J1) and Mexico (Liga MX).** Coverage and format problems.
Allsvenskan's market-value coverage is catastrophic in early seasons (23.6% of minutes
carried a valued player in 2005) and never exceeds about 94% even in modern seasons, so no
single filter makes it usable across the span. J1 has missing match caches for 2014–2015.
Liga MX captures only one of two tournaments per season, so it has no full-season
equivalent to model.

### 2.4 Scraping conduct

The scrapers are deliberately slow. Transfermarkt calls sleep 2 to 5 seconds each;
SofaScore calls sleep 2 to 3.5 seconds with jitter, rest 90 seconds every 250 requests,
back off ten minutes on any 403 or 429, and abort after three consecutive failures with
progress saved, so a run is always resumable from wherever it stopped. Only HTTP 404 is
recorded as permanently missing; every other failure is retried on the next populate run. A
full big-5 SofaScore scrape takes days.

One incident is worth recording. During early development a burst of about 70 rapid
requests earned a roughly 24-hour IP block from SofaScore. Steady, paced scraping has never
been blocked, across ten league-seasons of pilot work and fifty of the full run. The pacing
constants have a comment in the source explaining why they must not be removed, and the
reason they have a comment is that incident.

---

## 3. Method

The whole model is a five-link chain, and it helps to hold the chain in mind before the
detail: **value → expectation → residual → coach → grade.**

### 3.1 Step 1: Minutes-weighted squad value

For each player in a team-season, multiply his Transfermarkt market value by his share of
his team's league minutes, then sum across the squad.

The intuition is a single sentence: *a €60m striker who played 400 minutes was not a €60m
contribution to that season.* Raw squad value measures what a club owns. Minutes-weighted
value measures what it put on the pitch.

Two normalisations follow. Values are divided by the mean for that league-season, so 1.0
means "an average squad in this competition this year", since being worth €200m meant
something different in the 2008 Eredivisie than in the 2024 Premier League. And the
predictor enters the model logged, because value's effect on points is multiplicative
rather than additive: the difference between the cheapest and second-cheapest squad in a
league is worth far more points than the same euro gap at the top.

One edge case is worth flagging because a reader will look for a hole there. A small number
of team-seasons have no usable minutes data, giving a weighted value of zero. Those are
imputed from a within-season regression of weighted value on raw value. It is a small
population and the imputation is transparent, but it exists.

### 3.2 Step 2: Expected points

```
points_per_game ~ log(norm_weighted_value) + league + is_b_team
```

Three things about this specification are deliberate.

**The response is points per game.** The 14 leagues play between 22 and 46 matches. Total
points are not comparable across them, so every reader-facing effect size in this document
has to be converted explicitly; I do that once, in §6.6, and use points per 38-game season
thereafter.

**League fixed effects, no season fixed effects.** Leagues differ in how tightly value
tracks points. Seasons, pooled across 14 competitions, do not differ enough to justify the
parameters, though the omission does produce small systematic imbalances in individual
league-seasons, and it is carried as a limitation (§10).

**The model is kept deliberately austere.** There is no form variable, no injury proxy, no
xG term, no manager-tenure control. The baseline exists to be beaten cleanly, and every
additional covariate is another place for information from the future to leak backwards
into the prediction. That restraint looks like a missed opportunity until §7.5, where a
single leaked variable produces a p-value of 10⁻²¹ for an effect that does not exist.

### 3.3 Step 3: The residual

**Residual = actual PPG − expected PPG.** Everything downstream is a way of slicing this
one quantity.

Three properties of the residual distribution were checked, because each of them supports a
claim made later:

- It is approximately normal with mean 0 and **SD ≈ 0.242 PPG**. A residual of +0.20 PPG is
  about +7.6 points over a 38-game season.
- It shows **no heteroskedasticity across squad-value tiers.** The model is equally reliable
  for a newly promoted club and for a European champion, which is what licenses comparing
  residuals across the whole population instead of within value bands.
- **Lag-1 persistence is r = 0.203**, CI [0.174, 0.232]. This is the number that pre-empts
  the most obvious objection. A modest club effect exists, since some clubs consistently
  over-run their valuation for reasons that outlive any manager, but at r ≈ 0.2 the residual
  is a long way from being a stable club-quality proxy in disguise. Roughly 96% of
  year-to-year variation in a club's residual is something other than the club's own
  persistent level.

### 3.4 Step 4: Attribution to coaches

Each match is assigned to whichever coach's Transfermarkt tenure bracket covers its date.
**99.4% of matches are attributed.** Matches falling in a coverage gap are dropped from
*both* the actual and the expected side, so a gap shrinks a stint symmetrically instead of
crediting a coach with expectation he was not present for.

The unit of analysis is the **stint**, meaning one coach, one club, one season, because
mid-season changes are common enough that seasons are the wrong grain: about 30% of
team-seasons in some years involve more than one manager.

A coverage filter runs before attribution: a team-season is excluded unless **≥80% of its
minutes** were played by players carrying a market value. This exists because sparse early
data in small leagues produces spectacular artefacts. The worst case in the raw data is
Kalmar FF's 2005 Allsvenskan season, where 26 of 27 players had no recorded value, yielding
an apparent residual of +2.02 PPG. A team beating expectation by two points a game because
the expectation was built from one player.

**One invariant runs through this whole layer: `coach_id` is the identity, and `coach_name`
is only a label.** §9.3 describes what happened when I briefly forgot it.

### 3.5 Step 5: The mixed model

```
partial_residual_ppg ~ (1 | coach_id) + (1 | club_id),  weights = n_games
```

fitted by maximum likelihood, restricted to coaches with at least 3 stints and 10 total
games. The coach and club effects are estimated simultaneously, so the model asks how much
of the leftover follows the manager once the club he worked at has been given its own chance
to explain it.

**Why games weighting, and what it costs.** Section 1.2 gave the variance function
(`0.014 + 1.50/n`); inverse-variance weights under it are very nearly proportional to games.
I tested a saturating `n/(n+k)` alternative with the fitted `k = 110`; it rank-correlated
0.998 with plain games weights and was less numerically stable, so plain games weights won.
More importantly, I tested the weighting choice **out-of-sample**: splitting the data by
even and odd seasons, games-weighted estimates predicted held-out stint residuals at
r = 0.13 against 0.09 for unweighted ones.

The honest cost of that choice: **stint length is itself an outcome.** Coaches get sacked
for bad results, so short stints are disproportionately truncated bad spells. Mean stint
residual runs from −0.41 PPG at 1 to 5 games up to +0.10 at 46 or more, and that gradient is
mostly *within* coaches rather than across them. Games weighting therefore slightly
discounts each coach's own disasters. The out-of-sample test says the noise reduction
outweighs the selection tilt, and the choice is retained with that trade recorded. It is not
cosmetic: the leaderboard rank-correlates 0.79 with its unweighted counterpart. Long-tenure
coaches judged on full seasons rise, and coaches whose best numbers came in short bursts
fall.

**Shrinkage, in one sentence:** a coach with two good months is pulled toward the average,
and a coach with ten good seasons is not. The estimated coach effect is a BLUP (best linear
unbiased predictor) in points per game.

### 3.6 Step 6: Grades, and a bar that is presentational

The BLUPs are placed on a bell curve for display: mean 75, one standard deviation = 10
points, ordinary letter cutoffs on top (A ≥ 93, B ≥ 83, C ≥ 73, down to F). A C is an
average professional manager.

A coach must clear a **display certification bar** to receive a grade: ≥ 109 career games in
that cut, or individual FDR significance. Sub-bar coaches keep their estimated effect, stay
in the mixed model, and appear on the site with their stints and residuals; they get no
grade, no leaderboard slot, and no place in the recommender pool.

The bar needs some explanation, mostly because of what it *is not*. It is not a correction
to the model. The motivating case is Andrea Mandorlini: 5 stints, 108 career games, and on the
current fit a BLUP of +0.078 that would place him **seventh in the top-5 cut**, on the
strength of three short stints that the games weighting correctly discounted. His record is
consistent with a very good coach and equally consistent with luck, and the data cannot tell
those apart.

The obvious response is to penalise thin records in the score itself. I tested three ways of
doing that (a floor on stint weights, a penalty proportional to a coach's share of truncated
stints, and a penalty on the gap between his weighted and unweighted career means) and
**every one of them degraded out-of-sample prediction of held-out stints.** The gap penalty
carried the opposite sign to the one intended: high-gap coaches slightly *beat* their
estimates (p ≈ 0.02–0.03). The data said the ranking math was already right, so the ranking
math was left alone and the problem was solved where it actually lives, in presentation.

### 3.7 The two cuts

Everything is computed twice: once on the **top-5 leagues** and once on **all 14**. They are
separate populations with separate grading curves, so the same coach can be a B+ in one and
an A− in the other, and both are correct. A coach who dominated the Eredivisie has an
all-leagues grade and frequently no top-5 grade at all. **No grade appears anywhere without
its cut label**, on the site or in this document.

---

## 4. Result 1: The metric works

The first question is the original hypothesis, and it is a straight model comparison:
does weighting by minutes beat not weighting by minutes?

| Metric | Baseline (raw value) | Enhanced (minutes-weighted) |
|---|---|---|
| In-sample R² | 0.629 | **0.674** |
| In-sample RMSE (PPG) | 0.2577 | **0.2413** |
| Leave-one-season-out RMSE | 0.2576 | **0.2412** |
| Leave-one-league-out RMSE | 0.2689 | **0.2541** |

*(All figures recomputed on the current 2005–2025 dataset, 5,332 rows after dropping seven
team-seasons with non-positive normalised value.)*

**Two orthogonal cross-validation schemes were run, because they test different things.**

**Leave-one-season-out** (21 folds) asks whether the improvement generalises across time,
and whether it is an artefact of a particular era of football or of a particular vintage of
Transfermarkt's valuation methodology. Improvement **+0.0164 PPG**, paired t-test
**p = 7.6 × 10⁻⁷**, 95% CI [0.0116, 0.0212]. **19 of 21 seasons improved**; the two that did
not are 2013 and 2018.

**Leave-one-league-out** (14 folds) is the harder test, and it asks whether the improvement
generalises across *competitions*, or whether the metric is picking up something about
football versus something about the Premier League. It is harder for a mechanical reason as
well: the held-out league has never been seen at training time, so its fixed effect cannot
be estimated and the specification drops to value-only. Improvement **+0.0148 PPG**, paired
t-test **p = 1.7 × 10⁻⁴**, 95% CI [0.0087, 0.0210]. **12 of 14 leagues improved.**

**Two further checks.** A *combined* model carrying raw and weighted value together was
fitted and cross-validated; across the season folds it comes in **0.0005 PPG worse** than
weighted value alone. The weighting step is therefore a better version of the same
information rather than extra information bolted onto it, which is a cleaner result than a
combined model would have been. The improvement is also not driven by any one competition:
the per-league CV breakdown shows the enhanced model ahead everywhere except two folds.

**Those two exceptions deserve to be in the text rather than buried.** The leagues where
minutes weighting loses are **Serie A** and the **Croatian HNL**, and Serie A is also the
one league where the enhanced model underperforms the baseline in-sample (RMSE 0.224 vs
0.246). This is the same disease that got Brazil and MLS excluded, in its mildest form:
Italian squad rotation across a congested calendar weakens the link between league minutes
and squad deployment. Serie A is retained because the contamination is modest and it is a
core European competition, but the pattern is consistent across all four cases, which is
mild corroboration that the exclusion logic in §2.3 was diagnosing something real.

**The size of the effect, stated honestly.** 0.016 PPG is about **0.6 points per 38-game
season** of error reduction. That is small. The argument for it is not magnitude; the
argument is that a small effect pointed the same direction in 19 of 21 seasons and 12 of 14
leagues, under two cross-validation schemes that fail for different reasons.

---

## 5. Result 2: The residual contains a coach, not just a club

The hypothesis's load-bearing claim is that the leftover from §4 is partly a property of the
manager. The test is the variance decomposition of §3.5, run separately on both cuts.

| Cut | Stints fitted | Coaches | Coach var | Club var | Residual | LRT |
|---|---|---|---|---|---|---|
| All 14 leagues | 6,772 | 1,006 | **4.1%** | 3.8% | 92.1% | χ² = 35.78, df = 1, **p = 2.2 × 10⁻⁹** |
| Top-5 leagues | 2,347 | 354 | **5.4%** | 4.8% | 89.8% | χ² = 19.79, df = 1, **p = 8.7 × 10⁻⁶** |

*(The stint spine holds 8,642 stints across 2,445 coaches; the mixed model fits on the
subset belonging to coaches with ≥3 stints and ≥10 games. The residual variance is per-game
under the weights, and the percentage shares put it on the stint scale at the mean stint
length.)*

Five things follow, in order of importance.

**1. The coach term is significant, decisively, in both cuts.** The null being rejected is
"coach identity explains nothing about performance above squad-value expectation once club
identity and squad value have had their say." A likelihood-ratio test against a
club-random-effect-only model rejects it at p = 2 × 10⁻⁹ on the broad cut.

**2. Coach variance exceeds club variance in both cuts.** This is the portability claim, and
it is the sentence the whole project rests on: the leftover follows the manager more than it
stays at the club. It is also a result that *moved*, which is worth saying. On the ≤2024
vintage the two components were tied in the all-leagues cut (3.7% coach vs 3.8% club); the
2025/26 refit put the coach ahead (4.1% vs 3.8%). A number that shifts when the data grows
is more credible than one that never does, and I would rather show the movement than quote
only the flattering vintage.

**3. Residual variance is 90–92%, and that number belongs in the headline.** Coaching is a
small share of what happens in football. A writeup that buries this figure to make the rest
sound bigger has already lost the argument. Stating it plainly and then showing that the
small share predicts a season the model has never seen is a much stronger claim, because it
is a claim about a *real* effect instead of a large one.

**4. The top-5 cut shows a bigger coach share, and the reason is interpretable.** Elite
coaches move between clubs and between leagues, so their portable effect has room to show
itself. In the broader dataset, locally-anchored managers at permanently dominant clubs
(Dinamo Zagreb, Legia Warsaw, Club Brugge) push signal into the club term, because a coach
who never leaves is statistically hard to tell apart from the institution he never left.

**5. Individual significance is rare, and the reason is sample size.** After
Benjamini–Hochberg FDR correction across the whole coach population, exactly **four coaches
clear individual significance in each cut**: Guardiola, Ferguson, Conte and Xavi. Everyone
else shows directional evidence without the data to certify it individually. This is a power
limit rather than a model failure, and it is why the project ships **shrunken estimates
behind a certification bar** instead of a confident 1-to-2,445 ordering of human beings.

### Face validity: illustration, not evidence

Labelled as such, and kept to a paragraph. The top of the top-5 cut runs Guardiola (A+,
BLUP +0.141, 17 stints, 3 clubs), Ferguson, Conte, Urs Fischer, Allegri, Tuchel, Klopp. The
all-leagues cut promotes coaches whose careers happened outside the big five: Carlos
Corberán, Sergej Jakirović, Neil Warnock at #10 on 21 stints and 588 games. The notable
negatives are Eusebio Di Francesco (13 stints, 8 clubs, D−) and Marcelo Bielsa (9 stints, 4
clubs, D− in the top-5 cut), both of which are strong *negative* portability results, since
the underperformance travels too. The most portable career in the dataset is Claudio Ranieri,
with 17 stints across **11 clubs** and an A− in the top-5 cut, which is about as many
independent environments as a manager can supply.

None of that is evidence. Guardiola ranking first is reassuring and proves nothing, since
any model that failed to rank him highly would be discarded on sight, which makes the check
unfalsifiable. The evidence is §6.

---

## 6. Result 3: Three independent validations

This section is where the project stops being a correlation study.

### 6.1 Why three

A single validation can only rule out the failure modes its own design is sensitive to.
Three were run, deliberately chosen so that each is vulnerable to something the other two
are not:

- The **out-of-sample forecast** pools appointments across hundreds of clubs, so it is
  strong on sample size and weak on the fact that it still compares coaches working with
  different squads.
- The **event study** holds a single club fixed across a single managerial swap, so squad
  quality is swept out entirely, and it is weak because clubs choose whom to hire.
- The **forward test** uses a genuinely future season that no part of the model had seen, so
  leakage is impossible by construction, and it is weak because it is one season.

The three should be read as a triangulation rather than as three attempts at the same thing.

### 6.2 Validation 1: Forecasting new coach–club pairings

**Why this test.** The most direct commercial question is whether knowing a coach's track
record improves the forecast of an appointment that has not happened yet. This is harder
than asking whether coach identity improves prediction generally, because it restricts
attention to **brand-new pairings**, meaning a coach at a club where he did not work the
previous season, which is exactly the situation a hiring club is in.

**Design.** Leave-one-season-out over 10 folds (2016/17 – 2025/26), forecasting stint PPG
for **877 new coach–club pairings**, games-weighted RMSE, with model layers added one at a
time. In each fold, coach effects are estimated exclusively from the training seasons; a
coach appearing for the first time enters at the shrinkage prior of 0, which is the honest
forecast for someone with no record. Two framings were reported: a **pre-hire** framing
using only information available before the appointment (raw squad value), and a
**realized** framing conditioning on the season's actual minutes-weighted value.

Critically, the acceptance rule was **pre-registered**: a layer ships in the headline score
only if it does not hurt out-of-sample RMSE. That was written down before the test was run,
which is what makes the null results in §7 interpretable instead of post-hoc.

**Result.** The coach quality layer improves forecast RMSE from **0.3026 to 0.2993**,
**p = 0.0027** in the realized framing and **p = 0.017** in the pre-hire framing, with 7 of
10 folds improving. The layers added after it (global archetype effects, coach-specific fit
slopes, formation deployment) are a wash and ship as clearly-labelled exploratory columns.

**A small point of statistical hygiene that matters.** The published p-value is
**one-sided**, and I say so. The pre-registration declared a *directional* acceptance rule,
meaning a layer ships only if it improves prediction, so the one-sided test is the test that
was specified. The two-sided value would be 0.0054. Reporting that number instead would look
more conservative while actually answering a different question than the one that was
pre-registered.

### 6.3 Validation 2: The manager-change event study

**Why this test.** Every comparison in §6.2 still puts coaches next to each other while they
work with different squads. A within-club design removes that objection entirely: hold the
club fixed, look at what changes when only the manager changes.

**Design.** All **3,043 manager changes across 436 clubs, 2005–2025**, both mid-season and
between adjacent seasons. A first-difference structure sweeps out the club's squad-value
level. The leakage rule is the design's most important feature: each coach's grade is taken
**as of the outgoing coach's season**, which uniformly excludes both the before-period and
the after-period result from *both* coaches' grades. Implementing that required an
expanding-window refit of the entire mixed model, once per cutoff year.

**Result: the level specification.** Regressing the incoming coach's
performance-above-expectation on his prior grade, controlling for the club's recent form:
**slope +1.17, p = 0.0015**. In a games-weighted mixed model with a club random effect,
**+0.91, p = 0.002**. The effect is **strongest for mid-season crisis hires (p = 0.0023)**
and weakest for considered summer moves, so the grade matters most exactly where clubs are
choosing under the most pressure and the least deliberation.

**The difference specification is a confounded null, and why it is confounded is the more
useful half of the result.** The intuitive question is whether the *gap* between
the incoming and outgoing coach's grades predicts the change in performance. It does not,
and the reason is a specific interaction between selection and regression to the mean.
Clubs fire a well-graded coach precisely when he is in an unlucky dip. That dip reverts
regardless of who arrives. So a large positive grade gap is systematically associated with a
starting point that was artificially low, forcing a spurious negative association. Regression
to the mean dominates any managerial change: the outgoing performance level carries a
coefficient of **−0.95**. Once a manager is gone, his quality is simply irrelevant to what
happens next.

The practical lesson is sharp and it falls straight out of the two specifications:
**hiring is about the absolute quality of the man you bring in, not about how he
compares to the man you are replacing.**

**Sacking efficiency, from the same machinery.** Clubs sack on results; the model sees
results minus squad-value expectation. That difference lets the same data grade the sackings
themselves. Of **1,748 mid-season sackings, 16.5% fired a coach who was actually
overperforming his squad**, meaning bad results attached to a worse squad than the club
believed it had. And firing that overperformer **backfires**: the replacement's
performance-versus-expectation averages **−0.16 PPG**, and improves on the sacked man only
**35%** of the time. Replacing a genuine underperformer is followed by the expected bounce
(**+0.35 PPG**, improving **79%** of the time). The harshest-sacking list reads like the
game's own catalogue of regret, surfaced from the residual with no knowledge of any
narrative: Birmingham City firing an overperforming John Eustace (+0.47) for Wayne Rooney
(−0.50) en route to relegation; Birmingham, again, firing Gary Rowett for Gianfranco Zola.

### 6.4 Validation 3: The 2025/26 forward test

**Why this test.** Cross-validation holds out seasons from inside a window the analyst has
already seen and already made a hundred decisions about. A genuinely future season is
immune to that, and it is the only design where leakage is impossible by construction
instead of merely controlled.

**Design.** The model was **frozen at 2024**, both the M3 value coefficients and the coach
effects, estimated only on completed seasons through 2024/25, and then used to predict a
freshly-scraped **2025/26** season across all 14 leagues (252 team-seasons). Two questions
were asked.

**Q1: does the model structure generalise out of time?** On the holdout year the enhanced
model posts **R² = 0.721, correlation 0.852, and a mean error of 6.3 points per
team-season**, and it **still beats raw squad value by 0.0133 PPG**, statistically the same
margin the original cross-validation found, on a year no part of the fitting process had
touched. (This uses realized minutes, so it is an out-of-time test of the model's
*structure*. The genuinely pre-season forecasting question is §7.4.)

**Q2: do the grades predict the future?** Regressing each 2025/26 stint's realized
overperformance on the coach's frozen prior grade gives a slope of **+1.90, p = 0.0024**
across all 435 stints, and **p = 0.0036** on the 219 stints belonging to coaches who already
had a grade. Adding the grade to the forecast lowers holdout RMSE from 0.223 to 0.220. This
is the cleanest single confirmation of the coaching signal in the project.

**The vintage problem, and the engineering that protects it.** After the test was run,
2025/26 was folded into the fit like any other season, so the grades on the site today are a
*later* vintage than the ones the test scored. The obvious way to destroy this test is to
refit the pipeline and let the test re-read the live coach effects, at which point it would
be scoring grades against the very season they were estimated on, **and it would still print
a small p-value.** A silent success is the worst failure mode there is.

The fix is a byte snapshot: `coach_blups_14league_asof2024.rds`, taken before the refit. The
forward test reads the snapshot and **errors out rather than falling back** to the live
file, and the refit driver refuses to run at all if the snapshot is missing. After the full
2025/26 refit the test reprints 5,080 training rows, R² 0.721, slope +1.896, p = 0.0024,
graded-only p = 0.0036, identical to the published figures. The site's validation page
carries a vintage line saying that the displayed grade is a later version of the tested one,
because without it the page would imply something false.

### 6.5 The confound, tested rather than waved away

The objection to all three validations is the same, and it is the right objection: *good
coaches are hired by big clubs, so you may just be measuring club size.* And the raw
correlation is there. A coach's grade correlates about +0.2 to +0.3 with the average
squad-value percentile of the clubs he has worked at (+0.39 within the style-analysis
subset).

The test is to split club size into its **between-coach** and **within-coach** components
and look at the signs.

- **Between coaches:** slope **+0.00087 (t = 4.2)**. Coaches who spend their careers at
  bigger clubs grade higher. This is the confound, and it is exactly as large as expected.
- **Within a coach:** slope **−0.00085 (t = −5.0)**. A coach fixed-effects cross-check gives
  the same answer at **p = 1 × 10⁻⁷**.

The logic turns on the sign. If the grades were an artefact of the value model
under-predicting big clubs, then **the same coach would have to overperform more once he
moved to a bigger club**. That requires a *positive* within-coach slope. The observed slope
is negative. The sign is wrong for mis-specification, so the between-coach correlation is
composition: good coaches end up at big clubs, and the effect measured is genuinely theirs.

**Robustness.** I refit the whole chain with a curvature-corrected (natural spline) value
term to see whether the linear-in-log form was hiding the problem. The ranking is
essentially unchanged (**rank correlation 0.98**, Guardiola still first) and the confound
shrinks only from 0.21 to 0.16. There *is* one real residual: linear-in-log slightly
under-predicts the single biggest club in each league (top decile +0.08 PPG), and the spline
correction is validated out-of-sample (leave-one-season-out RMSE 2.55% lower, p = 0.0017).
The consequence is that coaches *permanently* at elite clubs carry roughly 0.02–0.04 PPG of
inflation without any reordering. I declined to adopt the spline, since it re-plumbs six
downstream layers and the site for an average BLUP movement of about 0.005 PPG, and
documented the bias instead.

### 6.6 The three tests together, and what the number is worth

| Test | Design type | n | Result | p |
|---|---|---|---|---|
| Recommender payoff | Out-of-sample forecast, new pairings | 877 pairings / 10 folds | RMSE 0.3026 → 0.2993 | **0.0027** |
| Manager-change event study | Within-club natural experiment | 3,043 changes / 436 clubs | slope +1.17 | **0.0015** |
| 2025/26 forward test | True future holdout | 435 stints (219 graded) | slope +1.90 | **0.0024** |

**In football units:** approximately **1.4 points per 38-game season per standard deviation
of grade** on the forward test, and approximately **0.7** on the event study. The event-study
figure is lower because a single partial-season outcome is a very noisy measurement of
anyone. I give the range, not just the flattering endpoint. One standard deviation of grade
is 10 grade points, the distance from a C to a B.

**One design lesson from visualising Q2, because it generalises.** The scatter of prior
grade against realized 2025/26 overperformance has a raw correlation of **r = 0.166**. It
looks like a null. Plotting it required three things simultaneously: dot area scaled by
games played (a 6-game caretaker residual spans about ±1.9 PPG against ±1.0 for stints of 10
or more, so equal dots invite reading the noisiest points hardest), a games-weighted fit
line, and **tertile means** (−0.052 / +0.061 / +0.074, in ascending grade order). Without the
group means, a validated result reads as noise. Without a caption saying the cloud is wide
and single dots mean little, the trend line oversells it. Quartiles were tried and rejected:
their Q3/Q4 difference (0.117 vs 0.060) sits inside its own standard errors and reads as a
real dip that does not exist. And the group standard errors (~0.03 against a ±1.9 axis)
render as 2-pixel stubs, so they are stated in words and never drawn.

---

## 7. What the model is not: five nulls

I think this is the most valuable part of the project. Five separate attempts, on four
different data slices, to find either a *decomposition* of the coaching number or a *second,
independent* coach effect. All five failed. That consistency is itself the finding: the coach
signal this data can measure is one number, and the project's refusal to ship the others is
the reason the one it does ship can be trusted.

Each null taught something different, so each gets its own methodological lesson.

### 7.1 Null 1: Coach × player-type fit

**Why the test.** The natural next question after "how good is he?" is "good with what?"
Sporting directors do not hire in the abstract; they hire for a squad. If coaches differ in
which player types they get the most out of, that is directly actionable.

**Design.** Every big-5 player-season since 2015/16 with ≥600 league minutes (17,219 of
them) was described by 38 **style-only** features: heatmap shape descriptors, per-90
passing, carrying and defending profiles, shot-location profiles. No goals, no assists, no
ratings, no xG, because the features must describe *how* a player plays and not *how well*.
Features were z-scored within league × season × position group, then clustered by k-means
into **11 archetypes**:

| Group | Archetypes (with exemplars) |
|---|---|
| Defenders | no-nonsense CB (Tarkowski, Pezzella) · ball-playing CB (Van Dijk, Rüdiger, Marquinhos) · defensive fullback (Azpilicueta, Coleman) · attacking fullback (Theo Hernández, Alexander-Arnold, Cancelo) |
| Midfielders | destroyer (Casemiro, Ndidi) · deep playmaker (Kroos, Modrić, Jorginho) · wing-back (Gosens, Hateboer, Trimmel) · advanced creator (De Bruyne, Müller, Fekir) |
| Forwards | pressing forward (Richarlison, Jota) · box striker (Kane, Lewandowski, Immobile) · wide creator (Messi, Salah, Mbappé) |

Each coach stint's minutes-weighted archetype mix was joined to its residual. Archetypes are
**lagged** to the player's most recent prior season, across leagues, so a Serie A to Premier
League transfer arrives carrying his Serie A archetype. That is an endogeneity guard, since a
player's current-season style is partly the coach's doing. Players with no prior big-5 season
fall back to the current season and are flagged.

**Result: the global effect is real, and it strengthened with more data.** Squad archetype
composition predicts overperformance: **χ² = 26.13, df = 11, p = 0.0062**, and a
**strict-lagged sensitivity** that drops the fallback entirely gives **p = 0.0003**, so the
result is robust to the fallback choice and *stronger* without it. **Wide-creator share is
the dominant coefficient** (0.76, t = 3.48): shifting 10 percentage points of outfield
minutes from destroyers to wide creators is associated with roughly **+2.8 points per season**
above squad-value expectation. Every archetype's coefficient is non-negative against the
destroyer reference, so destroyer-heavy squads underperform their valuation most. Two
readings survive: squads built around wide creators genuinely outperform, and/or the transfer
market underprices wide creators.

**Result: the individual effect is not.** **1,704 within-coach correlations** between stint
residuals and archetype shares were computed; **none survive FDR correction.** A follow-up
model with shrunken per-coach random slopes on three pre-specified composition axes gives
**LRT χ² = 2.65, df = 3, p = 0.449**, and the wing-back slope variance shrank to exactly zero.

**The right reading, plainly: squad composition matters, and the data cannot show that
*this particular coach* is the one who benefits from it.** Descriptive pairs that recur
across both specifications and have face validity, such as Gasperini overperforming with more
man-marking centre-backs (r = 0.89 over 10 stints, which is his back-three system in a
nutshell), Vieira with destroyers (r = 0.92), and Pochettino underperforming with more
pressing forwards (r = −0.89), are presented as colour, explicitly labelled exploratory, and
never as a finding.

**Methodological lesson:** a global effect and a per-unit effect are different claims, and
4 to 10 stints per coach cannot power the second one no matter how significant the first is.

### 7.2 Null 2: Style → quality

**Why the test.** This is the literal question everyone asks: *what makes good coaches
good?* If the nine-axis style fingerprint (§8.2) explains the grade, the project has an
answer.

**Design.** The quality BLUP regressed on the nine style axes plus a rigidity measure,
across the **231 coaches** with both a top-5 grade and a fingerprint, games-weighted, with
test families pre-specified from the prior variance-decomposition result instead of chosen
after seeing the correlations.

**Every raw association is large and FDR-significant.** Defensive solidity **+0.64**, shot
volume +0.53, possession **+0.52**, chance quality +0.46, lineup stability −0.37, rigidity
+0.25, all standardized. Taken at face value that is a complete "what makes coaches good"
story, and **it would have been the most shareable content the project ever produced.**

**All of it is artefact.** Four checks were applied, each asking a different question, and
each killing a different group:

| Check | Question it asks | Casualties |
|---|---|---|
| Consistency across four specs | Same sign and significant in raw, squad-residualized, club-controlled, and graded-only fits? | pressing, directness, width, set-piece reliance |
| Separable from club size? | Can the axis be distinguished from club size at all? | possession (**r = 0.86** with mean club-value percentile), shot volume (0.81), solidity (0.74) |
| Does the axis restate the outcome? | Is it built from the thing the grade measures? | chance quality, solidity, shot volume |
| Within- vs between-coach | Does the *same* coach do better when he does more of it? | **lineup stability, where the sign reverses** |

**Nothing survives.** Three traps came out of it, each worth stating so nobody re-walks them.

**The suppression trap.** The all-axes multivariable model reports club level at
**β = −0.60**, which reads as "big clubs systematically underperform their value." The
bivariate association is **+0.39**, the opposite sign. The tell that generalises beyond this
dataset: possession's own coefficient *rises* when the club control is added
(0.517 → 0.568). Genuine confound removal shrinks a coefficient toward zero. A coefficient
that grows under a control is a signal that the control and the predictor are jointly
soaking up variance in a way neither can be read individually. One axis plus one control is
the only interpretable specification here.

**A Simpson's paradox in the axis most likely to be believed.** Lineup stability was the one
tactical axis the variance decomposition had marked as genuinely coach-owned, so it was the
finding a reader would trust. Between coaches, rotators grade higher (−0.373, q < 0.0001, in
all four specifications). Within a coach, *stability* associates with better seasons
(**+0.131**, p < 0.0001); within a club, +0.110. The between-coach version is club sorting,
and naming the heaviest rotators explains it instantly: Heynckes, Tuchel, Allegri, Luis
Enrique, all managing clubs with European fixture loads.

**Outcome restatement.** Defensive solidity is constructed from shots conceded, which is a
step on the causal path to conceding goals and dropping points. "Solid teams overperform" is
a restatement of the outcome variable wearing a tactical costume.

**Only rigidity is unkilled, and the reason it survived is the section's moral.** Rigidity
is a career constant, so it has **no within-coach variation**, so the decisive check
*cannot be run on it*. It is recorded as "between-coach only; untestable," and is not
allowed to pass by default. A predictor that survives because it cannot be tested has not
survived.

### 7.3 Null 3: The Coach Development Effect

**Why the test.** Everything above measures coaches against *points*. A large part of the
industry cares about a euro-denominated outcome instead: does a coach make players more
valuable? A €5m academy graduate sold for €40m is value the league table never records. This
was the first genuinely **new outcome** the project attempted, a different axis entirely,
with no re-slicing of the points residual, so it was the best available chance either to
corroborate the quality signal independently or to expose that the two measure the same
thing.

**Design.** The response is log market-value growth, `g = log(value_{t+1} / value_t)`, for a
player at the same club in consecutive seasons (34,653 player-seasons in the big five,
80,033 across 14 leagues). A baseline expectation model regresses `g` on **confounders
only**: a natural-spline age curve interacted with position group, a splined starting value
to capture mean reversion, the player's own prior-season momentum, and league and season
fixed effects. It deliberately leaves every *mediator* (minutes, results, the player's own
output) in the residual, because conditioning on something the coach causes would subtract
the effect being measured. The residual is attributed to coaches through the same M5 spine
and fed to a mixed model with **player, club and coach** random effects. The player random
effect is the metric's integrity: without it, a coach handed naturally-rising talent is
simply credited with their trajectory.

**The baseline works.** It captures the age story exactly (teens gain ~+0.22 log-value/year,
over-30s lose ~0.29), the residual is flat across age bins and starting-value deciles, and
its extremes are the right players. The largest over-expectation seasons are canonical
breakouts (Chiesa €0.1m → €10m at 17, Mainoo €0.8m → €50m, Aouar, Ekitiké) and the largest
under-expectation ones are aging collapses. **As a player-development residual it is
trustworthy.**

**As a coach metric it is a null**, on three pre-registered gates:

| Gate | Result | Verdict |
|---|---|---|
| Orthogonal to points (is it points in euros?) | cor with points BLUP 0.20–0.27; **93–96% of variance orthogonal** | passes, a genuinely different axis |
| **Repeatability** (do even seasons predict odd seasons?) | split-half **r = −0.07** (top-5) / **+0.05** (14-league), n = 792 | **fails, indistinguishable from zero in both cuts** |
| Face validity | top of the list is journeymen, not the developer-reputation tenures | weak |

**The trap worth naming:** the in-sample coach variance component looks impressive, 18–22%
of variance with LRT p < 10⁻⁶⁰, and it is meaningless. It does not repeat within a coach's
own career, so it is not a trait. It measures *which players happened to blow up on his
watch*. The decomposition confirms the mechanism: the **player random effect dominates at
44–62%**. The result is stable to adding transfer movers (Spearman 0.89–0.94 with the
same-club-only ranking), so the null itself is robust and not a selection artefact.

**Slicing does not rescue it.** Restricting the repeatability test to young players (age
≤ 21, where development actually happens), to each position group, and to each of the 11
archetypes leaves the coach effect null everywhere; young players are if anything slightly
negative (r = −0.09 to −0.16, mean reversion).

**Two by-products are worth keeping.** First, the clean **player**-development residual,
which ships as a scouting leaderboard describing players and never coaches. Second, an
independent corroboration of §7.1 from a completely different direction: sorting the residual
by archetype shows attacking and creative roles over-appreciating beyond their age/price
baseline (wide creator +0.07, deep playmaker and box striker ≈ +0.04) and defensive fullbacks
least (−0.02). Two unrelated analyses agreeing that wide creators are underpriced is worth
more than either alone.

**The one real signal is a club property, in selling leagues only.** A club's
player-value-growth level under one manager predicts its level under the **next, different**
manager at **r ≈ +0.10 (p = 2 × 10⁻⁴)**, and that entire signal lives **outside the big
five**. Big-5 clubs show none (consecutive-regime r = +0.005); Eredivisie, Liga Portugal and
Championship-type development pipelines carry all of it. Selling clubs are built to
appreciate and move on players regardless of who is in the dugout.

**A method trap that produced a spurious result on the first pass, and is easy to repeat.**
The naive version of that club test gives **+0.40**, which looks like a major finding. It is
an artefact of mid-season managerial changes: about 30% of seasons are split, so a
player-season is **shared between two managers** and appears on both sides of a
"consecutive regimes" comparison. Collapsing each player-season to its primary coach removes
the artefact and leaves the real, much smaller selling-league effect.

### 7.4 Null 4: The betting market

**Why the test.** Every validation above is *internal*: the model is scored against a
baseline I also built. The fair sceptical reply is *"show me you beat, or add to, the
market."* A bookmaker's closing line aggregates every serious model plus real money on the
outcome, and it is the one benchmark that already prices **both** the squad and the manager.
It is the hardest and most credible baseline available.

This was pre-registered as **confirmatory**: metrics fixed before the run, and a null ("the
market already knows what we know") declared in advance to be a legitimate, on-brand result.

**Design.** A leakage-free walk-forward match forecaster: a **pre-season squad-value
snapshot** (never the minutes-weighted value, which embeds realized minutes) and a **coach
effect refit on completed seasons strictly before the match**, which is an expanding-window
re-run of the full mixed model once per cutoff year, feeding a Dixon–Coles bivariate-Poisson
goal model whose own coefficients are fitted only on prior seasons. Evaluated against
de-margined closing probabilities on 51,977 matches across 13 leagues, 2012/13–2025/26,
99.9% carrying Pinnacle closing odds.

The evaluation is a McFadden conditional logit of the realized result on the market's
implied probability plus the model's signal. **A significant coefficient on our signal after
conditioning on the market is the honest, high-power test of whether we carry information the
line underweights, and it does not require beating the book**, which makes it a much fairer
test than a head-to-head accuracy comparison.

**The crosswalk is where this analysis could have quietly died.** football-data uses stable
abbreviations ("Ath Madrid", "Sp Lisbon") that no
name-similarity score maps reliably. The mapping is instead a **within-season greedy
one-to-one assignment**, exploiting the fact that the ~20 clubs in a season form a bijection,
so even a mediocre scorer resolves under the constraint. It was verified not by name score
but by **reconciliation**: fd-derived season points checked against Transfermarkt's own match
records, **99.7% exact outside Belgium** (100% in seven leagues), with every miss a
fixture-count difference (Belgian playoff rounds fd carries and TM does not) and never a
misidentification.

**Result: a clean null, on every framing.** The forecaster is strictly worse than the
closing line (pooled log-loss **1.015 vs 0.979**, market better in **all 11** evaluated
leagues) and adds nothing beyond it: squad value **p = 0.29**, **coach BLUP p = 0.96**, and
**p = 0.68** even in the pre-declared subgroup where mispricing was most plausible, namely
new and low-profile managers. A pre-registered flat-stake P&L backtest returns **−6.6% ROI**
at closing prices (bootstrap 95% CI [−8.2%, −5.1%], excluding zero) and **−7.8%** once a
realistic 5% haircut acknowledges that a bettor rarely gets the closing line. Every odds
bucket loses.

**Note the direction of travel.** Folding 2025/26 in moved every p-value *further* from
significance. A weakening result on added data is what a real null looks like; a
strengthening one would have been the signal to go back and re-examine.

**One structural note, stated because it limits the design and not the verdict.** The coach
term would not fit stably *inside* the goal model, being collinear with squad value,
sign-flipping and fold-unstable. So the forecaster is value-plus-home and the coach is tested
as a separate incremental signal. That is a conservative choice; the null holds under every
framing tried.

**The honest reading.** A near-efficient market pricing our signal is **external
corroboration that the signal is real**, and simultaneously the ceiling on exploiting it.
Sections 4–6 stand; §7.4 says the edge has already been discovered by people with money on
it.

### 7.5 The leakage story

This gets its own heading because a technical reader will get more out of it than out of
anything else here.

The first version of the market forecaster used each season's **own** Transfermarkt squad
value in place of the prior season's. Its incremental coefficient beyond the closing line
was **+0.224, p = 1 × 10⁻²¹**. Against the sharpest benchmark in existence. It would have
been the project's headline result, and it is exactly the kind of number that makes a person
stop checking.

Swapping in strictly pre-season value, meaning the prior season's snapshot and a one-line
change, collapsed it to **+0.023, p = 0.31**.

The mechanism is mundane and completely invisible from inside the code. Transfermarkt
updates its valuations *within* a season. A team overperforming in October carries an
inflated valuation by January, so "the season's squad value" already contains the season's
results. The apparent edge was hindsight, laundered through a vendor's update schedule.

The general lesson: **against a near-efficient benchmark, a few percent of leaked variance is
the difference between a spurious 10⁻²¹ and the truth.** The current-value variant is
retained in the codebase as a live leakage demonstration, and its favourable P&L numbers are
labelled in the source as artefacts so that nobody, including me later, can mistake them
for a result.

### 7.6 Null 5: The recommender's fit and deployment layers

Brief, because the lesson is a variation on §7.1. Both layers pass their **mechanical**
gates emphatically: a player's fit to an incoming coach's usual formations predicts his
minutes share beyond market value at **t = 26.9**, with a positive within-stint rank
correlation in **100%** of the 316 historical arrivals tested. The eligibility matrix tracks
real deployment decisions.

Neither layer improves hiring forecasts (§6.2), so both ship as clearly-labelled exploratory
columns and stay out of the headline score.

One interpretation is worth offering, since it is a genuine limitation of the *evidence*
rather than of the machinery: **clubs already hire for fit.** The validation universe is
realized appointments, so survivorship pushes the measurable fit signal toward zero, because
the catastrophic mismatches were never hired and are therefore not in the data. Testing this
properly needs a dataset of hiring *shortlists*, which is the highest-value thing on the
future-work list (§11.3).

---

## 8. What *can* be described honestly

Three descriptive layers exist at deliberately different trust levels, and each is labelled
with its own. The gradient between them is what this section is about.

### 8.1 Layer A: where the edge comes from (defensible; ships on coach pages)

**Why.** Every coach page answered *how good* with one number and never said *good at what*.

**Design.** The expectation model is refit on the **same right-hand side** with
goals-for-per-game and goals-against-per-game as the response, and the two head residuals
attributed to coach stints through the **identical** M5 path: same coverage filter, same
match-to-coach assignment, same games weighting, same shrinkage, same ≥3-stint FDR rule,
reused verbatim with no re-implementation. Goals come from the match cache, so this covers
the full 2005–2025 span and all 14 leagues.

**Why it is defensible:** it re-slices a residual the project already trusts and makes no new
attribution leap. That is why it is the one descriptive layer stated plainly on coach pages.

**Checks.** The goal-difference edge ties back to the points residual at **r = 0.862**
(top-5) / **0.872** (14-league), about 0.59 points per goal of edge; at coach level the goal
edge correlates **r = 0.823** with the published grade.

**One finding worth stating on its own.** The coach effect is **substantially stronger on
goals than on points**: the 14-league LRT for coach variance gives **χ² = 160** for offence
and **60** for defence, against **28** for the points model. Goals-for is a lower-noise coach
signal than points. That is the most valuable known lead in the project for future work.

**The instructive exception.** Diego Simeone holds a B grade in the top-5 cut on a goal edge
of ≈ 0 (−0.03). His overperformance sits in converting goal difference into points, which
the split describes and does not explain. His coach page says so in plain words, because a
lede that flatly contradicts the grade card above it is worse than no lede.

### 8.2 Layer B: the style fingerprint (descriptive-clean; ships, carefully labelled)

**Design.** The archetype recipe pointed at *team* style: per-player-per-match → team-match →
z-scored within league × season → coach-stint mean → games-weighted coach profile, over
36,018 team-matches across all 50 big-5 league-seasons. Nine axes (possession, pressing
intensity, directness, width, shot volume, chance quality, defensive solidity, set-piece
reliance, lineup stability) each an **equal-weight mean of its members' z-scores**.
Deliberately not a PCA and not a fitted weighting: nothing here is trained against an
outcome, so there is nothing to overfit and every axis stays readable.

**Two caricatures the data corrected**, both of which are better colour than anything the
project invented:

- **"Guardiola presses high" resolves to *height*, and not to intensity.** He sits at ≈ 0 on
  per-match pressing intensity and +1.5 SD on pressing height. City make few defensive actions
  because opponents rarely have the ball, and win it high when they do. The two measures
  correlate only r = 0.38 and are different traits.
- **"Simeone: low possession, low block" is not supported.** He is 74th percentile on
  possession and dead average on pressing height. What *is* supported: solidity (94th),
  narrowness (13th on width), shot selection (84th on chance quality).

**The main result was designed as a caveat and became the finding: team style is mostly the
club's.**

| Axis | Coach var % | Club var % | Travels (coach → new club) | Persists (club → new coach) | R² from squad archetype mix |
|---|---|---|---|---|---|
| possession | 11.6 | **69.2** | 0.55 | 0.82 | **0.69** |
| pressing intensity | **30.9** | 23.6 | 0.34 | 0.47 | 0.12 |
| directness | 24.8 | **52.1** | 0.52 | 0.71 | 0.51 |
| width | 29.8 | 34.6 | 0.44 | 0.50 | 0.39 |
| shot volume | 11.3 | **54.4** | 0.43 | 0.67 | 0.54 |
| chance quality | 13.8 | 27.6 | 0.29 | 0.36 | 0.11 |
| defensive solidity | 11.0 | **45.0** | 0.29 | 0.58 | 0.31 |
| set-piece reliance | 12.9 | 24.7 | 0.25 | 0.29 | 0.22 |
| lineup stability | **19.2** | 14.6 | **0.33** | 0.17 | 0.10 |

Club variance beats coach variance on **7 of 9 axes**. The squad's archetype mix *alone*
explains 69% of possession, 54% of shot volume and 51% of directness. A club under two
different coaches (possession r = 0.82) looks more alike than a coach at two different clubs
(r = 0.55), and residualising on the squad's archetype mix collapses the travel correlations
(possession 0.55 → 0.17).

**The consequence is binding on how this may be presented.** Every radar on the site is
labelled as *the style of the teams this coach ran*, and the phrase "his style" appears
nowhere. **Two axes survive as genuinely the coach's** and are marked on the chart:
**lineup stability** (the only axis where coach beats club, the only one that travels better
than it persists, only 10% personnel-explained, and it survives residualization, since
rotation is a decision rather than a squad property) and **pressing intensity** (the highest
coach share at 30.9%, 12% personnel-explained, the only tactical axis still standing after
residualization).

**A method caveat that cuts against my own headline.** The travel-versus-persist comparison
is not like-for-like. Consecutive coaches at one club inherit
nearly the same squad, so `r_club > r_coach` is expected under *any* model in which the squad
matters at all. The variance decomposition estimates both effects simultaneously and is the
better instrument; it agrees on 7 of 9, which is why the conclusion stands. Neither check is
causal, since coaches are hired by clubs that already suit them, which inflates travel, and
the archetype mix is partly one the coach shaped, which strips out some of his own signature.
These are bounds rather than an identified split.

**A display note that took two attempts to get right.** Axis units are standard deviations of
*team-matches*, so coach means compress heavily toward zero: Simeone's 92nd-percentile
defensive solidity is only +0.28 SD. Rendering raw SDs makes every fingerprint look flat and
identical. The site maps to percentile among coaches instead, and uses a single hue rather
than the site's positive/negative colour pair, because these axes have no good/bad polarity
and a diverging ramp would invent a verdict the data does not contain.

### 8.3 The xG cut: measured, and deliberately not shipped

**Why.** Splitting the goals cut again separates *process* from *outcome*: **creation** (xG
created above expectation) and **prevention** (xG conceded below it) against **finishing**
(goals minus xG) and **shot-stopping** (xG conceded minus goals conceded). The design
asserted in advance that process would repeat and outcome would not.

**The strongest single integrity check in the project lives here.** The xG cut is built
entirely from SofaScore; the goals cut is built entirely from Transfermarkt. Over 605 stints,
`creation + finishing` against the goals cut's offensive residual gives **r = 0.960**, and
`prevention + shot-stopping` against the defensive residual gives **r = 0.981**. Two
independently sourced pipelines, joined through a team crosswalk and a coach-attribution
spine, agreeing to that tolerance. This is the check that breaks first if the SofaScore→TM
team map or the attribution ever regresses, which is why it is run on every refresh.

**Repeatability** (lag-1, same club, consecutive seasons, 247 pairs):

| Measure | lag-1 r | Reading |
|---|---|---|
| creation | **0.353** | most repeatable, genuinely process |
| prevention | 0.275 | repeatable |
| finishing | 0.246 | **more persistent than the design assumed** |
| shot-stopping | **0.033** (p = 0.61) | pure noise, exactly as predicted |

The process-versus-outcome ordering survives. Creation's margin over finishing is narrower
than the three-season sample suggested (creation fell from 0.42 as the fourth season was
added), which is a useful reminder that early estimates on thin data run hot. Finishing
persisting at 0.25 instead of ≈ 0 is most plausibly squad continuity, since clubs keep their
finishers, which is a reason to keep labelling finishing an unreliable *coach* signal
instead of promoting it.

**Why it is not on the site.** 605 stints, 310 coaches, 89 with ≥3 stints, 7 with ≥5, and
**zero FDR-significant on all four measures**. Adding a fourth season did not manufacture
significance. It is a recent-form lens over four big-5 seasons, and a coach page is exactly
the surface that would flatten it into a career verdict.

**Two data defects, recorded because they show the checking habit.** First, **28 of 7,082
xG-era events carry a full complement of about 21 shots and are missing their goal shots
entirely** (0.4%, almost all in 2023). Including them understates creation and inflates
finishing. The fix is that an event counts only if its shotmap reconciles with the scoreline
on *both* sides, and note that a reconciliation check conditioning on events *having* goal
shots would never catch this. Second, own goals sit in the shotmap credited to the
*benefiting* side, named for the defender, with no xG attached; they land wholly in finishing
by construction, which is where they belong.

---

## 9. What was built

### 9.1 Products

**The site.** Per-coach, per-team and per-league pages, a leaderboard with both cuts, and a
search index. The honesty gradient of §8 is enforced structurally: each page is *allowed* to
show only what its layer's label permits. Grades never render without their cut. The xG cut
and Layer C have no surface at all.

**The coach recommender.** "Who is the best coach for this squad?", decomposed into
**quality** (validated), **fit** (exploratory) and **deployment** (exploratory), with career
plausibility filters (has coached in this league, this country, big-5 proven, similar club
level, recently active, domestic) that are never mixed into the score.

**The squad-fit gap drawer.** Which of a squad's value a coach's usual formations tend to
leave on the bench, and which positions those formations can only fill with a player out of
role, expressed **in euros and slots and never in points**. Two design lessons are embedded
here. First, the computed gap *scalar* is deliberately **not displayed**, because QA showed it
mis-orders the value-maximising anchor and does not reconcile with the strand list shown
beside it; a number that contradicts the list under it is worse than no number. Second, the
"stranded value" calculation only counts players who make the best XI in **at least one** of
the 22 formations. Without that filter, a player benched in every conceivable shape
contributed his full value identically to every coach, which put the same flat entry on all
81 of Manchester City's candidate coaches and made 88.9% of a team's coaches share a top
label. With it, top-label agreement fell to 77.8%. The residual sameness is real and is
reported as a partial fix.

**The team builder.** Build any XI on a drawn pitch from every big-5 player-season since
2015/16, and get the similarity-based coach suggestions computed client-side. The JavaScript
implementation was verified **numerically identical** to the R one against a fixture. It
deliberately shows no predicted points for a fantasy XI: a 2016 Leicester midfield behind a
2024 Bayern attack sits outside anything the model has evidence about, and producing a number
for it would be fiction.

**The deserved table.** The residual restated as league standings, with expected points beside
actual finish, so over- and under-achievement reads as a position swing. It is the most
visceral version of the whole project: **Leicester 2015/16 finished first and deserved
tenth; Chelsea that season deserved first and finished tenth.**

**The player-development leaderboard.** The one durable by-product of §7.3, ranking players by
market-value growth above their own age, price, position and momentum baseline. It describes
*players*, never coaches, and says so on the page.

### 9.2 Architecture

Three layers, with one invariant that makes the whole thing reproducible.

**Data layer**, two tiers across two independent sources. `xx_raw_*` functions scrape and are
always slow; `xx_data_*` functions check an in-memory cache, then an RDS cache on disk, and
call the scraper only if neither has the answer. The SofaScore layer mirrors the same split
under an `ss_` prefix.

**Analysis layer**, a chain of pure cache-readers: coach attribution → residual analysis →
model comparison, then the descriptive layers, the recommender, the validations. **The
invariant: analysis code cannot make a network call.** Any result in this document can be
regenerated offline from the caches, which is what makes "reproducible" a fact and not an
aspiration.

**Publishing layer**, which writes only to `site/`, wipes and rebuilds the generated paths on
every export, and never touches hand-written files.

### 9.3 Four bugs that would have been invisible

Each of these taught something different, and none of them would have announced itself.

**One coach, two spellings.** Transfermarkt re-spelled Ivan Juric as "Ivan Jurić" on his
2025/26 page. The profile URL was unchanged. One function grouped coaches by
`(coach_id, coach_name)` and split that career into two ranked rows; the mixed model, which
groups by `coach_id` alone, kept one. Two tables silently disagreed about who existed. It
surfaced as a crash on a length-2 vector where the code expected a scalar, and **the crash was
the lucky part**, because the quiet version of this failure is a coach appearing twice with
half a career each and nothing going wrong. The fix resolves each id to its most recent
spelling at the root of the chain, so every downstream layer inherits it. The same trap exists
in one-to-many form: a `distinct(coach_id, coach_name)` join duplicates stint rows instead of
crashing. Expect it to recur; any season can re-spell any name.

**The archetype relabelling hazard.** K-means cluster indices are arbitrary, so re-clustering
after adding a season can permute them and silently mislabel every downstream layer (coach
fit, style, recommender, builder, site copy) with nothing failing anywhere. Rather than
assume it was fine, I recovered the previous cluster assignment from git, joined on
`(player_ss_id, season_start_year)` and cross-tabulated old against new within each position
group. Diagonal agreement was 97–100% on all 11 archetypes and the mapping was the identity.
The check is now documented as mandatory after any re-cluster, with the instruction to remap
the label vector instead of re-running until the indices happen to line up.

**The half-rendered page.** A deleted-but-still-referenced variable threw a `ReferenceError`
inside an unhandled async render function, so a coach page drew its header, subtitle and stat
tiles and then silently appended nothing: no career chart, no strengths, no style, no
formations. Nothing caught it. The throw is inside an unhandled promise rejection, so no
console error appeared. `node --check` passed, because a ReferenceError is a runtime error.
And the smoke test asserted only that the page produced more than 200 characters of text,
which 777 characters of half-rendered page clears comfortably. The replacement checker
installs `error` **and `unhandledrejection`** handlers *before* page scripts evaluate, and
asserts a **per-page minimum card count**. Those counts are a contract: when a page gains a
card, the number is raised.

**The `team_ss_id` trap.** SofaScore's per-match player rows carry the player's club *at scrape
time*, which matches the actual match side only **41.5%** of the time, so a player transferred
in January is labelled with his new club on matches he played for his old one. Every team-side
derivation in the project goes through the event's home/away ids instead. This is the kind of
field that is right often enough to pass a spot check and wrong often enough to poison an
aggregate.

### 9.4 Vintage discipline and the pipeline as code

The M3 → M4 → M5 refit procedure existed for months only as prose in a session log. It is now
`refit_pipeline.R`. The validation that made replacing the manual process safe: pinned to
≤2024 it reproduced the hand-run results **bit-identically**, with a maximum absolute numeric
delta of **0** across residuals, coach residuals, rankings, BLUPs and grades on the 14-league
cut, and ≤ 10⁻¹¹ on the top-5 cut, which is lme4 optimizer noise. Everything that moved after
the real refit is therefore attributable to the new season alone.

The snapshot discipline behind the forward test is described in §6.4. Alongside it,
`gh_verify_endpoint()` requires the final vintage of the grade-history layer to reproduce the
live published grades exactly, and it does, at **max |Δgrade| = 0.00 × 10⁰**. That check exists
to fail loudly if a downstream layer was not re-run after a refit, which is the most likely
way for two surfaces of the site to start disagreeing about the same coach.

### 9.5 One season knob, and a roll-forward procedure

`xx_last_data_season` is a single constant from which every layer's season default derives.
Rolling the project forward a year is a documented sequence: scrape the season from both
sources, snapshot the current coach effects as the frozen vintage, bump the constant, run the
refit driver, re-run the downstream layers, then re-run the forward test against the new
holdout. The forward test is designed to be re-run every year as a rolling scorecard, which is
the property that makes a single-season holdout accumulate into evidence over time.

### 9.6 Working with an AI agent

This was an explicit goal of the project, so one honest paragraph. The mechanism that actually
worked was a large, continuously maintained `CLAUDE.md` recording **binding verdicts and
traps**, with almost nothing about code structure, so that a null stays a null, a rejected
approach stays rejected, and a data quirk does not have to be rediscovered in three months.
The generalisable lesson is about what an agent's context should contain: **decisions and the
reasons for them**, because the code is already readable and the reasoning behind it is not.
Every "do not re-open this" note in that file exists because re-opening it once cost a session.

---

## 10. Limitations

Seven, selected because a sceptic would actually raise them, each labelled bounded, tested or
open.

**1. Coaching is roughly 5% of the variance.** *(Bounded.)* The effect is real and small.
Everything downstream inherits that ceiling, including every effect size in §6.6.

**2. Individual coaches are mostly not individually significant.** *(Bounded.)* Four coaches
per cut clear FDR. What ships is a set of shrunken estimates behind a certification bar, and
that framing is load-bearing rather than merely modest. A confident 1-to-2,445 ordering would
be unsupportable.

**3. Value endogeneity, and the Year 2 dip.** *(Open.)* Transfermarkt values partly reflect
past performance, so strong year-1 coaching may raise the year-2 baseline and compress
residuals for long-tenured coaches. A related pattern is consistent across cuts but
statistically inconclusive: a coach's second season at a club shows a lower residual than his
first, reversing from year 3. Two explanations fit equally well, a new-manager bounce
inflating year 1 or value inflation raising the year-2 expectation, and this data cannot
distinguish them.

**4. Early-season sparsity in smaller leagues.** *(Bounded by a filter.)* The Kalmar FF 2005
case in §3.4 is the extreme: 26 of 27 players unvalued, producing an apparent +2.02 PPG
residual. The ≥80% minutes-coverage filter removes the worst of it and the site prints a
caveat on affected league-seasons, but pre-2010 small-league figures deserve caution.

**5. Selection into hiring.** *(Tested, not eliminated.)* All three validations observe real
appointments and none randomises. The within-coach club-size test in §6.5 bounds the worst
version of this and rules out the specific mis-specification story, and it does not make the
data experimental.

**6. Scope.** *(Bounded.)* Fourteen European leagues. The six exclusions are principled, and
being principled is exactly what limits generalisation beyond Europe, since the metric is
defined over competitions where league minutes reflect squad deployment. SofaScore-dependent
layers are big-5 and 2015/16 onward only, so a coach seen exclusively in the Championship gets
a grade and an attack/defence split and no fingerprint, and no radar is fabricated for him.

**7. Single-source dependence.** *(Open.)* Squad values are one vendor's estimates, and the
entire project rests on them. The xG cross-source tie-back in §8.3 (r = 0.96 / 0.98) is the
only genuine second-source check anywhere in the pipeline, and it validates the attribution
spine, not the valuations themselves.

---

## 11. Conclusion

### 11.1 The thesis, with the evidence attached

Coaching quality is real (coach variance significant at p = 2 × 10⁻⁹ in the 14-league cut and
p = 9 × 10⁻⁶ in the top-5 cut), portable (coach variance exceeds club variance in both cuts),
worth roughly **1.4 points per 38-game season per standard deviation of grade** on a future
holdout and 0.7 on a within-club natural experiment, useful for forecasting a hire against a
squad-value baseline (p = 0.0027 over 877 new pairings), corroborated by a within-club design
that sweeps out squad quality entirely (p = 0.0015 over 3,043 manager changes), and confirmed
on a season the model had never seen (p = 0.0024). It is also **a single number**: four
independent attempts to decompose it or to find a second coach effect all came back empty, and
the betting market has already priced it.

### 11.2 Against the pre-declared criterion

The criterion in §1.3 required either a coaching variable that significantly reduces model
error, or a sufficient disproof plus a replacement hypothesis. **It was met on the first
branch**, on three independent designs instead of one.

The **numeric target was missed, and missing it should be stated plainly.**
The hoped-for reduction was 25% of variance. The honest figure is a few percent: 4.1% coach
variance in the 14-league cut, 5.4% in the top-5 cut, against residual variance of 90–92%. A
project that reports the miss against its own written target is worth more than one that
reports only the tests it passed, and the reason the small number is defensible is that it
survived §6.

### 11.3 Next, ranked by expected value

1. **Goals as the response, in place of points.** Layer A found the coach effect is far
   stronger on goals (χ² = 160 offence vs 28 for points). This is the highest-value known lead
   in the project and it requires no new data.
2. **A matchday-frozen value snapshot**, which would let the market benchmark be re-run
   without the season-level valuation compromise that §7.5 exposed.
3. **Contract length and realized transfer fees**, the two open gaps named in the
   value-growth design, both of which need new scrapes.
4. **More seasons for the xG cut**, the only null that failed on statistical power instead
   of on substance.
5. **A hiring-decision dataset, meaning shortlists and not just outcomes.** This is the only
   way to break the survivorship problem in §7.6, and it is the difference between measuring
   which coaches are good and measuring which hires were good.

---

## Appendix A: Complete test register

Every statistical test the project ran, why it was run, and what it returned. Grouped by
what each was testing.

### The core model

| # | Test | Why | Result |
|---|---|---|---|
| A1 | In-sample fit, raw vs minutes-weighted value | Baseline comparison of the original hypothesis | R² 0.629 → 0.674; RMSE 0.2577 → 0.2413 |
| A2 | Leave-one-season-out CV, 21 folds, paired t | Does the improvement generalise across time? | +0.0164 PPG, **p = 7.6 × 10⁻⁷**, CI [0.0116, 0.0212], 19/21 folds |
| A3 | Leave-one-league-out CV, 14 folds, paired t | Does it generalise across competitions? (harder, no league FE available) | +0.0148 PPG, **p = 1.7 × 10⁻⁴**, CI [0.0087, 0.0210], 12/14 folds |
| A4 | Combined (raw + weighted) model vs weighted alone | Is weighting extra information or better information? | Combined 0.0005 PPG **worse**; dropped |
| A5 | Per-league in-sample breakdown | Where does the metric's assumption fail? | Serie A baseline beats enhanced (0.224 vs 0.246); Serie A + HNL are the two CV losses |
| A6 | Residual normality and heteroskedasticity across value tiers | Is the residual comparable across the value range? | Approximately normal, SD 0.242 PPG, no heteroskedasticity |
| A7 | Lag-1 residual persistence | Is the residual just a stable club-quality proxy? | r = 0.203, CI [0.174, 0.232], a modest club effect only |
| A8 | Match-to-coach attribution coverage | Is the stint spine complete enough to trust? | 99.4% of matches attributed |

### The coach effect

| # | Test | Why | Result |
|---|---|---|---|
| B1 | Mixed-model LRT, coach variance = 0, 14-league | The central hypothesis test | χ² = 35.78, df = 1, **p = 2.2 × 10⁻⁹** |
| B2 | Mixed-model LRT, top-5 | Same test on the cleanest cut | χ² = 19.79, df = 1, **p = 8.7 × 10⁻⁶** |
| B3 | Coach vs club variance shares | The portability claim | 4.1% vs 3.8% (14lg); 5.4% vs 4.8% (top-5) |
| B4 | Per-coach one-sample t-tests + BH FDR | Can any individual coach be certified? | 4 per cut: Guardiola, Ferguson, Conte, Xavi |
| B5 | Stint variance function estimation | How noisy is a short stint? | Var ≈ 0.014 + 1.50/n |
| B6 | Even/odd split-half: games-weighted vs unweighted estimates predicting held-out stints | Which weighting is right, decided out-of-sample? | Games-weighted r = 0.13 vs unweighted 0.09 |
| B7 | Saturating n/(n+k) weight alternative | Is plain games weighting the right functional form? | k = 110, rank r = 0.998 with games weights, less stable; rejected |
| B8 | Three score-side thin-record corrections (weight floor, truncation-share penalty, weighted–unweighted gap penalty) | Should thin records be penalised in the score? | **All degraded OOS prediction**; gap penalty had the opposite sign (p ≈ 0.02–0.03). All rejected; handled in presentation instead |
| B9 | Games-weighted vs unweighted leaderboard rank correlation | How material is the weighting choice? | r = 0.79 |

### The three validations

| # | Test | Why | Result |
|---|---|---|---|
| C1 | Pre-registered LOSO payoff, 10 folds, 877 new coach–club pairings, layers added one at a time | Does the grade improve the forecast of a *new appointment*? | Quality layer RMSE 0.3026 → 0.2993, **p = 0.0027** (realized), **p = 0.017** (pre-hire), 7/10 folds |
| C2 | Same, subsequent layers (archetype effects, fit slopes, deployment) | Pre-registered acceptance rule: ship only if it does not hurt | All a wash; ship as exploratory |
| C3 | Event study, level spec, 3,043 changes / 436 clubs | Within-club design removing squad-quality confounding | slope +1.17, **p = 0.0015** |
| C4 | Event study, club-random-effect games-weighted mixed model | Robustness of C3 to clustering | +0.91, **p = 0.002** |
| C5 | Event study by hire type | Where does the grade matter most? | Mid-season crisis hires p = 0.0023; summer moves weak |
| C6 | Event study, difference spec (grade *gap*) | The intuitive question | **Confounded null**; outgoing performance coefficient −0.95 (regression to the mean dominates) |
| C7 | Sacking efficiency | Can the residual grade the sacking decision itself? | 1,748 mid-season sackings, 16.5% harsh; harsh replacements −0.16 PPG and improve 35% of the time vs +0.35 and 79% for defensible ones |
| C8 | Forward test Q1, frozen-at-2024 model on 2025/26 | Does the model structure generalise out of time? | R² 0.721, r 0.852, mean error 6.3 pts, still beats raw value by 0.0133 PPG |
| C9 | Forward test Q2, prior grade vs realized overperformance | Do the grades predict a future season? | slope +1.90, **p = 0.0024** (435 stints); **p = 0.0036** (219 graded); RMSE 0.223 → 0.220 |
| C10 | Post-refit reproduction of the forward test from the frozen snapshot | Does the vintage rail actually hold? | Identical to published on every figure |

### The club-size confound

| # | Test | Why | Result |
|---|---|---|---|
| D1 | Between-coach club-size slope | Measure the confound | +0.00087 (t = 4.2) |
| D2 | Within-coach club-size slope | **The sign test**: mis-specification requires positive | **−0.00085 (t = −5.0)**, wrong sign for mis-specification |
| D3 | Coach fixed-effects cross-check | Robustness of D2 | −0.00086, **p = 1 × 10⁻⁷** |
| D4 | Spline value term refit, full chain | Is linear-in-log hiding the problem? | Rank r = 0.98, Guardiola still #1; confound 0.21 → 0.16 |
| D5 | Spline correction OOS validation | Is the curvature real? | LOSO RMSE 2.55% lower, p = 0.0017; residual bias ~0.02–0.04 PPG on permanent-elite coaches, no reordering |

### The nulls

| # | Test | Why | Result |
|---|---|---|---|
| E1 | Global archetype composition mixed model | Does squad player-type mix predict overperformance? | **χ² = 26.13, df = 11, p = 0.0062**, a real global effect |
| E2 | Strict-lagged sensitivity (no current-season fallback) | Is E1 an artefact of the fallback? | **p = 0.0003**, stronger without it |
| E3 | 1,704 within-coach archetype correlations + BH FDR | Is fit a property of individual coaches? | **None survive** |
| E4 | Per-coach random slopes on 3 composition axes, LRT | Same question, shrunken-model form | **χ² = 2.65, df = 3, p = 0.449** |
| E5 | K-means split-half stability (ARI) | Are the archetypes reproducible? | 0.62–0.92 across groups |
| E6 | Cluster-index permutation cross-tab after re-clustering | Did adding a season silently relabel everything? | 97–100% diagonal, identity mapping on all 11 |
| E7 | Deployment mechanical gate: formation fit predicting minutes share | Does the deployment machinery track reality? | t = 26.9; positive in 100% of 316 arrivals |
| E8 | Layer C: 9 style axes + rigidity vs grade, raw | What makes coaches good? | Every association large and FDR-significant (solidity +0.64, possession +0.52) |
| E9 | Layer C check 1: consistency across 4 specs | Does it hold under reasonable alternatives? | Kills pressing, directness, width, set-pieces |
| E10 | Layer C check 2: separability from club size | Can the axis be distinguished from club size? | Kills possession (r = 0.86), shot volume (0.81), solidity (0.74) |
| E11 | Layer C check 3: outcome restatement | Is the axis built from the outcome? | Kills chance quality, solidity, shot volume |
| E12 | Layer C check 4: within- vs between-coach | Does the *same* coach do better when he does more of it? | **Lineup stability reverses sign**: −0.373 between, **+0.131 within** |
| E13 | Layer C multivariable diagnostic | Why does the all-axes model disagree? | **Suppression**: club β = −0.60 vs bivariate +0.39; tell is possession rising 0.517 → 0.568 under control |
| E14 | Weighted ridge stability check | Is the null an artefact of one estimator? | Agrees; no axis survives |
| E15 | CDE gate 1: orthogonality to points | Is value growth just points in euros? | 93–96% orthogonal, a genuinely different axis |
| E16 | CDE gate 2: even/odd split-half repeatability | Is the coach effect a trait? | **r = −0.07 / +0.05**, indistinguishable from zero |
| E17 | CDE in-sample variance decomposition | What is the metric actually measuring? | Coach 18–22% (LRT p < 10⁻⁶⁰) but **player RE 44–62%**, it is which players blew up |
| E18 | CDE robustness to including transfer movers | Is the null a sample-selection artefact? | Spearman 0.89–0.94, null is stable |
| E19 | CDE slicing by age band, position, archetype | Does a subgroup rescue it? | Null everywhere; young players slightly negative |
| E20 | Club cross-regime value growth, primary-coach collapsed | Is development a club property? | r ≈ +0.10, p = 2 × 10⁻⁴, entirely outside the big five |
| E21 | Same test, naive (uncollapsed) | Method trap | Spurious **+0.40** from shared mid-season player-seasons |
| E22 | Points-grade vs selling-league career correlation | Does the points grade penalise developmental coaches? | r = −0.03; no penalty |
| E23 | Market: log-loss / Brier vs closing line | Does the forecaster beat the market? | 1.015 vs 0.979; market better in **all 11** leagues |
| E24 | Market: conditional logit, model signal beyond market | Does it *add* to the market? | value **p = 0.29** |
| E25 | Market: coach BLUP beyond market | The question that mattered most | **p = 0.96** |
| E26 | Market: pre-declared low-profile-manager subgroup | Where mispricing was most plausible | **p = 0.68** |
| E27 | Market: pre-registered P&L backtest + bootstrap CI | Economic significance | **−6.6% ROI**, CI [−8.2%, −5.1%]; −7.8% at achievable prices |
| E28 | **Market: leakage demonstration** (current-season value) | What a leaked variable looks like against a sharp benchmark | **+0.224, p = 10⁻²¹** → **+0.023, p = 0.31** under prior-season value |
| E29 | Odds crosswalk reconciliation (points vs TM match records) | Is the team mapping right? | 99.7% exact outside Belgium, 100% in seven leagues; every miss a fixture-count difference |
| E30 | DC joint MLE vs stacked-Poisson GLM | Is the fast fit the same fit? | Numerically identical |

### The descriptive layers

| # | Test | Why | Result |
|---|---|---|---|
| F1 | Goals-cut tie-back to points residual | Does the attack/defence split reconstruct the thing it splits? | r = 0.862 (top-5) / 0.872 (14lg); coach level r = 0.823 |
| F2 | LRT for coach variance on goals-for and goals-against | Is the coach effect stronger on goals? | **χ² = 160 offence, 60 defence, vs 28 for points** |
| F3 | **Cross-source tie-back**: SofaScore xG cut vs TM goals cut | The project's strongest integrity check | **r = 0.960 / 0.981** over 605 stints |
| F4 | xG lag-1 repeatability, 247 same-club pairs | Design pre-asserted process repeats, outcome does not | creation 0.353, prevention 0.275, finishing 0.246, shot-stopping **0.033 (p = 0.61)** |
| F5 | xG per-coach FDR across four measures | Can any coach be certified on process? | **Zero significant**; 89 coaches with ≥3 stints |
| F6 | Shotmap–scoreline reconciliation | Are the shot data complete? | 28 of 7,082 events missing goal shots (0.4%); excluded |
| F7 | Style axes variance decomposition (coach vs club) | Whose style is it? | **Club wins 7 of 9 axes**; possession 69% club vs 12% coach |
| F8 | Travel (coach → new club) vs persist (club → new coach) | Second instrument on the same question | possession travel 0.55 vs persist 0.82 |
| F9 | R² of each axis from squad archetype mix | How much is personnel? | possession 0.69, shot volume 0.54, directness 0.51 |
| F10 | Travel correlations after residualising on archetype mix | Does anything survive the squad? | possession 0.55 → 0.17; only stability and pressing intensity survive |
| F11 | Pressing intensity vs pressing height correlation | Are they the same trait? | r = 0.38, different traits |

### Engineering acceptance tests

| # | Test | Why | Result |
|---|---|---|---|
| G1 | `refit_pipeline.R` pinned to ≤2024 vs hand-run results | Can a manual recipe be retired safely? | **Max abs delta 0** (14lg); ≤10⁻¹¹ (top-5) |
| G2 | Grade-history endpoint identity | Does a historical vintage reproduce the live published grade? | **max \|Δgrade\| = 0.00 × 10⁰** |
| G3 | As-of BLUP cache reproduction, 18 vintages | Is the leakage-free vintage machinery deterministic? | All 18 at 0.00 × 10⁰ |
| G4 | Mixed-model LRT guard on thin vintages | Does a degenerate fit fail loudly? | Guards on LRT p and BLUP SD; a 44-coach pool silently produced all-`NaN` grades rendering as "F" before the guard existed |
| G5 | Builder client-side vs R fixture | Is the JS reimplementation the same model? | Numerically identical |
| G6 | Site render check: `error` + `unhandledrejection` handlers, per-page minimum card counts | Catch silent half-rendered pages | Contract in place after the ReferenceError incident |
| G7 | Squad-composition-changes check on new leagues | Catch Argentina-style silent corruption | Now standard on every new league |

---

## Appendix B: Figure inventory

| # | Figure | Design notes that matter |
|---|---|---|
| 1 | The chain: value → expectation → residual → coach → grade | Anchors §3; referenced throughout |
| 2 | Predicted vs actual PPG, both models | Shared axis domain (a squashed axis fakes a tighter fit); PPG, never total points, since the leagues play 22–46 games |
| 3 | Prior grade vs realized 2025/26 overperformance | Dot area = games played; games-weighted fit line; **tertile** means (quartiles read as a fake dip); error bars stated in words, never drawn at ~0.03 against a ±1.9 axis |
| 4 | Coach vs club variance shares, both cuts | Paired bars; carries the portability claim |
| 5 | A style radar with its honesty label | Percentile, never raw SD; one hue, no diverging good/bad ramp; title must say "the teams he coached" |
| 6 | Architecture: two sources → two-tier cache → analysis layers → publishing layer | Carries the "analysis cannot make a network call" invariant |
| 7 | Deserved-table extract, 2015/16 | Leicester 1st / deserved 10th; Chelsea 10th / deserved 1st, the fastest way to make a lay reader understand the residual |

---

*All figures in this document were computed on the 2005/06–2025/26 dataset. The
cross-validation results in §4 and the variance decompositions in §5 were recomputed
directly from the cached pipeline for this writeup. Every grade and count is labelled with
its cut.*
