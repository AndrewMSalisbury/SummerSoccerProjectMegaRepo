// coach.js — coach page: header + grade card, career PPG chart with crest
// points, click-for-stint-detail, sort toggle, player-type fit, summary.

import { loadJSON, getParam, el, clear, showError,
         fmtSeason, fmtPpg, fmtSigned, fmtPoints } from "./data.js";
import { initHeader, coachImg, statTile, seasonSpan } from "./components.js";
import { careerChart } from "./charts.js";

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
  main.append(renderFit(c));
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
        el("div", {}, "insufficient data for a grade"),
        el("div", { class: "muted" }, "(needs ≥3 stints and ≥10 games)")));
  }
  const card = el("div", { class: "grade-card" },
    el("div", { class: "grade-letter" }, r.letter_grade),
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
      "N/A — player-type data currently covers Premier League 2015/16–2024/25 only."));
    return card;
  }

  const f = c.archetype_fit;
  if (!f.findings.length) {
    card.append(el("p", {},
      `Tested over ${f.n_stints_pl} Premier League stints: no player-type ` +
      "pattern recurs across both analysis specifications."));
  } else {
    card.append(el("div", { class: "chart-sub" },
      `Squad archetypes whose share of minutes tracks this coach's over/under-performance ` +
      `(${f.n_stints_pl} Premier League stints; shown only when the pattern holds in both ` +
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
    "Descriptive finding: with 4–9 stints per coach, no individual coach × " +
    "player-type test survives multiple-testing correction. See the writeup, Part 6."));
  return card;
}
