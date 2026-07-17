// coach.js — coach page: header + grade card, career PPG chart with crest
// points, click-for-stint-detail, sort toggle, player-type fit, summary.

import { loadJSON, getParam, el, clear, showError,
         fmtSeason, fmtPpg, fmtSigned, fmtPoints } from "./data.js";
import { initHeader, coachImg, statTile, seasonSpan, gradeTier } from "./components.js";
import { careerChart, strengthBars, styleBars, spectrumBar } from "./charts.js";

initHeader();
init();

async function init() {
  const id = getParam("id");
  if (!id || !/^\d+$/.test(id)) return showError("No coach id in the URL.");

  let c;
  try {
    c = await loadJSON(`data/coaches/${id}.json`);
  } catch {
    return showError(`No coach with id ${id}.`);
  }

  document.title = `${c.name} — Coach Valuation`;
  const main = document.querySelector("main");
  clear(main);

  main.append(renderHeader(c));
  main.append(el("p", { class: "subtitle" }, c.summary));
  main.append(renderStats(c));
  main.append(renderChartCard(c));
  if (c.strengths) main.append(renderStrengths(c));
  if (c.style) main.append(renderStyle(c));
  if (c.formations) main.append(renderFormations(c));
  main.append(renderFit(c));
}

// Strengths (Layer A, goals cut): the graded overperformance split into an
// attacking and a defensive half. Only present for graded coaches — it
// re-slices the BLUP, so it inherits the grade's certification bar.
function renderStrengths(c) {
  const s = c.strengths;
  const card = el("div", { class: "chart-card" });
  card.append(
    el("div", { class: "chart-title" }, "Where his edge comes from"),
    el("div", { class: "chart-sub" },
      "The same overperformance the grade is built on, split into goals scored " +
      "above what the squad's value predicts and goals conceded below it. " +
      "Positive is better on both rows. " +
      `${s.cut_label} cut · ${s.n_stints} stints · ${s.total_games} games.`));

  card.append(el("p", { class: "strength-lede" }, edgeSentence(c.name, s), " ",
    el("span", { class: "tilt-chip" }, tiltLabel(s.tilt))));

  const note = edgeNote(s, c.rating);
  if (note) card.append(el("p", { class: "strength-lede muted" }, note));

  const host = el("div", {});
  card.append(host);
  strengthBars(host, s);

  const sig = [s.off_significant ? "attacking" : null,
               s.def_significant ? "defensive" : null].filter(Boolean);
  if (sig.length) {
    card.append(el("p", { class: "footnote" },
      `His ${sig.join(" and ")} edge is among the few that stay significant ` +
      "after FDR correction for testing every coach at once."));
  }
  card.append(el("p", { class: "footnote" },
    "This splits a number the project already trusts rather than making a new " +
    "claim — it is the same residual the grade rests on, re-cut by goals. Goal " +
    "difference tracks points closely but not perfectly (r = 0.86 across " +
    "team-seasons), so the split characterises an edge without fully explaining " +
    "it: a coach can grade well on points with little goal-difference edge. " +
    "See the writeup, Part 8."));
  return card;
}

function edgeSentence(name, s) {
  const verb = s.edge >= 0 ? "beat their squad-value expectation by"
                           : "fell short of their squad-value expectation by";
  return `Across ${s.n_stints} stints, ${name}'s teams ${verb} ` +
    `${Math.abs(s.edge).toFixed(2)} goals of goal difference per game — ` +
    `${fmtSigned(s.off)} of it in attack, ${fmtSigned(s.def)} in defence.`;
}

// A coach can grade well on points while having no goal-difference edge at all
// (Simeone is the type case: a B grade on a -0.03 goal edge). Left unsaid, the
// lede reads as a flat contradiction of the grade card above it, so name the
// gap where it happens rather than leaving it to the footnote.
function edgeNote(s, rating) {
  if (!rating || rating.blup == null) return null;
  if ((s.edge >= 0) === (rating.blup >= 0)) return null;
  return rating.blup >= 0
    ? "That runs the other way to his grade, which is built on points: his teams " +
      "converted the goal difference they had into more points than expected. " +
      "This split describes that gap rather than explaining it."
    : "That runs the other way to his grade, which is built on points: his teams " +
      "had the goal difference their squad value predicted but turned less of it " +
      "into points than expected.";
}

