# Coaching Quality Is Real, It Travels, and It Is One Number

**Measuring manager performance against squad value across 14 leagues and 21 seasons**

Andrew Salisbury · R · [live site] · [repository]

---

> **Abstract.** Squad market value predicts league points well enough that the gap between the two
> is the only place a coaching effect could live. Weighting each player's value by his share of team
> minutes improves that prediction significantly and out-of-sample. I decompose the residual from
> the improved model into coach and club random effects; the coach component is significant in both
> dataset cuts and larger than the club's in each. The resulting grade survives three independent
> validations, including a true future season the model had never seen. Four attempts to find *more*
> than that single number all returned nulls, and all of them are reported here.

A solo R project covering 5,339 team-seasons and 8,642 coaching stints across 14 European leagues,
2005/06 to 2025/26, shipped as a public site and reproducible offline from cached scrapes.

---

## 1. The question

A manager hire is the most consequential personnel decision most clubs make in a year, and it is
made on reputation, a shortlist and vibes. The question here is narrow: **given what a squad was
worth, how did the team actually do, and does the answer follow the manager when he moves?**

Four properties of the problem make the naive approach useless, and every design decision below
answers one of them. Points are mostly the squad, so ranking coaches by points per game ranks clubs
by wage bill with extra steps. Coaches are not randomly assigned, so reputation and results are
contaminated at the source (tested in §4.2). The per-coach sample is tiny, typically 3 to 10 stints.
And short spells are enormously noisy: a stint's per-game residual has sampling variance of roughly
`0.014 + 1.50/n` in games, so a 2-game caretaker carries about 19 times the variance of a 38-game
one.

The hypothesis and its success criterion were fixed before any scraping, including a numeric target
of a 25% reduction in model error. **The target was missed**, and §7 returns to it. Nothing here
claims the effect is causal in any identified sense, that the model can say *what* good coaches do
differently, or that any of it is exploitable. Attribution is not causation.

---

## 2. Data and method

**Transfermarkt** supplies the spine: per-player values and league minutes, coach appointment dates,
match results. **SofaScore**, scraped through headless Chrome because it rejects ordinary HTTP
clients by TLS fingerprint, supplies per-match statistics, formations and shots, so everything built
on it is big-5 and 2015/16-onward. **football-data.co.uk** supplies the closing odds in §5.

Six leagues were scraped, diagnosed and dropped, and two diagnoses matter more than the leagues.
Transfermarkt silently ignores the season parameter for Argentina and returns the *current* squad
for every historical year: no error, no missing field, and two decades of clean, plausible,
meaningless results had a routine squad-composition check not caught it. And in Brazil and MLS the
minutes-weighted metric *actively hurts* prediction, because multi-competition rotation and
salary-cap roster construction both break the assumption that league minutes reflect squad
deployment. A competition that violates the metric's assumption is out of scope, and the correct
response is to say so and exclude it.

**The model is a five-link chain: value → expectation → residual → coach → grade.**

*Value* is each player's market value × his share of team league minutes, summed, normalised to the
league-season mean and entered logged. *A €60m striker who played 400 minutes was not a €60m
contribution.* Raw value measures what a club owns; weighted value measures what it put on the
pitch. *Expectation* is `points_per_game ~ log(norm_weighted_value) + league + is_b_team` — per
game, because the leagues play 22 to 46 matches, and deliberately austere: no form, no injury proxy,
no xG, no tenure control. Every extra covariate is another place for the future to leak backwards,
and §5 shows what one leaked variable is worth.

*The residual* is actual minus expected PPG: approximately normal, SD ≈ 0.242, and lag-1 persistence
of only r = 0.203, a modest club effect rather than a club-quality proxy in disguise. *Attribution*
assigns each match to whichever coach's tenure bracket covers its date (**99.4% are attributed**),
dropping gaps from the actual *and* expected sides so a stint shrinks symmetrically. The unit is the
**stint**, one coach at one club in one season, because about 30% of team-seasons in some years
involve more than one manager.

*The mixed model* is `partial_residual ~ (1 | coach_id) + (1 | club_id)`, games-weighted, coaches
with ≥3 stints. Coach and club are estimated simultaneously, so the model asks how much of the
leftover follows the manager once the club has had its own chance to explain it. *Grades* place the
shrunken estimates on a bell curve (mean 75, SD 10), gated by a **display certification bar** (≥109
career games, or FDR significance) that is presentational rather than a model correction: I tested
three ways of penalising thin records inside the score and **every one degraded out-of-sample
prediction**, one with the opposite sign to the one intended. Everything is computed twice, top-5
and all-14, and **no grade appears anywhere without its cut label**.

