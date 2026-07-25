// validation.js — "Does the model work?" report card. Presents the two new
// positive validations (2025/26 forward test + manager-change natural experiment)
// plus the recommender payoff, honestly labelled.

import { loadJSON, el, clear, showError, fmtSeason, fmtSigned } from "./data.js";
import { initHeader, statTile } from "./components.js";
import { expectedVsActual, gradeVsOutcome } from "./charts.js";

initHeader();
init();

function pfmt(p) {
  if (p == null) return "—";
  return p < 0.001 ? p.toExponential(1).replace("e", " × 10^") : `p = ${p.toFixed(p < 0.01 ? 4 : 3)}`;
}
function leagueName(slug) {
  return slug.split("-").map(w => w[0].toUpperCase() + w.slice(1)).join(" ")
    .replace("Laliga2", "LaLiga 2").replace("Laliga", "LaLiga").replace("1 Hnl", "HNL");
}

async function init() {
  let V;
  try {
    V = await loadJSON("data/validation.json");
  } catch {
    return showError("Validation data not available. Run the site export.");
  }
  document.title = "Does the model work? — Coach Valuation";
  const main = document.querySelector("main");
  clear(main);
  const F = V.forward, E = V.event;

  main.append(
    el("h1", {}, "Does the model actually work?"),
    el("p", { class: "subtitle" },
      "Three independent tests of the coaching grade — real hires, a natural experiment, and a future season"));

  main.append(el("div", { class: "card" },
    el("p", { style: "margin:0" },
      "Every coach here carries one number: how much his teams beat what their squad was " +
      "worth. Any model can explain the past — the number earns trust only by predicting " +
      "things it was never shown. These three tests do that, each closing a different hole.")));

  main.append(el("h2", {}, "Three concordant validations"));
  main.append(el("p", { class: "subtitle", style: "margin-top:-4px" },
    "Three different designs, on purpose: a forecasting test spread across many clubs, a " +
    "before-and-after inside a single club, and a season that had not been played yet."));
  main.append(renderValidations(V));
  main.append(el("p", { class: "footnote", style: "margin-top:0" },
    "“p” is the chance of a result this strong if the grade carried no information at all — " +
    "below 0.05 is the conventional bar. Effects are points over a 38-game season for a coach " +
    "one standard deviation above average: a real but modest edge next to squad value."));

  // ---- forward test detail (test 3 above) ----
  // Two charts, because test 3 asks two questions in sequence: did the squad-value
  // model survive an unseen year (Q1), and did the grades built on top of it predict
  // that year (Q2)? A p-value states the answers; these show them.
  main.append(el("h2", {}, `Inside test 3: the ${F.season} season`));
  main.append(el("div", { class: "card" },
    el("p", { style: "margin:0" },
      "Two things had to hold for the future test to mean anything. First the " +
      "squad-value model underneath the grades had to survive a year it had never " +
      "seen — a model that no longer worked would make the grades meaningless. Then " +
      "the coaches it had already rated had to go on and beat their squads. Both did, " +
      "and each is a picture rather than a claim.")));

  if (F.scatter && F.scatter.length) {
    const c1 = el("div", { class: "chart-card" },
      el("div", { class: "chart-title" },
        `Every club in ${F.season}, against what the frozen model expected`),
      el("div", { class: "chart-sub" },
        `One dot per club — ${F.n_team_seasons} of them across 14 leagues, none of which ` +
        "existed as data when the model was built. The diagonal is a flawless forecast; " +
        "how far a club sits above or below it is exactly the over- or under-performance " +
        "the coach grades are made of."));
    const host1 = el("div");
    c1.append(host1);
    c1.append(el("p", { class: "footnote", style: "margin:8px 0 0" },
      `The cloud tracks the line at R² ${F.enh_r2.toFixed(2)} — the model misses by ` +
      `${F.mean_pts_err} points per club over a whole season, no worse than it did on the ` +
      "seasons it was trained on. Points per game rather than total points because these " +
      "leagues play between 22 and 46 games."));
    main.append(c1);
    expectedVsActual(host1, F.scatter);
  }

  // The chart's own footnote carries R² and the average miss, so the tiles keep
  // only the fact it cannot show: this is the minutes-weighted model, and the
  // margin it holds over raw squad value survived the new year too.
  main.append(el("div", { class: "stat-row" },
    statTile("Still beats raw squad value", `+${F.rmse_edge.toFixed(3)} PPG`,
      "the same margin it showed on the original cross-validation")));

  if (F.q2 && F.q2.length) {
    const fit = F.q2_fit;
    const c2 = el("div", { class: "chart-card", style: "margin-top:16px" },
      el("div", { class: "chart-title" },
        "Grade going in, against what actually happened"),
      el("div", { class: "chart-sub" },
        `The other half of the test, and the whole of it in one frame. Each dot is a ` +
        `${F.season} spell taken by a coach who already had a grade (${fit.n} of ` +
        `${F.n_stints}): where he stood on the model's estimate of him beforehand, ` +
        "against how far his team went on to beat what its squad was worth. Nothing " +
        "about the new season went into the grades."));
    const host2 = el("div");
    c2.append(host2);
    // The scatter is deliberately unflattering: the relationship is real but small,
    // and saying so here is what keeps the trend line from overselling it.
    c2.append(el("p", { class: "footnote", style: "margin:8px 0 0" },
      "The cloud is wide — one part-season is a noisy measure of a coach, so single dots " +
      `mean little and the correlation is only ${fit.r.toFixed(2)}. The claim is the ` +
      `tilt: the line rises across the range (${pfmt(fit.p)}), and the three group ` +
      "averages, each about thirty times more precise than any dot in it, rise with it. " +
      "Coaches with no prior record are not plotted; they are in the headline test, " +
      `scored at the model's average, which is where its ${pfmt(F.q2_p)} comes from.`));
    main.append(c2);
    gradeVsOutcome(host2, F.q2, fit, F.bins);
  }

  // ---- event study detail (test 2 above) ----
  main.append(el("h2", {}, "Inside test 2: what the manager changes also show"));
  main.append(el("div", { class: "card" },
    el("p", { style: "margin:0" },
      `The same ${E.n_changes.toLocaleString()} changes grade the sackings themselves. Clubs ` +
      "sack on results; the model sees results minus what the squad was worth — so it can ask " +
      `how often the sacked man was actually doing well with a weak squad. Of the ` +
      `${E.n_midseason.toLocaleString()} mid-season sackings, that is what happened in ` +
      `${E.pct_harsh}% of them, and those are the ones that backfire.`)));

  main.append(el("h3", {}, "Sacking efficiency — and the cost of a panic sacking"));
  main.append(el("div", { class: "stat-row" },
    statTile("Harsh sackings", `${E.pct_harsh}%`,
      "of mid-season sackings fired a coach who was overperforming his squad"),
    statTile("After a harsh sacking", `${fmtSigned(E.backfire_harsh, 2)} PPG`,
      `the replacement improved only ${E.improve_harsh}% of the time`),
    statTile("After a fair sacking", `${fmtSigned(E.backfire_defensible, 2)} PPG`,
      `the replacement improved ${E.improve_defensible}% of the time`)));

  const hc = el("div", { class: "chart-card" },
    el("div", { class: "chart-title" }, "The model's catalogue of regret"),
    el("div", { class: "chart-sub" },
      "Mid-season sackings of an overperforming coach whose replacement then did worse — " +
      "surfaced from the residual alone."));
  const table = el("table", { class: "data" },
    el("thead", {}, el("tr", {},
      el("th", {}, "Season"), el("th", {}, "Club"),
      el("th", {}, "Sacked"), el("th", { class: "num" }, "was"),
      el("th", {}, "Hired"), el("th", { class: "num" }, "became"),
      el("th", { class: "num" }, "Swing"))),
    el("tbody", {}, E.harsh_examples.map(x => el("tr", {},
      el("td", { class: "muted" }, fmtSeason(x.season)),
      el("td", {}, el("strong", {}, x.club),
        el("span", { class: "muted" }, ` · ${leagueName(x.league)}`)),
      el("td", {}, x.sacked),
      el("td", { class: "num delta-pos" }, fmtSigned(x.resid_out, 2)),
      el("td", {}, x.hired),
      el("td", { class: "num delta-neg" }, fmtSigned(x.resid_in, 2)),
      el("td", { class: "num delta-neg" }, fmtSigned(x.swing, 2))))));
  hc.append(el("div", { class: "table-wrap" }, table));
  main.append(hc);

  main.append(el("p", { class: "footnote" },
    "“Was / became” are performance above squad-value expectation (PPG). A harsh sacking is " +
    "one where the outgoing coach was above expectation; the backfire is largely regression " +
    "to the mean acting against the club, not proof the sacked coach was elite. One " +
    "part-season is a noisy sample, so read the pattern rather than any single row."));
}