// tilt = off - def, in goals per game
function tiltLabel(tilt) {
  if (tilt >= 0.10) return "Attacking tilt";
  if (tilt <= -0.10) return "Defensive tilt";
  return "Balanced";
}

// Style (Layer B): what this coach's teams did. The title and the footnote are
// load-bearing — phase 4 found club identity explains more of the variation
// than the coach on 7 of these 9 axes, so the card may never say "his style".
function renderStyle(c) {
  const st = c.style;
  const card = el("div", { class: "chart-card" });
  card.append(
    el("div", { class: "chart-title" }, "Style of the teams he coached"),
    el("div", { class: "chart-sub" },
      "What his teams actually did on the pitch, as a percentile among the " +
      `${st.n_pool} coaches with big-5 style data ` +
      `(${fmtSeason(st.seasons[0])}–${fmtSeason(st.seasons[1])}). ` +
      `${st.n_stints} stints · ${st.total_games} games.`));

  const host = el("div", {});
  card.append(host);
  styleBars(host, st.axes);

  card.append(el("div", { class: "chart-legend" },
    el("span", { class: "key" },
      el("span", { class: "key-dot" }),
      "the two axes the coach owns more than the club does")));

  card.append(renderPressingHeight(st.pressing_height, st.n_pool));

  card.append(el("p", { class: "footnote" },
    "This is the style of his ", el("em", {}, "teams"), ", not his style in the " +
    "abstract: it is co-produced with the squad he was given. On seven of these " +
    "nine axes the club explains more of the variation than the coach does, and " +
    "the squad's player-type mix alone accounts for 69% of possession. Only " +
    "lineup stability and pressing intensity are more his than the club's. " +
    "Descriptive only — none of these axes predicts coaching quality once club " +
    "size is accounted for. See the writeup, Part 8."));
  return card;
}

// Pressing height — where up the pitch the ball is won back. Its own block
// rather than a footnote line: it is the axis a reader most wants a plain
// answer on, and "98th percentile on pressing height" is not one.
// It sits apart from the nine style axes on purpose — it is measured per
// SEASON (possessionWonAttThird is absent from the per-match data), so unlike
// them it cannot always be pinned to this coach rather than his club.
function renderPressingHeight(h, n) {
  const box = el("div", { class: "ph-block" });
  box.append(
    el("div", { class: "ph-title" }, "Where the ball is won back"),
    el("p", { class: "ph-lede" }, ...heightSentence(h.pct)));

  const host = el("div", {});
  box.append(host);
  spectrumBar(host, {
    pct: h.pct,
    leftLabel: "Deep block",
    rightLabel: "High press",
    // "0th percentile" / "100th percentile" are what a 256-coach midpoint rank
    // rounds to at the ends, and neither is English anyone says
    label: h.pct <= 0 ? `lowest of ${n}`
         : h.pct >= 100 ? `highest of ${n}`
         : undefined,
  });

  box.append(el("p", { class: "footnote", style: "margin-top:2px" },
    h.blended
      ? "Measured per season rather than per match, and most of his seasons shared " +
        "a club with another coach — so this figure is substantially the club's, " +
        "not his."
      : "Measured per season rather than per match."));
  return box;
}

// The percentile is a midpoint rank over 256 coaches, so the extremes really do
// round to 0 and 100 — and "more often than 100% of coaches" (he cannot beat
// himself) and "more often than 0% of coaches" (reads as: never did it at all)
// are both false as English. The tails get their own phrasing.
function heightSentence(pct) {
  const base = "His teams won possession in the attacking third ";
  if (pct >= 98) {
    return [base, el("strong", {}, "more often than almost every coach"),
            " in the data — a high press."];
  }
  if (pct <= 2) {
    return [base, el("strong", {}, "less often than almost every coach"),
            " in the data — a deep block."];
  }
  return [base, "more often than ", el("strong", {}, `${pct}% of coaches`),
          " — ", heightLabel(pct), "."];
}

function heightLabel(pct) {
  if (pct >= 80) return "a high press";
  if (pct >= 60) return "a fairly high line";
  if (pct >= 40) return "a mid-block";
  if (pct >= 20) return "a fairly deep line";
  return "a deep block";
}