---

## 3. Result 1: the metric works

| | Baseline (raw value) | Enhanced (minutes-weighted) |
|---|---|---|
| In-sample R² / RMSE | 0.629 / 0.2577 | **0.674 / 0.2413** |
| Leave-one-season-out | 0.2576 | **0.2412** — +0.0164 PPG, **p = 7.6 × 10⁻⁷**, 19/21 folds |
| Leave-one-league-out | 0.2689 | **0.2541** — +0.0148 PPG, **p = 1.7 × 10⁻⁴**, 12/14 folds |

Two orthogonal cross-validations, because they fail for different reasons. Season folds ask whether
the gain is an artefact of an era of football or a vintage of Transfermarkt's methodology; league
folds are harder, since the held-out league's fixed effect cannot be estimated at all. A combined
model carrying both predictors comes in 0.0005 PPG *worse* than weighted value alone, so the
weighting is a better version of the same information, not extra information bolted on.

**The effect is small: 0.016 PPG is about 0.6 points per 38-game season.** The argument for it is
not magnitude. It is that a small effect pointed the same way in 19 of 21 seasons and 12 of 14
leagues, under two schemes that break differently.

---

## 4. Result 2: the residual contains a coach, not just a club

| Cut | Stints | Coaches | Coach var | Club var | Residual | LRT |
|---|---|---|---|---|---|---|
| All 14 leagues | 6,772 | 1,006 | **4.1%** | 3.8% | 92.1% | χ² = 35.78, **p = 2.2 × 10⁻⁹** |
| Top-5 leagues | 2,347 | 354 | **5.4%** | 4.8% | 89.8% | χ² = 19.79, **p = 8.7 × 10⁻⁶** |

**Coach variance exceeds club variance in both cuts.** That is the portability claim and the
sentence the project rests on: the leftover follows the manager more than it stays at the club. It
is also a number that *moved* — on the ≤2024 vintage the two were tied in the all-leagues cut, and
the 2025/26 refit put the coach ahead. I would rather show the movement than quote only the
flattering vintage.

**Residual variance is 90–92%, and that belongs in the headline.** Coaching is a small share of what
happens in football, and showing that the small share predicts a season the model has never seen is
a stronger claim than burying it, because it is a claim about a *real* effect rather than a large
one. **Individual significance is rare**: after FDR correction, exactly four coaches clear it in each
cut (Guardiola, Ferguson, Conte, Xavi). That is a power limit, not a model failure, and it is why
the project ships shrunken estimates behind a certification bar rather than a confident 1-to-2,445
ordering of human beings. Guardiola ranking first is reassuring and proves nothing, since any model
that failed to rank him highly would be discarded on sight.

### 4.1 Three independent validations

Each is vulnerable to something the other two are not.

| Test | Design | n | Result | p |
|---|---|---|---|---|
| Recommender payoff | Out-of-sample forecast, new coach–club pairings | 877 pairings / 10 folds | RMSE 0.3026 → 0.2993 | **0.0027** |
| Manager-change event study | Within-club natural experiment | 3,043 changes / 436 clubs | slope +1.17 | **0.0015** |
| 2025/26 forward test | True future holdout | 435 stints (219 graded) | slope +1.90 | **0.0024** |

**New pairings** means a coach at a club where he did not work the previous season, which is the
situation a hiring club is actually in; first-timers enter at the shrinkage prior of 0, the honest
forecast for someone with no record. The acceptance rule was **pre-registered** — a layer ships only
if it does not hurt out-of-sample RMSE — which is what makes the nulls in §5 interpretable rather
than post-hoc.

**The event study** holds the club fixed across a single swap, sweeping out squad quality. Its most
important feature is the leakage rule: each grade is taken **as of the outgoing coach's season**,
which excludes both the before- and after-period from *both* grades and required refitting the whole
mixed model once per cutoff year. The effect is strongest for mid-season crisis hires (p = 0.0023),
where clubs choose under the most pressure. The *difference* spec, regressing performance change on
the grade *gap*, is a **confounded null**, and why is the more useful half: clubs fire a well-graded
coach precisely during an unlucky dip, and the dip reverts regardless of who arrives. **Hiring is
about the absolute quality of the man you bring in, not how he compares to the man you are
replacing.** The same machinery grades the sackings: **16.5% of 1,748 mid-season sackings fired a
coach who was actually overperforming his squad**, and doing so backfires, the replacement averaging
−0.16 PPG against +0.35 when a genuine underperformer goes.

