// league.js — league page: season selector, sortable standings, diverging
// residual chart, league statistics block.

import { loadJSON, getParam, el, clear, showError, fmtSeason, fmtPpg,
         fmtSigned, fmtPoints } from "./data.js";
import { initHeader, crestImg, statTile, sortableTable } from "./components.js";
import { divergingBars } from "./charts.js";

initHeader();
init();

async function init() {
  const id = getParam("id");
  if (!id) return showError("No league id in the URL.");

  let L;
  try {
    L = await loadJSON(`data/leagues/${encodeURIComponent(id)}.json`);
  } catch {
    return showError(`No league "${id}".`);
  }

  document.title = `${L.name} — Coach Valuation`;
  const main = document.querySelector("main");
  clear(main);

  const latest = Math.max(...L.seasons);
  let season = latest;

  const headerSub = el("p", { class: "subtitle" });
  main.append(el("h1", {}, L.name), headerSub);

  // controls: season select + sort toggle, one row above the content
  const select = el("select", { "aria-label": "Season" });
  for (const yr of [...L.seasons].sort((a, b) => b - a)) {
    select.append(el("option", { value: yr }, fmtSeason(yr)));
  }
  const toggle = el("div", { class: "seg-toggle", role: "group" });
  main.append(el("div", { class: "chart-controls" },
    el("span", { class: "muted" }, "Season"), select, toggle));

  const tableCard = el("div", { class: "chart-card" });
  const chartCard = el("div", { class: "chart-card" });
  main.append(tableCard, chartCard, renderStats(L));

  let sortMode = "points";
  const sorts = {
    points: { label: "Most points",
      fn: (a, b) => (b.points ?? -1) - (a.points ?? -1) },
    over: { label: "Most overperforming",
      fn: (a, b) => (b.residual_points ?? -999) - (a.residual_points ?? -999) },
  };
  for (const [key, s] of Object.entries(sorts)) {
    toggle.append(el("button", {
      type: "button", class: key === sortMode ? "active" : "",
      onclick: e => {
        sortMode = key;
        toggle.querySelectorAll("button").forEach(b => b.classList.remove("active"));
        e.currentTarget.classList.add("active");
        renderSeason();
      },
    }, s.label));
  }

  select.addEventListener("change", () => {
    season = Number(select.value);
    renderSeason();
  });

  function renderSeason() {
    headerSub.textContent =
      `${fmtSeason(season)}${season === latest ? " — latest available season" : ""}` +
      ` · actual vs squad-value-expected points`;

    const rows = L.standings[String(season)] ?? [];
    renderStandings(tableCard, rows, sorts[sortMode]);
    renderChart(chartCard, rows, season);
  }

  renderSeason();
}

function renderStandings(card, rows, sort) {
  clear(card);
  card.append(el("div", { class: "chart-title" }, "Standings"));

  const sorted = [...rows].sort(sort.fn);
  const anyNote = rows.some(r => r.residual_note);

  const table = el("table", { class: "data" },
    el("thead", {}, el("tr", {},
      el("th", {}, "#"),
      el("th", {}, "Team"),
      el("th", {}, "Coaches"),
      el("th", { class: "num" }, "Games"),
      el("th", { class: "num" }, "Points"),
      el("th", { class: "num" }, "Expected"),
      el("th", { class: "num" }, "Deserved"),
      el("th", { class: "num" }, "± vs expected"),
      el("th", { class: "num" }, "PPG"))),
    el("tbody", {}, sorted.map((r, i) => el("tr", {},
      el("td", { class: "num muted" }, String(i + 1)),
      el("td", {}, el("a", { class: "cell-entity", href: `team.html?id=${r.team_id}` },
        crestImg(r.crest, r.team),
        r.team, r.is_b_team ? el("span", { class: "grade-chip" }, "B") : null)),
      el("td", {}, coachCell(r.coaches)),
      el("td", { class: "num" }, String(r.games)),
      el("td", { class: "num" }, el("strong", {}, fmtPoints(r.points))),
      el("td", { class: "num" }, r.residual_note
        ? el("span", { class: "muted", title: r.residual_note }, "—*")
        : fmtPoints(r.expected_points)),
      el("td", { class: "num" }, r.expected_rank == null
        ? el("span", { class: "muted" }, "—")
        : el("span", { title: `Deserved ${ordinal(r.expected_rank)}, finished ${ordinal(r.actual_rank)}` },
            ordinal(r.expected_rank),
            r.pos_delta ? el("span", {
              class: (r.pos_delta > 0 ? "delta-pos" : "delta-neg"),
              style: "margin-left:6px; font-size:0.85em",
            }, fmtSigned(r.pos_delta, 0)) : null)),
      el("td", { class: "num" }, r.residual_points == null
        ? el("span", { class: "muted" }, "—")
        : el("span", { class: r.residual_points >= 0 ? "delta-pos" : "delta-neg" },
            fmtSigned(r.residual_points, 1))),
      el("td", { class: "num" }, fmtPpg(r.ppg))))));

  card.append(el("div", { class: "table-wrap" }, table));
  if (anyNote) {
    card.append(el("p", { class: "footnote" },
      "* no expectation computed — insufficient market value data for that squad."));
  }
}