// Preferred formations: the coach's recency-weighted formation repertoire
// (SofaScore big-5 data 2015/16–2024/25; only present for coaches in the pool).
function renderFormations(c) {
  const f = c.formations;
  const card = el("div", { class: "chart-card" });
  card.append(
    el("div", { class: "chart-title" }, "Preferred formations"),
    el("div", { class: "chart-sub" },
      "How his matches split across formations, weighted toward recent seasons " +
      "(SofaScore big-5 data, 2015/16–2024/25)."));

  const list = el("div", { class: "sf-forms" });
  const shapes = f.shapes.filter(s => s.pct >= 1);
  (shapes.length ? shapes : f.shapes.slice(0, 1)).forEach(s => {
    list.append(el("div", { class: "sf-form-row" },
      el("span", { class: "sf-form-name" }, s.formation),
      el("span", { class: "sf-form-bar" },
        el("span", { style: `width:${s.pct}%` })),
      el("span", { class: "sf-form-pct muted" }, `${s.pct}%`)));
  });
  card.append(list);
  card.append(el("div", { class: "sf-rigid muted", style: "margin-top:10px" },
    rigidityLabel(f.rigidity)));
  return card;
}

// rigidity in [0,1]: higher = more fixed a shape (cr_rigidity).
function rigidityLabel(r) {
  if (r == null) return "";
  if (r >= 0.66) return "Sticks tightly to his usual shape.";
  if (r >= 0.48) return "Fairly consistent shape across squads.";
  if (r >= 0.32) return "Adapts his shape to the squad.";
  return "Highly flexible — reshapes often.";
}

function renderHeader(c) {
  const photo = coachImg(c.img, c.name, "entity-photo");
  const head = el("div", { class: "entity-header" });

  const career = `${c.career.n_stints} stints · ${c.career.n_clubs} ` +
    `${c.career.n_clubs === 1 ? "club" : "clubs"} · ${c.career.total_games} games · ` +
    seasonSpan(c.career.first_season, c.career.last_season);

  head.append(
    photo,
    el("div", { class: "entity-main" },
      el("h1", {}, c.name),
      el("p", { class: "subtitle", style: "margin-bottom:4px" }, career),
      el("p", { class: "subtitle" }, c.career.leagues.join(" · "))),
    renderGradeCard(c.rating));
  return head;
}

function renderGradeCard(r) {
  if (!r) {
    return el("div", { class: "grade-card" },
      el("div", { class: "grade-letter muted" }, "—"),
      el("div", { class: "grade-detail" },
        el("div", {}, el("strong", {}, "Unranked")),
        el("div", {}, "record too thin to grade"),
        el("div", { class: "muted" }, "(needs ≥3 stints and ≥109 games)")));
  }
  const card = el("div", { class: "grade-card" },
    el("div", { class: "grade-letter" + gradeTier(r.letter_grade) }, r.letter_grade),
    el("div", { class: "grade-detail" },
      el("div", {}, el("span", { class: "cut-label" }, r.cut_label)),
      el("div", {}, el("strong", {}, `${r.numeric_grade.toFixed(1)} / 100`),
        ` · rank ${r.rank} of ${r.n_ranked}`),
      el("div", {}, `BLUP ${fmtSigned(r.blup, 3)} PPG`),
      r.other_cut
        ? el("div", { class: "muted" },
            `${r.other_cut.cut_label}: ${r.other_cut.letter_grade} · ` +
            `rank ${r.other_cut.rank} of ${r.other_cut.n_ranked} · ` +
            `BLUP ${fmtSigned(r.other_cut.blup, 3)}`)
        : null));
  return card;
}

function renderStats(c) {
  const r = c.rating;
  const row = el("div", { class: "stat-row" },
    statTile("Stints", String(c.career.n_stints)),
    statTile("Games", String(c.career.total_games)),
    statTile("Clubs", String(c.career.n_clubs)));
  if (r && r.mean_residual != null) {
    row.append(statTile("Mean residual",
      `${fmtSigned(r.mean_residual)} PPG`,
      r.ci ? `95% CI ${fmtSigned(r.ci[0])} to ${fmtSigned(r.ci[1])}` : null));
    row.append(statTile("Significance",
      r.significant ? "Significant" : "Not significant",
      "after FDR correction"));
  }
  return row;
}