// The three validations. A bare p-value communicates nothing and a wall of prose
// goes unread, so each card gets: the design named in the eyebrow, the question,
// a short paragraph of what the test actually DOES, the result in points, a
// one-clause caveat (on the card, never demoted to a footnote), and the takeaway.
// Tests 1 and 2 are the pair a reader will conflate — both are about hiring — so
// test 2's description opens by naming the difference: test 1 pools appointments
// across hundreds of clubs, test 2 holds one club fixed across a single swap.
function renderValidations(V) {
  const P = V.payoff, E = V.event, F = V.forward;
  const cards = [];

  if (P) {
    cards.push(valCard({
      n: 1,
      kind: "Out-of-sample forecast",
      title: "Forecasting hires it had never seen",
      question: "Does knowing a coach's grade make the forecast of a new appointment more accurate?",
      does: `Take ${P.n_pairings} real appointments where the coach had not been at that ` +
        "club the season before, and forecast each one twice: from squad value alone, then " +
        "from squad value plus the coach's grade. Every forecast comes from a model refit " +
        "with that season removed, so the appointment being judged was never in its " +
        "training data. The test is whether the second forecast lands closer to what " +
        "actually happened.",
      headline: `Forecast error fell ${P.rmse0.toFixed(3)} → ${P.rmse1.toFixed(3)} PPG, ` +
        `better in ${P.folds_improved} of ${P.n_folds} seasons`,
      p: P.p,
      caveat: "Against realized squad value; the stricter pre-hire framing is weaker (p = 0.052).",
      means: "Grades are worth consulting at the moment of hiring, not just in hindsight.",
    }));
  }

  cards.push(valCard({
    n: 2,
    kind: "Natural experiment",
    title: "The same club, before and after",
    question: "When a club swaps managers, does the incoming coach's grade predict what changes?",
    does: "Where test 1 pools appointments across hundreds of different clubs, this one " +
      `holds a single club fixed. Across ${E.n_changes.toLocaleString()} manager changes ` +
      `at ${E.n_clubs} clubs (${E.first_season}–${E.last_season}), it compares how far the ` +
      "team beat its squad-value expectation under the outgoing coach with how far it beat " +
      "it under the incoming one — same club, same league, much the same squad. Each grade " +
      "is frozen as of the outgoing coach's final season, so it cannot contain either spell.",
    headline: `${fmtSigned(E.pts_per_sd, 1)} points a season per standard deviation of grade`,
    p: E.level_p,
    caveat: `Strongest for mid-season crisis hires (${pfmt(E.mid_p)}); the gap between the ` +
      "incoming and outgoing grades predicts nothing.",
    means: "The effect follows the coach rather than the squad — and matters most when a club hires in a panic.",
  }));

  cards.push(valCard({
    n: 3,
    kind: "Future holdout",
    title: "A season that had not been played",
    question: "Do grades built on the past predict the future?",
    does: "The model was frozen at the end of 2024 — the squad-value formula and every " +
      `coach's grade — before ${F.season} had been played. That season was then scraped ` +
      `after the fact and predicted cold: ${F.n_team_seasons} team-seasons and ` +
      `${F.n_stints} coach stints it knew nothing about. The test is whether the coaches ` +
      "it had already rated highly went on to beat their squad's expectation.",
    headline: `${fmtSigned(F.pts_per_sd, 1)} points a season per standard deviation of grade`,
    p: F.q2_p,
    caveat: `Adding the grade cut forecast error ${F.rmse_noaug.toFixed(3)} → ` +
      `${F.rmse_aug.toFixed(3)} PPG. One season — the test is re-run every year.`,
    means: "The grades carry genuine forward-looking information, with no hindsight of any kind.",
  }));

  const grid = el("div", { class: "val-grid" }, ...cards);
  const why = el("div", { class: "card" },
    el("h3", { style: "margin-top:0" }, "Why it takes three"),
    el("p", { style: "margin:0" },
      "Alone, each has a hole: the first compares coaches across different clubs, the " +
      "second is fitted on history, the third is a single season. Each is vulnerable to " +
      "something the other two are not, and all three agree."));
  return el("div", {}, grid, why);
}

function valCard(c) {
  const row = (label, ...content) => el("div", { class: "val-row" },
    el("span", { class: "val-label" }, label), ...content);
  return el("div", { class: "val-card" },
    el("div", { class: "val-eyebrow" }, `Test ${c.n}`,
      el("span", { class: "val-kind" }, c.kind)),
    el("h3", {}, c.title),
    el("p", { class: "val-q" }, c.question),
    row("What the test does", c.does),
    row("Result",
      el("div", { class: "val-headline" }, c.headline,
        el("span", { class: "val-p" }, pfmt(c.p))),
      c.caveat ? el("p", { class: "val-caveat", style: "margin:4px 0 0" }, c.caveat) : null),
    el("div", { class: "val-row val-rules" },
      el("span", { class: "val-label" }, "What this means"),
      c.means, " ",
      el("a", { href: "writeup.html#does-it-work" }, "How this test works →")));
}