**The forward test** froze the model at 2024, both value coefficients and coach effects, and
predicted a freshly scraped 2025/26 (R² = 0.721; prior grades predict realized overperformance at
+1.90). The obvious way to destroy it is to refit and let it re-read the live coach effects, at which
point it would score grades against the very season they were estimated on **and it would still print
a small p-value**. A silent success is the worst failure mode there is, so the test reads a byte
snapshot taken before the refit and **errors out rather than falling back**.

**In football units:** roughly **1.4 points per 38-game season per standard deviation of grade** on
the forward test and 0.7 on the event study, the latter lower because a single partial season is a
very noisy measurement of anyone. One SD is the distance from a C to a B.

### 4.2 The confound, tested rather than waved away

*Good coaches are hired by big clubs, so you may just be measuring club size.* The raw correlation is
real, about +0.2 to +0.3. Split it and read the signs: **between coaches, +0.00087 (t = 4.2)**;
**within a coach, −0.00085 (t = −5.0)**, with a fixed-effects cross-check at p = 1 × 10⁻⁷. The logic
turns on the sign. If the grades were an artefact of the value model under-predicting big clubs, the
*same* coach would have to overperform more after moving to a bigger club, which requires a
*positive* within-coach slope. The observed slope is negative, so the between-coach correlation is
composition: good coaches end up at big clubs, and the effect measured is theirs.

---

## 5. Four nulls

Four attempts to find either a *decomposition* of the coaching number or a *second, independent*
coach effect. All four failed. That consistency is the finding: the coach signal this data can
measure is one number, and the refusal to ship the others is why the one that ships can be trusted.

**Coach × player-type fit.** Big-5 player-seasons described by 38 **style-only** features (no goals,
no ratings, no xG, because the features must describe *how* a player plays and not *how well*),
clustered into 11 archetypes and lagged to the prior season as an endogeneity guard. The **global**
effect is real (p = 0.0062, and p = 0.0003 under a strict sensitivity), with wide-creator share
dominating. The **individual** effect is not: 1,704 within-coach correlations, none surviving FDR,
and shrunken per-coach slopes at p = 0.449. Squad composition matters, and the data cannot show that
*this particular coach* is the one who benefits.

**Style → quality**, the literal question everyone asks. Every raw association is large and
FDR-significant (defensive solidity +0.64, possession +0.52, lineup stability −0.37), and it would
have been the most shareable content the project produced. **All of it is artefact.** Four
pre-specified checks each killed a different group: consistency across specs; separability from club
size (possession correlates **0.86** with mean club-value percentile); outcome restatement (solidity
is built from shots conceded, a step on the causal path to dropping points); and within- versus
between-coach, which **reverses the sign of lineup stability**, the one axis a reader would have
trusted — rotators grade higher between coaches, but within a coach, stability associates with
better seasons, because the between version is club sorting. Only rigidity is unkilled, and only
because it is a career constant on which the decisive check *cannot be run*. A predictor that
survives because it cannot be tested has not survived.

**The Coach Development Effect**, the first genuinely new outcome: does a coach make players more
valuable? Log market-value growth against a baseline of **confounders only**, with player, club and
coach random effects — the player effect is the metric's integrity, since without it a coach handed
rising talent is credited with their trajectory. **It fails repeatability**: even/odd split-half
r = −0.07 and +0.05. The in-sample coach variance looks impressive (18–22%, LRT p < 10⁻⁶⁰) and is
meaningless, because it does not repeat within a career while the player effect dominates at 44–62%.
It measures *which players happened to blow up on a coach's watch*. One by-product survives, a clean
**player**-development residual that ships as a scouting leaderboard and never as a coach ranking.

**The betting market.** Every validation above is internal; the fair sceptical reply is *show me you
beat, or add to, the market*, and a closing line already prices both squad and manager. A
leakage-free walk-forward forecaster on 51,977 matches, pre-registered as confirmatory with a null
declared in advance to be a legitimate result, returns **a clean null on every framing**: worse than
the line (log-loss 1.015 vs 0.979, market better in all 11 leagues), value p = 0.29, **coach BLUP
p = 0.96**, and −6.6% ROI on a flat-stake backtest. Folding a new season in moved every p *further*
from significance, which is what a real null looks like. A near-efficient market pricing our signal
is **external corroboration that the signal is real**, and simultaneously the ceiling on exploiting
it.