function renderChartCard(c) {
  const card = el("div", { class: "chart-card" });
  card.append(
    el("div", { class: "chart-title" }, "Career points per game"),
    el("div", { class: "chart-sub" },
      "Each crest is one stint — click it for that season's details. " +
      "The dashed line is the squad-value model's expected PPG."));

  const toggle = el("div", { class: "seg-toggle", role: "group" });
  const controls = el("div", { class: "chart-controls" }, toggle);
  const chartHost = el("div", {});
  const detail = el("div", {});
  card.append(controls, chartHost, legend(), detail);

  const chart = careerChart(chartHost, c.stints, {
    mode: "chrono",
    onSelect: s => renderDetail(detail, s, () => chart.clearSelection()),
  });

  const modes = [["chrono", "Chronological"], ["best", "Best → worst"]];
  for (const [key, label] of modes) {
    toggle.append(el("button", {
      type: "button",
      class: key === "chrono" ? "active" : "",
      onclick: e => {
        toggle.querySelectorAll("button").forEach(b => b.classList.remove("active"));
        e.currentTarget.classList.add("active");
        chart.setMode(key);
      },
    }, label));
  }
  return card;
}

function legend() {
  return el("div", { class: "chart-legend" },
    el("span", { class: "key" },
      el("span", { class: "key-line", style: "border-top-color: var(--series-1)" }),
      "actual PPG (crest = club)"),
    el("span", { class: "key" },
      el("span", { class: "key-line dashed", style: "border-top-color: var(--muted)" }),
      "expected PPG (squad-value model)"));
}

function renderDetail(host, s, onClose) {
  clear(host);
  if (!s) return;
  const residPts = s.residual_ppg != null ? s.residual_ppg * s.n_games : null;
  const item = (label, value) => el("div", {},
    el("div", { class: "label" }, label), el("div", {}, value));

  host.append(el("div", { class: "detail-panel" },
    el("button", { class: "dp-close", type: "button", "aria-label": "Close",
      onclick: () => { clear(host); onClose(); } }, "×"),
    el("div", { class: "dp-title" },
      el("a", { href: `team.html?id=${s.team_id}` }, s.team),
      ` · ${fmtSeason(s.season)} · ${s.league_name}`),
    el("div", { class: "detail-grid" },
      item("Games managed", `${s.n_games}` +
        (s.season_share != null && s.season_share < 1
          ? ` (${Math.round(s.season_share * 100)}% of the season)` : "")),
      item("In charge from", s.date_from ?? "—"),
      item("Actual points", `${fmtPoints(s.actual_points)} (${fmtPpg(s.actual_ppg)} PPG)`),
      item("Expected points", `${fmtPoints(s.expected_points)} (${fmtPpg(s.predicted_ppg)} PPG)`),
      item("Residual", el("span",
        { class: s.residual_ppg >= 0 ? "delta-pos" : "delta-neg" },
        `${fmtSigned(s.residual_ppg)} PPG (${fmtSigned(residPts, 1)} pts over the stint)`)))));
}

function renderFit(c) {
  const card = el("div", { class: "chart-card" });
  card.append(el("div", { class: "chart-title" }, "Player-type fit"));

  if (!c.archetype_fit) {
    card.append(el("p", { class: "muted" },
      "N/A — player-type data covers the big-5 leagues 2015/16–2024/25, and this " +
      "coach has fewer than 4 stints there."));
    return card;
  }

  const f = c.archetype_fit;
  if (!f.findings.length) {
    card.append(el("p", {},
      `Tested over ${f.n_stints} big-5 league stints: no player-type ` +
      "pattern recurs across both analysis specifications."));
  } else {
    card.append(el("div", { class: "chart-sub" },
      `Squad archetypes whose share of minutes tracks this coach's over/under-performance ` +
      `(${f.n_stints} big-5 league stints; shown only when the pattern holds in both ` +
      "the standard and strict-lagged specifications)."));
    const list = el("div", { class: "fit-list" });
    for (const x of f.findings) {
      list.append(el("div", { class: "fit-item" },
        el("span", { class: `dir ${x.direction === "+" ? "pos" : "neg"}` },
          x.direction === "+" ? "▲" : "▼"),
        el("span", {},
          x.direction === "+" ? "performs better with more " : "performs worse with more ",
          el("strong", {}, x.label + "s")),
        el("span", { class: "r" }, `r = ${x.r.toFixed(2)} / ${x.r_strict.toFixed(2)} strict`)));
    }
    card.append(list);
  }
  card.append(el("p", { class: "footnote" },
    "Descriptive finding: with 4–10 stints per coach, no individual coach × " +
    "player-type test survives multiple-testing correction. See the writeup, Part 6."));
  return card;
}