function ordinal(n) {
  const s = ["th", "st", "nd", "rd"], v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

function coachCell(coaches) {
  if (!coaches || !coaches.length) {
    return el("span", { class: "muted" }, "—");
  }
  const parts = [];
  coaches.forEach((c, i) => {
    if (i) parts.push(", ");
    parts.push(el("a", { href: `coach.html?id=${c.id}` }, c.name));
    if (coaches.length > 1) parts.push(el("span", { class: "muted" }, ` (${c.games})`));
  });
  return el("span", {}, parts);
}

function renderChart(card, rows, season) {
  clear(card);
  card.append(
    el("div", { class: "chart-title" }, `Over/under-performance, ${fmtSeason(season)}`),
    el("div", { class: "chart-sub" },
      "Points above (blue) or below (red) what squad value predicted. Click a bar for the team page."));
  const host = el("div", {});
  card.append(host);
  divergingBars(host, rows);
}

function renderStats(L) {
  const wrap = el("div", {});
  wrap.append(el("h2", {}, "League statistics"));
  // R² and RMSE describe the fit, so they are computed on the fitted seasons
  // only — the hint names that window, which is one season shorter than the
  // team-season count beside it.
  const fitWin = L.stats.fit_seasons;
  wrap.append(el("div", { class: "stat-row" },
    statTile("Team-seasons", String(L.stats.n_team_seasons)),
    statTile("Model R²", L.stats.r2?.toFixed(2) ?? "—",
      `squad value → points · ${fitWin}`),
    statTile("Model RMSE", L.stats.rmse?.toFixed(2) ?? "—", `PPG · ${fitWin}`)));

  const lists = el("div", { style:
    "display:grid; grid-template-columns:repeat(auto-fit,minmax(260px,1fr)); gap:16px" });

  lists.append(
    perfList("All-time overperformers", L.stats.top_overperformers),
    perfList("All-time underperformers", L.stats.top_underperformers),
    coachList("Most games coached", L.stats.top_coaches));
  wrap.append(lists);
  wrap.append(el("p", { class: "footnote" },
    "Extreme entries from pre-2010 seasons in smaller leagues can reflect " +
    "sparse Transfermarkt market-value coverage rather than genuine " +
    "over/under-performance — see ",
    el("a", { href: "writeup.html#what-the-model-does-not-do" }, "how it works"), "."));
  return wrap;
}

function perfList(title, items) {
  const card = el("div", { class: "card" }, el("h3", { style: "margin-top:0" }, title));
  for (const x of items) {
    card.append(el("div", { style: "display:flex; gap:8px; padding:3px 0" },
      el("a", { href: `team.html?id=${x.team_id}`, style: "flex:1" },
        `${x.team} ${fmtSeason(x.season)}`),
      el("span", { class: x.residual_points >= 0 ? "delta-pos" : "delta-neg" },
        `${fmtSigned(x.residual_points, 1)} pts`)));
  }
  return card;
}

function coachList(title, items) {
  const card = el("div", { class: "card" }, el("h3", { style: "margin-top:0" }, title));
  for (const x of items) {
    card.append(el("div", { style: "display:flex; gap:8px; padding:3px 0" },
      el("a", { href: `coach.html?id=${x.id}`, style: "flex:1" }, x.name),
      el("span", { class: "muted" }, `${x.games} games · ${x.stints} stints`)));
  }
  return card;
}