**And the leakage story, which a technical reader will get more from than anything else here.** The
first version of that forecaster used each season's **own** squad value rather than the prior
season's. Its incremental coefficient beyond the closing line was **+0.224, p = 1 × 10⁻²¹**, against
the sharpest benchmark in existence. It would have been the headline result, and it is exactly the
kind of number that makes a person stop checking. Swapping in strictly pre-season value, a one-line
change, collapsed it to **+0.023, p = 0.31**. Transfermarkt updates valuations *within* a season, so
a team overperforming in October carries an inflated valuation by January: the apparent edge was
hindsight, laundered through a vendor's update schedule. **Against a near-efficient benchmark, a few
percent of leaked variance is the difference between a spurious 10⁻²¹ and the truth.**

---

## 6. What can be described honestly

Three descriptive layers exist at deliberately different trust levels, and each page shows only what
its layer's label permits. **Where the edge comes from** re-slices the residual into attack and
defence by refitting on goals with the same right-hand side; it makes no new attribution leap, so it
is the one layer stated plainly on coach pages, and it produced the project's best lead: **the coach
effect is substantially stronger on goals than on points** (LRT χ² = 160 offence against 28 for
points). **The style fingerprint** ships carefully labelled, because the caveat became the finding:
club variance beats coach variance on **7 of 9 axes**, so every radar reads *the style of the teams
this coach ran* and the phrase "his style" appears nowhere. **The xG cut** is measured and
deliberately not shipped, since zero coaches clear FDR on any of its four measures, but it carries
the project's strongest integrity check — built entirely from SofaScore against a goals cut built
entirely from Transfermarkt, the two agree at **r = 0.960 and 0.981** over 605 stints.

Two engineering properties carry the rest. **Analysis code cannot make a network call**, so every
figure regenerates offline from the caches, and the refit driver was validated by reproducing the
hand-run results **bit-identically** when pinned to the old season. The bugs worth remembering were
all silent ones: Transfermarkt re-spelling a coach's name behind a stable profile URL and splitting
one career into two ranked rows; arbitrary k-means indices that could permute on a re-cluster and
mislabel every downstream layer with nothing failing anywhere; and a SofaScore field naming the
player's club at scrape time that matches the real match side only 41.5% of the time, which is right
often enough to pass a spot check and wrong often enough to poison an aggregate.

---

## 7. Limitations and conclusion

**Coaching is roughly 5% of the variance** *(bounded)*, and everything downstream inherits that
ceiling. **Most coaches are not individually significant** *(bounded)*. **Value endogeneity**
*(open)*: Transfermarkt values partly reflect past performance, so strong year-1 coaching may raise
the year-2 baseline. **Selection into hiring** *(tested, not eliminated)*: §4.2 rules out the
specific mis-specification story and does not make the data experimental. **Scope** *(bounded)*:
fourteen European leagues, and being principled about the exclusions is exactly what limits
generalisation beyond them. **Single-source dependence** *(open)*: squad values are one vendor's
estimates.

Coaching quality is **real** (p = 2 × 10⁻⁹ and 9 × 10⁻⁶ across the two cuts), **portable** (coach
variance exceeds club variance in both), worth roughly **1.4 points per 38-game season per standard
deviation of grade** on a future holdout and 0.7 on a within-club natural experiment, useful for
**forecasting a hire** (p = 0.0027 over 877 new pairings), corroborated by a design that sweeps out
squad quality entirely (p = 0.0015 over 3,043 manager changes), and confirmed on a season the model
had never seen (p = 0.0024). It is also **a single number**: four independent attempts to decompose
it or find a second coach effect came back empty, and the betting market has already priced it.

Against the pre-declared criterion, the first branch was met, on three independent designs instead
of one, but the **numeric target was missed**: the hope was a 25% reduction and the honest figure is
4.1% coach variance in the 14-league cut and 5.4% in the top-5, against 90–92% residual. A project
that reports the miss against its own written target is worth more than one that reports only the
tests it passed, and the reason the small number is defensible is that it survived §4.1.

**Next, ranked by expected value:** goals as the response in place of points, since the coach effect
is far stronger there and it needs no new data; a matchday-frozen value snapshot, so the market
benchmark can be re-run without the compromise the leakage story exposed; more seasons for the xG
cut, the only null that failed on power rather than substance; and a hiring-decision dataset of
shortlists rather than outcomes, which is the difference between measuring which coaches are good
and measuring which hires were good.
